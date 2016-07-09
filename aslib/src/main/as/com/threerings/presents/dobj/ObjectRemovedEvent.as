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
 * An object removed event is dispatched when an object is removed from an
 * <code>OidList</code> attribute of a distributed object. It can also be
 * constructed to request the removal of an oid from an
 * <code>OidList</code> attribute of an object and posted to the dobjmgr.
 *
 * @see DObjectManager#postEvent
 */
public class ObjectRemovedEvent extends NamedEvent
{
    /**
     * Constructs a new object removed event on the specified target
     * object with the supplied oid list attribute name and object id to
     * remove.
     *
     * @param targetOid the object id of the object from whose oid list we
     * will remove an oid.
     * @param name the name of the attribute (data member) from which to
     * remove the specified oid.
     * @param oid the oid to remove from the oid list attribute.
     */
    public function ObjectRemovedEvent (
            targetOid :int = 0, name :String = null, oid :int = 0)
    {
        super(targetOid, name);

        // only init these values if they were specified
        if (arguments.length > 0) {
            _oid = oid;
        }
    }

    /**
     * Returns the oid that has been removed.
     */
    public function getOid () :int
    {
        return _oid;
    }

    /**
     * Applies this event to the object.
     */
    override public function applyToObject (target :DObject) :Boolean
        //throws ObjectAccessException
    {
        var list :OidList = (target[_name] as OidList);
        list.remove(_oid);
        return true;
    }

    // documentation inherited
    override protected function notifyListener (listener :Object) :void
    {
        if (listener is OidListListener) {
            listener.objectRemoved(this);
        }
    }

    override public function writeObject (out :ObjectOutputStream) :void
    {
        super.writeObject(out);
        out.writeInt(_oid);
    }

    override public function readObject (ins :ObjectInputStream) :void
    {
        super.readObject(ins);
        _oid = ins.readInt();
    }

    // documentation inherited
    override protected function toStringJoiner (j :Joiner) :void
    {
        super.toStringJoiner(j);
        j.add("oid", _oid);
    }

    protected var _oid :int;
}
}
