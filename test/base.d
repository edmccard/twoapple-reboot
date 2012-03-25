module test.base;


import std.algorithm, std.conv, std.exception, std.random, std.range,
       std.string, std.traits;

public import test.wrap6502;


class TestException : Exception { this(string msg) { super(msg); } }


/*
 * Emulates zero page, stack, and 3 additional pages of "main memory"
 * starting at a user-defined address. Accesses outside the defined
 * address space raise an exception.
 */
struct TestMemory
{
private:
    ubyte[0x200] data1;
    ubyte[0x300] data2;
    immutable ushort data2_base;
    immutable size_t data2_max;

public:
    /*
     * Constructs a TestMemory with data filled in from an array of
     * Blocks.
     *
     * The blocks do not need to be contiguous, or ordered by their
     * base address, but note that the base address of the 3-page
     * "main memory" will be that of the first block with a base
     * address greater than 0x01FF (there must be at least one such
     * block).
     */
    this(const Block[] blocks ...)
    {
        foreach (block; blocks)
        {
            auto base = block.base;
            auto data = block.data;
            if (base < 0x200)
            {
                enforce(base + data.length <= 0x200,
                        format("Address out of bounds %0.4x", base));
                data1[base..base + data.length] = data[];
            }
            else
            {
                if (!data2_base)
                {
                    if (base > 0xFD00)
                        data2_base = 0xFD00;
                    else
                        data2_base = base;
                    data2_max = base + 0x300;
                }
                enforce(base + data.length <= data2_max,
                        format("Address  out of bounds %0.4x", base));
                auto last = base + data.length;
                data2[base-data2_base..last-data2_base] = data[];
            }
        }
        enforce(data2_base, "Missing memory > 0x0200");
    }

    ubyte read(ushort addr)
    {
        if (addr < 0x0200)
            return data1[addr];
        else if (addr >= data2_base && addr < data2_max)
            return data2[addr - data2_base];
        else
            throw new TestException(format("read %0.4x", addr));
    }

    void write(ushort addr, ubyte val)
    {
        if (addr < 0x0200)
            data1[addr] = val;
        else if (addr >= data2_base && addr < data2_max)
            data2[addr - data2_base] = val;
        else
            throw new TestException(format("write %0.4x", addr));
    }

    ubyte opIndex(size_t i1)
    {
        auto addr = cast(ushort)i1;
        enforce(addr < 0x0200 || (addr >= data2_base && addr < data2_max),
                "Read out of bounds");
        return read(addr);
    }
}

/*
 * A block of memory with a given base address.
 */
struct Block
{
    ushort base;
    ubyte[] data;

    string toString() const
    {
        return format("Block(%0.4X, %s)", base, formatMemory());
    }

    string formatMemory(int max = 3) const
    {
        if (max > data.length) max = data.length;
        auto hexbytes = map!(`format("%0.2X", a)`)(data[0..max]);
        auto ret = join(array(hexbytes), " ");
        if (data.length > max)
            ret ~= format(" (%d more bytes)", data.length - max);
        return "[" ~ ret ~ "]";
    }
}


struct Ref(T)
if (isPointer!T)
{
    private const(T) data;
    this(T ptr) { data = ptr; }
    auto deref() { return *data; }
    alias deref this;

    string toString () const { return format("%s", *data); }
}

auto constRef(T)(T ptr)
if (isPointer!T)
{
    return Ref!(const(T))(ptr);
}


enum Flag : ubyte
{
    C = 0x01,
    Z = 0x02,
    I = 0x04,
    D = 0x08,
    V = 0x40,
    N = 0x80
}

void updateFlag(T)(T cpu, Flag f, bool val)
if (isCpu!T)
{
    if (val)
        setFlag(cpu, f);
    else
        clearFlag(cpu, f);
}


void expectBranch(T)(T cpu, ubyte opcode)
if (isCpu!T)
{
    switch (opcode)
    {
        case /*BPL*/ 0x10: clearFlag(cpu, Flag.N); break;
        case /*BMI*/ 0x30: setFlag(cpu, Flag.N); break;
        case /*BVC*/ 0x50: clearFlag(cpu, Flag.V); break;
        case /*BVS*/ 0x70: setFlag(cpu, Flag.V); break;
        case /*BCC*/ 0x90: clearFlag(cpu, Flag.C); break;
        case /*BCS*/ 0xB0: setFlag(cpu, Flag.C); break;
        case /*BNE*/ 0xD0: clearFlag(cpu, Flag.Z); break;
        case /*BEQ*/ 0xF0: setFlag(cpu, Flag.Z); break;
        default:
            if (isCMOS!T) { if (opcode == /*BRA*/ 0x80) break; }
            enforce(0, format("not a branching opcpde %0.2X", opcode));
    }
}

