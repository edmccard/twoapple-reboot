/+
 + device/paddle.d
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

module device.paddle;

import device.base;
import timer;
import memory;

class Paddles
{
    Timer timer;

    int numPaddles;
    int[4] onTrigger;
    bool[4] stillTiming;
    ubyte[4] switchVal;

    this()
    {
        numPaddles = 4;
    }

    void reboot()
    {
        onTrigger[0..4] = 1380;    // XXX only if no real joystick ??
        stillTiming[0..4] = false;
        switchVal[0..4] = 0;
    }

    // XXX II: C07X | IIe Orig: C07X | IIe Enh: C070-C07E
    // (IOU gets C07F)
    // IIc: as IIe Enh, plus VBLINT?

    mixin(InitSwitches("", [
        mixin(MakeSwitch(
            [0xC070, 0xC071, 0xC072, 0xC073, 0xC074, 0xC075, 0xC076, 0xC077,
             0xC078, 0xC079, 0xC07A, 0xC07B, 0xC07C, 0xC07D, 0xC07E],
                                           "R0W", "trigger")),
        mixin(MakeSwitch([0xC064, 0xC06C], "R7", "check_pdl_0")),
        mixin(MakeSwitch([0xC065, 0xC06D], "R7", "check_pdl_1")),
        mixin(MakeSwitch([0xC066, 0xC06E], "R7", "check_pdl_2")),
        mixin(MakeSwitch([0xC067, 0xC06F], "R7", "check_pdl_3"))
    ]));

    void update(int pdl, int value)
    {
        onTrigger[pdl] = value ? value : 1;
    }

    ubyte check_pdl_0()
    {
        return switchVal[0];
    }

    ubyte check_pdl_1()
    {
        return switchVal[1];
    }
    ubyte check_pdl_2()
    {
        return switchVal[2];
    }
    ubyte check_pdl_3()
    {
        return switchVal[3];
    }

    void trigger()
    {
        for (int i = 0; i < numPaddles; ++i)
        {
            if (stillTiming[i]) return;
        }
        for (int i = 0; i < numPaddles; ++i)
        {
            if (onTrigger[i] == 0) onTrigger[i] = 1;
            switchVal[i] = 0x80;
        }
        timer.new Counter(onTrigger[0], &pdl_0_expired);
        timer.new Counter(onTrigger[1], &pdl_1_expired);
        if (numPaddles > 2)
        {
            timer.new Counter(onTrigger[2], &pdl_2_expired);
            timer.new Counter(onTrigger[3], &pdl_3_expired);
        }
    }

    bool pdl_0_expired()
    {
        stillTiming[0] = false;
        switchVal[0] = 0x00;
        return false;
    }

    bool pdl_1_expired()
    {
        stillTiming[1] = false;
        switchVal[1] = 0x00;
        return false;
    }

    bool pdl_2_expired()
    {
        stillTiming[2] = false;
        switchVal[2] = 0x00;
        return false;
    }

    bool pdl_3_expired()
    {
        stillTiming[3] = false;
        switchVal[3] = 0x00;
        return false;
    }
}

// NOTE: IIe Unenhanced uses Paddles_II; IIe enhanced uses Paddles
//       (because C07F is handled first by IOU)

class Paddles_II : Paddles
{
    mixin(InitSwitches("super", [
        mixin(MakeSwitch([0xC07F], "R0W", "trigger"))
    ]));
}

// XXX IIc: 0xC07X resets VBLINT along with triggering timers,
//          C07E/C07F as IIe enhanced, maybe more? (and there
//          are only two paddles, so no C066/C067/C06E/C06F)

class Paddles_IIc : Paddles
{
    // XXX add the switches
    mixin(EmptyInitSwitches());

    this()
    {
        super();
        numPaddles = 2;
    }
}
