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

import aspire.util.Joiner;

/**
 * A simple serializable object implements the {@link Streamable}
 * interface and provides a default {@link #toString} implementation which
 * outputs all public members.
 */
public class SimpleStreamableObject implements Streamable
{
    // from interface Streamable
    public function readObject (ins :ObjectInputStream) :void
    {
        // nothing by default
    }

    // from interface Streamable
    public function writeObject (out :ObjectOutputStream) :void
    {
        // nothing by default
    }

    /**
     * Generates a string representation of this instance.
     */
    public function toString () :String
    {
        var j :Joiner = Joiner.createFor(this);
        toStringJoiner(j);
        return j.toString();
    }

    /**
     * Handles the toString-ification of all public members. Derived
     * classes can override and include non-public members if desired.
     */
    protected function toStringJoiner (j :Joiner): void
    {
        j.addFields(this);
    }
}
}
