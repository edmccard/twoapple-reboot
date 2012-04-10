/+
 + cpu6502.d
 +
 + Copyright: 2012 Ed McCardell, 2007 Gerald Stocker
 +
 + This file is part of twoapple-reboot.
 +
 + twoapple-reboot is free software; you can redistribute it and/or modify
 + it under the terms of the GNU General Public License as published by
 + the Free Software Foundation; either version 2 of the License, or
 + (at your option) any later version.
 +
 + twoapple-reboot is distributed in the hope that it will be useful,
 + but WITHOUT ANY WARRANTY; without even the implied warranty of
 + MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 + GNU General Public License for more details.
 +
 + You should have received a copy of the GNU General Public License
 + along with twoapple-reboot; if not, write to the Free Software
 + Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 +/


module cpu6502;


import std.array, std.format;


enum Strict : bool
{
    no, yes
}

enum Cumulative : bool
{
    no, yes
}


template is6502(T)
{
    enum is6502 = __traits(getMember, T, "_chip") == "6502";
}

template is65C02(T)
{
    enum is65C02 = __traits(getMember, T, "_chip") == "65C02";
}


// The following versions are mutually exclusive.

// OpDelegates: each opcode is a method of the Cpu class.
version(OpDelegates)
{
    enum versionCheck = 1;
    enum opArray = true;
}

// OpFunctions: each opcode is a free function with a Cpu argument.
version(OpFunctions)
{
    enum versionCheck = 2;
    enum opArray = true;

    // With free functions, strict and cumulative need to be set by
    // version.
    version(Strict)
        enum vStrict = true;
    else
        enum vStrict = false;
    version(Cumulative)
        enum vCumulative = true;
    else
        enum vCumulative = false;
}

// OpSwitch: each opcode is inlined in a 256-case switch.
version(OpSwitch)
{
    enum versionCheck = 3;
    enum opArray = false;
}

/*
 * OpNestedSwitch: each opcode is inlined in a nested switch.
 *
 * (The outer one switches on the high byte, with each case switching
 * on the low byte.)
 */
version(OpNestedSwitch)
{
    enum versionCheck = 4;
    enum opArray = false;
}


// At least one of the previous versions must be specified.
static if (!__traits(compiles, { bool b = opArray; })) enum opArray = 0;
static assert (versionCheck);


final class Cpu(string chip, bool strict, bool cumulative)
{
    static assert(chip == "6502" || chip == "65C02" || chip == "65c02");
    enum _isCpu = true;
    enum _chip = (chip == "6502" ? "6502" : "65C02");
    enum _isStrict = strict;
    enum _isCumulative = cumulative;

    struct _Mem
    {
        // Reads a value from system memory.
        ubyte delegate(ushort addr) read;

        // Writes a value to system memory.
        void delegate(ushort addr, ubyte val) write;
    }
    _Mem memory;

    struct _Clock
    {
        static if (cumulative)
            /*
             * Updates the number of cycles executed. Called just
             * prior to the final read/write action of each opcode.
             */
            void delegate(int cycles) tick;
        else
            /*
             * Increments the number of cycles executed. Called prior
             * to each read/write action.
             */
            void delegate() tick;
    }
    _Clock clock;

    ubyte A, X, Y, S;
    ushort PC;

    // The status flags.
    ubyte N, Z;
    bool V, D, I, C;

    static if (opArray) { mixin(OpArrayDef()); }

    // TODO: other methods for stopping cpu
    bool keepRunning;

    this()
    {
        static if (opArray) mixin(OpArrayInit());
    }

    final void statusFromByte(ubyte p)
    {
        N = p;
        V = ((p & 0x40) != 0);
        D = ((p & 0x08) != 0);
        I = ((p & 0x04) != 0);
        Z = ((p & 0x02) ? 0 : 1);
        C = ((p & 0x01) != 0);
    }

    final ubyte statusToByte()
    {
        return (C ? 0x01 : 0) |
               ((Z == 0) ? 0x02 : 0) |
               (I ? 0x04 : 0) |
               (D ? 0x08 : 0) |
               0x30 | // break and reserved both set
               (V ? 0x40 : 0) |
               (N & 0x80);
    }

    final void run(bool continuous)
    {
        keepRunning = continuous;
        // TODO debugging info?
        ubyte opcode;
        static if (!opArray)
        {
            static if (cumulative) { int cycles; }
            ubyte op1;
            ushort address, base;
            ubyte data;
        }
        do {
            static if (cumulative && !opArray)
                cycles = 1;
                // XXX figure out final cycle stuff
            static if (!cumulative)
                clock.tick();
            // XXX check signals, NMI/IRQ delays, etc.
            opcode = memory.read(PC++);
            mixin(OpExecute(_chip, strict, cumulative));
        } while (keepRunning);
    }

    version(OpDelegates) mixin (OpBodies(_chip, strict, cumulative));
}


enum ushort IRQ_VECTOR = 0xFFFE;


private:

string OpArrayDef()
{
    version(OpDelegates)
        return q{void delegate()[256] opcodes;};
    else version(OpFunctions)
        return q{void function(typeof(this))[256] opcodes;};
    else
        return "";
}

string OpArrayInit()
{
    static if (!opArray) return "";
    else
    {
        string ret;
        foreach (op; 0..256)
        {
            version(OpDelegates)
                ret ~= Fmt("opcodes[0x#] = &opcode_#;\n",
                           Hex2(op), Hex2(op));
            version(OpFunctions)
                ret ~= Fmt("opcodes[0x#] = &opcode_#!(typeof(this));\n",
                           Hex2(op), Hex2(op));
        }
        return ret;
    }
}

string OpBodies(string chip, bool strict, bool cumulative)
{
    static if (!opArray) return "";
    else
    {
        string ret;
        foreach (op; 0..256)
        {
            version(OpDelegates)
                ret ~= "final void opcode_" ~ Hex2(op) ~ "()\n{\n" ~
                       If!(cumulative)("int cycles = 1;\n") ~
                       OpBody(op, chip, strict, cumulative) ~ "}\n";
            version(OpFunctions)
                ret ~= "void opcode_" ~ Hex2(op) ~
                       "(T)(T cpu) if (is" ~ chip ~ "!T)\n{\n" ~
                       If!(cumulative)("int cycles = 1;\n") ~
                       OpBody(op, chip, strict, cumulative) ~ "}\n";
        }
/+
        foreach (op; 13..256)
            version(OpDelegates)
                ret ~= "final void opcode_" ~ Hex2(op) ~ "()\n{\n" ~
                       If!(cumulative)("int cycles = 1;\n") ~
                       "" ~ "}\n";
            version(OpFunctions)
                ret ~= "void opcode_" ~ Hex2(op) ~
                       "(T)(T cpu) if (is" ~ chip ~ "!T)\n{\n" ~
                       If!(cumulative)("int cycles = 1;\n") ~
                       "" ~ "}\n";
+/
        return ret;
    }
}

