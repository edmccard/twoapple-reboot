/+
 + d6502/cmos.d
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
import d6502.cpu;

class Cmos : Cpu
{
    this()
    {
        super();
        spuriousAddress = &programCounter;
    }

    final override void do_IRQ_or_NMI(ushort vector)
    {
        super.do_IRQ_or_NMI(vector);
        flag.decimal = false;
    }

    final override void doReset()
    {
        super.doReset();
        flag.decimal = false;
    }

    final override void dec_addWithCarry(ubyte val)
    {
        super.dec_addWithCarry(val);
        peek(programCounter);
        flag.zero_ = flag.negative_ = accumulator;
    }

    final override void dec_subWithCarry(ubyte val)
    {
        super.dec_subWithCarry(val);
        peek(programCounter);
        flag.zero_ = flag.negative_ = accumulator;
    }

    final void addrZeropageI()
    {
        ubyte vector = readByteOperand();
        primaryAddress = readWord(vector, cast(ubyte)(vector + 1));
    }

    final void addrNone()
    {
        version(CumulativeCycles) ticks(totalCycles);
    }

    final ubyte testSet(ubyte val)
    {
        flag.zero_ = val & accumulator;
        return val | accumulator;
    }

    final ubyte testReset(ubyte val)
    {
        flag.zero_ = val & accumulator;
        return val & ~accumulator;
    }

    static string RMW(string action)
    {
        return "peek(primaryAddress);\n" ~
            "writeFinal(primaryAddress, (flag.zero_ = flag.negative_ = " ~
            action ~ "(readVal = read(primaryAddress))));\n";
    }

    static string TestModify(string action)
    {
        return "peek(primaryAddress);\n" ~
            "writeFinal(primaryAddress, " ~
            action ~ "(readVal = read(primaryAddress)));\n";
    }