bool wouldBranch(T)(T cpu, ubyte opcode)
if (isCpu!T)
{
    switch (opcode)
    {
        case /*BPL*/ 0x10: return !getFlag(cpu, Flag.N);
        case /*BMI*/ 0x30: return getFlag(cpu, Flag.N);
        case /*BVC*/ 0x50: return !getFlag(cpu, Flag.V);
        case /*BVS*/ 0x70: return getFlag(cpu, Flag.V);
        case /*BCC*/ 0x90: return !getFlag(cpu, Flag.C);
        case /*BCS*/ 0xB0: return getFlag(cpu, Flag.C);
        case /*BNE*/ 0xD0: return !getFlag(cpu, Flag.Z);
        case /*BEQ*/ 0xF0: return getFlag(cpu, Flag.Z);
        default:
            if (isCMOS!T) { if (opcode == /*BRA*/ 0x80) return true; }
            assert(0, format("not a branching opcpde %0.2X", opcode));
    }
}

void expectNoBranch(T)(T cpu, ubyte opcode)
{
    switch (opcode)
    {
        case /*BPL*/ 0x10: setFlag(cpu, Flag.N); break;
        case /*BMI*/ 0x30: clearFlag(cpu, Flag.N); break;
        case /*BVC*/ 0x50: setFlag(cpu, Flag.V); break;
        case /*BVS*/ 0x70: clearFlag(cpu, Flag.V); break;
        case /*BCC*/ 0x90: setFlag(cpu, Flag.C); break;
        case /*BCS*/ 0xB0: clearFlag(cpu, Flag.C); break;
        case /*BNE*/ 0xD0: setFlag(cpu, Flag.Z); break;
        case /*BEQ*/ 0xF0: clearFlag(cpu, Flag.Z); break;
        default:
            if (isCMOS!T)
                enforce(opcode != 0x80, "BRA can never not branch");
            enforce(0, format("not a branching opcpde %0.2X", opcode));
    }
}


ushort address(ubyte l, ubyte h)
{
    return cast(ushort)((h << 8) | l);
}

ushort pageWrapAdd(ushort base, int offset)
{
    return (base & 0xFF00) + cast(ubyte)((base & 0xFF) + offset);
}

ushort pageCrossAdd(ushort base, int offset)
{
    return cast(ushort)(base + offset);
}


// A random value to use for "uninitialized" memory.
ubyte XX()
{
    return cast(ubyte)uniform(0, 256);
}

// A number different from some other number.
ubyte notXX(ubyte val)
{
    return cast(ubyte)(val ^ 0xAA);
}


// 2-cycle opcodes which neither read nor write.
template REG_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum REG_OPS = cast(ubyte[])
            x"0A 18 1A 2A 38 3A 4A 58 5A 6A 78 7A 8A 88 98 9A
              A8 AA B8 BA C8 CA D8 DA E8 EA F8 FA";
    else
        enum REG_OPS = cast(ubyte[])
            x"0A 18 1A 2A 38 3A 4A 58 6A 78 8A 88 98 9A
              A8 AA B8 BA C8 CA D8 E8 EA F8";
}


// Opcodes which push to the stack.
template PUSH_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum PUSH_OPS = cast(ubyte[])x"08 48";
    else
        enum PUSH_OPS = cast(ubyte[])x"08 48 5A DA";
}


// Opcodes which pull from the stack.
template PULL_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum PULL_OPS = cast(ubyte[])x"28 68";
    else
        enum PULL_OPS = cast(ubyte[])x"28 68 7A FA";
}


// Relative branch opcodes.
template BRANCH_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum BRANCH_OPS = cast(ubyte[])x"10 30 50 70    90 B0 D0 F0";
    else
        enum BRANCH_OPS = cast(ubyte[])x"10 30 50 70 80 90 B0 D0 F0";
}


// Write-only opcodes.
template WRITE_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum WRITE_OPS = cast(ubyte[])x"81 83 84 85 86 87       8C 8D 8E 8F
                                        91 93 94 95 96 97 99 9B 9C 9D 9E 9F";
    else
        enum WRITE_OPS = cast(ubyte[])x"64 74 81 84 85 86 8C 8D 8E
                                        91 92 94 95 96 99 9C 9D 9E";
}


