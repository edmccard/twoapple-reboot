/+
 + system/io.d
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

module system.io;

import memory;
import timer;

import ui.inputevents;
import ui.sound;

import device.annunciator;
import device.pushbutton;
import device.speaker;
import device.keyboard;
import device.paddle;

class IO
{
    Annunciator annun;
    Paddles paddles;
    Pushbuttons buttons;
    Speaker spkr;
    Keyboard kbd;

    this(SoftSwitchPage switches, Timer timer, Timer.Cycle deviceCycle)
    {
        makeSpeaker(switches, timer, deviceCycle);
        makeButtons(switches);
        makeKeyboard(switches);
        makePaddles(switches, timer);
        makeAnnunciators(switches);
    }

    void makeSpeaker(SoftSwitchPage switches, Timer timer,
            Timer.Cycle deviceCycle)
    {
        if (soundCard.isActive)
        {
            spkr = new Speaker();
            spkr.initSwitches(switches);
            // XXX reference to SoundCardYes is bad?
            spkr.setTiming(timer.hertz, SoundCardYes.sampleFreq, deviceCycle);
            soundCard.installSpeaker(spkr);
        }
    }

    void makeButtons(SoftSwitchPage switches)
    {
        buttons = new Pushbuttons();
        buttons.initSwitches(switches);
        input.installButtons(buttons);
    }

    void makeKeyboard(SoftSwitchPage switches)
    {
        kbd = newKeyboard();
        kbd.initSwitches(switches);
        kbd.buttons = buttons;
        input.installKeyboard(kbd);
    }

    void makePaddles(SoftSwitchPage switches, Timer timer)
    {
        paddles = newPaddles();
        paddles.initSwitches(switches);
        paddles.timer = timer;
        input.installPaddles(paddles);
    }

    void makeAnnunciators(SoftSwitchPage switches)
    {
        annun = newAnnunciators();
        annun.initSwitches(switches);
    }

    void reboot()
    {
        annun.reboot();
        buttons.reboot();
        kbd.reboot();
        paddles.reboot();
    }

    abstract Keyboard newKeyboard();
    abstract Annunciator newAnnunciators();
    abstract Paddles newPaddles();
}

class IO_II : IO
{
    this(SoftSwitchPage switches, Timer timer, Timer.Cycle deviceCycle)
    {
        super(switches, timer, deviceCycle);
    }

    Keyboard newKeyboard()
    {
        return new Keyboard_II();
    }

    Annunciator newAnnunciators()
    {
        return new Annunciator_II();
    }

    Paddles newPaddles()
    {
        return new Paddles_II();
    }
}

class IO_IIe : IO
{
    this(SoftSwitchPage switches, Timer timer, Timer.Cycle deviceCycle)
    {
        super(switches, timer, deviceCycle);
    }

    Keyboard newKeyboard()
    {
        return new Keyboard_IIe();
    }

    Annunciator newAnnunciators()
    {
        // NOTE: C058-C05F are handled by IOU
        return new Annunciator();
    }

    Paddles newPaddles()
    {
        // XXX if unenhanced:
        //return new Paddles_II();
        // XXX else:
        return new Paddles();
    }
}

