module test.opcodes;


import test.cpu;


// 2-cycle opcodes which neither read nor write.
template REG_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum REG_OPS = cast(ubyte[])
            x"0A 18 1A 2A 38 3A 4A 58 5A 6A 78 7A 8A 88 98 9A
              A8 AA B8 BA C8 CA D8 DA E8 EA F8 FA";
    else
        enum REG_OPS = cast(ubyte[])
            x"0A 18 1A 2A 38 3A 4A 58 6A 78 8A 88 98 9A
              A8 AA B8 BA C8 CA D8 E8 EA F8";
}


// Opcodes which push to the stack.
template PUSH_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum PUSH_OPS = cast(ubyte[])x"08 48";
    else
        enum PUSH_OPS = cast(ubyte[])x"08 48 5A DA";
}


// Opcodes which pull from the stack.
template PULL_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum PULL_OPS = cast(ubyte[])x"28 68";
    else
        enum PULL_OPS = cast(ubyte[])x"28 68 7A FA";
}


// Relative branch opcodes.
template BRANCH_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum BRANCH_OPS = cast(ubyte[])x"10 30 50 70    90 B0 D0 F0";
    else
        enum BRANCH_OPS = cast(ubyte[])x"10 30 50 70 80 90 B0 D0 F0";
}


// Write-only opcodes.
template WRITE_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum WRITE_OPS = cast(ubyte[])x"81 83 84 85 86 87       8C 8D 8E 8F
                                        91 93 94 95 96 97 99 9B 9C 9D 9E 9F";
    else
        enum WRITE_OPS = cast(ubyte[])x"64 74 81 84 85 86 8C 8D 8E
                                        91 92 94 95 96 99 9C 9D 9E";
}


// Read-only opcodes (excluding ADC/SBC).
template READ_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum READ_OPS = cast(ubyte[])
            x"01 04 05 09 0B 0C 0D 11 14 15 19 1C 1D
              21 24 25 29 2B 2C 2D 31 34 35 39 3C 3D
              41 44 45 49 4B 4D 51 54 55 59 5C 5D
              64 6B 74 7C 82 89 8B
              A0 A1 A2 A3 A4 A5 A6 A7 A9 AB AC AD AE AF
              B1 B3 B4 B5 B6 B7 B9 BB BC BD BE BF
              C0 C1 C2 C4 C5 C9 CB CC CD D1 D4 D5 D9 DC DD
              E0 E2 E4 EC F4 FC";
    else
        enum READ_OPS = cast(ubyte[])
            x"01 02 05 09 0D 11 12 15 19 1D
              21 22 24 25 29 2C 2D 31 32 34 35 39 3C 3D
              41 42 44 45 49 4D 51 52 54 55 59 5D 62 82 89
              A0 A1 A2 A4 A5 A6 A9 AC AD AE
              B2 B1 B4 B5 B6 B9 BC BD BE
              C0 C1 C2 C4 C5 C9 CC CD D1 D2 D4 D5 D9 DC DD
              E0 E2 E4 EC F4 FC";
}


// Opcodes affected by decimal mode (ADC/SBC).
template BCD_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum BCD_OPS = cast(ubyte[])x"61 65 69 6B 6D 71 75 79 7D
                                      E1 E5 E9 EB ED F1 F5 F9 FD";
    else
        enum BCD_OPS = cast(ubyte[])x"61 65 69 6D 71 72 75 79 7D
                                      E1 E5 E9 ED F1 F2 F5 F9 FD";
}


// Opcodes which both read and write.
template RMW_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum RMW_OPS = cast(ubyte[])
            x"03 06 07 0E 0F 13 16 17 1B 1E 1F
              23 26 27 2E 2F 33 36 37 3B 3E 3F
              43 46 47 4E 4F 53 56 57 5B 5E 5F
              63 66 67 6E 6F 73 76 77 7B 7E 7F
              C3 C6 C7 CE CF D3 D6 D7 DB DE DF
              E3 E6 E7 EE EF F3 F6 F7 FB FE FF";
    else
        enum RMW_OPS = cast(ubyte[])
            x"04 06 0C 0E 14 16 1C 1E 26 2E 36 3E 46 4E 56 5E
                 66    6E    76    7E C6 CE D6 DE E6 EE F6 FE";
}


// Opcodes with immediate address mode.
template IMM_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum IMM_OPS = cast(ubyte[])x"09 0B 29 2B 49 4B 69 6B
                                      80 82 89 8B A0 A2 A9 AB
                                      C0 C2 C9 CB E0 E2 E9 EB";
    else
        enum IMM_OPS = cast(ubyte[])x"02 09 22 29 42 49 62 69 82
                                      89 A0 A2 A9 C0 C2 C9 E0 E2 E9";
}


// Opcodes with zeropage address mode.
template ZPG_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ZPG_OPS = cast(ubyte[])x"04 05 06 07 24 25 26 27
                                      44 45 46 47 64 65 66 67
                                      84 85 86 87 A4 A5 A6 A7
                                      C4 C5 C6 C7 E4 E5 E6 E7";
    else
        enum ZPG_OPS = cast(ubyte[])x"04 05 06 14 24 25 26 44 45 46 64 65 66
                                      84 85 86 A4 A5 A6 C4 C5 C6 E4 E5 E6";
}