// Read-only opcodes (excluding ADC/SBC).
template READ_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum READ_OPS = cast(ubyte[])
            x"01 04 05 09 0B 0C 0D 11 14 15 19 1C 1D
              21 24 25 29 2B 2C 2D 31 34 35 39 3C 3D
              41 44 45 49 4B 4D 51 54 55 59 5C 5D
              64 6B 74 7C 82 89 8B
              A0 A1 A2 A3 A4 A5 A6 A7 A9 AB AC AD AE AF
              B1 B3 B4 B5 B6 B7 B9 BB BC BD BE BF
              C0 C1 C2 C4 C5 C9 CB CC CD D1 D4 D5 D9 DC DD
              E0 E2 E4 EC F4 FC";
    else
        enum READ_OPS = cast(ubyte[])
            x"01 02 05 09 0D 11 12 15 19 1D
              21 22 24 25 29 2C 2D 31 32 34 35 39 3C 3D
              41 42 44 45 49 4D 51 52 54 55 59 5D 62 82 89
              A0 A1 A2 A4 A5 A6 A9 AC AD AE
              B2 B1 B4 B5 B6 B9 BC BD BE
              C0 C1 C2 C4 C5 C9 CC CD D1 D2 D4 D5 D9 DC DD
              E0 E2 E4 EC F4 FC";
}


// Opcodes affected by decimal mode (ADC/SBC).
template BCD_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum BCD_OPS = cast(ubyte[])x"61 65 69 6B 6D 71 75 79 7D
                                      E1 E5 E9 EB ED F1 F5 F9 FD";
    else
        enum BCD_OPS = cast(ubyte[])x"61 65 69 6D 71 72 75 79 7D
                                      E1 E5 E9 ED F1 F2 F5 F9 FD";
}


// Opcodes which both read and write.
template RMW_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum RMW_OPS = cast(ubyte[])
            x"03 06 07 0E 0F 13 16 17 1B 1E 1F
              23 26 27 2E 2F 33 36 37 3B 3E 3F
              43 46 47 4E 4F 53 56 57 5B 5E 5F
              63 66 67 6E 6F 73 76 77 7B 7E 7F
              C3 C6 C7 CE CF D3 D6 D7 DB DE DF
              E3 E6 E7 EE EF F3 F6 F7 FB FE FF";
    else
        enum RMW_OPS = cast(ubyte[])
            x"04 06 0C 0E 14 16 1C 1E 26 2E 36 3E 46 4E 56 5E
                 66    6E    76    7E C6 CE D6 DE E6 EE F6 FE";
}


// Opcodes with immediate address mode.
template IMM_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum IMM_OPS = cast(ubyte[])x"09 0B 29 2B 49 4B 69 6B
                                      80 82 89 8B A0 A2 A9 AB
                                      C0 C2 C9 CB E0 E2 E9 EB";
    else
        enum IMM_OPS = cast(ubyte[])x"02 09 22 29 42 49 62 69 82
                                      89 A0 A2 A9 C0 C2 C9 E0 E2 E9";
}


// Opcodes with zeropage address mode.
template ZPG_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ZPG_OPS = cast(ubyte[])x"04 05 06 07 24 25 26 27
                                      44 45 46 47 64 65 66 67
                                      84 85 86 87 A4 A5 A6 A7
                                      C4 C5 C6 C7 E4 E5 E6 E7";
    else
        enum ZPG_OPS = cast(ubyte[])x"04 05 06 14 24 25 26 44 45 46 64 65 66
                                      84 85 86 A4 A5 A6 C4 C5 C6 E4 E5 E6";
}


// Opcodes with zeropage,x address mode.
template ZPX_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ZPX_OPS = cast(ubyte[])x"14 15 16 17 34 35 36 37
                                      54 55 56 57 74 75 76 77
                                      94 95 B4 B5 D4 D5 D6 D7
                                      F4 F5 F6 F7";
    else
        enum ZPX_OPS = cast(ubyte[])x"15 16 34 35 36 54 55 56 74 75 76
                                      94 95 B4 B5 D4 D5 D6 F4 F5 F6";
}


// Opcodes with zeropage,y address mode.
template ZPY_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ZPY_OPS = cast(ubyte[])x"96 97 B6 B7";
    else
        enum ZPY_OPS = cast(ubyte[])x"96 B6";
}


// Opcodes with absolute address mode.
template ABS_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ABS_OPS = cast(ubyte[])x"0C 0D 0E 0F 2C 2D 2E 2F
                                      4C 4D 4E 4F    6D 6E 6F
                                      8C 8D 8E 8F AC AD AE AF
                                      CC CD CE CF EC ED EE EF";
    else
        enum ABS_OPS = cast(ubyte[])x"0C 0D 0E 1C 2C 2D 2E 4C 4D 4E    6D 6E
                                      8C 8D 8E 9C AC AD AE CC CD CE EC ED EE";
}


