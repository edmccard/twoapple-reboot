/+
 + d6502/cpu.d
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

class Cpu : CpuBase
{
    static string InitOpcodes()
    {
        string initCalls;
        for (int op = 0; op < 256; ++op)
        {
            initCalls ~= "opcodes[0x" ~ hexByte(op) ~ "] = &opcode" ~
                hexByte(op) ~ ";\n";
        }
        return initCalls;
    }

    this()
    {
        mixin(InitOpcodes());
        flag = new StatusRegister();
    }

    const ushort STACK_BASE = 0x0100;
    const ushort NMI_VECTOR = 0xFFFA;
    const ushort RESET_VECTOR = 0xFFFC;
    const ushort IRQ_VECTOR = 0xFFFE;

    void delegate()[256] opcodes;
    bool continueExecution;
    version(CycleAccuracy) bool finalCycle;
    version(CumulativeCycles) int totalCycles;

    debug(disassemble)
    {
        import hacking.debugger;
        import std.stdio;
    }
    final override void run(bool continuous)
    {
        assert ((memoryRead !is null) && (memoryWrite !is null));
        version(CycleAccuracy) assert (tick !is null);

        continueExecution = continuous;
        do
        {
            if (signalActive) handleSignals();

            opcodePC = programCounter;
            opcode = read(programCounter++);
            version(CycleAccuracy) finalCycle = false;
            version(CumulativeCycles) totalCycles = 0;

            /+ TODO: call sync delegate +/

            opcodes[opcode]();
            debug(disassemble)
            {
                writefln(Debugger.disassemble(this, cmosMap)
                        ~ Debugger.displayRegisters(this));
            }
        } while (continueExecution);
    }

    final override void stop()
    {
        continueExecution = false;
    }

    version(CycleAccuracy)
    {
        final override bool checkFinalCycle()
        {
            return finalCycle;
        }
    }

    final override void resetLow()
    {
        resetActive = signalActive = true;
    }

    final override void nmiLow(bool signalLow)
    {
        nmiActive = signalLow;
        if (!signalLow) nmiArmed = true;
        signalActive = testSignals();
    }

    final override void irqLow(bool signalLow)
    {
        irqActive = signalLow;
        signalActive = testSignals();
    }

    final bool testSignals()
    {
        return (resetActive || nmiActive || irqActive);
    }

    final void handleSignals()
    {
        bool checkNMI()
        {
            if (nmiActive && nmiArmed)
            {
                nmiArmed = false;
                return true;
            }
            return false;
        }

        if (resetActive) doReset();
        else if (checkNMI()) do_IRQ_or_NMI(NMI_VECTOR);
        else if ((!flag.interrupt) && irqActive) do_IRQ_or_NMI(IRQ_VECTOR);
    }

    void do_IRQ_or_NMI(ushort vector)
    {
        doInterrupt(vector, (flag.toByte() & ~0x10));
    }

    final void doInterrupt(ushort vector, ubyte statusByte)
    {
        pushWord(programCounter);
        push(statusByte);
        flag.interrupt = true;
        programCounter = readWord(vector, vector + 1);
        version(CumulativeCycles) ticks(totalCycles);
    }

    void doReset()
    {
        version(CycleAccuracy)
        {
            tick(); tick();
        }
        version(CumulativeCycles)
        {
            totalCycles += 2;
        }

        peek(STACK_BASE + stackPointer);
        --stackPointer;
        peek(STACK_BASE + stackPointer);
        --stackPointer;
        peek(STACK_BASE + stackPointer);
        --stackPointer;

        flag.interrupt = true;
        resetActive = false;
        signalActive = testSignals();

        programCounter = readWord(RESET_VECTOR, RESET_VECTOR + 1);
        version(CumulativeCycles) ticks(totalCycles);
    }

    final ubyte read(ushort addr)
    {
        version(CycleAccuracy) tick();
        version(CumulativeCycles) ++totalCycles;
        return memoryRead(addr);
    }

    final void write(ushort addr, ubyte val)
    {
        version(CycleAccuracy) tick();
        version(CumulativeCycles) ++totalCycles;
        memoryWrite(addr, val);
    }

    final void peek(ushort addr)
    {
        version(CycleAccuracy) tick();
        version(CumulativeCycles) ++totalCycles;
        version(StrictMemoryAccess) memoryRead(addr);
    }

    final void poke(ushort addr, ubyte val)
    {
        version(CycleAccuracy) tick();
        version(CumulativeCycles) ++totalCycles;
        version(StrictMemoryAccess) memoryWrite(addr, val);
    }

