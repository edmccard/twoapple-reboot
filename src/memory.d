/+
 + memory.d
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

import std.string;

class Memory
{
	final ushort baseAddress;
	final uint blockSize;
    string debugName;

	this(ushort baseAddr, uint size)
	{
		assert(baseAddr + size <= 0x10000,
                "Memory block larger than 64K");
		assert((baseAddr % 0x0100) == 0,
                "Memory block does not start on page boundary");
		assert((size % 0x0100) == 0,
                "Memory block does not end on page boundary");
		baseAddress = baseAddr;
		blockSize = size;
	}

	abstract ubyte read(ushort addr);
	abstract void write(ushort addr, ubyte val);
    void reboot() {}
}

class ZeroMem : Memory
{
    this(ushort baseAddr, uint size)
    {
        super(baseAddr, size);
    }

    ubyte read(ushort addr) { return 0; }
    void write(ushort addr, ubyte val) {}
}

class DataMem : Memory
{
	ubyte* data;
	ubyte data_[];

	this(ushort baseAddr, uint size)
	{
		super(baseAddr, size);
	}

	ubyte read(ushort addr)
	{
		return data[addr - baseAddress];
	}

	void write(ushort addr, ubyte val)
	{
		data[addr - baseAddress] = val;
	}
}

class PrimaryMem : DataMem
{
	this(ushort baseAddr, uint size)
	{
		super(baseAddr, size);
	}

    void reboot()
    {
		data_ = new ubyte[blockSize];
		data = data_.ptr;
    }
}

class Rom : DataMem
{
    this(ushort baseAddr, uint size, ubyte[] rom)
    {
        super(baseAddr, size);
        data_ = rom;
        data = data_.ptr;
    }

    void write(ushort addr, ubyte val) {}
}

class SliceMem : DataMem
{
    DataMem otherMem;

	this(ushort baseAddr, uint size, DataMem other)
	{
		super(baseAddr, size);
        otherMem = other;
        debugName = otherMem.debugName;
	}

    void reboot()
    {
        int otherStart = baseAddress - otherMem.baseAddress;
        int otherEnd = otherStart + blockSize;
        assert((otherStart >= 0) && (otherEnd <= otherMem.blockSize),
                "Memory slice out of range");
        data_ = otherMem.data_[otherStart..otherEnd];
		data = data_.ptr;
    }
}

class BankMem : DataMem
{
    ubyte[][] banks;
    string[] debugNames;

	this(ushort baseAddr, uint size, uint numBanks)
    {
        super(baseAddr, size);
        banks.length = numBanks;
        debugNames.length = numBanks;
    }

    void setDebugNames(string name)
    {
        if (debugNames.length > 1)
        {
            for (int n = 0; n < debugNames.length; ++n)
            {
                debugNames[n] = name ~ " bank " ~ std.string.toString(n);
            }
        }
        else
        {
            debugNames[0] = name;
        }
    }

    void reboot()
    {
        for (int b = 0; b < banks.length; ++b)
        {
            banks[b] = new ubyte[blockSize];
        }
        setBank(0);
    }

    void setBank(int bankNum)
    {
        data_ = banks[bankNum];
        data = data_.ptr;
        debugName = debugNames[bankNum];
    }
}

class SubBankMem : DataMem
{
    ubyte[][][] banks;
    string[][] debugNames;
    int primaryBank, subBank;
    int numBanks, numSubBanks;

    this(ushort baseAddr, uint size, uint numBanks_, uint numSubBanks_)
    {
        super(baseAddr, size);
        banks.length = numBanks = numBanks_;
        debugNames.length = numBanks;
        numSubBanks = numSubBanks_;
        for (int b = 0; b < numBanks; ++b)
        {
            banks[b].length = numSubBanks_;
            debugNames[b].length = numSubBanks_;
        }
    }

    void setDebugNames(string[] names)
    {
        for (int b = 0; b < numBanks; ++b)
        {
            for (int n = 0; n < numSubBanks; ++n)
            {
                debugNames[b][n] = names[b] ~ " bank " ~
                    std.string.toString(n);
            }
        }
    }

    void reboot()
    {
        for (int b = 0; b < banks.length; ++b)
        {
            for (int s = 0; s < banks[b].length; ++s)
            {
                banks[b][s] = new ubyte[blockSize];
            }
        }
        primaryBank = subBank = 0;
        setSubBank(0);
        setPrimaryBank(0);
    }

    void setPrimaryBank(uint bank)
    {
        primaryBank = bank;
        data_ = banks[bank][subBank];
        data = data_.ptr;
        debugName = debugNames[bank][subBank];
    }