// Opcodes with absolute,x address mode.
template ABX_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ABX_OPS = cast(ubyte[])x"1C 1D 1E 1F 3C 3D 3E 3F
                                      5C 5D 5E 5F 7C 7D 7E 7F
                                      9C 9D BC BD DC DD DE DF
                                      FC FD FE FF";
    else
        enum ABX_OPS = cast(ubyte[])x"1D 1E 3C 3D 3E 5D 5E 7D 7E
                                      9D 9E BC BD DC DD DE FC FD FE";
}


// Opcodes with absolute,y address mode.
template ABY_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ABY_OPS = cast(ubyte[])x"19 1B 39 3B 59 5B 79 7B
                                      99 9B 9E 9F B9 BB BE BF
                                      D9 DB F9 FB";
    else
        enum ABY_OPS = cast(ubyte[])x"19 39 59 79 99 B9 BE D9 F9";
}


// Opcodes with indirect zeropage,x address mode.
template IZX_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum IZX_OPS = cast(ubyte[])x"01 03 21 23 41 43 61 63
                                      81 83 A1 A3 C1 C3 E1 E3";
    else
        enum IZX_OPS = cast(ubyte[])x"01 21 41 61 81 A1 C1 E1";
}


// Opcodes with indirect zeropage,y address mode.
template IZY_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum IZY_OPS = cast(ubyte[])x"11 13 31 33 51 53 71 73
                                      91 93 B1 B3 D1 D3 F1 F3";
    else
        enum IZY_OPS = cast(ubyte[])x"11 31 51 71 91 B1 D1 F1";
}


// Opcodes with indirect zeropage address mode.
template ZPI_OPS(T)
if (isCpu!T && isCMOS!T)
{
    enum ZPI_OPS = cast(ubyte[])x"12 32 52 72 92 B2 D2 F2";
}


// 1-cycle NOPS.
template NOP1_OPS(T)
if (isCpu!T && isCMOS!T)
{
    enum NOP1_OPS = cast(ubyte[])
        x"03 13 23 33 43 53 63 73 83 93 A3 B3 C3 D3 E3 F3
          07 17 27 37 47 57 67 77 87 97 A7 B7 C7 D7 E7 F7
          0B 1B 2B 3B 4B 5B 6B 7B 8B 9B AB BB CB DB EB FB
          0F 1F 2F 3F 4F 5F 6F 7F 8F 9F AF BF CF DF EF FF";
}


// NMOS HLT opcodes.
template HLT_OPS(T)
if (isCpu!T && isNMOS!T)
{
    enum HLT_OPS = cast(ubyte[])x"02 12 22 32 42 52 62 72 92 B2 D2 F2";
}


// Associates opcodes with test setup functions.
string getMemSetup(T)()
if (isCpu!T)
{
    string[] tmp1 = new string[256], tmp2 = new string[256];
    tmp2[] = "        setups2 = &setup_data_none!T;\n";

    void call_addr(const(ubyte[]) list, string fname)
    {
        foreach(op; list)
        {
            tmp1[op] =
                "        setups1 = &setup_address_" ~ fname ~ "!T;\n";
        }
    }

    void call_data(const(ubyte[]) list, string fname)
    {
        foreach(op; list)
        {
            tmp2[op] =
                "        setups2 = &setup_data_" ~ fname ~ "!T;\n";
        }
    }


    call_addr(IMM_OPS!T, "imm");
    call_addr(ZPG_OPS!T, "zpg");
    call_addr(ZPX_OPS!T, "zpxy");
    call_addr(ZPY_OPS!T, "zpxy");
    call_addr(ABS_OPS!T, "abs");
    call_addr(ABX_OPS!T, "abxy");
    call_addr(ABY_OPS!T, "abxy");
    call_addr(IZX_OPS!T, "izx");
    call_addr(IZY_OPS!T, "izy");
    call_addr(REG_OPS!T, "reg");
    call_addr(PUSH_OPS!T, "push");
    call_addr(PULL_OPS!T, "pull");
    call_addr(BRANCH_OPS!T, "branch");
    call_addr([0x00], "op_BRK");
    call_addr([0x20], "op_JSR");
    call_addr([0x40, 0x60], "op_RTx");
    call_addr([0x4C], "op_JMP_abs");
    call_addr([0x6C], "op_JMP_ind");

    call_data([0x08], "op_PHP");
    call_data([0x28], "op_PLP");
    call_data([0x00], "op_BRK");
    call_data([0x40], "op_RTI");
    static if (isNMOS!T)
    {
        call_addr(HLT_OPS!T, "none");

        call_data([0x48], "push");
        call_data([0x68], "pull");
    }
    else
    {
        call_addr(ZPI_OPS!T, "zpi");
        call_addr(NOP1_OPS!T, "reg");
        call_addr([0x5C], "op_5C");
        call_addr([0x7C], "op_JMP_inx");

        call_data([0x48, 0x5A, 0xDA], "push");
        call_data([0x68, 0x7A, 0xFA], "pull");
    }

    auto ret = "final switch (opcode)\n{\n";
    for (auto i = 0; i < 256; i++)
    {
        ret ~= "    case 0x" ~ to!string(i, 16) ~ ":\n" ~
               tmp1[i] ~ tmp2[i] ~ "        break;\n";
    }
    return ret ~ "\n}";
}


