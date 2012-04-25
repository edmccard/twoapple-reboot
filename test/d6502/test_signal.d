import std.stdio, std.string, std.exception;

import test.d6502.base, test.d6502.cpu;


auto setup_vectors(T)(bool res, bool nmi, bool irq)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        setPC(cpu, 0xfd00);
        auto ndata = [Block(0xfd00, [0xea, 0xea]),
                      Block(0xfe35, [0xea, 0xea])];
        if (res)
            callNext("RESET ", ndata ~
                     [Block(0xfffa, [0x00, 0xff, 0x35, 0xfe, 0x80, 0xff])]);
        else if (nmi)
            callNext("NMI ", ndata ~
                     [Block(0xfffa, [0x35, 0xfe, 0x40, 0xff, 0x80, 0xff])]);
        else if (irq && !getFlag(cpu, Flag.I))
            callNext("IRQ ", ndata ~
                     [Block(0xfffa, [0x00, 0xff, 0x40, 0xff, 0x35, 0xfe])]);
        else
            callNext("NOP ", ndata);
    }

    return connect(setup_mask_flags(), setup_flag(Flag.I), TestSetup(&setup));
}


auto accesses_reset(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto sp = getSP(cpu);
    auto sp1 = pageWrapAdd(sp, -1);
    auto sp2 = pageWrapAdd(sp, -2);

    cycles = 7;
    return If!(strict)(
                [Bus(Action.READ, pc),
                 Bus(Action.READ, pc),
                 Bus(Action.READ, sp),
                 Bus(Action.READ, sp1),
                 Bus(Action.READ, sp2)]) ~
           [Bus(Action.READ, 0xfffc),
            Bus(Action.READ, 0xfffd)];
}

auto accesses_nmi(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto sp = getSP(cpu);
    auto sp1 = pageWrapAdd(sp, -1);
    auto sp2 = pageWrapAdd(sp, -2);

    cycles = 7;
    return If!(strict)(
                [Bus(Action.READ, pc),
                 Bus(Action.READ, pc)]) ~
           [Bus(Action.WRITE, sp),
            Bus(Action.WRITE, sp1),
            Bus(Action.WRITE, sp2),
            Bus(Action.READ, 0xfffa),
            Bus(Action.READ, 0xfffb)];
}

auto accesses_irq(T)(T cpu, ref TestMemory mem, out int cycles)
if (isCpu!T)
{
    auto pc = getPC(cpu);
    auto sp = getSP(cpu);
    auto sp1 = pageWrapAdd(sp, -1);
    auto sp2 = pageWrapAdd(sp, -2);

    cycles = 7;
    return If!(strict)(
                [Bus(Action.READ, pc),
                 Bus(Action.READ, pc)]) ~
           [Bus(Action.WRITE, sp),
            Bus(Action.WRITE, sp1),
            Bus(Action.WRITE, sp2),
            Bus(Action.READ, 0xfffe),
            Bus(Action.READ, 0xffff)];
}


auto check_signal_timing(T)(bool res, bool nmi, bool irq, busreport report)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        auto testcpu = makeCpu!T(cpu);
        auto mem = TestMemory(data);

        if (res) testcpu.signals.triggerReset();
        if (nmi) testcpu.signals.triggerNMI();
        if (irq) testcpu.signals.assertIRQ();

        int expCycles, dummy;
        Bus[] expBus;
        auto accesses_after = [Bus(Action.READ, 0xfe35)] ~
                              If!(strict)([Bus(Action.READ, 0xfe36)]);
        if (res)
            expBus = accesses_reset(testcpu, mem, expCycles) ~
                     accesses_after;
        else if (nmi)
            expBus = accesses_nmi(testcpu, mem, expCycles) ~
                     accesses_after;
        else if (irq && !getFlag(testcpu, Flag.I))
            expBus = accesses_irq(testcpu, mem, expCycles) ~
                     accesses_after;
        else
            expBus = accesses_reg(testcpu, mem, dummy);
        expCycles += 2;
        expBus = expBus ~ new Bus[9 - expBus.length];

        connectMem(testcpu, mem);
        auto actualBus = recordBus(testcpu, 9);
        auto actualCycles = recordCycles(testcpu);

        runOneOpcode(testcpu);

        report(actualCycles, actualBus, expCycles, expBus,
               opcode, T.stringof ~  " | " ~ msg);
        callNext();
    }
    return TestSetup(&setup);
}


