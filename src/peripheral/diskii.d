/+
 + peripheral/diskii.d
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

module peripheral.diskii;

import peripheral.base;
import device.base;
import memory;
import timer;

import ui.mainwindow;
import ui.sound;

import std.stream;

ubyte[256] controllerRom = [
    0xa2, 0x20, 0xa0, 0x00, 0xa2, 0x03, 0x86, 0x3c,
    0x8a, 0x0a, 0x24, 0x3c, 0xf0, 0x10, 0x05, 0x3c,
    0x49, 0xff, 0x29, 0x7e, 0xb0, 0x08, 0x4a, 0xd0,
    0xfb, 0x98, 0x9d, 0x56, 0x03, 0xc8, 0xe8, 0x10,
    0xe5, 0x20, 0x58, 0xff, 0xba, 0xbd, 0x00, 0x01,
    0x0a, 0x0a, 0x0a, 0x0a, 0x85, 0x2b, 0xaa, 0xbd,
    0x8e, 0xc0, 0xbd, 0x8c, 0xc0, 0xbd, 0x8a, 0xc0,
    0xbd, 0x89, 0xc0, 0xa0, 0x50, 0xbd, 0x80, 0xc0,
    0x98, 0x29, 0x03, 0x0a, 0x05, 0x2b, 0xaa, 0xbd,
    0x81, 0xc0, 0xa9, 0x56, 0x20, 0xa8, 0xfc, 0x88,
    0x10, 0xeb, 0x85, 0x26, 0x85, 0x3d, 0x85, 0x41,
    0xa9, 0x08, 0x85, 0x27, 0x18, 0x08, 0xbd, 0x8c,
    0xc0, 0x10, 0xfb, 0x49, 0xd5, 0xd0, 0xf7, 0xbd,
    0x8c, 0xc0, 0x10, 0xfb, 0xc9, 0xaa, 0xd0, 0xf3,
    0xea, 0xbd, 0x8c, 0xc0, 0x10, 0xfb, 0xc9, 0x96,
    0xf0, 0x09, 0x28, 0x90, 0xdf, 0x49, 0xad, 0xf0,
    0x25, 0xd0, 0xd9, 0xa0, 0x03, 0x85, 0x40, 0xbd,
    0x8c, 0xc0, 0x10, 0xfb, 0x2a, 0x85, 0x3c, 0xbd,
    0x8c, 0xc0, 0x10, 0xfb, 0x25, 0x3c, 0x88, 0xd0,
    0xec, 0x28, 0xc5, 0x3d, 0xd0, 0xbe, 0xa5, 0x40,
    0xc5, 0x41, 0xd0, 0xb8, 0xb0, 0xb7, 0xa0, 0x56,
    0x84, 0x3c, 0xbc, 0x8c, 0xc0, 0x10, 0xfb, 0x59,
    0xd6, 0x02, 0xa4, 0x3c, 0x88, 0x99, 0x00, 0x03,
    0xd0, 0xee, 0x84, 0x3c, 0xbc, 0x8c, 0xc0, 0x10,
    0xfb, 0x59, 0xd6, 0x02, 0xa4, 0x3c, 0x91, 0x26,
    0xc8, 0xd0, 0xef, 0xbc, 0x8c, 0xc0, 0x10, 0xfb,
    0x59, 0xd6, 0x02, 0xd0, 0x87, 0xa0, 0x00, 0xa2,
    0x56, 0xca, 0x30, 0xfb, 0xb1, 0x26, 0x5e, 0x00,
    0x03, 0x2a, 0x5e, 0x00, 0x03, 0x2a, 0x91, 0x26,
    0xc8, 0xd0, 0xee, 0xe6, 0x27, 0xe6, 0x3d, 0xa5,
    0x3d, 0xcd, 0x00, 0x08, 0xa6, 0x2b, 0x90, 0xdb,
    0x4c, 0x01, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00
];

class StopTimer
{
    Timer timer;
    Timer.Counter stopCounter;
    void delegate() notifyExpired;

    void startCountdown()
    {
        if (stopCounter is null)
            stopCounter = timer.new Counter(1_020_484, &expire);
    }