template addrsetup_t(T)
{
    alias Block[] delegate(T, out ushort, out string) addrsetup_t;
}

template datasetup_t(T)
{
    alias Block[] delegate(T, ushort, out string) datasetup_t;
}


auto setup_address_none(T)(ubyte opcode)
if (isCpu!T)
{
    return cast(addrsetup_t!T[])[];
}

auto setup_address_imm(T)(ubyte opcode)
if (isCpu!T)
{
    assert(IMM_OPS!T.canFind(opcode));

    auto setup(T cpu, out ushort addr, out string name)
    {
        name = "imm";
        addr = 0x1001;
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode])];
    }

    return [&setup];
}

auto setup_address_zpg(T)(ubyte opcode)
if (isCpu!T)
{
    assert(ZPG_OPS!T.canFind(opcode));

    auto setup(T cpu, out ushort addr, out string name)
    {
        name = "zpg";
        addr = 0x0070;
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode, 0x70])];
    }

    return [&setup];
}

auto setup_address_zpxy(T)(ubyte opcode)
if (isCpu!T)
{
    bool useX = ZPX_OPS!T.canFind(opcode);
    assert(useX || ZPY_OPS!T.canFind(opcode));

    auto setup(T cpu, out ushort addr, out string name, ubyte idx,
               ubyte opcode)
    {
        name = (useX ? "zpx" : "zpy");
        addr = pageWrapAdd(0x0070, idx);
        if (useX)
        {
            setX(cpu, idx); setY(cpu, 0x10);
        }
        else
        {
            setY(cpu, idx); setX(cpu, 0x10);
        }
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode, 0x70])];
    }

    auto setup_nowrap(T cpu, out ushort addr, out string name)
    {
        auto ret = setup(cpu, addr, name, 0x20, opcode);
        name ~= " no-wrap";
        return ret;
    }

    auto setup_wrap(T cpu, out ushort addr, out string name)
    {
        auto ret = setup(cpu, addr, name, 0xA0, opcode);
        name ~= " wrap";
        return ret;
    }

    return [&setup_nowrap, &setup_wrap];
}

auto setup_address_abs(T)(ubyte opcode)
if (isCpu!T)
{
    assert(ABS_OPS!T.canFind(opcode));

    auto setup(T cpu, out ushort addr, out string name)
    {
        name = "abs";
        addr = 0x10C5;
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode, 0xC5, 0x10])];
    }

    return [&setup];
}

auto setup_address_zpi(T)(ubyte opcode)
if (isCpu!T && isCMOS!T)
{
    assert(ZPI_OPS!T.canFind(opcode));

    auto setup_nowrap(T cpu, out ushort addr, out string name)
    {
        name = "zpi no-wrap";
        addr = 0x10C5;
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode, 0x70]),
                Block(0x0070, [0xC5, 0x10])];
    }

    auto setup_wrap(T cpu, out ushort addr, out string name)
    {
        name = "zpi wrap";
        addr = 0x10C5;
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode, 0xFF]),
                Block(0x00FF, [0xC5]),
                Block(0x0000, [0x10])];
    }

    return [&setup_nowrap, &setup_wrap];
}

auto setup_address_izx(T)(ubyte opcode)
if (isCpu!T)
{
    assert(IZX_OPS!T.canFind(opcode));

    auto setup_nowrap(T cpu, out ushort addr, out string name)
    {
        name = "izx no-wrap";
        addr = 0x10C5;
        setPC(cpu, 0x1000);
        setX(cpu, 0x20);
        return [Block(0x1000, [opcode, 0x70]),
                Block(0x0090, [0xC5, 0x10])];
    }

    auto setup_wrap(T cpu, out ushort addr, out string name)
    {
        name = "izx wrap";
        addr = 0x10C5;
        setPC(cpu, 0x1000);
        setX(cpu, 0x90);
        return [Block(0x1000, [opcode, 0x70]),
                Block(0x00FF, [0xC5]),
                Block(0x0000, [0x10])];
    }

    return [&setup_nowrap, &setup_wrap];
}

