/*
 * Test functionality that either depends on a specific cpu
 * implementation, or that may be useful to any test which requires a
 * cpu (as opposed to testing the cpu itself).
 */
module test.cpu;


import std.conv, std.exception, std.random, std.string, std.traits;

public import cpu.d6502 : Cpu, is6502, is65C02;

import test.base : strict, cumulative;


// True if T is the type of a cpu.
template isCpu(T)
{
    enum isCpu = __traits(hasMember, T, "_isCpu");
}

// True if the cpu type T represents a 6502.
template isNMOS(T)
{
    enum isNMOS = is6502!T;
}

// True if the cpu type T represents a 65C02.
template isCMOS(T)
{
    enum isCMOS = is65C02!T;
}


// Not used in test mode, but needed to instantiate a cpu.
class DummyMem
{
    ubyte read(ushort) { return 0; }
    void write(ushort, ubyte) {}
    static if (cumulative) { void tick(int) {} }
    else { void tick() {} }
}


/*
 * The type of a cpu, based on its architecture (6502 or 65C02).
 */
template CPU(string arch, M = DummyMem, C = DummyMem)
{
    alias Cpu!(arch, M, C) CPU;
}


auto makeCpu(T)(CpuInfo info)
if (isCpu!T)
{
    auto cpu = new T(null, null);
    cpu.PC = info.PC;
    cpu.S = info.SP;
    cpu.statusFromByte(info.S);
    cpu.A = info.A;
    cpu.X = info.X;
    cpu.Y = info.Y;
    return cpu;
}

// Connects test memory to a cpu.
void connectMem(T, S)(T cpu, ref S mem)
if (isCpu!T)
{
    static if (cumulative)
        void tick(int cycles) {}
    else
        void tick() {}

    cpu.memory.read = &mem.read;
    cpu.memory.write = &mem.write;
    cpu.clock.tick = &tick;
}


/*
 * Sets up a cpu to record the number of cycles executed.
 *
 * For example:
 *
 * auto cycles = recordCycles(cpu);
 * // run a test
 * if (cycles != expected) ...
 */
