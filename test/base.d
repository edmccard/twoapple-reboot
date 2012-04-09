module test.base;


import std.algorithm, std.array, std.conv, std.exception, std.stdio,
       std.string;

import test.cpu, test.opcodes;


/*
 * Emulates zero page, stack, and 3 additional pages of "main memory"
 * starting at a user-defined address. Accesses outside the defined
 * address space raise an exception.
 *
 * The contents are initialized to 0xFF. Individual locations can be
 * read and written using array index syntax.
 */
struct TestMemory
{
private:
    ubyte[0x200] data1 = 0xFF;
    ubyte[0x300] data2 = 0xFF;
    ushort data2_base;
    size_t data2_max;

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
    this(const(Block[]) blocks ...)
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

    ubyte read(ushort addr) const
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

    ubyte opIndex(size_t i1) const
    {
        auto addr = cast(ushort)i1;
        enforce(addr < 0x0200 || (addr >= data2_base && addr < data2_max),
                "Read out of bounds");
        return read(addr);
    }

    ubyte opIndexAssign(ubyte val, size_t i1)
    {
        auto addr = cast(ushort)i1;
        enforce(addr < 0x0200 || (addr >= data2_base && addr < data2_max),
                "Write out of bounds");
        write(addr, val);
        return val;
    }
}


// A block of memory with a given base address.
struct Block
{
    const ushort base;
    const(ubyte[]) data;

    string toString() const
    {
        return format("Block(%0.4X, [%s])", base, formatMemory(data));
    }
}


/*
 * Formats data as a string of 2-digit hex bytes, separated by spaces.
 *
 * If data is longer than max, the string will end with an indication
 * of the number of extra bytes.
 */
string formatMemory(const(ubyte[]) data, size_t max = 3)
{
    if (max > data.length) max = data.length;
    auto hexbytes = map!(`format("%0.2X", a)`)(data[0..max]);
    auto ret = join(array(hexbytes), " ");
    if (data.length > max)
        ret ~= format(" (%d more bytes)", data.length - max);
    return ret;
}


struct OpInfo
{
    ushort addr;
    ubyte data;
    int len;
    bool write;
}

alias void delegate(ubyte, CpuInfo, Block[], OpInfo, string, TestSetup*)
    testsetup;

class TestSetup
{
    testsetup setup;
    TestSetup next;

    auto static opCall(testsetup d)
    {
        auto obj = new TestSetup();
        obj.setup = d;
        return obj;
    }

    void run(ubyte opcode, CpuInfo cpu = CpuInfo(), Block[] data = [],
             OpInfo info = OpInfo(), string msg = "")
    {
        setup(opcode, cpu, data, info, msg, &next);
    }
}

TestSetup connect(TestSetup first, TestSetup[] rest...)
{
    if (!(rest.empty))
    {
        auto x = first;
        while (x.next !is null) x = x.next;
        x.next = connect(rest[0], rest[1..$]);
    }
    return first;
}

template testCallNext()
{
    void callNext(string newMsg = "", Block[] newData = [])
    {
        if (*next !is null)
            next.run(opcode, cpu, data ~ newData, info, msg ~ newMsg);
    }
}


// Does nothing.
auto setup_none()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        if (*next !is null) next.run(opcode, cpu, data, info, msg);
    }
    return TestSetup(&setup);
}


// Aborts a test.
auto setup_op_abort()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
    }
    return TestSetup(&setup);
}


// Prints the current message.
auto setup_debug()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        import std.stdio;
        writeln(format("%s\n  data %s\n  addr %0.4X op %0.2X %s",
                       msg, data, info.addr, opcode, cpu));
        if (*next !is null) next.run(opcode, cpu, data, info, msg);
    }
    return TestSetup(&setup);
}


// Splits with the given flag set, then cleared.
auto setup_flag(Flag f)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        clearFlag(cpu, f);
        callNext(format("%s0 ", flagToString(f)));

        setFlag(cpu, f);
        callNext(format("%s1 ", flagToString(f)));
    }
    return TestSetup(&setup);
}


// Splits with all flags set, then all flags cleared.
auto setup_mask_flags()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        clearFlag(cpu, Flag.C, Flag.Z, Flag.I, Flag.D, Flag.V, Flag.N);
        callNext("F0 ");

        setFlag(cpu, Flag.C, Flag.Z, Flag.I, Flag.D, Flag.V, Flag.N);
        callNext("F1 ");
    }
    return TestSetup(&setup);
}


/*
 * Used after setup_mask_flags, guarantees coverage of all
 * combinations of N and Z.
 */
auto setup_nz()
{
    return setup_flag(Flag.N);
}


/*
 * Can be used after setup_mask_flags to cover all combinations of
 * flags.
 */
auto setup_nvdzc()
{
    return connect(setup_flag(Flag.N), setup_flag(Flag.Z),
                   setup_flag(Flag.V), setup_flag(Flag.D),
                   setup_flag(Flag.C));
}


// Splits with info.data 0x00, 0x40, and 0x80.
auto setup_data()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.data = 0x00;
        callNext("zero ");

        info.data = 0x40;
        callNext("positive ");

        info.data = 0x80;
        callNext("negative ");
    }
    return connect(TestSetup(&setup));
}


/*
 * For register transfer opcodes.
 *
 * Splits on 0x00, 0x40, and 0x80 in the source register.
 */
auto setup_op_transfer(Reg source, Reg dest)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        ubyte other = (info.data > 0x00 && info.data < 0x80) ? 0x00 : 0x01;
        setX(cpu, other); setY(cpu, other); setA(cpu, other);
        setReg(cpu, source, info.data);
        callNext("xfer ");
    }
    return connect(setup_nz(), setup_data(), TestSetup(&setup));
}


// For TXS and TSX.
auto setup_op_stack_xfer()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setSP(cpu, 0x00);
        setX(cpu, 0xFF);
        callNext("TXS ");
    }
    return connect(setup_nz(), TestSetup(&setup));
}


/*
 * For implied address mode.
 *
 * Sets PC to 0x1000 and puts a (1-byte) opcode in memory.
 */
auto setup_addr_implied()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setPC(cpu, 0x1000);
        info.len = 1;
        callNext("", [Block(0x1000, [opcode])]);
    }
    return TestSetup(&setup);
}

/*
 * For immediate address mode.
 *
 * Sets PC to 0x1000 and info.addr to 0x1001.
 */
auto setup_addr_imm()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setPC(cpu, 0x1000);
        info.len = 2;
        info.addr = 0x1001;
        callNext("imm ", [Block(0x1000, [opcode])]);
    }
    return TestSetup(&setup);
}


/*
 * For branch opcodes.
 */
auto setup_addr_branch(bool cmos)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        if (!cmos || opcode != 0x80)
        {
            expectNoBranch(cpu, opcode);
            setPC(cpu, 0x1000);
            info.addr = 0x1002;
            callNext("no-branch ", [Block(0x1000, [opcode, 0x10])]);
        }

        expectBranch(cpu, opcode);

        setPC(cpu, 0x1000);
        info.addr = 0x1012;
        callNext("branch-fwd ", [Block(0x1000, [opcode, 0x10])]);

        setPC(cpu, 0x1081);
        info.addr = 0x1102;
        callNext("branch-fwd-px ", [Block(0x1081, [opcode, 0x7F])]);

        setPC(cpu, 0x1000);
        info.addr = 0x1000;
        callNext("branch-bkwd ", [Block(0x1000, [opcode, 0xFE])]);

        setPC(cpu, 0x1100);
        info.addr = 0x10F7;
        callNext("branch-bkwd-px ", [Block(0x1000, []),
                                     Block(0x1100, [opcode, 0xF5])]);
    }
    return TestSetup(&setup);
}


/*
 * For zeropage adddress mode.
 *
 * Sets PC to 0x1000 and puts [opcode, 0x70] in memory.
 */
auto setup_addr_zpg()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setPC(cpu, 0x1000);
        info.len = 2;
        info.addr = 0x0070;
        callNext("zpg ", [Block(0x1000, [opcode, 0x70])]);
    }
    return TestSetup(&setup);
}


/*
 * For absolute address mode.
 *
 * Sets PC to 0x1000 and puts [opcode, 0xC5, 0x10] in memory.
 */
auto setup_addr_abs()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setPC(cpu, 0x1000);
        info.len = 3;
        info.addr = 0x10C5;
        callNext("abs ", [Block(0x1000, [opcode, 0xC5, 0x10])]);
    }
    return TestSetup(&setup);
}


/*
 * For zeropage,x/y address modes.
 *
 * Sets PC to 0x1000 and puts [opcode, 0x70] in memory.
 */
auto setup_addr_zpxy(Reg reg)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        string name = (reg == Reg.X ? "zpx " : "zpy ");
        info.len = 2;
        setPC(cpu, 0x1000);

        setX(cpu, 0x10); setY(cpu, 0x10); setA(cpu, 0x10);
        setReg(cpu, reg, 0x00);
        info.addr = pageWrapAdd(0x0070, 0x00);
        callNext(name ~ "no-idx ", [Block(0x1000, [opcode, 0x70])]);

        setX(cpu, 0x10); setY(cpu, 0x10); setA(cpu, 0x10);
        setReg(cpu, reg, 0x20);
        info.addr = pageWrapAdd(0x0070, 0x20);
        callNext(name ~ "no-wrap ", [Block(0x1000, [opcode, 0x70])]);

        setX(cpu, 0x10); setY(cpu, 0x10); setA(cpu, 0x10);
        setReg(cpu, reg, 0xA0);
        info.addr = pageWrapAdd(0x0070, 0xA0);
        callNext(name ~ "wrap ", [Block(0x1000, [opcode, 0x70])]);
    }
    return TestSetup(&setup);
}


