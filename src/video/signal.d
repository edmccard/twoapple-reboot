/+
 + video/signal.d
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
import video.patterns;
import device.base;
import memory;
import timer;

class Signal : SignalBase
{
    ubyte[560 * 192] bitmap;
    int nextLine, nextCol;
    bool col80Switch, dHGR;

    Screen screen;
    ScannerBase scanner;
    ubyte delegate() kbdLatch;

    PatternGenerator loresPattern, hiresPattern;
    TextPatternGenerator textPattern;

    void init(Timer timer, ubyte[] rom)
    {
        assert(textPattern !is null);

        textPattern.signal = this;
        textPattern.scanner = scanner;
        textPattern.init(timer);
        textPattern.initPatterns(rom);
        loresPattern = new LoresPatternGenerator();
        hiresPattern = new HiresPatternGenerator();
        loresPattern.scanner = scanner;
        hiresPattern.scanner = scanner;
    }

    void reboot()
    {
        textPattern.reboot();
    }

    void update()
    {
        if (!scanner.shouldUpdate()) return;

        int stopLine = scanner.currentLine();
        int stopCol = scanner.currentCol();

        Mode mode = scanner.getMode();
        bool col80 =
            ((mode == Mode.TEXT) ? col80Switch : (col80Switch && dHGR));
        bool colorBurst = scanner.checkColorBurst();

        if (nextLine < 192)
        {
            update(mode, col80, colorBurst, nextLine, nextCol, stopLine,
                    stopCol);
        }

        if (stopCol == 64)
        {
            nextLine = (stopLine + 1) % 262;   // XXX PAL: 312
            nextCol = 25;
        }
        else
        {
            nextLine = stopLine;
            nextCol = stopCol + 1;
        }
    }

    void update(Mode mode, bool col80, bool colorBurst, int startLine,
            int startCol, int stopLine, int stopCol)
    {
        PatternGenerator pattern;
        switch (mode)
        {
            case Mode.TEXT:
                pattern = textPattern;
                break;
            case Mode.LORES:
                pattern = loresPattern;
                break;
            case Mode.HIRES:
                pattern = hiresPattern;
                break;
        }

        int lastLine = (stopLine < 192) ? stopLine : 191;
        int scanStart = (startCol < 25) ? 0 : startCol - 25;
        int scanEnd = 39;
        ubyte* bitmapPtr;

        for (int scanLine = startLine; scanLine <= lastLine; ++scanLine)
        {
            if (scanLine == stopLine)
            {
                if (stopCol < 25) break;
                scanEnd = stopCol - 25;
            }

            bitmapPtr = bitmap.ptr + ((scanLine * 80) + (scanStart * 2));

            if (col80)
                pattern.update80(bitmapPtr, scanLine, scanStart,
                        (scanEnd - scanStart) + 1);
            else
                pattern.update(bitmapPtr, scanLine, scanStart, 
                        (scanEnd - scanStart) + 1);

            screen.draw(col80, colorBurst,
                    scanStart == 0 ? bitmapPtr: bitmapPtr - 1,
                    scanLine, scanStart, scanEnd);

            scanStart = 0;
        }
    }

    void col80SwitchChange(bool newCol80Switch)
    {
        if (col80Switch == newCol80Switch) return;
        update();
        col80Switch = newCol80Switch;
    }

    void dHGRChange(bool newdHGR)
    {
        if (dHGR == newdHGR) return;
        update();
        dHGR = newdHGR;
    }

    void initSwitches(SoftSwitchPage switches, int slot = -1)
    {
        textPattern.initSwitches(switches, slot);
    }
}

class Signal_II : Signal
{
    void init(Timer timer, ubyte[] rom)
    {
        textPattern = new TextPatternGenerator_II();
        super.init(timer, rom);
        loresPattern.initPatterns();
        hiresPattern.initPatterns();
    }
}

class Signal_IIe : Signal
{
    void init(Timer timer, ubyte[] rom)
    {
        textPattern = new TextPatternGenerator_IIe();
        textPattern.kbdLatch = kbdLatch;
        super.init(timer, rom);
        loresPattern.initPatterns(rom);
        hiresPattern.initPatterns(rom);
    }

    void reboot()
    {
        super.reboot();
        col80SwitchChange(false);
    }

    void col80SwitchOff()
    {
        col80SwitchChange(false);
    }

    void col80SwitchOn()
    {
        col80SwitchChange(true);
    }

    ubyte readCol80Switch()
    {
        return kbdLatch() | (col80Switch ? 0x80 : 0x00);
    }

    mixin(InitSwitches("super", [
        mixin(MakeSwitch([0xC00C], "W", "col80SwitchOff")),
        mixin(MakeSwitch([0xC00D], "W", "col80SwitchOn")),
        mixin(MakeSwitch([0xC01F], "R", "readCol80Switch"))
    ]));
}

