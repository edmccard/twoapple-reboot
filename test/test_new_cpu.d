version(Strict)
    enum s1 = true;
else
    enum s1 = false;
version(Cumulative)
    enum c1 = true;
else
    enum c1 = false;

void main()
{
    import std.stdio;
    import test.base, test.cpu;

    void test_func(ubyte[] ops)
    {
        auto report = report_debug();
        auto report2 = report_timing_debug();

        version(OpFunctions) writeln("(Functions)");
        version(OpDelegates) writeln("(Delegates)");
        version(OpSwitch) writeln("(Switch)");
        version(OpNestedSwitch) writeln("(NestedSwitch)");

        alias Cpu!("6502", s1, c1) TX1;
        writeln("NMOS ", s1, " ", c1, " func");
        foreach (op; ops)
            test_one_opcode!TX1(op, report);
        writeln("NMOS ", s1, " ", c1, " bus");
        foreach(op; ops)
            test_opcode_timing!TX1(op, report2);

        alias Cpu!("65C02", s1, c1) TX2;
        writeln("CMOS ", s1, " ", c1, " func");
        foreach (op; ops)
            test_one_opcode!TX2(op, report);
        writeln("CMOS ", s1, " ", c1, " bus");
        foreach (op; ops)
            test_opcode_timing!TX2(op, report2);
    }

    test_func([0x00, 0x08, 0x10, 0x18, 0x28, 0x30, 0x38, 0x50, 0x58, 0x68,
               0x70, 0x78, 0x90, 0xad, 0xb0, 0xb8, 0xd0, 0xd8, 0xf0, 0xf8,
               0xae, 0xac, 0x8d, 0x8e, 0x8c, 0xe8, 0xc8, 0xca, 0x88, 0xcd,
               0xec, 0xcc, 0x0d, 0x2d, 0x4d, 0xee, 0xce, 0x60, 0x6d, 0xed,
               0x4c, 0x09, 0x29, 0x49, 0x69, 0xe9, 0xc9, 0xe0, 0xc0, 0xa9,
               0xa2, 0xa0, 0x1d, 0x19, 0x3d, 0x39, 0x5d, 0x59, 0x7d, 0x79,
               0xfd, 0xf9, 0xdd, 0xd9, 0xde, 0xfe, 0xbd, 0xb9, 0x9d, 0x99,
               0xbe, 0xbc]);
}
