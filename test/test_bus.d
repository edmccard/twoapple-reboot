module test_bus;

import std.algorithm, std.array, std.conv, std.exception, std.string;
import test.base;


T[] If(alias cond, T)(T[] actions)
{
    if (cond)
        return actions;
    else
        return [];
}


template timesetup_t(T)
{
    alias Bus[] function(T, ref TestMemory, out int) timesetup_t;
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

    bool decimal = isCMOS!T && isStrict!T && getFlag(cpu, Flag.D) &&
                   BCD_OPS!T.canFind(opcode);

    cycles = 2 + decimal;
    return [Bus(Action.READ, pc),
            Bus(Action.READ, pc+1)] ~
           If!decimal(
                [Bus(Action.READ, pc+2)]);
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
    bool decimal = isCMOS!T && isStrict!T && getFlag(cpu, Flag.D) &&
                   BCD_OPS!T.canFind(opcode);

    cycles += (rmw ? 3 : (write ? 1 : (1 + decimal)));
    return If!read(
                [Bus(Action.READ, addr)] ~
                If!decimal(
                    [Bus(Action.READ, pc + opLen)])) ~
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


enum Action : ushort { NONE, READ, WRITE }

struct Bus
{
    Action action;
    ushort addr;

    this(Action action, int addr)
    {
        this.action = action; this.addr = cast(ushort)addr;
    }

    string toString() const
    {
        return format("Bus(%s, %0.4X)", to!string(action), addr);
    }
}

/*
 *
 */
const(Bus[]) recordBus(T)(T cpu, int actions = 8)
if (isCpu!T)
{
    auto record = new Bus[actions];
    int c;

    enforce(cpu.memoryRead !is null && cpu.memoryWrite !is null);
    auto wrappedRead = cpu.memoryRead;
    auto wrappedWrite = cpu.memoryWrite;

    ubyte read(ushort addr)
    {
        if (c == actions)
            throw new TestException(
                format("cannot record more than %d actions", actions));
        record[c++] = Bus(Action.READ, addr);
        return wrappedRead(addr);
    }

    void write(ushort addr, ubyte val)
    {
        if (c == actions)
            throw new TestException(
                format("cannot record more than %d actions", actions));
        record[c++] = Bus(Action.WRITE, addr);
        wrappedWrite(addr, val);
    }

    cpu.memoryRead = &read;
    cpu.memoryWrite = &write;

    return record;
}

auto recordCycles(T)(T cpu)
if (isCpu!T)
{
    auto cycles = new int;
    auto wrappedTick = cpu.tick;

    static if (isCumulative!T)
    {
        void tick(int cyc)
        {
            (*cycles) += cyc;
            wrappedTick(cyc);
        }
    }
    else
    {
        void tick()
        {
            (*cycles)++;
            wrappedTick();
        }
    }
    cpu.tick = &tick;

    return constRef(cycles);
}


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

import std.stdio;

void test_opcode_timing(T)(ubyte opcode)
{
    addrsetup_t!T[] function(ubyte) setups1;
    datasetup_t!T[] function(ubyte) setups2;
    mixin(getMemSetup!T());

    timesetup_t!T expected;
    mixin(getExpected!T());

    auto funcs1 = setups1(opcode);
    string name1;
    foreach(func1; funcs1)
    {
        ushort addr;
        int cycles;
        auto cpu = new T();
        auto block1 = func1(cpu, addr, name1);
        auto mem = TestMemory(block1);
        connectCpu(cpu, mem);
        auto exp = expected(cpu, mem, cycles);
        exp = exp ~ new Bus[8 - exp.length];
        auto actual = recordBus(cpu);
        auto actualCycles = recordCycles(cpu);
        // XXX debug
        write(format("Testing %s (%0.2X) -- ", name1, opcode));
        try
        {
            runOneOpcode(cpu);
        }
        catch (TestException e) // possibly not related to timing
        {
            // XXX wrap
            throw e;
        }
        if (actual != exp)
        {
            // XXX make error message, throw
        }
        if (actualCycles != cycles)
        {
            // XXX make error message, throw
        }
        if (actual == exp && actualCycles == cycles)
            writeln("OK");
        else
        {
            writeln();
            writeln(actualCycles, " ", cycles);
            writeln(actual);
            writeln(exp);
            throw new TestException("timing");
        }
    }
}

unittest
{
    import std.stdio;

    alias CPU!("65C02", false, false) T1;
    for (int op = 0x00; op < 0x100; op++)
    test_opcode_timing!T1(cast(ubyte)op);

    alias CPU!("65C02", true, false) T2;
    for (int op = 0x00; op < 0x100; op++)
    test_opcode_timing!T2(cast(ubyte)op);

    alias CPU!("6502", false, false) T3;
    for (int op = 0x00; op < 0x100; op++)
    test_opcode_timing!T3(cast(ubyte)op);

    alias CPU!("6502", true, false) T4;
    for (int op = 0x00; op < 0x100; op++)
    test_opcode_timing!T4(cast(ubyte)op);

    alias CPU!("65C02", false, true) T1;
    for (int op = 0x00; op < 0x100; op++)
    test_opcode_timing!T1(cast(ubyte)op);

    alias CPU!("65C02", true, true) T2;
    for (int op = 0x00; op < 0x100; op++)
    test_opcode_timing!T2(cast(ubyte)op);

    alias CPU!("6502", false, true) T3;
    for (int op = 0x00; op < 0x100; op++)
    test_opcode_timing!T3(cast(ubyte)op);

    alias CPU!("6502", true, true) T4;
    for (int op = 0x00; op < 0x100; op++)
    test_opcode_timing!T4(cast(ubyte)op);
}
