/+
 + ui/inputvents.d
 +
 + Copyright: 2007 Gerald Stocker
 +
 + This file is part of Twoapple.
 +
 + Twoapple is free software; you can redistribute it and/or modify
 + it under the terms of the GNU General Public License as published by
 + the Free Software Foundation; either version 2 of the License, or
 + (at your option) any later version.
 +
 + Twoapple is distributed in the hope that it will be useful,
 + but WITHOUT ANY WARRANTY; without even the implied warranty of
 + MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 + GNU General Public License for more details.
 +
 + You should have received a copy of the GNU General Public License
 + along with Twoapple; if not, write to the Free Software
 + Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 +/

module ui.inputevents;

import std.stdio;

import gtkglc.glgdktypes;
import gtk.Widget;
import gtkc.gtktypes;
import gtk.Image;
import gtk.ToggleToolButton;
import gtk.GtkD;
import gtk.Timeout;

import derelict.sdl.sdl;

import device.keyboard;
import device.paddle;
import device.pushbutton;

import ui.textinput;

static import host;

static this()
{
    if (host.SDL)
    {
        if (SDL_InitSubSystem(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK) == -1)
        {
            writefln("%s", std.string.toString(SDL_GetError()));
            return;
        }

        int numJoysticks = SDL_NumJoysticks();
        if (numJoysticks == 0) return;

        joysticks.length = numJoysticks;
        SDL_JoystickEventState(SDL_ENABLE);

        SDL_Joystick* device;
        for (int i = 0; i < numJoysticks; ++i)
        {
            device = SDL_JoystickOpen(i);
            if (device is null)
            {
                writefln("%s", std.string.toString(SDL_GetError()));
                continue;
            }
            writefln("Joystick %s: %s", i,
                    std.string.toString(SDL_JoystickName(i)));

            joysticks[i] = new Joystick(device,
                    SDL_JoystickNumAxes(device),
                    SDL_JoystickNumButtons(device));
        }
        if (device is null)
            joysticks.length = 0;
    }
}

Input input;

private:

Joystick[] joysticks;

class Joystick
{
    bool isActive;

    int deviceNum;
    SDL_Joystick* device;

    int[] pdlForAxis;
    int[] pbForButton;

    this(SDL_Joystick* dev, int numAxes, int numButtons)
    {
        device = dev;
        pdlForAxis.length = numAxes;
        pbForButton.length = numButtons;
        for (int i = 0; i < numAxes; ++i)
            pdlForAxis[i] = -1;
        for (int i = 0; i < numButtons; ++i)
            pbForButton[i] = -1;
    }
}

class Input
{
    SDL_Event sEvent;
    Timeout timeout;

    Keyboard kbd;
    Pushbuttons buttons;
    Paddles paddles;
    TextInput textIn;
    ToggleToolButton pauseButton;
    void delegate() onReset;

    this()
    {
        pauseButton = new ToggleToolButton("gtk-media-pause");
        // XXX read from config / allow changing
        for (int i = 0; i < joysticks.length; ++i)
        {
            // By default, ignore all but the first two joysticks
            if (i > 1) break;

            joysticks[i].pdlForAxis[0] = i * 2;
            joysticks[i].pdlForAxis[1] = i * 2 + 1;
            joysticks[i].pbForButton[0] = i * 2;
            joysticks[i].pbForButton[1] = 1;

            // XXX hackish way of setting "pause" button
            if (joysticks[i].pbForButton.length > 2)
                joysticks[i].pbForButton[length - 1] = -2;
        }
    }

    void installButtons(Pushbuttons btns)
    {
        buttons = btns;
    }

    void installKeyboard(Keyboard keyboard)
    {
        kbd = keyboard;
    }

    void installPaddles(Paddles pdl)
    {
        paddles = pdl;
    }

    gboolean onKeyPress(GdkEventKey* evt, Widget w)
    {
        static const int KEY_PAUSE  = 65299;    // Pause/Break
        static const int KEY_ESCAPE = 65307;

        // Let someone else handle ALT-<x> presses
        if ((evt.state & GdkModifierType.MOD1_MASK) != 0) return false;

        if (textIn !is null)
        {
            if (evt.keyval == KEY_ESCAPE)
            {
                stopTextInput();
                return true;
            }
            else
                return false;
        }

        if (evt.keyval == KEY_PAUSE)
        {
            pauseButton.setActive(!(pauseButton.getActive()));
            return true;
        }

        if (pauseButton.getActive()) return false;

        bool ctrl = ((evt.state & GdkModifierType.CONTROL_MASK) != 0);
        return kbd.handlePress(evt.keyval, ctrl, evt.hardwareKeycode);
    }

    gboolean onKeyRelease(GdkEventKey* evt, Widget w)
    {
        static const int KEY_RESET  = 65481;  // F12

        // Let someone else handle ALT-<x> releases
        if ((evt.state & GdkModifierType.MOD1_MASK) != 0) return false;

        if (evt.keyval == KEY_RESET)
        {
            onReset();
            if (pauseButton.getActive())
            {
                pauseButton.setActive(false);
            }
            return true;
        }

        if (pauseButton.getActive()) return false;

        bool ctrl = ((evt.state & GdkModifierType.CONTROL_MASK) != 0);
        return kbd.handleRelease(evt.keyval, ctrl, evt.hardwareKeycode);
    }

    void onJoystickEvent()
    {
        static const float scale = 65535.0 / 2760.0;
        static const int shift = 32768;
        bool buttonDown = false;
        switch(sEvent.type)
        {
            case SDL_JOYAXISMOTION:
                Joystick joy = joysticks[sEvent.jaxis.which];
                int axis = sEvent.jaxis.axis;
                int pdl = joy.pdlForAxis[axis];
                if (pdl != -1)
                {
                    int value =
                        cast(int)(((sEvent.jaxis.value) + shift) / scale);
                    paddles.update(pdl, value);
                }
                break;
            case SDL_JOYBUTTONDOWN:
                buttonDown = true;
            case SDL_JOYBUTTONUP:
                Joystick joy = joysticks[sEvent.jbutton.which];
                int pb = joy.pbForButton[sEvent.jbutton.button];
                if ((pb == -2) && buttonDown)
                    pauseButton.setActive(!pauseButton.getActive());
                else if (pb >= 0)
                {
                    buttons.update(pb, buttonDown);
                }
                break;
            default:
                break;
        }
    }

    void startTextInput(string filename)
    {
        textIn = new TextInput(filename, &stopTextInput);
        kbd.onReadLatch = &textIn.read;
        kbd.onClearStrobe = &textIn.advancePos;
    }

    void stopTextInput()
    {
        kbd.onReadLatch = null;
        kbd.onClearStrobe = null;
        delete textIn;
    }

    void processEvents()
    {
        kbd.processPresses();
        kbd.processReleases();

        while(GtkD.eventsPending())
        {
            GtkD.mainIteration();
        }
        processJoystickEvents();
    }

    bool processJoystickEvents()
    {
        while (SDL_PollEvent(&sEvent))
        {
            onJoystickEvent();
        }
        return true;
    }
}