string OpExecute(string chip, bool strict, bool cumulative)
{
    version(OpDelegates)
        return q{opcodes[opcode]();};
    version(OpFunctions)
        return q{opcodes[opcode](this);};
    version(OpSwitch)
        return Switch256(chip, strict, cumulative);
    version(OpNestedSwitch)
        return Switch16x16(chip, strict, cumulative);
}

string Switch256(string chip, bool strict, bool cumulative)
{
    string ret = "final switch (opcode)\n{\n";
    foreach (op; 0..256)
        ret ~= "case 0x" ~ Hex2(op) ~ ":\n" ~
               OpBody(op, chip, strict, cumulative) ~ "break;\n";
    return ret ~ "}\n";
}

string Switch16x16(string chip, bool strict, bool cumulative)
{
    string ret = "final switch (opcode & 0xF0)\n{\n";
    foreach (opHi; 0..16)
    {
        ret ~= "case 0x" ~ Hex1(opHi) ~ "0:\n" ~
               "final switch(opcode & 0x0F)\n{\n";
        foreach (opLo; 0..16)
        {
            int op = opLo | (opHi << 4);
            ret ~= "case 0x0" ~ Hex1(opLo) ~ ":\n" ~
                   OpBody(op, chip, strict, cumulative) ~
                   "break;\n";
        }
        ret ~= "}\nbreak;\n";
    }
    return ret ~ "}\n";
}


string OpBody(int op, string chip, bool s, bool c)
{
    bool nmos = (chip == "6502");
    final switch (opName(op, chip))
    {
        case "BRK":
            return Break(s, c) ~
                   Done(c);
        case "RTI":
            return "";
        case "JSR":
            return JumpSub(s, c) ~
                   Done(c);
        case "RTS":
            return RetSub(s, c) ~
                   Done(c);
        case "JMP":
            return Jump(op, chip, s, c) ~
                   Done(c);
        case "KIL":
            return Attr("PC") ~ "--;\n" ~
                   Done(c);
        case "BPL":
            return Branch("!(" ~ Attr("N") ~ " & 0x80)", nmos, s, c) ~
                   Done(c);
        case "BMI":
            return Branch("(" ~ Attr("N") ~ " & 0x80)", nmos, s, c) ~
                   Done(c);
        case "BVC":
            return Branch("!" ~ Attr("V"), nmos, s, c) ~
                   Done(c);
        case "BVS":
            return Branch(Attr("V"), nmos, s, c) ~
                   Done(c);
        case "BRA":
            return Branch("true", nmos, s, c) ~
                   Done(c);
        case "BCC":
            return Branch("!" ~ Attr("C"), nmos, s, c) ~
                   Done(c);
        case "BCS":
            return Branch(Attr("C"), nmos, s, c) ~
                   Done(c);
        case "BNE":
            return Branch(Attr("Z"), nmos, s, c) ~
                   Done(c);
        case "BEQ":
            return Branch("!" ~ Attr("Z"), nmos, s, c) ~
                   Done(c);
        case "CLC":
            return AddrIMP(s, c) ~
                   ClearFlag("C") ~
                   Done(c);
        case "SEC":
            return AddrIMP(s, c) ~
                   SetFlag("C") ~
                   Done(c);
        case "CLI":
            return AddrIMP(s, c) ~
                   ClearFlag("I") ~
                   Done(c);
        case "SEI":
            return AddrIMP(s, c) ~
                   SetFlag("I") ~
                   Done(c);
        case "CLV":
            return AddrIMP(s, c) ~
                   ClearFlag("V") ~
                   Done(c);
        case "CLD":
            return AddrIMP(s, c) ~
                   ClearFlag("D") ~
                   Done(c);
        case "SED":
            return AddrIMP(s, c) ~
                   SetFlag("D") ~
                   Done(c);
        case "NOP":
            return Nop(op, chip, s, c) ~
                   Done(c);
        case "TAX":
            return Transfer(op, "A", "X", s, c) ~
                   Done(c);
        case "TXA":
            return Transfer(op, "X", "A", s, c) ~
                   Done(c);
        case "TAY":
            return Transfer(op, "A", "Y", s, c) ~
                   Done(c);
        case "TYA":
            return Transfer(op, "Y", "A", s, c) ~
                   Done(c);
        case "TSX":
            return Transfer(op, "S", "X", s, c) ~
                   Done(c);
        case "TXS":
            return Transfer(op, "X", "S", s, c) ~
                   Done(c);
        case "DEX":
            return AddrIMP(s, c) ~
                   Dec(Attr("X")) ~
                   Done(c);
        case "DEY":
            return AddrIMP(s, c) ~
                   Dec(Attr("Y")) ~
                   Done(c);
        case "INX":
            return AddrIMP(s, c) ~
                   Inc(Attr("X")) ~
                   Done(c);
        case "INY":
            return AddrIMP(s, c) ~
                   Inc(Attr("Y")) ~
                   Done(c);
        case "PHP":
            return AddrIMP(s, c) ~
                   Push(Attr("statusToByte()"), s, c) ~
                   Done(c);
        case "PLP":
            return AddrIMP(s, c) ~
                   PullStatus(s, c) ~
                   Done(c);
        case "PLA":
            return PullReg("A", s, c) ~
                   Done(c);
        case "PLX":
            return PullReg("X", s, c) ~
                   Done(c);
        case "PLY":
            return PullReg("Y", s, c) ~
                   Done(c);
        case "PHA":
            return PushReg("A", s, c) ~
                   Done(c);
        case "PHX":
            return PushReg("X", s, c) ~
                   Done(c);
        case "PHY":
            return PushReg("Y", s, c) ~
                   Done(c);
        case "LDA":
            return Load(op, "A", chip, s, c) ~
                   Done(c);
        case "LDX":
            return Load(op, "X", chip, s, c) ~
                   Done(c);
        case "LDY":
            return Load(op, "Y", chip, s, c) ~
                   Done(c);
        case "STA":
            return Store(op, "A", chip, s, c) ~
                   Done(c);
        case "STX":
            return Store(op, "X", chip, s, c) ~
                   Done(c);
        case "STY":
            return Store(op, "Y", chip, s, c) ~
                   Done(c);
        case "STZ":
            return "";
        case "BIT":
            return Bit(op, chip, s, c) ~
                   Done(c);
        case "CMP":
            return Compare(op, "A", chip, s, c) ~
                   Done(c);
        case "CPX":
            return Compare(op, "X", chip, s, c) ~
                   Done(c);
        case "CPY":
            return Compare(op, "Y", chip, s, c) ~
                   Done(c);
        case "ORA":
            return Logic(op, "|=", chip, s, c) ~
                   Done(c);
        case "AND":
            return Logic(op, "&=", chip, s, c) ~
                   Done(c);
        case "EOR":
            return Logic(op, "^=", chip, s, c) ~
                   Done(c);
        case "ADC":
            return Add(op, chip, s, c) ~
                   Done(c);
        case "SBC":
            return Sub(op, chip, s, c) ~
                   Done(c);
        case "ASL":
            if (op == 0x0a)
                return AddrIMP(s, c) ~ ShiftLeft(Attr("A")) ~ Done(c);
            else
                return RMW(op, ShiftLeft("data"), chip, s, c) ~ Done(c);
        case "ROL":
            if (op == 0x2a)
                return AddrIMP(s, c) ~ RotateLeft(Attr("A")) ~ Done(c);
            else
                return RMW(op, RotateLeft("data"), chip, s, c) ~ Done(c);
        case "LSR":
            if (op == 0x4a)
                return AddrIMP(s, c) ~ ShiftRight(Attr("A")) ~ Done(c);
            else
                return RMW(op, ShiftRight("data"), chip, s, c) ~ Done(c);
        case "ROR":
            if (op == 0x6a)
                return AddrIMP(s, c) ~ ShiftRight(Attr("A")) ~ Done(c);
            else
                return RMW(op, RotateRight("data"), chip, s, c) ~ Done(c);
        case "INC":
            if (op == 0x1a)
                return AddrIMP(s, c) ~ Inc(Attr("A")) ~ Done(c);
            else
                return RMW(op, Inc("data"), chip, s, c) ~ Done(c);
        case "DEC":
            if (op == 0x3a)
                return AddrIMP(s, c) ~ Dec(Attr("A")) ~ Done(c);
            else
                return RMW(op, Dec("data"), chip, s, c) ~ Done(c);
        case "TRB":
            return "";
        case "TSB":
            return "";
        case "LAS":
            return "";
        case "LAX":
            return ""; // address modes
        case "SAX":
            return "";
        case "ANC":
            return "";
        case "ALR":
            return "";
        case "ARR":
            return "";
        case "AXS":
            return "";
        case "AHX":
            return "";
        case "SHY":
            return "";
        case "SHX":
            return "";
        case "TAS":
            return "";
        case "XAA":
            return "";
        case "SLO":
            return "";
        case "RLA":
            return "";
        case "SRE":
            return "";
        case "RRA":
            return "";
        case "DCP":
            return "";
        case "ISC":
            return "";
    }
}


