module test.base;


import std.conv, std.exception, std.string, std.traits;


public import d6502.nmosundoc : NmosUndoc;
public import d6502.cmos : Cmos;


template isNMOS(T)
{
    enum isNMOS = __traits(hasMember, T, "_isNMOS");
}

template isCMOS(T)
{
    enum isCMOS = __traits(hasMember, T, "_isCMOS");
}

template isCpu(T)
{
    enum isCpu = __traits(hasMember, T, "_isCpuBase");
}

template isStrict(T)
{
    enum isStrict = __traits(hasMember, T, "_isStrict");
}

template isCumulative(T)
{
    enum isCumulative = __traits(hasMember, T, "_isCumulative");
}


class TestException : Exception { this(string msg) { super(msg); } }


struct Block
{
    ushort base;
    ubyte[] data;
}

/* Emulates zero page, stack, and 3 additional pages starting at a
 * user-defined address. Accesses outside the defined address space
 * raise an exception.
 */
struct TestMemory
{
    ubyte[0x200] data1;
    ubyte[0x300] data2;
    immutable ushort data2_base;
    immutable size_t data2_max;

    this(Block[] blocks ...)
    {
        size_t last_1, last_2;
        foreach (block; blocks)
        {
            auto base = block.base;
            auto data = block.data;
            if (base < 0x200)
            {
                enforce(base >= last_1,
                        format("Overlapping address %0.4x", base));
                enforce(base + data.length <= 0x200,
                        format("Address out of bounds %0.4x", base));
                last_1 = base + data.length;
                data1[base..last_1] = data[];
            }
            else
            {
                if (!data2_base)
                {
                    last_2 = data2_base = base;
                    data2_max = base + 0x300;
                }
                enforce(base >= last_2,
                        format("Overlapping address %0.4x", base));
                enforce(base + data.length <= data2_max,
                        format("Address  out of bounds %0.4x", base));
                last_2 = base + data.length;
                data2[base-data2_base..last_2-data2_base] = data[];
            }
        }
        enforce(data2_base, "Missing memory > 0x0200");
    }

    ubyte read(ushort addr)
    {
        if (addr < 0x0200)
            return data1[addr];
        else if (addr >= data2_base && addr < data2_max)
            return data2[addr - data2_base];
        else
            throw new TestException(format("read %0.4x", addr));
    }

    void write(ushort addr, ubyte val)
    {
        if (addr < 0x0200)
            data1[addr] = val;
        else if (addr >= data2_base && addr < data2_max)
            data2[addr - data2_base] = val;
        else
            throw new TestException(format("write %0.4x", addr));
    }

    ubyte opIndex(size_t i1)
    {
        auto addr = cast(ushort)i1;
        enforce(addr < 0x0200 || (addr >= data2_base && addr < data2_max),
                "Read out of bounds");
        return read(addr);
    }
}


T makeCpu(T)(ref TestMemory mem)
if (isCpu!T)
{
    static if (isCumulative!T) void tick(int cycles) {}
    else void tick() {}

    auto cpu = new T();
    cpu.memoryRead = &mem.read;
    cpu.memoryWrite = &mem.write;
    cpu.tick = &tick;
    return cpu;
}


struct Ref(T)
if (isPointer!T)
{
    private const(T) data;
    this(T ptr) { data = ptr; }
    auto deref() { return *data; }
    alias deref this;

    string toString () const { return format("%s", *data); }
}

auto constRef(T)(T ptr)
if (isPointer!T)
{
    return Ref!(const(T))(ptr);
}

auto recordCycles(T)(T cpu)
if (isCpu!T)
{
    auto cycles = new int;
    auto wrappedTick = cpu.tick;

    static if (isCumulative!T)
    {
        void tick(int cyc)
        {
            (*cycles) += cyc;
            wrappedTick(cyc);
        }
    }
    else
    {
        void tick()
        {
            (*cycles)++;
            wrappedTick();
        }
    }
    cpu.tick = &tick;

    return constRef(cycles);
}


enum Action : ushort { NONE, READ, WRITE }

struct Bus
{
    Action action;
    ushort addr;

    string toString() const
    {
        return format("Bus(%s, %0.4X)", to!string(action), addr);
    }
}

/*
 *
 */
const(Bus[]) recordBus(T)(T cpu, int actions = 8)
if (isCpu!T)
{
    auto record = new Bus[actions];
    int c;

    enforce(cpu.memoryRead !is null && cpu.memoryWrite !is null);
    auto wrappedRead = cpu.memoryRead;
    auto wrappedWrite = cpu.memoryWrite;

    ubyte read(ushort addr)
    {
        if (c == actions)
            throw new TestException(
                format("cannot record more than %d actions", actions));
        record[c++] = Bus(Action.READ, addr);
        return wrappedRead(addr);
    }

    void write(ushort addr, ubyte val)
    {
        if (c == actions)
            throw new TestException(
                format("cannot record more than %d actions", actions));
        record[c++] = Bus(Action.WRITE, addr);
        wrappedWrite(addr, val);
    }

    cpu.memoryRead = &read;
    cpu.memoryWrite = &write;

    return record;
}


class StopException : Exception { this(string msg) { super(msg); } }

void runUntilBRK(T)(T cpu)
if (isCpu!T)
{
    enforce(cpu.memoryRead !is null);
    auto wrappedRead = cpu.memoryRead;

    ubyte read(ushort addr)
    {
        if (addr == 0xFFFE) throw new StopException("BRK");
        return wrappedRead(addr);
    }

    cpu.memoryRead = &read;

    try { cpu.run(true); } catch (StopException e) {}
}


void runOneOpcode(T)(T cpu)
if (isCpu!T)
{
    cpu.run(false);
}
