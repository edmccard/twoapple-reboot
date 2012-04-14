module cpu.ctfe_d6502;


import cpu.data_d6502;


version(Strict)
    private enum strict = true;
else
    private enum strict = false;
version(Cumulative)
    private enum cumulative = true;
else
    private enum cumulative = false;


// The following versions are mutually exclusive.

// OpDelegates: each opcode is a method of the Cpu class.
version(OpDelegates)
{
    enum versionCheck = 1;
    enum opArray = true;
}

// OpSwitch: each opcode is inlined in a 256-case switch.
version(OpSwitch)
{
    enum versionCheck = 2;
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
    enum versionCheck = 3;
    enum opArray = false;
}


// At least one of the previous versions must be specified.
static if (!__traits(compiles, { bool b = opArray; })) enum opArray = 0;
static assert (versionCheck);


string OpArrayDef()
{
    version(OpDelegates)
        return q{void delegate()[256] opcodes;};
    else
        return "";
}

string OpArrayInit()
{
    string ret;
    foreach (op; 0..256)
    {
        ret ~= Fmt("opcodes[0x#] = &opcode_#;\n",
                   Hex2(op), Hex2(op));
    }
    return ret;
}

string OpMethods(string chip)
{
    string ret;
    foreach (op; 0..256)
    {
        ret ~= "final void opcode_" ~ Hex2(op) ~ "()\n{\n" ~
               If!(cumulative)("int cycles = 1;\n") ~
               OpBody(op, chip) ~ "}\n";
    }
    return ret;
}

string OpExecute(string chip)
{
    version(OpDelegates)
        return q{opcodes[opcode]();};
    version(OpSwitch)
        return Switch256(chip);
    version(OpNestedSwitch)
        return Switch16x16(chip);
}

string Switch256(string chip)
{
    string ret = "final switch (opcode)\n{\n";
    foreach (op; 0..256)
        ret ~= "case 0x" ~ Hex2(op) ~ ":\n" ~
               OpBody(op, chip) ~ "break;\n";
    return ret ~ "}\n";
}

string Switch16x16(string chip)
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
                   OpBody(op, chip) ~
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


