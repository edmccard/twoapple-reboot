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
               0xbe, 0xbc, 0x6c, 0x7c, 0xb2, 0x72, 0x32, 0xd2, 0x52, 0x12,
               0xf2, 0x92, 0xaa, 0x8a, 0xa8, 0x98, 0xba, 0x9a, 0x0a, 0x0e,
               0x1e, 0x48, 0x2c, 0x05, 0x25, 0x45, 0x65, 0xe5, 0xc5, 0xe4,
               0xc4, 0xc6, 0xe6, 0x06, 0x26, 0x46, 0x66, 0xa5, 0x85, 0xa6,
               0x86, 0xa4, 0x84, 0x24, 0x15, 0x35, 0x55, 0x75, 0xf5, 0xd5,
               0xd6, 0xf6, 0x16, 0x36, 0x56, 0x76, 0xb5, 0x95, 0xb6, 0x96,
               0xb4, 0x94, 0x01, 0x21, 0x41, 0x61, 0xe1, 0xc1, 0xa1, 0x81,
               0x11, 0x31, 0x51, 0x71, 0xf1, 0xd1, 0xb1, 0x91, 0xda, 0x5a,
               0x7a, 0xfa, 0x89, 0x34, 0x3c, 0x1a, 0x3a, 0x80, 0x64, 0x74,
               0x14, 0x1c, 0x04, 0x0c, 0x40]);
}