// For absolute,x/y address modes.
auto setup_addr_abxy(Reg reg)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        string name = (reg == Reg.X ? "abx " : "aby ");
        info.len = 3;
        setPC(cpu, 0x1000);

        setX(cpu, 0x10); setY(cpu, 0x10); setA(cpu, 0x10);
        setReg(cpu, reg, 0x00);
        info.addr = pageCrossAdd(0x10C5, 0x00);
        callNext(name ~ "no-idx ", [Block(0x1000, [opcode, 0xC5, 0x10])]);

        setX(cpu, 0x10); setY(cpu, 0x10); setA(cpu, 0x10);
        setReg(cpu, reg, 0x20);
        info.addr = pageCrossAdd(0x10C5, 0x20);
        callNext(name ~ "no-px ", [Block(0x1000, [opcode, 0xC5, 0x10])]);

        setX(cpu, 0x10); setY(cpu, 0x10); setA(cpu, 0x10);
        setReg(cpu, reg, 0x50);
        info.addr = pageCrossAdd(0x10C5, 0x50);
        callNext(name ~ "px ", [Block(0x1000, [opcode, 0xC5, 0x10])]);
    }
    return TestSetup(&setup);
}


// For zeropage indirect,x address mode.
auto setup_addr_izx()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.addr = 0x10C5;
        info.len = 2;
        setPC(cpu, 0x1000);
        setA(cpu, 0x01); setY(cpu, 0x01);

        setX(cpu, 0x20);
        callNext("izx no-wrap ", [Block(0x1000, [opcode, 0x70]),
                                  Block(0x0090, [0xC5, 0x10])]);

        setX(cpu, 0xA0);
        callNext("izx wrap ", [Block(0x1000, [opcode, 0x70]),
                               Block(0x0010, [0xC5, 0x10])]);

        setX(cpu, 0x8F);
        callNext("izx px ", [Block(0x1000, [opcode, 0x70]),
                             Block(0x00FF, [0xC5]),
                             Block(0x0000, [0x10])]);
    }
    return TestSetup(&setup);
}


// For zeropage indirect,y address mode.
auto setup_addr_izy()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.len = 2;
        setPC(cpu, 0x1000);
        setA(cpu, 0x01); setX(cpu, 0x01);

        info.addr = pageCrossAdd(0x10C5, 0x20);
        setY(cpu, 0x20);

        callNext("izy no-wrap ", [Block(0x1000, [opcode, 0x70]),
                                  Block(0x0070, [0xC5, 0x10])]);

        callNext("izy wrap ", [Block(0x1000, [opcode, 0xFF]),
                               Block(0x00FF, [0xC5]),
                               Block(0x0000, [0x10])]);

        info.addr = pageCrossAdd(0x10C5, 0x50);
        setY(cpu, 0x50);
        callNext("izy px ", [Block(0x1000, [opcode, 0x70]),
                             Block(0x0070, [0xC5, 0x10])]);
    }
    return TestSetup(&setup);
}


// For zeropage indirect address mode.
auto setup_addr_zpi()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.len = 2;
        info.addr = 0x10C5;
        setPC(cpu, 0x1000);

        callNext("zpi no-wrap ", [Block(0x1000, [opcode, 0x70]),
                                  Block(0x0070, [0xC5, 0x10])]);

        callNext("zpi wrap ", [Block(0x1000, [opcode, 0xFF]),
                               Block(0x00FF, [0xC5]),
                               Block(0x0000, [0x10])]);
    }
    return TestSetup(&setup);
}

/*
 * Splits with the SP at 0xFF, and then at 0x00 (to cover the case of
 * pull operations when the stack is "empty").
 */
auto setup_pull_wrap()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setSP(cpu, 0xFF);
        callNext("wrap ");

        setSP(cpu, 0x00);
        callNext("no-wrap ");
    }
    return TestSetup(&setup);
}


/*
 * For pull opcodes.
 *
 * Splits with 0x00, 0x40, and 0x80 at the top of the stack (to
 * exercise different potential combinations of N and Z).
 */
auto setup_op_pull(Reg reg)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        auto sp = pageWrapAdd(getSP(cpu), 1);
        ubyte other = (info.data > 0x00 && info.data < 0x80) ? 0x00 : 0x01;
        setX(cpu, other); setY(cpu, other); setA(cpu, other);
        callNext("pull ", [Block(sp, [info.data])]);
    }
    return connect(setup_pull_wrap(), setup_nz(), setup_data(),
                   TestSetup(&setup));
}


/*
 * Splits with each possible meaningful status byte value on the
 * stack, and with values with break/reserved bits set.
 */
auto setup_status()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        for (int i = 0; i < 4; i++)
        {
            for (int j = 0; j < 16; j++)
            {
                info.data = cast(ubyte)(i * 0x40 + j);
                callNext(format("S %0.2X ", info.data | 0x30));
            }
        }

        string[] msgs = ["B ", "R ", "BR "];
        foreach (val; [0x10, 0x20, 0x30])
        {
            info.data = cast(ubyte)val;
            callNext("S " ~ msgs[(info.data >> 4) - 1]);
        }
    }
    return TestSetup(&setup);
}


// For PLP.
auto setup_op_PLP()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        auto sp = pageWrapAdd(getSP(cpu), 1);
        setStatus(cpu, ~info.data);
        callNext("PLP ", [Block(sp, [info.data])]);
    }
    return connect(setup_pull_wrap(), setup_status(), TestSetup(&setup));
}


/*
 * Splits with the SP at 0x00, and then at 0xFF (to cover the case of
 * push operations when the stack is "full").
 */
auto setup_push_wrap()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setSP(cpu, 0x00);
        callNext("wrap ");

        setSP(cpu, 0xFF);
        callNext("no-wrap ");
    }
    return TestSetup(&setup);
}


/*
 * For push opcodes.
 *
 * Splits with 0x00, 0x40, and 0x80 in the appropriate register.
 */
auto setup_op_push(Reg reg)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setX(cpu, 0x01); setY(cpu, 0x01); setA(cpu, 0x01);
        setReg(cpu, reg, info.data);
        callNext("push ", [Block(getSP(cpu), [~info.data])]);
    }
    return connect(setup_push_wrap(), setup_data(), TestSetup(&setup));
}


/*
 * For PHP.
 *
 * Puts a garbage value (that does not correspond to the current
 * status) just below the top of the stack.
 */
auto setup_op_PHP()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.data = getStatus(cpu);
        callNext("PHP ", [Block(getSP(cpu), [~info.data])]);
    }
    return connect(setup_nvdzc(), setup_push_wrap(), TestSetup(&setup));
}


/*
 * For load opcodes.
 *
 * Splits with 0x00, 0x40, and 0x80 in the source memory location.
 */
auto setup_op_load(Reg reg)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        callNext("load ", [Block(info.addr, [info.data])]);
    }
    return connect(setup_nz(), setup_data(), TestSetup(&setup));
}


// Splits with 0x00, 0x40, 0x80 in the source register.
auto setup_op_store(Reg reg)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setReg(cpu, reg, info.data);
        callNext("store ", [Block(info.addr, [~info.data])]);
    }
    return connect(setup_data(), TestSetup(&setup));
}


// For SAX.
auto setup_op_SAX()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        if (opcode == 0x83)
        {
            setA(cpu, 0x00);
            callNext("zero SAX ");

            setA(cpu, 0x2B);
            callNext("positive SAX ");

            setA(cpu, 0x8B);
            callNext("negative SAX ");
        }
        else
        {
            setA(cpu, 0x00); setX(cpu, 0x00);
            callNext("zero SAX ");

            setA(cpu, 0x10); setX(cpu, 0x01);
            callNext("zero SAX ");

            setA(cpu, 0x0B); setX(cpu, 0x0D);
            callNext("positive SAX ");

            setA(cpu, 0x8B); setX(cpu, 0x8D);
            callNext("negative SAX ");
        }
    }
    return TestSetup(&setup);
}


// For STZ.
auto setup_op_STZ()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.data = 0;
        callNext("STZ ", [Block(info.addr, [~info.data])]);
    }
    return TestSetup(&setup);
}


// setup_bit_val, puts in memory;
auto setup_bit_data()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.data = 0x80;
        callNext("N1 ", [Block(info.addr, [info.data])]);

        info.data = 0x40;
        callNext("V1 ", [Block(info.addr, [info.data])]);

        info.data = 0xC0;
        callNext("N1V1 ", [Block(info.addr, [info.data])]);

        info.data = 0x20;
        callNext("N0V0 ", [Block(info.addr, [info.data])]);
    }
    return TestSetup(&setup);
}


// For BIT.
auto setup_op_BIT()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, info.data);
        callNext("BIT non-zero ");

        setA(cpu, ~info.data);
        callNext("BIT zero");
    }
    return connect(setup_nz(), setup_flag(Flag.V), setup_bit_data(),
                   TestSetup(&setup));
}


// For TRB.
auto setup_op_TRB()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0); setX(cpu, 0xFF); setY(cpu, 0xFF);
        info.data = 0x01;
        callNext("TRB Z1 1 ", [Block(info.addr, [info.data])]);

        setA(cpu, 0x40); setX(cpu, 0x00); setY(cpu, 0x00);
        info.data = 0x40;
        callNext("TRB Z0 0 ", [Block(info.addr, [info.data])]);

        setA(cpu, 0x40); setX(cpu, 0x00); setY(cpu, 0x00);
        info.data = 0x41;
        callNext("TRB Z0 1 ", [Block(info.addr, [info.data])]);
    }
    return TestSetup(&setup);
}


// For TSB.
auto setup_op_TSB()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x01); setX(cpu, 0x00); setY(cpu, 0x00);
        info.data = 0x00;
        callNext("TSB Z1 1 ", [Block(info.addr, [info.data])]);

        setA(cpu, 0x02); setX(cpu, 0x00); setY(cpu, 0x00);
        info.data = 0x02;
        callNext("TSB Z0 2 ", [Block(info.addr, [info.data])]);

        setA(cpu, 0x30); setX(cpu, 0x00); setY(cpu, 0x00);
        info.data = 0x80;
        callNext("TSB Z1 B0 ", [Block(info.addr, [info.data])]);

        setA(cpu, 0x00); setX(cpu, 0xFF); setY(cpu, 0xFF);
        info.data = 0x02;
        callNext("TSB Z1 2 ", [Block(info.addr, [info.data])]);
    }
    return TestSetup(&setup);
}


