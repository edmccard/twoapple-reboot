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

struct Env
{
    int op;
    string chip;
    bool s, c;
    bool nmos, cmos;
    int mode;
    int exCyc;

    this(int op, string chip, bool s, bool c)
    {
        this.op = op;
        this.chip = chip;
        this.s = s;
        this.c = c;
        nmos = (chip == "6502");
        cmos = !nmos;
        mode = opMode(op, chip);
        exCyc = opExCyc(op, chip);
    }
}

string OpBody(int op, string chip, bool s, bool c)
{
    auto env = Env(op, chip, s, c);
    string ret = ((op == 0x20) ? "" : Address(env));

    final switch (opName(op, chip))
    {
        case "BRK":
            ret ~= Break(env);
            break;
        case "RTI":
            ret ~= RetInt(env);
            break;
        case "JSR":
            ret ~= JumpSub(env);
            break;
        case "RTS":
            ret ~= RetSub(env);
            break;
        case "JMP":
            ret ~= Jump(env);
            break;
        case "KIL":
            ret ~= _PC ~ "--;\n";
            break;
        case "BPL":
            ret ~= Branch("!(" ~ _N ~ " & 0x80)", env);
            break;
        case "BMI":
            ret ~= Branch("(" ~ _N ~ " & 0x80)", env);
            break;
        case "BVC":
            ret ~= Branch("!" ~ _V, env);
            break;
        case "BVS":
            ret ~= Branch(_V, env);
            break;
        case "BRA":
            ret ~= Branch("true", env);
            break;
        case "BCC":
            ret ~= Branch("!" ~ _C, env);
            break;
        case "BCS":
            ret ~= Branch(_C, env);
            break;
        case "BNE":
            ret ~= Branch(_Z, env);
            break;
        case "BEQ":
            ret ~= Branch("!" ~ _Z, env);
            break;
        case "CLC":
            ret ~= ClearFlag(_C);
            break;
        case "SEC":
            ret ~= SetFlag(_C);
            break;
        case "CLI":
            ret ~= ClearFlag(_I);
            break;
        case "SEI":
            ret ~= SetFlag(_I);
            break;
        case "CLV":
            ret ~= ClearFlag(_V);
            break;
        case "CLD":
            ret ~= ClearFlag(_D);
            break;
        case "SED":
            ret ~= SetFlag(_D);
            break;
        case "NOP":
            ret ~= Nop(env);
            break;
        case "TAX":
            ret ~= Transfer(_A, _X, env);
            break;
        case "TXA":
            ret ~= Transfer(_X, _A, env);
            break;
        case "TAY":
            ret ~= Transfer(_A, _Y, env);
            break;
        case "TYA":
            ret ~= Transfer(_Y, _A, env);
            break;
        case "TSX":
            ret ~= Transfer(_S, _X, env);
            break;
        case "TXS":
            ret ~= Transfer(_X, _S, env);
            break;
        case "DEX":
            ret ~= Dec(_X);
            break;
        case "DEY":
            ret ~= Dec(_Y);
            break;
        case "INX":
            ret ~= Inc(_X);
            break;
        case "INY":
            ret ~= Inc(_Y);
            break;
        case "PHP":
            ret ~= Push(Attr("statusToByte()"), env);
            break;
        case "PLP":
            ret ~= PullStatus(env);
            break;
        case "PLA":
            ret ~= PullReg(_A, env);
            break;
        case "PLX":
            ret ~= PullReg(_X, env);
            break;
        case "PLY":
            ret ~= PullReg(_Y, env);
            break;
        case "PHA":
            ret ~= PushReg(_A, env);
            break;
        case "PHX":
            ret ~= PushReg(_X, env);
            break;
        case "PHY":
            ret ~= PushReg(_Y, env);
            break;
        case "LDA":
            ret ~= Load(_A, env);
            break;
        case "LDX":
            ret ~= Load(_X, env);
            break;
        case "LDY":
            ret ~= Load(_Y, env);
            break;
        case "STA":
            ret ~=  Store(_A, env);
            break;
        case "STX":
            ret ~= Store(_X, env);
            break;
        case "STY":
            ret ~= Store(_Y, env);
            break;
        case "STZ":
            ret ~= Store("0", env);
            break;
        case "CMP":
            ret ~= Compare(_A, env);
            break;
        case "CPX":
            ret ~= Compare(_X, env);
            break;
        case "CPY":
            ret ~= Compare(_Y, env);
            break;
        case "BIT":
            ret ~= Bit(env);
            break;
        case "ORA":
            ret ~= Logic("|=", env);
            break;
        case "AND":
            ret ~= Logic("&=", env);
            break;
        case "EOR":
            ret ~= Logic("^=", env);
            break;
        case "ADC":
            ret ~= Add(env);
            break;
        case "SBC":
            ret ~= Sub(env);
            break;
        case "INC":
            if (op == 0x1a)
                ret ~= Inc(_A);
            else
                ret ~= RMW(Inc("data"), env);
            break;
        case "DEC":
            if (op == 0x3a)
                ret ~= Dec(_A);
            else
                ret ~= RMW(Dec("data"), env);
            break;
        case "ASL":
            if (op == 0x0a)
                ret ~= ShiftLeft(_A);
            else
                ret ~= RMW(ShiftLeft("data"), env);
            break;
        case "ROL":
            if (op == 0x2a)
                ret ~= RotateLeft(_A);
            else
                ret ~= RMW(RotateLeft("data"), env);
            break;
        case "LSR":
            if (op == 0x4a)
                ret ~= ShiftRight(_A);
            else
                ret ~= RMW(ShiftRight("data"), env);
            break;
        case "ROR":
            if (op == 0x6a)
                ret ~= ShiftRight(_A);
            else
                ret ~= RMW(RotateRight("data"), env);
            break;
        case "TRB":
                ret ~= RMW(TestReset(), env);
                break;
        case "TSB":
                ret ~= RMW(TestSet(), env);
                break;
        case "LAS":
            ret ~= LAS_Undoc(env);
            break;
        case "LAX":
            if (op != 0xAB)
                ret ~= Load(_A ~ " = " ~ _X, env);
            else
                return "";
            break;
        case "SAX":
            ret ~= Store(_A ~ " & " ~ _X, env);
            break;
        case "ANC":
            ret ~= ANC_Undoc(env);
            break;
        case "ALR":
            ret ~= ALR_Undoc(env);
            break;
        case "ARR":
            ret ~= ARR_Undoc(env);
            break;
        case "AXS":
            ret ~= AXS_Undoc(env);
            break;
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
            ret ~= RMW_Undoc(ShiftLeft("data"),
                             SetNZ(_A ~ " |= data"), env);
            break;
        case "RLA":
            ret ~= RMW_Undoc(RotateLeft("data"),
                             SetNZ(_A ~ " &= data"), env);
            break;
        case "SRE":
            ret ~= RMW_Undoc(ShiftRight("data"),
                             SetNZ(_A ~ " ^= data"), env);
            break;
        case "RRA":
            ret ~= RMW_Undoc(RotateRight("data"), AddBase(env), env);
            break;
        case "DCP":
            ret ~= RMW_Undoc(Dec("data"), CompareBase(_A, env), env);
            break;
        case "ISC":
            ret ~= RMW_Undoc(Inc("data"), SubBase(env), env);
            break;
    }
    return ret ~ Done(env);
}


