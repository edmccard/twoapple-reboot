/+
 + video/patterns.d
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
import device.base;
import memory;
import timer;

static this()
{
    initDoubleBits();
    initReverseBits();
}

private:

ubyte[2][128] doubleBits;
ubyte[128] reverseBits;

void initDoubleBits()
{
    for (int bits = 0; bits < 128; ++bits)
    {
        for (int newBit = 13; newBit >= 0; --newBit)
        {
            int index = 1 - (newBit / 7);
            doubleBits[bits][index] <<= 1;
            if (bits & (1 << (newBit / 2)))
                doubleBits[bits][index] |= 1;
        }
    }
}

void initReverseBits()
{
    for (int bits = 0; bits < 128; ++bits)
    {
        for (int bitPos = 0; bitPos < 7 ; ++bitPos)
        {
            reverseBits[bits] <<= 1;
            if ((bits & (1 << bitPos)) != 0)
                reverseBits[bits] |= 1;
        }
    }
}

final ubyte INVERSE = 0b01111111;

public:

class TextPatternGenerator : PatternGenerator
{
    ubyte[2][8][256] flashOffPatterns;
    ubyte[2][8][256] flashOnPatterns;
    ubyte[2][8][256] flashNullPatterns;
    ubyte[8][256] flashOffPatterns80;
    ubyte[8][256] flashOnPatterns80;
    ubyte[8][256] flashNullPatterns80;

    ubyte[2][8][256]* patterns;
    ubyte[8][256]* patterns80;

    bool flash, altCharset;

    SignalBase signal;
    ScannerBase scanner;
    ubyte delegate() kbdLatch;

    this()
    {
        patterns = &flashOffPatterns;
        patterns80 = &flashOffPatterns80;
    }

    bool toggleFlash()
    {
        flash = !flash;
        if (!altCharset)
        {
            if (scanner.getMode() == Mode.TEXT)
            {
                signal.update();
            }
            applyFlash();
        }
        return true;
    }

    void altCharsetChange(bool newState)
    {
        if (altCharset == newState) return;
        if (scanner.getMode() == Mode.TEXT)
        {
            signal.update();
        }
        altCharset = newState;
        if (newState)
        {
            patterns = &flashNullPatterns;
            patterns80 = &flashNullPatterns80;
        }
        else applyFlash();
    }

    void applyFlash()
    {
        patterns = (flash ? &flashOnPatterns : &flashOffPatterns);
        patterns80 = (flash ? &flashOnPatterns80 : &flashOffPatterns80);
    }

    void update(ubyte* signal, int scanLine, int startCol, uint len)
    {
        uint screenPos = 0;
        uint dotLine = scanLine % 8;
        uint memByte;
        ubyte* data = scanner.getData(scanLine, startCol + 25);

        for (uint offset = 0; offset < len; ++offset)
        {
            memByte = data[offset];
            signal[screenPos++] = (*patterns)[memByte][dotLine][0];
            signal[screenPos++] = (*patterns)[memByte][dotLine][1];
        }
    }

    void update80(ubyte* signal, int scanLine, int startCol, uint len)
    {
        uint screenPos = 0;
        uint dotLine = scanLine % 8;
        ubyte* data = scanner.getData(scanLine, startCol + 25);
        ubyte* auxData = scanner.getData80(scanLine, startCol + 25);

        for (uint offset = 0; offset < len; ++offset)
        {
            signal[screenPos++] = (*patterns80)[auxData[offset]][dotLine];
            signal[screenPos++] = (*patterns80)[data[offset]][dotLine];
        }
    }

    void reboot()
    {
        altCharsetChange(false);
    }

    mixin(EmptyInitSwitches());

    abstract void init(Timer timer);
}

class TextPatternGenerator_II : TextPatternGenerator
{
    mixin("static final ubyte[256] charsetUpper_II = "
            ~ import("charset_upper_ii"));
    mixin("static final ubyte[256] charsetSymbol_II = "
            ~ import("charset_symbol_ii"));
    
    void initPatterns()
    {
        ubyte[][] segments = new ubyte[][8];
        segments[0] = segments[2] = segments[4] = segments[6] =
            charsetUpper_II;
        segments[1] = segments[3] = segments[5] = segments[7] =
            charsetSymbol_II;

        ubyte flashOff, flashOn;
        for (int seg = 0; seg < 8; ++seg)
        {
            foreach(index, pattern; segments[seg])
            {
                uint ascii = (((index / 32) * 4) + (index % 4)) + (seg * 32);
                uint dotLine = (index / 4) % 8;
                switch (seg)
                {
                    case 0, 1:
                        flashOff = flashOn = (pattern ^ INVERSE);
                        break;
                    case 2, 3:
                        flashOff = pattern;
                        flashOn = (pattern ^ INVERSE);
                        break;
                    default:
                        flashOff = flashOn = pattern;
                        break;
                }
                flashOffPatterns[ascii][dotLine][0] = doubleBits[flashOff][0];
                flashOffPatterns[ascii][dotLine][1] = doubleBits[flashOff][1];
                flashOnPatterns[ascii][dotLine][0] = doubleBits[flashOn][0];
                flashOnPatterns[ascii][dotLine][1] = doubleBits[flashOn][1];
            }
        }
    }

