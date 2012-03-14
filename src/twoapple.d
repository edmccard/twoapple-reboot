//@ //////////////////////////////////////////////////////////////////////////
//@ Copyright: 2007 Gerald Stocker
//@
//@ This file is part of Twoapple.
//@
//@ Twoapple is free software; you can redistribute it and/or modify
//@ it under the terms of the GNU General Public License as published by
//@ the Free Software Foundation; either version 2 of the License, or
//@ (at your option) any later version.
//@
//@ Twoapple is distributed in the hope that it will be useful,
//@ but WITHOUT ANY WARRANTY; without even the implied warranty of
//@ MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//@ GNU General Public License for more details.
//@
//@ You should have received a copy of the GNU General Public License
//@ along with Twoapple; if not, write to the Free Software
//@ Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
//@ //////////////////////////////////////////////////////////////////////////

import std.stdio;

import d6502.base;
import timer;
import memory;
import system.base;
import ui.monitor;
import ui.sound;
import ui.inputevents;

import gthread.Thread;
import gtk.GtkD;
import glgdk.GLdInit;
import gtkc.gdktypes;
import gtkc.gtktypes;

import peripheral.base;
import peripheral.diskii;
import peripheral.langcard;
import peripheral.saturn128;

class TestSystem : II
{
    this(ubyte[] romDump)
    {
        super(romDump);
    }

    void setRom(ubyte[] rom_data)
    {
        uint rom_len = rom_data.length;
        memory_.mainRom.data_[0..12288] = rom_data[(rom_len - 12288)..rom_len];
    }
}

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
	GtkD.init(args);
	GLdInit.init(null, null);

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

    System sys;
    if ((args.length > 1) && (args[1] == "--iie"))
        sys = new IIe(cast(ubyte[])std.file.read(romFile.fileName));
    else
        sys = new II(cast(ubyte[])std.file.read(romFile.fileName));
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