string AddrIMM(bool s, bool c)
{
     return Local("ushort") ~ "address = " ~ Attr("PC") ~ "++;\n";
}

string AddrIMP(bool s, bool c)
{
    return Peek(Attr("PC"), s, c);
}

string AddrZP(bool s, bool c)
{
    return ReadOp(Local("ushort", "address"), c);
}

string AddrZPXY(string reg, string chip, bool s, bool c)
{
    bool nmos = (chip == "6502");

    return ReadOp(Local("ushort", "base"), c) ~
           If!(nmos)(
               Peek("base", s, c),
               Peek(Attr("PC"), s, c)) ~
           Local("ushort") ~
           "address = cast(ubyte)(base + " ~ Attr(reg) ~ ");\n";
}

string AddrIZX(string chip, bool s, bool c)
{
    bool nmos = (chip == "6502");
    return ReadOp(Local("ushort", "base"), c) ~
           If!(nmos)(
               Peek("base", s, c),
               Peek(Attr("PC"), s, c)) ~
           ReadWordZP("ushort", "address", "base + " ~ Attr("X"), c);
}

string AddrIZY(int op, string chip, bool s, bool c)
{
    int exCyc = opExCyc(op, chip);
    bool nmos = (chip == "6502");

    return ReadOp("ubyte vector", c) ~
           ReadWordZP("ushort", "base", "vector", c) ~
           Local("ushort") ~
           "address = cast(ushort)(base + " ~ Attr("Y") ~ ");\n" ~
           CheckShortcut("address", Attr("PC"),
                         exCyc, nmos, s, c);
}

string AddrABS(bool s, bool c)
{
    return ReadWordOp("ushort", "address", c);
}

string AddrABXY(int op, string reg, string chip, bool s, bool c)
{
    bool nmos = (chip == "6502");
    int exCyc = opExCyc(op, chip);
    string IDX = Attr(reg);

    return ReadWordOp("ushort", "base", c) ~
           Local("ushort") ~ "address = cast(ushort)(base + " ~ IDX ~ ");\n" ~
           CheckShortcut("address", Attr("PC"), exCyc, nmos, s, c);
}

string AddrZPI(bool s, bool c)
{
    return ReadOp(Local("ushort", "base"), c) ~
           ReadWordZP("ushort", "address", "base", c);
}

string Branch(string check, bool nmos, bool s, bool c)
{
    string PC = Attr("PC");
    return ReadOp(Local("ubyte", "op1"), c) ~
           "if (" ~ check ~ ")\n{\n" ~
               Peek(PC, s, c) ~
               Local("ushort", "base") ~ " = " ~ PC ~ ";\n" ~
               PC ~ " = cast(ushort)(" ~ PC ~ " + cast(byte)op1);\n" ~
               CheckShortcut(Attr("PC"), "base", 0, nmos, s, c) ~
           "}\n";
}

