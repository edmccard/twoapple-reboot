/+
 + device/base.d
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

module device.base;

string hex2Digits(int decimalByte)
{
    int highNibble = (decimalByte & 0xF0) >> 4;
    int lowNibble = decimalByte & 0x0F;

    string digits = "0123456789ABCDEF";

    return digits[highNibble..(highNibble + 1)] ~
        digits[lowNibble..(lowNibble + 1)];
}

string hex4Digits(int decimalWord)
{
    return hex2Digits(decimalWord >> 8) ~
        hex2Digits(decimalWord & 0xFF);
}

string InitSwitches(string superCall, string[][] switches)
{
    string initFunc =
        "void initSwitches(SoftSwitchPage switches, " ~
        "int slot = -1)\n{\n";

    if (superCall == "super")
    {
        initFunc ~= "super.initSwitches(switches, slot);\n";
    }

    initFunc ~=
        "ubyte offset = (slot == -1) ? 0 : slot * 16;\n";


    string switchFuncs;
    for(int sw = 0; sw < switches.length; ++sw)
    {
        initFunc ~= switches[sw][0] ~ "\n";
        switchFuncs ~= switches[sw][1] ~ "\n";
    }

    initFunc ~= "}\n";
    return initFunc ~ "\n" ~ switchFuncs;
}

/+
Read:
    ubyte wrapper(ushort addr) { wrapped(); return 0; }
    ubyte wrapper(ushort addr) { return wrapped(); }
    ubyte wrapped(ushort addr)
Write:
    void wrapper(ushort addr, ubyte val) { wrapped(); }
    void wrapper(ushort addr, ubyte val) { wrapped(val); }
    void wrapper(ushort addr, ubyte val) { wrapped(addr); }
    void wrapped(ushort addr, ubyte val)

Wrapped:
    same called for r/w:
        void func() void func(addr)
        void func(rw) void func(rw, addr) void func(rw, addr, val)
        ubyte func()
        ubyte func(rw) ubyte func(rw, addr) ubyte func(rw, addr, val)
    only read:
        void func() void func(addr) ubyte(func) <passthru>
    only write:
        void func() void func(addr) <passthru>
    RETURN VAL: (only applies to read) "0" = void, " "/"7" = ubyte
    WRAP STYLE:
        "R?  " (read only) could be: ()/(addr) (+ rw)
        "  W?" (write only) could be: ()/(addr)/(val)/(addr, val) (+ rw)
        "R?W?" (both) could be: ()/(addr) (+ rw)
                            OR: (rw, val)/(rw, addr, val)
+/

string MakeSwitch(int[] addrs, string type, string wrapped)
{
    string initCalls = "";
    string funcBody;

    string readType, writeType;
    if (type[0] == 'R')
    {
        if (type.length == 1) readType = "R";
        else if (type[1] == 'W')
        {
            readType = "R";
            writeType = "W";
        }
        else
        {
            readType = type[0..2];
            if (type.length > 2) writeType = "W";
        }
    }
    else writeType = "W";

    string wrapper, realWrapped;
    string rSwitch, wSwitch, args;

    realWrapped = wrapped;
    if (wrapped[length - 1] == ')')
    {
        for (int pos = 0; pos < wrapped.length; ++pos)
        {
            if (wrapped[pos] == '(')
            {
                args = wrapped[(pos + 1) .. (length - 1)];
                realWrapped = wrapped[0 .. pos];
                break;
            }
        }
    }
    wrapper = "wrapper_" ~ realWrapped;

    if (readType == "R")
    {
        rSwitch = "setRSwitch";
        funcBody = MakeRSwitch(wrapper, realWrapped, args);
    }
    else if (readType == "R7")
    {
        rSwitch = "setR7Switch";
        funcBody = MakeRSwitch(wrapper, realWrapped, args);
    }
    else if (readType == "R0")
    {
        rSwitch = "setR0Switch";
        funcBody = MakeR0Switch(wrapper, realWrapped, args);
    }

    if (writeType == "W")
    {
        wSwitch = "setWSwitch";
        funcBody ~= MakeWSwitch(wrapper, realWrapped, args);
    }

    for (int ad = 0; ad < addrs.length; ++ad)
    {
        string addrStr = "(0x" ~ hex4Digits(addrs[ad]) ~ " + offset)";
        if (rSwitch != "")
            initCalls ~= "switches." ~ rSwitch ~ "(" ~ addrStr ~ ", &" ~
                wrapper ~ ");\n";
        if (wSwitch != "")
            initCalls ~= "switches." ~ wSwitch ~ "(" ~ addrStr ~ ", &" ~
                wrapper ~ ");\n";
    }

    return "[\"" ~ initCalls ~ "\", \"" ~ funcBody ~ "\"]";
}

string MakeR0Switch(string wrapper, string wrapped, string args)
{
    return "ubyte " ~ wrapper ~ "(ushort addr)\n" ~
           "{\n" ~ wrapped ~ "(" ~ args ~ ");\n" ~
           "return 0;\n}\n";
}

string MakeRSwitch(string wrapper, string wrapped, string args)
{
    return "ubyte " ~ wrapper ~ "(ushort addr)\n" ~
           "{\n" ~ "return " ~ wrapped ~ "(" ~ args ~ ");\n}\n";
}

string MakeWSwitch(string wrapper, string wrapped, string args)
{
    return "void " ~ wrapper ~ "(ushort addr, ubyte val)\n" ~
           "{\n" ~ wrapped ~ "(" ~ args ~ ");\n}\n";
}

string AbstractInitSwitches()
{
    return
        "abstract void initSwitches(SoftSwitchPage switches, " ~
        "int slot = -1);\n";
}

string EmptyInitSwitches()
{
    return
        "void initSwitches(SoftSwitchPage switches, int slot = -1) {}\n";
}
