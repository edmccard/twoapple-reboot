module test.wrap6502;


public import d6502.nmosundoc : NmosUndoc;
public import d6502.cmos : Cmos;

import test.base;


// True if T is the type of a cpu.
template isCpu(T)
{
    enum isCpu = __traits(hasMember, T, "_isCpuBase");
}

// True if the cpu type T represents a 6502.
template isNMOS(T)
{
    enum isNMOS = __traits(hasMember, T, "_isNMOS");
}

// True if the cpu type T represents a 65C02.
template isCMOS(T)
{
    enum isCMOS = __traits(hasMember, T, "_isCMOS");
}

// True if the cpu type T accesses memory on every cycle.
template isStrict(T)
{
    enum isStrict = __traits(hasMember, T, "_isStrict");
}

// True if the cpu type T
template isCumulative(T)
{
    enum isCumulative = __traits(hasMember, T, "_isCumulative");
}


template CPU(string type, bool strict, bool cumulative)
{
    static if (type == "65c02" || type == "65C02")
        alias Cmos!(strict, cumulative) CPU;
    else static if (type == "6502")
        alias NmosUndoc!(strict, cumulative) CPU;
    else static assert(0);
}


/*
 * Connects a cpu and memory.
 */
void connectCpu(T)(T cpu, ref TestMemory mem)
if (isCpu!T)
{
    static if (isCumulative!T)
        void tick(int cycles) {}
    else
        void tick() {}

    cpu.memoryRead = &mem.read;
    cpu.memoryWrite = &mem.write;
    cpu.tick = &tick;
}


class StopException : Exception { this(string msg) { super(msg); } }

void runUntilBRK(T)(T cpu)
if (isCpu!T)
{
    assert(cpu.memoryRead !is null);
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

void setPC(T)(T cpu, int addr)
if (isCpu!T)
{
    cpu.programCounter = cast(ushort)addr;
}

ushort getPC(T)(T cpu)
if (isCpu!T)
{
    return cpu.programCounter;
}

void setSP(T)(T cpu, int val)
if (isCpu!T)
{
    cpu.stackPointer = cast(ubyte)val;
}

ushort getSP(T)(T cpu)
if (isCpu!T)
{
    return 0x100 | cpu.stackPointer;
}

void setX(T)(T cpu, int val)
if (isCpu!T)
{
    cpu.xIndex = cast(ubyte)val;
}

ubyte getX(T)(T cpu)
if (isCpu!T)
{
    return cpu.xIndex;
}

void setY(T)(T cpu, int val)
if (isCpu!T)
{
    cpu.yIndex = cast(ubyte)val;
}

ubyte getY(T)(T cpu)
if (isCpu!T)
{
    return cpu.yIndex;
}

void setFlag(T)(T cpu, Flag f)
if (isCpu!T)
{
    cpu.flag.fromByte(cpu.flag.toByte() | f);
}

void clearFlag(T)(T cpu, Flag f)
if (isCpu!T)
{
    cpu.flag.fromByte(cpu.flag.toByte() & ~f);
}

bool getFlag(T)(T cpu, Flag f)
if (isCpu!T)
{
    return (cpu.flag.toByte() & f) != 0;
}