    void stopCountdown()
    {
        if (stopCounter !is null)
        {
            stopCounter.discard();
            stopCounter = null;
        }
    }

    bool expire()
    {
        notifyExpired();
        stopCounter = null;
        return false;
    }
}

class Controller : Peripheral
{
    import gtk.VBox;

    Drive[2] drives;

    int activeDrive;
    bool writeMode;
    bool loadRegister;
    bool delegate() checkFinalCycle;
    ubyte dataLatch;
    bool isOn;
    StopTimer drivesOffDelay;

    this()
    {
        ioSelectROM = controllerRom;
        statusBox = new VBox(false, 3);
        drives[0] = new Drive(1);
        statusBox.packStart(drives[0].status.display, false, false, 0);
        drives[1] = new Drive(2);
        statusBox.packStart(drives[1].status.display, false, false, 0);
    }

    void reset()
    {
        drives[0].deactivate();
        drives[1].deactivate();
        activeDrive = 0;
    }

    void initTimer(Timer timer)
    {
        drivesOffDelay = new StopTimer();
        drivesOffDelay.timer = timer;
        drivesOffDelay.notifyExpired = &doDrivesOff;
    }

    void doDrivesOff()
    {
        drives[activeDrive].deactivate();
        isOn = false;
    }

    void changeActiveDrive(int newActive)
    {
        drives[activeDrive].deactivate();
        if (isOn) drives[newActive].activate();
        activeDrive = newActive;
    }

    ubyte checkWriteProtect()
    {
        if (drives[activeDrive].writeProtected ||
                drives[activeDrive].magnets[1])
            return 0x80;
        else
            return 0x00;
    }

    ubyte phaseOff(ushort addr)
    {
        int phase = (addr >> 1) & 3;
        drives[activeDrive].setPhase(phase, false);
        return 0xFF;
    }

    void phaseOn(ushort addr)
    {
        int phase = (addr >> 1) & 3;
        drives[activeDrive].setPhase(phase, true);
    }

    ubyte drive_0_select()
    {
        if (activeDrive != 0) changeActiveDrive(0);
        return 0xFF;
    }

    void drive_1_select()
    {
        if (activeDrive != 1) changeActiveDrive(1);
    }

    ubyte drivesOff()
    {
        drivesOffDelay.startCountdown();
        return 0xFF;
    }

    void drivesOn()
    {
        isOn = true;
        drivesOffDelay.stopCountdown();
        drives[activeDrive].activate();
    }

    void readQ6H()
    {
        loadRegister = true;
    }

    ubyte Q6L()
    {
        loadRegister = false;
        if (isOn && checkFinalCycle())
        {
            if (writeMode)
            {
                drives[activeDrive].write(dataLatch);
                return dataLatch;
            }
            else
            {
                return drives[activeDrive].read();
            }
        }
        return 0x00;
    }

    void writeQ6H(ubyte val)
    {
        loadRegister = true;
        dataLatch = val;
    }

    ubyte Q7L()
    {
        writeMode = false;
        if (loadRegister) return checkWriteProtect();
        else return 0xFF;
    }

    void readQ7H()
    {
        writeMode = true;
    }

    void writeQ7H(ubyte val)
    {
        writeMode = true;
        dataLatch = val;
    }

    mixin(InitSwitches("", [
        mixin(MakeSwitch([0xC080, 0xC082, 0xC084, 0xC086],
                "RW", "phaseOff(addr)")),
        mixin(MakeSwitch([0xC081, 0xC083, 0xC085, 0xC087],
                "R0W", "phaseOn(addr)")),
        mixin(MakeSwitch([0xC088], "RW", "drivesOff")),
        mixin(MakeSwitch([0xC089], "R0W", "drivesOn")),
        mixin(MakeSwitch([0xC08A], "RW", "drive_0_select")),
        mixin(MakeSwitch([0xC08B], "R0W", "drive_1_select")),
        mixin(MakeSwitch([0xC08C], "RW", "Q6L")),
        mixin(MakeSwitch([0xC08D], "R0", "readQ6H")),
        mixin(MakeSwitch([0xC08D], "W", "writeQ6H(val)")),
        mixin(MakeSwitch([0xC08E], "RW", "Q7L")),
        mixin(MakeSwitch([0xC08F], "R0", "readQ7H")),
        mixin(MakeSwitch([0xC08F], "W", "writeQ7H(val)"))
    ]));
}