    final ubyte readFinal(ushort addr)
    {
        version(CycleAccuracy)
        {
            finalCycle = true;
            tick();
        }
        version(CumulativeCycles) ticks(++totalCycles);
        return memoryRead(addr);
    }

    final void writeFinal(ushort addr, ubyte val)
    {
        version(CycleAccuracy)
        {
            finalCycle = true;
            tick();
        }
        version(CumulativeCycles) ticks(++totalCycles);
        memoryWrite(addr, val);
    }

    final ushort readWord(ushort addrLo, ushort addrHi)
    {
        ushort word = read(addrLo);
        return word | (read(addrHi) << 8);
    }

    final void push(ubyte val)
    {
        write((STACK_BASE + stackPointer), val);
        --stackPointer;
        /+ TODO: call stack overflow delegate +/
    }

    final void pushWord(ushort val)
    {
        push(val >> 8);
        push(val & 0xFF);
    }

    final ubyte readStack()
    {
        ++stackPointer;
        /+ TODO: call stack underflow delegate +/
        return read(STACK_BASE + stackPointer);
    }

    final ubyte pull()
    {
        peek(STACK_BASE + stackPointer);
        return readStack();
    }

    final ushort pullWord()
    {
        ushort word = pull();
        return word | (readStack() << 8);
    }

    final ubyte readByteOperand()
    {
        return (operand1 = read(programCounter++));
    }

    final ushort readWordOperand()
    {
        operand1 = read(programCounter++);
        operand2 = read(programCounter++);
        return (operand1 | (operand2 << 8));
    }

    ushort* spuriousAddress;
    ushort badAddress, baseAddress, primaryAddress;
    ubyte readVal, writeVal;

    final ushort tryShortcut(bool noShortcut, ushort goodAddress)
    {
        badAddress = (baseAddress & 0xFF00) | cast(ubyte)goodAddress;
        if (noShortcut || (badAddress != goodAddress)) peek(*spuriousAddress);
        return goodAddress;
    }

    final void addrRelative(byte offset)
    {
        peek(programCounter);
        baseAddress = programCounter;
        programCounter = tryShortcut(false, programCounter + offset);
    }
    
    final void addrZeropage()
    {
        primaryAddress = readByteOperand();
    }

    final void addrAbsolute()
    {
        primaryAddress = readWordOperand();
    }

    final void addrZeropageX()
    {
        baseAddress = badAddress = readByteOperand();
        peek(*spuriousAddress);
        primaryAddress = cast(ubyte)(baseAddress + xIndex);
    }

    final void addrZeropageY()
    {
        baseAddress = badAddress = readByteOperand();
        peek(*spuriousAddress);
        primaryAddress = cast(ubyte)(baseAddress + yIndex);
    }

    final void addrIndirectX()
    {
        baseAddress = badAddress = readByteOperand();
        peek(*spuriousAddress);
        ushort vector = cast(ubyte)(baseAddress + xIndex);
        primaryAddress = readWord(vector, cast(ubyte)(vector + 1));
    }

    final void addrAbsoluteX(bool write)
    {
        baseAddress = readWordOperand();
        primaryAddress = tryShortcut(write, baseAddress + xIndex);
    }

    final void addrAbsoluteY(bool write)
    {
        baseAddress = readWordOperand();
        primaryAddress = tryShortcut(write, baseAddress + yIndex);
    }

    final void addrIndirectY(bool write)
    {
        ubyte vector = readByteOperand();
        baseAddress = readWord(vector, cast(ubyte)(vector + 1));
        primaryAddress = tryShortcut(write, baseAddress + yIndex);
    }

    void dec_addWithCarry(ubyte val)
    {
        uint bcdSum = (accumulator & 0x0F) + (val & 0x0F) + flag.carry;

        if (bcdSum >= 10)
            bcdSum = (bcdSum - 10) | 0x10;
        bcdSum += (accumulator & 0xF0) + (val & 0xF0);

        flag.negative_ = bcdSum;
        flag.overflow =
            (!((accumulator ^ val) & 0x80)) && ((val ^ bcdSum) & 0x80);

        if (bcdSum > 0x9f)
            bcdSum += 0x60;

        flag.zero_ = accumulator + val + (flag.carry ? 1 : 0);
        flag.carry = (bcdSum > 0xFF);

        accumulator = bcdSum;
    }

