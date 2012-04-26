/+
 + timer.d
 +
 + Copyright: 2012 Ed McCardell, 2007 Gerald Stocker
 +
 + This file is part of twoapple-reboot.
 +
 + twoapple-reboot is free software; you can redistribute it and/or modify
 + it under the terms of the GNU General Public License as published by
 + the Free Software Foundation; either version 2 of the License, or
 + (at your option) any later version.
 +
 + twoapple-reboot is distributed in the hope that it will be useful,
 + but WITHOUT ANY WARRANTY; without even the implied warranty of
 + MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 + GNU General Public License for more details.
 +
 + You should have received a copy of the GNU General Public License
 + along with twoapple-reboot; if not, write to the Free Software
 + Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 +/

module timer;

final class Timer
{
private:
    static struct Counter
    {
        uint start, curr;
        bool active;
        size_t next = -1, nextFree;
        bool delegate() expiry;
        ulong creationTick;

        this(uint length, bool delegate() expiry, ulong creationTick)
        {
            start = curr = length;
            this.expiry = expiry;
            this.creationTick = creationTick;
            active = true;
        }
    }

    ulong _totalTicks;
    uint start = uint.max, curr = uint.max, minCurr = uint.max;
    uint balance;
    size_t head, tail, nextFree;
    Counter[] counters;
    uint _hertz;

    final void setNextFree()
    {
        for (size_t i = nextFree; i < counters.length; i++)
            counters[i].nextFree = i + 1;
    }

    final void deleteCounter(size_t idx, size_t prev)
    {
        auto tmp = nextFree;
        nextFree = idx;
        counters[idx].nextFree = tmp;

        auto next = counters[idx].next;
        if (idx == head)
        {
            head = next;
        }
        else
        {
            counters[prev].next = next;
        }
        if (idx == tail)
        {
            tail = prev;
            counters[tail].next = -1;
        }

        counters[idx].active = false;
    }

public:
    this(uint primaryLength, uint hertz, bool delegate() primaryStop)
    {
        counters = new Counter[50];
        setNextFree();
        _hertz = hertz;
        addCounter(primaryLength, primaryStop);
    }

    final @property uint primaryRemaining()
    {
        return counters[0].curr;
    }

    final @property uint primaryLength()
    {
        return counters[0].start;
    }

    final @property uint hertz()
    {
        return _hertz;
    }

    final @property ulong totalTicks()
    {
        return _totalTicks;
    }

    final void tick()
    {
        _totalTicks++;
        curr--;
        if (!curr)
        {
            minCurr = uint.max;
            size_t idx = head;
            size_t prev = -1;
            while (idx != -1)
            {
                if (counters[idx].active)
                {
                    counters[idx].curr -= start;
                    if (counters[idx].curr) counters[idx].curr -= balance;
                    if (!counters[idx].curr)
                    {
                        if (counters[idx].expiry())
                            counters[idx].curr = counters[idx].start;
                        else
                            deleteCounter(idx, prev);
                    }
                    if (counters[idx].active && counters[idx].curr < minCurr)
                        minCurr = counters[idx].curr;
                }
                else
                {
                    deleteCounter(idx, prev);
                }
                if (counters[idx].active) prev = idx;
                idx = counters[idx].next;
            }
            start = curr = minCurr;
            balance = 0;
        }
    }

    final size_t addCounter(uint length, bool delegate() expiry)
    {
        if (nextFree == counters.length)
        {
            counters.length += 20;
            setNextFree();
        }

        auto idx = nextFree;
        nextFree = counters[nextFree].nextFree;
        counters[idx] = Counter(length, expiry, _totalTicks);
        counters[tail].next = idx;
        tail = idx;
        counters[tail].next = -1;

        if (curr == 0)
        {
            counters[idx].curr += start;
        }
        else
        {
            if (counters[idx].curr < curr)
            {
                balance = start - curr;
                start = curr = counters[idx].curr;
            }
            else
            {
                counters[idx].curr += (start - curr);
            }
        }

        return idx;
    }

    final void removeCounter(ulong creationTick, size_t idx)
    {
        assert(counters[idx].creationTick == creationTick);
        counters[idx].active = false;
    }


    final class Cycle
    {
        ulong startTick;
        uint rollOver;