class DriveStatus
{
    import gtk.HBox;
    import gtk.MenuBar;
    import gtk.MenuItem;
    import gtk.ProgressBar;
    import gtk.CheckButton;
    import gtk.ToggleButton;
    import gtk.Label;
    import gtkc.pangotypes;

    import std.string;

    Drive drive;
    HBox display;
    ProgressBar activity;
    string statusClean, statusDirty;
    CheckButton wpButton;
    Label imgName;
    MenuItem openItem;
    MenuItem saveItem;
    MenuItem ejectItem;

    this(Drive drive_, int driveNum)
    {
        drive = drive_;

        statusClean = "Drive " ~ std.string.toString(driveNum);
        statusDirty = "( " ~ statusClean ~ " )";
        activity = new ProgressBar();
        activity.setText(statusClean);

        auto menuBar = new MenuBar();
        auto menu = menuBar.append("Image");
        openItem = new MenuItem(&onOpenImage, "Open", "img.open", false);
        saveItem = new MenuItem(&onSaveImage, "Save", "img.save", false);
        ejectItem = new MenuItem(&onEjectImage, "Eject", "img.eject", false);
        menu.append(openItem);
        menu.append(saveItem);
        menu.append(ejectItem);
        saveItem.setSensitive(false);
        ejectItem.setSensitive(false);

        wpButton = new CheckButton("WP", false);
        wpButton.addOnToggled(&onWPToggle);
        wpButton.setSensitive(false);

        imgName = new Label("No disk");
        imgName.setMaxWidthChars(35);
        imgName.setEllipsize(PangoEllipsizeMode.START);

        display = new HBox(false, 3);
        display.packStart(activity, false, false, 0);
        display.packStart(wpButton, false, false, 0);
        display.packStart(imgName, true, true, 0);
        display.packStart(menuBar, false, false, 0);
    }

    void setActive(bool isActive)
    {
        soundCard.speedyMode = isActive;
        activity.setFraction(isActive ? 1.0 : 0.0);
    }

    void setDirty(bool isDirty)
    {
        if (isDirty)
            activity.setText(statusDirty);
        else
            activity.setText(statusClean);
        saveItem.setSensitive(isDirty);
    }

    void onWPToggle(ToggleButton b)
    {
        drive.writeProtected = (b.getActive() != 0);
    }

    void onOpenImage(MenuItem m)
    {
        TwoappleFile file = TwoappleFilePicker.open("image file",
                &ExternalImage.isValidImage);
        if (file is null) return;
        if (!drive.loadImage(file)) return;

        if (!file.canWrite())
        {
            wpButton.setActive(true);
            wpButton.setSensitive(false);
        }
        else
            wpButton.setSensitive(true);

        setDirty(false);
        ejectItem.setSensitive(true);
        imgName.setText(file.fileName);
    }

    void onEjectImage(MenuItem m)
    {
        if (!drive.ejectImage()) return;
        setDirty(false);
        wpButton.setActive(false);
        wpButton.setSensitive(true);
        ejectItem.setSensitive(false);
        imgName.setText("No disk");
    }

    void onSaveImage(MenuItem m)
    {
        if (!drive.saveImage()) return;
        setDirty(false);
    }
}

class Drive
{
    InternalImage imgData;
    ExternalImage imgFile;
    DriveStatus status;
    bool writeProtected;
    int headPos, maxHeadPos, track;
    bool[4] magnets;

    this(int driveNum)
    {
        maxHeadPos = (InternalImage.NUM_TRACKS - 1) * 4;
        imgData = new NonImage();
        status = new DriveStatus(this, driveNum);
    }

