/+
 + d6502/nmosbase.d
 +
 + Copyright: 2007 Gerald Stocker
 +
 + This file is part of Twoapple.
 +
 + Twoapple is free software; you can redistribute it and/or modify
 + it under the terms of the GNU General Public License as published by
 + the Free Software Foundation; either version 2 of the License, or
 + (at your option) any later version.
 +
 + Twoapple is distributed in the hope that it will be useful,
 + but WITHOUT ANY WARRANTY; without even the implied warranty of
 + MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 + GNU General Public License for more details.
 +
 + You should have received a copy of the GNU General Public License
 + along with Twoapple; if not, write to the Free Software
 + Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 +/

import d6502.cpu;

class NmosBase : Cpu
{
    this()
    {
        super();
        spuriousAddress = &badAddress;
    }

    static string RMW(string action)
    {
        return "poke(primaryAddress, (readVal = read(primaryAddress)));\n" ~
            "writeFinal(primaryAddress, flag.zero_ = flag.negative_ = " ~
            action ~ "(readVal));\n";
    }

    mixin(Opcode(mixin(Type2Address(
        "ASL", "Write", [0x06, 0x0E, 0x16, 0x1E])),
        RMW("shiftLeft")));
    mixin(Opcode(mixin(Type2Address(
        "LSR", "Write", [0x46, 0x4E, 0x56, 0x5E])),
        RMW("shiftRight")));
    mixin(Opcode(mixin(Type2Address(
        "ROL", "Write", [0x26, 0x2E, 0x36, 0x3E])),
        RMW("rotateLeft")));
    mixin(Opcode(mixin(Type2Address(
        "ROR", "Write", [0x66, 0x6E, 0x76, 0x7E])),
        RMW("rotateRight")));
    mixin(Opcode(mixin(Type2Address(
        "INC", "Write", [0xE6, 0xEE, 0xF6, 0xFE])),
        RMW("increment")));
    mixin(Opcode(mixin(Type2Address(
        "DEC", "Write", [0xC6, 0xCE, 0xD6, 0xDE])),
        RMW("decrement")));

    /* JMP ($$$$) */
    override void opcode6C()
    {
        ushort vector = readWordOperand();
        programCounter = readWord(vector,
                (vector & 0xFF00) | cast(ubyte)(vector + 1));
        version(CumulativeCycles) ticks(totalCycles);
    }
}
