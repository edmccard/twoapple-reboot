/+
 + ioummu.d
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
import device.base;
import system.io;   // XXX XXX too many dependencies?
import video.base;
import peripheral.langcard;
import iomem;

struct MemMap
{
    Memory X0000_01FF;
    Memory X0200_03FF;
    Memory X0400_07FF;
    Memory X0800_1FFF;
    Memory X2000_3FFF;
    Memory X4000_BFFF;

    void reboot()
    {
        X0000_01FF.reboot();
        X0200_03FF.reboot();
        X0400_07FF.reboot();
        X0800_1FFF.reboot();
        X2000_3FFF.reboot();
        X4000_BFFF.reboot();
    }
}

class IOU
{
    IO io_;
    SignalBase signal;
    bool dHGR;

    this(IO ioDevices, SignalBase sig)
    {
        io_ = ioDevices;
        signal = sig;
    }

    void resetAn0()
    {
        io_.annun.ann_0_Off();
    }

    void resetAn1()
    {
        io_.annun.ann_1_Off();
    }
    
    void resetAn2()
    {
        io_.annun.ann_2_Off();
    }

    void resetAn3()
    {
        io_.annun.ann_3_Off();
        dHGR = true;
        signal.dHGRChange(true);
    }

    void setAn0()
    {
        io_.annun.ann_0_On();
    }

    void setAn1()
    {
        io_.annun.ann_1_On();
    }
    
    void setAn2()
    {
        io_.annun.ann_2_On();
    }

    void setAn3()
    {
        io_.annun.ann_3_On();
        dHGR = false;
        signal.dHGRChange(false);
    }

    ubyte readDHGR()
    {
        io_.paddles.trigger();
        return (dHGR ? 0x80 : 0x00);
    }

    void triggerTimers()
    {
        io_.paddles.trigger();
    }

    mixin(InitSwitches("", [
        mixin(MakeSwitch([0xC058], "R0W", "resetAn0")),
        mixin(MakeSwitch([0xC059], "R0W", "setAn0")),
        mixin(MakeSwitch([0xC05A], "R0W", "resetAn1")),
        mixin(MakeSwitch([0xC05B], "R0W", "setAn1")),
        mixin(MakeSwitch([0xC05C], "R0W", "resetAn2")),
        mixin(MakeSwitch([0xC05D], "R0W", "setAn2")),
        mixin(MakeSwitch([0xC05E], "R0W", "resetAn3")),
        mixin(MakeSwitch([0xC05F], "R0W", "setAn3")),
        // XXX next two only for enhanced:
        mixin(MakeSwitch([0xC07F], "R7", "readDHGR")),
        mixin(MakeSwitch([0xC07F], "W", "triggerTimers"))
    ]));
}

class MMU
{
    LanguageCard_IIe himemManager; 
    AddressDecoder decoder;
    AuxiliaryCard auxCard;
    IOMem_IIe ioMem;
    ScannerBase scanner;
    ubyte delegate() kbdLatch;

    MemMap[2] mem;

    this()
    {
        himemManager = new LanguageCard_IIe();
    }

    void reboot()
    {
        himemManager.reboot();
        mem[0].reboot();
    }

    void reset()
    {
        himemManager.reset();
        ioMem.reset();
    }

    void init(SoftSwitchPage switches, AuxiliaryCard auxCard_,
            AddressDecoder addrDecode, DataMem mainRam, DataMem mainRom)
    {
        auxCard = auxCard_;
        decoder = addrDecode;

        himemManager.auxslot = auxCard.himem;
        himemManager.initSwitches(switches);
        himemManager.init(decoder, &mainRom.read,
                &mainRom.write);

        initMem(mainRam);
        
        initSwitches(switches);
        ioMem.initSwitches(switches);
    }

    void initMem(DataMem mainRam)
    {
        mem[0].X0000_01FF = new SliceMem(0x0000, 0x0200, mainRam);
        mem[0].X0200_03FF = new SliceMem(0x0200, 0x0200, mainRam);
        mem[0].X0400_07FF = new SliceMem(0x0400, 0x0400, mainRam);
        mem[0].X0800_1FFF = new SliceMem(0x0800, 0x1800, mainRam);
        mem[0].X2000_3FFF = new SliceMem(0x2000, 0x2000, mainRam);
        mem[0].X4000_BFFF = new SliceMem(0x4000, 0x8000, mainRam);
        mem[1] = auxCard.mem;
    }

    void initIO(ScannerBase scn, ubyte delegate() peekLatch)
    {
        kbdLatch = peekLatch;
        scanner = scn;
        ioMem.kbdLatch = kbdLatch;
        himemManager.kbdLatch = kbdLatch;
    }

    bool switchPage2, switchHires, switch80Store;
    bool ramRd, ramWrt, altZP;

    void mapVidMem(bool rd, bool wrt)
    {
        decoder.installRead(mem[cast(int)rd].X0400_07FF);
        decoder.installWrite(mem[cast(int)wrt].X0400_07FF);
        if (switchHires)
        {
            mapHiresVidMem(rd, wrt);
        }
    }

    void mapHiresVidMem(bool rd, bool wrt)
    {
        decoder.installRead(mem[cast(int)rd].X2000_3FFF);
        decoder.installWrite(mem[cast(int)wrt].X2000_3FFF);
    }

    void resetRamRd()
    {
        ramRd = false;
        changeRamSwitch(ramRd, true, false);
    }

    void setRamRd()
    {
        ramRd = true;
        changeRamSwitch(ramRd, true, false);
    }

    void resetRamWrt()
    {
        ramWrt = false;
        changeRamSwitch(ramWrt, false, true);
    }

