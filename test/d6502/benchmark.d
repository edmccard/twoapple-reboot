import std.datetime, std.stdio;

import test.d6502.base, test.d6502.cpu;


final class BreakRunner
{
    TestMemory* mem;
    bool* keepRunning;

    this(ref TestMemory mem)
    {
        this.mem = &mem;
    }

    final ubyte read(ushort addr)
    {
        if (addr == 0xfffe)
        {
            *keepRunning = false;
            return 0x00;
        }
        else if (addr == 0xffff)
        {
            return 0x80;
        }
        else return mem.read(addr);
    }

    final void write(ushort addr, ubyte val)
    {
        mem.write(addr, val);
    }

    static if (cumulative) { final void tick(int) {} }
    else { final void tick() {} }
}


void run_benchmark(T)()
if (isCpu!T)
{
    auto mem = decimal_test_mem!T();
    auto runner = new BreakRunner(mem);
    auto cpu = new T(runner, runner);
    runner.keepRunning = &cpu.keepRunning;
    setPC(cpu, 0x8000);
    cpu.run(true);

    if (mem[0x8003])
    {
        // TODO: check data block to find out what failed exactly
        throw new TestException("failed decimal mode " ~ T.stringof);
    }
}


void main()
{
//    auto milliExpected = (61886766.0 / 1020484.0) * 1000;
    auto milliExpected = (64508206.0 / 1020484.0) * 1000;
    auto r = benchmark!(
        run_benchmark!(CPU!("65C02", BreakRunner, BreakRunner)))(1);
    writeln(milliExpected / r[0].to!("msecs", int));
}
