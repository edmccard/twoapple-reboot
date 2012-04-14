/+
 + system/base.d
 +
 + Copyright: 2007 Gerald Stocker
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

module system.base;

import timer;
import memory;
import cpu.d6502;

import ui.sound;
import ui.inputevents;

import system.io;
import system.video;
import iomem;
import video.base;
import system.peripheral;
import ioummu;


class SystemBase
{
    Video video_;

    abstract void reboot();
    abstract void reset();
    abstract uint checkpoint();
    abstract uint sinceCheckpoint(uint cp);
    abstract void execute();
}

class System(string chip) : SystemBase
{
    Timer timer;
    Timer.Cycle deviceCycle;
    AddressDecoder decoder;
    SoftSwitchPage switches;

    Cpu!(chip, AddressDecoder, Timer) cpu;
    // XXX
    bool* cpuRun, signalActive, resetLow;

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
                    romDump[($-12288)..$]);
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

    Memory memory_;
    IO io_;

    static if (chip == "65C02")
    {
        AuxiliaryCard auxCard;
        MMU mmu;
        IOU iou;
    }

    this(ubyte[] romDump)
    {
        initTimer();
        initMemory(romDump);
        initCpu();
        initIO(null);   // XXX where is vidRom passed in?
        decoder.nullRead = &video_.scanner.floatingBus;

        static if (chip == "6502")
            peripherals = new Peripherals_II();
        else
            peripherals = new Peripherals_IIe();
        peripherals.install(decoder, memory_.mainRom);
        ioMem.initialize(decoder, switches, timer, peripherals);

        input.onReset = &reset;
        switches.setFloatingBus(&video_.scanner.floatingBus);
    }

    override void reboot()
    {
        // XXX replace
        //cpu.reboot();
        deviceCycle.restart();
        memory_.reboot();
        ioMem.reboot();
        io_.reboot();
        peripherals.reboot();
        video_.reboot();

        static if (chip == "65C02")
        {
            auxCard.reboot();
            mmu.reboot();
        }
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
        static if (chip == "65C02")
        {
            mmu = new MMU();
            mmu.ioMem = new IOMem_IIe();
            mmu.ioMem.setRom(romDump);
        }
        memory_ = new Memory(romDump);
        decoder = new AddressDecoder();
        switches = new SoftSwitchPage();
        decoder.installSwitches(switches);
        decoder.install(memory_.mainRam);
        decoder.install(memory_.mainRom);
        static if (chip == "6502")
            ioMem = new IOMem();
        else
        {
            ioMem = mmu.ioMem;
            auxCard = new Extended80ColumnCard();
            mmu.init(switches, auxCard, decoder, memory_.mainRam,
                     memory_.mainRom);
        }
    }

    void initCpu()
    {
        cpu = new Cpu!(chip, AddressDecoder, Timer)(decoder, timer);
        // XXX
        cpuRun = &cpu.keepRunning;
        signalActive = &cpu.signalActive;
        resetLow = &cpu.resetLow;

        debug(disassemble) cpu.memoryName = &decoder.memoryReadName;
        timer.onPrimaryStop(&primaryStop);
    }

    void initIO(ubyte[] vidRom)
    {
        static if (chip == "6502")
        {
            io_ = new IO_II(switches, timer, deviceCycle);
            video_ = new Video_II(switches, memory_.vidPages, timer, vidRom,
                                  &io_.kbd.peekLatch, decoder);
        }
        else
        {
            io_ = new IO_IIe(switches, timer, deviceCycle);
            video_ = new Video_IIe(switches, memory_.vidPages, timer, vidRom,
                                   &io_.kbd.peekLatch, auxCard.vidPages);
            iou = new IOU(io_, video_.signal);
            iou.initSwitches(switches);
            mmu.initIO(video_.scanner, &io_.kbd.peekLatch);
        }
    }

    bool primaryStop()
    {
        *cpuRun = false;
        return true;
    }

    override void reset()
    {
        static if (chip == "65C02")
        {
            auxCard.reset();
            mmu.reset();
        }

        peripherals.reset();
        *signalActive = true;
        *resetLow = true;
    }

    override uint checkpoint()
    {
        return timer.primaryCounter.currentLength;
    }

    override uint sinceCheckpoint(uint cp)
    {
        uint currentLength = timer.primaryCounter.currentLength;
        return ((currentLength == timer.primaryCounter.startLength) ?
            cp : (cp - currentLength));
    }

    override void execute()
    {
        cpu.run(true);

        soundCard.process();
        soundCard.start();

        video_.signal.update();
        deviceCycle.restart();
        // XXX peripherals get notification
    }
}
