import std.algorithm, std.array, std.exception, std.getopt, std.process,
    std.stdio;


string GTKD = "";
string DERELICT = "";


version(GNU)
    string OPMODE = " -version=OpSwitch ";
else version(DigitalMars)
    string OPMODE = " -version=OpNestedSwitch ";
else
    static assert(0, "Unsupported compiler");


bool notGTKD(string a)
{
    return indexOf(a, GTKD) == -1;
}
bool compilable(string a)
{
    return endsWith(a, ".d") && indexOf(a, "ctfe") == -1;
}


int main(string[] args)
{
    getopt(
        args,
        "gtkd", &GTKD,
        "derelict", &DERELICT);

    string opts = "-Jdata " ~ OPMODE;
    if (GTKD.length)
        opts ~= " -I" ~ GTKD ~ "/src -I" ~ GTKD ~ "/srcgl ";
    if (DERELICT.length)
        opts ~= " -I" ~ DERELICT ~ "/import ";
    try
    {
        auto deps = split(shell("rdmd --makedepend " ~ opts ~ " twoapple.d"));
        auto d_files = array(filter!compilable(deps));
        auto without_gtkd = array(filter!notGTKD(d_files));
        opts = " -inline -release -O -noboundscheck " ~ opts ~
               " -d -L-lGL -L-ldl -L-lX11 " ~
               " -L-L" ~ DERELICT ~ "/lib -L-lDerelictSDL -L-lDerelictUtil ";
        version(DigitalMars)
        {
            if (GTKD.length)
                opts ~= " -L-L" ~ GTKD ~ " -L-lgtkd -L-lgtkdgl ";
            auto files = join(without_gtkd, " ");
            return system("dmd " ~ opts ~ " " ~ files);
        }
        else version(GNU)
        {
            auto files = join(d_files, " ");
            return system("gdmd " ~ opts ~ " " ~ files);
        }
    }
    catch (ErrnoException e)
    {
        return 1;
    }

    return 0;
}
