module test.test_bus;


import std.algorithm, std.array, std.conv, std.exception, std.stdio,
       std.string;

import test.base, test.cpu, test.opcodes;


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

unittest
{
    auto report = report_timing_debug();

    alias CPU!("65C02", false, false) T1;
    for (int op = 0x00; op < 0x100; op++)
        test_opcode_timing!T1(cast(ubyte)op, report);

    alias CPU!("65C02", true, false) T2;
    for (int op = 0x00; op < 0x100; op++)
        test_opcode_timing!T2(cast(ubyte)op, report);

    alias CPU!("6502", false, false) T3;
    for (int op = 0x00; op < 0x100; op++)
        test_opcode_timing!T3(cast(ubyte)op, report);

    alias CPU!("6502", true, false) T4;
    for (int op = 0x00; op < 0x100; op++)
        test_opcode_timing!T4(cast(ubyte)op, report);

    alias CPU!("65C02", false, true) T5;
    for (int op = 0x00; op < 0x100; op++)
        test_opcode_timing!T5(cast(ubyte)op, report);

    alias CPU!("65C02", true, true) T6;
    for (int op = 0x00; op < 0x100; op++)
        test_opcode_timing!T6(cast(ubyte)op, report);

    alias CPU!("6502", false, true) T7;
    for (int op = 0x00; op < 0x100; op++)
        test_opcode_timing!T7(cast(ubyte)op, report);

    alias CPU!("6502", true, true) T8;
    for (int op = 0x00; op < 0x100; op++)
        test_opcode_timing!T8(cast(ubyte)op, report);
}