    void setPhase(int phase, bool newState)
    {
        //if (magnets[phase] == newState) return;
        magnets[phase] = newState;

        // Find the number of active magnets and their
        // distances from any cog.
        int totalOn = 0, delta;
        for (int p = 0; p < 4; ++p)
        {
            if (magnets[p])
            {
                ++totalOn;
                delta = (p * 2) - (headPos % 8);
            }
        }

        // Do not move the head if more than one magnet
        // is on (which precludes quarter-tracking).
        if (totalOn != 1) return;

        // Do not move the head if the active magnet is
        // equidistant from the two nearest cogs, or if
        // it is already in line with a cog.
        if ((delta == -4) || (delta == 4) || (delta == 0)) return;

        // Pull the nearest cog to the magnet.
        if (delta > 4) delta -= 8;
        else if (delta < -4) delta += 8;
        headPos += delta;

        if (headPos < 0) headPos = 0; // make a noise?
        //else if (headPos > 136) headPos = 136;
        else if (headPos > maxHeadPos) headPos = maxHeadPos;
        track = (headPos & -4) / 4;
    }

    void activate()
    {
        status.setActive(true);
    }

    void deactivate()
    {
        status.setActive(false);
        magnets[0..4] = false;
    }

    ubyte read()
    {
        return imgData.peek(track);
    }

    void write(ubyte val)
    {
        if (writeProtected) return;
        bool wasDirty = imgData.isDirty;
        imgData.poke(track, val);
        if (imgData.isDirty && !wasDirty) status.setDirty(true);
    }

    bool ejectImage()
    {
        if (imgData.isDirty)
        {
            int response = TwoappleDialog.run("Warning",
                    "Save image currently in drive?",
                    ["Save", "Don't save", "Cancel"]);
            if (response == 2) return false;
            if (response == 0)
            {
                if (!saveImage(true)) return false;
            }
        }

        imgData = new NonImage();
        imgFile = null;

        return true;
    }

    bool loadImage(TwoappleFile file)
    {
        if (imgData.isDirty)
        {
            int response = TwoappleDialog.run("Warning",
                    "Save image currently in drive?",
                    ["Save", "Don't save", "Cancel"]);
            if (response == 2) return false;
            if (response == 0)
            {
                if (!saveImage(true)) return false;
            }
        }

        imgFile = ExternalImage.loadImage(file);
        assert(imgFile !is null);
        imgData = imgFile.imgData;
        
        return true;
    }

    bool saveImage(bool indirect = false)
    {
        bool retry, success;

        void chooseAction(string msg, void delegate() firstAction = null,
                string firstButton = null)
        {
            bool chooseAgain;
            void delegate()[] actions;
            string[] buttons;

            void delegate() saveAsNib =
            {
                TwoappleFile file = TwoappleFilePicker.saveAs("Image file",
                        imgFile.imgFile.folder(),
                        imgFile.imgFile.baseName() ~ ".nib");
                if (file is null) chooseAgain = true;
                else
                {
                    imgFile = new NIBImage(file, imgData);
                    retry = true;
                }
            };
            void delegate() noSave = { success = true; };
            void delegate() cancel = {};

            actions.length = buttons.length = 2 +
                (indirect ? 1 : 0) +
                ((firstAction !is null) ? 1 : 0);
            actions[length - 1] = cancel;
            buttons[length - 1] = "Cancel";
            if (indirect)
            {
                actions[length - 2] = noSave;
                buttons[length - 2] = "Don't save";
                actions[length - 3] = saveAsNib;
                buttons[length - 3] = "Save as NIB";
            }
            else
            {
                actions[length - 2] = saveAsNib;
                buttons[length - 2] = "Save as NIB";
            }
            if (firstAction !is null)
            {
                actions[0] = firstAction;
                buttons[0] = firstButton;
            }

            do
            {
                int action = TwoappleDialog.run("Warning", msg, buttons);
                actions[action]();
            } while (chooseAgain);
        }

        do
        {
            success = retry = false;
            try
            {
                imgFile.save();
                imgData.isDirty = false;
                success = true;
            }
            catch (DSKImage.VolumeException e)
            {
                chooseAction("Disk volume is not 254",
                        { e.ignoreVolume(); retry = true; },
                        "Ignore and save");
            }
            catch (DSKImage.DSKException e)
            {
                chooseAction("Image cannot be saved in DSK format");
            }
            catch (Exception e)
            {
                TwoappleError.show(e.msg);
            }
        } while (retry);

        return success;
    }
}