    static string ReadNOP()
    {
        return "readVal = readFinal(primaryAddress);\n";
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

    mixin(Opcode(mixin(Type2Address(
        "ASL", "Read", [0x06, 0x0E, 0x16, 0x1E])),
        RMW("shiftLeft")));
    mixin(Opcode(mixin(Type2Address(
        "LSR", "Read", [0x46, 0x4E, 0x56, 0x5E])),
        RMW("shiftRight")));
    mixin(Opcode(mixin(Type2Address(
        "ROL", "Read", [0x26, 0x2E, 0x36, 0x3E])),
        RMW("rotateLeft")));
    mixin(Opcode(mixin(Type2Address(
        "ROR", "Read", [0x66, 0x6E, 0x76, 0x7E])),
        RMW("rotateRight")));
    mixin(Opcode(mixin(Type2Address(
        "INC", "Read", [0xE6, 0xEE, 0xF6, 0xFE])),
        RMW("increment")));
    mixin(Opcode(mixin(Type2Address(
        "DEC", "Read", [0xC6, 0xCE, 0xD6, 0xDE])),
        RMW("decrement")));

    mixin(Opcode(mixin(Type2Address(
        "BIT", "Read", [0x34, 0x3C])),
        BitTest()));
    mixin(Opcode([["ORA", "Read"], ["12", "ZeropageI()"]],
        Read("accumulator |=")));
    mixin(Opcode([["AND", "Read"], ["32", "ZeropageI()"]],
        Read("accumulator &=")));
    mixin(Opcode([["EOR", "Read"], ["52", "ZeropageI()"]],
        Read("accumulator ^=")));
    mixin(Opcode([["LDA", "Read"], ["B2", "ZeropageI()"]],
        Read("accumulator =")));
    mixin(Opcode([["CMP", "Read"], ["D2", "ZeropageI()"]],
        Compare("accumulator")));
    mixin(Opcode([["ADC", "Read"], ["72", "ZeropageI()"]],
        Decimal("addWithCarry")));
    mixin(Opcode([["SBC", "Read"], ["F2", "ZeropageI()"]],
        Decimal("subWithCarry")));
    mixin(Opcode([["STA", "Write"], ["92", "ZeropageI()"]],
        Write("accumulator")));

    mixin(RegisterOpcode("DEA", "3A", "accumulator -= 1"));
    mixin(RegisterOpcode("INA", "1A", "accumulator += 1"));
    mixin(SimpleOpcode("PHX", "DA", "push(xIndex)"));
    mixin(SimpleOpcode("PHY", "5A", "push(yIndex)"));
    mixin(RegisterOpcode("PLX", "FA", "xIndex = pull()"));
    mixin(RegisterOpcode("PLY", "7A", "yIndex = pull()"));
    mixin(BranchOpcode("BRA", "80", "true"));

    mixin(Opcode([["TRB", "Read"],
        ["14", "Zeropage()"], ["1C", "Absolute"]],
        TestModify("testReset")));
    mixin(Opcode(mixin(Type2Address(
        "TSB", "Read", [0x04, 0x0C])),
        TestModify("testSet")));
    mixin(Opcode([["STZ", "Write"],
        ["64", "Zeropage()"], ["74", "ZeropageX()"],
        ["9C", "Absolute()"], ["9E", "AbsoluteX(true)"]],
        Write("0")));

    mixin(Opcode(mixin(ManualAddress(
        "NOP", [0x02, 0x22, 0x42, 0x62, 0x82, 0xC2, 0xE2],
            "Immediate")),
        ReadNOP()));
    mixin(Opcode(mixin(ManualAddress(
        "NOP", [0x44],
            "Zeropage()")),
        ReadNOP()));
    mixin(Opcode(mixin(ManualAddress(
        "NOP", [0x54, 0xD4, 0xF4],
            "ZeropageX()")),
        ReadNOP()));
    mixin(Opcode(mixin(ManualAddress(
        "NOP", [0xDC, 0xFC],
            "AbsoluteX(false)")),
        ReadNOP()));
    mixin(Opcode(mixin(ManualAddress(
        "NOP", [0x03, 0x13, 0x23, 0x33, 0x43, 0x53, 0x63, 0x73, 0x83, 0x93,
                0xA3, 0xB3, 0xC3, 0xD3, 0xE3, 0xF3, 0x07, 0x17, 0x27, 0x37,
                0x47, 0x57, 0x67, 0x77, 0x87, 0x97, 0xA7, 0xB7, 0xC7, 0xD7,
                0xE7, 0xF7, 0x0B, 0x1B, 0x2B, 0x3B, 0x4B, 0x5B, 0x6B, 0x7B,
                0x8B, 0x9B, 0xAB, 0xBB, 0xCB, 0xDB, 0xEB, 0xFB, 0x0F, 0x1F,
                0x2F, 0x3F, 0x4F, 0x5F, 0x6F, 0x7F, 0x8F, 0x9F, 0xAF, 0xBF,
                0xCF, 0xDF, 0xEF, 0xFF], "None()")),
        ""));

    /* NOP8 */
    void opcode5C()
    {
        readByteOperand();
        peek(programCounter);
        peek(0xFF00 | operand1);
        peek(0xFFFF);
        peek(0xFFFF);
        peek(0xFFFF);
        peek(0xFFFF);
    }

    /* JMP ($$$$) */
    override void opcode6C()
    {
        ushort vector = readWordOperand();
        peek(programCounter);
        programCounter = readWord(vector, vector + 1);
        version(CumulativeCycles) ticks(totalCycles);
    }
    
    /* JMP ($$$$,X) */
    void opcode7C()
    {
        baseAddress = readWordOperand();
        peek(programCounter);
        ushort vector = baseAddress + xIndex;
        programCounter = readWord(vector, vector + 1);
        version(CumulativeCycles) ticks(totalCycles);
    }

    /* BIT #$$ */
    void opcode89()
    {
        readVal = operand1 = readFinal(programCounter++);
        flag.zero_ = accumulator & readVal;
    }
}