string CheckShortcut(string addr, string pc, int exCyc, bool nmos, bool s,
                     bool c)
{
    return "ushort guess = (base & 0xFF00) | cast(ubyte)" ~ addr ~ ";\n" ~
           "if (guess != " ~ addr ~ ")\n{\n" ~
               If!(nmos)(Peek("guess", s, c),
                         Peek(pc, s, c)) ~
           "}\n" ~
           If!(exCyc)("else\n{\n" ~ Peek("address", s, c) ~ "}\n");
}


string Nop(int op, string chip, bool s, bool c)
{
    auto mode = opMode(op, chip);
    if (mode == IMP || mode == NP1 || mode == NP8)
        return Address(op, chip, s, c);
    else
        return Address(op, chip, s, c) ~
               Peek("address", true, c);
}


string Break(bool s, bool c)
{
    return AddrIMP(s, c) ~
           IncPC() ~
           PushPC(s, c) ~
           Push(Attr("statusToByte()"), s, c) ~
           SetFlag("I") ~
           ReadWord(Attr("PC"), "IRQ_VECTOR", c);
}


string RetSub(bool s, bool c)
{
    return AddrIMP(s, c) ~
           PullPC(s, c) ~
           Peek(Attr("PC"), s, c) ~
           IncPC();
}


string JumpSub(bool s, bool c)
{
    string PC = Attr("PC");

    return ReadOp(Local("ushort", "address"), c) ~
           Peek("0x0100 + " ~ Attr("S"), s, c) ~
           PushPC(s, c) ~
           PreAccess(c) ~ "address |= (" ~ ReadRaw(PC ~ "++") ~ " << 8);\n" ~
           PC ~ " = address;\n";
}


string Jump(int op, string chip, bool s, bool c)
{
    bool nmos = (chip == "6502");
    string PC = Attr("PC");

    if (op == 0x4c)
        return Address(op, chip, s, c) ~
               PC ~ " = address;\n";
    else if (op == 0x6c)
        return ReadWordOp("ushort", "base", c) ~
               If!(nmos)(
                   "",
                   Peek(PC, s, c)) ~
               ReadWordBasic(PC, "base",
                             If!(nmos)(
                                 "(base & 0xFF00) | cast(ubyte)(base + 1)",
                                 "cast(ushort)(base + 1)"), c);
    else if (op == 0x7c)
        return ReadWordOp("ushort", "base",  c) ~
               Peek(PC, s, c) ~
               ReadWord(PC, "cast(ushort)(base + " ~ Attr("X") ~ ")", c);
    return "";
}


string ReadInto(string var, string action, string addr, bool c)
{
    return PreAccess(c) ~
           var ~ " " ~ action ~ " " ~ ReadRaw("(" ~ addr ~ ")") ~ ";\n";
}

string ReadInto(string var, string addr, bool c)
{
    return ReadInto(var, "=", addr, c);
}

string ReadOp(string var, bool c)
{
    return ReadInto(var, Attr("PC") ~ "++", c);
}

string ReadRaw(string addr)
{
    return Attr("memory") ~ ".read(" ~ addr ~")";
}

string ReadWordBasic(string type, string var, string addr1, string addr2,
                     bool c)
{
    return PreAccess(c) ~
           Local(type, var) ~ " = " ~ ReadRaw(addr1) ~ ";\n" ~
           PreAccess(c) ~
           var ~ " |= ((" ~ ReadRaw(addr2) ~ ") << 8);\n";
}

string ReadWordBasic(string var, string addr1, string addr2, bool c)
{
    return ReadWordBasic("", var, addr1, addr2, c);
}

string ReadWord(string type, string var, string addr, bool c)
{
    return ReadWordBasic(type, var, addr, "cast(ushort)(" ~ addr ~ " + 1)", c);
}

string ReadWord(string var, string addr, bool c)
{
    return ReadWord("", var, addr, c);
}

string ReadWordZP(string type, string var, string addr, bool c)
{
    return ReadWordBasic(type, var, "cast(ubyte)( " ~ addr ~ ")",
                                    "cast(ubyte)(" ~ addr ~ " + 1)", c);
}

string ReadWordZP(string var, string addr, bool c)
{
    return ReadWordZP("", var, addr, c);
}

string ReadWordOp(string type, string var, bool c)
{
    string PC = Attr("PC");

    return ReadWordBasic(type, var, PC ~ "++", PC ~ "++", c);
}

string ReadWordOp(string var, bool c)
{
    return ReadWordOp("", var, c);
}


string Local(string type)
{
    version(OpSwitch)
        return "";
    else version(OpNestedSwitch)
        return "";
    else
        return type ~ " ";
}

string Local(string type, string var)
{
    version(OpSwitch)
        return var;
    else version(OpNestedSwitch)
        return var;
    else
        return type ~ " " ~ var;
}


string Transfer(int op, string source, string dest, bool s, bool c)
{
    return AddrIMP(s, c) ~
           Attr(dest) ~ " = " ~ Attr(source) ~ ";\n" ~
           ((op != 0x9a) ? SetNZ(Attr(dest)) : "");
}


string PullReg(string reg, bool s, bool c)
{
    return AddrIMP(s, c) ~
           PullInto(Attr(reg), s, c) ~
           SetNZ(Attr(reg));
}


string PushReg(string reg, bool s, bool c)
{
    return AddrIMP(s, c) ~
           Push(Attr(reg), s, c);
}


string Load(int op, string reg, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           ReadInto(Attr(reg), "address", c) ~
           SetNZ(Attr(reg));
}


string Store(int op, string reg, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           Write("address", Attr(reg), c);
}


string Compare(int op, string reg, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           ReadInto(Local("ubyte", "data"), "address", c) ~
           UpdateFlag("C", Attr(reg) ~ " >= data") ~
           SetNZ("cast(ubyte)(" ~ Attr(reg) ~ " - data)");
}


string Bit(int op, string chip, bool s, bool c)
{
    bool notImm = (opMode(op, chip) != IMM);

    return Address(op, chip, s, c) ~
           ReadInto(Local("ubyte", "data"), "address", c) ~
           If!(notImm)(
               Attr("N") ~ " = data;\n" ~
               Attr("V") ~ " = ((data & 0x40) != 0);\n") ~
           Attr("Z") ~ " = (" ~ Attr("A") ~ " & data);\n";
}


string Logic(int op, string action, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           ReadInto(Attr("A"), action, "address", c) ~
           SetNZ(Attr("A"));
}


string Add(int op, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           ReadInto(Local("ubyte", "data"), "address", c) ~
           "if (" ~ Attr("D") ~ ")\n{\n" ~
               DecAdd(chip, s, c) ~
           "}\nelse\n{\n" ~
               HexAdd(chip, s, c) ~
           "}\n";
}