// For BRK.
auto setup_op_BRK()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.addr = 0xFE55;
        setPC(cpu, 0xFD00);
        ushort ret = 0xFD02;
        auto sp = getSP(cpu);
        auto sp1 = pageWrapAdd(sp, -1);
        auto sp2 = pageWrapAdd(sp, -2);
        info.data = getStatus(cpu);
        callNext("BRK ", [Block(0xFD00, [opcode]),
                          Block(sp, [~addrHi(ret)]),
                          Block(sp1, [~addrLo(ret)]),
                          Block(sp2, [~info.data]),
                          Block(0xFFFE, [0x55, 0xFE])]);

    }
    return connect(setup_nvdzc(), setup_push_wrap(), TestSetup(&setup));
}


auto setup_RTx(bool isRTI)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        string name = (isRTI ? "RTI " : "RTS ");
        info.addr = 0x1211;
        setPC(cpu, 0x1000);
        auto sp = getSP(cpu);
        auto sp1 = pageWrapAdd(sp, (isRTI ? 1 : 0));
        auto sp2 = pageWrapAdd(sp, (isRTI ? 2 : 1));
        auto sp3 = pageWrapAdd(sp, (isRTI ? 3 : 2));
        callNext(name, [Block(0x1000, [opcode])] ~
                       (isRTI ? [Block(sp1, [info.data])] : []) ~
                       [Block(sp2, [addrLo(info.addr)]),
                        Block(sp3, [addrHi(info.addr)])]);
    }
    return connect(setup_pull_wrap(), TestSetup(&setup));
}


// For RTI.
auto setup_op_RTI()
{
    return connect(setup_status(), setup_RTx(true));
}


// For RTS.
auto setup_op_RTS()
{
    return setup_RTx(false);
}


// For JMP inx.
auto setup_op_JMP_inx()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.addr = 0x1234;
        info.len = 3;
        setPC(cpu, 0x1000);

        setX(cpu, 0x20);
        callNext("JMP inx A ", [Block(0x1000, [opcode, 0xC5, 0x10]),
                                Block(0x10E5, [0x34, 0x12])]);

        setX(cpu, 0x40);
        callNext("JMP inx B ", [Block(0x1000, [opcode, 0xC5, 0x10]),
                                Block(0x1105, [0x34, 0x12])]);

        setX(cpu, 0x30);
        callNext("JMP inx C ", [Block(0x1000, [opcode, 0xCF, 0x10]),
                                Block(0x10FF, [0x34, 0x12])]);
    }
    return TestSetup(&setup);
}


// For JMP ind.
auto setup_op_JMP_ind(bool cmos)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.addr = 0x1234;
        info.len = 3;
        setPC(cpu, 0x1000);
        setX(cpu, 0x40); setY(cpu, 0x40); setA(cpu, 0x40);

        callNext("JMP ind px ", [Block(0x1000, [opcode, 0xFF, 0x11])] ~
                                (cmos ? [Block(0x11FF, [0x34, 0x12])]
                                      : [Block(0x11FF, [0x34]),
                                         Block(0x1100, [0x12])]));

        callNext("JMP ind no px ", [Block(0x1000, [opcode, 0xC5, 0x10]),
                                    Block(0x10C5, [0x34, 0x12])]);
    }
    return TestSetup(&setup);
}


// For JSR.
auto setup_op_JSR()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.addr = 0x10C5;
        setPC(cpu, 0x1000);
        ushort ret = 0x1002;
        auto sp = getSP(cpu);
        auto sp1 = pageWrapAdd(sp, 1);
        callNext("JSR ", [Block(0x1000, [opcode, 0xC5, 0x10]),
                          Block(sp, [~addrHi(ret)]),
                          Block(sp, [~addrLo(ret)])]);
    }
    return connect(setup_push_wrap(), TestSetup(&setup));
}


// For CMOS opcode 5C.
auto setup_op_5C()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.len = 3;
        setPC(cpu, 0xFD00);
        callNext("NOP8 ", [Block(0xFD00, [0x5C, 0x72])]);
    }
    return TestSetup(&setup);
}


auto setup_dec_data()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.data = 0x01;
        callNext("zero ");

        info.data = 0x00;
        callNext("negative ");

        info.data = 0x80;
        callNext("positive ");
    }
    return TestSetup(&setup);
}


// For DEX, DEY, DEA.
auto setup_op_DEC_reg(Reg reg)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setX(cpu, 0x40); setY(cpu, 0x40); setA(cpu, 0x40);
        setReg(cpu, reg, info.data);
        callNext("DEC r ", [Block(0x1000, [opcode])]);
    }
    return connect(setup_nz(), setup_dec_data(), TestSetup(&setup));
}


// For DEC.
auto setup_op_DEC()
{
    return setup_rmw(false, "DEC ", setup_dec_data());
}


auto setup_inc_data()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.data = 0xFF;
        callNext("zero ");

        info.data = 0x7F;
        callNext("negative ");

        info.data = 0x00;
        callNext("positive ");
    }
    return TestSetup(&setup);
}


// For INX, INY, INA
auto setup_op_INC_reg(Reg reg)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setX(cpu, 0x40); setY(cpu, 0x40); setA(cpu, 0x40);
        setReg(cpu, reg, info.data);
        callNext("INC r ", [Block(0x1000, [opcode])]);
    }
    return connect(setup_nz(), setup_inc_data(), TestSetup(&setup));
}


// For INC.
auto setup_op_INC()
{
    return setup_rmw(false, "INC ", setup_inc_data());
}


auto setup_rmw(bool isAcc, string name, TestSetup data_setup)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        if (isAcc)
        {
            setA(cpu, info.data); setX(cpu, 0x10); setY(cpu, 0x10);
            callNext(name ~ "a ");
        }
        else
        {
            callNext(name, [Block(info.addr, [info.data])]);
        }
    }
    return connect(setup_nz(), data_setup, TestSetup(&setup));
}


// For ROL.
auto setup_op_ROL(bool isAcc)
{
    return setup_rmw(isAcc, "ROL ", setup_data());
}


auto setup_asl_data()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.data = 0x00;
        callNext("zero ");

        info.data = 0x80;
        callNext("zero carry ");

        info.data = 0x40;
        callNext("negative ");

        info.data = 0x01;
        callNext("positive ");
    }
    return TestSetup(&setup);
}


// For ASL.
auto setup_op_ASL(bool isAcc)
{
    return setup_rmw(isAcc, "ASL ", setup_asl_data());
}


auto setup_right_data()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        info.data = 0x01;
        callNext("0x01 ");

        info.data = 0x80;
        callNext("0x80 ");

        info.data = 0x00;
        callNext("0x00 ");
    }
    return TestSetup(&setup);
}


// For ROR.
auto setup_op_ROR(bool isAcc)
{
    return setup_rmw(isAcc, "ROR ", setup_right_data());
}


// For LSR.
auto setup_op_LSR(bool isAcc)
{
    return setup_rmw(isAcc, "LSR ", setup_right_data());
}


// For ASO.
auto setup_op_ASO()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x00);
        callNext("acc 0x00 ");

        setA(cpu, 0xFF);
        callNext("acc 0xFF ");

        setA(cpu, 0x20);
        callNext("acc 0x20 ");
    }
    return connect(TestSetup(&setup),
                   setup_rmw(false, "ASO ", setup_asl_data()));
}

// For RLA.
auto setup_op_RLA()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x00);
        callNext("acc 0x00 ");

        setA(cpu, 0xFF);
        callNext("acc 0xFF ");
    }
    return connect(TestSetup(&setup),
                   setup_rmw(false, "RLA ", setup_data()));
}


// For LSE.
auto setup_op_LSE()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x00);
        callNext("acc 0x00 ");

        setA(cpu, 0xFF);
        callNext("acc 0xFF ");
    }
    return connect(TestSetup(&setup),
                   setup_rmw(false, "LSE ", setup_right_data()));
}


/*
 * For ADC.
 *
 * This opcode is extensively tested elsewhere.
 */
auto setup_op_ADC(bool cmos)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x99);
        info.data = 0x01;
        callNext("ADC 1", [Block(info.addr, [info.data])]);

        setA(cpu, 0x5B);
        info.data = 0x46;
        callNext("ADC 2", [Block(info.addr, [info.data])]);

        setA(cpu, 0x50);
        info.data = 0x60;
        callNext("ADC 3", [Block(info.addr, [info.data])]);

        setA(cpu, 0x90);
        info.data = 0x90;
        callNext("ADC 4", [Block(info.addr, [info.data])]);

        setA(cpu, 0x90);
        info.data = 0x0F;
        callNext("ADC 5", [Block(info.addr, [info.data])]);
    }
    return connect(setup_nz(), setup_flag(Flag.C), setup_flag(Flag.D),
                   TestSetup(&setup));
}


// For RRA.
auto setup_op_RRA()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x00);
        callNext("acc 0x00 ");

        setA(cpu, 0x10);
        callNext("acc 0x10 ");

        setA(cpu, 0xBF);
        callNext("acc 0xBF ");
    }

    return connect(TestSetup(&setup), setup_flag(Flag.C), setup_flag(Flag.D),
                   setup_rmw(false, "RRA ", setup_right_data()));
}


/*
 * For SBC.
 *
 * This opcode is extensively tested elsewhere.
 */
