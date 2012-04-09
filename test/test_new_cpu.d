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

    void test_func(ubyte op)
    {
        auto report = report_debug();
        auto report2 = report_timing_debug();

        version(OpFunctions) writeln("(Functions)");
        version(OpDelegates) writeln("(Delegates)");
        version(OpSwitch) writeln("(Switch)");
        version(OpNestedSwitch) writeln("(NestedSwitch)");

        alias Cpu!("6502", s1, c1) TX1;
        writeln("NMOS ", s1, " ", c1, " func");
        test_one_opcode!TX1(op, report);
        writeln("NMOS ", s1, " ", c1, " bus");
        test_opcode_timing!TX1(op, report2);

        alias Cpu!("65C02", s1, c1) TX2;
        writeln("CMOS ", s1, " ", c1, " func");
        test_one_opcode!TX2(op, report);
        writeln("CMOS ", s1, " ", c1, " bus");
        test_opcode_timing!TX2(op, report2);
    }

    test_func(0x00);
}