string Break(Env env)
{
    return IncPC() ~
           PushPC(env) ~
           Push(Attr("statusToByte()"), env) ~
           SetFlag(_I) ~
           ReadWord(_PC, "IRQ_VECTOR", env);
}


string JumpSub(Env env)
{
    return ReadOp(Local("ushort", "address"), env) ~
           Peek(STACK, env) ~
           PushPC(env) ~
           LoadHiByte("address", _PC ~ "++", env) ~
           _PC ~ " = address;\n";
}


string RetSub(Env env)
{
    return Peek(STACK, env) ~
           PullPC(env) ~
           Peek(_PC, env) ~
           IncPC();
}


string RetInt(Env env)
{
    return PullStatus(env) ~
           PullPC(env);
}


string Jump(Env env)
{
    bool cmos = env.cmos;
    bool nmos = env.nmos;

    if (env.op == 0x4c)
        return _PC ~ " = address;\n";
    else if (env.op == 0x6c)
        return ReadWordOp("ushort", "base", env) ~
               If!(cmos)(
                   Peek(_PC, env)) ~
               ReadWordBasic(_PC, "base",
                             If!(nmos)(
                                 "(base & 0xFF00) | cast(ubyte)(base + 1)",
                                 "cast(ushort)(base + 1)"), env);
    else if (env.op == 0x7c)
        return ReadWordOp("ushort", "base",  env) ~
               Peek(_PC, env) ~
               ReadWord(_PC, "cast(ushort)(base + " ~ _X ~ ")", env);
    return "";
}


