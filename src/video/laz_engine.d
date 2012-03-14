/+
 + video/laz_engine.d
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

private:

template Tuple(E...) { alias E Tuple; }

enum Color
{
    Black,
    Red,
    Brown,
    Orange,
    DarkGreen,
    DarkGray,
    Green,
    Yellow,
    DarkBlue,
    Purple,
    LightGray,
    Pink,
    MediumBlue,
    LightBlue,
    Aqua,
    White
}

public:

class LazEngine : Screen
{
    ushort data_[562 * 192];

    ushort[1][3] monoPalettes = [
        [0x03E0],   // green
        [0xFAA3],   // amber
        [0xFFFF]    // white
    ];
    ushort* monoPalette;

    mixin("static final ushort[32][8] colorPalettes = " 
            ~ import("palette_5_6_5"));
    ushort* colorPalette;

    mixin("static final uint[32][4][3] schemes = "
            ~ import("laz_scheme"));
    uint[32]* scheme;

    mixin("static final uint[32][2][2] sharp_table = "
            ~ import("laz_sharp"));

    this()
    {
        width = 562;
        height = 192;
        data = data_.ptr;
        monoPalette = monoPalettes[0].ptr;
        colorPalette = colorPalettes[0].ptr;
        scheme = schemes[0].ptr;
        isColor = true;
    }

    void monochrome(ubyte* bitmap, int scanLine, int scanStart, int scanEnd,
            ushort color_5_6_5)
    {
        uint dataPtr = (scanLine * width) + scanStart * 14;
        uint bitmapPtr = 0;
        uint bits, bitPos;
        for (int scan = scanStart; scan <= scanEnd; ++scan)
        {
            foreach(mapByte; Tuple!(0, 1))
            {
                bits = bitmap[bitmapPtr++];
                bitPos = 0b01000000;
                foreach (mapBit; Tuple!(0, 1, 2, 3, 4, 5, 6))
                {
                    if (bits & bitPos)
                        data[dataPtr++] = color_5_6_5;
                    else
                        data[dataPtr++] = 0;
                    bitPos >>= 1;
                }
            }
        }
    }

    void draw(bool col80, bool colorBurst, ubyte* bitmap, int scanLine,
            int scanStart, int scanEnd)
    {
        if (!isColor || !colorBurst)
        {
            monochrome(((scanStart == 0) ? bitmap : bitmap + 1),
                    scanLine, scanStart, scanEnd,
                    (isColor ? colorPalette[15] : monoPalette[0]));
        }
        else
        {
            polychrome(col80, bitmap, scanLine, scanStart, scanEnd);
        }
    }

    void polychrome(bool col80, ubyte* bitmap, int scanLine, int scanStart,
            int scanEnd)
    {
        uint colStart = scanStart * 14;
        uint colEnd = scanEnd * 14 + 13;
        uint colCorrection = (col80 ? 0 : 3);
        bool finishCols;

        uint bitmapPtr = 0;
        uint dataPtr = (scanLine * width) + colStart;

        uint colorIndex, paletteIndex;
        uint prevBit, nextBit;
        uint nextBitTest = 0b00010000;
        uint nextBitShift = 4;
        
        ubyte bits = bitmap[bitmapPtr];

        if (scanStart == 0)
        {
            colorIndex = (bits >> 5) & 0b11;
        }
        else
        {
            colorIndex = (bits << 2) & 0b11111;
            bits = bitmap[++bitmapPtr];
            colorIndex |= (bits >> 5 & 0b11);
        }
        nextBit = (bits & nextBitTest) >> nextBitShift;

        if (colEnd > 556)
        {
            finishCols = true;
            colEnd = 556;
        }
        colEnd += colCorrection;

        for (uint col = colStart + colCorrection; col <= colEnd; ++col)
        {
            nextBitTest >>= 1;
            --nextBitShift;
            if (nextBitTest == 0)
            {
                nextBitTest = 0b01000000;
                nextBitShift = 6;
                bits = bitmap[++bitmapPtr];
            }
            prevBit = colorIndex >> 4;
            colorIndex = ((colorIndex << 1) | nextBit) & 0b11111;
            nextBit = (bits & nextBitTest) >> nextBitShift;
            paletteIndex = scheme[col & 0b11][colorIndex];
            if (paletteIndex > 0x80)
            {
                switch (sharp_table[prevBit][nextBit][colorIndex])
                {
                    case 0:
                        paletteIndex = Color.Black;
                    case 15:
                        paletteIndex = Color.White;
                    case 99:
                        paletteIndex &= 0x7F;
                }
            }
            data[dataPtr++] = colorPalette[paletteIndex];
        }

        if (finishCols)
        {
            for (uint col = 557 + colCorrection; col <= 561 + colCorrection;
                    ++col)
            {
                prevBit = colorIndex >> 4;
                colorIndex = (colorIndex << 1) & 0b11111;
                paletteIndex = scheme[col & 0b11][colorIndex];
                if (paletteIndex > 0x80)
                {
                    switch (sharp_table[prevBit][nextBit][colorIndex])
                    {
                        case 0:
                            paletteIndex = Color.Black;
                        case 15:
                            paletteIndex = Color.White;
                        case 99:
                            paletteIndex &= 0x7F;
                    }
                }
                data[dataPtr++] = colorPalette[paletteIndex];
            }
        }
    }
}

