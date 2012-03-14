/+
 + device/keyboard.d
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

module device.keyboard;

import device.base;
import memory;
import device.pushbutton;

const int KEY_BKSP   = 65288;  // Backspace (DELETE)
const int KEY_TAB    = 65289;  // Tab
const int KEY_RETURN = 65293;  // Enter
const int KEY_ESCAPE = 65307;  // ESC
const int KEY_LEFT   = 65361;  // left arrow
const int KEY_UP     = 65362;  // up arrow
const int KEY_RIGHT  = 65363;  // right arrow
const int KEY_DOWN   = 65364;  // down arrow
const int KEY_LSHIFT = 65505;  // left shift
const int KEY_RSHIFT = 65506;  // right sight
const int KEY_LOS    = 65515;  // left "windows" (open apple)
const int KEY_ROS    = 65516;  // right "windows" (closed apple)

const int KEY_LOWER_MIN = 97;
const int KEY_LOWER_MAX = 122;
const int KEY_UPPER_MIN = 65;
const int KEY_UPPER_MAX = 90;

// !"#$%&'()*+,-./0123456789:;<=>?@
const int KEY_SYMBOL_MIN = 32;
const int KEY_SYMBOL_MAX = 64;
const int KEY_SYMBOL2_MAX = 126;

const int KEY_BRACKETRIGHT = 93;
const int KEY_CIRCUM       = 94;

import std.stdio;

class Keyboard
{
    bool keyStrobe;
    bool anyKeyDown;
    ubyte latch;
    bool[int] keysDown;
    Pushbuttons buttons;

    class RingBuffer
    {
        int[] values;
        int nextRead, nextWrite;

        this(int len)
        {
            values.length = len;
            clear();
        }

        void clear()
        {
            nextRead = nextWrite = 0;
        }

        bool canRead()
        {
            return (nextRead != nextWrite);
        }

        int read()
        {
            // assert(canRead()); XXX
            int val = values[nextRead];
            nextRead = (nextRead + 1) % values.length;
            return val;
        }

        void write(int val)
        {
            int next = (nextWrite + 1) % values.length;
            if (next != nextRead)
            {
                values[nextWrite] = val;
                nextWrite = next;
            }
            else
            {
                // XXX Need to clean up press buffer
                // else emulator misbehaves
                writefln("Press buffer full");
            }
        }
    }

    RingBuffer presses, releases;

    this()
    {
        // XXX constants
        presses = new RingBuffer(20);
        releases = new RingBuffer(10);
    }

    void reboot()
    {
        latch = 0;
        keyStrobe = anyKeyDown = false;
        keysDown = keysDown.init;
        presses.clear();
        releases.clear();
    }

    abstract int appleASCII(int keyval, bool ctrl);
    abstract bool handleSpecialKey(int keyval, bool keyDown);

    bool handlePress(int keyval, bool ctrl, int keycode)
    {
        int ascii = appleASCII(keyval, ctrl);
        if (ascii < 0)
        {
            if (handleSpecialKey(keyval, true)) return true;
            return false;
        }
        recordKeyPress(ascii, keycode);
        return true;
    }

    bool handleRelease(int keyval, bool ctrl, int keycode)
    {
        int ascii = appleASCII(keyval, ctrl);
        if (ascii < 0)
        {
            if (handleSpecialKey(keyval, false)) return true;
            return false;
        }
        recordKeyRelease(keycode);
        return true;
    }

    void processPresses()
    {
        if (!presses.canRead()) return;
        
        anyKeyDown = true;
        keyStrobe = true;

        // assert latch < 0x80; XXX
        latch = presses.read();
        keysDown[presses.read()] = true;
    }

    void processReleases()
    {
        if (!releases.canRead()) return;

        int code = releases.read();
        if (code in keysDown) {
            keysDown.remove(code);
            if (keysDown.length == 0)
            {
                anyKeyDown = false;
            }
        }
    }

    void recordKeyPress(int ascii, int code)
    {
        presses.write(ascii);
        presses.write(code);
    }

    void recordKeyRelease(int code)
    {
        releases.write(code);
    }

    ubyte delegate() onReadLatch;
    void delegate() onClearStrobe;

    ubyte readLatch()
    {
        if (onReadLatch !is null)
        {
            keyStrobe = true;
            return onReadLatch() | 0x80;
        }

        if (keyStrobe)
        {
            return latch | 0x80;
        }
        else
        {
            return latch;
        }
    }

    ubyte peekLatch()
    {
        return latch;
    }

    void clearKeystrobe()
    {
        if (keyStrobe)
        {
            keyStrobe = false;
            if (onClearStrobe !is null)
                onClearStrobe();
        }
    }

    mixin(AbstractInitSwitches());
}