class InternalImage
{
    bool isDirty;
    static const NUM_TRACKS = 35;
    static const TRACK_LENGTH = 6656;   // XXX No DOS 3.2
    abstract ubyte peek(uint track);
    abstract void poke(uint track, ubyte val);
}

class NonImage : InternalImage
{
    ubyte peek(uint track) { return 0; }
    void poke(uint track, ubyte val) {}
}

class RealImage : InternalImage
{
    ubyte[][] trackData;
    uint currentPos;

    this()
    {
        trackData = new ubyte[][NUM_TRACKS];
        for (uint t = 0; t < NUM_TRACKS; ++t)
            trackData[t] = new ubyte[TRACK_LENGTH];
    }

    ubyte peek(uint track)
    {
        currentPos %= TRACK_LENGTH;
        return trackData[track][currentPos++];
    }

    void poke(uint track, ubyte val)
    {
        currentPos %= TRACK_LENGTH;
        trackData[track][currentPos++] = val;
        isDirty = true;
    }
}

class ExternalImage
{
    TwoappleFile imgFile;
    RealImage imgData;
    static const string invalidMessage = "Invalid image file";

    class ReadOnlyException : Exception
    {
        this() { super("File is read-only"); }
    }

    static string isValidImage(TwoappleFile checkFile)
    {
        uint fsize = checkFile.fileSize();
        return (isDSKImage(fsize) || isNIBImage(fsize)) ?
            null : invalidMessage;
    }

    static ExternalImage loadImage(TwoappleFile checkFile)
    {
        uint fsize = checkFile.fileSize();
        if (isDSKImage(fsize)) return new DSKImage(checkFile);
        if (isNIBImage(fsize)) return new NIBImage(checkFile);
        return null;
    }

    static bool isDSKImage(uint fsize)
    {
        return (fsize == 143488) ||
            ((fsize >= 143358) && (fsize <= 143363));
    }

    static bool isNIBImage(uint fsize)
    {
        return (fsize == 232960);
    }

    this(TwoappleFile checkFile)
    {
        imgFile = checkFile;
        imgData = new RealImage();
        load();
    }

    this(TwoappleFile checkFile, InternalImage data)
    {
        imgFile = checkFile;
        imgData = cast(RealImage)data;
    }

    abstract void load();
    abstract void writeOut(File stream);

    void save()
    {
        //if (!imgFile.canWrite()) throw new ReadOnlyException();
        File stream = new File(imgFile.fileName, FileMode.Out);
        scope(exit)
        {
            if (stream !is null) stream.close();
        }
        writeOut(stream);
    }
}

class DSKImage : ExternalImage
{
    static int[16] dosOrder = [
        0x00, 0x07, 0x0E, 0x06, 0x0D, 0x05, 0x0C, 0x04,
        0x0B, 0x03, 0x0A, 0x02, 0x09, 0x01, 0x08, 0x0F];

    static int[16] prodosOrder = [
        0x00, 0x08, 0x01, 0x09, 0x02, 0x0A, 0x03, 0x0B,
        0x04, 0x0C, 0x05, 0x0D, 0x06, 0x0E, 0x07, 0x0F];

    static ubyte[3] DATA_PROLOGUE = [0xD5, 0xAA, 0xAD];
    static ubyte[3] ADDR_PROLOGUE = [0xD5, 0xAA, 0x96];
    static ubyte[3] EPILOGUE = [0xDE, 0xAA, 0xEB];

    static ubyte[0x40] diskByte = [
        0x96, 0x97, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F, 0xA6,
        0xA7, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF, 0xB2, 0xB3,
        0xB4, 0xB5, 0xB6, 0xB7, 0xB9, 0xBA, 0xBB, 0xBC,
        0xBD, 0xBE, 0xBF, 0xCB, 0xCD, 0xCE, 0xCF, 0xD3,
        0xD6, 0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE,
        0xDF, 0xE5, 0xE6, 0xE7, 0xE9, 0xEA, 0xEB, 0xEC,
        0xED, 0xEE, 0xEF, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6,
        0xF7, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF
    ];

