/+
 + video/base.d
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

module video.base;

import memory;

enum Mode
{
    TEXT,
    LORES,
    HIRES
}

class ScannerBase
{
    abstract ubyte* getData(uint vidClock);
    abstract ubyte* getData(uint line, uint col);
    abstract ubyte* getData80(uint vidClock);
    abstract ubyte* getData80(uint line, uint col);
    abstract bool shouldUpdate();
    abstract uint currentLine();
    abstract uint currentCol();
    abstract Mode getMode();
    abstract bool checkColorBurst();
    abstract ubyte floatingBus(ushort addr);
    abstract void page2SwitchOn();
    abstract void page2SwitchOff();
    abstract void hiresSwitchOn();
    abstract void hiresSwitchOff();
}

class PatternGenerator
{
    ScannerBase scanner;
    abstract void initPatterns();
    abstract void initPatterns(ubyte[] rom);
    abstract void update(ubyte* signal, int scanLine, int startCol,
            uint len);
    abstract void update80(ubyte* signal, int scanLine, int startCol,
            uint len);
}

class SignalBase
{
    abstract void update();
    abstract void update(Mode mode, bool col80, bool colorBurst,
            int startLine, int stopLine, int startCol, int stopCol);
    abstract void dHGRChange(bool newdHGR);
}

class Screen
{
    ushort* data;
    int width, height;
    ScannerBase scanner;

    bool isColor;

    abstract void draw(bool col80, bool colorBurst, ubyte* bitmap,
            int scanLine, int scanStart, int scanEnd);
}

struct VideoPages
{
    DataMem lores1;
    DataMem lores2;
    DataMem hires1;
    DataMem hires2;

    void reboot()
    {
        lores1.reboot();
        lores2.reboot();
        hires1.reboot();
        hires2.reboot();
    }
}