string HexAdd(string chip, bool s, bool c)
{
    string A = Attr("A"), C = Attr("C");

    return "uint sum = " ~ A ~ " + data + " ~ C ~ ";\n" ~
           Attr("V") ~
           " = (!((" ~ A ~ " ^ data) & 0x80)) && ((data ^ sum) & 0x80);\n" ~
           C ~ " = (sum > 0xFF);\n" ~
           SetNZ(A ~ " = cast(ubyte)sum");
}

string DecAdd(string chip, bool s, bool c)
{
    bool cmos = (chip != "6502");
    string A = Attr("A"), C = Attr("C");

    return "int a = " ~ A ~ ";\n" ~
           "int al = (a & 0x0F) + (data & 0x0F) + " ~ C ~ ";\n" ~
           "if (al >= 0x0A)\n" ~
               "al = ((al + 0x06) & 0x0F) + 0x10;\n" ~
           "a = (a & 0xF0) + (data & 0xF0) + al;\n" ~
           If!(cmos)("",
               Attr("N") ~ " = cast(ubyte)a;\n" ~
               Attr("Z") ~ " = cast(ubyte)(" ~ A ~ " + data + " ~ C ~ ");\n") ~
           Attr("V") ~
           " = (!((" ~ A ~ " ^ data) & 0x80)) && ((data ^ a) & 0x80);\n" ~
           "if (a >= 0xA0)\n" ~
               "a = a + 0x60;\n" ~
           C ~ " = (a >= 0x100);\n" ~
           If!(cmos)(
               SetNZ(A ~ " = cast(ubyte)a") ~ Peek(Attr("PC"), s, c),
               A ~ " = cast(ubyte)a;\n");
}


string Sub(int op, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           ReadInto(Local("ubyte", "data"), "address", c) ~
           "if (" ~ Attr("D") ~ ")\n{\n" ~
               DecSub(chip, s, c) ~
           "}\nelse\n{\n" ~
               HexSub(chip, s, c) ~
           "}\n";
}

string HexSub(string chip, bool s, bool c)
{
    string A = Attr("A"), C = Attr("C");

    return "uint diff = " ~ A ~ " - data - !" ~ C ~ ";\n" ~
           Attr("V") ~
           " = ((" ~ A ~ " ^ diff) & 0x80) && ((" ~ A ~ " ^ data) & 0x80);\n" ~
           C ~ " = (diff < 0x100);\n" ~
           SetNZ(A ~ " = cast(ubyte)diff");
}

string DecSub(string chip, bool s, bool c)
{
    return (chip == "6502" ? DecSubNMOS(s, c) : DecSubCMOS(s, c));
}

string DecSubNMOS(bool s, bool c)
{
    string A = Attr("A"), C = Attr("C");

    return "int a = " ~ A ~ ";\n" ~
           "int al = (a & 0x0F) - (data & 0x0F) - !" ~ C ~ ";\n" ~
           "if (al < 0)\n" ~
               "al = ((al - 0x06) & 0x0F) - 0x10;\n" ~
           "a = (a & 0xF0) - (data & 0xF0) + al;\n" ~
           "if (a < 0)\n" ~
               "a = a - 0x60;\n" ~
           "uint diff = " ~ A ~ " - data - !" ~ C ~ ";\n" ~
           Attr("V") ~
           " = ((" ~ A ~ " ^ diff) & 0x80) && ((" ~ A ~ " ^ data) & 0x80);\n" ~
           C ~ " = (diff < 0x100);\n" ~
           SetNZ("cast(ubyte)diff") ~
           A ~ " = cast(ubyte)a;\n";
}

string DecSubCMOS(bool s, bool c)
{
    string A = Attr("A"), C = Attr("C");

    return "int a = " ~ A ~ ";\n" ~
           "int al = (a & 0x0F) - (data & 0x0F) - !" ~ C ~ ";\n" ~
           "a = a - data - !" ~ C ~ ";\n" ~
           "if (a < 0) a = a - 0x60;\n" ~
           "if (al < 0) a = a - 0x06;\n" ~
           "uint diff = " ~ A ~ " - data - !" ~ C ~ ";\n" ~
           Attr("V") ~
           " = ((" ~ A ~ " ^ diff) & 0x80) && ((" ~ A ~ " ^ data) & 0x80);\n" ~
           C ~ " = (diff < 0x100);\n" ~
           Peek(Attr("PC"), s, c) ~
           SetNZ(A ~ " = cast(ubyte)a");
}


string Inc(string val)
{
    return val ~ "++;\n" ~
           SetNZ(val);
}


string Dec(string val)
{
    return val ~ "--;\n" ~
           SetNZ(val);
}


string ShiftLeft(string val)
{
    return Attr("C") ~ " = (" ~ val ~ " > 0x7F);\n" ~
           SetNZ(val ~ " = cast(ubyte)(" ~ val ~ " << 1)");
}

string RotateLeft(string val)
{
    string C = Attr("C");

    return "auto oldC = " ~ C ~ ";\n" ~
            C ~ " = (" ~ val ~ " > 0x7f);\n" ~
            SetNZ(val ~ " = cast(ubyte)(" ~ val ~ " << 1 | (oldC ? 1 : 0))");
}

string ShiftRight(string val)
{
    return Attr("C") ~ " = ((" ~ val ~ " & 0x01) != 0);\n" ~
           SetNZ(val ~ " = " ~ val ~ " >> 1");
}

string RotateRight(string val)
{
    string C = Attr("C");

    return "auto oldC = " ~ C ~ ";\n" ~
           C ~ " = ((" ~ val ~ " & 0x01) != 0);\n" ~
           SetNZ(val ~ " = (" ~ val ~ " >> 1 | (oldC ? 0x80 : 0))");
}

string RMW(int op, string action, string chip, bool s, bool c)
{
    bool nmos = (chip == "6502");

    return Address(op, chip, s, c) ~
           ReadInto(Local("ubyte", "data"), "address", c) ~
           If!(nmos)(Poke("address", "data", s, c),
                     Peek("address", s, c)) ~
           action ~
           Write("address", "data", c);
}


