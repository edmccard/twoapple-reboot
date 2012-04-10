import test.base, test.cpu;


void main()
{
    auto report = report_debug();

    alias CPU!("65C02", false, false) T1;
    foreach (opcode; 0..255)
        test_one_opcode!T1(cast(ubyte)opcode, report);

    alias CPU!("6502", false, false) T2;
    foreach (opcode; 0..255)
        test_one_opcode!T2(cast(ubyte)opcode, report);
}