string Branch(string check, Env env)
{
    return ReadOp(Local("ushort", "base"), env) ~
           "if (" ~ check ~ ")\n{\n" ~
               Peek(_PC, env) ~
               Local("ushort", "address") ~
               " = cast(ushort)(" ~ _PC ~ " + cast(byte)base);\n" ~
               CheckShortcut(_PC, "address", env) ~
               _PC ~ " = address;\n" ~
           "}\n";
}


string Nop(Env env)
{
    if (env.mode == IMP ||  env.mode == NP1 || env.mode == NP8)
        return ""; // XXX add np1/np8 stuff
    else
        return PreAccess(env) ~
               ReadRaw("address") ~ ";\n";
}


string Transfer(string source, string dest, Env env)
{
    return dest ~ " = " ~ source ~ ";\n" ~
           ((env.op != 0x9a) ? SetNZ(dest) : "");
}


string PullReg(string reg, Env env)
{
    return Peek(STACK, env) ~
           PullInto(reg, env) ~
           SetNZ(reg);
}


string PushReg(string reg, Env env)
{
    return Push(reg, env);
}


string Load(string reg, Env env)
{
    return ReadInto(reg, "address", env) ~
           SetNZ(reg);
}


string Store(string reg, Env env)
{
    return Write("address", reg, env);
}


string Compare(string reg, Env env)
{
    return ReadInto(Local("ubyte", "data"), "address", env) ~
           CompareBase(reg, env);
}

string CompareBase(string reg, Env env)
{
    return UpdateFlag(_C, reg ~ " >= data") ~
           SetNZ("cast(ubyte)(" ~ reg ~ " - data)");
}


string Bit(Env env)
{
    bool notImm = (env.mode != IMM);

    return ReadInto(Local("ubyte", "data"), "address", env) ~
           If!(notImm)(
               _N ~ " = data;\n" ~
               _V ~ " = ((data & 0x40) != 0);\n") ~
           _Z ~ " = (" ~ _A ~ " & data);\n";
}


string Logic(string action, Env env)
{
    return ReadInto(_A, action, "address", env) ~
           SetNZ(_A);
}


string Add(Env env)
{
    return ReadInto(Local("ubyte", "data"), "address", env) ~
           AddBase(env);
}

string AddBase(Env env)
{
    return "if (" ~ _D ~ ")\n{\n" ~
               DecAdd(env) ~
           "}\nelse\n{\n" ~
               HexAdd(env) ~
           "}\n";
}

string HexAdd(Env env)
{
    return "uint sum = " ~ _A ~ " + data + " ~ _C ~ ";\n" ~
           _V ~
           " = (!((" ~ _A ~ " ^ data) & 0x80)) && ((data ^ sum) & 0x80);\n" ~
           _C ~ " = (sum > 0xFF);\n" ~
           SetNZ(_A ~ " = cast(ubyte)sum");
}

