/+
 + ui/mainwindow.d
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

module ui.mainwindow;

import std.string;

import gtk.MainWindow;
import gtkc.gtktypes;

import ui.inputevents;
import ui.sound;
import ui.monitor;
import host;
import system.base;

TwoappleMainWindow appWindow;

class TwoappleMainWindow : MainWindow
{
    import gtk.MenuBar;
    import gtk.Widget;
    import gdk.Event;
    import gtk.Toolbar;
    import gtk.ToggleToolButton;
    import gtk.SeparatorToolItem;
    import gtk.ToolButton;
    import gtk.SeparatorToolItem;
    import gtk.MenuItem;
    import gtk.AccelGroup;
    import gtk.VBox;
    import gtk.Toolbar;
    import gtk.Label;
    import gtk.ToolItem;
    import gtk.Alignment;
    import peripheral.base;

    System system;
    Label speedLabel;
    ToolItem speedItem;

    // XXX FIXME XXX
    // the system and its ui components need to be separated
    // (so system can switch from ii to iie or whatever,
    // without affecting listeners/pausers/etc. that are connected to
    // the mainwindow)
    this()
    {
        super("Twoapple");

        addOnKeyPress(&input.onKeyPress);
        addOnKeyRelease(&input.onKeyRelease);

        auto mainBox = new VBox(false, 3);

        auto menuBar = new MenuBar();
        auto menu = menuBar.append("_Menu");
        auto item = new MenuItem(&onMenuActivate, "_Read text file",
                "menu.read", true, null, 'r');
        menu.append(item);

        auto toolBar = new Toolbar();
        toolBar.insert(input.pauseButton, -1);
        auto bootButton = new ToolButton(null, "Boot");
        toolBar.insert(bootButton, -1);
        bootButton.addOnClicked(&onBootClicked);
        toolBar.insert(new SeparatorToolItem());
        auto monoButton = new ToggleToolButton();
        monoButton.setLabel("Mono");
        monoButton.addOnToggled(&onMonoToggle);
        toolBar.insert(monoButton, -1);
        auto toolSpace = new SeparatorToolItem();
        toolSpace.setDraw(false);
        toolSpace.setExpand(true);
        toolBar.insert(toolSpace, -1);
        speedLabel = new Label("    0%");
        speedItem = new ToolItem();
        speedItem.add(speedLabel);
        toolBar.insert(speedItem, -1);
        toolBar.setStyle(GtkToolbarStyle.TEXT);

        mainBox.packStart(menuBar, false, false, 0);
        mainBox.packStart(toolBar, false, false, 0);
        mainBox.packStart(monitor, false, false, 0);
        mainBox.packStart(peripheralStatus, false, false, 0);

        add(mainBox);
        setResizable(0);
        showAll();
    }

    void onBootClicked(ToolButton b)
    {
        reboot = true;
    }

    void onMonoToggle(ToggleToolButton b)
    {
        monitor.screen.isColor = (!b.getActive());
        if (input.pauseButton.getActive())
        {
            system.video_.forceFrame();
        }
    }

    void initSystem(System sys)
    {
        showAll();
        system = sys;
    }

    void onMenuActivate(MenuItem menuItem)
    {
        TwoappleFile checkFile =
            TwoappleFilePicker.open("text file");
        if (checkFile !is null)
            input.startTextInput(checkFile.fileName);
    }

    int windowDelete(Event event, Widget widget)
    {
        stayOpen = false;
        soundCard.pause();
        return super.windowDelete(event, widget);
    }

    bool configChanged;
    bool runOnce;
    bool stayOpen;
    bool reboot;

    import std.stream;
    void mainLoop()
    {
        bool shouldRun;
        uint willElapse, didElapse;
        float speedPercent;
        char[] speedString = new char[10];
        stayOpen = true;
        do
        {
            if (configChanged)
            {
                // apply config
                configChanged = false;
                debug(disassemble)
                {
                    reboot = false;
                }
                else
                {
                    reboot = true;
                }
            }

            if (reboot)
            {
                system.reboot();
                system.reset();
                input.pauseButton.setSensitive(true);
                input.pauseButton.setActive(false);
                host.delay.reset();
                reboot = false;
            }

            if (input.pauseButton.getActive())
                shouldRun = runOnce;
            else
                shouldRun = true;

            if (shouldRun)
            {
                willElapse = system.checkpoint();
                system.execute();
                didElapse = system.sinceCheckpoint(willElapse);
                input.processEvents();
                // XXX do something about typeahead?
                if (!runOnce)
                {
                    host.delay.sleep();
                    speedPercent = host.delay.checkSpeedPercent(didElapse);
                    if (speedPercent > -1.0)
                    {
                        speedString = std.string.sformat(speedString,
                                "% 5d%%", cast(int)(speedPercent * 100));
                        speedLabel.setText(speedString);
                    }
                }
                runOnce = false;
            }
            else
            {
                input.processEvents();
                // XXX time says "Paused" or something
                if (!(input.pauseButton.getActive()))
                    host.delay.reset();
                else
                    host.delay.nap();
            }
        }
        while (stayOpen)
    }
}