string OpBody(int op, string chip)
{
    auto mode = opMode(op, chip);
    auto exCyc = opExCyc(op, chip);
    string ret = ((op == 0x20) ? "" : Address(mode, exCyc, chip));

    final switch (opName(op, chip))
    {
        case "BRK":
            ret ~= Break();
            break;
        case "RTI":
            ret ~= RetInt();
            break;
        case "JSR":
            ret ~= JumpSub();
            break;
        case "RTS":
            ret ~= RetSub();
            break;
        case "JMP":
            ret ~= Jump(op, chip);
            break;
        case "KIL":
            ret ~= _PC ~ "--;\n";
            break;
        case "BPL":
            ret ~= Branch("!(" ~ _N ~ " & 0x80)", chip);
            break;
        case "BMI":
            ret ~= Branch("(" ~ _N ~ " & 0x80)", chip);
            break;
        case "BVC":
            ret ~= Branch("!" ~ _V, chip);
            break;
        case "BVS":
            ret ~= Branch(_V, chip);
            break;
        case "BRA":
            ret ~= Branch("true", chip);
            break;
        case "BCC":
            ret ~= Branch("!" ~ _C, chip);
            break;
        case "BCS":
            ret ~= Branch(_C, chip);
            break;
        case "BNE":
            ret ~= Branch(_Z, chip);
            break;
        case "BEQ":
            ret ~= Branch("!" ~ _Z, chip);
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
            ret ~= Nop(mode);
            break;
        case "TAX":
            ret ~= Transfer(_A, _X);
            break;
        case "TXA":
            ret ~= Transfer(_X, _A);
            break;
        case "TAY":
            ret ~= Transfer(_A, _Y);
            break;
        case "TYA":
            ret ~= Transfer(_Y, _A);
            break;
        case "TSX":
            ret ~= Transfer(_S, _X);
            break;
        case "TXS":
            ret ~= Transfer(_X, _S, false);
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
            ret ~= Push(Attr("statusToByte()"));
            break;
        case "PLP":
            ret ~= PullStatus();
            break;
        case "PLA":
            ret ~= PullReg(_A);
            break;
        case "PLX":
            ret ~= PullReg(_X);
            break;
        case "PLY":
            ret ~= PullReg(_Y);
            break;
        case "PHA":
            ret ~= PushReg(_A);
            break;
        case "PHX":
            ret ~= PushReg(_X);
            break;
        case "PHY":
            ret ~= PushReg(_Y);
            break;
        case "LDA":
            ret ~= Load(_A);
            break;
        case "LDX":
            ret ~= Load(_X);
            break;
        case "LDY":
            ret ~= Load(_Y);
            break;
        case "STA":
            ret ~=  Store(_A);
            break;
        case "STX":
            ret ~= Store(_X);
            break;
        case "STY":
            ret ~= Store(_Y);
            break;
        case "STZ":
            ret ~= Store("0");
            break;
        case "CMP":
            ret ~= Compare(_A);
            break;
        case "CPX":
            ret ~= Compare(_X);
            break;
        case "CPY":
            ret ~= Compare(_Y);
            break;
        case "BIT":
            ret ~= Bit(mode);
            break;
        case "ORA":
            ret ~= Logic("|=");
            break;
        case "AND":
            ret ~= Logic("&=");
            break;
        case "EOR":
            ret ~= Logic("^=");
            break;
        case "ADC":
            ret ~= Add(chip);
            break;
        case "SBC":
            ret ~= Sub(chip);
            break;
        case "INC":
            if (op == 0x1a)
                ret ~= Inc(_A);
            else
                ret ~= RMW(Inc("data"), chip);
            break;
        case "DEC":
            if (op == 0x3a)
                ret ~= Dec(_A);
            else
                ret ~= RMW(Dec("data"), chip);
            break;
        case "ASL":
            if (op == 0x0a)
                ret ~= ShiftLeft(_A);
            else
                ret ~= RMW(ShiftLeft("data"), chip);
            break;
        case "ROL":
            if (op == 0x2a)
                ret ~= RotateLeft(_A);
            else
                ret ~= RMW(RotateLeft("data"), chip);
            break;
        case "LSR":
            if (op == 0x4a)
                ret ~= ShiftRight(_A);
            else
                ret ~= RMW(ShiftRight("data"), chip);
            break;
        case "ROR":
            if (op == 0x6a)
                ret ~= RotateRight(_A);
            else
                ret ~= RMW(RotateRight("data"), chip);
            break;
        case "TRB":
                ret ~= RMW(TestReset(), chip);
                break;
        case "TSB":
                ret ~= RMW(TestSet(), chip);
                break;
        case "LAS":
            ret ~= LAS_Undoc();
            break;
        case "LAX":
            if (op != 0xAB)
                ret ~= Load(_A ~ " = " ~ _X);
            else
                ret ~= LAX_IMM_Undoc();
            break;
        case "SAX":
            ret ~= Store(_A ~ " & " ~ _X);
            break;
        case "ANC":
            ret ~= ANC_Undoc();
            break;
        case "ALR":
            ret ~= ALR_Undoc();
            break;
        case "ARR":
            ret ~= ARR_Undoc();
            break;
        case "AXS":
            ret ~= AXS_Undoc();
            break;
        case "AHX":
            ret ~= Strange_Undoc(_A ~ " &" ~ _X);
            break;
        case "SHY":
            ret ~= Strange_Undoc(_Y);
            break;
        case "SHX":
            ret ~= Strange_Undoc(_X);
            break;
        case "TAS":
            ret ~= Strange_Undoc(_S ~ " = " ~ _A ~ " & " ~ _X);
            break;
        case "XAA":
            ret ~= XAA_Undoc();
            break;
        case "SLO":
            ret ~= RMW_Undoc(ShiftLeft("data"),
                             SetNZ(_A ~ " |= data"));
            break;
        case "RLA":
            ret ~= RMW_Undoc(RotateLeft("data"),
                             SetNZ(_A ~ " &= data"));
            break;
        case "SRE":
            ret ~= RMW_Undoc(ShiftRight("data"),
                             SetNZ(_A ~ " ^= data"));
            break;
        case "RRA":
            ret ~= RMW_Undoc(RotateRight("data"), AddBase(chip));
            break;
        case "DCP":
            ret ~= RMW_Undoc(Dec("data"), CompareBase(_A));
            break;
        case "ISC":
            ret ~= RMW_Undoc(Inc("data"), SubBase(chip));
            break;
    }
    return ret ~ Done();
}


string Break()
{
    return IncPC() ~
           PushPC() ~
           Push(Attr("statusToByte()")) ~
           SetFlag(_I) ~
           ReadWord(_PC, "IRQ_VECTOR");
}


string JumpSub()
{
    return ReadOp(Local("ushort", "address")) ~
           Peek(STACK) ~
           PushPC() ~
           LoadHiByte("address", _PC ~ "++") ~
           _PC ~ " = address;\n";
}


string RetSub()
{
    return Peek(STACK) ~
           PullPC() ~
           Peek(_PC) ~
           IncPC();
}