string DecAdd(Env env)
{
    bool cmos = env.cmos;

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
               SetNZ(_A ~ " = cast(ubyte)a") ~ Peek(_PC, env),
               _A ~ " = cast(ubyte)a;\n");
}


string Sub(Env env)
{
    return ReadInto(Local("ubyte", "data"), "address", env) ~
           SubBase(env);
}

string SubBase(Env env)
{
    bool nmos = env.nmos;

    return "if (" ~ _D ~ ")\n{\n" ~
               If!(nmos)(DecSubNMOS(), DecSubCMOS(env)) ~
           "}\nelse\n{\n" ~
               HexSub() ~
           "}\n";
}

string HexSub()
{
    return "uint diff = " ~ _A ~ " - data - !" ~ _C ~ ";\n" ~
           _V ~
           " = ((" ~ _A ~ " ^ diff) & 0x80) && ((" ~
           _A ~ " ^ data) & 0x80);\n" ~
           _C ~ " = (diff < 0x100);\n" ~
           SetNZ(_A ~ " = cast(ubyte)diff");
}

string DecSubNMOS()
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

string DecSubCMOS(Env env)
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
           Peek(_PC, env) ~
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


string RMW(string action, Env env)
{
    bool nmos = env.nmos;

    return ReadInto(Local("ubyte", "data"), "address", env) ~
           If!(nmos)(Poke("address", "data", env),
                     Peek("address", env)) ~
           action ~
           Write("address", "data", env);
}


string RMW_Undoc(string action1, string action2, Env env)
{
    return ReadInto(Local("ubyte", "data"), "address", env) ~
           Poke("address", "data", env) ~
           action1 ~
           Write("address", "data", env) ~
           action2;
}


string LAS_Undoc(Env env)
{
    return ReadInto(Local("ubyte", "data"), "address", env) ~
           SetNZ(_X ~ " = " ~ _A ~ " = (" ~ _S ~ " & data)");
}


string ARR_Undoc(Env env)
{
    return ReadInto(Local("ubyte", "data"), "address", env) ~
           "ubyte tmp1 = data & " ~ _A ~ ";\n" ~
           "if (" ~ _D ~ ")\n{\n" ~
               "ubyte tmp2 = cast(ubyte)((tmp1 >> 1) + (" ~
               _C ~ " ? 0x80 : 0));\n" ~
               _N ~ " = " ~ _Z ~ " = tmp2;\n" ~
               _V ~ " = (((tmp2 ^ tmp1) & 0x40) != 0);\n" ~
               "if ((data & 0x0F) + (tmp1 & 0x01) > 5)\n" ~
                   "tmp2 = (tmp2 & 0xF0) + ((tmp2 + 0x6) & 0x0F);\n" ~
               "if (tmp1 + (tmp1 & 0x10) >= 0x60)\n{\n" ~
                   "tmp2 += 0x60;\n" ~
                   SetFlag(_C) ~
               "}\nelse\n" ~
                   ClearFlag(_C) ~
               _A ~ " = tmp2;\n" ~
           "}\nelse{\n" ~
               _A ~ " = cast(ubyte)((tmp1 >> 1) + (" ~
               _C ~ " ? 0x80 : 0));\n" ~
               _N ~ " = " ~ _Z ~ " = " ~_A ~ ";\n" ~
               "tmp1 >>= 7;\n" ~
               _C ~ " = (tmp1 != 0);\n" ~
               _V ~ " = ((tmp1 ^ ((" ~ _A ~ " >> 5) & 1)) != 0);\n}";
}


string ANC_Undoc(Env env)
{
    return ReadInto(_A, "address", env) ~
           SetNZ(_A) ~
           _C ~ " = (" ~ _A ~ " > 0x7f);\n";
}


string ALR_Undoc(Env env)
{
    return ReadInto(Local("ubyte", "data"), "address", env) ~
           _A ~ " &= data;\n" ~
           ShiftRight(_A);
}


