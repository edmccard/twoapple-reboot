/+
 + system/base.d
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

module system.base;

import timer;
import memory;
import d6502.base;

import ui.sound;
import ui.inputevents;

import system.io;
import system.video;
import iomem;
import video.base;
import system.peripheral;

class System
{
    Timer timer;
    Timer.Cycle deviceCycle;
    AddressDecoder decoder;
    SoftSwitchPage switches;
    CpuBase cpu;
    IOMem ioMem;
    Peripherals peripherals;

    class Memory
    {
        PrimaryMem mainRam;
        Rom mainRom;
        VideoPages vidPages;

        this(ubyte[] romDump)
        {
            mainRam = new PrimaryMem(0x0000, 0xC000);
            mainRam.debugName = "RAM";
            mainRom = new Rom(0xD000, 0x3000,
                    romDump[(length-12288)..length]);
            mainRom.debugName = "ROM";
            vidPages.lores1 = new SliceMem(0x0400, 0x0400, mainRam);
            vidPages.lores2 = new SliceMem(0x0800, 0x0400, mainRam);
            vidPages.hires1 = new SliceMem(0x2000, 0x2000, mainRam);
            vidPages.hires2 = new SliceMem(0x4000, 0x2000, mainRam);
        }

        void reboot()
        {
            mainRam.reboot();
            vidPages.reboot();
        }
    }

    Video video_;
    Memory memory_;
    IO io_;

    abstract IO newIO();
    abstract CpuBase newCpu();
    abstract Video newVideo(ubyte[] vidRom);
    abstract IOMem newIOMem();
    abstract Peripherals newPeripherals();

    this(ubyte[] romDump)
    {
        initTimer();
        initMemory(romDump);
        initCpu();
        initIO(null);   // XXX where is vidRom passed in?
        decoder.nullRead = &video_.scanner.floatingBus;

        peripherals = newPeripherals();
        peripherals.install(cpu, decoder, memory_.mainRom);
        ioMem.initialize(decoder, switches, timer, peripherals);

        input.onReset = &reset;
        switches.setFloatingBus(&video_.scanner.floatingBus);
    }

    void reboot()
    {
        cpu.reboot();
        deviceCycle.restart();
        memory_.reboot();
        ioMem.reboot();
        io_.reboot();
        peripherals.reboot();
        video_.reboot();
    }

    void initTimer()
    {
        // XXX constants? variables?
        timer = new Timer(10_205, 1_020_484);
        deviceCycle =
            timer.startCycle(timer.primaryCounter.startLength * 2);
    }

    void initMemory(ubyte[] romDump)
    {
        memory_ = new Memory(romDump);
        decoder = new AddressDecoder();
        switches = new SoftSwitchPage();
        decoder.installSwitches(switches);
        decoder.install(memory_.mainRam);
        decoder.install(memory_.mainRom);
        ioMem = newIOMem();
    }

    void initCpu()
    {
        cpu = newCpu();
        debug(disassemble) cpu.memoryName = &decoder.memoryReadName;
        cpu.tick = &timer.tick;
        timer.onPrimaryStop(&primaryStop);
        cpu.memoryRead = &decoder.read;
        cpu.memoryWrite = &decoder.write;
    }

    void initIO(ubyte[] vidRom)
    {
        io_ = newIO();
        video_ = newVideo(vidRom);
    }

    bool primaryStop()
    {
        cpu.stop();
        return true;
    }

    void reset()
    {
        peripherals.reset();
        cpu.resetLow();
    }

    uint checkpoint()
    {
        return timer.primaryCounter.currentLength;
    }

    uint sinceCheckpoint(uint cp)
    {
        uint currentLength = timer.primaryCounter.currentLength;
        return ((currentLength == timer.primaryCounter.startLength) ?
            cp : (cp - currentLength));
    }

    void execute()
    {
        cpu.run(true);

        soundCard.process();
        soundCard.start();

        video_.signal.update();
        deviceCycle.restart();
        // XXX peripherals get notification
    }
}

class II : System
{
    import d6502.nmosundoc : NmosUndoc;

    int revision;

    this(ubyte[] romDump)
    {
        // XXX FIXME XXX
        revision = int.max;
        super(romDump);
    }

    CpuBase newCpu()
    {
        return new NmosUndoc();
    }

    IO newIO()
    {
        return new IO_II(switches, timer, deviceCycle);
    }

    Video newVideo(ubyte[] vidRom)
    {
        return new Video_II(switches, memory_.vidPages, timer, vidRom,
                &io_.kbd.peekLatch, decoder);
    }

    IOMem newIOMem()
    {
        return new IOMem();
    }

    Peripherals newPeripherals()
    {
        return new Peripherals_II();
    }
}

import ioummu;

class IIe : System
{
    import d6502.cmos : Cmos;

    AuxiliaryCard auxCard;
    MMU mmu;
    IOU iou;

    this(ubyte[] romDump)
    {
        // XXX if different or no aux card?
        //auxMemory = new Memory();
        super(romDump);
    }

    void reboot()
    {
        super.reboot();
        auxCard.reboot();
        mmu.reboot();
    }

    void reset()
    {
        auxCard.reset();
        mmu.reset();
        super.reset();
    }

    CpuBase newCpu()
    {
        // XXX this is enhanced
        return new Cmos();
    }

    IO newIO()
    {
        return new IO_IIe(switches, timer, deviceCycle);
    }

    Video newVideo(ubyte[] vidRom)
    {
        return new Video_IIe(switches, memory_.vidPages, timer, vidRom,
                &io_.kbd.peekLatch, auxCard.vidPages);
    }

    IOMem newIOMem()
    {
        return mmu.ioMem;
    }

    Peripherals newPeripherals()
    {
        return new Peripherals_IIe();
    }

    void initMemory(ubyte[] romDump)
    {
        mmu = new MMU();
        mmu.ioMem = new IOMem_IIe();
        mmu.ioMem.setRom(romDump);

        super.initMemory(romDump);

        // XXX XXX XXX
        // allow for different card from config
        auxCard = new Extended80ColumnCard();

        mmu.init(switches, auxCard, decoder, memory_.mainRam,
                memory_.mainRom);
    }

    void initIO(ubyte[] vidRom)
    {
        super.initIO(vidRom);
        iou = new IOU(io_, video_.signal);
        iou.initSwitches(switches);
        mmu.initIO(video_.scanner, &io_.kbd.peekLatch);
    }
}

