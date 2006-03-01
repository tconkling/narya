package com.threerings.presents.dobj {

import flash.util.StringBuilder;

import com.threerings.io.ObjectInputStream;
import com.threerings.io.ObjectOutputStream;
import com.threerings.io.Streamable;

import com.threerings.util.Comparable;

import com.threerings.presents.Log;

public /* abstract */ class DEvent
    implements Streamable
{
    public function DEvent (targetOid :int)
    {
        _toid = targetOid;
    }

    /**
     * Returns the oid of the object that is the target of this event.
     */
    public function getTargetOid () :int
    {
        return _toid;
    }


    /**
     * Some events are used only internally on the server and need not be
     * broadcast to subscribers, proxy or otherwise. Such events can
     * return true here and short-circuit the normal proxy event dispatch
     * mechanism.
     */
    public function applyToObject (target :DObject) :Boolean
    {
        // TODO
        Log.warning("DEvent.applyToTarget is really an abstract method.");
        return false;
    }

    /**
     * Returns the object id of the client that generated this event. If
     * the event was generated by the server, the value returned will be
     * -1. This is not valid on the client, it will return -1 for all
     * events there (it is primarily provided to allow for event-level
     * access control).
     */
    public function getSourceOid () :int
    {
        return _soid;
    }

    /**
     * Do not call this method. Sets the source oid of the client that
     * generated this event. It is automatically called by the client
     * management code when a client forwards an event to the server.
     */
    public function setSourceOid (sourceOid :int) :void
    {
        _soid = sourceOid;
    }

    /**
     * We want to make the notifyListener method visible to DObject.
     */
    internal function friendNotifyListener (listener :Object) :void
    {
        notifyListener(listener);
    }

    /**
     * Events with associated listener interfaces should implement this
     * function and notify the supplied listener if it implements their
     * event listening interface. For example, the {@link
     * AttributeChangedEvent} will notify listeners that implement {@link
     * AttributeChangeListener}.
     */
    protected function notifyListener (listener :Object) :void
    {
        // the default is to do nothing
    }

    // documentation inherited from interface Streamable
    public function writeObject (out :ObjectOutputStream) :void
    {
        out.writeInt(_toid);
    }

    // documentation inherited from interface Streamable
    public function readObject (ins :ObjectInputStream) :void
    {
        _toid = ins.readInt();
    }

    /**
     * Constructs and returns a string representation of this event.
     */
    public function toString () :String
    {
        var buf :StringBuilder = new StringBuilder();
        buf.append("[");
        toStringBuf(buf);
        buf.append("]");
        return buf.toString();
    }

    /**
     * This should be overridden by derived classes (which should be sure
     * to call <code>super.toString()</code>) to append the derived class
     * specific event information to the string buffer.
     */
    protected function toStringBuf (buf :StringBuilder) :void
    {
        buf.append("targetOid=", _toid);
    }

    /** The oid of the object that is the target of this event. */
    protected var _toid :int;

    /** The oid of the client that generated this event. */
    protected var _soid :int = -1;

    protected static const UNSET_OLD_ENTRY :DSetEntry = new DummyEntry();
}
}

class DummyEntry implements com.threerings.presents.dobj.DSetEntry
{
    public function getKey () :Object
    {
        return null;
    }

    public function writeObject (out :com.threerings.io.ObjectOutputStream) :void
    {
    }

    public function readObject (ins :com.threerings.io.ObjectInputStream) :void
    {
    }
}