string AXS_Undoc(Env env)
{
    return ReadInto(Local("ubyte", "data"), "address", env) ~
           _X ~ " &= " ~ _A ~ ";\n" ~
           CompareBase(_X, env);
}


string Local(string type)
{
    version(OpFunctions)
        return type ~ " ";
    else
        return "";
/+
    version(OpSwitch)
        return "";
    else version(OpNestedSwitch)
        return "";
    else
        return  type ~ " ";
+/
}

string Local(string type, string var)
{
    version(OpFunctions)
        return type ~ " " ~ var;
    else
        return var;
/+
    version(OpSwitch)
        return var;
    else version(OpNestedSwitch)
        return var;
    else
        return type ~ " " ~ var;
+/
}

string Attr(string var)
{
    version(OpFunctions)
        return "cpu." ~ var;
    else
        return var;
}


string Address(Env env)
{
    final switch (env.mode)
    {
        case IMP:
            return AddrIMP(env);
        case IMM:
            return AddrIMM(env);
        case ZP:
            return AddrZP(env);
        case ZPX:
            return AddrZPXY(_X, env);
        case ZPY:
            return AddrZPXY(_Y, env);
        case IZX:
            return AddrIZX(env);
        case IZY:
            return AddrIZY(env);
        case ABS:
            return AddrABS(env);
        case ABX:
            return AddrABXY(_X, env);
        case ABY:
            return AddrABXY(_Y, env);
        case IND:
            return "";
        case REL:
            return "";
        case ZPI:
            return AddrZPI(env);
        case ABI:
            return "";
        case NP1:
            return "";
        case NP8:
            return AddrNP8(env);
        case KIL:
            return "";
    }
    return "";
}


string AddrIMM(Env env)
{
     return Local("ushort") ~ "address = " ~ _PC ~ "++;\n";
}

string AddrIMP(Env env)
{
    return Peek(_PC, env);
}

string AddrZP(Env env)
{
    return ReadOp(Local("ushort", "address"), env);
}

string AddrZPXY(string reg, Env env)
{
    bool nmos = env.nmos;

    return ReadOp(Local("ushort", "base"), env) ~
           If!(nmos)(
               Peek("base", env),
               Peek(_PC, env)) ~
           Local("ushort") ~
           "address = cast(ubyte)(base + " ~ reg ~ ");\n";
}

string AddrIZX(Env env)
{
    bool nmos = env.nmos;

    return ReadOp(Local("ushort", "base"), env) ~
           If!(nmos)(
               Peek("base", env),
               Peek(_PC, env)) ~
           ReadWordZP("ushort", "address", "base + " ~ _X, env);
}

string AddrIZY(Env env)
{
    return ReadOp("ubyte vector", env) ~
           ReadWordZP("ushort", "base", "vector", env) ~
           Local("ushort") ~
           "address = cast(ushort)(base + " ~ _Y ~ ");\n" ~
           CheckShortcut("base", "address", env);
}

string AddrABS(Env env)
{
    return ReadWordOp("ushort", "address", env);
}

string AddrABXY(string reg, Env env)
{
    return ReadWordOp("ushort", "base", env) ~
           Local("ushort") ~ "address = cast(ushort)(base + " ~ reg ~ ");\n" ~
           CheckShortcut("base", "address", env);
}

string AddrZPI(Env env)
{
    return ReadOp(Local("ushort", "base"), env) ~
           ReadWordZP("ushort", "address", "base", env);
}

string AddrNP8(Env env)
{
    return ReadOp(Local("ushort", "base"), env) ~
           Peek(_PC, env) ~
           IncPC() ~
           Peek("0xff00 | base", env) ~
           Peek("0xffff", env) ~
           Peek("0xffff", env) ~
           Peek("0xffff", env) ~
           Peek("0xffff", env);
}