string RetInt()
{
    return PullStatus() ~
           PullPC();
}


string Jump(int op, string chip)
{
    bool nmos = (chip == "6502");
    bool cmos = !nmos;

    if (op == 0x4c)
        return _PC ~ " = address;\n";
    else if (op == 0x6c)
        return ReadWordOp("ushort", "base") ~
               If!(cmos)(
                   Peek(_PC)) ~
               ReadWordBasic(_PC, "base",
                             If!(nmos)(
                                 "(base & 0xFF00) | cast(ubyte)(base + 1)",
                                 "cast(ushort)(base + 1)"));
    else if (op == 0x7c)
        return ReadWordOp("ushort", "base") ~
               Peek(_PC) ~
               ReadWord(_PC, "cast(ushort)(base + " ~ _X ~ ")");
    return "";
}


string Branch(string check, string chip)
{
    return ReadOp(Local("ushort", "base")) ~
           "if (" ~ check ~ ")\n{\n" ~
               Peek(_PC) ~
               Local("ushort", "address") ~
               " = cast(ushort)(" ~ _PC ~ " + cast(byte)base);\n" ~
               CheckShortcut(_PC, "address", chip, 0) ~
               _PC ~ " = address;\n" ~
           "}\n";
}


string Nop(int mode)
{
    if (mode == IMP ||  mode == NP1 || mode == NP8)
        return "";
    else
        return Tick() ~
               ReadRaw("address") ~ ";\n";
}


string Transfer(string source, string dest, bool setNZ = true)
{
    return dest ~ " = " ~ source ~ ";\n" ~
           (setNZ ? SetNZ(dest) : "");
}


string PullReg(string reg)
{
    return Peek(STACK) ~
           PullInto(reg) ~
           SetNZ(reg);
}


string PushReg(string reg)
{
    return Push(reg);
}


string Load(string reg)
{
    return ReadInto(reg, "address") ~
           SetNZ(reg);
}


string Store(string reg,)
{
    return Write("address", reg);
}


string Compare(string reg)
{
    return ReadInto(Local("ubyte", "data"), "address") ~
           CompareBase(reg);
}

string CompareBase(string reg)
{
    return UpdateFlag(_C, reg ~ " >= data") ~
           SetNZ("cast(ubyte)(" ~ reg ~ " - data)");
}


string Bit(int mode)
{
    bool notImm = (mode != IMM);

    return ReadInto(Local("ubyte", "data"), "address") ~
           If!(notImm)(
               _N ~ " = data;\n" ~
               _V ~ " = ((data & 0x40) != 0);\n") ~
           _Z ~ " = (" ~ _A ~ " & data);\n";
}


string Logic(string action)
{
    return ReadInto(_A, action, "address") ~
           SetNZ(_A);
}


string Add(string chip)
{
    return ReadInto(Local("ubyte", "data"), "address") ~
           AddBase(chip);
}

string AddBase(string chip)
{
    return "if (" ~ _D ~ ")\n{\n" ~
               DecAdd(chip) ~
           "}\nelse\n{\n" ~
               HexAdd() ~
           "}\n";
}

string HexAdd()
{
    return "uint sum = " ~ _A ~ " + data + " ~ _C ~ ";\n" ~
           _V ~
           " = (!((" ~ _A ~ " ^ data) & 0x80)) && ((data ^ sum) & 0x80);\n" ~
           _C ~ " = (sum > 0xFF);\n" ~
           SetNZ(_A ~ " = cast(ubyte)sum");
}

string DecAdd(string chip)
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
               SetNZ(_A ~ " = cast(ubyte)a") ~ Peek(_PC),
               _A ~ " = cast(ubyte)a;\n");
}


string Sub(string chip)
{
    return ReadInto(Local("ubyte", "data"), "address") ~
           SubBase(chip);
}