string Address(int op, string chip, bool s, bool c)
{
    auto EXTRA_CYCLE = opExCyc(op, chip);
    auto PC = Attr("PC");

    final switch (opMode(op, chip))
    {
        case IMP:
            return AddrIMP(s, c);
        case IMM:
            return AddrIMM(s, c);
        case ZP:
            return AddrZP(s, c);
        case ZPX:
            return AddrZPXY("X", chip, s, c);
        case ZPY:
            return AddrZPXY("Y", chip, s, c);
        case IZX:
            return AddrIZX(chip, s, c);
        case IZY:
            return AddrIZY(op, chip, s, c);
        case ABS:
            return AddrABS(s, c);
        case ABX:
            return AddrABXY(op, "X", chip, s, c);
        case ABY:
            return AddrABXY(op, "Y", chip, s, c);
        case IND:
            return Local("ushort", "address") ~ " = 0;";
        case REL:
            return Local("ushort", "address") ~ " = 0;";
        case ZPI:
            return AddrZPI(s, c);
        case ABI:
            return Local("ushort", "address") ~ " = 0;";
        case NP1:
            return "";
        case NP8:
            return Local("ushort", "address") ~ " = 0;";
        case KIL:
            return Local("ushort", "address") ~ " = 0;";
    }
    return "";
}


string PreAccess(bool cumulative)
{
    return If!(cumulative)("++cycles;\n", Attr("clock") ~ ".tick();\n");
}

string Peek(string addr, bool strict, bool cumulative)
{
    return PreAccess(cumulative) ~
           If!(strict)(Attr("memory") ~ ".read(" ~ addr ~");\n");
}

string Poke(string addr, string val, bool strict, bool cumulative)
{
    return PreAccess(cumulative) ~
           If!(strict)(
               Attr("memory") ~ ".write(" ~ addr ~ ", " ~ val ~ ");\n");
}

string Write(string addr, string val, bool cumulative)
{
    return PreAccess(cumulative) ~
           Attr("memory") ~ ".write(" ~ addr ~ ", " ~ val ~ ");\n";
}

string IncPC()
{
    return "++" ~ Attr("PC") ~ ";\n";
}


string IncSP()
{
    return "++" ~ Attr("S") ~ ";\n";
}

string DecSP()
{
    return "--" ~ Attr("S") ~ ";\n";
}

string PullStatus(bool s, bool c)
{
    return Peek("0x0100 + " ~ Attr("S"), s, c) ~
           IncSP() ~
           PreAccess(c) ~
           Attr("statusFromByte") ~ "(" ~
           ReadRaw("0x0100 + " ~ Attr("S")) ~ ");\n";
}

string PullInto(string var, bool s, bool c)
{
    return Peek("0x0100 + " ~ Attr("S"), s, c) ~
           IncSP() ~
           ReadInto(var, "0x0100 + " ~ Attr("S"), c);
}

string Push(string val, bool s, bool c)
{
    return Write("0x0100 + " ~ Attr("S"), val, c) ~
           DecSP();
}

string PushPC(bool s, bool c)
{
    return Push(HiByte(Attr("PC")), s, c) ~
           Push(LoByte(Attr("PC")), s, c);
}


string PullPC(bool s, bool c)
{
    string PC = Attr("PC");

    return PullInto(PC, s, c) ~
           PreAccess(c) ~
           IncSP() ~
           PC ~ " |= (" ~ ReadRaw("0x0100 + " ~ Attr("S")) ~ " << 8);\n";
}

string SetFlag(string flag)
{
    return Attr(flag) ~ " = true;\n";
}

string ClearFlag(string flag)
{
    return Attr(flag) ~ " = false;\n";
}

string UpdateFlag(string flag, string val)
{
    return Attr(flag) ~ " = (" ~ val ~ ");\n";
}

string SetNZ(string var)
{
    return Attr("N") ~ " = " ~ Attr("Z") ~ " = (" ~ var ~ ");\n";
}

string Done(bool cumulative)
{
    return If!(cumulative)(Attr("clock") ~ ".tick(cycles);\n");
}


string Attr(string var)
{
    version(OpFunctions)
        return "cpu." ~ var;
    else
        return var;
}


string HiByte(string var)
{
    return var ~ " >> 8";
}

string LoByte(string var)
{
    return var ~ " & 0xff";
}


string If(alias cond)(string yes, string no = "")
{
    if (cond)
        return yes;
    else
        return no;
}


string opName(int op, string chip)
{
    if (chip == "6502")
        return OP_NAMES_6502[op];
    else
        return OP_NAMES_65C02[op];
}

int opMode(int op, string chip)
{
    if (chip == "6502")
        return ADDR_MODES_6502[op];
    else
        return ADDR_MODES_65C02[op];
}

int opExCyc(int op, string chip)
{
    if (chip == "6502")
        return EXTRA_CYCLES_6502[op];
    else
        return EXTRA_CYCLES_65C02[op];
}


