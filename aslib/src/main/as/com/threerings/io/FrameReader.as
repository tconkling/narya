//
// $Id$
//
// Narya library - tools for developing networked games
// Copyright (C) 2002-2012 Three Rings Design, Inc., All Rights Reserved
// http://code.google.com/p/narya/
//
// This library is free software; you can redistribute it and/or modify it
// under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation; either version 2.1 of the License, or
// (at your option) any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

package com.threerings.io {

import aspire.util.Log;

import flash.events.EventDispatcher;
import flash.events.ProgressEvent;
import flash.net.Socket;
import flash.utils.ByteArray;
import flash.utils.Endian;

/**
 * Reads socket data until a complete frame is available.
 * This dispatches a FrameAvailableEvent.FRAME_AVAILABLE once a frame
 * has been fully read off the socket and is ready for decoding.
 */
public class FrameReader extends EventDispatcher
{
    public function FrameReader (socket :Socket)
    {
        _socket = socket;
        _socket.addEventListener(ProgressEvent.SOCKET_DATA, socketHasData);
    }

    /**
     * Stop listening on the socket.
     */
    public function shutdown () :void
    {
        _socket.removeEventListener(ProgressEvent.SOCKET_DATA, socketHasData);
    }

    /**
     * Called when our socket has data that we can read.
     */
    protected function socketHasData (event :ProgressEvent) :void
    {
        try {
            readAvailable();
        } catch (e :Error) {
            Log.getLog(this).warning("Error reading socket data", e);
        }
    }

    protected function readAvailable () :void
    {
        if (ObjectInputStream.DEBUG) {
            Log.getLog(this).debug("socketHasData(" + _socket.bytesAvailable + ")");
        }

        while (_socket.connected && _socket.bytesAvailable > 0) {
            if (_curData == null) {
                if (_socket.bytesAvailable < HEADER_SIZE) {
                    // if there are less bytes available than a header, let's
                    // just leave them on the socket until we can read the length
                    // all at once
                    return;
                }
                // the length specified is the length of the entire frame,
                // including the length of the bytes used to encode the length.
                // (I think this is pretty silly).
                // So for our purposes we subtract 4 bytes so we know how much
                // more data is in the frame.
                _length = _socket.readInt() - HEADER_SIZE;
                _curData = new ByteArray();
                _curData.endian = Endian.BIG_ENDIAN;
            }

            // read bytes: either as much as possible or up to the end of the frame
            var toRead :int = Math.min(_length - _curData.length, _socket.bytesAvailable);
            // Just in case, if the amount needed is 0, don't do anything!
            // Passing 0 causes it to read *all available bytes*.
            if (toRead != 0) {
                _socket.readBytes(_curData, _curData.length, toRead);
            }

            if (_length === _curData.length) {
                // we have now read a complete frame, let us dispatch the data
                _curData.position = 0; // move the read pointer to the beginning
                if (ObjectInputStream.DEBUG) {
                    Log.getLog(this).debug("+ FrameAvailable");
                }
                dispatchEvent(new FrameAvailableEvent(_curData));
                _curData = null; // clear, so we know we need to first read length
            }
        }
    }

    protected var _socket :Socket;
    protected var _curData :ByteArray;
    protected var _length :int;

    /** The number of bytes in the frame header (a 32-bit integer). */
    protected const HEADER_SIZE :int = 4;
}
}
