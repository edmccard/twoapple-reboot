/+
 + video/scanner.d
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

import video.base;
import video.offsets;
import memory;
import timer;
import device.base;

class Scanner : ScannerBase
{
    uint page;
    bool graphicsTime, textSwitch, mixedSwitch, hiresSwitch, oldTextSwitch;
    Mode mode;

    Timer.Cycle vidCycle;
    uint frameSkip, frameCount;

    DataMem[2][3] displayMem;
    DataMem[2][3] auxDisplayMem;

    SignalBase signal;
    ubyte delegate() kbdLatch;
    bool delegate() drawFrame;

    void init(Timer timer)
    {
        int frameLen = 262 * 65;    // XXX PAL: 312 * 65
        vidCycle = timer.startCycle(frameLen);
        graphicsTime = true;
        
        timer.new Counter(frameLen, &graphicsTimeOn);
        timer.new DelayedCounter(frameLen, &frameComplete, frameLen - 1);
        timer.new DelayedCounter(frameLen, &graphicsTimeOff, 160 * 65);
        timer.new DelayedCounter(frameLen, &graphicsTimeOn, 192 * 65);
        timer.new DelayedCounter(frameLen, &graphicsTimeOff, 224 * 65);
    }

    void forceFrame()
    {
    }

    void reboot()
    {
        page2SwitchOff();
        hiresSwitchOff();
        mixedSwitchOff();
        textSwitchOn();
    }

    void installMemory(DataMem loresPage1, DataMem loresPage2,
            DataMem hiresPage1, DataMem hiresPage2)
    {
        displayMem[Mode.TEXT][0] = loresPage1;
        displayMem[Mode.TEXT][1] = loresPage2;
        displayMem[Mode.LORES][0] = loresPage1;
        displayMem[Mode.LORES][1] = loresPage2;
        displayMem[Mode.HIRES][0] = hiresPage1;
        displayMem[Mode.HIRES][1] = hiresPage2;
    }

    void installAuxMemory(DataMem loresPage1, DataMem loresPage2,
            DataMem hiresPage1, DataMem hiresPage2)
    {
        auxDisplayMem[Mode.TEXT][0] = loresPage1;
        auxDisplayMem[Mode.TEXT][1] = loresPage2;
        auxDisplayMem[Mode.LORES][0] = loresPage1;
        auxDisplayMem[Mode.LORES][1] = loresPage2;
        auxDisplayMem[Mode.HIRES][0] = hiresPage1;
        auxDisplayMem[Mode.HIRES][1] = hiresPage2;
    }

    bool graphicsTimeOn()
    {
        changeMode({graphicsTime = true;});
        return true;
    }

    bool graphicsTimeOff()
    {
        changeMode({graphicsTime = false;});
        return true;
    }

    bool frameComplete()
    {
        signal.update();
        if (shouldUpdate()) drawFrame();
        frameCount = ((frameCount + 1) % (frameSkip + 1));
        return true;
    }

    bool shouldUpdate()
    {
        return ((frameCount % (frameSkip + 1)) == 0);
    }

    void changeMode(void delegate() change)
    {
        oldTextSwitch = textSwitch;
        change();
        Mode newMode = changedMode();
        if (newMode != mode)
        {
            signal.update();
        }
        mode = newMode;
        oldTextSwitch = textSwitch;
    }

    Mode changedMode()
    {
        if (textSwitch) return Mode.TEXT;
        if (mixedSwitch && !graphicsTime) return Mode.TEXT;

        if (hiresSwitch) return Mode.HIRES;
        else return Mode.LORES;
    }

    void textSwitchOff()
    {
        changeMode({textSwitch = false;});
    }

    void textSwitchOn()
    {
        changeMode({textSwitch = true;});
    }

    void mixedSwitchOff()
    {
        changeMode({mixedSwitch = false;});
    }

    void mixedSwitchOn()
    {
        changeMode({mixedSwitch = true;});
    }

    void hiresSwitchOff()
    {
        changeMode({hiresSwitch = false;});
    }

    void hiresSwitchOn()
    {
        changeMode({hiresSwitch = true;});
    }

    void page2SwitchOff()
    {
        if (page == 1)
        {
            signal.update();
            page = 0;
        }
    }

    void page2SwitchOn()
    {
        if (page == 0)
        {
            signal.update();
            page = 1;
        }
    }

    Mode getMode()
    {
        return mode;
    }

    bool checkColorBurst()
    {
        return !oldTextSwitch;
        /+ TODO: For "pretty" mixed mode, return (mode != Mode.TEXT) +/
    }

    uint currentLine()
    {
        return vidCycle.currentVal() / 65;
    }

    uint currentCol()
    {
        return vidCycle.currentVal() % 65;
    }

    ubyte* getData(uint vidClock)
    {
        return displayMem[mode][page].data + scanOffset(vidClock, mode);
    }

    ubyte* getData(uint line, uint col)
    {
        return displayMem[mode][page].data + scanOffset(line, col, mode);
    }

    ubyte* getData80(uint vidClock)
    {
        return auxDisplayMem[mode][page].data + scanOffset(vidClock, mode);
    }

    ubyte* getData80(uint line, uint col)
    {
        return auxDisplayMem[mode][page].data + scanOffset(line, col, mode);
    }

    mixin(InitSwitches("", [
        mixin(MakeSwitch([0xC050], "R0W", "textSwitchOff")),
        mixin(MakeSwitch([0xC051], "R0W", "textSwitchOn")),
        mixin(MakeSwitch([0xC052], "R0W", "mixedSwitchOff")),
        mixin(MakeSwitch([0xC053], "R0W", "mixedSwitchOn"))
    ]));
}

class Scanner_II : Scanner
{
    import memory: AddressDecoder;

    AddressDecoder decoder;

    ubyte floatingBus(ushort addr)
    {
        uint clock = vidCycle.currentVal();
        if (((clock % 65) < 25) && (mode != Mode.HIRES))
            return decoder.read(0x1400 + (page * 0x400) +
                    scanOffset(clock, mode));
        else
            return displayMem[mode][page].data[scanOffset(clock, mode)];
    }

    mixin(InitSwitches("super", [
        mixin(MakeSwitch([0xC054], "R0W", "page2SwitchOff")),
        mixin(MakeSwitch([0xC055], "R0W", "page2SwitchOn")),
        mixin(MakeSwitch([0xC056], "R0W", "hiresSwitchOff")),
        mixin(MakeSwitch([0xC057], "R0W", "hiresSwitchOn"))
    ]));
}

class Scanner_IIe : Scanner
{
    ubyte floatingBus(ushort addr)
    {
        return displayMem[mode][page].data[scanOffset(vidCycle.currentVal(),
                mode)];
        // equivalent to getData()[0];
    }

    ubyte readText()
    {
        return kbdLatch() | (textSwitch ? 0x80 : 0x00);
    }

    ubyte readMixed()
    {
        return kbdLatch() | (mixedSwitch ? 0x80 : 0x00);
    }

    bool readVBL()
    {
        return (vidCycle.currentVal() >= (192 * 65));
    }

    ubyte readLowVBL()
    {
        return kbdLatch() | ((!readVBL()) ? 0x80 : 0x00);
    }

    mixin(InitSwitches("super", [
        mixin(MakeSwitch([0xC019], "R", "readLowVBL")),
        mixin(MakeSwitch([0xC01A], "R", "readText")),
        mixin(MakeSwitch([0xC01B], "R", "readMixed"))
    ]));
}

