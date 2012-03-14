/+
 + peripheral/langcard.d
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

module peripheral.langcard;

import peripheral.base;
import device.base;
import memory;

private:

string MakeRAMSwitches(bool isIIe)
{
    string ramSwitches;
    for (int sw = 0xC080; sw <= 0xC08F; ++sw)
    {
        ramSwitches ~= "void read" ~ hex4Digits(sw) ~ "()\n{\n" ~
            MakeRAMSwitch(sw, false, isIIe) ~ "}\n";
        ramSwitches ~= "void write" ~ hex4Digits(sw) ~ "()\n{\n" ~
            MakeRAMSwitch(sw, true, isIIe) ~ "}\n";
    }
    return ramSwitches;
}

string MakeRAMSwitch(int sw, bool write, bool isIIe)
{
    string ramSwitch;

    ramSwitch ~= CallRAMFunction(isIIe, "setBank(" ~
            hex4Digits((sw & 0b1000) >> 3 ) ~ ")") ~ "\n";

    if (((sw & 0b11) == 0b11) || ((sw & 0b11) == 0b00))
        ramSwitch ~= CallRAMFunction(isIIe, "enableRead()") ~ "\n";
    else
        ramSwitch ~= CallRAMFunction(isIIe, "disableRead()") ~ "\n";

    if ((sw & 0b1) == 0b0)
        ramSwitch ~= CallRAMFunction(isIIe, "clearPreWrite()") ~ "\n" ~
            CallRAMFunction(isIIe, "disableWrite()") ~ "\n";
    else
    {
        if (write)
            ramSwitch ~= CallRAMFunction(isIIe, "clearPreWrite()") ~ "\n";
        else
            ramSwitch ~= CallRAMFunction(isIIe, "checkEnableWrite()") ~ "\n";
    }

    return ramSwitch;
}

string CallRAMFunction(bool isIIe, string func)
{
    if (!isIIe)
    {
        return "implementation." ~ func ~ ";";
    }
    else
    {
        return "onboard." ~ func ~ ";\n" ~
            "if (auxslot !is null) auxslot." ~ func ~ ";";
    }
}

static const string[][] langcardSwitches = [
        mixin(MakeSwitch([0xC080], "R0", "readC080")),
        mixin(MakeSwitch([0xC081], "R0", "readC081")),
        mixin(MakeSwitch([0xC082], "R0", "readC082")),
        mixin(MakeSwitch([0xC083], "R0", "readC083")),
        mixin(MakeSwitch([0xC084], "R0", "readC084")),
        mixin(MakeSwitch([0xC085], "R0", "readC085")),
        mixin(MakeSwitch([0xC086], "R0", "readC086")),
        mixin(MakeSwitch([0xC087], "R0", "readC087")),
        mixin(MakeSwitch([0xC088], "R0", "readC088")),
        mixin(MakeSwitch([0xC089], "R0", "readC089")),
        mixin(MakeSwitch([0xC08A], "R0", "readC08A")),
        mixin(MakeSwitch([0xC08B], "R0", "readC08B")),
        mixin(MakeSwitch([0xC08C], "R0", "readC08C")),
        mixin(MakeSwitch([0xC08D], "R0", "readC08D")),
        mixin(MakeSwitch([0xC08E], "R0", "readC08E")),
        mixin(MakeSwitch([0xC08F], "R0", "readC08F")),
        mixin(MakeSwitch([0xC080], "W", "writeC080")),
        mixin(MakeSwitch([0xC081], "W", "writeC081")),
        mixin(MakeSwitch([0xC082], "W", "writeC082")),
        mixin(MakeSwitch([0xC083], "W", "writeC083")),
        mixin(MakeSwitch([0xC084], "W", "writeC084")),
        mixin(MakeSwitch([0xC085], "W", "writeC085")),
        mixin(MakeSwitch([0xC086], "W", "writeC086")),
        mixin(MakeSwitch([0xC087], "W", "writeC087")),
        mixin(MakeSwitch([0xC088], "W", "writeC088")),
        mixin(MakeSwitch([0xC089], "W", "writeC089")),
        mixin(MakeSwitch([0xC08A], "W", "writeC08A")),
        mixin(MakeSwitch([0xC08B], "W", "writeC08B")),
        mixin(MakeSwitch([0xC08C], "W", "writeC08C")),
        mixin(MakeSwitch([0xC08D], "W", "writeC08D")),
        mixin(MakeSwitch([0xC08E], "W", "writeC08E")),
        mixin(MakeSwitch([0xC08F], "W", "writeC08F"))
];

public:

class HighRam
{
    AddressDecoder decoder;

	ReadFunc origRead;
	WriteFunc origWrite;

    Memory lowerChunk, upperChunk;

    bool preWrite;
    bool readEn, writeEn;
    bool enabled;
    int current4KBank;

    this()
    {
        initMemory();
    }

    abstract void initMemory();

    void init(AddressDecoder addrDecode, ReadFunc read, WriteFunc write)
    {
        decoder = addrDecode;
        origRead = read;
        origWrite = write;
    }

    void reboot()
    {
        preWrite = false;
        lowerChunk.reboot();
        upperChunk.reboot();
        current4KBank = 0;
        forceReadDisable();
        forceWriteEnable();
    }

    void clearPreWrite()
    {
        preWrite = false;
    }

    void forceReadDisable()
    {
        readEn = true;
        disableRead();
    }

