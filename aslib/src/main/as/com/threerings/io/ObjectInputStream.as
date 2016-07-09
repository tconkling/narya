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

import aspire.util.ClassUtil;
import aspire.util.Log;

import com.threerings.util.Long;

import flash.errors.IOError;
import flash.errors.MemoryError;
import flash.utils.ByteArray;
import flash.utils.IDataInput;

public class ObjectInputStream
{
    /** Enables verbose object I/O debugging. */
    public static const DEBUG :Boolean = false;

    public function ObjectInputStream (source :IDataInput = null, clientProps :Object = null)
    {
        _source = source || new ByteArray();
        _cliProps = clientProps || {};
    }

    /**
     * Set a new source from which to read our data.
     */
    public function setSource (source :IDataInput) :void
    {
        _source = source;
    }

    /**
     * Return a "client property" with the specified name.
     * Actionscript only.
     */
    public function getClientProperty (name :String) :*
    {
        return _cliProps[name];
    }

    /**
     * Reads the next Object (or null) from the stream and returns it as * so that you may assign
     * to any variable without casting. It is strongly recommended that you pass a 'checkType'
     * parameter so that the type of the Object is verified to be what you believe it to be,
     * thus helping you detect streaming errors as quickly as possible.
     *
     * @param checkType optional type to check the read object against
     * @return the Object read, or null.
     * @throws TypeError if the object is read successfully but is the wrong type
     *
     * @example This demonstrates how to type-check the objects read off the stream without
     * having to cast them.
     * <listing version="3.0">
     *
     * public function readObject (ins :ObjectInputStream) :void
     * {
     *     _scoops = ins.readObject(Array);
     *     _coneType = ins.readObject(Cone);
     * }
     *
     * protected var _scoops :Array;
     * protected var _coneType :Cone;
     * </listing>
     */
    public function readObject (checkType :Class = null) :*
        //throws IOError
    {
        var DEBUG_ID :String = "[" + (++_debugObjectCounter) + "] ";
        try {
            // read in the class code for this instance
            var code :int = readShort();

            // a zero code indicates a null value
            if (code == 0) {
                if (DEBUG) log.debug(DEBUG_ID + "Read null");
                return null;
            }

            var cmap :ClassMapping;

            // if the code is negative, that means we've never seen it
            // before and class metadata follows
            if (code < 0) {
                // first swap the code into positive land
                code *= -1;

                // read in the class metadata
                var jname :String = readUTF();
//                log.debug("read jname: " + jname);
                var streamer :Streamer = Streamer.getStreamerByJavaName(jname);
                if (streamer == null) {
                    log.warning("OMG, cannot stream " + jname);
                    return null;
                }
                if (DEBUG) log.debug(DEBUG_ID + "Got streamer (" + streamer + ")");

                cmap = new ClassMapping(code, streamer);
                _classMap[code] = cmap;
                if (DEBUG) log.debug(DEBUG_ID + "Created mapping: (" + code + "): " + jname);

            } else {
                cmap = (_classMap[code] as ClassMapping);
                if (null == cmap) {
                    throw new IOError("Read object for which we have no " +
                        "registered class metadata [code=" + code + "].");
                }
                if (DEBUG) {
                    log.debug(DEBUG_ID + "Read known code: (" + code + ": " +
                        cmap.streamer.getJavaClassName() + ")");
                }
            }

//            log.debug("Creating object sleeve...");
            var target :Object = cmap.streamer.createObject(this);
            //log.debug("Reading object...");
            readBareObjectImpl(target, cmap.streamer);
            if (DEBUG) log.debug(DEBUG_ID + "Read object: " + target);
            if (checkType != null && !(target is checkType)) {
                throw new TypeError(
                    "Cannot convert " + ClassUtil.getClass(target) + " to " + checkType);
            }
            return target;

        } catch (me :MemoryError) {
            throw new IOError("out of memory" + me.message);
        }
        return null; // not reached: compiler dumb
    }

    public function readBareObject (obj :Object) :void
        //throws IOError
    {
        readBareObjectImpl(obj, Streamer.getStreamer(obj));
    }

    public function readBareObjectImpl (obj :Object, streamer :Streamer) :void
    {
        _current = obj;
        _streamer = streamer;
        try {
            _streamer.readObject(obj, this);

        } finally {
            // clear out our current object references
            _current = null;
            _streamer = null;
        }
    }

    /**
     * Called to read an Object of a known final type into a Streamable object.
     *
     * @param type either a String representing the java type,
     *             a Class representing the actionscript type,
     *             or the Streamer to be used to read the field.
     */
    public function readField (type :Object) :*
        //throws IOError
    {
        if (!readBoolean()) {
            return null;
        }

        var streamer :Streamer;
        if (type is Streamer) {
            streamer = Streamer(type);
        } else {
            var jname :String = type as String;
            if (type is Class) {
                jname = Translations.getToServer(ClassUtil.getClassName(type));
            }
            streamer= Streamer.getStreamerByJavaName(jname);
            if (streamer == null) {
                throw new Error("Cannot field stream " + type);
            }
        }

        var obj :Object = streamer.createObject(this);
        readBareObjectImpl(obj, streamer);
        return obj;
    }

    public function defaultReadObject () :void
        //throws IOError
    {
        _streamer.readObject(_current, this);
    }

    public function readBoolean () :Boolean
        //throws IOError
    {
        return _source.readBoolean();
    }

    public function readByte () :int
        //throws IOError
    {
        return _source.readByte();
    }

    /**
     * Read bytes into the byte array. If length is not specified, then
     * enough bytes to fill the array (from the offset) are read.
     */
    public function readBytes (
        bytes :ByteArray, offset :uint = 0, length :uint = uint.MAX_VALUE) :void
        //throws IOError
    {
        // if no length specified then fill the ByteArray
        if (length == uint.MAX_VALUE) {
            length = bytes.length - offset;
        }
        // And, if we really want to read 0 bytes then just don't do anything, because an
        // IDataInput will read *all available bytes* when the specified length is 0.
        if (length > 0) {
            _source.readBytes(bytes, offset, length);
        }
    }

    public function readDouble () :Number
        //throws IOError
    {
        return _source.readDouble();
    }

    public function readFloat () :Number
        //throws IOError
    {
        return _source.readFloat();
    }

    public function readLong () :Long
    {
        const result :Long = new Long();
        readBareObject(result);
        return result;
    }

    public function readInt () :int
        //throws IOError
    {
        return _source.readInt();
    }

    public function readShort () :int
        //throws IOError
    {
        return _source.readShort();
    }

    public function readUTF () :String
        //throws IOError
    {
        return _source.readUTF();
    }

    /** Named "client properties" that we can provide to deserialized objects. */
    protected var _cliProps :Object;

    /** The target DataInput that we route input from. */
    protected var _source :IDataInput;

    /** The object currently being read from the stream. */
    protected var _current :Object;

    /** The streamer being used currently. */
    protected var _streamer :Streamer;

    /** A map of short class code to ClassMapping info. */
    protected var _classMap :Array = new Array();

    private static var _debugObjectCounter :int = 0;

    private static const log :Log = Log.getLog(ObjectInputStream);
}
}
