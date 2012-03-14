/+
 + peripheral/saturn128.d
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

module peripheral.saturn128;

import device.base;
import peripheral.base;
import memory;

string MakeSaturnSwitches()
{
    string saturnSwitches;
    for (int sw = 0xC080; sw <= 0xC08F; ++sw)
    {
        saturnSwitches ~= "void access" ~ hex4Digits(sw) ~ "()\n{\n";
        if (sw & 0b00000100)
            saturnSwitches ~= MakeBankSwitch(sw);
        else
            saturnSwitches ~= MakeModeSwitch(sw);
        saturnSwitches ~= "}\n";
    }
    return saturnSwitches;
}

string MakeModeSwitch(int sw)
{
    string modeSwitch;
    modeSwitch ~= "set4KBank(" ~ hex2Digits((sw & 0b1000) >> 3) ~ ");\n";
    modeSwitch ~= (sw & 0b1) ? "tryWriteEnable();\n" : "writeProtect();\n";
    modeSwitch ~= (((sw & 0b11) == 0b00) || ((sw & 0b11) == 0b11)) ?
        "readRAM();\n" : "readROM();\n";
    return modeSwitch;
}

string MakeBankSwitch(int sw)
{
    int bank = (sw & 0b11) | ((sw & 0b1000) >> 1);
    return "set16KBank(" ~ hex2Digits(bank) ~ ");\n";
}

class Saturn128 : Peripheral
{
    AddressDecoder decoder;

	ReadFunc origRead;
	WriteFunc origWrite;
    bool preWrite;
    bool readEn, writeEn;
    BankMem e000ffff;
    SubBankMem d000dfff;

    this()
    {
        e000ffff = new BankMem(0xE000, 0x2000, 16);
        d000dfff = new SubBankMem(0xD000, 0x1000, 16, 2);
    }

    void init(AddressDecoder addrDecode, ReadFunc read, WriteFunc write)
    {
        decoder = addrDecode;
        origRead = read;
        origWrite = write;
    }

    void reboot()
    {
        preWrite = false;
        e000ffff.reboot();
        d000dfff.reboot();
        readEn = true;
        readROM();
        writeEn = true;
        writeProtect();
    }

    void writeProtect()
    {
        if (writeEn)
        {
            decoder.writePages[0xD0..0x100] = origWrite;
        }
        preWrite = false;
        writeEn = false;
    }

    void tryWriteEnable()
    {
        if (preWrite) writeEnable();
        preWrite = true;
    }

    void writeEnable()
    {
        if (!writeEn)
        {
            decoder.installWrite(e000ffff);
            decoder.installWrite(d000dfff);
        }
        writeEn = true;
    }

    void readRAM()
    {
        if (!readEn)
        {
            decoder.installRead(e000ffff);
            decoder.installRead(d000dfff);
        }
        readEn = true;
    }

    void readROM()
    {
        if (readEn)
        {
            decoder.readPages[0xD0..0x100] = origRead;
        }
        readEn = false;
    }

    void set16KBank(int bank)
    {
        e000ffff.setBank(bank);
        d000dfff.setPrimaryBank(bank);
    }

    void set4KBank(int bank)
    {
        d000dfff.setSubBank(bank);
    }

    mixin(MakeSaturnSwitches());
    
    mixin(InitSwitches("", [
        mixin(MakeSwitch([0xC080], "R0W", "accessC080")),
        mixin(MakeSwitch([0xC081], "R0W", "accessC081")),
        mixin(MakeSwitch([0xC082], "R0W", "accessC082")),
        mixin(MakeSwitch([0xC083], "R0W", "accessC083")),
        mixin(MakeSwitch([0xC084], "R0W", "accessC084")),
        mixin(MakeSwitch([0xC085], "R0W", "accessC085")),
        mixin(MakeSwitch([0xC086], "R0W", "accessC086")),
        mixin(MakeSwitch([0xC087], "R0W", "accessC087")),
        mixin(MakeSwitch([0xC088], "R0W", "accessC088")),
        mixin(MakeSwitch([0xC089], "R0W", "accessC089")),
        mixin(MakeSwitch([0xC08A], "R0W", "accessC08A")),
        mixin(MakeSwitch([0xC08B], "R0W", "accessC08B")),
        mixin(MakeSwitch([0xC08C], "R0W", "accessC08C")),
        mixin(MakeSwitch([0xC08D], "R0W", "accessC08D")),
        mixin(MakeSwitch([0xC08E], "R0W", "accessC08E")),
        mixin(MakeSwitch([0xC08F], "R0W", "accessC08F"))
    ]));
}