// Opcodes with zeropage,x address mode.
template ZPX_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ZPX_OPS = cast(ubyte[])x"14 15 16 17 34 35 36 37
                                      54 55 56 57 74 75 76 77
                                      94 95 B4 B5 D4 D5 D6 D7
                                      F4 F5 F6 F7";
    else
        enum ZPX_OPS = cast(ubyte[])x"15 16 34 35 36 54 55 56 74 75 76
                                      94 95 B4 B5 D4 D5 D6 F4 F5 F6";
}


// Opcodes with zeropage,y address mode.
template ZPY_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ZPY_OPS = cast(ubyte[])x"96 97 B6 B7";
    else
        enum ZPY_OPS = cast(ubyte[])x"96 B6";
}


// Opcodes with absolute address mode.
template ABS_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ABS_OPS = cast(ubyte[])x"0C 0D 0E 0F 2C 2D 2E 2F
                                      4C 4D 4E 4F    6D 6E 6F
                                      8C 8D 8E 8F AC AD AE AF
                                      CC CD CE CF EC ED EE EF";
    else
        enum ABS_OPS = cast(ubyte[])x"0C 0D 0E 1C 2C 2D 2E 4C 4D 4E    6D 6E
                                      8C 8D 8E 9C AC AD AE CC CD CE EC ED EE";
}


// Opcodes with absolute,x address mode.
template ABX_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ABX_OPS = cast(ubyte[])x"1C 1D 1E 1F 3C 3D 3E 3F
                                      5C 5D 5E 5F 7C 7D 7E 7F
                                      9C 9D BC BD DC DD DE DF
                                      FC FD FE FF";
    else
        enum ABX_OPS = cast(ubyte[])x"1D 1E 3C 3D 3E 5D 5E 7D 7E
                                      9D 9E BC BD DC DD DE FC FD FE";
}


// Opcodes with absolute,y address mode.
template ABY_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum ABY_OPS = cast(ubyte[])x"19 1B 39 3B 59 5B 79 7B
                                      99 9B 9E 9F B9 BB BE BF
                                      D9 DB F9 FB";
    else
        enum ABY_OPS = cast(ubyte[])x"19 39 59 79 99 B9 BE D9 F9";
}


// Opcodes with indirect zeropage,x address mode.
template IZX_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum IZX_OPS = cast(ubyte[])x"01 03 21 23 41 43 61 63
                                      81 83 A1 A3 C1 C3 E1 E3";
    else
        enum IZX_OPS = cast(ubyte[])x"01 21 41 61 81 A1 C1 E1";
}


// Opcodes with indirect zeropage,y address mode.
template IZY_OPS(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum IZY_OPS = cast(ubyte[])x"11 13 31 33 51 53 71 73
                                      91 93 B1 B3 D1 D3 F1 F3";
    else
        enum IZY_OPS = cast(ubyte[])x"11 31 51 71 91 B1 D1 F1";
}


// Opcodes with indirect zeropage address mode.
template ZPI_OPS(T)
if (isCpu!T && isCMOS!T)
{
    enum ZPI_OPS = cast(ubyte[])x"12 32 52 72 92 B2 D2 F2";
}


// 1-cycle NOPS.
template NOP1_OPS(T)
if (isCpu!T && isCMOS!T)
{
    enum NOP1_OPS = cast(ubyte[])
        x"03 13 23 33 43 53 63 73 83 93 A3 B3 C3 D3 E3 F3
          07 17 27 37 47 57 67 77 87 97 A7 B7 C7 D7 E7 F7
          0B 1B 2B 3B 4B 5B 6B 7B 8B 9B AB BB CB DB EB FB
          0F 1F 2F 3F 4F 5F 6F 7F 8F 9F AF BF CF DF EF FF";
}


// NMOS HLT opcodes.
template HLT_OPS(T)
if (isCpu!T && isNMOS!T)
{
    enum HLT_OPS = cast(ubyte[])x"02 12 22 32 42 52 62 72 92 B2 D2 F2";
}


// Opcodes which decrement a register.
template OPS_DEC_REG(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum OPS_DEC_REG = cast(ubyte[])x"88 CA";
    else
        enum OPS_DEC_REG = cast(ubyte[])x"3A 88 CA";
}


// Opcodes which increment a register.
template OPS_INC_REG(T)
if (isCpu!T)
{
    static if (isNMOS!T)
        enum OPS_INC_REG = cast(ubyte[])x"C8 E8";
    else
        enum OPS_INC_REG = cast(ubyte[])x"1A C8 E8";
}

// Opcodes which decrement a memory location.
template OPS_DEC(T)
if (isCpu!T)
{
    enum OPS_DEC = cast(ubyte[])x"C6 CE D6 DE";
}


// Opcodes which increment a memory location.
template OPS_INC(T)
if (isCpu!T)
{
    enum OPS_INC = cast(ubyte[])x"E6 EE F6 FE";
}


// Opcodes which rotate a value left.
template OPS_ROL(T)
if (isCpu!T)
{
    enum OPS_ROL = cast(ubyte[])x"26 2A 2E 36 3E";
}


// Opcodes which shift a value left.
template OPS_ASL(T)
if (isCpu!T)
{
    enum OPS_ASL = cast(ubyte[])x"06 0A 0E 16 1E";
}
