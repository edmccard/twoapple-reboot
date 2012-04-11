module cpu.ctfe_d6502;


import cpu.data_d6502;


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


enum _PC = Attr("PC");
enum _A = Attr("A");
enum _X = Attr("X");
enum _Y = Attr("Y");
enum _N = Attr("N");
enum _V = Attr("V");
enum _D = Attr("D");
enum _I = Attr("I");
enum _Z = Attr("Z");
enum _C = Attr("C");
enum _S = Attr("S");
enum STACK = "0x0100 + " ~ _S;


string OpBody(int op, string chip, bool s, bool c)
{
    bool nmos = (chip == "6502");
    final switch (opName(op, chip))
    {
        case "BRK":
            return Break(s, c) ~
                   Done(c);
        case "RTI":
            return RetInt(s, c) ~
                   Done(c);
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
            return _PC ~ "--;\n" ~
                   Done(c);
        case "BPL":
            return Branch("!(" ~ _N ~ " & 0x80)", nmos, s, c) ~
                   Done(c);
        case "BMI":
            return Branch("(" ~ _N ~ " & 0x80)", nmos, s, c) ~
                   Done(c);
        case "BVC":
            return Branch("!" ~ _V, nmos, s, c) ~
                   Done(c);
        case "BVS":
            return Branch(_V, nmos, s, c) ~
                   Done(c);
        case "BRA":
            return Branch("true", nmos, s, c) ~
                   Done(c);
        case "BCC":
            return Branch("!" ~ _C, nmos, s, c) ~
                   Done(c);
        case "BCS":
            return Branch(_C, nmos, s, c) ~
                   Done(c);
        case "BNE":
            return Branch(_Z, nmos, s, c) ~
                   Done(c);
        case "BEQ":
            return Branch("!" ~ _Z, nmos, s, c) ~
                   Done(c);
        case "CLC":
            return AddrIMP(s, c) ~
                   ClearFlag(_C) ~
                   Done(c);
        case "SEC":
            return AddrIMP(s, c) ~
                   SetFlag(_C) ~
                   Done(c);
        case "CLI":
            return AddrIMP(s, c) ~
                   ClearFlag(_I) ~
                   Done(c);
        case "SEI":
            return AddrIMP(s, c) ~
                   SetFlag(_I) ~
                   Done(c);
        case "CLV":
            return AddrIMP(s, c) ~
                   ClearFlag(_V) ~
                   Done(c);
        case "CLD":
            return AddrIMP(s, c) ~
                   ClearFlag(_D) ~
                   Done(c);
        case "SED":
            return AddrIMP(s, c) ~
                   SetFlag(_D) ~
                   Done(c);
        case "NOP":
            return Nop(op, chip, s, c) ~
                   Done(c);
        case "TAX":
            return Transfer(op, _A, _X, s, c) ~
                   Done(c);
        case "TXA":
            return Transfer(op, _X, _A, s, c) ~
                   Done(c);
        case "TAY":
            return Transfer(op, _A, _Y, s, c) ~
                   Done(c);
        case "TYA":
            return Transfer(op, _Y, _A, s, c) ~
                   Done(c);
        case "TSX":
            return Transfer(op, _S, _X, s, c) ~
                   Done(c);
        case "TXS":
            return Transfer(op, _X, _S, s, c) ~
                   Done(c);
        case "DEX":
            return AddrIMP(s, c) ~
                   Dec(_X) ~
                   Done(c);
        case "DEY":
            return AddrIMP(s, c) ~
                   Dec(_Y) ~
                   Done(c);
        case "INX":
            return AddrIMP(s, c) ~
                   Inc(_X) ~
                   Done(c);
        case "INY":
            return AddrIMP(s, c) ~
                   Inc(_Y) ~
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
            return PullReg(_A, s, c) ~
                   Done(c);
        case "PLX":
            return PullReg(_X, s, c) ~
                   Done(c);
        case "PLY":
            return PullReg(_Y, s, c) ~
                   Done(c);
        case "PHA":
            return PushReg(_A, s, c) ~
                   Done(c);
        case "PHX":
            return PushReg(_X, s, c) ~
                   Done(c);
        case "PHY":
            return PushReg(_Y, s, c) ~
                   Done(c);
        case "LDA":
            return Load(op, _A, chip, s, c) ~
                   Done(c);
        case "LDX":
            return Load(op, _X, chip, s, c) ~
                   Done(c);
        case "LDY":
            return Load(op, _Y, chip, s, c) ~
                   Done(c);
        case "STA":
            return Store(op, _A, chip, s, c) ~
                   Done(c);
        case "STX":
            return Store(op, _X, chip, s, c) ~
                   Done(c);
        case "STY":
            return Store(op, _Y, chip, s, c) ~
                   Done(c);
        case "STZ":
            return Store(op, "0", chip, s, c) ~
                   Done(c);
        case "CMP":
            return Compare(op, _A, chip, s, c) ~
                   Done(c);
        case "CPX":
            return Compare(op, _X, chip, s, c) ~
                   Done(c);
        case "CPY":
            return Compare(op, _Y, chip, s, c) ~
                   Done(c);
        case "BIT":
            return Bit(op, chip, s, c) ~
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
        case "INC":
            if (op == 0x1a)
                return AddrIMP(s, c) ~ Inc(_A) ~ Done(c);
            else
                return RMW(op, Inc("data"), chip, s, c) ~ Done(c);
        case "DEC":
            if (op == 0x3a)
                return AddrIMP(s, c) ~ Dec(_A) ~ Done(c);
            else
                return RMW(op, Dec("data"), chip, s, c) ~ Done(c);
        case "ASL":
            if (op == 0x0a)
                return AddrIMP(s, c) ~ ShiftLeft(_A) ~ Done(c);
            else
                return RMW(op, ShiftLeft("data"), chip, s, c) ~ Done(c);
        case "ROL":
            if (op == 0x2a)
                return AddrIMP(s, c) ~ RotateLeft(_A) ~ Done(c);
            else
                return RMW(op, RotateLeft("data"), chip, s, c) ~ Done(c);
        case "LSR":
            if (op == 0x4a)
                return AddrIMP(s, c) ~ ShiftRight(_A) ~ Done(c);
            else
                return RMW(op, ShiftRight("data"), chip, s, c) ~ Done(c);
        case "ROR":
            if (op == 0x6a)
                return AddrIMP(s, c) ~ ShiftRight(_A) ~ Done(c);
            else
                return RMW(op, RotateRight("data"), chip, s, c) ~ Done(c);
        case "TRB":
                return RMW(op, TestReset(), chip, s, c) ~ Done(c);
        case "TSB":
                return RMW(op, TestSet(), chip, s, c) ~ Done(c);
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


string Break(bool s, bool c)
{
    return AddrIMP(s, c) ~
           IncPC() ~
           PushPC(s, c) ~
           Push(Attr("statusToByte()"), s, c) ~
           SetFlag(_I) ~
           ReadWord(_PC, "IRQ_VECTOR", c);
}


string JumpSub(bool s, bool c)
{
    return ReadOp(Local("ushort", "address"), c) ~
           Peek(STACK, s, c) ~
           PushPC(s, c) ~
           LoadHiByte("address", _PC ~ "++", c) ~
           _PC ~ " = address;\n";
}


string RetSub(bool s, bool c)
{
    return AddrIMP(s, c) ~
           Peek(STACK, s, c) ~
           PullPC(s, c) ~
           Peek(_PC, s, c) ~
           IncPC();
}


string RetInt(bool s, bool c)
{
    return AddrIMP(s, c) ~
           PullStatus(s, c) ~
           PullPC(s, c);
}


string Jump(int op, string chip, bool s, bool c)
{
    bool nmos = (chip == "6502");

    if (op == 0x4c)
        return Address(op, chip, s, c) ~
               _PC ~ " = address;\n";
    else if (op == 0x6c)
        return ReadWordOp("ushort", "base", c) ~
               If!(nmos)(
                   "",
                   Peek(_PC, s, c)) ~
               ReadWordBasic(_PC, "base",
                             If!(nmos)(
                                 "(base & 0xFF00) | cast(ubyte)(base + 1)",
                                 "cast(ushort)(base + 1)"), c);
    else if (op == 0x7c)
        return ReadWordOp("ushort", "base",  c) ~
               Peek(_PC, s, c) ~
               ReadWord(_PC, "cast(ushort)(base + " ~ _X ~ ")", c);
    return "";
}


string Branch(string check, bool nmos, bool s, bool c)
{
    return ReadOp(Local("ubyte", "op1"), c) ~
           "if (" ~ check ~ ")\n{\n" ~
               Peek(_PC, s, c) ~
               Local("ushort", "base") ~ " = " ~ _PC ~ ";\n" ~
               _PC ~ " = cast(ushort)(" ~ _PC ~ " + cast(byte)op1);\n" ~
               CheckShortcut(_PC, "base", 0, nmos, s, c) ~
           "}\n";
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


string Transfer(int op, string source, string dest, bool s, bool c)
{
    return AddrIMP(s, c) ~
           dest ~ " = " ~ source ~ ";\n" ~
           ((op != 0x9a) ? SetNZ(dest) : "");
}


string PullReg(string reg, bool s, bool c)
{
    return AddrIMP(s, c) ~
           Peek(STACK, s, c) ~
           PullInto(reg, s, c) ~
           SetNZ(reg);
}


string PushReg(string reg, bool s, bool c)
{
    return AddrIMP(s, c) ~
           Push(reg, s, c);
}


string Load(int op, string reg, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           ReadInto(reg, "address", c) ~
           SetNZ(reg);
}


string Store(int op, string reg, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           Write("address", reg, c);
}


string Compare(int op, string reg, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           ReadInto(Local("ubyte", "data"), "address", c) ~
           UpdateFlag(_C, reg ~ " >= data") ~
           SetNZ("cast(ubyte)(" ~ reg ~ " - data)");
}


string Bit(int op, string chip, bool s, bool c)
{
    bool notImm = (opMode(op, chip) != IMM);

    return Address(op, chip, s, c) ~
           ReadInto(Local("ubyte", "data"), "address", c) ~
           If!(notImm)(
               _N ~ " = data;\n" ~
               _V ~ " = ((data & 0x40) != 0);\n") ~
           _Z ~ " = (" ~ _A ~ " & data);\n";
}


string Logic(int op, string action, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           ReadInto(_A, action, "address", c) ~
           SetNZ(_A);
}


string Add(int op, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           ReadInto(Local("ubyte", "data"), "address", c) ~
           "if (" ~ _D ~ ")\n{\n" ~
               DecAdd(chip, s, c) ~
           "}\nelse\n{\n" ~
               HexAdd(chip, s, c) ~
           "}\n";
}

string HexAdd(string chip, bool s, bool c)
{
    return "uint sum = " ~ _A ~ " + data + " ~ _C ~ ";\n" ~
           _V ~
           " = (!((" ~ _A ~ " ^ data) & 0x80)) && ((data ^ sum) & 0x80);\n" ~
           _C ~ " = (sum > 0xFF);\n" ~
           SetNZ(_A ~ " = cast(ubyte)sum");
}

string DecAdd(string chip, bool s, bool c)
{
    bool cmos = (chip != "6502");

    return "int a = " ~ _A ~ ";\n" ~
           "int al = (a & 0x0F) + (data & 0x0F) + " ~ _C ~ ";\n" ~
           "if (al >= 0x0A)\n" ~
               "al = ((al + 0x06) & 0x0F) + 0x10;\n" ~
           "a = (a & 0xF0) + (data & 0xF0) + al;\n" ~
           If!(cmos)("",
               _N ~ " = cast(ubyte)a;\n" ~
               _Z ~ " = cast(ubyte)(" ~ _A ~ " + data + " ~ _C ~ ");\n") ~
           _V ~
           " = (!((" ~ _A ~ " ^ data) & 0x80)) && ((data ^ a) & 0x80);\n" ~
           "if (a >= 0xA0)\n" ~
               "a = a + 0x60;\n" ~
           _C ~ " = (a >= 0x100);\n" ~
           If!(cmos)(
               SetNZ(_A ~ " = cast(ubyte)a") ~ Peek(_PC, s, c),
               _A ~ " = cast(ubyte)a;\n");
}


string Sub(int op, string chip, bool s, bool c)
{
    return Address(op, chip, s, c) ~
           ReadInto(Local("ubyte", "data"), "address", c) ~
           "if (" ~ _D ~ ")\n{\n" ~
               DecSub(chip, s, c) ~
           "}\nelse\n{\n" ~
               HexSub(chip, s, c) ~
           "}\n";
}

string HexSub(string chip, bool s, bool c)
{
    return "uint diff = " ~ _A ~ " - data - !" ~ _C ~ ";\n" ~
           _V ~
           " = ((" ~ _A ~ " ^ diff) & 0x80) && ((" ~
           _A ~ " ^ data) & 0x80);\n" ~
           _C ~ " = (diff < 0x100);\n" ~
           SetNZ(_A ~ " = cast(ubyte)diff");
}

string DecSub(string chip, bool s, bool c)
{
    return (chip == "6502" ? DecSubNMOS(s, c) : DecSubCMOS(s, c));
}

string DecSubNMOS(bool s, bool c)
{
    return "int a = " ~ _A ~ ";\n" ~
           "int al = (a & 0x0F) - (data & 0x0F) - !" ~ _C ~ ";\n" ~
           "if (al < 0)\n" ~
               "al = ((al - 0x06) & 0x0F) - 0x10;\n" ~
           "a = (a & 0xF0) - (data & 0xF0) + al;\n" ~
           "if (a < 0)\n" ~
               "a = a - 0x60;\n" ~
           "uint diff = " ~ _A ~ " - data - !" ~ _C ~ ";\n" ~
           _V ~
           " = ((" ~ _A ~ " ^ diff) & 0x80) && ((" ~
           _A ~ " ^ data) & 0x80);\n" ~
           _C ~ " = (diff < 0x100);\n" ~
           SetNZ("cast(ubyte)diff") ~
           _A ~ " = cast(ubyte)a;\n";
}

string DecSubCMOS(bool s, bool c)
{
    return "int a = " ~ _A ~ ";\n" ~
           "int al = (a & 0x0F) - (data & 0x0F) - !" ~ _C ~ ";\n" ~
           "a = a - data - !" ~ _C ~ ";\n" ~
           "if (a < 0) a = a - 0x60;\n" ~
           "if (al < 0) a = a - 0x06;\n" ~
           "uint diff = " ~ _A ~ " - data - !" ~ _C ~ ";\n" ~
           _V ~
           " = ((" ~ _A ~ " ^ diff) & 0x80) && ((" ~
           _A ~ " ^ data) & 0x80);\n" ~
           _C ~ " = (diff < 0x100);\n" ~
           Peek(_PC, s, c) ~
           SetNZ(_A ~ " = cast(ubyte)a");
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
    return _C ~ " = (" ~ val ~ " > 0x7F);\n" ~
           SetNZ(val ~ " = cast(ubyte)(" ~ val ~ " << 1)");
}


string RotateLeft(string val)
{
    return "auto oldC = " ~ _C ~ ";\n" ~
            _C ~ " = (" ~ val ~ " > 0x7f);\n" ~
            SetNZ(val ~ " = cast(ubyte)(" ~ val ~ " << 1 | (oldC ? 1 : 0))");
}


string ShiftRight(string val)
{
    return _C ~ " = ((" ~ val ~ " & 0x01) != 0);\n" ~
           SetNZ(val ~ " = " ~ val ~ " >> 1");
}


string RotateRight(string val)
{
    return "auto oldC = " ~ _C ~ ";\n" ~
           _C ~ " = ((" ~ val ~ " & 0x01) != 0);\n" ~
           SetNZ(val ~ " = (" ~ val ~ " >> 1 | (oldC ? 0x80 : 0))");
}


string TestReset()
{
    return _Z ~ " = data & " ~ _A ~ ";\n" ~
           "data &= (~" ~ _A ~ ");\n";
}


string TestSet()
{
    return _Z ~ " = data & " ~ _A ~ ";\n" ~
           "data |= " ~ _A ~ ";\n";
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
            return AddrZPXY(_X, chip, s, c);
        case ZPY:
            return AddrZPXY(_Y, chip, s, c);
        case IZX:
            return AddrIZX(chip, s, c);
        case IZY:
            return AddrIZY(op, chip, s, c);
        case ABS:
            return AddrABS(s, c);
        case ABX:
            return AddrABXY(op, _X, chip, s, c);
        case ABY:
            return AddrABXY(op, _Y, chip, s, c);
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


string AddrIMM(bool s, bool c)
{
     return Local("ushort") ~ "address = " ~ _PC ~ "++;\n";
}

string AddrIMP(bool s, bool c)
{
    return Peek(_PC, s, c);
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
               Peek(_PC, s, c)) ~
           Local("ushort") ~
           "address = cast(ubyte)(base + " ~ reg ~ ");\n";
}

string AddrIZX(string chip, bool s, bool c)
{
    bool nmos = (chip == "6502");
    return ReadOp(Local("ushort", "base"), c) ~
           If!(nmos)(
               Peek("base", s, c),
               Peek(_PC, s, c)) ~
           ReadWordZP("ushort", "address", "base + " ~ _X, c);
}

string AddrIZY(int op, string chip, bool s, bool c)
{
    int exCyc = opExCyc(op, chip);
    bool nmos = (chip == "6502");

    return ReadOp("ubyte vector", c) ~
           ReadWordZP("ushort", "base", "vector", c) ~
           Local("ushort") ~
           "address = cast(ushort)(base + " ~ _Y ~ ");\n" ~
           CheckShortcut("address", _PC,
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

    return ReadWordOp("ushort", "base", c) ~
           Local("ushort") ~ "address = cast(ushort)(base + " ~ reg ~ ");\n" ~
           CheckShortcut("address", _PC, exCyc, nmos, s, c);
}

string AddrZPI(bool s, bool c)
{
    return ReadOp(Local("ushort", "base"), c) ~
           ReadWordZP("ushort", "address", "base", c);
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
    return ReadInto(var, _PC ~ "++", c);
}

string ReadRaw(string addr)
{
    return Attr("memory") ~ ".read(" ~ addr ~")";
}

string ReadWordBasic(string type, string var, string addr1, string addr2,
                     bool c)
{
    return LoadLoByte(type, var, addr1, c) ~
           LoadHiByte(var, addr2, c);
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
    return ReadWordBasic(type, var, _PC ~ "++", _PC ~ "++", c);
}

string ReadWordOp(string var, bool c)
{
    return ReadWordOp("", var, c);
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
    return "++" ~ _PC ~ ";\n";
}


string IncSP()
{
    return "++" ~ _S ~ ";\n";
}

string DecSP()
{
    return "--" ~ _S ~ ";\n";
}

string PullStatus(bool s, bool c)
{
    return Peek(STACK, s, c) ~
           IncSP() ~
           PreAccess(c) ~
           Attr("statusFromByte") ~ "(" ~
           ReadRaw(STACK) ~ ");\n";
}

string PullInto(string var, bool s, bool c)
{
    return IncSP() ~
           ReadInto(var, STACK, c);
}

string Push(string val, bool s, bool c)
{
    return Write(STACK, val, c) ~
           DecSP();
}

string PushPC(bool s, bool c)
{
    return Push(HiByte(_PC), s, c) ~
           Push(LoByte(_PC), s, c);
}


string PullPC(bool s, bool c)
{
    return PullInto(_PC, s, c) ~
           IncSP() ~
           LoadHiByte(_PC, STACK, c);
}

string LoadLoByte(string type, string var, string addr, bool c)
{
    return PreAccess(c) ~
           Local(type, var) ~ " = " ~ ReadRaw(addr) ~ ";\n";
}

string LoadHiByte(string var, string addr, bool c)
{
    return PreAccess(c) ~
           var ~ " |= (" ~ ReadRaw(addr) ~ " << 8);\n";
}

string SetFlag(string flag)
{
    return flag ~ " = true;\n";
}

string ClearFlag(string flag)
{
    return flag ~ " = false;\n";
}

string UpdateFlag(string flag, string val)
{
    return flag ~ " = (" ~ val ~ ");\n";
}

string SetNZ(string var)
{
    return _N ~ " = " ~ _Z ~ " = (" ~ var ~ ");\n";
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
