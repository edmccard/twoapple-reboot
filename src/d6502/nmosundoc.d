/+
 + d6502/nmosundoc.d
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

import d6502.base;
import d6502.nmosbase;

class NmosUndoc : NmosBase
{
    this()
    {
        super();
    }

    final void addrHalt() {}
    final void addrImplied()
    {
        peek(programCounter);
        version(CumulativeCycles) ticks(totalCycles);
    }

    final void strange(ubyte val)
    {
        version(Commodore64)
        {
            ubyte hiAddr = ((primaryAddress >> 8) + 1);
            val = val & hiAddr;
            ushort addr = (badAddress == primaryAddress) ? primaryAddress :
                ((val << 8) | (primaryAddress & 0xFF));
            writeFinal(addr, val);
        }
        else
        {
            ubyte hiAddr = ((baseAddress >> 8) + 1);
            writeFinal(primaryAddress, val & hiAddr);
        }
    }

    static string UndocAddress(string name, string rw, int[] opcodes)
    {
        string type = (rw == "Write") ? "true" : "false";
        string modes = "[[\"" ~ name ~ "\", \"" ~ rw ~ "\"], \n";
        for (int op = 0; op < opcodes.length; ++op)
        {
            int opcode = opcodes[op];
            modes ~= "[\"" ~ hexByte(opcode) ~ "\", \"";
            switch ((opcode & 0b00011100) >> 2)
            {
                case 0:
                    modes ~= "IndirectX()";
                    break;
                case 1:
                    modes ~= "Zeropage()";
                    break;
                case 3:
                    modes ~= "Absolute()";
                    break;
                case 4:
                    modes ~= "IndirectY("~ type ~ ")";
                    break;
                case 5:
                    modes ~= "ZeropageX()";
                    break;
                case 7:
                    modes ~= "AbsoluteY(" ~ type ~ ")";
                    break;
            }
            modes ~= "\"]";
            if (op != (opcodes.length - 1)) modes ~= ", ";
            modes ~= "\n";
        }
        return modes ~ "]\n";
    }

    static string ManualAddress(string name, int[] opcodes,
            string mode)
    {
        string modes = "[[\"" ~ name ~ "\", \"NA\"], \n";
        for (int op = 0; op < opcodes.length; ++op)
        {
            int opcode = opcodes[op];
            modes ~= "[\"" ~ hexByte(opcode) ~ "\", \"" ~ mode ~ "\"]";
            if (op != (opcodes.length - 1)) modes ~= ", ";
            modes ~= "\n";
        }
        return modes ~ "]\n";
    }

    static string Halt()
    {
        /+ TODO: have this do something useful +/
        return "\n";
    }

    static string ReadNOP()
    {
        return "readVal = readFinal(primaryAddress);\n";
    }

    static string RMW_Read(string action1, string action2)
    {
        return "poke(primaryAddress, (readVal = read(primaryAddress)));\n" ~
            "writeFinal(primaryAddress, flag.zero_ = flag.negative_ = " ~
            "(writeVal = " ~ action1 ~ "(readVal)));\n" ~
            action2 ~ " writeVal;\n";
    }

    static string RMW_Compare(string action1, string action2)
    {
        return "poke(primaryAddress, (readVal = read(primaryAddress)));\n" ~
            "writeFinal(primaryAddress, flag.zero_ = flag.negative_ = " ~
            "(writeVal = " ~ action1 ~ "(readVal)));\n" ~
            "compare(" ~ action2 ~ ", writeVal);\n";
    }

    static string RMW_Decimal(string action1, string action2)
    {
        return "poke(primaryAddress, (readVal = read(primaryAddress)));\n" ~
            "writeFinal(primaryAddress, flag.zero_ = flag.negative_ = " ~
            "(writeVal = " ~ action1 ~ "(readVal)));\n" ~
            "if (flag.decimal) dec_" ~ action2 ~ "(writeVal);\n" ~
            "else hex_" ~ action2 ~ "(writeVal);\n";
    }

    mixin(Opcode(mixin(ManualAddress(
        "HLT", [0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x92, 0xB2,
                0xD2, 0xF2], "Halt()")),
        Halt()));

    mixin(Opcode(mixin(ManualAddress(
        "NOP", [0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA], "Implied()")),
        ""));
    mixin(Opcode(mixin(ManualAddress(
        "NOP", [0x0C, 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC],
            "AbsoluteX(false)")),
        ReadNOP()));
    mixin(Opcode(mixin(ManualAddress(
        "NOP", [0x80, 0x82, 0x89, 0xC2, 0xE2],
            "Immediate")),
        ReadNOP()));
    mixin(Opcode(mixin(ManualAddress(
        "NOP", [0x04, 0x44, 0x64],
            "Zeropage()")),
        ReadNOP()));
    mixin(Opcode(mixin(ManualAddress(
        "NOP", [0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4],
            "ZeropageX()")),
        ReadNOP()));

    mixin(Opcode(mixin(UndocAddress(
        "LAX", "Read", [0xA3, 0xA7, 0xAF, 0xB3, 0xB7, 0xBF])),
        Read("accumulator = xIndex =")));
    mixin(Opcode(mixin(UndocAddress(
        "SAX", "Write", [0x83, 0x87, 0x8F, 0x97])),
        Write("accumulator & xIndex")));