    void setSubBank(uint bank)
    {
        subBank = bank;
        data_ = banks[primaryBank][bank];
        data = data_.ptr;
        debugName = debugNames[primaryBank][bank];
    }
}

alias ubyte delegate(ushort) ReadFunc;
alias void delegate(ushort, ubyte) WriteFunc;

class AddressDecoder
{
	ReadFunc readPages[256];
	WriteFunc writePages[256];
    Memory readResponders[256];
    Memory writeResponders[256];

	void nullWrite(ushort addr, ubyte val) {}

    public:

    ubyte delegate(ushort) nullRead;

    void installSwitches(SoftSwitchPage switches)
    {
		readPages[0xC0] = &switches.read;
		writePages[0xC0] = &switches.write;
    }

	ubyte read(ushort addr)
	{
		return readPages[addr >> 8](addr);
	}

	void write(ushort addr, ubyte val)
	{
		writePages[addr >> 8](addr, val);
	}

    // XXX address read only/write only code
	void install(Memory block, bool forRead = true, bool forWrite = true)
	{
		uint base = block.baseAddress >> 8;
		uint size = block.blockSize >> 8;
        for (uint pg = base; pg < base + size; ++pg)
        {
            if (pg == 0xC0) continue;

    		if (forRead)
            {
                readPages[pg] = &block.read;
                readResponders[pg] = block;
            }
    		if (forWrite)
            {
                writePages[pg] = &block.write;
                writeResponders[pg] = block;
            }
        }
	}

    void installNull(uint baseAddress, uint blockSize, bool forRead = true,
            bool forWrite = true)
    {
		uint base = baseAddress >> 8;
		uint size = blockSize >> 8;
        for (uint pg = base; pg < base + size; ++pg)
        {
            if (pg == 0xC0) continue;
            if (forRead)
            {
                readPages[pg] = nullRead;
                readResponders[pg] = null;
            }
            if (forWrite)
            {
                writePages[pg] = &nullWrite;
                writeResponders[pg] = null;
            }
        }
    }

	void installRead(Memory block)
	{
		install(block, true, false);
	}

	void installWrite(Memory block)
	{
		install(block, false, true);
	}

    string memoryReadName(ushort addr)
    {
        int page = addr >> 8;
        if (readResponders[page] is null) return null;
        return readResponders[page].debugName;
    }

    Memory readResponse(int page)
    {
        return readResponders[page];
    }

    Memory writeResponse(int page)
    {
        return writeResponders[page];
    }
}

class SoftSwitchPage : Memory
{
    private:

	ReadFunc[256] readSwitches;
    ubyte[256] bitsReturned;
	WriteFunc[256] writeSwitches;

    ubyte nullRead(ushort addr) { return 0; }
	void nullWrite(ushort addr, ubyte val) {}

    public:

    ReadFunc floatingBus;

	this()
	{
        super(0xC000, 0x0100);
		for (int addr = 0xC000; addr < 0xC100; ++addr)
		{
			writeSwitches[addr & 0xFF] = &nullWrite;
		}
	}

    void setFloatingBus(ReadFunc floatingBus_)
    {
        floatingBus = floatingBus_;
        for (int addr = 0xC000; addr < 0xC100; ++addr)
        {
            if (readSwitches[addr & 0xFF] is null)
                readSwitches[addr & 0xFF] = floatingBus;
        }
    }

	void setReadSwitch(ushort addr, ReadFunc read_, ubyte bitsReturned_)
	{
		readSwitches[addr - 0xC000] = read_;
        bitsReturned[addr - 0xC000] = bitsReturned_;
	}

    void setR0Switch(ushort addr, ReadFunc read_)
    {
        setReadSwitch(addr, read_, 0);
    }

    void setR7Switch(ushort addr, ReadFunc read_)
    {
        setReadSwitch(addr, read_, 0x80);
    }

    void setRSwitch(ushort addr, ReadFunc read_)
    {
        setReadSwitch(addr, read_, 0xFF);
    }

	void setWSwitch(ushort addr, WriteFunc write_)
	{
		writeSwitches[addr - 0xC000] = write_;
	}

	final ubyte read(ushort addr)
	{
        ubyte ret = readSwitches[addr - 0xC000](addr);
        ubyte mask = bitsReturned[addr - 0xC000];
        if (mask < 0xFF)
        {
            ret = (ret & mask) | (floatingBus(addr) & (mask ^ 0xFF));
        }
        return ret;
	}

	final void write(ushort addr, ubyte val)
	{
		writeSwitches[addr - 0xC000](addr, val);
	}
}