string SubBase(string chip)
{
    bool nmos = (chip == "6502");

    return "if (" ~ _D ~ ")\n{\n" ~
               If!(nmos)(DecSubNMOS(), DecSubCMOS()) ~
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

string DecSubCMOS()
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
           Peek(_PC) ~
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


string RMW(string action, string chip)
{
    bool nmos = (chip == "6502");

    return ReadInto(Local("ubyte", "data"), "address") ~
           If!(nmos)(Poke("address", "data"),
                     Peek("address")) ~
           action ~
           Write("address", "data");
}


string RMW_Undoc(string action1, string action2)
{
    return ReadInto(Local("ubyte", "data"), "address") ~
           Poke("address", "data") ~
           action1 ~
           Write("address", "data") ~
           action2;
}


string LAS_Undoc()
{
    return ReadInto(Local("ubyte", "data"), "address") ~
           SetNZ(_X ~ " = " ~ _A ~ " = (" ~ _S ~ " & data)");
}


string ARR_Undoc()
{
    return ReadInto(Local("ubyte", "data"), "address") ~
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


string ANC_Undoc()
{
    return ReadInto(_A, "address") ~
           SetNZ(_A) ~
           _C ~ " = (" ~ _A ~ " > 0x7f);\n";
}


string ALR_Undoc()
{
    return ReadInto(Local("ubyte", "data"), "address") ~
           _A ~ " &= data;\n" ~
           ShiftRight(_A);
}


string AXS_Undoc()
{
    return ReadInto(Local("ubyte", "data"), "address") ~
           _X ~ " &= " ~ _A ~ ";\n" ~
           CompareBase(_X);
}


/*
 * This opcode is unstable on certain machines; see
 * http://visual6502.org/wiki/index.php?title=6502_Opcode_8B_(XAA,ANE)
 */
string XAA_Undoc()
{
    /*
     * As far as I can tell, the only programs in the wild that depend
     * on this opcode are certain C64 Mastertronic tape loaders; this
     * magic value is used in the VICE emulator to make them work.
     */
    string MAGIC = "0xff";

    return ReadInto(Local("ubyte", "data"), "address") ~
           _A ~ " = ((" ~ _A ~ " | " ~ MAGIC ~ ") & " ~ _X ~ " & data);\n" ~
           SetNZ(_A);
}


/*
 * This opcode is unstable on certain machines.
 */
string LAX_IMM_Undoc()
{
    // From the VICE emulator.
    string MAGIC = "0xee";

    return ReadInto(Local("ubyte", "data"), "address") ~
           _A ~ " = ((" ~ _A ~ " | " ~ MAGIC ~ ") & " ~ _X ~ " & data);\n" ~
           SetNZ(_A);
}


// TODO: these are affected by DMA on the C64.
string Strange_Undoc(string val)
{
    return "ubyte addrHi = cast(ubyte)((address >> 8) + 1);\n" ~
           Local("ubyte", "data") ~ " = " ~ val ~ " & addrHi;\n" ~
           "address = (guess == address) ? address : " ~
           "((data << 8) | (address & 0xff));\n" ~
           Write("address", "data");
}


string Local(string type)
{
    return "";
}

string Local(string type, string var)
{
    return var;
}

string Attr(string var)
{
    return var;
}


string Address(int mode, int exCyc, string chip)
{
    final switch (mode)
    {
        case IMP:
            return AddrIMP();
        case IMM:
            return AddrIMM();
        case ZP:
            return AddrZP();
        case ZPX:
            return AddrZPXY(_X, chip);
        case ZPY:
            return AddrZPXY(_Y, chip);
        case IZX:
            return AddrIZX(chip);
        case IZY:
            return AddrIZY(chip, exCyc);
        case ABS:
            return AddrABS();
        case ABX:
            return AddrABXY(_X, chip, exCyc);
        case ABY:
            return AddrABXY(_Y, chip, exCyc);
        case IND:
            // handled by Jump()
            return "";
        case REL:
            // handled by Branch()
            return "";
        case ZPI:
            return AddrZPI();
        case ABI:
            // handled in Jump()
            return "";
        case NP1:
            // handled implicitly (the 1 cycle is the opcode fetch)
            return "";
        case NP8:
            return AddrNP8();
        case KIL:
            // handled by case KIL in OpBody()
            return "";
    }
    return "";
}


string AddrIMM()
{
     return Local("ushort") ~ "address = " ~ _PC ~ "++;\n";
}

string AddrIMP()
{
    return Peek(_PC);
}

string AddrZP()
{
    return ReadOp(Local("ushort", "address"));
}

string AddrZPXY(string reg, string chip)
{
    bool nmos = (chip == "6502");

    return ReadOp(Local("ushort", "base")) ~
           If!(nmos)(
               Peek("base"),
               Peek(_PC)) ~
           Local("ushort") ~
           "address = cast(ubyte)(base + " ~ reg ~ ");\n";
}

string AddrIZX(string chip)
{
    bool nmos = (chip == "6502");

    return ReadOp(Local("ushort", "base")) ~
           If!(nmos)(
               Peek("base"),
               Peek(_PC)) ~
           ReadWordZP("ushort", "address", "base + " ~ _X);
}

string AddrIZY(string chip, int exCyc)
{
    return ReadOp("ubyte vector") ~
           ReadWordZP("ushort", "base", "vector") ~
           Local("ushort") ~
           "address = cast(ushort)(base + " ~ _Y ~ ");\n" ~
           CheckShortcut("base", "address", chip, exCyc);
}

string AddrABS()
{
    return ReadWordOp("ushort", "address");
}

string AddrABXY(string reg, string chip, int exCyc)
{
    return ReadWordOp("ushort", "base") ~
           Local("ushort") ~ "address = cast(ushort)(base + " ~ reg ~ ");\n" ~
           CheckShortcut("base", "address", chip, exCyc);
}

string AddrZPI()
{
    return ReadOp(Local("ushort", "base")) ~
           ReadWordZP("ushort", "address", "base");
}

string AddrNP8()
{
    return ReadOp(Local("ushort", "base")) ~
           Peek(_PC) ~
           IncPC() ~
           Peek("0xff00 | base") ~
           Peek("0xffff") ~
           Peek("0xffff") ~
           Peek("0xffff") ~
           Peek("0xffff");
}

string CheckShortcut(string base, string addr, string chip, int exCyc)
{
    bool nmos = (chip == "6502");

    return "ushort guess = (" ~ base ~ " & 0xFF00) | cast(ubyte)" ~ addr ~ ";\n" ~
           "if (guess != " ~ addr ~ ")\n{\n" ~
               If!(nmos)(Peek("guess"),
                         Peek(_PC)) ~
           "}\n" ~
           If!(exCyc)("else\n{\n" ~ Peek("address") ~ "}\n");
}


string ReadInto(string var, string action, string addr)
{
    return Tick() ~
           var ~ " " ~ action ~ " " ~ ReadRaw("(" ~ addr ~ ")") ~ ";\n";
}

string ReadInto(string var, string addr)
{
    return ReadInto(var, "=", addr);
}

string ReadOp(string var)
{
    return ReadInto(var, _PC ~ "++");
}

string ReadRaw(string addr)
{
    return Attr("memory") ~ ".read(" ~ addr ~")";
}

string ReadWordBasic(string type, string var, string addr1, string addr2)
{
    return LoadLoByte(type, var, addr1) ~
           LoadHiByte(var, addr2);
}

string ReadWordBasic(string var, string addr1, string addr2)
{
    return ReadWordBasic("", var, addr1, addr2);
}

string ReadWord(string type, string var, string addr)
{
    return ReadWordBasic(type, var, addr, "cast(ushort)(" ~ addr ~ " + 1)");
}

string ReadWord(string var, string addr)
{
    return ReadWord("", var, addr);
}

string ReadWordZP(string type, string var, string addr)
{
    return ReadWordBasic(type, var, "cast(ubyte)( " ~ addr ~ ")",
                                    "cast(ubyte)(" ~ addr ~ " + 1)");
}

string ReadWordZP(string var, string addr)
{
    return ReadWordZP("", var, addr);
}

string ReadWordOp(string type, string var)
{
    return ReadWordBasic(type, var, _PC ~ "++", _PC ~ "++");
}

string ReadWordOp(string var)
{
    return ReadWordOp("", var);
}

string Tick()
{
    return If!(cumulative)("++cycles;\n", Attr("clock") ~ ".tick();\n");
}

string Peek(string addr)
{
    return Tick() ~
           If!(strict)(Attr("memory") ~ ".read(" ~ addr ~");\n");
}

string Poke(string addr, string val)
{
    return Tick() ~
           If!(strict)(
               Attr("memory") ~ ".write(" ~ addr ~ ", " ~ val ~ ");\n");
}

string Write(string addr, string val)
{
    return Tick() ~
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

string PullStatus()
{
    return Peek(STACK) ~
           IncSP() ~
           Tick() ~
           Attr("statusFromByte") ~ "(" ~
           ReadRaw(STACK) ~ ");\n";
}

string PullInto(string var)
{
    return IncSP() ~
           ReadInto(var, STACK);
}

string Push(string val)
{
    return Write(STACK, val) ~
           DecSP();
}

string PushPC()
{
    return Push(HiByte(_PC)) ~
           Push(LoByte(_PC));
}


string PullPC()
{
    return PullInto(_PC) ~
           IncSP() ~
           LoadHiByte(_PC, STACK);
}

string LoadLoByte(string type, string var, string addr)
{
    return Tick() ~
           Local(type, var) ~ " = " ~ ReadRaw(addr) ~ ";\n";
}

string LoadHiByte(string var, string addr)
{
    return Tick() ~
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

string Done()
{
    return If!(cumulative)(Attr("clock") ~ ".tick(cycles);\n");
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