    mixin(Opcode(mixin(Type1Address(
        "ASO", "Write", [0x03, 0x07, 0x0F, 0x13, 0x17, 0x1B, 0x1F])),
        RMW_Read("shiftLeft", "accumulator |=")));
    mixin(Opcode(mixin(Type1Address(
        "RLA", "Write", [0x23, 0x27, 0x2F, 0x33, 0x37, 0x3B, 0x3F])),
        RMW_Read("rotateLeft", "accumulator &=")));
    mixin(Opcode(mixin(Type1Address(
        "LSE", "Write", [0x43, 0x47, 0x4F, 0x53, 0x57, 0x5B, 0x5F])),
        RMW_Read("shiftRight", "accumulator ^=")));
    mixin(Opcode(mixin(Type1Address(
        "DCM", "Write", [0xC3, 0xC7, 0xCF, 0xD3, 0xD7, 0xDB, 0xDF])),
        RMW_Compare("decrement", "accumulator")));
    mixin(Opcode(mixin(Type1Address(
        "RRA", "Write", [0x63, 0x67, 0x6F, 0x73, 0x77, 0x7B, 0x7F])),
        RMW_Decimal("rotateRight", "addWithCarry")));
    mixin(Opcode(mixin(Type1Address(
        "INS", "Write", [0xE3, 0xE7, 0xEF, 0xF3, 0xF7, 0xFB, 0xFF])),
        RMW_Decimal("increment", "subWithCarry")));

    /* ANC #$$ */
    override void opcode0B()
    {
        readVal = operand1 = readFinal(programCounter);
        flag.zero_ = flag.negative_ = (accumulator = readVal);
        flag.carry = (flag.negative_ > 0x7F);
    } 

    /* ANC #$$ */
    override void opcode2B()
    {
        readVal = operand1 = readFinal(programCounter);
        flag.zero_ = flag.negative_ = (accumulator = readVal);
        flag.carry = (flag.negative_ > 0x7F);
    }

    /* ALR #$$ */
    override void opcode4B()
    {
        readVal = operand1 = readFinal(programCounter);
        flag.zero_ = flag.negative_ =
            (accumulator = shiftRight(accumulator & readVal));
    }

    /* ARR #$$ */
    override void opcode6B()
    {
        readVal = operand1 = readFinal(programCounter);
        ubyte val = readVal & accumulator;
        if (flag.decimal) {
            ubyte temp = (val >> 1) + (flag.carry ? 0x80 : 0);
            flag.zero_ = flag.negative_ = temp;
            flag.overflow = (((temp ^ val) & 0x40) != 0);
            if ((readVal & 0x0F) + (val & 0x01) > 5)
                temp = (temp & 0xF0) + ((temp + 0x6) & 0x0F);
            if (val + (val & 0x10) >= 0x60)
            {
                temp += 0x60;
                flag.carry = true;
            }
            else
                flag.carry = false;
            accumulator = temp;
        }
        else {
            accumulator = (val >> 1) + (flag.carry ? 0x80 : 0);
            flag.zero_ = flag.negative_ = accumulator;
            val >>= 7;
            flag.carry = (val != 0);
            flag.overflow = ((val ^ ((accumulator >> 5) & 1)) != 0);
        }
    }

    /* ANE #$$ */
    override void opcode8B()
    {
        // unstable
        readVal = operand1 = readFinal(programCounter);

        version(Atari8Bit)
        {
            flag.zero_ = flag.negative_ =
                (accumulator & xIndex & readVal);
            accumulator &= xIndex & (operand1 | 0xEF);
        }
        else
        {
            flag.zero_ = flag.negative_ =
                (accumulator &= (xIndex & readVal));
        }
    }

    /* SHA ($$),Y */
    void opcode93()
    {
        addrIndirectY(true);
        strange(accumulator & xIndex);
    }

    /* SHA $$$$,Y */
    void opcode9F()
    {
        addrAbsoluteY(true);
        strange(accumulator & xIndex);
    }

    /* SHS $$$$,Y */
    void opcode9B()
    {
        addrAbsoluteY(true);
        strange(stackPointer = (accumulator & xIndex));
    }

    /* SHY $$$$,X */
    void opcode9C()
    {
        addrAbsoluteX(true);
        strange(yIndex);
    }

    /* SHX $$$$,Y */
    void opcode9E()
    {
        addrAbsoluteY(true);
        strange(xIndex);
    }

    /* LAX #$$ */
    override void opcodeAB()
    {
        readVal = operand1 = readFinal(programCounter);

        version(Commodore128)
        {
            // not unstable?
            flag.zero_ = flag.negative_ =
                (accumulator = readVal);
        }
        else
        {
            // unstable
            version(Commodore64)
            {
                accumulator |= 0xEE;
            }
            flag.zero_ = flag.negative_ =
                (accumulator &= readVal);
        }
        xIndex = accumulator;
    }

    /* LAS $$$$,Y */
    override void opcodeBB()
    {
        addrAbsoluteY(false);
        readVal = readFinal(primaryAddress);

        flag.zero_ = flag.negative_ =
            (xIndex = accumulator = (stackPointer & readVal));
    }

    /* SBX #$$ */
    override void opcodeCB()
    {
        readVal = operand1 = readFinal(programCounter);
        xIndex &= accumulator;
        flag.zero_ = flag.negative_ = compare(xIndex, readVal);
    }

    /* SBC #$$ */
    override void opcodeEB()
    {
        readVal = operand1 = readFinal(programCounter);
        if (flag.decimal) dec_subWithCarry(readVal);
        else hex_subWithCarry(readVal);
    }
}