auto setup_address_izy(T)(ubyte opcode)
if (isCpu!T)
{
    assert(IZY_OPS!T.canFind(opcode));

    auto setup_nowrap(T cpu, out ushort addr, out string name)
    {
        name = "izy no-wrap";
        addr = pageCrossAdd(0x10C5, 0x20);
        setY(cpu, 0x20);
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode, 0x70]),
                Block(0x0070, [0xC5, 0x10])];
    }

    auto setup_wrap(T cpu, out ushort addr, out string name)
    {
        name = "izy wrap";
        addr = pageCrossAdd(0x10C5, 0x20);
        setY(cpu, 0x20);
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode, 0xFF]),
                Block(0x00FF, [0xC5]),
                Block(0x0000, [0x10])];
    }

    auto setup_px(T cpu, out ushort addr, out string name)
    {
        name = "izy px";
        addr = pageCrossAdd(0x10C5, 0x50);
        setY(cpu, 0x50);
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode, 0x70]),
                Block(0x070, [0xC5, 0x10])];
    }

    return [&setup_nowrap, &setup_wrap, &setup_px];
}

auto setup_address_abxy(T)(ubyte opcode)
if (isCpu!T)
{
    bool useX = ABX_OPS!T.canFind(opcode);
    assert(useX || ABY_OPS!T.canFind(opcode));

    auto setup(T cpu, out ushort addr, out string name, ubyte idx,
               ubyte opcode)
    {
        name = (useX ? "abx" : "aby");
        addr = pageCrossAdd(0x10C5, idx);
        if (useX)
        {
            setX(cpu, idx); setY(cpu, 0x10);
        }
        else
        {
            setY(cpu, idx); setX(cpu, 0x10);
        }
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode, 0xC5, 0x10])];

    }

    auto setup_no_px(T cpu, out ushort addr, out string name)
    {
        auto ret = setup(cpu, addr, name, 0x20, opcode);
        name ~= " no-px";
        return ret;
    }

    auto setup_px(T cpu, out ushort addr, out string name)
    {
        auto ret = setup(cpu, addr, name, 0x50, opcode);
        name ~= " px";
        return ret;
    }

    return [&setup_no_px, &setup_px];
}

auto setup_address_reg(T)(ubyte opcode)
if (isCpu!T)
{
    static if (isNMOS!T)
        assert(REG_OPS!T.canFind(opcode));
    else
        assert(REG_OPS!T.canFind(opcode) || NOP1_OPS!T.canFind(opcode));

    auto setup(T cpu, out ushort addr, out string name)
    {
        name = "register";
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode])];
    }

    return [&setup];
}

auto setup_address_push(T)(ubyte opcode)
if (isCpu!T)
{
    assert(PUSH_OPS!T.canFind(opcode));

    auto setup_nowrap(T cpu, out ushort addr, out string name)
    {
        name = "non-wrapping";
        setSP(cpu, 0xFE);
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode])];
    }

    auto setup_wrap(T cpu, out ushort addr, out string name)
    {
        name = "wrapping";
        setSP(cpu, 0x00);
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode])];
    }

    return [&setup_nowrap, &setup_wrap];
}

auto setup_address_pull(T)(ubyte opcode)
if (isCpu!T)
{
    assert(PULL_OPS!T.canFind(opcode));

    auto setup_nowrap(T cpu, out ushort addr, out string name)
    {
        name = "non-wrapping";
        setSP(cpu, 0x01);
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode])];
    }

    auto setup_wrap(T cpu, out ushort addr, out string name)
    {
        name = "wrapping";
        setSP(cpu, 0xFF);
        setPC(cpu, 0x1000);
        return [Block(0x1000, [opcode])];
    }

    return [&setup_nowrap, &setup_wrap];
}

auto setup_address_branch(T)(ubyte opcode)
if (isCpu!T)
{
    assert(BRANCH_OPS!T.canFind(opcode));

    int count;
    static string[5] names =
        ["no-branch", "forward", "forward-px", "backward", "backward-px"];
    static ubyte[5] values = [0x10, 0x10, 0x7F, 0xFE, 0xF5];

    auto setup(T cpu, out ushort addr, out string name)
    {
        name = names[count];
        if (name == "no-branch")
        {
            if (isNMOS!T || opcode != 0x80)
                expectNoBranch(cpu, opcode);
        }
        else
        {
            expectBranch(cpu, opcode);
        }
        if (name == "forward-px")
        {
            setPC(cpu, 0x1081);
            return [Block(0x1000, []), // for wrong-page read
                    Block(getPC(cpu), [opcode, values[count++]])];
        }
        else
        {
            setPC(cpu, 0x1000);
            return [Block(getPC(cpu), [opcode, values[count++]])];
        }
    }

    return [&setup, &setup, &setup, &setup, &setup];
}

