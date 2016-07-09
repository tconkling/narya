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

import aspire.util.Cloneable;
import aspire.util.Equalable;
import aspire.util.Log;
import aspire.util.Util;

import com.threerings.io.ObjectInputStream;
import com.threerings.io.ObjectOutputStream;
import com.threerings.io.Streamable;
import com.threerings.io.TypedArray;
import com.threerings.util.ArrayIterator;
import com.threerings.util.Iterator;

/**
 * The distributed set class provides a means by which an unordered set of
 * objects can be maintained as a distributed object field. Entries can be
 * added to and removed from the set, requests for which will generate
 * events much like other distributed object fields.
 *
 * <p> Classes that wish to act as set entries must implement the {@link
 * Entry} interface which extends {@link Streamable} and adds the
 * requirement that the object provide a key which will be used to
 * identify entry equality. Thus an entry is declared to be in a set of
 * the object returned by that entry's {@link Entry#getKey} method is
 * equal (using {@link Object#equals}) to the entry returned by the {@link
 * Entry#getKey} method of some other entry in the set. Additionally, in
 * the case of entry removal, only the key for the entry to be removed
 * will be transmitted with the removal event to save network
 * bandwidth. Lastly, the object returned by {@link Entry#getKey} must be
 * a {@link Streamable} type.
 */
public class DSet
    implements Cloneable, Streamable
{
    /**
     * Returns the number of entries in this set.
     */
    public function size () :int
    {
        return _entries.length;
    }

    /**
     * Returns true if this set contains no entries.
     */
    public function isEmpty () :Boolean
    {
        return _entries.length == 0;
    }

   /**
     * Returns true if the set contains an entry whose
     * <code>getKey()</code> method returns a key that
     * <code>equals()</code> the key returned by <code>getKey()</code> of
     * the supplied entry. Returns false otherwise.
     */
    public function contains (elem :DSet_Entry) :Boolean
    {
        return containsKey(elem.getKey());
    }

    /**
     * Returns true if an entry in the set has a key that
     * <code>equals()</code> the supplied key. Returns false otherwise.
     */
    public function containsKey (key :Object) :Boolean
    {
        return get(key) != null;
    }

    /**
     * Returns the entry that matches (<code>getKey().equals(key)</code>)
     * the specified key or null if no entry could be found that matches
     * the key.
     */
    public function get (key :Object) :DSet_Entry
    {
        // o(n) for now
        for each (var entry :DSet_Entry in _entries) {
            if (Util.equals(key, entry.getKey())) {
                return entry;
            }
        }
        return null;
    }

    /**
     * Returns an iterator over the entries of this set. It does not
     * support modification (nor iteration while modifications are being
     * made to the set). It should not be kept around as it can quickly
     * become out of date.
     */
    public function iterator () :Iterator
    {
        return new ArrayIterator(_entries, false);
    }

    /**
     * Returns the elements of this distributed set in an Array.
     */
    public function toArray () :Array
    {
        return _entries.concat(); // makes a copy
    }

    /**
     * Adds the specified entry to the set. This should not be called
     * directly, instead the associated <code>addTo{Set}()</code> method
     * should be called on the distributed object that contains the set in
     * question.
     *
     * @return true if the entry was added, false if it was already in
     * the set.
     */
    internal function add (elem :DSet_Entry) :Boolean
    {
        if (_entries.length == 0) {
            // there is nothing in the map yet, check the key validity
            var key :Object = elem.getKey();
            if (!(key is Equalable) && !Util.isSimple(key)) {
                throw new Error("Element key is not 'simple' or Equalable");
            }

        } else if (contains(elem)) {
            Log.getLog(this).warning("Refusing to add duplicate entry " +
                "[set=" + this + ", entry=" + elem + "].");
            return false;
        }

        _entries.push(elem);
        return true;
    }

    /**
     * Removes the specified entry from the set. This should not be called
     * directly, instead the associated <code>removeFrom{Set}()</code>
     * method should be called on the distributed object that contains the
     * set in question.
     *
     * @return true if the entry was removed, false if it was not in the
     * set.
     */
    internal function remove (elem :DSet_Entry) :Boolean
    {
        return (null != removeKey(elem.getKey()));
    }

    /**
     * Removes from the set the entry whose key matches the supplied
     * key. This should not be called directly, instead the associated
     * <code>removeFrom{Set}()</code> method should be called on the
     * distributed object that contains the set in question.
     *
     * @return the old matching entry if found and removed, null if not
     * found.
     */
    internal function removeKey (key :Object) :DSet_Entry
    {
        // o(n) for now
        for (var ii :int = 0; ii < _entries.length; ii++) {
            var entry :DSet_Entry = _entries[ii];
            if (Util.equals(key, entry.getKey())) {
                _entries.splice(ii, 1);
                return entry;
            }
        }
        return null;
    }

    /**
     * Updates the specified entry by locating an entry whose key matches
     * the key of the supplied entry and overwriting it. This should not
     * be called directly, instead the associated
     * <code>update{Set}()</code> method should be called on the
     * distributed object that contains the set in question.
     *
     * @return the old entry that was replaced, or null if it was not
     * found (in which case nothing is updated).
     */
    internal function update (elem :DSet_Entry) :DSet_Entry
    {
        var key :Object = elem.getKey();
        for (var ii :int = 0; ii < _entries.length; ii++) {
            var entry :DSet_Entry = _entries[ii];
            if (Util.equals(key, entry.getKey())) {
                _entries[ii] = elem;
                return entry; // return the old entry
            }
        }
        return null;
    }

    // from interface Cloneable
    public function clone () :Object
    {
        var other :DSet = new DSet();
        for each (var val :DSet_Entry in _entries) {
            other._entries.push(val);
        }
        return other;
    }

    /**
     * Generates a string representation of this set instance.
     */
    public function toString () :String
    {
        return "(" + _entries.toString() + ")";
    }

    // documentation inherited from interface Streamable
    public function writeObject (out :ObjectOutputStream) :void
    {
        if (_entries.length > 0) {
            Log.getLog(this).warning("Error! We can't send DSets back to the server until we " +
                "fix up the actionscript implementation!");
            Log.dumpStack();
        }

        out.writeInt(_entries.length);
        for (var ii :int = 0; ii < _entries.length; ii++) {
            out.writeObject(_entries[ii]);
        }
    }

    // documentation inherited from interface Streamable
    public function readObject (ins :ObjectInputStream) :void
    {
        _entries.length = ins.readInt();
        for (var ii :int = 0; ii < _entries.length; ii++) {
            _entries[ii] = ins.readObject();
        }
    }

    /** The entries of the set (in a sparse array). */
    protected var _entries :TypedArray = TypedArray.create(DSet_Entry);
}
}
