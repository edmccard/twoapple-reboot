/+
 + system/peripheral.d
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

module system.peripheral;

import memory;
import d6502.base;

import peripheral.base;
import peripheral.diskii;
import peripheral.langcard;
import peripheral.saturn128;

class Peripherals
{
    Peripheral[8] cards;

    abstract void install(CpuBase cpu, AddressDecoder decoder, Rom mainRom);

    void reboot()
    {
        for (int p = 0; p < 8; ++p)
        {
            if (cards[p] !is null)
                cards[p].reboot();
        }
    }

    void reset()
    {
        for (int s = 0; s < 8; ++s)
        {
            if (cards[s] !is null)
                cards[s].reset();
        }
    }
}

class Peripherals_II : Peripherals
{
    void install(CpuBase cpu, AddressDecoder decoder, Rom mainRom)
    {
        auto diskController = new Controller();
        diskController.checkFinalCycle = &cpu.checkFinalCycle;
        cards[6] = diskController;    // XXX

        auto langCard = new LanguageCard();
        langCard.implementation.init(decoder, &mainRom.read, &mainRom.write);
        cards[0] = langCard;

        /+
        auto saturn = new Saturn128();
        saturn.init(decoder, &mainRom.read, &mainRom.write);
        cards[0] = saturn;
        +/
    }
}

class Peripherals_IIe : Peripherals
{
    void install(CpuBase cpu, AddressDecoder decoder, Rom mainRom)
    {
        auto diskController = new Controller();
        diskController.checkFinalCycle = &cpu.checkFinalCycle;
        cards[6] = diskController;    // XXX
    }
}