string CheckShortcut(string base, string addr, Env env)
{
    bool nmos = env.nmos;
    int exCyc = env.exCyc;

    return "ushort guess = (" ~ base ~ " & 0xFF00) | cast(ubyte)" ~ addr ~ ";\n" ~
           "if (guess != " ~ addr ~ ")\n{\n" ~
               If!(nmos)(Peek("guess", env),
                         Peek(_PC, env)) ~
           "}\n" ~
           If!(exCyc)("else\n{\n" ~ Peek("address", env) ~ "}\n");
}


string ReadInto(string var, string action, string addr, Env env)
{
    return PreAccess(env) ~
           var ~ " " ~ action ~ " " ~ ReadRaw("(" ~ addr ~ ")") ~ ";\n";
}

string ReadInto(string var, string addr, Env env)
{
    return ReadInto(var, "=", addr, env);
}

string ReadOp(string var, Env env)
{
    return ReadInto(var, _PC ~ "++", env);
}

string ReadRaw(string addr)
{
    return Attr("memory") ~ ".read(" ~ addr ~")";
}

string ReadWordBasic(string type, string var, string addr1, string addr2,
                     Env env)
{
    return LoadLoByte(type, var, addr1, env) ~
           LoadHiByte(var, addr2, env);
}

string ReadWordBasic(string var, string addr1, string addr2, Env env)
{
    return ReadWordBasic("", var, addr1, addr2, env);
}

string ReadWord(string type, string var, string addr, Env env)
{
    return ReadWordBasic(type, var, addr, "cast(ushort)(" ~ addr ~ " + 1)",
                         env);
}

string ReadWord(string var, string addr, Env env)
{
    return ReadWord("", var, addr, env);
}

string ReadWordZP(string type, string var, string addr, Env env)
{
    return ReadWordBasic(type, var, "cast(ubyte)( " ~ addr ~ ")",
                                    "cast(ubyte)(" ~ addr ~ " + 1)", env);
}

string ReadWordZP(string var, string addr, Env env)
{
    return ReadWordZP("", var, addr, env);
}

string ReadWordOp(string type, string var, Env env)
{
    return ReadWordBasic(type, var, _PC ~ "++", _PC ~ "++", env);
}

string ReadWordOp(string var, Env env)
{
    return ReadWordOp("", var, env);
}

string PreAccess(Env env)
{
    bool c = env.c;
    return If!(c)("++cycles;\n", Attr("clock") ~ ".tick();\n");
}

string Peek(string addr, Env env)
{
    bool s = env.s;
    return PreAccess(env) ~
           If!(s)(Attr("memory") ~ ".read(" ~ addr ~");\n");
}

string Poke(string addr, string val, Env env)
{
    bool s = env.s;
    return PreAccess(env) ~
           If!(s)(
               Attr("memory") ~ ".write(" ~ addr ~ ", " ~ val ~ ");\n");
}

string Write(string addr, string val, Env env)
{
    return PreAccess(env) ~
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

string PullStatus(Env env)
{
    return Peek(STACK, env) ~
           IncSP() ~
           PreAccess(env) ~
           Attr("statusFromByte") ~ "(" ~
           ReadRaw(STACK) ~ ");\n";
}

string PullInto(string var, Env env)
{
    return IncSP() ~
           ReadInto(var, STACK, env);
}

string Push(string val, Env env)
{
    return Write(STACK, val, env) ~
           DecSP();
}

string PushPC(Env env)
{
    return Push(HiByte(_PC), env) ~
           Push(LoByte(_PC), env);
}


string PullPC(Env env)
{
    return PullInto(_PC, env) ~
           IncSP() ~
           LoadHiByte(_PC, STACK, env);
}

string LoadLoByte(string type, string var, string addr, Env env)
{
    return PreAccess(env) ~
           Local(type, var) ~ " = " ~ ReadRaw(addr) ~ ";\n";
}

string LoadHiByte(string var, string addr, Env env)
{
    return PreAccess(env) ~
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

string Done(Env env)
{
    bool c = env.c;
    return If!(c)(Attr("clock") ~ ".tick(cycles);\n");
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
