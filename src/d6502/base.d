/+
 + d6502/base.d
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

module d6502.base;

string hexByte(int decByte)
{
    int highNybble = (decByte & 0xF0) >> 4;
    int lowNybble = decByte & 0x0F;

    string digits = "0123456789ABCDEF";

    return digits[highNybble..(highNybble + 1)] ~
        digits[lowNybble..(lowNybble + 1)];
}

final class StatusRegister
{
    bool carry, decimal, interrupt, overflow;
    ubyte zero_, negative_;

    ubyte toByte()
    {
        return (carry ? 0x01 : 0) |
            ((zero_ == 0) ? 0x02 : 0) | 
            (interrupt ? 0x04 : 0) |
            (decimal ? 0x08 : 0) |
            0x30 |          // break and reserved both set
            (overflow ? 0x40 : 0) |
            (negative_ & 0x80);
    }

    void fromByte(ubyte val)
    {
        carry = ((val & 0x01) != 0);
        zero_ = ((val & 0x02) ? 0 : 1);
        interrupt = ((val & 0x04) != 0);
        decimal = ((val & 0x08) != 0);
        overflow = ((val & 0x40) != 0);
        negative_ = val;
    }
}

class CpuBase
{
    static string AbstractOpcodes()
    {
        string abstractOpcodes;
        for (int op = 0; op < 256; ++op)
            abstractOpcodes ~= "abstract void opcode" ~ hexByte(op) ~ "();\n";
        return abstractOpcodes;
    }

    mixin(AbstractOpcodes());

    ushort programCounter;
    ubyte accumulator, xIndex, yIndex, stackPointer;
    final StatusRegister flag;

    bool signalActive, irqActive, resetActive, nmiActive, nmiArmed;

    ushort opcodePC;
    ubyte opcode, operand1, operand2;

    final ubyte[] save()
    {
        ubyte[] data = new ubyte[12];
        data[0] = programCounter & 0xFF;
        data[1] = programCounter >> 8;
        data[2] = accumulator;
        data[3] = xIndex;
        data[4] = yIndex;
        data[5] = stackPointer;
        data[6] = flag.toByte();
        data[7] = (signalActive ? 1 : 0);
        data[8] = (irqActive ? 1 : 0);
        data[9] = (resetActive ? 1 : 0);
        data[10] = (nmiActive ? 1 : 0);
        data[11] = (nmiArmed ? 1 : 0);
        return data;
    }

    final void restore(ubyte[] data)
    {
        assert (data.length >= 12);

        programCounter = data[0] | (data[1] << 8);
        accumulator = data[2];
        xIndex = data[3];
        yIndex = data[4];
        stackPointer = data[5];
        flag.fromByte(data[6]);
        signalActive = ((data[7] == 0) ? false : true);
        irqActive = ((data[8] == 0) ? false : true);
        resetActive = ((data[9] == 0) ? false : true);
        nmiActive = ((data[10] == 0) ? false : true);
        nmiArmed = ((data[11] == 0) ? false : true);
    }

    final void reboot()
    {
        restore([0, 0, 0, 0, 0, 0xFF, 0, 0, 0, 0, 0, 1]);
    }

    ubyte delegate(ushort addr) memoryRead;
    void delegate(ushort addr, ubyte val) memoryWrite;
    debug(disassemble)
    {
        string delegate(ushort addr) memoryName;
    }
    version(CycleAccuracy) void delegate() tick;
    version(CumulativeCycles) void delegate(int cycles) ticks;

    abstract void run(bool continuous);
    abstract void stop();
    version(CycleAccuracy) abstract bool checkFinalCycle();
    abstract void resetLow();
    abstract void nmiLow(bool signalLow);
    abstract void irqLow(bool signalLow);
}

