module cpu6502;


enum Strict : bool
{
    no, yes
}

enum Cumulative : bool
{
    no, yes
}


class Cpu(bool cumulative)
{
    struct _Mem
    {
        // Reads a value from system memory.
        ubyte delegate(ushort addr) read;

        // Writes a value to system memory.
        void delegate(ushort addr, ubyte val) write;
    }
    _Mem memory;

    struct _Clock
    {
        static if (cumulative)
            /*
             * Updates the number of cycles executed. Called just
             * prior to the final read/write action of each opcode.
             */
            void delegate(int cycles) tick;
        else
            /*
             * Increments the number of cycles executed. Called prior
             * to each read/write action.
             */
            void delegate() tick;
    }
    _Clock clock;

    ubyte A, X, Y, S, P;
}
