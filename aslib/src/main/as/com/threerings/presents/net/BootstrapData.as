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

package com.threerings.presents.net {

import aspire.util.Log;

import com.threerings.io.ObjectInputStream;
import com.threerings.io.ObjectOutputStream;
import com.threerings.io.Streamable;

/**
 * A BoostrapData object is communicated back to the client after authentication has succeeded and
 * after the server is fully prepared to deal with the client. It contains information the client
 * will need to interact with the server.
 */
public class BootstrapData
    implements Streamable
{
    /** The unique id of the client's connection. */
    public var connectionId :int;

    /** The oid of this client's associated distributed object. */
    public var clientOid :int;

    /** A list of handles to invocation services. */
    public var services :Array;

    // documentation inherited from interface Streamable
    public function writeObject (out :ObjectOutputStream) :void
    {
        Log.getLog(this).warning("This is client code: BootstrapData shouldn't be written");
    }

    // documentation inherited from interface Streamable
    public function readObject (ins :ObjectInputStream) :void
    {
        connectionId = ins.readInt();
        clientOid = ins.readInt();
        services = (ins.readField("java.util.List") as Array);
    }
}
}
