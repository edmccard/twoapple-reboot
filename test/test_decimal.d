module test.test_decimal;


import std.stdio;

import test.base, test.cpu;


void testDecimalMode(T)()
if (isCpu!T)
{
    auto mem = TestMemory(Block(0x8000, cast(ubyte[])
    /* 8000         JMP TEST    */ x"4C 14 80"
    /* 8003 ERROR   DB  0       */ x"00"
    /* 8004 N1      DB  0       */ x"00"
    /* 8005 N2      DB  0       */ x"00"
    /* 8006 N1H     DB  0       */ x"00"
    /* 8007 N1L     DB  0       */ x"00"
    /* 8008 N2H     DW  0       */ x"0000"
    /* 800A N2L     DB  0       */ x"00"
    /* 800B DA      DB  0       */ x"00"
    /* 800C DNVZC   DB  0       */ x"00"
    /* 800D HA      DB  0       */ x"00"
    /* 800E HNVZC   DB  0       */ x"00"
    /* 800F AR      DB  0       */ x"00"
    /* 8010 NF      DB  0       */ x"00"
    /* 8011 VF      DB  0       */ x"00"
    /* 8012 ZF      DB  0       */ x"00"
    /* 8013 CF      DB  0       */ x"00"
    /* 8014 TEST    LDY #1      */ x"A0 01"
    /* 8016         STY ERROR   */ x"8C 03 80"
    /* 8019         LDA #0      */ x"A9 00"
    /* 801B         STA N1      */ x"8D 04 80"
    /* 801E         STA N2      */ x"8D 05 80"
    /* 8021 LOOP1   LDA N2      */ x"AD 05 80"
    /* 8024         AND #$0F    */ x"29 0F"
    /* 8026         STA N2L     */ x"8D 0A 80"
    /* 8029         LDA N2      */ x"AD 05 80"
    /* 802C         AND #$F0    */ x"29 F0"
    /* 802E         STA N2H     */ x"8D 08 80"
    /* 8031         ORA #$0F    */ x"09 0F"
    /* 8033         STA N2H+1   */ x"8D 09 80"
    /* 8036 LOOP2   LDA N1      */ x"AD 04 80"
    /* 8039         AND #$0F    */ x"29 0F"
    /* 803B         STA N1L     */ x"8D 07 80"
    /* 803E         LDA N1      */ x"AD 04 80"
    /* 8041         AND #$F0    */ x"29 F0"
    /* 8043         STA N1H     */ x"8D 06 80"
    /* 8045         JSR ADD     */ x"20 6F 80"
    /* 8049         JSR A6502   */ x"20 58 81"
    /* 804C         JSR COMPARE */ x"20 29 81"
    /* 804F         BNE DONE    */ x"D0 1D"
    /* 8051         JSR SUB     */ x"20 C2 80"
    /* 8054         JSR S6502   */ x"20 65 81"
    /* 8057         JSR COMPARE */ x"20 29 81"
    /* 805A         BNE DONE    */ x"D0 12"
    /* 805C         INC N1      */ x"EE 04 80"
    /* 805F         BNE LOOP2   */ x"D0 D5"
    /* 8061         INC N2      */ x"EE 05 80"
    /* 8064         BNE LOOP1   */ x"D0 BB"
    /* 8066         DEY         */ x"88"
    /* 8067         BPL LOOP1   */ x"10 B8"
    /* 8069         LDA #0      */ x"A9 00"
    /* 806B         STA ERROR   */ x"8D 03 80"
    /* 806E DONE    BRK         */ x"00"
    /* 806F ADD     SED         */ x"F8"
    /* 8070         CPY #1      */ x"C0 01"
    /* 8072         LDA N1      */ x"AD 04 80"
    /* 8075         ADC N2      */ x"6D 05 80"
    /* 8078         STA DA      */ x"8D 0B 80"
    /* 807B         PHP         */ x"08"
    /* 807C         PLA         */ x"68"
    /* 807D         STA DNVZC   */ x"8D 0C 80"
    /* 8080         CLD         */ x"D8"
    /* 8081         CPY #1      */ x"C0 01"
    /* 8083         LDA N1      */ x"AD 04 80"
    /* 8086         ADC N2      */ x"6D 05 80"
    /* 8089         STA HA      */ x"8D 0D 80"
    /* 808C         PHP         */ x"08"
    /* 808D         PLA         */ x"68"
    /* 808E         STA HNVZC   */ x"8D 0E 80"
    /* 8091         CPY #1      */ x"C0 01"
    /* 8093         LDA N1L     */ x"AD 07 80"
    /* 8096         ADC N2L     */ x"6D 0A 80"
    /* 8099         CMP #$0A    */ x"C9 0A"
    /* 809B         LDX #0      */ x"A2 00"
    /* 809D         BCC A1      */ x"90 06"
    /* 809F         INX         */ x"E8"
    /* 80A0         ADC #5      */ x"69 05"
    /* 80A2         AND #$0F    */ x"29 0F"
    /* 80A4         SEC         */ x"38"
    /* 80A5 A1      ORA N1H     */ x"0D 06 80"
    /* 80A8         ADC N2H,X   */ x"7D 08 80"
    /* 80AB         PHP         */ x"08"
    /* 80AC         BCS A2      */ x"B0 04"
    /* 80AE         CMP #$A0    */ x"C9 A0"
    /* 80B0         BCC A3      */ x"90 03"
    /* 80B2 A2      ADC #$5F    */ x"69 5F"
    /* 80B4         SEC         */ x"38"
    /* 80B5 A3      STA AR      */ x"8D 0F 80"
    /* 80B8         PHP         */ x"08"
    /* 80B9         PLA         */ x"68"
    /* 80BA         STA CF      */ x"8D 13 80"
    /* 80BD         PLA         */ x"68"
    /* 80BE         STA VF      */ x"8D 11 80"
    /* 80C1         RTS         */ x"60"
    /* 80C2 SUB     SED         */ x"F8"
    /* 80C3         CPY #1      */ x"C0 01"
    /* 80C5         LDA N1      */ x"AD 04 80"
    /* 80C8         SBC N2      */ x"ED 05 80"
    /* 80CB         STA DA      */ x"8D 0B 80"
    /* 80CE         PHP         */ x"08"
    /* 80CF         PLA         */ x"68"
    /* 80D0         STA DNVZC   */ x"8D 0C 80"
    /* 80D3         CLD         */ x"D8"
    /* 80D4         CPY #1      */ x"C0 01"
    /* 80D6         LDA N1      */ x"AD 04 80"
    /* 80D9         SBC N2      */ x"ED 05 80"
    /* 80DC         STA HA      */ x"8D 0D 80"
    /* 80DF         PHP         */ x"08"
    /* 80E0         PLA         */ x"68"
    /* 80E1         STA HNVZC   */ x"8D 0E 80"
    /* 80E4         RTS         */ x"60"
    /* 80E5 SUB1    CPY #1      */ x"C0 01"
    /* 80E7         LDA N1L     */ x"AD 07 80"
    /* 80EA         SBC N2L     */ x"ED 0A 80"
    /* 80ED         LDX #0      */ x"A2 00"
    /* 80EF         BCS S11     */ x"B0 06"
    /* 80F1         INX         */ x"E8"
    /* 80F2         SBC #5      */ x"E9 05"
    /* 80F4         AND #$0F    */ x"29 0F"
    /* 80F6         CLC         */ x"18"
    /* 80F7 S11     ORA N1H     */ x"0D 06 80"
    /* 80FA         SBC N2H,X   */ x"FD 08 80"
    /* 80FD         BCS S12     */ x"B0 02"
    /* 80FF         SBC #$5F    */ x"E9 5F"
    /* 8101 S12     STA AR      */ x"8D 0F 80"
    /* 8104         RTS         */ x"60"
    /* 8105 SUB2    CPY #1      */ x"C0 01"
    /* 8107         LDA N1L     */ x"AD 07 80"
    /* 810A         SBC N2L     */ x"ED 0A 80"
    /* 810D         LDX #0      */ x"A2 00"
    /* 810F         BCS S21     */ x"B0 04"
    /* 8111         INX         */ x"E8"
    /* 8112         AND #$0F    */ x"29 0F"
    /* 8114         CLC         */ x"18"
    /* 8115 S21     ORA N1H     */ x"0D 06 80"
    /* 8118         SBC N2H,X   */ x"FD 08 80"
    /* 811B         BCS S22     */ x"B0 02"
    /* 811D         SBC #$5F    */ x"E9 5F"
    /* 811F S22     CPX #0      */ x"E0 00"
    /* 8121         BEQ S23     */ x"F0 02"
    /* 8123         SBC #6      */ x"E9 06"
    /* 8125 S23     STA AR      */ x"8D 0F 80"
    /* 8128         RTS         */ x"60"
    /* 8129 COMPARE LDA DA      */ x"AD 0B 80"
    /* 812C         CMP AR      */ x"CD 0F 80"
    /* 812F         BNE C1      */ x"D0 26"
    /* 8131         LDA DNVZC   */ x"AD 0C 80"
    /* 8134         EOR NF      */ x"4D 10 80"
    /* 8137         AND #$80    */ x"29 80"
    /* 8139         BNE C1      */ x"D0 1C"
    /* 813B         LDA DNVZC   */ x"AD 0C 80"
    /* 813E         EOR VF      */ x"4D 11 80"
    /* 8141         AND #$40    */ x"29 40"
    /* 8143         BNE C1      */ x"D0 12"
    /* 8145         LDA DNVZC   */ x"AD 0C 80"
    /* 8148         EOR ZF      */ x"4D 12 80"
    /* 814B         AND #2      */ x"29 02"
    /* 814D         BNE C1      */ x"D0 08"
    /* 814F         LDA DNVZC   */ x"AD 0C 80"
    /* 8152         EOR CF      */ x"4D 13 80"
    /* 8155         AND #1      */ x"29 01"
    /* 8157 C1      RTS         */ x"60"
    /* 8158 A6502   LDA VF      */ x"AD 11 80"
    /* 815B         STA NF      */ x"8D 10 80"
    /* 815E         LDA HNVZC   */ x"AD 0E 80"
    /* 8161         STA ZF      */ x"8D 12 80"
    /* 8164         RTS         */ x"60"
    /* 8165 S6502   JSR SUB1    */ x"20 E5 80"
    /* 8168         LDA HNVZC   */ x"AD 0E 80"
    /* 816B         STA NF      */ x"8D 10 80"
    /* 816E         STA VF      */ x"8D 11 80"
    /* 8171         STA ZF      */ x"8D 12 80"
    /* 8174         STA CF      */ x"8D 13 80"
    /* 8177         RTS         */ x"60"
    /* 8178 A65C02  LDA AR      */ x"AD 0F 80"
    /* 817B         PHP         */ x"08"
    /* 817C         PLA         */ x"68"
    /* 817D         STA NF      */ x"8D 10 80"
    /* 8180         STA ZF      */ x"8D 12 80"
    /* 8183         RTS         */ x"60"
    /* 8184 S65C02  JSR SUB2    */ x"20 05 81"
    /* 8187         LDA AR      */ x"AD 0F 80"
    /* 818A         PHP         */ x"08"
    /* 818B         PLA         */ x"68"
    /* 818C         STA NF      */ x"8D 10 80"
    /* 818F         STA ZF      */ x"8D 12 80"
    /* 8192         LDA HNVZC   */ x"AD 0E 80"
    /* 8195         STA VF      */ x"8D 11 80"
    /* 8198         STA CF      */ x"8D 13 80"
    /* 819B         RTS         */ x"60"
    ));

    // Patch the JSRs at $804A/$8055
    static if (isNMOS!T)
    {
        mem.write(0x804A, 0x58);
        mem.write(0x8055, 0x65);
    }
    else
    {
        mem.write(0x804A, 0x78);
        mem.write(0x8055, 0x84);
    }

    auto cpu = new T();
    connectMem(cpu, mem);
    setPC(cpu, 0x8000);
    runUntilBRK(cpu);
    if (mem[0x8003])
    {
        // TODO: check data block to find out what failed exactly
        throw new TestException("failed decimal mode " ~ T.stringof);
    }
}


version(Benchmark)
{
    import std.datetime, std.stdio;
    void f0()
    {
        testDecimalMode!(CPU!("65C02"))();
    }

    void main()
    {
    //    auto milliExpected = (61886766.0 / 1020484.0) * 1000;
        auto milliExpected = (64508206.0 / 1020484.0) * 1000;
        auto r = benchmark!(f0)(1);
        writeln(milliExpected / r[0].to!("msecs", int));
    }
}
else
{
    void main()
    {
        writeln("Testing decimal mode, 6502");
        testDecimalMode!(CPU!("6502"))();

        writeln("Testing decimal mode, 65C02");
        testDecimalMode!(CPU!("65C02"))();
    }
}
