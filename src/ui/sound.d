/+
 + ui/sound.d
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

module ui.sound;

import std.stdio;
import std.c.string;

import derelict.sdl.sdl;
import derelict.util.exception;

import timer;
import device.speaker;
import ui.inputevents;

static import host;

static this()
{
    soundCard = new SoundCardNo();
    if (host.SDL)
    {
        if (SDL_InitSubSystem(SDL_INIT_AUDIO) == -1)
        {
            writefln("%s", std.string.toString(SDL_GetError()));
            return;
        }
        auto checkCard = new SoundCardYes();
        if (checkCard.isActive)
            soundCard = checkCard;
    }
    host.delay.soundCardActive = &soundCard.getIsActive;
    host.delay.soundCardHasEnoughData = &soundCard.hasEnoughData;
}

SoundCard soundCard;

private:

class SoundCard
{
    bool isActive;

    // XXX hack for fast mode testing
    bool speedyMode;

    bool getIsActive()
    {
        return isActive;
    }

    abstract void installSpeaker(Speaker spkr);
    abstract void start();
    abstract void pause();
    abstract void resume();
    abstract void process();
    abstract bool hasEnoughData();
}

class SoundCardNo : SoundCard
{
    this()
    {
        isActive = false;
    }

    void installSpeaker(Speaker spkr) {}
    void start() {}
    void pause() {}
    void resume() {}
    void process() {}
    bool hasEnoughData() { return true; }  // XXX Throw exception?
}

class SoundCardYes : SoundCard
{
    SDL_AudioSpec audioRequest;
    short[] xferBuffer;
    short[] zeroBuffer;
    uint xferWriteIndex, xferReadIndex;
    Timer.Cycle soundCycle;
    Speaker speaker;

    static const int samplesPerCallback = 1024;
    static const int sampleFreq = 44100;

    this()
    {
        audioRequest.freq = sampleFreq;
        audioRequest.format = AUDIO_S16SYS;
        audioRequest.channels = 1;
        audioRequest.samples = samplesPerCallback;
        audioRequest.callback = &audioCallback;
        audioRequest.userdata = cast(void*)this;

        if (SDL_OpenAudio(&audioRequest, null) == -1)
        {
            writefln("%s", std.string.toString(SDL_GetError()));
            return;
        }

        xferBuffer.length = 8192;
        zeroBuffer.length = samplesPerCallback;
        isActive = true;
    }

    void installSpeaker(Speaker spkr)
    {
        speaker = spkr;
    }

    void start()
    {
        SDL_PauseAudio(0);
    }

    void pause()
    {
        SDL_PauseAudio(1);
        SDL_LockAudio();
    }

    void resume()
    {
        SDL_UnlockAudio();
        SDL_PauseAudio(0);
    }

    void process()
    {
        speaker.update();

        if (!speedyMode) // XXX
        {
            SDL_LockAudio();

            int inLength = speaker.mainIndex;
            short* inBuffer = speaker.mainBuffer.ptr;

            // truncate xfer buffer if it would overflow
            if (xferWriteIndex + inLength > xferBuffer.length)
            {
                memmove(xferBuffer.ptr, xferBuffer.ptr + xferReadIndex,
                        (xferBuffer.length - xferReadIndex) * 2);
                xferWriteIndex -= xferReadIndex;
                xferReadIndex = 0;
            }

            memcpy(xferBuffer.ptr + xferWriteIndex, inBuffer,
                    inLength * 2);
            xferWriteIndex += inLength;

            SDL_UnlockAudio();
        }
        finishProcessing();
    }

    void finishProcessing()
    {
        speaker.clearBuffer();
    }

    bool hasEnoughData()
    {
        if (speedyMode) return false; // XXX
        SDL_LockAudio();
        uint bufLen = xferWriteIndex - xferReadIndex;
        SDL_UnlockAudio();
        return bufLen > samplesPerCallback;
    }

    void fillAudio(Uint8* stream, int len)
    {
        int available = (xferWriteIndex - xferReadIndex) * 2;
        int readLen = (available > len) ? len : available;
        memcpy(stream, xferBuffer.ptr + xferReadIndex, readLen);
        if (input.pauseButton.getActive())
        {
            if (len > readLen)
                memcpy(stream + readLen, zeroBuffer.ptr, (len - readLen));
        }
        xferReadIndex += (readLen / 2);
    }
}

extern(C) void audioCallback(void* userdata, Uint8* stream, int len)
{
    (cast(SoundCardYes)userdata).fillAudio(stream, len);
}