        this(uint rollOver)
        {
            this.rollOver = rollOver;
            restart();
        }

        final void restart()
        {
            startTick = _totalTicks;
        }

        final uint val()
        {
            return (_totalTicks - startTick) % rollOver;
        }
    }
}


unittest
{
    bool primary() { return true; }

    auto t = new Timer(10205, 1020484, &primary);
    int c1 = 0, c2 = 0;
    t.addCounter(10, (){assert(t._totalTicks == 10); c1++; return true;});
    foreach (i; 0..9) t.tick();
    t.addCounter(5, (){assert(t._totalTicks == 14); c2++; return true;});
    foreach (i; 0..5) t.tick();
    assert (c1 == 1 && c2 == 1);
}

unittest
{
    bool primary() { return true; }

    auto t = new Timer(10205, 1020484, &primary);
    int c1 = 0, c2 = 0;
    struct Dummy
    {
        bool exp1()
        {
            auto ticks = t._totalTicks;
            assert((c1 == 0 && ticks == 10) || (c1 == 1 && ticks == 30));
            c1++;
            t.addCounter(10, &exp2);
            return false;
        }
        bool exp2()
        {
            auto ticks = t._totalTicks;
            assert((c2 == 0 && ticks == 20) || (c2 == 1 && ticks == 40));
            c2++;
            t.addCounter(10, &exp1);
            return false;
        }
    }
    Dummy d;
    t.addCounter(10, &d.exp1);
    foreach (i; 0..40) t.tick();
    assert(c1 == 2 && c2 == 2);
}

unittest
{
    bool primary() { return true; }

    auto t = new Timer(10205, 1020484, &primary);
    int c1 = 0, c2 = 0, c3 = 0;

    void addExtra()
    {
        t.addCounter(4, (){auto ticks = t._totalTicks;
                           assert((c1 == 0 && ticks == 14) ||
                                  (c1 == 1 && ticks == 24));
                           c1++;
                           return false;});
        t.addCounter(5, (){auto ticks = t._totalTicks;
                           assert((c2 == 0 && ticks == 15) ||
                                  (c2 == 1 && ticks == 25));
                           c2++;
                           return false;});
        t.addCounter(6, (){auto ticks = t._totalTicks;
                           assert((c3 == 0 && ticks == 16) ||
                                  (c3 == 1 && ticks == 26));
                           c3++;
                           return false;});
    }
    t.addCounter(10, (){addExtra(); return true;});
    foreach (i; 0..30) t.tick();
    assert (c1 == 2 && c2 == 2 && c3 == 2);
}

unittest
{
    bool primary() { return true; }

    auto t = new Timer(10205, 1020484, &primary);
    auto c1 = t.addCounter(10, (){assert(false); return false;});
    auto c1_tick = t._totalTicks;
    foreach (i; 0..5) t.tick();
    t.removeCounter(c1_tick, c1);
    foreach (i; 0..5) t.tick();
}

unittest
{
    bool primary() { return true; }

    auto t = new Timer(10205, 1020484, &primary);
    int c1 = 0, c2 = 0;
    t.addCounter(10, (){c1++; return true;});
    auto idx = t.addCounter(15, (){c2++; return true;});
    auto tick = t._totalTicks;
    foreach (i; 0..20) t.tick();
    assert(c1 == 2 && c2 == 1);
    t.removeCounter(tick, idx);
    foreach (i; 0..20) t.tick();
    assert(c1 == 4 && c2 == 1);
}

unittest
{
    bool primary() { return true; }

    auto t = new Timer(10205, 1020484, &primary);

    bool t1() { assert(!(t.totalTicks % 5000)); return true; }
    bool t2() { assert(!(t.totalTicks % 4500)); return true; }
    bool t3() { assert(!(t.totalTicks % 6500)); return true; }
    bool junk() { assert(!((t.totalTicks - 7000) % 1500)); return true; }

    t.addCounter(5000, &t1);
    t.addCounter(4500, &t2);
    t.addCounter(6500, &t3);

    foreach (i; 0..7000) t.tick();

    t.addCounter(1500, &junk);
    t.addCounter(1500, &junk);
    t.addCounter(1500, &junk);
    t.addCounter(1500, &junk);

    foreach (i; 0..7000) t.tick();
}
