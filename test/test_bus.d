import std.stdio;

import test.base, test.cpu;


void main(string[] args)
{
    auto opts = CheckOptions(args);
    auto report = report_timing_debug();

    alias CPU!("6502") T1;
    writeln("Testing bus/timing, 6502");
    foreach (op; opts.codes6502)
        test_opcode_timing!T1(cast(ubyte)op, report);

    alias CPU!("65C02") T2;
    writeln("Testing bus/timing, 65C02");
    foreach (op; opts.codes65C02)
        test_opcode_timing!T2(cast(ubyte)op, report);
}