auto recordCycles(T)(T cpu)
if (isCpu!T)
{
    auto cycles = new int;
    auto wrappedTick = cpu.clock.tick;

    static if (cumulative)
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
    cpu.clock.tick = &tick;

    return constRef(cycles);
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


/*
 * Sets up a cpu to record bus accesses during execution.
 *
 * For example:
 *
 * auto accesses = recordBus(cpu);
 * // run a test
 * if (accesses != expected) ...
 */
const(Bus[]) recordBus(T)(T cpu, int actions = 8)
if (isCpu!T)
{
    auto record = new Bus[actions];
    int c;

    enforce(cpu.memory.read !is null && cpu.memory.write !is null);
    auto wrappedRead = cpu.memory.read;
    auto wrappedWrite = cpu.memory.write;

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

    cpu.memory.read = &read;
    cpu.memory.write = &write;

    return record;
}


// A record of a bus access with its type and address.
struct Bus
{
    Action action;
    ushort addr;

    this(Action action, int addr)
    {
        this.action = action; this.addr = cast(ushort)addr;
    }

    string toString() const
    {
        return format("Bus(%s, %0.4X)", to!string(action), addr);
    }
}


// Types of bus accesses.
enum Action : ushort { NONE, READ, WRITE }


// Runs the cpu until a BRK instruction.
void runUntilBRK(T)(T cpu)
if (isCpu!T)
{
    assert(cpu.memory.read !is null);
    auto wrappedRead = cpu.memory.read;

    ubyte read(ushort addr)
    {
        if (addr == 0xFFFE) throw new StopException("BRK");
        return wrappedRead(addr);
    }

    cpu.memory.read = &read;

    try { cpu.run(true); } catch (StopException e) {}
}

class StopException : Exception { this(string msg) { super(msg); } }


// Runs the cpu for one opcode.
void runOneOpcode(T)(T cpu)
if (isCpu!T)
{
    cpu.run(false);
}


struct CpuInfo
{
    ushort PC;
    ubyte SP = 0xFF;
    ubyte A, X, Y;
    ubyte S = 0x30;

    string toString() const
    {
        return format("PC %0.4X SP %0.2X S %0.8b A %0.2X X %0.2X Y %0.2X",
                      PC, SP, S, A, X, Y);
    }

    static CpuInfo fromCpu(T)(T cpu)
    {
        CpuInfo info;
        info.PC = cpu.PC;
        info.SP = cpu.S;
        info.A = cpu.A;
        info.X = cpu.X;
        info.Y = cpu.Y;
        info.S = cpu.statusToByte();
        return info;
    }
}


// Sets the program counter.
void setPC(T)(ref T cpu, int addr)
if (isCpu!T || is(T == CpuInfo))
{
    cpu.PC = cast(ushort)addr;
}

void incPC(T : CpuInfo)(ref T cpu, int amt = 1)
{
    cpu.PC = pageCrossAdd(cpu.PC, amt);
}


// Returns the program counter.
ushort getPC(T)(ref T cpu)
if (isCpu!T || is(T == CpuInfo))
{
    return cpu.PC;
}


/*
 * Sets the stack pointer.
 *
 * Can be called with either an offset (e.g., 0xFE) or an absolute
 * stack address (e.g., 0x01FE).
 */
void setSP(T)(T cpu, int val)
if (isCpu!T)
{
    assert(val < 0x0200);
    cpu.S = cast(ubyte)val;
}

void setSP(T : CpuInfo)(ref T cpu, int val)
{
    assert(val < 0x0200);
    cpu.SP = cast(ubyte)val;
}

void incSP(T : CpuInfo)(ref T cpu, int amt = 1)
{
    cpu.SP = cast(ubyte)pageWrapAdd(cpu.SP, amt);
}

void decSP(T : CpuInfo)(ref T cpu, int amt = -1)
{
    cpu.SP = cast(ubyte)pageWrapAdd(cpu.SP, amt);
}


/*
 * Returns the stack address (in the range 0x0100-0x01FF) represented
 * by the stack pointer.
 */
ushort getSP(T)(T cpu)
if (isCpu!T)
{
    return 0x100 | cpu.S;
}

ushort getSP(T : CpuInfo)(ref T cpu)
{
    return 0x0100 | cpu.SP;
}


// The names of the registers.
enum Reg
{
    A, X, Y
}

// Sets a register.
void setReg(T)(ref T cpu, Reg reg, int val)
if (isCpu!T || is(T == CpuInfo))
{
    final switch (reg)
    {
        case Reg.A: setA(cpu, val); break;
        case Reg.X: setX(cpu, val); break;
        case Reg.Y: setY(cpu, val); break;
    }
}

// Returns a register
ubyte getReg(T)(ref T cpu, Reg reg)
if (isCpu!T || is(T == CpuInfo))
{
    final switch (reg)
    {
        case Reg.A: return getA(cpu);
        case Reg.X: return getX(cpu);
        case Reg.Y: return getY(cpu);
    }
}

// Sets the A register.
void setA(T)(ref T cpu, int val)
if (isCpu!T || is(T == CpuInfo))
{
    cpu.A = cast(ubyte)val;
}


// Returns the A register.
ubyte getA(T)(ref T cpu)
if (isCpu!T || is(T == CpuInfo))
{
    return cpu.A;
}


// Sets the X register.
void setX(T)(ref T cpu, int val)
if (isCpu!T || is(T == CpuInfo))
{
    cpu.X = cast(ubyte)val;
}


// Returns the X register.
ubyte getX(T)(ref T cpu)
if (isCpu!T || is(T == CpuInfo))
{
    return cpu.X;
}


// Sets the Y register.
void setY(T)(ref T cpu, int val)
if (isCpu!T || is(T == CpuInfo))
{
    cpu.Y = cast(ubyte)val;
}


// Returns the Y register.
ubyte getY(T)(ref T cpu)
if (isCpu!T || is(T == CpuInfo))
{
    return cpu.Y;
}


// The names of the status flags.
enum Flag : ubyte
{
    C = 0x01,
    Z = 0x02,
    I = 0x04,
    D = 0x08,
    V = 0x40,
    N = 0x80
}

string flagToString(Flag f)
{
    switch (f)
    {
        case Flag.C: return "C";
        case Flag.Z: return "Z";
        case Flag.I: return "I";
        case Flag.D: return "D";
        case Flag.V: return "V";
        case Flag.N: return "N";
        default: return "?";
    }
}

// Sets one or more status flags.
void setFlag(T)(T cpu, Flag[] flags...)
if (isCpu!T)
{
    auto reg = cpu.statusToByte();
    foreach (flag; flags) reg |= flag;
    cpu.statusFromByte(reg);
}

void setFlag(T : CpuInfo)(ref T cpu, Flag[] flags...)
{
    foreach (flag; flags) cpu.S |= flag;
}

// Clears one or more status flags.
void clearFlag(T)(T cpu, Flag[] flags...)
if (isCpu!T)
{
    auto reg = cpu.statusToByte();
    foreach (flag; flags) reg &= ~flag;
    cpu.statusFromByte(reg);
}

void clearFlag(T : CpuInfo)(ref T cpu, Flag[] flags...)
{
    foreach (flag; flags) cpu.S &= ~flag;
}

// Returns a status flag.
bool getFlag(T)(T cpu, Flag f)
if (isCpu!T)
{
    return (cpu.statusToByte() & f) != 0;
    return false;
}

bool getFlag(T : CpuInfo)(ref T cpu, Flag f)
{
    return (cpu.S & f) != 0;
}


// Sets the status register from a byte.
void setStatus(T)(T cpu, int val)
if (isCpu!T)
{
    cpu.statusFromByte(cast(ubyte)val);
}

void setStatus(T : CpuInfo)(ref T cpu, int val)
{
    cpu.S = cast(ubyte)val | 0x30;
}

// Returns the status register as a byte.
ubyte getStatus(T)(T cpu)
if (isCpu!T)
{
    return cpu.statusToByte();
    return 0;
}

ubyte getStatus(T : CpuInfo)(ref T cpu)
{
    return cpu.S | 0x30;
}

// Sets or clears a single status flag.
void updateFlag(T)(ref T cpu, Flag f, bool val)
if (isCpu!T || is(T == CpuInfo))
{
    if (val)
        setFlag(cpu, f);
    else
        clearFlag(cpu, f);
}

void setNZ(T : CpuInfo)(ref T cpu, ubyte val)
{
    updateFlag(cpu, Flag.Z, (val == 0));
    updateFlag(cpu, Flag.N, (val >= 0x80));
}

// Sets or clears the flag required for a given opcode to branch.
void expectBranch(T)(ref T cpu, ubyte opcode)
if (isCpu!T || is(T == CpuInfo))
{
    switch (opcode)
    {
        case /*BPL*/ 0x10: clearFlag(cpu, Flag.N); break;
        case /*BMI*/ 0x30: setFlag(cpu, Flag.N); break;
        case /*BVC*/ 0x50: clearFlag(cpu, Flag.V); break;
        case /*BVS*/ 0x70: setFlag(cpu, Flag.V); break;
        case /*BRA*/ 0x80: break;
        case /*BCC*/ 0x90: clearFlag(cpu, Flag.C); break;
        case /*BCS*/ 0xB0: setFlag(cpu, Flag.C); break;
        case /*BNE*/ 0xD0: clearFlag(cpu, Flag.Z); break;
        case /*BEQ*/ 0xF0: setFlag(cpu, Flag.Z); break;
        default:
            enforce(0, format("not a branching opcpde %0.2X", opcode));
    }
}

// Returns whether an opcode would branch if executed.
bool wouldBranch(T)(ref T cpu, ubyte opcode)
if (isCpu!T || is(T == CpuInfo))
{
    switch (opcode)
    {
        case /*BPL*/ 0x10: return !getFlag(cpu, Flag.N);
        case /*BMI*/ 0x30: return getFlag(cpu, Flag.N);
        case /*BVC*/ 0x50: return !getFlag(cpu, Flag.V);
        case /*BVS*/ 0x70: return getFlag(cpu, Flag.V);
        case /*BRA*/ 0x80: return true;
        case /*BCC*/ 0x90: return !getFlag(cpu, Flag.C);
        case /*BCS*/ 0xB0: return getFlag(cpu, Flag.C);
        case /*BNE*/ 0xD0: return !getFlag(cpu, Flag.Z);
        case /*BEQ*/ 0xF0: return getFlag(cpu, Flag.Z);
        default:
            assert(0, format("not a branching opcpde %0.2X", opcode));
    }
}

// Sets or clears the flag required for a given opcode to not branch.
void expectNoBranch(T)(ref T cpu, ubyte opcode)
if (isCpu!T || is(T == CpuInfo))
{
    switch (opcode)
    {
        case /*BPL*/ 0x10: setFlag(cpu, Flag.N); break;
        case /*BMI*/ 0x30: clearFlag(cpu, Flag.N); break;
        case /*BVC*/ 0x50: setFlag(cpu, Flag.V); break;
        case /*BVS*/ 0x70: clearFlag(cpu, Flag.V); break;
        case /*BCC*/ 0x90: setFlag(cpu, Flag.C); break;
        case /*BCS*/ 0xB0: clearFlag(cpu, Flag.C); break;
        case /*BNE*/ 0xD0: setFlag(cpu, Flag.Z); break;
        case /*BEQ*/ 0xF0: clearFlag(cpu, Flag.Z); break;
        default:
            enforce(0, format("not a branching opcpde %0.2X", opcode));
    }
}


// Constructs an address from its low and high bytes.
ushort address(ubyte l, ubyte h)
{
    return cast(ushort)((h << 8) | l);
}


ubyte addrLo(ushort addr)
{
    return cast(ubyte)(addr & 0xFF);
}

ubyte addrHi(ushort addr)
{
    return cast(ubyte)(addr >> 8);
}


/*
 * Adds an offset to an address, resulting in an address in the same
 * page.
 */
ushort pageWrapAdd(ushort base, int offset)
{
    return (base & 0xFF00) + cast(ubyte)((base & 0xFF) + offset);
}


/*
 * Adds an offset to an address, possibly resulting in an address in a
 * different page.
 */
ushort pageCrossAdd(ushort base, int offset)
{
    return cast(ushort)(base + offset);
}


// A random value to use for "uninitialized" memory.
ubyte XX()
{
    return cast(ubyte)uniform(0, 256);
}

// A number different from some other number.
ubyte notXX(ubyte val)
{
    return cast(ubyte)~val;
}


class TestException : Exception { this(string msg) { super(msg); } }