class TwoappleFile
{
    import std.c.linux.linux;
    import std.file;
    import std.path;

    string fileName;
    char* fileNameZ;

    this(string fname)
    {
        assert(isabs(fname) != 0);
        fileName = fname;
        fileNameZ = std.string.toStringz(fname);
    }

    string folder()
    {
        return getDirName(fileName);
    }

    string baseName()
    {
        string base = getName(fileName);
        if (base is null) return getBaseName(fileName);
        else return getBaseName(base);
    }

    bool canRead()
    {
        return !(access(fileNameZ, 4));
    }

    bool canWrite()
    {
        return !(access(fileNameZ, 2));
    }

    bool canCreate()
    {
        return !(access(std.string.toStringz(folder()), 2));
    }

    bool exists()
    {
        return (std.file.exists(fileName) != 0);
    }

    uint fileSize()
    {
        return getSize(fileName);
    }
}

class TwoappleError
{
    import gtk.Window;
    import gtk.MessageDialog;

    static void show(Window parent, string msg)
    {
        scope md = new MessageDialog(parent, GtkDialogFlags.MODAL,
                MessageType.ERROR, ButtonsType.CLOSE, msg);
        md.setTitle("Error");
        md.run();
        md.hide();
        md.destroy();
    }

    static void show(string msg)
    {
        soundCard.pause();
        show(appWindow, msg);
        host.delay.reset();
        soundCard.resume();
    }
}

class TwoappleFilePicker
{
    import std.stdio;
    import gtk.FileChooserDialog;

    static string[string] lastFolder;

    static TwoappleFile saveAs(string type, string folder, string name)
    {
        soundCard.pause();

        scope fcd = new FileChooserDialog("Save " ~ type, appWindow,
                FileChooserAction.SAVE);

        scope chooser = fcd.getFileChooser();
        chooser.setCurrentFolder(folder);
        chooser.setCurrentName(name);

        TwoappleFile file;
        while (true)
        {
            if (fcd.run() != ResponseType.GTK_RESPONSE_OK) break;
            file = new TwoappleFile(chooser.getFilename());
            if (file.exists())
            {
                if (!file.canWrite())
                {
                    TwoappleError.show(fcd, "File is read-only");
                    file = null;
                }
            }
            else
            {
                if (!file.canCreate())
                {
                    TwoappleError.show(fcd, "Directory is read-only");
                    file = null;
                }
            }
            if (file !is null) break;
        }

        fcd.hide();
        fcd.destroy();
        
        host.delay.reset();
        soundCard.resume();

        return file;
    }

    static TwoappleFile open(string type, string delegate(TwoappleFile) dg)
    {
        soundCard.pause();

        scope fcd = new FileChooserDialog("Open " ~ type, appWindow,
                FileChooserAction.OPEN);
        scope chooser = fcd.getFileChooser();

        if (type in lastFolder)
            chooser.setCurrentFolder(lastFolder[type]);

        TwoappleFile file;
        while(true)
        {
            if (fcd.run() != ResponseType.GTK_RESPONSE_OK) break;
            file = new TwoappleFile(chooser.getFilename());
            if (!file.canRead())
            {
                TwoappleError.show(fcd, "File cannot be read");
                file = null;
            }
            else
            {
                string msg = dg(file);
                if (msg !is null)
                {
                    TwoappleError.show(fcd, msg);
                    file = null;
                }
            }
            if (file !is null)
            {
                lastFolder[type] = file.folder();
                break;
            }
        }

        fcd.hide();
        fcd.destroy();

        host.delay.reset();
        soundCard.resume();

        return file;
    }

    static TwoappleFile open(string type, string function(TwoappleFile) func)
    {
        return open(type,
                delegate string(TwoappleFile checkFile)
                    { return func(checkFile); });
    }

    static TwoappleFile open(string type)
    {
        return open(type,
                delegate string(TwoappleFile checkFile)
                    { return null; });
    }
}

class TwoappleDialog
{
    import gtk.MessageDialog;

    static int run(string title, string msg, string[] buttonText,
            bool hasDefault = true)
    {
        soundCard.pause();

        scope md = new MessageDialog(appWindow, GtkDialogFlags.MODAL,
                MessageType.WARNING, ButtonsType.NONE, msg);
        md.setTitle(title);

        int response;
        for (int b = 0; b < buttonText.length; ++b)
        {
            if ((b == 0) && hasDefault)
                response = ResponseType.GTK_RESPONSE_OK;
            else if (b == (buttonText.length - 1))
                response = ResponseType.GTK_RESPONSE_CANCEL;
            else
                response = b;
            md.addButton(buttonText[b], response);
        }

        response = md.run();
        md.hide();
        md.destroy();

        if (response == ResponseType.GTK_RESPONSE_OK)
            response = 0;
        else if ((response == ResponseType.GTK_RESPONSE_CANCEL) ||
                (response == ResponseType.GTK_RESPONSE_DELETE_EVENT))
            response = buttonText.length - 1;

        host.delay.reset();
        soundCard.resume();

        return response;
    }
}
