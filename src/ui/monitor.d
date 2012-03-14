/+
 + ui/monitor.d
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

private import gtk.DrawingArea;
private import glgtk.GLCapability;
private import glgdk.GLDrawable;
private import glgdk.GLConfig;
private import glgdk.GLContext;
private import gtkglc.glgdktypes;
private import gtk.Widget;
private import gtk.ToggleToolButton;

import video.base;

Monitor monitor;

class Monitor : DrawingArea
{
	mixin GLCapability;

    Screen screen;

	this()
	{
		setGLCapability(new GLConfig(
                    GLConfigMode.MODE_RGB | GLConfigMode.MODE_DOUBLE,
                    GLConfigMode.MODE_RGB));
	}

    void installScreen(Screen screen_)
    {
        screen = screen_;
        setSizeRequest(screen.width, screen.height * 2);
    }

	bool initGL()
	{
		resizeGL(null);

        glDisable(GL_ALPHA_TEST);
        glDisable(GL_BLEND);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_FOG);
        glDisable(GL_LIGHTING);
        glDisable(GL_LOGIC_OP);
        glDisable(GL_STENCIL_TEST);
        glDisable(GL_TEXTURE_1D);
        glDisable(GL_TEXTURE_2D);

        glPixelZoom(1.0, -2.0);

		return true;
	}

	bool drawGL(GdkEventExpose* event = null)
	{
        glRasterPos2i(-1, 1);
        glDrawPixels(screen.width, screen.height, GL_RGB,
                GL_UNSIGNED_SHORT_5_6_5, screen.data);
		return true;
	}

	bool resizeGL(GdkEventConfigure* event = null)
	{
        glViewport(0, 0, screen.width, screen.height * 2);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();

		return true;
	}
}

