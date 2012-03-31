module test.base;


import std.algorithm, std.conv, std.exception, std.range, std.string;

import test.cpu, test.opcodes;


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
     * base address, but note that the base of the 3-page "main
     * memory" will be the start of the page that contains the first
     * block with a base address greater than 0x01FF (there must be at
     * least one such block).
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
                        data2_base = base & 0xFF00;
                    data2_max = data2_base + 0x300;
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
            return [Block(getPC(cpu), [opcode, values[count++]])];
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

auto setup_data_dec_reg(T)(ubyte opcode)
if (isCpu!T)
{
    /* XXX DEX, DEY, on CMOS DEC A
     * set reg to:
     * 0x01 (sets z) 0x00 (sets N) 0x80 (clears both)
     */
}

auto setup_data_dec(T)(ubyte opcode)
if (isCpu!T)
{
    // XXX all addressing modes of DEC
    // set addr to
    // 0x01 (sets z) 0x00 (sets N) 0x80 (clears both)
}

auto setup_data_inc_reg(T)(ubyte opcode)
if (isCpu!T)
{
    // XXX INX, INY, on CMOS INC A
    // set reg to:
    // 0xFF (sets Z) 0x7F (sets N) 0x00 (clears both)
}

auto setup_data_inc(T)(ubyte opcode)
if (isCpu!T)
{
    // XXX all addressing modes of INC
    // set addr to:
    // 0xFF (sets Z) 0x7F (sets N) 0x00 (clears both)
}

auto setup_data_rol(T)(ubyte opcode)
if (isCpu!T)
{
    // XXX all addressing modes of ROL
    // if 0x2A, set A else set addr
    // 0 carry set -> 1 (zero clear, carry clear, neg clear)
    // 0 carry clear -> 0 (zero set, carry clear, neg clear)
    // 0x80 carry set -> 1 (carry set, zero clear, neg clear)
    // 0x80 carry clear -> 0 (carry set, zero set, neg clear)
    // 0x40 carry set -> 0x81 (carry clear, zero clear, neg set)
    // 0x40 carry clear -> 0x80 (carry clear, zero clear, neg set)
}

auto setup_data_asl(T)(ubyte opcode)
if (isCpu!T)
{
    // XXX all addressing modes of ASL
    // if 0x0A, set A else set addr
    // each starting carry set, carry clear
    // 0 -> 0
    // 0x80 -> 0 carry set
    // 0x40 -> 0x80
    // 0x01 -> 0x02
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
    call_addr(BRANCH_OPS!T, "branch"); // XXX test
    call_addr([0x00], "op_BRK");
    call_addr([0x20], "op_JSR"); // XXX test
    call_addr([0x40, 0x60], "op_RTx"); // XXX 0x60 test
    call_addr([0x4C], "op_JMP_abs"); // XXX test
    call_addr([0x6C], "op_JMP_ind"); // XXX test

    call_data([0x08], "op_PHP");
    call_data([0x28], "op_PLP");
    call_data([0x00], "op_BRK");
    call_data([0x40], "op_RTI");
//    call_data(OPS_DEC_REG!T, "dec_reg");
//    call_data(OPS_DEC!T, "dec");
//    call_data(OPS_INC_REG!T, "inc_reg");
//    call_data(OPS_INC!T, "inc");
//    call_data(OPS_ROL!T, "rol");
//    call_data(OPS_ASL!T, "asl");

    static if (isNMOS!T)
    {
        call_addr(HLT_OPS!T, "none");

        call_data([0x48], "push");
        call_data([0x68], "pull");
    }
    else
    {
        call_addr(ZPI_OPS!T, "zpi");
        call_addr(NOP1_OPS!T, "reg"); /// XXX nop test 1 cycles
        call_addr([0x5C], "op_5C"); /// XXX test
        call_addr([0x7C], "op_JMP_inx"); /// XXX test

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
//    enum foo = getMemSetup!(NmosUndoc!(false, false))();
//    writeln(foo);
}
