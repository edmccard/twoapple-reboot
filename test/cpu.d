/*
 * Test functionality that either depends on a specific cpu
 * implementation, or that may be useful to any test which requires a
 * cpu (as opposed to testing the cpu itself).
 */
module test.cpu;


import std.conv, std.exception, std.random, std.string, std.traits;

public import d6502.nmosundoc : NmosUndoc;
public import d6502.cmos : Cmos;


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

// True if the cpu type T aggregates ticks.
template isCumulative(T)
{
    enum isCumulative = __traits(hasMember, T, "_isCumulative");
}


/*
 * The type of a cpu, based on its architecture (6502 or 65C02) and
 * its timing characteristics (strict or not bus access, cumulative or
 * not cycle reporting).
 */
template CPU(string arch, bool strict, bool cumulative)
{
    static if (arch == "65c02" || arch == "65C02")
        alias Cmos!(strict, cumulative) CPU;
    else static if (arch == "6502")
        alias NmosUndoc!(strict, cumulative) CPU;
    else static assert(0);
}


// Connects test memory to a cpu.
void connectMem(T, S)(T cpu, ref S mem)
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

class StopException : Exception { this(string msg) { super(msg); } }


// Runs the cpu for one opcode.
void runOneOpcode(T)(T cpu)
if (isCpu!T)
{
    cpu.run(false);
}


// Sets the program counter.
void setPC(T)(T cpu, int addr)
if (isCpu!T)
{
    cpu.programCounter = cast(ushort)addr;
}

// Returns the program counter.
ushort getPC(T)(T cpu)
if (isCpu!T)
{
    return cpu.programCounter;
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
    cpu.stackPointer = cast(ubyte)val;
}

/*
 * Returns the stack address (in the range 0x0100-0x01FF) represented
 * by the stack pointer.
 */
ushort getSP(T)(T cpu)
if (isCpu!T)
{
    return 0x100 | cpu.stackPointer;
}


// Sets the X register.
void setX(T)(T cpu, int val)
if (isCpu!T)
{
    cpu.xIndex = cast(ubyte)val;
}

// Returns the X register.
ubyte getX(T)(T cpu)
if (isCpu!T)
{
    return cpu.xIndex;
}


// Sets the Y register.
void setY(T)(T cpu, int val)
if (isCpu!T)
{
    cpu.yIndex = cast(ubyte)val;
}

// Returns the Y register.
ubyte getY(T)(T cpu)
if (isCpu!T)
{
    return cpu.yIndex;
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

// Sets one or more status flags.
void setFlag(T)(T cpu, Flag[] flags...)
if (isCpu!T)
{
    auto reg = cpu.flag.toByte();
    foreach (flag; flags) reg |= flag;
    cpu.flag.fromByte(reg);
}

// Clears one or more status flags.
void clearFlag(T)(T cpu, Flag[] flags...)
if (isCpu!T)
{
    auto reg = cpu.flag.toByte();
    foreach (flag; flags) reg &= ~flag;
    cpu.flag.fromByte(reg);
}

// Returns a status flag.
bool getFlag(T)(T cpu, Flag f)
if (isCpu!T)
{
    return (cpu.flag.toByte() & f) != 0;
}

// Sets or clears a single status flag.
void updateFlag(T)(T cpu, Flag f, bool val)
if (isCpu!T)
{
    if (val)
        setFlag(cpu, f);
    else
        clearFlag(cpu, f);
}


// Sets or clears the flag required for a given opcode to branch.
void expectBranch(T)(T cpu, ubyte opcode)
if (isCpu!T)
{
    switch (opcode)
    {
        case /*BPL*/ 0x10: clearFlag(cpu, Flag.N); break;
        case /*BMI*/ 0x30: setFlag(cpu, Flag.N); break;
        case /*BVC*/ 0x50: clearFlag(cpu, Flag.V); break;
        case /*BVS*/ 0x70: setFlag(cpu, Flag.V); break;
        case /*BCC*/ 0x90: clearFlag(cpu, Flag.C); break;
        case /*BCS*/ 0xB0: setFlag(cpu, Flag.C); break;
        case /*BNE*/ 0xD0: clearFlag(cpu, Flag.Z); break;
        case /*BEQ*/ 0xF0: setFlag(cpu, Flag.Z); break;
        default:
            if (isCMOS!T) { if (opcode == /*BRA*/ 0x80) break; }
            enforce(0, format("not a branching opcpde %0.2X", opcode));
    }
}

// Returns whether an opcode would branch if executed.
bool wouldBranch(T)(T cpu, ubyte opcode)
if (isCpu!T)
{
    switch (opcode)
    {
        case /*BPL*/ 0x10: return !getFlag(cpu, Flag.N);
        case /*BMI*/ 0x30: return getFlag(cpu, Flag.N);
        case /*BVC*/ 0x50: return !getFlag(cpu, Flag.V);
        case /*BVS*/ 0x70: return getFlag(cpu, Flag.V);
        case /*BCC*/ 0x90: return !getFlag(cpu, Flag.C);
        case /*BCS*/ 0xB0: return getFlag(cpu, Flag.C);
        case /*BNE*/ 0xD0: return !getFlag(cpu, Flag.Z);
        case /*BEQ*/ 0xF0: return getFlag(cpu, Flag.Z);
        default:
            if (isCMOS!T) { if (opcode == /*BRA*/ 0x80) return true; }
            assert(0, format("not a branching opcpde %0.2X", opcode));
    }
}

// Sets or clears the flag required for a given opcode to not branch.
void expectNoBranch(T)(T cpu, ubyte opcode)
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
            if (isCMOS!T)
                enforce(opcode != 0x80, "BRA can never not branch");
            enforce(0, format("not a branching opcpde %0.2X", opcode));
    }
}


// Constructs an address from its low and high bytes.
ushort address(ubyte l, ubyte h)
{
    return cast(ushort)((h << 8) | l);
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
    return cast(ubyte)(val ^ 0xAA);
}


class TestException : Exception { this(string msg) { super(msg); } }
