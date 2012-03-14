/+
 + device/pushbutton.d
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

module device.pushbutton;

import device.base;
import memory;

class Pushbuttons
{
    bool buttons[3];

    void reboot()
    {
        buttons[0..3] = false;
    }

    void update(int btn, bool isDown)
    {
        buttons[btn] = isDown;
    }

    ubyte read(int btn)
    {
        return (buttons[btn] ? 0x80 : 0);
    }

    ubyte readPB0()
    {
        return read(0);
    }

    ubyte readPB1()
    {
        return read(1);
    }

    ubyte readPB2()
    {
        return read(2);
    }

    mixin(InitSwitches("", [
        mixin(MakeSwitch([0xC061, 0xC069], "R7", "readPB0")),
        mixin(MakeSwitch([0xC062, 0xC06A], "R7", "readPB1")),
        mixin(MakeSwitch([0xC063, 0xC06B], "R7", "readPB2"))
    ]));
}
