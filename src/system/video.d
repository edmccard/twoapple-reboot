/+
 + system/video.d
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

module system.video;

import memory;
import timer;

import ui.monitor;

import video.base;
import video.scanner;
import video.signal;

class Video
{
    Scanner scanner;
    Signal signal;
    Screen screen;

    this(SoftSwitchPage switches, VideoPages vidPages, Timer timer,
            ubyte[] vidRom, ubyte delegate() peekLatch)
    {
        signal = newSignal();
        scanner = newScanner();

        screen = monitor.screen;
        screen.scanner = scanner;

        scanner.signal = signal;
        scanner.drawFrame = &monitor.glDrawFrame;
        scanner.kbdLatch = peekLatch;
        scanner.init(timer);
        scanner.installMemory(vidPages.lores1, vidPages.lores2,
                vidPages.hires1, vidPages.hires2);
        scanner.initSwitches(switches);

        signal.scanner = scanner;
        signal.screen = screen;
        signal.kbdLatch = peekLatch;
        signal.init(timer, vidRom);
        signal.initSwitches(switches);
    }

    void reboot()
    {
        signal.reboot();
        scanner.reboot();
    }

    void forceFrame()
    {
        scanner.forceFrame();
        monitor.glDrawFrame();
    }

    abstract Scanner newScanner();
    abstract Signal newSignal();
}

class Video_II : Video
{
    Scanner_II scanner40;

    this(SoftSwitchPage switches, VideoPages vidPages, Timer timer,
            ubyte[] vidRom, ubyte delegate() peekLatch,
            AddressDecoder decoder)
    {
        super(switches, vidPages, timer, vidRom, peekLatch);
        scanner40.decoder = decoder;
    }

    Scanner newScanner()
    {
        scanner40 = new Scanner_II();
        return scanner40;
    }

    Signal newSignal()
    {
        return new Signal_II();
    }
}

class Video_IIe : Video
{
    this(SoftSwitchPage switches, VideoPages vidPages, Timer timer,
            ubyte[] vidRom, ubyte delegate() peekLatch, VideoPages auxPages)
    {
        super(switches, vidPages, timer, vidRom, peekLatch);
        scanner.installAuxMemory(auxPages.lores1, auxPages.lores2,
                auxPages.hires1, auxPages.hires2);
    }

    Scanner newScanner()
    {
        return new Scanner_IIe();
    }

    Signal newSignal()
    {
        return new Signal_IIe();
    }
}