    static int[0x70] memByte;

    static const NUM_SECTORS = 16;
    static const SECTOR_LENGTH = 256;
    static const DATA_FIELD_LENGTH = 342;

    static this()
    {
        memByte[0..0x70] = -1;
        for (int i = 0; i < 0x40; ++i)
        {
            memByte[diskByte[i] - 0x96] = i;
        }
    }

    class VolumeException : Exception
    {
        DSKImage img;

        this()
        {
            super("");
            img = this.outer;
        }

        void ignoreVolume()
        {
            img.preserveVolume = false;
        }
    }

    class DSKException : Exception
    {
        this() { super(""); }
    }

    uint dataOffset;
    ubyte[] mbHeader;
    bool isProdos;
    ubyte volume;
    bool preserveVolume;

    this(TwoappleFile checkFile)
    {
        super(checkFile);
        volume = 0xFE;
        preserveVolume = true;
    }

    this(TwoappleFile checkFile, InternalImage data)
    {
        super(checkFile, data);
    }

    void checkMacBinary(File stream)
    {
        if (imgFile.fileSize() == 143488)
        {
            dataOffset = 128;
            mbHeader = new ubyte[128];
            stream.read(mbHeader);
        }
    }

    bool prodosOrderProdos(File stream)
    {
        ubyte checkLo, checkHi;
        ushort check1, check2, match1, match2;
        for (int s = 2; s <= 5; ++s)
        {
            stream.seekSet(s * 512 + dataOffset);
            stream.read(checkLo); stream.read(checkHi);
            check1 = (checkHi << 8) | checkLo;
            stream.read(checkLo); stream.read(checkHi);
            check2 = (checkHi << 8) | checkLo;
            match1 = ((s == 2) ? 0 : (s - 1));
            match2 = ((s == 5) ? 0 : (s + 1));
            if ((check1 != match1) || (check2 != match2)) return false;
        }
        return true;
    }

    bool prodosOrderDos(File stream)
    {
        ubyte check;
        for (int s = 5; s <= 13; ++s)
        {
            stream.seekSet(dataOffset + 0x11002 + (s * 256));
            stream.read(check);
            if (check != (14 - s)) return false;
        }
        return true;
    }

    void loadTrack(File stream, int track)
    {
        uint offset;
        ubyte[] trackData = imgData.trackData[track];

        void loadBytes(ubyte[] data)
        {
            uint len = data.length;
            trackData[offset..offset+len] = data;
            offset += len;
        }

        void loadByte(ubyte data, uint len = 1)
        {
            trackData[offset..offset+len] = data;
            offset += len;
        }

        void loadAddrField(ubyte sector)
        {
            void encode44(ubyte val)
            {
                loadByte((((val >> 1) & 0x55) | 0xAA));
                loadByte(((val & 0x55) | 0xAA));
            }

            loadBytes(ADDR_PROLOGUE[0..3]);

            encode44(0xFE);     // volume
            encode44(track);
            encode44(sector);
            encode44(0xFE ^ track ^ sector);    // check byte

            loadBytes(EPILOGUE[0..2]);
        }

        void loadDataField(ubyte sector)
        {
            loadBytes(DATA_PROLOGUE[0..3]);
            loadBytes(loadSector(stream, track, sector));
            loadBytes(EPILOGUE[0..3]);
        }

        loadByte(0xFF, 48);  // Load gap 1

        for (ubyte sector = 0; sector < NUM_SECTORS; ++sector)
        {
            loadAddrField(sector);
            loadByte(0xFF, 6);  // Load gap 2
            loadDataField(sector);
            loadByte(0xFF, 45); // Load gap 3
        }
    }