auto setup_address_op_BRK(T)(ubyte opcode)
if (isCpu!T)
{
    assert(opcode == 0x00);

    auto setup(T cpu, out ushort addr)
    {
        addr = 0xFE55;
        setPC(cpu, 0xFD00);
        auto sp = getSP(cpu);
        auto sp1 = pageWrapAdd(sp, -1);
        return [Block(0xFD00, [0x00]),
                Block(sp, [notXX(0xFD)]),
                Block(sp1, [notXX(0x00)]),
                // sp2 set by setup_data_op_BRK
                Block(0xFFFE, [0x55, 0xFE])];
    }

    auto setup_nowrap(T cpu, out ushort addr, out string name)
    {
        name = "BRK no-wrap";
        setSP(cpu, 0xFF);
        return setup(cpu, addr);
    }

    auto setup_wrap(T cpu, out ushort addr, out string name)
    {
        name = "BRK wrap";
        setSP(cpu, 0x01);
        return setup(cpu, addr);
    }

    return [&setup_nowrap, &setup_wrap];
}

auto setup_address_op_JSR(T)(ubyte opcode)
if (isCpu!T)
{
    assert(opcode == 0x20);

    auto setup(T cpu, out ushort addr)
    {
        addr = 0x10C5;
        setPC(cpu, 0x1000);
        auto sp = getSP(cpu);
        auto sp1 = pageWrapAdd(sp, 1);
        return [Block(0x1000, [0x20, 0xC5, 0x10]),
                Block(sp, [notXX(0x10)]),
                Block(sp1, [notXX(0x02)])];

    }

    auto setup_nowrap(T cpu, out ushort addr, out string name)
    {
        name = "JSR no-wrap";
        setSP(cpu, 0xFF);
        return setup(cpu, addr);
    }

    auto setup_wrap(T cpu, out ushort addr, out string name)
    {
        name = "JSR wrap";
        setSP(cpu, 0x00);
        return setup(cpu, addr);
    }

    return [&setup_nowrap, &setup_wrap];
}


auto setup_address_op_RTx(T)(ubyte opcode)
if (isCpu!T)
{
    assert(opcode == 0x40 || opcode == 0x60);

    auto setup(T cpu, out ushort addr, out string name, ubyte opcode)
    {
        name = (opcode == 0x40 ? "RTI" : "RTS");
        addr = 0x1211;
        setPC(cpu, 0x1000);
        auto sp = getSP(cpu);
        auto sp2 = pageWrapAdd(sp, (opcode == 0x40 ? 2 : 1));
        auto sp3 = pageWrapAdd(sp, (opcode == 0x40 ? 3 : 2));
        return [Block(0x1000, [opcode]),
                // sp1 set by setup_data_op_RTI for opcode 0x40
                Block(sp2, [0x11]),
                Block(sp3, [0x12])];
    }

    auto setup_nowrap(T cpu, out ushort addr, out string name)
    {
        setSP(cpu, 0xF0);
        auto ret = setup(cpu, addr, name, opcode);
        name ~= " no-wrap";
        return ret;
    }

    auto setup_wrap(T cpu, out ushort addr, out string name)
    {
        setSP(cpu, 0xFE);
        auto ret = setup(cpu, addr, name, opcode);
        name ~= " wrap";
        return ret;
    }

    return [&setup_nowrap, &setup_wrap];
}

auto setup_address_op_5C(T)(ubyte opcode)
if (isCpu!T && isCMOS!T)
{
    assert(opcode == 0x5C);

    auto setup(T cpu, out ushort addr, out string name)
    {
        name = "NOP8";
        setPC(cpu, 0xFD00);
        return [Block(0xFD00, [0x5C, 0x72])];
    }

    return [&setup];
}

auto setup_address_op_JMP_abs(T)(ubyte opcode)
if (isCpu!T)
{
    assert(opcode == 0x4C);

    auto setup(T cpu, out ushort addr, out string name)
    {
        name = "JMP abs";
        addr = 0x10C5;
        setPC(cpu, 0x1000);
        return [Block(0x1000, [0x4C, 0xC5, 0x10])];
    }

    return [&setup];
}

