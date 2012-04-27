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


final class Signals
{
private:
    bool active;
    bool resetLow, nmiLow, irqLow;

    final void updateSignals()
    {
        active = resetLow || nmiLow || irqLow;
    }

public:
    final void triggerReset()
    {
        resetLow = true;
        updateSignals();
    }

    final void triggerNMI()
    {
        nmiLow = true;
        updateSignals();
    }

    final void assertIRQ()
    {
        irqLow = true;
        updateSignals();
    }

    final void deassertIRQ()
    {
        irqLow = false;
        updateSignals();
    }
}


final class Cpu(string chip, MEM, CLK)
if (__traits(compiles, {
    MEM m; ubyte val; ushort addr;
    val = m[addr];
    m[addr] = val;
    CLK c; int cycles;
    version(Cumulative) c.tick(cycles);
    else c.tick();
}))
{
    static assert(chip == "6502" || chip == "65C02" || chip == "65c02");
    enum _isCpu = true;
    enum _chip = (chip == "6502" ? "6502" : "65C02");

    MEM memory;
    CLK clock;

    ubyte A, X, Y, S;
    ushort PC;

    // The status flags.
    ubyte N, Z;
    bool V, D, I, C;

    bool keepRunning;
    Signals signals;

    static if (_chip == "6502")
    {
        // To handle NMI/IRQ delay after 3-cycle branch, and after CLI/PLP.
        private bool ndelay, idelay, delay_handled;
    }

    version(Cumulative) { private int cycles; }

    version(OpDelegates)
    {
        mixin(OpArrayDef());
        ushort address, base;
        ubyte data;
    }

    this(MEM memory, CLK clock)
    {
        this.memory = memory;
        this.clock = clock;
        signals = new Signals();

        version(OpDelegates) mixin(OpArrayInit());
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
        ubyte opcode;
        static if (!opArray)
        {
            ushort address, base;
            ubyte data;
        }
        do
        {
            version(Cumulative) { cycles = 0; }
            if (signals.active) handleSignals();
            static if (_chip == "6502") { idelay = ndelay = false; }
            version(Cumulative) { cycles = 1; }
            else { clock.tick(); }
            opcode = memory[PC++];
            mixin(OpExecute(_chip));
        } while (keepRunning);
    }

    // TODO: irq/nmi
    void handleSignals()
    {
        if (signals.resetLow) { doReset(); return; }

        static if (_chip == "6502")
        {
            // Handle the case where NMI/IRQ are delayed for one
            // instruction after a 3-cycle branch opcode, a CLI, or a PLP.
            if (!delay_handled && (ndelay || (idelay && !signals.nmiLow)))
            {
                delay_handled = true;
                return;
            }
        }
        if (signals.nmiLow)
            doNMI();
        else if (signals.irqLow && !I)
            doIRQ();

        static if (_chip == "6502") { delay_handled = false; }
    }

    void doReset()
    {
        mixin(Peek("PC") ~ Peek("PC") ~
              Peek(STACK) ~ DecSP() ~
              Peek(STACK) ~ DecSP() ~
              Peek(STACK) ~ DecSP());

        I = true;
        static if (_chip == "65C02") { D = false; }
        signals.resetLow = false;
        signals.updateSignals();

        mixin(ReadWord(_PC, "RESET_VECTOR") ~
              Done());
    }

    void doNMI()
    {
        mixin(Peek("PC") ~ Peek("PC") ~
              PushPC() ~
              Push("statusToByte() & ~0x10"));

        I = true;
        static if (_chip == "65C02") { D = false; }
        signals.nmiLow = false;
        signals.updateSignals();

        mixin(ReadWord(_PC, "NMI_VECTOR") ~
              Done());
    }

    void doIRQ()
    {
        mixin(Peek("PC") ~ Peek("PC") ~
              PushPC() ~
              Push("statusToByte() & ~0x10"));

        I = true;
        static if (_chip == "65C02") { D = false; }

        mixin(ReadWord(_PC, "IRQ_VECTOR") ~
              Done());
    }

    version(OpDelegates) mixin (OpMethods(_chip));
}


enum ushort IRQ_VECTOR = 0xFFFE;
enum ushort RESET_VECTOR = 0xFFFC;
enum ushort NMI_VECTOR = 0xFFFA;


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