auto setup_op_SBC(bool cmos)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x00);
        info.data = 0x01;
        callNext("SBC 1", [Block(info.addr, [info.data])]);

        setA(cpu, 0x46);
        info.data = 0x12;
        callNext("SBC 2", [Block(info.addr, [info.data])]);

        setA(cpu, 0x50);
        info.data = 0x60;
        callNext("SBC 3", [Block(info.addr, [info.data])]);

        setA(cpu, 0x32);
        info.data = 0x02;
        callNext("SBC 4", [Block(info.addr, [info.data])]);

        setA(cpu, 0x90);
        info.data = 0x0F;
        callNext("SBC 5", [Block(info.addr, [info.data])]);
    }
    return connect(setup_nz(), setup_flag(Flag.C), setup_flag(Flag.D),
                   TestSetup(&setup));
}


// For INS.
auto setup_op_INS()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x00);
        callNext("acc 0x00 ");

        setA(cpu, 0x10);
        callNext("acc 0x10 ");

        setA(cpu, 0xBF);
        callNext("acc 0xBF ");
    }

    return connect(TestSetup(&setup), setup_flag(Flag.C), setup_flag(Flag.D),
                   setup_rmw(false, "INS ", setup_inc_data()));
}


// For CMP, CPY, CPX.
auto setup_op_cmp(Reg reg)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setReg(cpu, reg, 0x10);
        info.data = 0x20;
        callNext("compare <", [Block(info.addr, [info.data])]);

        setReg(cpu, reg, 0x10);
        info.data = 0x10;
        callNext("compare =", [Block(info.addr, [info.data])]);

        setReg(cpu, reg, 0x20);
        info.data = 0x10;
        callNext("compare >", [Block(info.addr, [info.data])]);
    }
    return connect(setup_nz(), TestSetup(&setup));
}


// For DCM.
auto setup_op_DCM()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x00);
        callNext("acc 0x00 ");

        setA(cpu, 0x10);
        callNext("acc 0x10 ");

        setA(cpu, 0xBF);
        callNext("acc 0xBF ");
    }

    return connect(TestSetup(&setup), setup_flag(Flag.C),
                   setup_rmw(false, "DCM ", setup_dec_data()));
}


// For ORA.
auto setup_op_ORA()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x00);
        info.data = 0x00;
        callNext("ORA zero", [Block(info.addr, [info.data])]);

        setA(cpu, 0x10);
        info.data = 0x01;
        callNext("ORA positive", [Block(info.addr, [info.data])]);

        setA(cpu, 0x80);
        info.data = 0x00;
        callNext("ORA negative", [Block(info.addr, [info.data])]);
    }
    return connect(setup_nz(),TestSetup(&setup));
}


// For AND.
auto setup_op_AND()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0x10);
        info.data = 0x01;
        callNext("AND zero", [Block(info.addr, [info.data])]);

        setA(cpu, 0x0B);
        info.data = 0x0D;
        callNext("AND positive", [Block(info.addr, [info.data])]);

        setA(cpu, 0x80);
        info.data = 0x80;
        callNext("AND negative", [Block(info.addr, [info.data])]);
    }
    return connect(setup_nz(),TestSetup(&setup));
}


// For EOR.
auto setup_op_EOR()
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setA(cpu, 0xFF);
        info.data = 0xFF;
        callNext("EOR zero", [Block(info.addr, [info.data])]);

        setA(cpu, 0x81);
        info.data = 0x82;
        callNext("EOR positive", [Block(info.addr, [info.data])]);

        setA(cpu, 0x40);
        info.data = 0x80;
        callNext("EOR negative", [Block(info.addr, [info.data])]);
    }
    return connect(setup_nz(),TestSetup(&setup));
}


/*
 * A range over the differences in two TestMemory structs. Each
 * element is an address with up to eight bytes of subsequent data
 * from the two structs.
 */
struct MemDiff
{

    static struct DiffBlock
    {
        ushort base;
        const(ubyte[]) a;
        const(ubyte[]) b;
    }

    const(TestMemory*) a, b;
    int i;
    bool _empty, _emptyChecked;

    this(const ref TestMemory a, const ref TestMemory b)
    {
        assert(a.data2_base == b.data2_base && a.data2_max == b.data2_max);
        this.a = &a; this.b = &b;
    }

    auto front()
    {
        assert(_emptyChecked && !_empty);
        if (i < 0x200)
        {
            auto extent = min(8, 0x200 - i);
            return DiffBlock(cast(ushort)i,
                             a.data1[i..i+extent].dup,
                             b.data1[i..i+extent].dup);
        }
        else
        {
            auto extent = min(8, a.data2_max - i);
            auto di = i - a.data2_base;
            return DiffBlock(cast(ushort)i,
                             a.data2[di..di+extent].dup,
                             b.data2[di..di+extent].dup);
        }
        assert(0);
    }

    void popFront()
    {
        assert(_emptyChecked && !_empty);
        if (i < 0x200)
            i += min(8, 0x200 - i);
        else
            i += min(8, a.data2_max - i);
    }

    bool empty()
    {
        _emptyChecked = true;
        while (i < 0x200)
        {
            if (a.data1[i] != b.data1[i]) { _empty = false; return false; }
            i++;
        }
        if (i < a.data2_base) i = a.data2_base;
        while (i < a.data2_max)
        {
            auto di = i - a.data2_base;
            if (a.data2[di] != b.data2[di]) { _empty = false; return false; }
            i++;
        }
        _empty = true; return true;
    }
}


struct Expected
{
    CpuInfo cpu;
    TestMemory mem;
}

alias void delegate(ref Expected, const OpInfo)
    testexpect;


// Expects nothing to have changed.
auto expect_none()
{
    void expect(ref Expected expected, const OpInfo info)
    {
    }
    return &expect;
}


// For opcodes which modify a register and set N/Z.
void expect_basic(Reg reg, ubyte val, ref Expected expected, const OpInfo info)
{
    with(expected)
    {
        setReg(cpu, reg, val);
        setNZ(cpu, val);
        incPC(cpu, info.len);
    }
}


// For flag opcodes.
auto expect_flag(Flag f, bool val)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            updateFlag(cpu, f, val);
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


// For NOP.
auto expect_NOP()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected) { incPC(cpu, info.len); }
    }
    return &expect;
}


// For register transfer opcodes.
auto expect_transfer(Reg source, Reg dest)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = getReg(expected.cpu, source);
        expect_basic(dest, val, expected, info);
    }
    return &expect;
}


// For push opcodes.
auto expect_push(Reg reg)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            mem[getSP(cpu)] = getReg(cpu, reg);
            decSP(cpu);
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


// For PHP.
auto expect_PHP()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            mem[getSP(cpu)] = getStatus(cpu);
            decSP(cpu);
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


// For pull opcodes.
auto expect_pull(Reg reg)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            incSP(cpu);
            auto val = mem[getSP(cpu)];
            expect_basic(reg, val, expected, info);
        }
    }
    return &expect;
}


// For PLP.
auto expect_PLP()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            incSP(cpu);
            setStatus(cpu, mem[getSP(cpu)]);
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


// For TSX.
auto expect_TSX()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        ubyte val = cast(ubyte)getSP(expected.cpu);
        expect_basic(Reg.X, val, expected, info);
    }
    return &expect;
}


// For TXS.
auto expect_TXS()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            auto val = getX(cpu);
            setSP(cpu, val);
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


// For load opcodes.
auto expect_load(Reg reg)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = expected.mem[info.addr];
        expect_basic(reg, val, expected, info);
    }
    return &expect;
}


// For LAX (except immediate).
auto expect_LAX()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        expect_load(Reg.A)(expected, info);
        with(expected) { setX(cpu, getA(cpu)); }
    }
    return &expect;
}

// For store opcodes.
auto expect_store(Reg reg)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            mem[info.addr] = getReg(cpu, reg);
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


// For SAX.
auto expect_SAX()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            mem[info.addr] = getA(cpu) & getX(cpu);
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


// For STZ.
auto expect_STZ()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            mem[info.addr] = 0;
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


// For branch opcodes.
auto expect_branch()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected) { setPC(cpu, info.addr); }
    }
    return &expect;
}


// For BIT.
auto expect_BIT()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            updateFlag(cpu, Flag.N, (info.data & 0x80) != 0);
            updateFlag(cpu, Flag.V, (info.data & 0x40) != 0);
            updateFlag(cpu, Flag.Z, (info.data & getA(cpu)) == 0);
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


// For BIT.
auto expect_BIT_imm()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            updateFlag(cpu, Flag.Z, (info.data & getA(cpu)) == 0);
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


// For TRB.
auto expect_TRB()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            updateFlag(cpu, Flag.Z, (info.data & getA(cpu)) == 0);
            mem[info.addr] = ~getA(cpu) & info.data;
            incPC(cpu, info.len);
        }
    }
    return &expect;
}


auto expect_TSB()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            updateFlag(cpu, Flag.Z, (info.data & getA(cpu)) == 0);
            mem[info.addr] = getA(cpu) | info.data;
            incPC(cpu, info.len);
        }
    }
    return &expect;
}

// For BRK.
auto expect_BRK()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            ushort ret = cast(ushort)(getPC(cpu) + 2);
            mem[getSP(cpu)] = addrHi(ret);
            decSP(cpu);
            mem[getSP(cpu)] = addrLo(ret);
            decSP(cpu);
            mem[getSP(cpu)] = info.data;
            decSP(cpu);
            setPC(cpu, info.addr);
            setFlag(cpu, Flag.I);
        }
    }
    return &expect;
}


// For RTI.
auto expect_RTI()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            setStatus(cpu, info.data);
            setPC(cpu, info.addr);
            incSP(cpu, 3);
        }
    }
    return &expect;
}


// For RTS.
auto expect_RTS()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            setPC(cpu, info.addr);
            incSP(cpu, 2);
            incPC(cpu, 1);
        }
    }
    return &expect;
}


// For JMP.
auto expect_JMP()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            setPC(cpu, info.addr);
        }
    }
    return &expect;
}


// For JSR.
auto expect_JSR()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            auto ret = cast(ushort)(getPC(cpu) + 2);
            setPC(cpu, info.addr);
            mem[getSP(cpu)] = addrHi(ret);
            decSP(cpu);
            mem[getSP(cpu)] = addrLo(ret);
            decSP(cpu);
        }
    }
    return &expect;
}


