//@ //////////////////////////////////////////////////////////////////////////
//@ Copyright: 2007 Gerald Stocker
//@
//@ This file is part of twoapple-reboot.
//@
//@ twoapple-reboot is free software; you can redistribute it and/or modify
//@ it under the terms of the GNU General Public License as published by
//@ the Free Software Foundation; either version 2 of the License, or
//@ (at your option) any later version.
//@
//@ twoapple-reboot is distributed in the hope that it will be useful,
//@ but WITHOUT ANY WARRANTY; without even the implied warranty of
//@ MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//@ GNU General Public License for more details.
//@
//@ You should have received a copy of the GNU General Public License
//@ along with twoapple-reboot; if not, write to the Free Software
//@ Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
//@ //////////////////////////////////////////////////////////////////////////

import std.stdio;

import cpu.d6502;
import timer;
import memory;
import system.base;
import ui.monitor;
import ui.sound;
import ui.inputevents;

import gthread.Thread;
import gtk.Main;
import glgdk.GLdInit;
import gtkc.gdktypes;
import gtkc.gtktypes;

import peripheral.base;
import peripheral.diskii;
import peripheral.langcard;
import peripheral.saturn128;

import std.file;
import std.string;
import device.speaker;
import ui.mainwindow;
import video.laz_engine;

// XXX Only needed for initializing peripheralStatus
import gtk.VBox;
import peripheral.base;

void main(string[] args)
{
    // Init GTK
    Thread.init(null);
    Main.init(args);
    GLdInit.init(args);

    // open config

    input = new Input();
    monitor = new Monitor();
    auto screen = new LazEngine();
    monitor.installScreen(screen);

    // XXX should make it so this can happen after system?
    peripheralStatus = new VBox(false, 3);

    appWindow = new TwoappleMainWindow();

    // Get ROM file
    TwoappleFile romFile = TwoappleFilePicker.open("ROM file", &checkRomFile);
    if (romFile is null) return;

    SystemBase sys;
    if ((args.length > 1) && (args[1] == "--iie"))
        sys = new System!"65C02"(cast(ubyte[])std.file.read(romFile.fileName));
    else
        sys = new System!"6502"(cast(ubyte[])std.file.read(romFile.fileName));
    appWindow.initSystem(sys);
    // XXX hack
    appWindow.configChanged = true;
    debug(disassemble)
    {
        input.pauseButton.setActive(true);
    }
    appWindow.mainLoop();

    // save config
}

string checkRomFile(TwoappleFile checkFile)
{
    ulong fsize = checkFile.fileSize();
    // XXX allow 12288 for II/II+ ?
    if (fsize >= 20480 && fsize <= 32768)
        return null;
    else
        return "Invalid ROM file";
}
