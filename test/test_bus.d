import test.base, test.cpu;


void main()
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