    ubyte[] loadSector(File stream, int track, int sector)
    {
        ubyte[] sectorData = new ubyte[SECTOR_LENGTH];
        ubyte[] trackData = new ubyte[DATA_FIELD_LENGTH + 1];

        stream.seekSet(dataOffset + (track * (NUM_SECTORS * SECTOR_LENGTH)) +
                (isProdos ? (prodosOrder[sector] * SECTOR_LENGTH) :
                            (dosOrder[sector] * SECTOR_LENGTH)));
        stream.read(sectorData);

        int x = 0x55;
        ubyte y = 2;
        uint val;
    
        // Translate 256 bytes of data into 342 6-bit index values

        while(true)
        {
            --y;
            val = sectorData[y];

            // index values 0 through 85 are composed of a combination
            // of the two least significant bits from each data value
            //     index 85 from data 85, 171, 1
            //     index 84 from data 84, 170, 0
            //     index 83 from data 83, 169, 255
            //     ...
            //     index  0 from data  0,  86, 172

            trackData[x] =
                (trackData[x] << 2) |
                (((val & 0x01) << 1) | ((val & 0x02) >> 1));

            // index values 86 through 341 are composed of the six
            // most significant bits of data values 0 through 255

            trackData[y + 0x56] = (val >> 2);

            --x;
            if (x >= 0x00) continue;
            x = 0x55;
            if (y == 0) break;
        }

        // Translate the 342 index values into 343 disk bytes
        // (where the 343rd disk byte is a check byte)

        ubyte lastByte = 0, indexByte;
        for (int i = 0; i < DATA_FIELD_LENGTH; ++i)
        {
            indexByte = trackData[i] & 0x3F;
            trackData[i] = diskByte[lastByte ^ indexByte];
            lastByte = indexByte;
        }
        trackData[DATA_FIELD_LENGTH] = diskByte[lastByte];

        return trackData;
    }

    void load()
    {
        File stream = new File(imgFile.fileName);

        checkMacBinary(stream);
        isProdos = (prodosOrderDos(stream) || prodosOrderProdos(stream));
        stream.seekSet(dataOffset);

        for (int t = 0; t < InternalImage.NUM_TRACKS; ++t)
            loadTrack(stream, t);
        stream.close();
    }

    bool writeTrack(int track, ubyte[] saveData)
    {
        uint offset;
        ubyte sector;
        int expectedSector = -1;
        bool sectorsWritten[] = new bool[NUM_SECTORS];
        bool sectorsSeen[] = new bool[NUM_SECTORS];
        ubyte sectorData[] = new ubyte[DATA_FIELD_LENGTH];

        ubyte[] trackData = imgData.trackData[track];

        ubyte nextData(uint delta)
        {
            return trackData[(offset + delta) % InternalImage.TRACK_LENGTH];
        }

        bool dataMatches(uint delta, ubyte[] data)
        {
            for (int b = 0; b < data.length; ++b)
            {
                if (nextData(delta + b) != data[b])
                    return false;
            }
            return true;
        }

        bool findAddressField()
        {
            ubyte decode44(ubyte first, ubyte second)
            {
                return ((first & 0x55) << 1) | (second & 0x55);
            }

            bool testAddressField()
            {
                ubyte check, storedVolume, storedTrack;

                storedVolume = decode44(nextData(3), nextData(4));
                if (storedVolume != 0xFE) volume = storedVolume;

                storedTrack = decode44(nextData(5), nextData(6));
                sector = decode44(nextData(7), nextData(8));
                check = decode44(nextData(9), nextData(10));

                if (expectedSector == -1)
                    expectedSector = sector;
                else
                    expectedSector = (expectedSector + 1) % NUM_SECTORS;

                offset += 13;

                return (storedTrack == track) && (sector < NUM_SECTORS) &&
                    (expectedSector == sector) &&
                    (check == (storedVolume ^ storedTrack ^ sector)) &&
                    (!sectorsSeen[sector]);
            }

            while (offset < InternalImage.TRACK_LENGTH)
            {
                if (dataMatches(0, ADDR_PROLOGUE) &&
                    dataMatches(11, EPILOGUE[0..2]))
                    return testAddressField();
                else
                    ++offset;
            }
            return false;
        }

        bool findDataField()
        {
            offset %= InternalImage.TRACK_LENGTH;
            while (offset < InternalImage.TRACK_LENGTH)
            {
                if (dataMatches(0, DATA_PROLOGUE) &&
                    dataMatches(346, EPILOGUE))
                {
                    offset += 3;
                    sectorsSeen[sector] = true;
                    return true;
                }
                else
                    ++offset;
            }
            return false;
        }

        void writeDataBlock()
        {
            uint sectorFirst = (InternalImage.TRACK_LENGTH - offset);
            if (sectorFirst > DATA_FIELD_LENGTH)
                sectorFirst = DATA_FIELD_LENGTH;
            uint sectorSecond = DATA_FIELD_LENGTH - sectorFirst;

            sectorData[0..sectorFirst] = trackData[offset..offset+sectorFirst];
            if (sectorSecond)
            {
                sectorData[sectorFirst..sectorFirst+sectorSecond] =
                    trackData[0..sectorSecond];
            }

            sectorsWritten[sector] =
                writeSector(saveData, sectorData, sector);
        }

        while (true)
        {
            if (!findAddressField()) break;
            if (!findDataField()) break;
            writeDataBlock();
        }

        for (int sect = 0; sect < NUM_SECTORS; ++sect)
        {
            if (!sectorsWritten[sect]) return false;
        }

        return true;
    }