// Opcode names.
immutable OP_NAMES_6502 = [
    "BRK", "ORA", "KIL", "SLO", "NOP", "ORA", "ASL", "SLO",
    "PHP", "ORA", "ASL", "ANC", "NOP", "ORA", "ASL", "SLO",
    "BPL", "ORA", "KIL", "SLO", "NOP", "ORA", "ASL", "SLO",
    "CLC", "ORA", "NOP", "SLO", "NOP", "ORA", "ASL", "SLO",
    "JSR", "AND", "KIL", "RLA", "BIT", "AND", "ROL", "RLA",
    "PLP", "AND", "ROL", "ANC", "BIT", "AND", "ROL", "RLA",
    "BMI", "AND", "KIL", "RLA", "NOP", "AND", "ROL", "RLA",
    "SEC", "AND", "NOP", "RLA", "NOP", "AND", "ROL", "RLA",
    "RTI", "EOR", "KIL", "SRE", "NOP", "EOR", "LSR", "SRE",
    "PHA", "EOR", "LSR", "ALR", "JMP", "EOR", "LSR", "SRE",
    "BVC", "EOR", "KIL", "SRE", "NOP", "EOR", "LSR", "SRE",
    "CLI", "EOR", "NOP", "SRE", "NOP", "EOR", "LSR", "SRE",
    "RTS", "ADC", "KIL", "RRA", "NOP", "ADC", "ROR", "RRA",
    "PLA", "ADC", "ROR", "ARR", "JMP", "ADC", "ROR", "RRA",
    "BVS", "ADC", "KIL", "RRA", "NOP", "ADC", "ROR", "RRA",
    "SEI", "ADC", "NOP", "RRA", "NOP", "ADC", "ROR", "RRA",
    "NOP", "STA", "NOP", "SAX", "STY", "STA", "STX", "SAX",
    "DEY", "NOP", "TXA", "XAA", "STY", "STA", "STX", "SAX",
    "BCC", "STA", "KIL", "AHX", "STY", "STA", "STX", "SAX",
    "TYA", "STA", "TXS", "TAS", "SHY", "STA", "SHX", "AHX",
    "LDY", "LDA", "LDX", "LAX", "LDY", "LDA", "LDX", "LAX",
    "TAY", "LDA", "TAX", "LAX", "LDY", "LDA", "LDX", "LAX",
    "BCS", "LDA", "KIL", "LAX", "LDY", "LDA", "LDX", "LAX",
    "CLV", "LDA", "TSX", "LAS", "LDY", "LDA", "LDX", "LAX",
    "CPY", "CMP", "NOP", "DCP", "CPY", "CMP", "DEC", "DCP",
    "INY", "CMP", "DEX", "AXS", "CPY", "CMP", "DEC", "DCP",
    "BNE", "CMP", "KIL", "DCP", "NOP", "CMP", "DEC", "DCP",
    "CLD", "CMP", "NOP", "DCP", "NOP", "CMP", "DEC", "DCP",
    "CPX", "SBC", "NOP", "ISC", "CPX", "SBC", "INC", "ISC",
    "INX", "SBC", "NOP", "SBC", "CPX", "SBC", "INC", "ISC",
    "BEQ", "SBC", "KIL", "ISC", "NOP", "SBC", "INC", "ISC",
    "SED", "SBC", "NOP", "ISC", "NOP", "SBC", "INC", "ISC"
];

immutable OP_NAMES_65C02 = [
    "BRK", "ORA", "NOP", "NOP", "TSB", "ORA", "ASL", "NOP",
    "PHP", "ORA", "ASL", "NOP", "TSB", "ORA", "ASL", "NOP",
    "BPL", "ORA", "ORA", "NOP", "TRB", "ORA", "ASL", "NOP",
    "CLC", "ORA", "INC", "NOP", "TRB", "ORA", "ASL", "NOP",
    "JSR", "AND", "NOP", "NOP", "BIT", "AND", "ROL", "NOP",
    "PLP", "AND", "ROL", "NOP", "BIT", "AND", "ROL", "NOP",
    "BMI", "AND", "AND", "NOP", "BIT", "AND", "ROL", "NOP",
    "SEC", "AND", "DEC", "NOP", "BIT", "AND", "ROL", "NOP",
    "RTI", "EOR", "NOP", "NOP", "NOP", "EOR", "LSR", "NOP",
    "PHA", "EOR", "LSR", "NOP", "JMP", "EOR", "LSR", "NOP",
    "BVC", "EOR", "EOR", "NOP", "NOP", "EOR", "LSR", "NOP",
    "CLI", "EOR", "PHY", "NOP", "NOP", "EOR", "LSR", "NOP",
    "RTS", "ADC", "NOP", "NOP", "STZ", "ADC", "ROR", "NOP",
    "PLA", "ADC", "ROR", "NOP", "JMP", "ADC", "ROR", "NOP",
    "BVS", "ADC", "ADC", "NOP", "STZ", "ADC", "ROR", "NOP",
    "SEI", "ADC", "PLY", "NOP", "JMP", "ADC", "ROR", "NOP",
    "BRA", "STA", "NOP", "NOP", "STY", "STA", "STX", "NOP",
    "DEY", "BIT", "TXA", "NOP", "STY", "STA", "STX", "NOP",
    "BCC", "STA", "STA", "NOP", "STY", "STA", "STX", "NOP",
    "TYA", "STA", "TXS", "NOP", "STZ", "STA", "STZ", "NOP",
    "LDY", "LDA", "LDX", "NOP", "LDY", "LDA", "LDX", "NOP",
    "TAY", "LDA", "TAX", "NOP", "LDY", "LDA", "LDX", "NOP",
    "BCS", "LDA", "LDA", "NOP", "LDY", "LDA", "LDX", "NOP",
    "CLV", "LDA", "TSX", "NOP", "LDY", "LDA", "LDX", "NOP",
    "CPY", "CMP", "NOP", "NOP", "CPY", "CMP", "DEC", "NOP",
    "INY", "CMP", "DEX", "NOP", "CPY", "CMP", "DEC", "NOP",
    "BNE", "CMP", "CMP", "NOP", "NOP", "CMP", "DEC", "NOP",
    "CLD", "CMP", "PHX", "NOP", "NOP", "CMP", "DEC", "NOP",
    "CPX", "SBC", "NOP", "NOP", "CPX", "SBC", "INC", "NOP",
    "INX", "SBC", "NOP", "NOP", "CPX", "SBC", "INC", "NOP",
    "BEQ", "SBC", "SBC", "NOP", "NOP", "SBC", "INC", "NOP",
    "SED", "SBC", "PLX", "NOP", "NOP", "SBC", "INC", "NOP"
];


// Addressing modes.

enum { IMP, IMM, ZP, ZPX, ZPY, IZX, IZY, ABS, ABX, ABY, IND, REL,
       ZPI, ABI, NP1, NP8, KIL }

