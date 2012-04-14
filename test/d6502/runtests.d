import std.array, std.exception, std.getopt, std.process, std.stdio,
       std.traits;


enum OpDefs
{
    None,
    Delegates = 1,
    Switch = 2,
    NestedSwitch = 4,
    All = 7
}

enum Tests
{
    None,
    Func = 1,
    Bus = 2,
    Dec = 4,
    All = 7
}

string[OpDefs] defStrings;
string[Tests] fNames;

static this()
{
    fNames = [
        Tests.Func:" test_func.d ",
        Tests.Bus:" test_bus.d ",
        Tests.Dec:" test_decimal.d "
    ];
}

version(DigitalMars)
{
    static this()
    {
        defStrings = [
            OpDefs.Delegates:" -version=OpDelegates",
            OpDefs.Switch:" -version=OpSwitch",
            OpDefs.NestedSwitch:" -version=OpNestedSwitch"
        ];
    }
    string[] stStrings = [" ", " -version=Strict"];
    string[] cmStrings = [" ", " -version=Cumulative"];
}
else version(GNU)
{
    static assert(false, "TODO: add support for GDC.");
}
else version(LDC)
{
    static assert(false, "TODO: add support for LDC.");
}
else
    static assert(false, "Unknown compiler.");


OpDefs opdefs;
bool strict, cumulative;
Tests tests;
bool help;

OpDefs[] deflist;
Tests[] testlist;

void main(string[] args)
{
    if (args.length == 1)
        writeln("(running default tests; use --help for options)");

    getopt(args,
           std.getopt.config.passThrough,
           "def", &deflist,
           "test", &testlist,
           "help", &help);

    if (help)
    {
        writeln(
`Options:
   --test=type   Func, Bus, Dec, or All
   --def=style   Delegates, Switch, or NestedSwitch
   --op=num      test opcode 'num' (num is hex)
   --op=name     test all opcodes named 'name'
   --addr=mode   test all opcodes with addressing mode 'mode'

(All options con be specified multiple times.
--op and --addr have no effect on decimal mode tests.)`
        );
        return;
    }

    foreach(def; deflist) opdefs |= def;
    foreach(test; testlist) tests |= test;

    try
    {
        runTests(args);
    }
    catch (ErrnoException e) {}
}

void runTests(string[] args)
{
    // If no opdef specified, use Delegates.
    if (opdefs == OpDefs.None) opdefs = OpDefs.Delegates;

    int defcount;
    foreach (def; EnumMembers!OpDefs)
        if ((opdefs & def) && def != OpDefs.All) defcount++;

    // If no tests specified, run all (but exclude Dec by default if
    // running with more than one opdef).
    if (tests == Tests.None)
        tests = Tests.Func | Tests.Bus;
        if (!defcount) tests |= Tests.Dec;

    foreach (def; EnumMembers!OpDefs)
        if ((opdefs & def) && def != OpDefs.All)
            foreach (test; EnumMembers!Tests)
                if ((tests & test) && test != Tests.All)
                    runTest(def, test, args[1..$]);
}

void runTest(OpDefs def, Tests test, string[] args)
{
    writeln("Using ", defStrings[def]);
    foreach (s; [false, true])
    {
        foreach (c; [false, true])
        {
            writeln("With strict=", s, " cumulative=", c);
            string cmdline = defStrings[def] ~ stStrings[s] ~ cmStrings[c] ~
                             fNames[test] ~ join(args, " ");
            system("rdmd --force -I../.. -I../../src -version=RunTest " ~
                   cmdline);
        }
    }
}
