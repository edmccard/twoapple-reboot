/+
 + device/annunciator.d
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

module device.annunciator;

import device.base;
import memory;

class Annunciator
{
    bool[4] ann;

    void reboot()
    {
        ann[0..4] = false;
    }

    void activate(int index)
    {
        if (!ann[index])
        {
            ann[index] = true;
        }
    }

    void deactivate(int index)
    {
        if (ann[index])
        {
            ann[index] = false;
        }
    }

    void ann_0_On()
    {
        activate(0);
    }

    void ann_1_On()
    {
        activate(1);
    }

    void ann_2_On()
    {
        activate(2);
    }

    void ann_3_On()
    {
        activate(3);
    }

    void ann_0_Off()
    {
        deactivate(0);
    }

    void ann_1_Off()
    {
        deactivate(1);
    }

    void ann_2_Off()
    {
        deactivate(2);
    }

    void ann_3_Off()
    {
        deactivate(3);
    }

    mixin(EmptyInitSwitches());
}

class Annunciator_II : Annunciator
{
    mixin(InitSwitches("super", [
        mixin(MakeSwitch([0xC058], "R0W", "ann_0_Off")),
        mixin(MakeSwitch([0xC059], "R0W", "ann_0_On")),
        mixin(MakeSwitch([0xC05A], "R0W", "ann_1_Off")),
        mixin(MakeSwitch([0xC05B], "R0W", "ann_1_On")),
        mixin(MakeSwitch([0xC05C], "R0W", "ann_2_Off")),
        mixin(MakeSwitch([0xC05D], "R0W", "ann_2_On")),
        mixin(MakeSwitch([0xC05E], "R0W", "ann_3_Off")),
        mixin(MakeSwitch([0xC05F], "R0W", "ann_3_On"))
    ]));
}

// NOTE: IIe uses Annunciator (the switches are handled by the IOU)
// NOTE: IIc has no annunciators