    void dec_subWithCarry(ubyte val)
    {
        uint diff = accumulator - val - (flag.carry ? 0 : 1);

        flag.overflow =
            ((accumulator ^ diff) & 0x80) &&
            ((accumulator ^ val) & 0x80);

        uint al = (accumulator & 0x0F) - (val & 0x0F) -
            (flag.carry ? 0 : 1);
        uint ah = (accumulator >> 4) - (val >> 4);
        if (al & 0x10)
        {
            al -= 6;
            ah--;
        }
        if (ah & 0x10)
            ah -= 6;

        flag.carry = (diff < 0x100);
        flag.zero_ = flag.negative_ = diff;

        accumulator = (ah << 4) + (al & 0x0F);
    }

    final void hex_addWithCarry(ubyte val)
    {
        uint sum = accumulator + val + flag.carry;

        flag.overflow =
            (!((accumulator ^ val) & 0x80)) && ((val ^ sum) & 0x80);
        flag.carry = (sum > 0xFF);

        flag.zero_ = flag.negative_ = (accumulator = sum);
    }

    final void hex_subWithCarry(ubyte val)
    {
        uint diff = accumulator - val - (flag.carry ? 0 : 1);

        flag.overflow =
            ((accumulator ^ diff) & 0x80) &&
            ((accumulator ^ val) & 0x80);
        flag.carry = (diff < 0x100);

        flag.zero_ = flag.negative_ = (accumulator = diff);
    }

    final ubyte compare(ubyte reg, ubyte val)
    {
        flag.carry = (reg >= val);
        return reg - val;
    }

    final void bitTest(ubyte val)
    {
        flag.negative_ = val;
        flag.zero_ = accumulator & val;
        flag.overflow = ((val & 0x40) != 0);
    }

    final ubyte shiftLeft(ubyte val)
    {
        flag.carry = (val > 0x7F);
        return val << 1;
    }

    final ubyte rotateLeft(ubyte val)
    {
        bool oldCarry = flag.carry;
        flag.carry = (val > 0x7F);
        val = (val << 1 | (oldCarry ? 1 : 0));
        return val;
    }

    final ubyte shiftRight(ubyte val)
    {
        flag.carry = ((val & 0x01) != 0);
        return val >> 1;
    }

    final ubyte rotateRight(ubyte val)
    {
        bool oldCarry = flag.carry;
        flag.carry = ((val & 0x01) != 0);
        val = (val >> 1 | (oldCarry ? 0x80 : 0));
        return val;
    }

    final ubyte increment(ubyte val)
    {
        return val + 1;
    }

    final ubyte decrement(ubyte val)
    {
        return val - 1;
    }

    static string SimpleOpcode(string name, string opcode, string action)
    {
        string code = "peek(programCounter);\n";
        version(CumulativeCycles) code ~= "ticks(totalCycles);\n";
        code ~= (action == "") ? "" : (action ~ ";");
        return "override void opcode" ~ opcode ~ "()\n{\n" ~ code ~ "\n}\n";
    }

    static string UpdateNZ(string action)
    {
        return "flag.zero_ = flag.negative_ = (" ~ action ~ ");" ~ "\n";
    }

    static string RegisterOpcode(string name, string opcode, string action)
    {
        string code = "peek(programCounter);\n";
        version(CumulativeCycles) code ~= "ticks(totalCycles);\n";
        return "override void opcode" ~ opcode ~ "()\n{\n" ~
            code ~ UpdateNZ(action) ~ "}\n";
    }

    static string BranchOpcode(string name, string opcode, string action)
    {
        string code = "readByteOperand();\n" ~
            "if (" ~ action ~ ") addrRelative(cast(byte)operand1);\n";
        version(CumulativeCycles) code ~= "ticks(totalCycles);\n";
        return "override void opcode" ~ opcode ~ "()\n{\n" ~ code ~ "}\n";
    }

