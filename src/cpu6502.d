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
}

// OpSwitch: each opcode is inlined in a 256-case switch.
version(OpSwitch)
{
    enum versionCheck = 3;
    enum opArray = false;
}

// OpNestedSwitch: each opcode is inlined in a nested switch.
// (The outer one switches on the high byte, with each case switching
// on the low byte.)
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

    ubyte N, Z;
    bool V, D, I, C;

    static if (opArray) mixin(OpArrayDef());

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
        C = ((val & 0x01) != 0);
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
        do {
            // XXX check signals
            // XXX figure out cumulative/final cycle stuff
            static if (cumulative) {}
            else
                clock.tick();
            opcode = memory.read(PC++);
            mixin(OpExecute(_chip));
        } while (keepRunning);
    }

    version(OpDelegates) mixin (OpBodies(_chip));
}


version(OpFunctions) mixin(OpBodies("6502"));
version(OpFunctions) mixin(OpBodies("65C02"));


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
                ret ~= "opcodes[0x" ~ Hex2(op) ~ "] = &opcode_" ~ Hex2(op) ~
                       ";\n";
            version(OpFunctions)
                ret ~= "opcodes[0x" ~ Hex2(op) ~ "] = &opcode_" ~ Hex2(op) ~
                       "!(typeof(this));\n";
        }
        return ret;
    }
}

string OpBodies(string chip)
{
    static if (!opArray) return "";
    else
    {
        string ret;
        foreach (op; 0..256)
        {
            version(OpDelegates)
                ret ~= "final void opcode_" ~ Hex2(op) ~ "()\n{\n" ~
                       OpBody(op, chip) ~ "}\n";
            version(OpFunctions)
                ret ~= "void opcode_" ~ Hex2(op) ~
                       "(T)(T cpu) if (is" ~ chip ~ "!T)\n{\n" ~
                       OpBody(op, chip) ~ "}\n";
        }
        return ret;
    }
}

string OpExecute(string chip)
{
    version(OpDelegates)
        return q{opcodes[opcode]();};
    version(OpFunctions)
        return q{opcodes[opcode](this);};
    version(OpSwitch)
        return Switch256(chip);
    version(OpNestedSwitch)
        return Switch16x16(chip);
}

string Switch256(string chip)
{
    string ret = "final switch (opcode)\n{\n";
    foreach (op; 0..256)
        ret ~= "case 0x" ~ Hex2(op) ~ ":\n" ~ OpBody(op, chip) ~ "break;\n\n";
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
            ret ~= "case 0x0" ~ Hex1(opLo) ~ ":\n" ~ OpBody(op, chip) ~
                   "break;\n\n";
        }
        ret ~= "}\nbreak;\n";
    }
    return ret ~ "}\n";
}


string OpBody(int op, string chip)
{
    return "";
}


// Custom hex printing.
// (to!string(x, 16) uses uppercase, which makes "8" and "B" hard to
// tell apart, and format("%0.2x", x) can't be used in CTFE.)

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


alias Cpu!("6502", false, false) T1;
alias Cpu!("6502", false, true) T2;
alias Cpu!("6502", true, false) T3;
alias Cpu!("6502", true, true) T4;
alias Cpu!("65C02", false, false) T5;
alias Cpu!("65C02", false, true) T6;
alias Cpu!("65C02", true, false) T7;
alias Cpu!("65C02", true, true) T8;

void main()
{
    import std.stdio;
    writeln(Switch16x16("6502"));
}
