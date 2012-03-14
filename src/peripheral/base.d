/+
 + peripheral/base.d
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

module peripheral.base;

import memory;
import device.base;
import timer;

import gtk.Box;
import gtk.VBox;

VBox peripheralStatus;

class Peripheral
{
    Box statusBox;

    ubyte[] ioSelectROM;
    ubyte[] ioStrobeROM;

    void plugIn(int slotNum, SoftSwitchPage switches, Timer timer)
    {
       initSwitches(switches, slotNum);
       initTimer(timer);

       if (statusBox !is null)
       {
           peripheralStatus.packStart(statusBox, false, false, 0);
       }
    }

    void reset() {}
    void reboot() {}
    void updateStatus() {}
    void initTimer(Timer timer) {}

    mixin(EmptyInitSwitches());
}