class Keyboard_II : Keyboard
{
    int appleASCII(int keyval, bool ctrl)
    {
        int ascii = -1;
        if (keyval > 65000)
        {
            switch (keyval)
            {
                case KEY_RETURN:
                    ascii = 0x0D;
                    break;
                case KEY_ESCAPE:
                    ascii = 0x1B;
                    break;
                case KEY_LEFT:
                    ascii = 0x08;
                    break;
                case KEY_RIGHT:
                    ascii = 0x15;
                    break;
                default:
                    break;
            }
        }
        else
        {
            if (keyval >= KEY_SYMBOL_MIN)
            {
                if (keyval < KEY_SYMBOL_MAX)
                {
                    ascii = keyval;
                }
                else if (keyval == KEY_SYMBOL_MAX)
                {
                    if (ctrl)
                        ascii = 0;
                    else
                        ascii = keyval;
                }
                else if (keyval >= KEY_UPPER_MIN)
                {
                    if (keyval <= KEY_UPPER_MAX)
                    {
                        if (ctrl)
                            ascii = keyval - KEY_UPPER_MIN + 1;
                        else
                            ascii = keyval;
                    }
                    else if (keyval == KEY_BRACKETRIGHT ||
                            keyval == KEY_CIRCUM)
                    {
                        ascii = keyval;
                    }
                    else if (keyval >= KEY_LOWER_MIN)
                    {
                        if (keyval <= KEY_LOWER_MAX)
                        {
                            if (ctrl)
                                ascii = keyval - KEY_LOWER_MIN + 1;
                            // XXX
                            // else if lowercase-mod
                            else
                                ascii = keyval - 32;
                        }
                    }
                }
            }
        }
        return ascii;
    }

    bool handleSpecialKey(int keyval, bool keyDown)
    {
        // XXX check for shift key mod
        return false;
    }

    mixin(InitSwitches("", [
        mixin(MakeSwitch(
        [0xC000, 0xC001, 0xC002, 0xC003, 0xC004, 0xC005, 0xC006, 0xC007,
         0xC008, 0xC009, 0xC00A, 0xC00B, 0xC00C, 0xC00D, 0xC00E, 0xC00F],
         "R", "readLatch")),
        mixin(MakeSwitch(
        [0xC010, 0xC011, 0xC012, 0xC013, 0xC014, 0xC015, 0xC016, 0xC017,
         0xC018, 0xC019, 0xC01A, 0xC01B, 0xC01C, 0xC01D, 0xC01E, 0xC01F],
         "R0W", "clearKeystrobe"))
    ]));
}

class Keyboard_IIe : Keyboard
{
    int appleASCII(int keyval, bool ctrl)
    {
        int ascii = -1;
        if (keyval > 65000)
        {
            switch (keyval)
            {
                case KEY_RETURN:
                    ascii = 0x0D;
                    break;
                case KEY_ESCAPE:
                    ascii = 0x1B;
                    break;
                case KEY_LEFT:
                    ascii = 0x08;
                    break;
                case KEY_RIGHT:
                    ascii = 0x15;
                    break;
                case KEY_UP:
                    ascii = 0x0B;
                    break;
                case KEY_DOWN:
                    ascii = 0x0A;
                    break;
                case KEY_BKSP:
                    ascii = 0x7F;
                    break;
                case KEY_TAB:
                    ascii = 0x09;
                    break;
                default:
                    break;
            }
        }
        else if ((keyval >= KEY_SYMBOL_MIN) && (keyval <= KEY_SYMBOL2_MAX))
        {
            if (ctrl)
            {
                if ((keyval >= KEY_UPPER_MIN) && (keyval <= KEY_UPPER_MAX))
                    ascii = keyval - KEY_UPPER_MIN + 1;
                else if ((keyval >= KEY_LOWER_MIN) &&
                        (keyval <= KEY_LOWER_MAX))
                    ascii = keyval - KEY_LOWER_MIN + 1;
                else
                    ascii = keyval;
            }
            else
            {
                ascii = keyval;
            }
        }
        return ascii;
    }

    bool handleSpecialKey(int keyval, bool keyDown)
    {
        if (keyval == KEY_LOS)
        {
            buttons.update(0, keyDown);
            return true;
        }
        else if (keyval == KEY_ROS)
        {
            buttons.update(1, keyDown);
            return true;
        }
        return false;
    }

    ubyte readAKD()
    {
        clearKeystrobe();
        return latch | (anyKeyDown ? 0x80 : 0x00);
    }

    mixin(InitSwitches("", [
        mixin(MakeSwitch(
        [0xC000, 0xC001, 0xC002, 0xC003, 0xC004, 0xC005, 0xC006, 0xC007,
         0xC008, 0xC009, 0xC00A, 0xC00B, 0xC00C, 0xC00D, 0xC00E, 0xC00F],
         "R", "readLatch")),
        mixin(MakeSwitch([0xC010], "R", "readAKD")),
        mixin(MakeSwitch(
        [0xC010, 0xC011, 0xC012, 0xC013, 0xC014, 0xC015, 0xC016, 0xC017,
         0xC018, 0xC019, 0xC01A, 0xC01B, 0xC01C, 0xC01D, 0xC01E, 0xC01F],
         "W", "clearKeystrobe"))
    ]));
}