    void initPatterns(ubyte[] rom)
    {
        /+ TODO: Initialize patterns from character generator rom +/
        if (rom is null) initPatterns();
        else initPatterns();
    }

    // XXX XXX INIT
    void init(Timer timer)
    {
        timer.new Counter(timer.hertz / 2, &toggleFlash);
    }
}

class TextPatternGenerator_IIe : TextPatternGenerator
{
    mixin("static final ubyte[256] charsetUpper_IIe = "
            ~ import("charset_upper_iie"));
    mixin("static final ubyte[256] charsetSymbol_IIe = "
            ~ import("charset_symbol_iie"));
    mixin("static final ubyte[256] charsetLower = "
            ~ import("charset_lower"));
    mixin("static final ubyte[256] charsetMouse = "
            ~ import("charset_mouse"));

    void initPatterns()
    {
        ubyte[][] segments = new ubyte[][8];
        segments[0] = segments[4] = segments[6] = charsetUpper_IIe;
        segments[1] = segments[5] = charsetSymbol_IIe;
        segments[2] = charsetMouse; // unenhanced: charsetUpper
        segments[3] = segments[7] = charsetLower;

        ubyte flashNull;
        for (int seg = 0; seg < 8; ++seg)
        {
            foreach(index, pattern; segments[seg])
            {
                uint ascii = (((index / 32) * 4) + (index % 4)) + (seg * 32);
                uint dotLine = (index / 4) % 8;
                switch (seg)
                {
                    case 0, 1, 3:
                        flashNull = pattern ^ INVERSE;
                        break;
                    case 2:
                        flashNull = pattern; // unenhanced: pattern ^ INVERSE
                        break;
                    default:
                        flashNull = pattern;
                        break;
                }
                flashNullPatterns[ascii][dotLine][0] =
                    doubleBits[flashNull][0];
                flashNullPatterns[ascii][dotLine][1] =
                    doubleBits[flashNull][1];
                flashNullPatterns80[ascii][dotLine] = flashNull;
            }
        }

        ubyte flashOn, flashOff;
        for (uint ascii = 0; ascii < 256; ++ascii)
        {
            for (uint dotLine = 0; dotLine < 8; ++dotLine)
            {
                if ((ascii >= 64) && (ascii < 128))
                {
                    flashOn = flashNullPatterns80[ascii - 64][dotLine];
                    flashOff = flashNullPatterns80[ascii + 64][dotLine];
                }
                else
                {
                    flashOn = flashOff = flashNullPatterns80[ascii][dotLine];
                }
                flashOffPatterns[ascii][dotLine][0] = doubleBits[flashOff][0];
                flashOffPatterns[ascii][dotLine][1] = doubleBits[flashOff][1];
                flashOffPatterns80[ascii][dotLine] = flashOff;
                flashOnPatterns[ascii][dotLine][0] = doubleBits[flashOn][0];
                flashOnPatterns[ascii][dotLine][1] = doubleBits[flashOn][1];
                flashOnPatterns80[ascii][dotLine] = flashOn;
            }
        }
    }

    void initPatterns(ubyte[] rom)
    {
        /+ TODO: Initialize patterns from character generator rom +/
        if (rom is null) initPatterns();
        else initPatterns();
    }

    // XXX XXX INIT
    void init(Timer timer)
    {
        timer.new Counter(32 * 262 * 65, &toggleFlash); // XXX PAL
    }

    void altCharsetOn()
    {
        altCharsetChange(true);
    }

    void altCharsetOff()
    {
        altCharsetChange(false);
    }

    ubyte readAltCharset()
    {
        return kbdLatch() | (altCharset ? 0x80 : 0x00);
    }

    // XXX XXX INIT
    mixin(InitSwitches("", [
        mixin(MakeSwitch([0xC00E], "W", "altCharsetOff")),
        mixin(MakeSwitch([0xC00F], "W", "altCharsetOn")),
        mixin(MakeSwitch([0xC01E], "R", "readAltCharset"))
    ]));
}

class LoresPatternGenerator : PatternGenerator
{
    ubyte[2][2][16] patterns;

