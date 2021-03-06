import std.stdio;

import test.d6502.base, test.d6502.cpu;


void main(string[] args)
{
    auto opts = CheckOptions(args);
    auto report = report_debug();

    alias CPU!("6502") T1;
    writeln("Testing functionality, 6502");
    foreach (opcode; opts.codes6502)
        test_one_opcode!T1(cast(ubyte)opcode, report);

    alias CPU!("65C02") T2;
    writeln("Testing functionality, 65C02");
    foreach (opcode; opts.codes65C02)
        test_one_opcode!T2(cast(ubyte)opcode, report);
}