    static string Type1Address(string name, string rw, int[] opcodes)
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
                case 2:
                    modes ~= "Immediate";
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
                case 6:
                    modes ~= "AbsoluteY(" ~ type ~ ")";
                    break;
                case 7:
                    modes ~= "AbsoluteX(" ~ type ~ ")";
                    break;
            }
            modes ~= "\"]";
            if (op != (opcodes.length - 1)) modes ~= ", ";
            modes ~= "\n";
        }
        return modes ~ "]\n";
    }

    static string Type2Address(string name, string rw, int[] opcodes)
    {
        string type = (rw == "Write") ? "true" : "false";
        string index = (name[2] == 'X') ? "Y" : "X";
        string modes = "[[\"" ~ name ~ "\", \"" ~ rw ~ "\"], \n";
        for (int op = 0; op < opcodes.length; ++op)
        {
            int opcode = opcodes[op];
            modes ~= "[\"" ~ hexByte(opcode) ~ "\", \"";
            switch ((opcode & 0b00011100) >> 2)
            {
                case 0:
                    modes ~= "Immediate";
                    break;
                case 1:
                    modes ~= "Zeropage()";
                    break;
                case 3:
                    modes ~= "Absolute()";
                    break;
                case 5:
                    modes ~= "Zeropage" ~ index ~ "()";
                    break;
                case 7:
                    modes ~= "Absolute" ~ index ~ "(" ~ type ~ ")";
                    break;
            }
            modes ~= "\"]";
            if (op != (opcodes.length - 1)) modes ~= ", ";
            modes ~= "\n";
        }
        return modes ~ "]\n";
    }

    static string Opcode(string[][] details, string action)
    {
        string methods;
        for (int op = 1; op < details.length; ++op)
        {
            methods ~= "override void opcode" ~ details[op][0] ~ "()\n{\n";
            if (details[op][1] == "Immediate")
            {
                methods ~= "primaryAddress = programCounter++;\n" ~
                    action ~ "operand1 = readVal;\n";
            }
            else
            {
                methods ~= "addr" ~ details[op][1] ~ ";\n" ~ action;
            }
            methods ~= "}\n";
        }
        return methods;
    }

    static string Read(string action)
    {
        return UpdateNZ(action ~ " (readVal = readFinal(primaryAddress))");
    }

    static string Decimal(string action)
    {
        string code = action ~ "(readVal = readFinal(primaryAddress));\n";
        return "if (flag.decimal) dec_" ~ code ~
            "else hex_" ~ code;
    }

    static string Compare(string action)
    {
        return UpdateNZ("compare(" ~ action ~
                ", (readVal = readFinal(primaryAddress)))");
    }

    static string Write(string action)
    {
        return "writeFinal(primaryAddress, " ~ action ~ ");\n";
    }

    static string BitTest()
    {
        return "bitTest(readVal = readFinal(primaryAddress));\n";
    }

    mixin(SimpleOpcode("CLC", "18", "flag.carry = false"));
    mixin(SimpleOpcode("SEC", "38", "flag.carry = true"));
    mixin(SimpleOpcode("CLI", "58", "flag.interrupt = false"));
    mixin(SimpleOpcode("SEI", "78", "flag.interrupt = true"));
    mixin(SimpleOpcode("CLV", "B8", "flag.overflow = false"));
    mixin(SimpleOpcode("CLD", "D8", "flag.decimal = false"));
    mixin(SimpleOpcode("SED", "F8", "flag.decimal = true"));

    mixin(SimpleOpcode("NOP", "EA", ""));

    mixin(SimpleOpcode("PHP", "08", "push(flag.toByte())"));
    mixin(SimpleOpcode("PLP", "28", "flag.fromByte(pull())"));
    mixin(SimpleOpcode("PHA", "48", "push(accumulator)"));
    mixin(SimpleOpcode("TXS", "9A", "stackPointer = xIndex"));

    mixin(RegisterOpcode("PLA", "68", "accumulator = pull()"));
    mixin(RegisterOpcode("TSX", "BA", "xIndex = stackPointer"));

    mixin(RegisterOpcode("TAX", "AA", "xIndex = accumulator"));
    mixin(RegisterOpcode("TXA", "8A", "accumulator = xIndex"));
    mixin(RegisterOpcode("DEX", "CA", "xIndex -= 1"));
    mixin(RegisterOpcode("INX", "E8", "xIndex += 1"));
    mixin(RegisterOpcode("TAY", "A8", "yIndex = accumulator"));
    mixin(RegisterOpcode("TYA", "98", "accumulator = yIndex"));
    mixin(RegisterOpcode("DEY", "88", "yIndex -= 1"));
    mixin(RegisterOpcode("INY", "C8", "yIndex += 1"));

    mixin(BranchOpcode("BPL", "10", "flag.negative_ < 0x80"));
    mixin(BranchOpcode("BMI", "30", "flag.negative_ > 0x7F"));
    mixin(BranchOpcode("BVC", "50", "!flag.overflow"));
    mixin(BranchOpcode("BVS", "70", "flag.overflow"));
    mixin(BranchOpcode("BCC", "90", "!flag.carry"));
    mixin(BranchOpcode("BCS", "B0", "flag.carry"));
    mixin(BranchOpcode("BNE", "D0", "flag.zero_ != 0"));
    mixin(BranchOpcode("BEQ", "F0", "flag.zero_ == 0"));

    mixin(RegisterOpcode("ASL A", "0A",
                "accumulator = shiftLeft(accumulator)"));
    mixin(RegisterOpcode("ROL A", "2A",
                "accumulator = rotateLeft(accumulator)"));
    mixin(RegisterOpcode("LSR A", "4A",
                "accumulator = shiftRight(accumulator)"));
    mixin(RegisterOpcode("ROR A", "6A",
                "accumulator = rotateRight(accumulator)"));

    mixin(Opcode(mixin(Type1Address(
        "LDA", "Read", [0xA1, 0xA5, 0xA9, 0xAD, 0xB1, 0xB5, 0xB9, 0xBD])),
        Read("accumulator =")));
    mixin(Opcode(mixin(Type1Address(
        "ORA", "Read", [0x01, 0x05, 0x09, 0x0D, 0x11, 0x15, 0x19, 0x1D])),
        Read("accumulator |=")));
    mixin(Opcode(mixin(Type1Address(
        "AND", "Read", [0x21, 0x25, 0x29, 0x2D, 0x31, 0x35, 0x39, 0x3D])),
        Read("accumulator &=")));
    mixin(Opcode(mixin(Type1Address(
        "EOR", "Read", [0x41, 0x45, 0x49, 0x4D, 0x51, 0x55, 0x59, 0x5D])),
        Read("accumulator ^=")));
    mixin(Opcode(mixin(Type1Address(
        "ADC", "Read", [0x61, 0x65, 0x69, 0x6D, 0x71, 0x75, 0x79, 0x7D])),
        Decimal("addWithCarry")));
    mixin(Opcode(mixin(Type1Address(
        "SBC", "Read", [0xE1, 0xE5, 0xE9, 0xED, 0xF1, 0xF5, 0xF9, 0xFD])),
        Decimal("subWithCarry")));
    mixin(Opcode(mixin(Type1Address(
        "CMP", "Read", [0xC1, 0xC5, 0xC9, 0xCD, 0xD1, 0xD5, 0xD9, 0xDD])),
        Compare("accumulator")));
    mixin(Opcode(mixin(Type1Address(
        "STA", "Write", [0x81, 0x85, 0x8D, 0x91, 0x95, 0x99, 0x9D])),
        Write("accumulator")));

    mixin(Opcode(mixin(Type2Address(
        "LDX", "Read", [0xA2, 0xA6, 0xAE, 0xB6, 0xBE])),
        Read("xIndex =")));
    mixin(Opcode(mixin(Type2Address(
        "LDY", "Read", [0xA0, 0xA4, 0xAC, 0xB4, 0xBC])),
        Read("yIndex =")));
    mixin(Opcode(mixin(Type2Address(
        "CPX", "Read", [0xE0, 0xE4, 0xEC])),
        Compare("xIndex")));
    mixin(Opcode(mixin(Type2Address(
        "CPY", "Read", [0xC0, 0xC4, 0xCC])),
        Compare("yIndex")));
    mixin(Opcode(mixin(Type2Address(
        "STX", "Write", [0x86, 0x8E, 0x96])),
        Write("xIndex")));
    mixin(Opcode(mixin(Type2Address(
        "STY", "Write", [0x84, 0x8C, 0x94])),
        Write("yIndex")));
    mixin(Opcode(mixin(Type2Address(
        "BIT", "Read", [0x24, 0x2C])),
        BitTest()));

    /* BRK */
    final override void opcode00()
    {
        peek(programCounter);
        ++programCounter;
        doInterrupt(IRQ_VECTOR, flag.toByte());
    }

    /* JSR */
    final override void opcode20()
    {
        ushort finalAddress = (operand1 = read(programCounter++));

        peek(STACK_BASE + stackPointer);
        pushWord(programCounter);

        finalAddress |= ((operand2 = read(programCounter)) << 8);
        version(CumulativeCycles) ticks(totalCycles);
        programCounter = finalAddress;
    }

    /* RTI */
    final override void opcode40()
    {
        peek(programCounter);
        flag.fromByte(pull());
        programCounter = pullWord();
        version(CumulativeCycles) ticks(totalCycles);
    }

    /* JMP $$$$ */
    final override void opcode4C()
    {
        programCounter = readWordOperand();
        version(CumulativeCycles) ticks(totalCycles);
    }

    /* RTS */
    final override void opcode60()
    {
        peek(programCounter);
        programCounter = pullWord();
        peek(programCounter);
        version(CumulativeCycles) ticks(totalCycles);
        ++programCounter;
    }
}