    void initPatterns()
    {
        int[16] dhrBits4 = [
            0x0, 0x8, 0x4, 0xC, 0x2, 0x5, 0x6, 0xE,
            0x1, 0x9, 0xA, 0xD, 0x3, 0xB, 0x7, 0xF];
        for (int bits4 = 0; bits4 < 16; ++bits4)
        {
            ubyte bits8 = (dhrBits4[bits4] << 4) | dhrBits4[bits4];
            ushort bits16 = (bits8 << 8) | bits8;
            uint bits32 = (bits16 << 16) | bits16;
            patterns[bits4][0][0] = bits32 >> 25;
            patterns[bits4][0][1] = (bits32 >> 18) & 0b01111111;
            patterns[bits4][1][0] = (bits32 >> 11) & 0b01111111;
            patterns[bits4][1][1] = (bits32 >> 4) & 0b01111111;
        }
    }

    void initPatterns(ubyte[] rom)
    {
        /+ TODO: Initialize patterns from IIe video ROM +/
        if (rom is null) initPatterns();
        else initPatterns();
    }

    void update(ubyte* signal, int scanLine, int startCol, uint len)
    {
        uint screenPos = 0;
        uint col = startCol;
        int shiftAmt = (((scanLine % 8) / 4) == 0) ? 0 : 4;
        ubyte* data = scanner.getData(scanLine, startCol + 25);
        uint memNybble;

        for (uint offset = 0; offset < len; ++offset)
        {
            memNybble = (data[offset] >> shiftAmt) & 0x0F;
            signal[screenPos++] = patterns[memNybble][col & 1][0];
            signal[screenPos++] = patterns[memNybble][col++ & 1][1];
        }
    }

    void update80(ubyte* signal, int scanLine, int startCol, uint len)
    {
        uint screenPos = 0;
        uint col = startCol;
        int shiftAmt = (((scanLine % 8) / 4) == 0) ? 0 : 4;
        ubyte* data = scanner.getData(scanLine, startCol + 25);
        ubyte* auxData = scanner.getData80(scanLine, startCol + 25);
        uint memNybble;
        
        for (uint offset = 0; offset < len; ++offset)
        {
            memNybble = (auxData[offset] >> shiftAmt) & 0x0F;
            signal[screenPos++] = patterns[memNybble][col & 1][0];

            memNybble = (data[offset] >> shiftAmt) & 0x0F;
            signal[screenPos++] = patterns[memNybble][col++ & 1][0];
        }
    }
}

class HiresPatternGenerator : PatternGenerator
{
    ubyte[2][256] patterns;
    ubyte[256] patterns80;

    ubyte prevByte;

    void initPatterns()
    {
        for (int bits = 0; bits < 256; ++bits)
        {
            ubyte leftPattern = doubleBits[reverseBits[bits & 0x7F]][0];
            ubyte rightPattern = doubleBits[reverseBits[bits & 0x7F]][1];
            if (bits > 0x7F)
            {
                patterns[bits][0] = leftPattern >> 1;
                patterns[bits][1] = (rightPattern >> 1) |
                    ((leftPattern & 1) << 6);
            }
            else
            {
                patterns[bits][0] = leftPattern;
                patterns[bits][1] = rightPattern;
            }

            patterns80[bits] = reverseBits[bits & 0x7F] | (bits & 0x80);
        }
    }

    void initPatterns(ubyte[] rom)
    {
        /+ TODO: Initialize patterns from IIe video ROM +/
        if (rom is null) initPatterns();
        else initPatterns();
    }

    void update(ubyte* signal, int scanLine, int startCol, uint len)
    {
        uint screenPos = 0;
        uint vidClock = scanLine * 65 + startCol + 25;
        ubyte* data = scanner.getData(vidClock);
        uint memByte;

        if (startCol == 0)
            prevByte = *(scanner.getData(vidClock - 1)) & 0b01000000;

        for (uint offset = 0; offset < len; ++offset)
        {
            memByte = data[offset];

            if (memByte > 0x7F)
                signal[screenPos++] = patterns[memByte][0] | prevByte;
            else
                signal[screenPos++] = patterns[memByte][0];
            prevByte = memByte & 0b01000000;
            signal[screenPos++] = patterns[memByte][1];
        }
    }

    void update80(ubyte* signal, int scanLine, int startCol, uint len)
    {
        uint screenPos = 0;
        ubyte* data = scanner.getData(scanLine, startCol + 25);
        ubyte* auxData = scanner.getData80(scanLine, startCol + 25);

        for (int offset = 0; offset < len; ++offset)
        {
            signal[screenPos++] = patterns80[auxData[offset]];
            signal[screenPos++] = patterns80[data[offset]];
        }
    }
}

class HiresPatternGenerator_Revision0 : HiresPatternGenerator
{
    void update(ubyte* signal, int scanLine, int startCol, uint len)
    {
        uint screenPos = 0;
        ubyte* data = scanner.getData(scanLine, startCol);
        uint memByte;

        for (int offset = 0; offset < len; ++offset)
        {
            memByte = data[offset] & 0x7F;
            signal[screenPos++] = patterns[memByte][0];
            signal[screenPos++] = patterns[memByte][1];
        }
    }
}