auto expect_int(T)(bool res, bool nmi, bool irq)
{
    void expect(ref Expected expected, const OpInfo info)
    {
        with(expected)
        {
            if (res || nmi || (irq && !getFlag(cpu, Flag.I)))
            {
                ushort ret = cast(ushort)(getPC(cpu));
                if (!res)
                    mem[getSP(cpu)] = addrHi(ret);
                decSP(cpu);
                if (!res)
                    mem[getSP(cpu)] = addrLo(ret);
                decSP(cpu);
                if (!res)
                    mem[getSP(cpu)] = getStatus(cpu) & ~0x10;
                decSP(cpu);
                setPC(cpu, 0xfe36);
                setFlag(cpu, Flag.I);
                if (isCMOS!T) clearFlag(cpu, Flag.D);
            }
            else
            {
                setPC(cpu, 0xfd01);
            }
        }
    }

    return &expect;
}


auto check_signal(T)(bool res, bool nmi, bool irq, testreport report)
{
    auto setup(ubyte opcode, CpuInfo cpu, Block[] data, OpInfo info,
              string msg, TestSetup* next)
    {
        mixin testCallNext;
        auto testcpu = makeCpu!T(cpu);
        auto mem = TestMemory(data);
        auto expected = Expected(cpu, mem);
        expect_int!T(res, nmi, irq)(expected, info);
        connectMem(testcpu, mem);

        if (res) testcpu.signals.triggerReset();
        if (nmi) testcpu.signals.triggerNMI();
        if (irq) testcpu.signals.assertIRQ();

        runOneOpcode(testcpu);
        auto cpuResult = CpuInfo.fromCpu(testcpu);
        report(opcode, expected, cpuResult, mem, T.stringof ~ " | " ~ msg);
        callNext();
    }
    return TestSetup(&setup);
}


void test_signals(T)()
{
    void foo(T)(bool res, bool nmi, bool irq)
    {
        auto run = connect(setup_vectors!T(res, nmi, irq),
            check_signal_timing!T(res, nmi, irq, report_timing_debug()));
        run.run(0xea);
    }

    void bar(T)(bool res, bool nmi, bool irq)
    {
        auto run = connect(setup_vectors!T(res, nmi, irq),
            check_signal!T(res, nmi, irq, report_debug()));
        run.run(0xea);
    }

    foreach (res; [false, true])
    {
        foreach (nmi; [false, true])
        {
            foreach (irq; [false, true])
            {
                foo!T(res, nmi, irq);
                bar!T(res, nmi, irq);
            }
        }
    }
}

void test_cli_delay(T)()
{
    void run_test(ubyte opcode2, ushort delayPC, string name)
    {
        auto mem = TestMemory(Block(0xfd00, [0x58, opcode2, 0xea]),
                              Block(0xfe35, [0xea, 0xea, 0xea]),
                              Block(0xfffe, [0x35, 0xfe]));
        auto cpu = makeCpu!T();
        setPC(cpu, 0xfd00);
        setFlag(cpu, Flag.I);
        cpu.signals.assertIRQ();
        connectMem(cpu, mem);
        runOneOpcode(cpu);
        runOneOpcode(cpu);
        runOneOpcode(cpu);

        static if (isCMOS!T) { auto expPC = 0xfe37; }
        else { auto expPC = delayPC; }

        if (getPC(cpu) != expPC)
        {
            writeln(format(name ~ " expected pc $%0.4x got $%0.4x",
                           expPC, getPC(cpu)));
            throw new TestException("cli_delay_1");
        }
    }

    run_test(0xea, 0xfe36, "CLI-delay");
    run_test(0x78, 0xfd03, "CLI-delay-allows-SEI");
    run_test(0x58, 0xfe36, "multiple-CLI");
}