    void forceReadEnable()
    {
        readEn = false;
        enableRead();
    }

    void forceWriteEnable()
    {
        writeEn = false;
        enableWrite();
    }

    void enableRead()
    {
        if ((!readEn) && enabled)
        {
            decoder.installRead(lowerChunk);
            decoder.installRead(upperChunk);
        }
        readEn = true;
    }

    void disableRead()
    {
        if (readEn && enabled)
        {
            decoder.readPages[0xD0..0x100] = origRead;
        }
        readEn = false;
    }

    void checkEnableWrite()
    {
        if (preWrite) enableWrite();
        preWrite = true;
    }

    void enableWrite()
    {
        if ((!writeEn) && enabled)
        {
            decoder.installWrite(lowerChunk);
            decoder.installWrite(upperChunk);
        }
        writeEn = true;
    }

    void disableWrite()
    {
        if (writeEn && enabled)
        {
            decoder.writePages[0xD0..0x100] = origWrite;
        }
        writeEn = false;
    }

    abstract void setLowerBank(int bank);

    void setBank(int bank)
    {
        setLowerBank(bank);
        current4KBank = bank;
    }
}

class HighRam_II : HighRam
{
    PrimaryMem e000ffff;
    BankMem d000dfff;

    this()
    {
        super();
        enabled = true;
    }

    void initMemory()
    {
        d000dfff = new BankMem(0xD000, 0x1000, 2);
        e000ffff = new PrimaryMem(0xE000, 0x2000);
        lowerChunk = d000dfff;
        upperChunk = e000ffff;
    }

    void setDebugName(string name)
    {
        e000ffff.debugName = name;
        d000dfff.setDebugNames(name);
    }

    void setLowerBank(int bank)
    {
        d000dfff.setBank(bank);
    }
}

class HighRam_IIe : HighRam
{
    bool isOnboard;
    int numBanks;
    SubBankMem d000dfff;
    BankMem e000ffff;

    this(bool isOnboard_, int banks)
    {
        numBanks = banks;
        super();
        isOnboard = isOnboard_;
    }

    void initMemory()
    {
        d000dfff = new SubBankMem(0xD000, 0x1000, numBanks, 2);
        e000ffff = new BankMem(0xE000, 0x2000, numBanks);
        lowerChunk = d000dfff;
        upperChunk = e000ffff;
    }

    void setLowerBank(int bank)
    {
        d000dfff.setSubBank(bank);
    }

    void resetBanks()
    {
        e000ffff.setBank(0);
        d000dfff.setPrimaryBank(0);
        d000dfff.setSubBank(0);
    }

    void enable(bool newState)
    {
        if (enabled == newState) return;
        enabled = newState;
        if (newState)
        {
            if (writeEn) forceWriteEnable();
            if (readEn) forceReadEnable();
        }
    }

    void setDebugName(string name)
    {
        string[] names;
        names.length = numBanks;
        if (numBanks > 1)
        {
            for (int b = 0; b < numBanks; ++b)
                names[b] = name ~ " " ~ std.string.toString(b);
        }
        else
        {
            names[0] = name;
        }
        e000ffff.setDebugNames(name);
        d000dfff.setDebugNames(names);
    }

    void reboot()
    {
        enabled = isOnboard;
        super.reboot();
    }

    void reset()
    {
        enabled = isOnboard;
        preWrite = false;
        resetBanks();
        current4KBank = 0;
        disableRead();
        enableWrite();
    }
}

class HighRam_Null : HighRam_IIe
{
    this()
    {
        super(false, 0);
    }

    void initMemory()
    {
        lowerChunk = new ZeroMem(0xD000, 0x1000);
        upperChunk = new ZeroMem(0xE000, 0x2000);
    }

    void setLowerBank(int bank) {}
    void resetBanks() {}
}

class LanguageCard : Peripheral
{
    HighRam_II implementation;

    mixin(MakeRAMSwitches(false));
    mixin(InitSwitches("", langcardSwitches));

    this()
    {
        implementation = new HighRam_II();
        implementation.setDebugName("Language card");
    }

    void reboot()
    {
        implementation.reboot();
    }
}

class LanguageCard_IIe
{
    HighRam_IIe onboard, auxslot;
    ubyte delegate() kbdLatch;

    mixin(MakeRAMSwitches(true));
    mixin(InitSwitches("", langcardSwitches ~ [
        mixin(MakeSwitch([0xC011], "R", "readBank2Switch")),
        mixin(MakeSwitch([0xC012], "R", "readReadSwitch"))
    ]));

    this()
    {
        onboard = new HighRam_IIe(true, 1);
        onboard.setDebugName("High RAM");
    }

    void init(AddressDecoder addrDecode, ReadFunc read, WriteFunc write)
    {
        onboard.init(addrDecode, read, write);
        auxslot.init(addrDecode, read, write);
    }

    void reboot()
    {
        onboard.reboot();
        auxslot.reboot();
    }

    void reset()
    {
        onboard.reset();
        auxslot.reset();
    }

    void enableAuxSlot(bool isAuxSlot)
    {
        onboard.enable(!isAuxSlot);
        auxslot.enable(isAuxSlot);
    }

    ubyte readBank2Switch()
    {
        return kbdLatch() | ((onboard.current4KBank == 0) ? 0x80 : 0x00);
    }

    ubyte readReadSwitch()
    {
        return kbdLatch() | (onboard.readEn ? 0x80 : 0x00);
    }
}