void expect_rmw(bool isAcc, ubyte val, ref Expected expected,
                const OpInfo info)
{
    if (isAcc)
        expect_basic(Reg.A, val, expected, info);
    else
    {
        with(expected)
        {
            mem[info.addr] = val;
            setNZ(cpu, val);
            incPC(cpu, info.len);
        }
    }
}


// For DEX, DEY, DEA.
auto expect_DEC_reg(Reg reg)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data - 1);
        expect_basic(reg, val, expected, info);
    }
    return &expect;
}


// For DEC.
auto expect_DEC()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data - 1);
        expect_rmw(false, val, expected, info);
    }
    return &expect;
}


// For INX, INY, INA.
auto expect_INC_reg(Reg reg)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data + 1);
        expect_basic(reg, val, expected, info);
    }
    return &expect;
}


// For INC.
auto expect_INC()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data + 1);
        expect_rmw(false, val, expected, info);
    }
    return &expect;
}


// For ROL.
auto expect_ROL(bool isAcc)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto carry = (getFlag(expected.cpu, Flag.C) ? 1 : 0);
        auto val = cast(ubyte)(info.data << 1 | carry);
        updateFlag(expected.cpu, Flag.C, (info.data > 0x7F));

        expect_rmw(isAcc, val, expected, info);
    }
    return &expect;
}


// For ASL.
auto expect_ASL(bool isAcc)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data << 1);
        updateFlag(expected.cpu, Flag.C, (info.data > 0x7F));

        expect_rmw(isAcc, val, expected, info);
    }
    return &expect;
}

// For ROR.
auto expect_ROR(bool isAcc)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto carry = (getFlag(expected.cpu, Flag.C) ? 0x80 : 0);
        auto val = cast(ubyte)(info.data >> 1 | carry);
        updateFlag(expected.cpu, Flag.C, ((info.data & 0x01) != 0));

        expect_rmw(isAcc, val, expected, info);
    }
    return &expect;
}


// For LSR.
auto expect_LSR(bool isAcc)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data >> 1);
        updateFlag(expected.cpu, Flag.C, ((info.data & 0x01) != 0));

        expect_rmw(isAcc, val, expected, info);
    }
    return &expect;
}


// For ASO.
auto expect_ASO()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data << 1);
        updateFlag(expected.cpu, Flag.C, (info.data > 0x7F));
        setA(expected.cpu, getA(expected.cpu) | val);

        expect_rmw(false, val, expected, info);
    }
    return &expect;
}


// For RLA.
auto expect_RLA()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto carry = (getFlag(expected.cpu, Flag.C) ? 1 : 0);
        auto val = cast(ubyte)(info.data << 1 | carry);
        updateFlag(expected.cpu, Flag.C, (info.data > 0x7F));
        setA(expected.cpu, getA(expected.cpu) & val);

        expect_rmw(false, val, expected, info);
    }
    return &expect;
}


// For LSE.
auto expect_LSE()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data >> 1);
        updateFlag(expected.cpu, Flag.C, ((info.data & 0x01) != 0));
        setA(expected.cpu, getA(expected.cpu) ^ val);

        expect_rmw(false, val, expected, info);
    }
    return &expect;
}


/*
 * Slightly cheating--this is copied from the original implementation,
 * but it was independently tested (see test_decimal.d).
 */
void expect_add(bool cmos, ubyte val, ref Expected expected)
{
    with(expected)
    {
        ubyte acc = getA(cpu);
        auto d = getFlag(cpu, Flag.D);
        auto c = getFlag(cpu, Flag.C);

        if (!d)
        {
            uint sum = acc + val + c;
            updateFlag(cpu, Flag.V,
                    (!((acc ^ val) & 0x80)) && ((val ^ sum) & 0x80));
            updateFlag(cpu, Flag.C, (sum > 0xFF));
            setNZ(cpu, cast(ubyte)sum);
            setA(cpu, cast(ubyte)sum);
        }
        else
        {
            int a = acc;
            int al = (a & 0x0F) + (val & 0x0F) + c;
            if (al >= 0x0A)
                al = ((al + 0x06) & 0x0F) + 0x10;
            a = (a & 0xF0) + (val & 0xF0) + al;

            if (!cmos)
            {
                updateFlag(cpu, Flag.N, (a & 0xFF) > 0x7F);
                updateFlag(cpu, Flag.Z, (cast(ubyte)(acc + val + c)) == 0);
            }
            updateFlag(cpu, Flag.V,
                    (!((acc ^ val) & 0x80)) && ((val ^ a) & 0x80));

            if (a >= 0xA0)
                a = a + 0x60;
            updateFlag(cpu, Flag.C, (a >= 0x100));

            setA(cpu, cast(ubyte)a);
            if (cmos)
                setNZ(cpu, cast(ubyte)a);
        }
    }
}


// For ADC.
auto expect_ADC(bool cmos)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected) { incPC(cpu, info.len); }
        expect_add(cmos, info.data, expected);
    }
    return &expect;
}


// For RRA.
auto expect_RRA()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto carry = (getFlag(expected.cpu, Flag.C) ? 0x80 : 0);
        auto val = cast(ubyte)(info.data >> 1 | carry);
        updateFlag(expected.cpu, Flag.C, ((info.data & 0x01) != 0));

        expect_rmw(false, val, expected, info);
        expect_add(false, val, expected);
    }
    return &expect;
}


/*
 * Slightly cheating--this is copied from the original implementation,
 * but it was independently tested (see test_decimal.d).
 */
void expect_sub(bool cmos, ubyte val, ref Expected expected)
{
    with(expected)
    {
        ubyte acc = getA(cpu);
        auto d = getFlag(cpu, Flag.D);
        auto c = getFlag(cpu, Flag.C);

        if (!d)
        {
            uint diff = acc - val - (c ? 0 : 1);
            updateFlag(cpu, Flag.V,
                ((acc ^ diff) & 0x80) && ((acc ^ val) & 0x80));
            updateFlag(cpu, Flag.C, (diff < 0x100));
            setA(cpu, cast(ubyte)diff);
            setNZ(cpu, cast(ubyte)diff);
        }
        else
        {
            if (!cmos)
            {
                int a = acc;
                int al = (a & 0x0F) - (val & 0x0F) - !c;
                if (al < 0)
                    al = ((al - 0x06) & 0x0F) - 0x10;
                a = (a & 0xF0) - (val & 0xF0) + al;
                if (a < 0)
                    a = a - 0x60;

                uint diff = acc - val - !c;
                updateFlag(cpu, Flag.V,
                    ((acc ^ diff) & 0x80) && ((acc ^ val) & 0x80));
                updateFlag(cpu, Flag.C, (diff < 0x100));
                setNZ(cpu, cast(ubyte)diff);

                setA(cpu, cast(ubyte)a);
            }
            else
            {
                int a = acc;
                int al = (a & 0x0F) - (val & 0x0F) - !c;
                a = a - val - !c;
                if (a < 0)
                    a = a - 0x60;
                if (al < 0)
                    a = a - 0x06;

                uint diff = acc - val - !c;
                updateFlag(cpu, Flag.V,
                    ((acc ^ diff) & 0x80) && ((acc ^ val) & 0x80));
                updateFlag(cpu, Flag.C, (diff < 0x100));
                setNZ(cpu, cast(ubyte)a);
                setA(cpu, cast(ubyte)a);
            }
        }
    }
}


// For SBC.
auto expect_SBC(bool cmos)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected) { incPC(cpu, info.len); }
        expect_sub(cmos, info.data, expected);
    }
    return &expect;
}


// For INS.
auto expect_INS()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data + 1);
        expect_rmw(false, val, expected, info);
        expect_sub(false, val, expected);
    }
    return &expect;
}


void expect_compare(Reg reg, ubyte val, ref Expected expected)
{
    with(expected)
    {
        auto r = getReg(cpu, reg);
        updateFlag(cpu, Flag.C, (r >= val));
        setNZ(cpu, cast(ubyte)(r - val));
    }
}


// For CMP, CPX, CPY.
auto expect_cmp(Reg reg)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected) { incPC(cpu, info.len); }
        expect_compare(reg, info.data, expected);
    }
    return &expect;
}


// For DCM.
auto expect_DCM()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data - 1);
        expect_rmw(false, val, expected, info);
        expect_compare(Reg.A, val, expected);
    }
    return &expect;
}


// For ORA.
auto expect_ORA()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data | getA(expected.cpu));
        expect_basic(Reg.A, val, expected, info);
    }
    return &expect;
}


// For AND.
auto expect_AND()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data & getA(expected.cpu));
        expect_basic(Reg.A, val, expected, info);
    }
    return &expect;
}


// For EOR.
auto expect_EOR()
{
    void expect(ref Expected expected, const OpInfo info)
    {
        auto val = cast(ubyte)(info.data ^ getA(expected.cpu));
        expect_basic(Reg.A, val, expected, info);
    }
    return &expect;
}