immutable ADDR_MODES_6502 = [
    IMP, IZX, KIL, IZX, ZP,  ZP,  ZP,  ZP,
    IMP, IMM, IMP, IMM, ABS, ABS, ABS, ABS,
    REL, IZY, KIL, IZY, ZPX, ZPX, ZPX, ZPX,
    IMP, ABY, IMP, ABY, ABX, ABX, ABX, ABX,
    ABS, IZX, KIL, IZX, ZP,  ZP,  ZP,  ZP,
    IMP, IMM, IMP, IMM, ABS, ABS, ABS, ABS,
    REL, IZY, KIL, IZY, ZPX, ZPX, ZPX, ZPX,
    IMP, ABY, IMP, ABY, ABX, ABX, ABX, ABX,
    IMP, IZX, KIL, IZX, ZP,  ZP,  ZP,  ZP,
    IMP, IMM, IMP, IMM, ABS, ABS, ABS, ABS,
    REL, IZY, KIL, IZY, ZPX, ZPX, ZPX, ZPX,
    IMP, ABY, IMP, ABY, ABX, ABX, ABX, ABX,
    IMP, IZX, KIL, IZX, ZP,  ZP,  ZP,  ZP,
    IMP, IMM, IMP, IMM, IND, ABS, ABS, ABS,
    REL, IZY, KIL, IZY, ZPX, ZPX, ZPX, ZPX,
    IMP, ABY, IMP, ABY, ABX, ABX, ABX, ABX,
    IMM, IZX, IMM, IZX, ZP,  ZP,  ZP,  ZP,
    IMP, IMM, IMP, IMM, ABS, ABS, ABS, ABS,
    REL, IZY, KIL, IZY, ZPX, ZPX, ZPY, ZPY,
    IMP, ABY, IMP, ABY, ABX, ABX, ABY, ABY,
    IMM, IZX, IMM, IZX, ZP,  ZP,  ZP,  ZP,
    IMP, IMM, IMP, IMM, ABS, ABS, ABS, ABS,
    REL, IZY, KIL, IZY, ZPX, ZPX, ZPY, ZPY,
    IMP, ABY, IMP, ABY, ABX, ABX, ABY, ABY,
    IMM, IZX, IMM, IZX, ZP,  ZP,  ZP,  ZP,
    IMP, IMM, IMP, IMM, ABS, ABS, ABS, ABS,
    REL, IZY, KIL, IZY, ZPX, ZPX, ZPX, ZPX,
    IMP, ABY, IMP, ABY, ABX, ABX, ABX, ABX,
    IMM, IZX, IMM, IZX, ZP,  ZP,  ZP,  ZP,
    IMP, IMM, IMP, IMM, ABS, ABS, ABS, ABS,
    REL, IZY, KIL, IZY, ZPX, ZPX, ZPX, ZPX,
    IMP, ABY, IMP, ABY, ABX, ABX, ABX, ABX
];

immutable ADDR_MODES_65C02 = [
    IMP, IZX, IMM, NP1, ZP,  ZP,  ZP,  NP1,
    IMP, IMM, IMP, NP1, ABS, ABS, ABS, NP1,
    REL, IZY, ZPI, NP1, ZP,  ZPX, ZPX, NP1,
    IMP, ABY, IMP, NP1, ABS, ABX, ABX, NP1,
    ABS, IZX, IMM, NP1, ZP,  ZP,  ZP,  NP1,
    IMP, IMM, IMP, NP1, ABS, ABS, ABS, NP1,
    REL, IZY, ZPI, NP1, ZPX, ZPX, ZPX, NP1,
    IMP, ABY, IMP, NP1, ABX, ABX, ABX, NP1,
    IMP, IZX, IMM, NP1, ZP,  ZP,  ZP,  NP1,
    IMP, IMM, IMP, NP1, ABS, ABS, ABS, NP1,
    REL, IZY, ZPI, NP1, ZPX, ZPX, ZPX, NP1,
    IMP, ABY, IMP, NP1, NP8, ABX, ABX, NP1,
    IMP, IZX, IMM, NP1, ZP,  ZP,  ZP,  NP1,
    IMP, IMM, IMP, NP1, IND, ABS, ABS, NP1,
    REL, IZY, ZPI, NP1, ZPX, ZPX, ZPX, NP1,
    IMP, ABY, IMP, NP1, ABI, ABX, ABX, NP1,
    REL, IZX, IMM, NP1, ZP,  ZP,  ZP,  NP1,
    IMP, IMM, IMP, NP1, ABS, ABS, ABS, NP1,
    REL, IZY, ZPI, NP1, ZPX, ZPX, ZPY, NP1,
    IMP, ABY, IMP, NP1, ABX, ABX, ABX, NP1,
    IMM, IZX, IMM, NP1, ZP,  ZP,  ZP,  NP1,
    IMP, IMM, IMP, NP1, ABS, ABS, ABS, NP1,
    REL, IZY, ZPI, NP1, ZPX, ZPX, ZPY, NP1,
    IMP, ABY, IMP, NP1, ABX, ABX, ABY, NP1,
    IMM, IZX, IMM, NP1, ZP,  ZP,  ZP,  NP1,
    IMP, IMM, IMP, NP1, ABS, ABS, ABS, NP1,
    REL, IZY, ZPI, NP1, ZPX, ZPX, ZPX, NP1,
    IMP, ABY, IMP, NP1, ABX, ABX, ABX, NP1,
    IMM, IZX, IMM, NP1, ZP,  ZP,  ZP,  NP1,
    IMP, IMM, IMP, NP1, ABS, ABS, ABS, NP1,
    REL, IZY, ZPI, NP1, ZPX, ZPX, ZPX, NP1,
    IMP, ABY, IMP, NP1, ABX, ABX, ABX, NP1
];


// Page-crossing extra cycles.

immutable EXTRA_CYCLES_6502 = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1,
];

immutable EXTRA_CYCLES_65C02 = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0,
];


// Custom string formatting.

enum HEX_DIGITS = "0123456789abcdef";

string Hex1(int dec)
{
    return HEX_DIGITS[dec..dec+1];
}

string Hex2(int dec)
{
    int highNybble = (dec & 0xF0) >> 4;
    int lowNybble = dec & 0x0F;

    return HEX_DIGITS[highNybble..highNybble+1] ~
           HEX_DIGITS[lowNybble..lowNybble+1];
}

string Fmt(string f, string[] p ...)
{
    if (!p.length) return "ERROR";
    string ret;
    size_t last;
    size_t other;
    for (size_t i = 0; i < f.length; i++)
    {
        if (f[i] == '#')
        {
            if (other == p.length) return "ERROR";
            ret ~= f[last..i] ~ p[other++];
            last = i + 1;
        }
    }
    return ret ~ f[last..$];
}


version(OpFunctions) mixin(OpBodies("6502", vStrict, vCumulative));
version(OpFunctions) mixin(OpBodies("65C02", vStrict, vCumulative));


//alias Cpu!("6502", false, false) T1;
//alias Cpu!("6502", false, true) T2;
//alias Cpu!("6502", true, false) T3;
//alias Cpu!("6502", true, true) T4;
//alias Cpu!("65C02", false, false) T5;
//alias Cpu!("65C02", false, true) T6;
//alias Cpu!("65C02", true, false) T7;
//alias Cpu!("65C02", true, true) T8;

/+
void main()
{
    import std.stdio;
    writeln(OpBody(0x11, "6502", true, false));
}
+/
