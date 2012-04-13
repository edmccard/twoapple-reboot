/+
 + cpu/d6502.d
 +
 + Copyright: 2012 Ed McCardell, 2007 Gerald Stocker
 +
 + This file is part of twoapple-reboot.
 +
 + twoapple-reboot is free software; you can redistribute it and/or modify
 + it under the terms of the GNU General Public License as published by
 + the Free Software Foundation; either version 2 of the License, or
 + (at your option) any later version.
 +
 + twoapple-reboot is distributed in the hope that it will be useful,
 + but WITHOUT ANY WARRANTY; without even the implied warranty of
 + MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 + GNU General Public License for more details.
 +
 + You should have received a copy of the GNU General Public License
 + along with twoapple-reboot; if not, write to the Free Software
 + Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 +/


module cpu.d6502;


import std.array, std.format;

import cpu.ctfe_d6502;


template is6502(T)
{
    enum is6502 = __traits(getMember, T, "_chip") == "6502";
}

template is65C02(T)
{
    enum is65C02 = __traits(getMember, T, "_chip") == "65C02";
}


final class Cpu(string chip)
{
    static assert(chip == "6502" || chip == "65C02" || chip == "65c02");
    enum _isCpu = true;
    enum _chip = (chip == "6502" ? "6502" : "65C02");

    struct _Mem
    {
        // Reads a value from system memory.
        ubyte delegate(ushort addr) read;

        // Writes a value to system memory.
        void delegate(ushort addr, ubyte val) write;
    }
    _Mem memory;

    struct _Clock
    {
        version(Cumulative)
            /*
             * Updates the number of cycles executed. Called just
             * prior to the final read/write action of each opcode.
             */
            void delegate(int cycles) tick;
        else
            /*
             * Increments the number of cycles executed. Called prior
             * to each read/write action.
             */
            void delegate() tick;
    }
    _Clock clock;

    ubyte A, X, Y, S;
    ushort PC;

    // The status flags.
    ubyte N, Z;
    bool V, D, I, C;

    static if (opArray) { mixin(OpArrayDef()); }
    version(OpFunctions) {}
    else
    {
        version(Cumulative) { int cycles; }
        ushort address, base;
        ubyte data;
    }

    // TODO: other methods for stopping cpu
    bool keepRunning;

    this()
    {
        static if (opArray) mixin(OpArrayInit());
    }

    final void statusFromByte(ubyte p)
    {
        N = p;
        V = ((p & 0x40) != 0);
        D = ((p & 0x08) != 0);
        I = ((p & 0x04) != 0);
        Z = ((p & 0x02) ? 0 : 1);
        C = ((p & 0x01) != 0);
    }

    final ubyte statusToByte()
    {
        return (C ? 0x01 : 0) |
               ((Z == 0) ? 0x02 : 0) |
               (I ? 0x04 : 0) |
               (D ? 0x08 : 0) |
               0x30 | // break and reserved both set
               (V ? 0x40 : 0) |
               (N & 0x80);
    }

    final void run(bool continuous)
    {
        keepRunning = continuous;
        // TODO debugging info?
        ubyte opcode;
        static if (!opArray)
        {
            version(Cumulative) { int cycles; }
            ushort address, base;
            ubyte data;
        }
        do {
            version(Cumulative)
            {
                static if (!opArray) cycles = 1;
            }
            else
            {
                clock.tick();
            }
            // XXX check signals, NMI/IRQ delays, etc.
            opcode = memory.read(PC++);
            mixin(OpExecute(_chip));
        } while (keepRunning);
    }

    version(OpDelegates) mixin (OpBodies(_chip));
}


enum ushort IRQ_VECTOR = 0xFFFE;


private:

version(OpFunctions) mixin(OpBodies("6502"));
version(OpFunctions) mixin(OpBodies("65C02"));


//alias Cpu!("6502", false, false) T1;
//alias Cpu!("6502", false, true) T2;
//alias Cpu!("6502", true, false) T3;
//alias Cpu!("6502", true, true) T4;
//alias Cpu!("65C02", false, false) T5;
//alias Cpu!("65C02", false, true) T6;
//alias Cpu!("65C02", true, false) T7;
//alias Cpu!("65C02", true, true) T8;

/+
void main()
{
    import std.stdio;
    writeln(OpBody(0x11, "6502", true, false));
}
+/