    bool writeSector(ubyte[] saveData, ubyte[] sectorData, ubyte sector)
    {
        uint dskOffset = (isProdos ? (prodosOrder[sector] * SECTOR_LENGTH) :
                                     (dosOrder[sector] * SECTOR_LENGTH));
        ubyte[] dskData = saveData[dskOffset..dskOffset+SECTOR_LENGTH];

        // Translate the 342 disk bytes into 6-bit index values
        
        ubyte[] indexData = new ubyte[DATA_FIELD_LENGTH];

        int lastByte = 0;
        ubyte nibByte;
        for (int i = 0; i < 0x156; ++i)
        {
            if (sectorData[i] < 0x96) return false;
            nibByte = memByte[sectorData[i] - 0x96];
            if (nibByte == -1) return false;
            indexData[i] = lastByte ^ nibByte;
            lastByte = indexData[i];
        }

        // TODO: verify the checksum
        // Translate the 342 index values into 256 bytes

        ubyte y = 0;
        uint x = 0;
        while(true)
        {
            // The lower two bits of each byte are taken from
            // a pair of bits from index values 0 through 85

            dskData[y] =
                ((indexData[x] & 0x01) << 1) | ((indexData[x] & 0x02) >> 1);
            indexData[x] >>= 2;

            // The upper six bits of bytes 0 through 255 are taken
            // from the lower six bits of index values 86 through 342.

            dskData[y] |= (indexData[y + 0x56] << 2);
            ++y;
            if (y == 0) break;
            ++x;
            if (x == 0x56) x = 0;
        }

        return true;
    }

    void writeOut(File stream)
    {
        ubyte[][] saveData;
        saveData = new ubyte[][InternalImage.NUM_TRACKS];

        for (int t = 0; t < InternalImage.NUM_TRACKS; ++t)
        {
            saveData[t] = new ubyte[NUM_SECTORS * SECTOR_LENGTH];
            if (!(writeTrack(t, saveData[t])))
                throw new DSKException();
        }
        if ((volume != 0xFE) && preserveVolume)
            throw new VolumeException();

        if (mbHeader.length != 0) stream.write(mbHeader);
        for (int t = 0; t < InternalImage.NUM_TRACKS; ++t)
            stream.write(saveData[t]);
    }
}

class NIBImage : ExternalImage
{
    this(TwoappleFile checkFile) { super(checkFile); }

    this(TwoappleFile checkFile, InternalImage data)
    {
        super(checkFile, data);
    }

    void load()
    {
        File stream = new File(imgFile.fileName);
        for (int t = 0; t < InternalImage.NUM_TRACKS; ++t)
        {
            stream.read(imgData.trackData[t]);
        }
        stream.close();
    }

    void writeOut(File stream)
    {
        for (int t = 0; t < InternalImage.NUM_TRACKS; ++t)
        {
            stream.write(imgData.trackData[t]);
        }
    }
}

