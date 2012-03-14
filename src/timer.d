/+
 + timer.d
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

module timer;

class Timer
{
	class Cycle
	{
		int delta;
		uint rollOver;

		this(uint maxVal)
		{
			rollOver = maxVal;
            restart();
		}

        void restart()
        {
			delta = 0 - currentCounter.elapsed();
        }

		uint currentVal()
		{
			return (currentCounter.elapsed() + delta) % rollOver;
		}

		void update()
		{
			delta = currentVal();
		}
	}

	class Counter
	{
		bool delegate() expiry;
		uint startLength, currentLength;
		int ticks;
        bool shouldContinue;

		this(uint start)
		{
            shouldContinue = true;
			startLength = currentLength = ticks = start;
            addCounter(this);
		}

		this(uint start, bool delegate() expiration)
		{
			this(start);
            initCounter(this);
			expiry = expiration;
		}

		final uint elapsed()
		{
			return currentLength - ticks;
		}

		final void tick()
		{
			--ticks;
			if (ticks == 0)
			{
				reset();
			}
		}

        final void forceExpire()
        {
            ticks = 1;
            tick();
        }

        final void discard()
        {
            expiry = &nullExpiry;
            forceExpire();
        }

		private final void resume()
		{
			currentLength = ticks;
		}

		private final bool expire()
		{
			ticks = currentLength = startLength;
			return expiry();
		}

        private bool nullExpiry() { return false; }
	}

	class DelayedCounter : Counter
	{
        uint realStart;
        bool delegate() realExpiry;

		this(uint start, bool delegate() expiration, uint delay)
		{
			realStart = start;
            realExpiry = expiration;
            super(delay, &becomeReal);
		}

		private bool becomeReal()
		{
			ticks = currentLength = startLength = realStart;
			expiry = realExpiry;
			bool retval = expiry();
			initCounter(this);
            return retval;
		}
	}

	Cycle[] cycles;
	Counter[] counters;
	Counter primaryCounter, currentCounter;
    uint hertz;

	this(uint primaryStart, uint hz)
	{
        hertz = hz;
		cycles.length = 10;
		counters.length = 10;
		cycles.length = 0;
		counters.length = 0;
		currentCounter = primaryCounter = new Counter(primaryStart);
	}

	final void onPrimaryStop(bool delegate() expiration)
	{
		primaryCounter.expiry = expiration;
	}

    Cycle startCycle(uint maxVal)
	{
		cycles.length = cycles.length + 1;
		cycles[length-1] = new Cycle(maxVal);
		return cycles[length-1];
	}

	void tick()
	{
		currentCounter.tick();
	}

    private void deleteCounters()
    {
        int numCounters = counters.length;
        int lastCounter;
main:   for (int counter = 0; counter < counters.length; ++counter)
        {
            lastCounter = counter;
            while (!counters[counter].shouldContinue)
            {
                numCounters--;
                if (++counter >= counters.length) break main;
            }
            currentCounter = counters[lastCounter] = counters[counter];
        } 
        if (numCounters < counters.length)
        {
            counters.length = numCounters;
        }
    }

	private void addCounter(Counter newCounter)
	{
		counters.length = counters.length + 1;
		counters[length-1] = newCounter;
	}

	private void initCounter(Counter newCounter)
	{
		if (newCounter.ticks < currentCounter.ticks)
		{
			reset(newCounter);
		}
		else
		{
			newCounter.ticks += currentCounter.elapsed();
		}
	}

	private void reset(Counter newCounter = null)
	{
        // update cycle counts
        for (int cycle = 0; cycle < cycles.length; ++cycle)
        {
            cycles[cycle].update();
        }

        // update counter counts
        for (int counter = 0; counter < counters.length; ++counter)
        {
            if (counters[counter] !is currentCounter &&
                    counters[counter] !is newCounter)
                counters[counter].ticks -= currentCounter.elapsed();
        }

        // check for expired counters
        for (int counter = 0; counter < counters.length; ++counter)
        {
            if (counters[counter].ticks <= 0)
                counters[counter].shouldContinue = counters[counter].expire();
            else
                counters[counter].resume();
        }

        //delete counters that should be deleted
        deleteCounters();

        // set current counter
        for (int counter = 0; counter < counters.length; ++counter)
        {
            if (counters[counter].ticks < currentCounter.ticks)
                currentCounter = counters[counter];
        }
	}

}