    void setRamWrt()
    {
        ramWrt = true;
        changeRamSwitch(ramWrt, false, true);
    }

    void changeRamSwitch(bool sw, bool rd, bool wrt)
    {
        int bank = cast(int)sw;
        decoder.install(mem[bank].X0200_03FF, rd, wrt);
        if (!switch80Store)
            decoder.install(mem[bank].X0400_07FF, rd, wrt);
        decoder.install(mem[bank].X0800_1FFF, rd, wrt);
        if ((!switch80Store) || (!switchHires))
            decoder.install(mem[bank].X2000_3FFF, rd, wrt);
        decoder.install(mem[bank].X4000_BFFF, rd, wrt);
    }

    void resetAltZP()
    {
        altZP = false;
        himemManager.enableAuxSlot(false);
        decoder.install(mem[0].X0000_01FF);
    }

    void setAltZP()
    {
        altZP = true;
        himemManager.enableAuxSlot(true);
        decoder.install(mem[1].X0000_01FF);
    }

    void reset80Store()
    {
        if (switchPage2)
            scanner.page2SwitchOn();
        else
            scanner.page2SwitchOff();
        switch80Store = false;
        mapVidMem(ramRd, ramWrt);
    }

    void set80Store()
    {
        scanner.page2SwitchOff();
        switch80Store = true;
        mapVidMem(switchPage2, switchPage2);
    }

    void resetPage2()
    {
        if (!switch80Store) scanner.page2SwitchOff();
        switchPage2 = false;
        if (switch80Store) mapVidMem(switchPage2, switchPage2);
    }

    void setPage2()
    {
        if (!switch80Store) scanner.page2SwitchOn();
        switchPage2 = true;
        if (switch80Store) mapVidMem(switchPage2, switchPage2);
    }

    void resetHires()
    {
        scanner.hiresSwitchOff();
        switchHires = false;
        if (switch80Store) mapHiresVidMem(ramRd, ramWrt);
    }

    void setHires()
    {
        scanner.hiresSwitchOn();
        switchHires = true;
        if (switch80Store) mapHiresVidMem(switchPage2, switchPage2);
    }

    ubyte readKbdSwitch(bool sw)
    {
        return kbdLatch() | (sw ? 0x80 : 0x00);
    }

    ubyte readRamRd()
    {
        return readKbdSwitch(ramRd);
    }

    ubyte readRamWrt()
    {
        return readKbdSwitch(ramWrt);
    }

    ubyte readAltZP()
    {
        return readKbdSwitch(altZP);
    }

    ubyte read80Store()
    {
        return readKbdSwitch(switch80Store);
    }

    ubyte readPage2()
    {
        return readKbdSwitch(switchPage2);
    }

    ubyte readHires()
    {
        return readKbdSwitch(switchHires);
    }

    mixin(InitSwitches("", [
        mixin(MakeSwitch([0xC000], "W", "reset80Store")),
        mixin(MakeSwitch([0xC001], "W", "set80Store")),
        mixin(MakeSwitch([0xC002], "W", "resetRamRd")),
        mixin(MakeSwitch([0xC003], "W", "setRamRd")),
        mixin(MakeSwitch([0xC004], "W", "resetRamWrt")),
        mixin(MakeSwitch([0xC005], "W", "setRamWrt")),
        mixin(MakeSwitch([0xC008], "W", "resetAltZP")),
        mixin(MakeSwitch([0xC009], "W", "setAltZP")),
        mixin(MakeSwitch([0xC013], "R", "readRamRd")),
        mixin(MakeSwitch([0xC014], "R", "readRamWrt")),
        mixin(MakeSwitch([0xC016], "R", "readAltZP")),
        mixin(MakeSwitch([0xC018], "R", "read80Store")),
        mixin(MakeSwitch([0xC01C], "R", "readPage2")),
        mixin(MakeSwitch([0xC01D], "R", "readHires")),
        mixin(MakeSwitch([0xC054], "R0W", "resetPage2")),
        mixin(MakeSwitch([0xC055], "R0W", "setPage2")),
        mixin(MakeSwitch([0xC056], "R0W", "resetHires")),
        mixin(MakeSwitch([0xC057], "R0W", "setHires"))
    ]));
}

class AuxiliaryCard
{
    HighRam_IIe himem;
    MemMap mem;
    VideoPages vidPages;
    abstract void reboot();
    abstract void reset();
}

class Extended80ColumnCard : AuxiliaryCard
{
    PrimaryMem auxRam;

    this()
    {
        auxRam = new PrimaryMem(0x0000, 0xC000);
        auxRam.debugName = "Aux RAM";
        himem = new HighRam_IIe(false, 1);
        himem.setDebugName("Aux high RAM");
        vidPages.lores1 = new SliceMem(0x0400, 0x0400, auxRam);
        vidPages.lores2 = new SliceMem(0x0800, 0x0400, auxRam);
        vidPages.hires1 = new SliceMem(0x2000, 0x2000, auxRam);
        vidPages.hires2 = new SliceMem(0x4000, 0x2000, auxRam);
        mem.X0000_01FF = new SliceMem(0x0000, 0x0200, auxRam);
        mem.X0200_03FF = new SliceMem(0x0200, 0x0200, auxRam);
        mem.X0400_07FF = new SliceMem(0x0400, 0x0400, auxRam);
        mem.X0800_1FFF = new SliceMem(0x0800, 0x1800, auxRam);
        mem.X2000_3FFF = new SliceMem(0x2000, 0x2000, auxRam);
        mem.X4000_BFFF = new SliceMem(0x4000, 0x8000, auxRam);
    }

    void reboot()
    {
        auxRam.reboot();
        vidPages.reboot();
        mem.reboot();
    }

    void reset() {}
}