auto setup_address_op_JMP_ind(T)(ubyte opcode)
if (isCpu!T)
{
    assert(opcode == 0x6C);

    auto setup_nopx(T cpu, out ushort addr, out string name)
    {
        name = "JMP ind no-px";
        addr = 0x1234;
        setPC(cpu, 0x1000);
        return [Block(0x1000, [0x6C, 0xC5, 0x10]),
                Block(0x10C5, [0x34, 0x12])];
    }

    auto setup_px(T cpu, out ushort addr, out string name)
    {
        name = "JMP ind px";
        addr = 0x1234;
        setPC(cpu, 0x1000);
        ushort ial = 0x11FF;
        ushort iah = (isNMOS!T ? 0x1100 : 0x1200);
        return [Block(0x1000, [0x6C, 0xFF, 0x11]),
                Block(ial, [0x34]),
                Block(iah, [0x12])];
    }

    return [&setup_nopx, &setup_px];
}

auto setup_address_op_JMP_inx(T)(ubyte opcode)
if (isCpu!T && isCMOS!T)
{
    assert(opcode == 0x7C);

    auto setup(T cpu, out ushort addr, out string name)
    {
        name = "JMP inx";
        addr = 0x1234;
        setPC(cpu, 0x1000);
        setX(cpu, 0x20);
        return [Block(0x1000, [0x7C, 0xC5, 0x10]),
                Block(0x10C5, [0x14, 0x12])];
    }

    return [&setup];
}



// XXX data not anything put in memory by setup_address_* ?

auto setup_data_none(T)(ubyte opcode)
if (isCpu!T)
{
    auto setup(T cpu, ushort addr, out string name)
    {
        name = "";
        return cast(Block[])[];
    }

    return [&setup];
}

auto setup_data_push(T)(ubyte opcode)
if (isCpu!T)
{
    static if (isNMOS!T)
        assert(opcode == 0x48);
    else
        assert(opcode == 0x48 || opcode == 0x5A || opcode == 0xDa);
    // XXX set register to non-zero value

    return cast(datasetup_t!T[])[];
}

auto setup_data_pull(T)(ubyte opcode)
if (isCpu!T)
{
    assert(isNMOS!T ? opcode == 0x68
                    : (opcode == 0x68 || opcode == 0x7A || opcode == 0xFA));

    int count;
    static ubyte[3] values = [0x00, 0x40, 0x80];
    static string[3] names = ["zero", "positive", "negative"];

    auto setup(T cpu, ushort addr, out string name)
    {
        assert(count < 3);
        auto sp = pageWrapAdd(getSP(cpu), 1);
        name = names[count];
        return [Block(sp, [values[count++]])];
    }

    return [&setup, &setup, &setup];
}

auto setup_data_op_BRK(T)(ubyte opcode)
if (isCpu!T)
{
    assert(opcode == 0x00);
    // XXX cpu flags each set/unset, with corresponding garbage values
    // at sp+2
    return cast(datasetup_t!T[])[];
}

auto setup_data_op_PHP(T)(ubyte opcode)
if (isCpu!T)
{
    assert(opcode == 0x08);
    // XXX cpu flags each set/unset, with corresponding garbage values
    return cast(datasetup_t!T[])[];
}

auto setup_data_op_RTI(T)(ubyte opcode)
if (isCpu!T)
{
    assert(opcode == 0x40);
    // XXX values for each flag set/unset, with flags corresponding
    return cast(datasetup_t!T[])[];
}

auto setup_data_op_PLP(T)(ubyte opcode)
if (isCpu!T)
{
    assert(opcode == 0x28);
    // XXX values for each flag set/unset, with flags corresponding
    return cast(datasetup_t!T[])[];
}

unittest
{
/+
    import std.stdio;
    alias Cmos!(false, false) T;
    addrsetup_t!T[] function(ubyte) setups1;
    datasetup_t!T[] function(ubyte) setups2;
    ubyte opcode = 0x10;
    mixin(getMemSetup!T());

    auto funcs1 = setups1(opcode);
    string name1, name2;
    foreach(func1; funcs1)
    {
        auto funcs2 = setups2(opcode);
        foreach(func2; funcs2)
        {
            ushort addr;
            auto cpu = new T();
            auto block1 = func1(cpu, addr, name1);
            auto block2 = func2(cpu, addr, name2);
            auto mem = TestMemory(block1 ~ block2);
            connectCpu(cpu, mem);
        }
    }
+/
//    enum foo = getMemSetup!(Cmos!(false, false))();
//    writeln(foo);
}