// Associates opcodes with test setup functions.
string getMemSetup(T)()
if (isCpu!T)
{
    string[] tmp1 = new string[256], tmp2 = new string[256],
             tmp3 = new string[256];
    tmp1[] = "        setup_addr = setup_none();\n";
    tmp2[] = "        setup_test = setup_none();\n";
    tmp3[] = "        expect = expect_none();\n";

    void get_addr(const(ubyte[]) list, string name, string arg = "")
    {
        foreach(op; list)
            tmp1[op] = "setup_addr = setup_addr_" ~ name ~ "(" ~ arg ~ ");\n";
    }

    void get_test(const(ubyte[]) list, string name, string arg = "")
    {
        foreach(op; list)
            tmp2[op] = "setup_test = setup_op_" ~ name ~ "(" ~ arg ~ ");\n";
    }

    void get_expect(const(ubyte[]) list, string name, string arg = "")
    {
        foreach(op; list)
            tmp3[op] = "expect = expect_" ~ name ~ "(" ~ arg ~ ");\n";
    }

    void get_both(const(ubyte[]) list, string name, string arg = "")
    {
        get_test(list, name, arg);
        get_expect(list, name, arg);
    }

    get_addr(REG_OPS!T, "implied");
    get_addr(PUSH_OPS!T, "implied");
    get_addr(PULL_OPS!T, "implied");
    get_addr(BRANCH_OPS!T, "branch", "isCMOS!T");
    get_addr(IMM_OPS!T, "imm");
    get_addr(ZPG_OPS!T, "zpg");
    get_addr(ABS_OPS!T, "abs");
    get_addr([0x4C], "abs");
    get_addr(ZPX_OPS!T, "zpxy", "Reg.X");
    get_addr(ZPY_OPS!T, "zpxy", "Reg.Y");
    get_addr(ABX_OPS!T, "abxy", "Reg.X");
    get_addr(ABY_OPS!T, "abxy", "Reg.Y");
    get_addr(IZX_OPS!T, "izx");
    get_addr(IZY_OPS!T, "izy");

    get_expect([0x18], "flag", "Flag.C, false");
    get_expect([0x38], "flag", "Flag.C, true");
    get_expect([0xD8], "flag", "Flag.D, false");
    get_expect([0xF8], "flag", "Flag.D, true");
    get_expect([0x58], "flag", "Flag.I, false");
    get_expect([0x78], "flag", "Flag.I, true");
    get_expect([0xB8], "flag", "Flag.V, false");
    get_both([0x08], "PHP");
    get_both([0x28], "PLP");
    get_both([0x48], "push", "Reg.A");
    get_both([0x68], "pull", "Reg.A");
    get_both([0x8A], "transfer", "Reg.X, Reg.A");
    get_both([0x98], "transfer", "Reg.Y, Reg.A");
    get_both([0xA8], "transfer", "Reg.A, Reg.Y");
    get_both([0xAA], "transfer", "Reg.A, Reg.X");
    get_test([0x9A, 0xBA], "stack_xfer");
    get_expect([0x9A], "TXS");
    get_expect([0xBA], "TSX");
    get_both([0xA1, 0xA5, 0xA9, 0xAD, 0xB1, 0xB5, 0xB9, 0xBD],
             "load", "Reg.A");
    get_both([0xA2, 0xA6, 0xAE, 0xB6, 0xBE], "load", "Reg.X");
    get_both([0xA0, 0xA4, 0xAC, 0xB4, 0xBC], "load", "Reg.Y");
    get_both([0x81, 0x85, 0x8D, 0x91, 0x95, 0x99, 0x9D], "store", "Reg.A");
    get_both([0x86, 0x8E, 0x96], "store", "Reg.X");
    get_both([0x84, 0x8C, 0x94], "store", "Reg.Y");
    get_expect(BRANCH_OPS!T, "branch");
    get_both([0x24, 0x2C], "BIT");
    get_both([0x00], "BRK");
    get_both([0x40], "RTI");
    get_both([0x60], "RTS");
    get_test([0x6C], "JMP_ind", "isCMOS!T");
    get_expect([0x4C, 0x6C], "JMP");
    get_both([0x20], "JSR");
    get_both([0x88], "DEC_reg", "Reg.Y");
    get_both([0xCA], "DEC_reg", "Reg.X");
    get_both([0xC8], "INC_reg", "Reg.Y");
    get_both([0xE8], "INC_reg", "Reg.X");
    get_both([0xE6, 0xEE, 0xF6, 0xFE], "INC");
    get_both([0xC6, 0xCE, 0xD6, 0xDE], "DEC");
    get_both([0x2A], "ROL", "true");
    get_both([0x0A], "ASL", "true");
    get_both([0x6A], "ROR", "true");
    get_both([0x4A], "LSR", "true");
    get_both([0x26, 0x2E, 0x36, 0x3E], "ROL", "false");
    get_both([0x06, 0x0E, 0x16, 0x1E], "ASL", "false");
    get_both([0x66, 0x6E, 0x76, 0x7E], "ROR", "false");
    get_both([0x46, 0x4E, 0x56, 0x5E], "LSR", "false");
    get_both([0x61, 0x65, 0x69, 0x6D, 0x71, 0x75, 0x79, 0x7D],
             "ADC", "isCMOS!T");
    get_both([0xE1, 0xE5, 0xE9, 0xED, 0xF1, 0xF5, 0xF9, 0xFD],
             "SBC", "isCMOS!T");
    get_both([0xC1, 0xC5, 0xC9, 0xCD, 0xD1, 0xD5, 0xD9, 0xDD], "cmp", "Reg.A");
    get_both([0x01, 0x05, 0x09, 0x0D, 0x11, 0x15, 0x19, 0x1D], "ORA");
    get_both([0x21, 0x25, 0x29, 0x2D, 0x31, 0x35, 0x39, 0x3D], "AND");
    get_both([0x41, 0x45, 0x49, 0x4D, 0x51, 0x55, 0x59, 0x5D], "EOR");
    get_both([0xE0, 0xE4, 0xEC], "cmp", "Reg.X");
    get_both([0xC0, 0xC4, 0xCC], "cmp", "Reg.Y");

    static if (isNMOS!T)
    {
        get_addr(HLT_OPS!T, "implied");

        get_test([0xA3, 0xA7, 0xAF, 0xB3, 0xB7, 0xBF], "load", "Reg.A");
        get_expect([0xA3, 0xA7, 0xAF, 0xB3, 0xB7, 0xBF], "LAX");
        get_expect([0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xEA, 0xFA], "NOP");
        get_expect([0x0C, 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC], "NOP");
        get_expect([0x80, 0x82, 0x89, 0xC2, 0xE2], "NOP");
        get_expect([0x04, 0x44, 0x64], "NOP");
        get_expect([0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4], "NOP");
        get_both([0x83, 0x87, 0x8F, 0x97], "SAX");
        get_both([0x03, 0x07, 0x0F, 0x13, 0x17, 0x1B, 0x1F], "ASO");
        get_both([0x23, 0x27, 0x2F, 0x33, 0x37, 0x3B, 0x3F], "RLA");
        get_both([0x43, 0x47, 0x4F, 0x53, 0x57, 0x5B, 0x5F], "LSE");
        get_both([0x63, 0x67, 0x6F, 0x73, 0x77, 0x7B, 0x7F], "RRA");
        get_both([0xE3, 0xE7, 0xEF, 0xF3, 0xF7, 0xFB, 0xFF], "INS");
        get_both([0xC3, 0xC7, 0xCF, 0xD3, 0xD7, 0xDB, 0xDF], "DCM");
        get_both([0xEB], "SBC", "false");

        // TODO: implement these opcode tests
        get_test([0x0B, 0x2B, 0x4B, 0x6B, 0x8B, 0x93, 0x9B, 0x9C, 0x9E,
                  0x9F, 0xAB, 0xBB, 0xCB, 0xEB], "abort");
    }
    else
    {
        get_addr(NOP1_OPS!T, "implied");
        get_addr(ZPI_OPS!T, "zpi");
        get_both([0x12], "ORA");
        get_both([0x32], "AND");
        get_both([0x52], "EOR");
        get_both([0x72], "ADC", "true");
        get_both([0x92], "store", "Reg.A");
        get_both([0xB2], "load", "Reg.A");
        get_both([0xD2], "cmp", "Reg.A");
        get_both([0xF2], "SBC", "true");
        get_both([0x5A], "push", "Reg.Y");
        get_both([0xDA], "push", "Reg.X");
        get_both([0x7A], "pull", "Reg.Y");
        get_both([0xFA], "pull", "Reg.X");
        get_expect([0xEA], "NOP");
        get_expect(NOP1_OPS!T, "NOP");
        get_expect([0x02, 0x22, 0x42, 0x62, 0x82, 0xC2, 0xE2], "NOP");
        get_expect([0x44, 0x54, 0xD4, 0xF4, 0xDC, 0xFC], "NOP");
        get_both([0x64, 0x74, 0x9C, 0x9E], "STZ");
        get_both([0x34, 0x3C], "BIT");
        get_test([0x89], "BIT"); get_expect([0x89], "BIT_imm");
        get_both([0x14, 0x1C], "TRB");
        get_both([0x04, 0x0C], "TSB");
        get_test([0x7C], "JMP_inx");
        get_expect([0x7C], "JMP");
        get_both([0xB2], "load", "Reg.A");
        get_both([0x92], "store", "Reg.A");
        get_test([0x5C], "5C");
        get_expect([0x5C], "NOP");
        get_both([0x3A], "DEC_reg", "Reg.A");
        get_both([0x1A], "INC_reg", "Reg.A");
    }

    auto ret = "final switch (opcode)\n{\n";
    for (auto i = 0; i < 256; i++)
    {
        ret ~= "    case 0x" ~ to!string(i, 16) ~ ":\n" ~
               "        " ~ tmp1[i] ~ "        " ~ tmp2[i] ~
               "        " ~ tmp3[i] ~ "        break;\n";
    }
    return ret ~ "\n}";
}


alias void delegate(ubyte, ref Expected, CpuInfo, const ref TestMemory, string)
    testreport;


/*
 * Runs one opcode. Calls expect for the expected values of the cpu
 * registers and memory. Calls report with the expected and actual
 * values.
 */
auto run_opcode_test(T)(testexpect expect, testreport report)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        auto testcpu = makeCpu!T(cpu);
        auto mem = TestMemory(data);
        auto expected = Expected(cpu, mem);
        expect(expected, info);
        connectMem(testcpu, mem);
        runOneOpcode(testcpu);
        auto cpuResult = CpuInfo.fromCpu(testcpu);
        report(opcode, expected, cpuResult, mem, T.stringof ~ " | " ~ msg);
        callNext();
    }
    return TestSetup(&setup);
}


