import std.stdio;

import test.d6502.base, test.d6502.cpu;


void testDecimalMode(T)()
if (isCpu!T)
{
    auto mem = decimal_test_mem!T();
    auto cpu = makeCpu!T();
    setPC(cpu, 0x8000);
    connectMem(cpu, mem);
    runUntilBRK(cpu);

    if (mem[0x8003])
    {
        // TODO: check data block to find out what failed exactly
        throw new TestException("failed decimal mode " ~ T.stringof);
    }
}

void main()
{
    writeln("Testing decimal mode, 6502");
    testDecimalMode!(CPU!("6502"))();

    writeln("Testing decimal mode, 65C02");
    testDecimalMode!(CPU!("65C02"))();
}
