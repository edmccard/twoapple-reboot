module test.test_func;


import  std.string;

import test.base, test.cpu, test.opcodes;


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


unittest
{
    auto report = report_debug();

    alias CPU!("65C02", false, false) T1;
    foreach (opcode; 0..255)
        test_one_opcode!T1(cast(ubyte)opcode, report);

    alias CPU!("6502", false, false) T2;
    foreach (opcode; 0..255)
        test_one_opcode!T2(cast(ubyte)opcode, report);
}
