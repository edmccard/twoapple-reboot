/+
 + iomem.d
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

import memory;
import timer;

import system.peripheral;
import peripheral.base;
import device.base;

import std.string;

class IOMem
{
    // NOTE: It is implied that a peripheral slot with
    // an I/O STROBE ROM' always responds to I/O STROBE'.
    class IOSelectMem : Rom
    {
        int slotNum;

        this(int slotNum_, ubyte[] rom)
        {
            super(0xC000 + (slotNum_ * 0x100), 0x0100, rom);
            slotNum = slotNum_;
        }

        ubyte read(ushort addr)
        {
            activateStrobeMem(slotNum);

            return data[addr - baseAddress];
        }

        void write(ushort addr, ubyte val)
        {
            activateStrobeMem(slotNum);
        }
    }

    // NOTE: It is implied that all peripherals obey the
    // $CFFF I/O STROBE' protocol.
    class IOStrobeMem : Rom
    {
        int slotNum;    // XXX not just num, but a reference to the
                        //     rom object for that slot (for debug
                        //     display).

        this(int slotNum_, ubyte[] rom)
        {
            super(0xC800, 0x0800, rom);
            slotNum = slotNum_;
        }

        ubyte read(ushort addr)
        {
            if (addr == 0xCFFF) deactivateStrobeMem();

            return data[addr - 0xC800];
        }

        void write(ushort addr)
        {
            if (addr == 0xCFFF) deactivateStrobeMem();
        }
    }

    int strobeSlotNum;
    IOSelectMem[8] selectMem;
    IOStrobeMem[8] strobeMem;
    AddressDecoder decoder;

    void initialize(AddressDecoder decoder_, SoftSwitchPage switches,
            Timer timer, Peripherals peripherals)
    {
        decoder = decoder_;
        Peripheral card;
        for (int slot = 0; slot <=7; ++slot)
        {
            card = peripherals.cards[slot];
            if (slot > 0)
            {
                if ((card is null) || (card.ioSelectROM is null))
                {
                    installEmptySelect(slot);
                }
                else
                {
                    selectMem[slot] = new IOSelectMem(slot, card.ioSelectROM);
                    selectMem[slot].debugName =
                        "Slot " ~ std.string.toString(slot) ~ " ROM";
                    decoder.install(selectMem[slot]);
                    if (card.ioStrobeROM !is null)
                    {
                        strobeMem[slot] = new IOStrobeMem(slot,
                                card.ioStrobeROM);
                        strobeMem[slot].debugName = selectMem[slot].debugName;
                    }
                }
            }
            if (card !is null) card.plugIn(slot, switches, timer);
        }
    }

    void reboot()
    {
        deactivateStrobeMem();
    }

    void installEmptySelect(int slotNum)
    {
        // NOTE: using these read/write delegates implies that
        // a slot without an I/O SELECT' ROM _cannot_ have an
        // I/O STROBE' ROM.
        decoder.installNull(0xC000 + (slotNum * 0x100), 0x100);
    }

    void activateStrobeMem(int slotNum)
    {
        // Do nothing if the I/O STROBE' memory for
        // the given slotNum is already active.
        if (strobeSlotNum == slotNum) return;

        if (strobeMem[slotNum] is null)
        {
            deactivateStrobeMem();
        }
        else
        {
            decoder.install(strobeMem[slotNum]);
            strobeSlotNum = slotNum;
        }
    }

    void deactivateStrobeMem()
    {
        decoder.installNull(0xC800, 0x0800);
        strobeSlotNum = 0;
    }

}

class IOMem_IIe : IOMem
{
    class IntC3ROM : Rom
    {
        this(ubyte[] rom)
        {
            super(0xC300, 0x0100, rom);
        }

        ubyte read(ushort addr)
        {
            activateIntStrobeMem();
            return data[addr - 0xC300];
        }

        void write(ushort addr, ubyte val)
        {
            activateIntStrobeMem();
        }
    }

    bool intC8ROM, slotC3ROM, intCXROM;
    IOStrobeMem intStrobeMem;
    IntC3ROM intC3ROM;
    Rom c100c2ff, c400c7ff;

    ubyte delegate() kbdLatch;

    void reboot()
    {
        super.reboot();
        resetIntCXROM();
        resetSlotC3ROM();
    }

    void reset()
    {
        deactivateStrobeMem(); 
        resetIntCXROM();
        resetSlotC3ROM();
    }

    void setSlotC3ROM()
    {
        if (slotC3ROM) return;
        slotC3ROM = true;

        // $C3XX cannot be configured for slot response if
        // INTCXROM is set.
        if (intCXROM) return;
        
        if (selectMem[3] !is null)
        {
            decoder.install(selectMem[3]);
        }
        else
        {
            installEmptySelect(3);
        }
    }

    void resetSlotC3ROM()
    {
        slotC3ROM = false;
        decoder.install(intC3ROM);
    }

    void setIntCXROM()
    {
        if (intCXROM) return;
        intCXROM = true;
        decoder.install(c100c2ff);
        decoder.install(intC3ROM);
        decoder.install(c400c7ff);
        decoder.install(intStrobeMem);
    }

    void resetIntCXROM()
    {
        intCXROM = false;
        for (int s = 1; s <= 7; ++s)
        {
            if (selectMem[s] !is null)
            {
                if ((s != 3) || (slotC3ROM)) decoder.install(selectMem[s]);
            }
            else
            {
                if ((s != 3) || (slotC3ROM)) installEmptySelect(s);
            }
        }
        if (!intC8ROM) deactivateStrobeMem();
    }

    void activateIntStrobeMem()
    {
        if (intC8ROM) return;

        decoder.install(intStrobeMem);
        strobeSlotNum = -1; // XXX hack (-1 represents internal?)
        intC8ROM = true;
    }

    void activateStrobeMem(int slotNum)
    {
        if (intC8ROM) return;

        super.activateStrobeMem(slotNum);
    }

    void deactivateStrobeMem()
    {
        intC8ROM = false;
        super.deactivateStrobeMem();
    }

    ubyte readIntCXROM()
    {
        return kbdLatch() | (intCXROM ? 0x80 : 0x00);
    }

    ubyte readSlotC3ROM()
    {
        return kbdLatch() | (slotC3ROM ? 0x80 : 0x00);
    }

    mixin(InitSwitches("", [
        mixin(MakeSwitch([0xC006], "W", "resetIntCXROM")),
        mixin(MakeSwitch([0xC007], "W", "setIntCXROM")),
        mixin(MakeSwitch([0xC00A], "W", "resetSlotC3ROM")),
        mixin(MakeSwitch([0xC00B], "W", "setSlotC3ROM")),
        mixin(MakeSwitch([0xC015], "R", "readIntCXROM")),
        mixin(MakeSwitch([0xC017], "R", "readSlotC3ROM"))
    ]));

    void setRom(ubyte[] romDump)
    {
        int c100 = romDump.length - 16128;
        c100c2ff = new Rom(0xC100, 0x0200, romDump[c100 .. (c100 + 0x0200)]);
        intC3ROM = new IntC3ROM(romDump[(c100 + 0x0200) .. (c100 + 0x0300)]);
        c400c7ff = new Rom(0xC400, 0x0400,
                romDump[(c100 + 0x0300) .. (c100 + 0x0700)]);
        // XXX not slot, but ref to intc3rom
        intStrobeMem = new IOStrobeMem(3,
                romDump[(c100 + 0x0700) .. (c100 + 0x0F00)]);
        c100c2ff.debugName = intC3ROM.debugName = c400c7ff.debugName =
            intStrobeMem.debugName = "Internal ROM";
    }
}