// Dummy function. Reports nothing.
auto report_none()
{
    void report(ubyte opcode, ref Expected expected, CpuInfo cpu,
                const ref TestMemory mem, string msg)
    {
    }
    return &report;
}


// Prints the differences between expected and actual cpu/memory.
auto report_debug()
{
    void report(ubyte opcode, ref Expected expected, CpuInfo cpu,
                const ref TestMemory mem, string msg)
    {
        import std.stdio;
        bool badCpu = (expected.cpu != cpu);
        bool badMem = (expected.mem != mem);
        if (badCpu || badMem)
            writeln(format("[%0.2X] %s", opcode, msg));
        if (badCpu)
        {
            writeln("  expect ", expected.cpu);
            writeln("  actual ", cpu);
        }
        if (badMem)
        {
            foreach (h; MemDiff(expected.mem, mem))
            {
                writeln(format("  %0.4X | %s", h.base, formatMemory(h.a, 8)));
                writeln(format("       | %s", formatMemory(h.b, 8)));
            }
        }
        if (badCpu || badMem) throw new Exception("BAD");
    }
    return &report;
}


void test_one_opcode(T)(ubyte opcode, testreport report)
{
    TestSetup setup_addr;
    TestSetup setup_test;
    testexpect expect;

    mixin(getMemSetup!T());

    auto setup = connect(setup_mask_flags(), setup_addr, setup_test);
    auto run = connect(setup, run_opcode_test!T(expect, report));
    run.run(opcode);
}


T[] If(alias cond, T)(T[] actions)
{
    if (cond)
        return actions;
    else
        return [];
}


/// Bus access pattern for register opcodes.
auto accesses_reg(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(REG_OPS!T.canFind(opcode));

    cycles = 2;
    return [Bus(Action.READ, pc)] ~
            If!(isStrict!T)(
                [Bus(Action.READ, pc+1)]);
}


/// Bus access pattern for push opcodes.
auto accesses_push(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(PUSH_OPS!T.canFind(opcode));

    auto sp = getSP(cpu);

    cycles = 3;
    return [Bus(Action.READ, pc)] ~
           If!(isStrict!T)(
                [Bus(Action.READ, pc+1)]) ~
           [Bus(Action.WRITE, sp)];
}


/// Bus access pattern for pull opcodes.
auto accesses_pull(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(PULL_OPS!T.canFind(opcode));

    auto sp = getSP(cpu);
    auto sp1 = pageWrapAdd(sp, 1);

    cycles = 4;
    return [Bus(Action.READ, pc)] ~
           If!(isStrict!T)(
                [Bus(Action.READ, pc+1),
                 Bus(Action.READ, sp)]) ~
           [Bus(Action.READ, sp1)];
}


/// Bus access pattern for immediate mode opcodes.
auto accesses_imm(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(IMM_OPS!T.canFind(opcode));

    bool decimal = isCMOS!T && getFlag(cpu, Flag.D) &&
                   BCD_OPS!T.canFind(opcode);

    cycles = 2 + decimal;
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1)] ~
           If!decimal(If!(isStrict!T)(
                [Bus(Action.READ, pc+2)]));
}


/// Bus access pattern for branch opcodes.
auto accesses_rel(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc], op1 = mem[pc+1];
    assert(BRANCH_OPS!T.canFind(opcode));

    auto base = cast(ushort)(pc + 2);
    bool branch = wouldBranch(cpu, opcode);
    ushort wrongPage = pageWrapAdd(base, cast(byte)op1);
    bool px = wrongPage != pageCrossAdd(base, cast(byte)op1);
    ushort wrongAddr = isNMOS!T ? wrongPage : base;

    cycles = 2 + branch + px;
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1)] ~
           If!branch(If!(isStrict!T)(
                [Bus(Action.READ, pc+2)] ~
                If!px(
                    [Bus(Action.READ, wrongAddr)])));
}


/// Bus access pattern for zeropage mode opcodes.
auto accesses_zpg(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc], op1 = mem[pc+1];
    assert(ZPG_OPS!T.canFind(opcode));

    cycles = 2; // + accesses_end
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1)] ~
           accesses_end(cpu, opcode, 2, op1, cycles);
}


/// Bus access pattern for absolute mode opcodes.
auto accesses_abs(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc], op1 = mem[pc+1], op2 = mem[pc+2];
    assert(ABS_OPS!T.canFind(opcode));

    auto addr = address(op1, op2);

    cycles = 3; // + accesses_end
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1),
            Bus(Action.READ, pc+2)] ~
           accesses_end(cpu, opcode, 3, addr, cycles);
}


/// Bus access pattern for zeropage,x/y mode opcodes.
auto accesses_zpxy(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc], op1 = mem[pc+1];
    bool useX = ZPX_OPS!T.canFind(opcode);
    assert(useX || ZPY_OPS!T.canFind(opcode));

    auto idx = (useX ? getX(cpu) : getY(cpu));
    auto addr = pageWrapAdd(op1, idx);

    cycles = 3; // + accesses_end
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1)] ~
           If!(isStrict!T)(
                If!(isNMOS!T)(
                    [Bus(Action.READ, op1)]) ~
                If!(isCMOS!T)(
                    [Bus(Action.READ, pc+2)])) ~ // XXX
           accesses_end(cpu, opcode, 2, addr, cycles);

    /*
     * According to "Understanding the Apple IIe", the extra read on
     * the 65C02 (marked XXX above) is the address of the last operand
     * byte (pc + 1).
     */
}


/// Bus access pattern for absolute,x/y mode opcodes.
auto accesses_abxy(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    auto op1 = mem[pc+1], op2 = mem[pc+2];
    bool useX = ABX_OPS!T.canFind(opcode);
    assert(useX || ABY_OPS!T.canFind(opcode));


    auto idx = useX ? getX(cpu) : getY(cpu);
    auto base = address(op1, op2);
    auto guess = pageWrapAdd(base, idx);
    auto addr = pageCrossAdd(base, idx);

    cycles = 3; // + accesses_px + accesses_end
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1),
            Bus(Action.READ, pc+2)] ~
           accesses_px(cpu, opcode, 3, guess, addr, cycles) ~
           accesses_end(cpu, opcode, 3, addr, cycles);
}


/// Bus access pattern for indirect zeropage,x mode opcodes.
auto accesses_izx(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc], op1 = mem[pc+1];
    assert(IZX_OPS!T.canFind(opcode));

    auto idx = getX(cpu);
    auto ial = pageWrapAdd(op1, idx);
    auto iah = pageWrapAdd(ial, 1);
    auto addr = address(mem[ial], mem[iah]);

    cycles = 5; // + accesses_end
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1)] ~
           If!(isStrict!T)(
                If!(isNMOS!T)(
                    [Bus(Action.READ, op1)]) ~
                If!(isCMOS!T)(
                    [Bus(Action.READ, pc+2)])) ~ // XXX
           [Bus(Action.READ, ial),
            Bus(Action.READ, iah)] ~
           accesses_end(cpu, opcode, 2, addr, cycles);

    /*
     * According to "Understanding the Apple IIe", the extra read on
     * the 65C02 (marked XXX above) is the address of the last operand
     * byte (pc + 1).
     */
}


/// Bus access pattern for indirect zeropage,y mode opcodes.
auto accesses_izy(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc], op1 = mem[pc+1];
    assert(IZY_OPS!T.canFind(opcode));

    auto idx = getY(cpu);
    auto ial = op1;
    auto iah = pageWrapAdd(ial, 1);
    auto base = address(mem[ial], mem[iah]);
    auto guess = pageWrapAdd(base, idx);
    auto addr = pageCrossAdd(base, idx);

    cycles = 4; // + accesses_px + accesses_end
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1),
            Bus(Action.READ, ial),
            Bus(Action.READ, iah)] ~
           accesses_px(cpu, opcode, 2, guess, addr, cycles) ~
           accesses_end(cpu, opcode, 2, addr, cycles);
}


/// Bus access pattern for indirect zeropage mode opcodes.
auto accesses_zpi(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T && isCMOS!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc], op1 = mem[pc+1];
    assert(ZPI_OPS!T.canFind(opcode));

    auto ial = op1;
    auto iah = pageWrapAdd(ial, 1);
    auto addr = address(mem[ial], mem[iah]);

    cycles = 4; // + accesses_end
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1),
            Bus(Action.READ, ial),
            Bus(Action.READ, iah)] ~
           accesses_end(cpu, opcode, 2, addr, cycles);
}


/// Bus access pattern for NMOS HLT opcodes.
auto accesses_hlt(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T && isNMOS!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(HLT_OPS!T.canFind(opcode));

    cycles = 1;
    return [Bus(Action.READ, pc)];
}


/// Bus access pattern for 1-cycle NOPs.
auto accesses_nop1(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T && isCMOS!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(NOP1_OPS!T.canFind(opcode));

    cycles = 1;
    return [Bus(Action.READ, pc)];
}


auto accesses_px(T)(T cpu, ubyte opcode, int opLen, ushort guess, ushort right,
                    ref int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    bool noShortcut = WRITE_OPS!T.canFind(opcode) ||
                      (isNMOS!T ? (RMW_OPS!T.canFind(opcode))
                                : (opcode == 0xDE || opcode == 0xFE));

    if (guess != right)
    {
        cycles += 1;
        return If!(isStrict!T)(
                    If!(isNMOS!T)([Bus(Action.READ, guess)]) ~
                    If!(isCMOS!T)([Bus(Action.READ, pc + opLen)])); // XXX
    }
    else if (noShortcut)
    {
        cycles += 1;
        return If!(isStrict!T)([Bus(Action.READ, guess)]);
    }
    else
    {
        return cast(Bus[])[];
    }

    /*
     * According to "Understanding the Apple IIe", the extra read on
     * the 65C02 (marked XXX above) is the address of the last operand
     * byte (pc + opLen - 1) for abx/aby, or the address of the high
     * byte of the indirect address (op1 + 1) for izy.
     */
}