void test_plp_delay(T)()
{
    void run_test(ubyte opcode2, ushort delayPC, string name)
    {
        auto mem = TestMemory(Block(0x1fe, [0x00, 0x00]),
                              Block(0xfd00, [0x28, opcode2, 0xea]),
                              Block(0xfe35, [0xea, 0xea, 0xea]),
                              Block(0xfffe, [0x35, 0xfe]));
        auto cpu = makeCpu!T();
        setPC(cpu, 0xfd00);
        setSP(cpu, 0x01fd);
        setFlag(cpu, Flag.I);
        cpu.signals.assertIRQ();
        connectMem(cpu, mem);
        runOneOpcode(cpu);
        runOneOpcode(cpu);
        runOneOpcode(cpu);

        static if (isCMOS!T) { auto expPC = 0xfe37; }
        else { auto expPC = delayPC; }

        if (getPC(cpu) != expPC)
        {
            writeln(format(name ~ " expected pc $%0.4x got $%0.4x",
                           expPC, getPC(cpu)));
            throw new TestException("cli_delay_1");
        }
    }

    run_test(0xea, 0xfe36, "PLP-delay");
    run_test(0x78, 0xfd03, "PLP-delay-allows-SEI");
    run_test(0x28, 0xfe36, "multiple-PLP");
}

void test_sei_interruptable(T)()
{
    auto mem = TestMemory(Block(0xfd00, [0x78, 0xea, 0xea]),
                          Block(0xfe35, [0xea, 0xea, 0xea]),
                          Block(0xfffe, [0x35, 0xfe]));
    auto cpu = makeCpu!T();
    setPC(cpu, 0xfd00);
    clearFlag(cpu, Flag.I);
    cpu.signals.assertIRQ();
    connectMem(cpu, mem);
    runOneOpcode(cpu);

    if (getPC(cpu) != 0xfe36)
    {
        writeln(format("SEI expected pc $fe36 got $%0.4x", getPC(cpu)));
        throw new TestException("cli_delay_1");
    }
}

void test_nmi_brk(T)()
{
    class RunTest
    {
        uint ticks, nmiTick;
        T cpu;
        void tick()
        {
            if (ticks == nmiTick) cpu.signals.triggerNMI();
            ticks++;
        }
        this(uint nmiTick)
        {
            this.nmiTick = nmiTick;
            auto mem = TestMemory(Block(0xfd00, [0x00, 0xea]),
                                  Block(0xfe35, [0xea]),
                                  Block(0xff45, [0xea]),
                                  Block(0xfffa, [0x45, 0xff]),
                                  Block(0xfffe, [0x35, 0xfe]));
            cpu = makeCpu!T();
            setPC(cpu, 0xfd00);
            connectMem(cpu, mem);
            cpu.clock.dtick = &tick;
            runOneOpcode(cpu);
            ushort expPC;
            if (nmiTick < 5 && isNMOS!T)
                expPC = 0xff45;
            else
                expPC = 0xfe35;
            if (getPC(cpu) != expPC)
            {
                writeln(format("nmi-brk tick %d expected $%0.4x got $%0.4x",
                               nmiTick, expPC, getPC(cpu)));
                throw new TestException("nmi-brk");
            }
        }
    }

    foreach (t; 0..6)
    {
        auto dummy = new RunTest(t);
    }
}


void main()
{
    alias CPU!("6502") T1;
    writeln("Testing signals, 6502");
    test_signals!T1();
    test_cli_delay!T1();
    test_plp_delay!T1();
    test_sei_interruptable!T1();
    version(Cumulative) {}
    else { test_nmi_brk!T1(); }

    alias CPU!("65C02") T2;
    writeln("Testing signals, 65C02");
    test_signals!T2();
    test_cli_delay!T2();
    test_plp_delay!T2();
    test_sei_interruptable!T2();
    version(Cumulative) {}
    else { test_nmi_brk!T2(); }
}
