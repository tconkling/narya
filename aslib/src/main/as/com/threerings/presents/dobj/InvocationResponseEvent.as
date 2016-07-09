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

package com.threerings.presents.dobj {

import aspire.util.Joiner;

import com.threerings.io.ObjectInputStream;
import com.threerings.io.ObjectOutputStream;

/**
 * Used to dispatch an invocation response from the server to the client.
 *
 * @see DObjectManager#postEvent
 */
public class InvocationResponseEvent extends DEvent
{
    /**
     * Constructs a new invocation response event on the specified target
     * object with the supplied code, method and arguments.
     *
     * @param targetOid the object id of the object on which the event is
     * to be dispatched.
     * @param requestId the id of the request to which we are responding.
     * @param methodId the method to be invoked.
     * @param args the arguments for the method. This array should contain
     * only values of valid distributed object types.
     */
    public function InvocationResponseEvent (
            targetOid :int = 0, requestId :int = 0, methodId :int = 0,
            args :Array = null)
    {
        super(targetOid);

        // only init these values if they were specified
        if (arguments.length > 0) {
            _requestId = requestId;
            _methodId = methodId;
            _args = args;
        }
    }

    /**
     * Returns the invocation request id associated with this response.
     */
    public function getRequestId () :int
    {
        return _requestId;
    }

    /**
     * Returns the method associated with this response.
     */
    public function getMethodId () :int
    {
        return _methodId;
    }

    /**
     * Returns the arguments associated with this response.
     */
    public function getArgs () :Array
    {
        return _args;
    }

    /**
     * Applies this attribute change to the object.
     */
    override public function applyToObject (target :DObject) :Boolean
        //throws ObjectAccessException
    {
        // nothing to do here
        return true;
    }

    // documentation inherited
    override protected function notifyListener (listener :Object) :void
    {
        // nothing to do here
    }

    // documentation inherited
    override protected function toStringJoiner (j :Joiner) :void
    {
        super.toStringJoiner(j);
        j.add("reqId", _requestId, "methodId", _methodId, "args", _args);
    }

    // documentation inherited
    override public function writeObject (out :ObjectOutputStream) :void
    {
        super.writeObject(out);
        out.writeShort(_requestId);
        out.writeByte(_methodId);
        out.writeField(_args);
    }

    // documentation inherited
    override public function readObject (ins :ObjectInputStream) :void
    {
        super.readObject(ins);
        _requestId = ins.readShort();
        _methodId = ins.readByte();
        _args = (ins.readField(Array) as Array);
    }

    /** The id of the request with which this response is associated. */
    protected var _requestId :int;

    /** The id of the method being invoked. */
    protected var _methodId :int;

    /** The arguments to the method being invoked. */
    protected var _args :Array;
}
}