auto accesses_end(T)(T cpu, ubyte opcode, int opLen, ushort addr,
                     ref int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    bool rmw = RMW_OPS!T.canFind(opcode);
    bool write = !rmw && WRITE_OPS!T.canFind(opcode);
    bool read = !rmw && !write;
    bool decimal = isCMOS!T && getFlag(cpu, Flag.D) &&
                   BCD_OPS!T.canFind(opcode);

    cycles += (rmw ? 3 : (write ? 1 : (1 + decimal)));
    return If!read(
                [Bus(Action.READ, addr)] ~
                If!decimal(If!(isStrict!T)(
                    [Bus(Action.READ, pc + opLen)]))) ~
           If!write(
                [Bus(Action.WRITE, addr)]) ~
           If!rmw(
                [Bus(Action.READ, addr)] ~
                If!(isStrict!T)(
                    If!(isNMOS!T)(
                        [Bus(Action.WRITE, addr)]) ~
                    If!(isCMOS!T)(
                        [Bus(Action.READ, addr)])) ~
                [Bus(Action.WRITE, addr)]);
}


/// Bus access pattern for RTS.
auto accesses_op_RTS(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(opcode == 0x60);

    auto sp = getSP(cpu);
    auto sp1 = pageWrapAdd(sp, 1);
    auto sp2 = pageWrapAdd(sp, 2);
    auto ret = address(mem[sp1], mem[sp2]);

    cycles = 6;
    return [Bus(Action.READ, pc)] ~
           If!(isStrict!T)(
                [Bus(Action.READ, pc+1),
                 Bus(Action.READ, sp)]) ~
           [Bus(Action.READ, sp1),
            Bus(Action.READ, sp2)] ~
           If!(isStrict!T)(
                [Bus(Action.READ, ret)]);
}


/// Bus access pattern for RTI.
auto accesses_op_RTI(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(opcode == 0x40);

    auto sp = getSP(cpu);
    auto sp1 = pageWrapAdd(sp, 1);
    auto sp2 = pageWrapAdd(sp, 2);
    auto sp3 = pageWrapAdd(sp, 3);

    cycles = 6;
    return [Bus(Action.READ, pc)] ~
           If!(isStrict!T)(
                [Bus(Action.READ, pc+1),
                 Bus(Action.READ, sp)]) ~
           [Bus(Action.READ, sp1),
            Bus(Action.READ, sp2),
            Bus(Action.READ, sp3)];
}


/// Bus access pattern for BRK.
auto accesses_op_BRK(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(opcode == 0x00);

    auto sp = getSP(cpu);
    auto sp1 = pageWrapAdd(sp, -1);
    auto sp2 = pageWrapAdd(sp, -2);

    cycles = 7;
    return [Bus(Action.READ, pc)] ~
           If!(isStrict!T)(
                [Bus(Action.READ, pc+1)]) ~
           [Bus(Action.WRITE, sp),
            Bus(Action.WRITE, sp1),
            Bus(Action.WRITE, sp2),
            Bus(Action.READ, 0xFFFE),
            Bus(Action.READ, 0xFFFF)];
}


/// Bus access pattern for JSR
auto accesses_op_JSR(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(opcode == 0x20);

    auto sp = getSP(cpu);
    auto sp1 = pageWrapAdd(sp, -1);

    cycles = 6;
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1)] ~
           If!(isStrict!T)(
                [Bus(Action.READ, sp)]) ~
           [Bus(Action.WRITE, sp),
            Bus(Action.WRITE, sp1),
            Bus(Action.READ, pc+2)];
}


/// Bus access pattern for JMP absolute
auto accesses_op_JMP_abs(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(opcode == 0x4C);

    cycles = 3;
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1),
            Bus(Action.READ, pc+2)];
}


/// Bus access pattern for JMP indirect
auto accesses_op_JMP_ind(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc], op1 = mem[pc+1], op2 = mem[pc+2];
    assert(opcode == 0x6C);

    auto ial = address(op1, op2);
    auto iah = (isNMOS!T ? pageWrapAdd(ial, 1)
                         : pageCrossAdd(ial, 1));

    cycles = 5 + isCMOS!T;
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1),
            Bus(Action.READ, pc+2)] ~
           If!(isStrict!T)(If!(isCMOS!T)(
                [Bus(Action.READ, pc+3)])) ~ // XXX
           [Bus(Action.READ, ial),
            Bus(Action.READ, iah)];

    /*
     * According to "Understanding the Apple IIe", the extra read on
     * the 65C02 (marked XXX above) is the address of the last operand
     * byte (pc + 2).
     */
}


/// Bus access pattern for JMP indirect,x
auto accesses_op_JMP_inx(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T && isCMOS!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(opcode == 0x7C);

    auto idx = getX(cpu);
    auto base = address(mem[pc+1], mem[pc+2]);
    auto ial = pageCrossAdd(base, idx);
    auto iah = pageCrossAdd(ial, 1);

    cycles = 6;
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1),
            Bus(Action.READ, pc+2)] ~
           If!(isStrict!T)(
                [Bus(Action.READ, pc+3)]) ~ // XXX
           [Bus(Action.READ, ial),
            Bus(Action.READ, iah)];

    /*
     * According to "Understanding the Apple IIe", the extra read on
     * the 65C02 (marked XXX above) is the address of the last operand
     * byte (pc + 2).
     */
}


/// Bus access pattern for CMOS opcode 5C
auto accesses_op_5C(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T && isCMOS!T)
{
    auto pc = getPC(cpu);
    auto opcode = mem[pc];
    assert(opcode == 0x5C);

    auto weird = address(mem[pc+1], 0xFF);

    cycles = 8;
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1)] ~
           If!(isStrict!T)(
                [Bus(Action.READ, pc+2),
                 Bus(Action.READ, weird),
                 Bus(Action.READ, 0xFFFF),
                 Bus(Action.READ, 0xFFFF),
                 Bus(Action.READ, 0xFFFF),
                 Bus(Action.READ, 0xFFFF)]);
}


// Associates opcodes with expected access patterns.
string getExpected(T)()
{
    string[] tmp = new string[256];

    void add_op(const(ubyte[]) list, string fname)
    {
        foreach(op; list)
        {
            tmp[op] = "    case 0x" ~ to!string(op, 16) ~ ": " ~
                      "expected = &" ~ fname ~ "!T; break;";
        }
    }

    add_op(REG_OPS!T, "accesses_reg");
    add_op(PUSH_OPS!T, "accesses_push");
    add_op(PULL_OPS!T, "accesses_pull");
    add_op(BRANCH_OPS!T, "accesses_rel");
    add_op(IMM_OPS!T, "accesses_imm");
    add_op(ZPG_OPS!T, "accesses_zpg");
    add_op(ZPX_OPS!T, "accesses_zpxy");
    add_op(ZPY_OPS!T, "accesses_zpxy");
    add_op(ABS_OPS!T, "accesses_abs");
    add_op(ABX_OPS!T, "accesses_abxy");
    add_op(ABY_OPS!T, "accesses_abxy");
    add_op(IZX_OPS!T, "accesses_izx");
    add_op(IZY_OPS!T, "accesses_izy");
    add_op([0x00], "accesses_op_BRK");
    add_op([0x20], "accesses_op_JSR");
    add_op([0x40], "accesses_op_RTI");
    add_op([0x4C], "accesses_op_JMP_abs");
    add_op([0x60], "accesses_op_RTS");
    add_op([0x6C], "accesses_op_JMP_ind");
    static if (isNMOS!T)
        add_op(HLT_OPS!T, "accesses_hlt");
    else
    {
        add_op(ZPI_OPS!T, "accesses_zpi");
        add_op(NOP1_OPS!T, "accesses_nop1");
        add_op([0x7C], "accesses_op_JMP_inx");
        add_op([0x5C], "accesses_op_5C");
    }

    return "final switch (opcode)\n{\n" ~ join(tmp, "\n") ~ "\n}";
}


template timesetup_t(T)
{
    alias Bus[] function(T, ref TestMemory, out int) timesetup_t;
}


alias void delegate(int, const Bus[], int, const Bus[], ubyte, string)
    busreport;


auto run_timing_test(T)(timesetup_t!T expect, busreport report)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        auto testcpu = makeCpu!T(cpu);
        auto mem = TestMemory(data);

        int expCycles;
        auto expBus = expect(testcpu, mem, expCycles);
        expBus = expBus ~ new Bus[8 - expBus.length];

        connectMem(testcpu, mem);
        auto actualBus = recordBus(testcpu);
        auto actualCycles = recordCycles(testcpu);

        runOneOpcode(testcpu);

        report(actualCycles, actualBus, expCycles, expBus,
               opcode, T.stringof ~  " | " ~ msg);
        callNext();
    }
    return TestSetup(&setup);
}



auto report_timing_debug()
{
    void report(int actualCycles, const Bus[] actualBus,
                int expectCycles, const Bus[] expectBus,
                ubyte opcode, string msg)
    {
        if (actualBus != expectBus)
        {
            // XXX make error message, throw
        }
        if (actualCycles != expectCycles)
        {
            // XXX make error message, throw
        }
        if (actualBus == expectBus && actualCycles == expectCycles) {}
        else
        {
            write(format("[%0.2X] %s", opcode, msg));
            writeln();
            writeln(expectCycles, " ", actualCycles);
            writeln(expectBus);
            writeln(actualBus);
            throw new TestException("timing");
        }
    }
    return &report;
}


// Tests the bus access patterns and cycles taken for a given opcode.
void test_opcode_timing(T)(ubyte opcode, busreport report)
{
    TestSetup setup_addr;
    TestSetup setup_test;
    testexpect expect;
    timesetup_t!T expected;

    mixin(getMemSetup!T());
    mixin(getExpected!T());

    auto setup = connect(setup_mask_flags(), setup_addr, setup_test);
    auto run = connect(setup, run_timing_test!T(expected, report));
    run.run(opcode);
}
