/+
 + ui/textinput.d
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

module ui.textinput;

import std.stream;

import gtkglc.glgdktypes;
import gtk.Widget;

class TextInput
{
    File file;
    int pos;
    string line;
    void delegate() onFinish;
    bool eol;

    this(string filename, void delegate() finished)
    {
        onFinish = finished;
        file = new File(filename);
    }

    ~this()
    {
        delete file;
    }

    bool getLine()
    {
        if (file.eof())
        {
            onFinish();
            return false;
        }
        line = file.readLine() ~ x"0D";
        pos = 0;
        return true;
    }

    ubyte read()
    {
        if (line is null)
        {
            if (!getLine())
                return 0;
        }
        return cast(ubyte)line[pos];
    }

    void advancePos()
    {
        if (line is null) return;
        if (++pos >= line.length)
        {
            getLine();
        }
    }
}
