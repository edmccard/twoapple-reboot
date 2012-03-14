/+
 + video/offsets.d
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

import video.base : Mode;

static this()
{
    hCounter = new HorizontalCounter();
    vCounter = new VerticalCounter();

    for (int scanLine = 0; scanLine < 192; ++scanLine)
    {
        firstDisplayedOffset[Mode.HIRES][scanLine] =
            screenOffset(&vCounter.states[scanLine], &hCounter.states[25],
                    Mode.HIRES);
        firstDisplayedOffset[Mode.LORES][scanLine] =
            screenOffset(&vCounter.states[scanLine], &hCounter.states[25],
                    Mode.LORES);
        firstDisplayedOffset[Mode.TEXT][scanLine] =
            screenOffset(&vCounter.states[scanLine], &hCounter.states[25],
                    Mode.TEXT);
    }
}

ushort scanOffset(uint vidClock, Mode mode)
{
    if (((vidClock % 65) == 25) && (vidClock / 65) < 192)
        return firstDisplayedOffset[mode][vidClock / 65];
    else
        return screenOffset(&vCounter.states[vidClock / 65],
                &hCounter.states[vidClock % 65], mode);
}

ushort scanOffset(uint line, uint col, Mode mode)
{
    if ((col == 25) && (line < 192))
        return firstDisplayedOffset[mode][line];
    else
        return screenOffset(&vCounter.states[line], &hCounter.states[col],
                mode);
}

private:

HorizontalCounter hCounter;
VerticalCounter vCounter;
ushort[192][3] firstDisplayedOffset;

class HorizontalCounter
{
    State[65] states;

    this()
    {
        uint counter = 0b0000000;
        int number = 0;
        while(counter <= 0b1111111)
        {
            states[number++] = new State(counter);
            if (counter == 0b0000000)
                counter = 0b1000000;
            else
                ++counter;
        }
    }

    enum
    {
        HP = 0b1000000,
        H5 = 0b0100000,
        H4 = 0b0010000,
        H3 = 0b0001000,
        H2 = 0b0000100,
        H1 = 0b0000010,
        H0 = 0b0000001
    }

    class State
    {
        int a6_a5_a4_a3;
        int a2_a1_a0;

        this(int counter)
        {
            a6_a5_a4_a3 = counter & (H5 | H4 | H3);
            a2_a1_a0 = counter & (H2 | H1 | H0);
        }
    }
}

class VerticalCounter
{
    State[] states;

    this()
    {
        uint counter = 0b011111010; // XXX PAL: 0b011001000
        states.length = 512 - counter;
        int scanline = 256;
        while (counter <= 0b111111111)
        {
            states[scanline++] = new State(counter++);
            if (counter == 0b100000000) scanline = 0;
        }
    }

    enum
    {
        V5 = 0b100000000,
        V4 = 0b010000000,
        V3 = 0b001000000,
        V2 = 0b000100000,
        V1 = 0b000010000,
        V0 = 0b000001000,
        VC = 0b000000100,
        VB = 0b000000010,
        VA = 0b000000001
    }

    class State
    {
        int a12_a11_a10;
        int a9_a8_a7;
        int a6_a5_a4_a3;

        this(int counter)
        {
            a12_a11_a10 = (counter & (VC | VB | VA)) << 10;
            a9_a8_a7 = (counter & (V2 | V1 | V0)) << 4;
            a6_a5_a4_a3 = ((counter & (V4 | V3)) >> 1) |
                ((counter & (V4 | V3)) >> 3);
        }
    }
}

alias VerticalCounter.State vState;
alias HorizontalCounter.State hState;

ushort screenOffset(vState* vSt, hState* hSt, Mode mode)
{
    ushort sum_a6_a5_a4_a3 =
        (vSt.a6_a5_a4_a3 + hSt.a6_a5_a4_a3 + 0b1101000) & 0b1111000;
    ushort offset = vSt.a9_a8_a7 | sum_a6_a5_a4_a3 | hSt.a2_a1_a0;

    if (mode == Mode.HIRES)
    {
        offset |= vSt.a12_a11_a10;
    }

    return offset;
}

