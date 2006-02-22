package com.threerings.presents.dobj {

import flash.util.StringBuilder;

import com.threerings.io.ObjectInputStream;
import com.threerings.io.ObjectOutputStream;


/**
 * An element updated event is dispatched when an element of an array
 * field in a distributed object is updated. It can also be constructed to
 * request the update of an entry and posted to the dobjmgr.
 *
 * @see DObjectManager#postEvent
 */
public class ElementUpdatedEvent extends NamedEvent
{
    /**
     * Constructs a new element updated event on the specified target
     * object with the supplied attribute name, element and index.
     *
     * @param targetOid the object id of the object whose attribute has
     * changed.
     * @param name the name of the attribute (data member) for which an
     * element has changed.
     * @param value the new value of the element (in the case of primitive
     * types, the reflection-defined object-alternative is used).
     * @param oldValue the previous value of the element (in the case of
     * primitive types, the reflection-defined object-alternative is
     * used).
     * @param index the index in the array of the updated element.
     */
    public function ElementUpdatedEvent (
        targetOid :int, name :String, value :Object, oldValue :Object,
        index :int)
    {
        super(targetOid, name);
        _value = value;
        _oldValue = oldValue;
        _index = index;
    }

    /**
     * Returns the new value of the element.
     */
    public function getValue () :Object
    {
        return _value;
    }

    /**
     * Returns the value of the element prior to the application of this
     * event.
     */
    public function getOldValue () :Object
    {
        return _oldValue;
    }

    /**
     * Returns the index of the element.
     */
    public function getIndex () :int
    {
        return _index;
    }

    /**
     * Applies this element update to the object.
     */
    public override function applyToObject (target :DObject) :Boolean
        //throws ObjectAccessException
    {
        if (_oldValue === UNSET_OLD_ENTRY) {
            _oldValue = target[_name][_index];
        }
        target[_name][_index] = _value;
        return true;
    }

    // documentation inherited
    public override function writeObject (out :ObjectOutputStream) :void
    {
        super.writeObject(out);
        out.writeObject(_value);
        out.writeInt(_index);
    }

    // documentation inherited
    public override function readObject (ins :ObjectInputStream) :void
    {
        super.readObject(ins);
        _value = ins.readObject();
        _index = ins.readInt();
    }

    // documentation inherited
    internal override function notifyListener (listener :Object) :void
    {
        if (listener is ElementUpdateListener) {
            listener.elementUpdated(this);
        }
    }

    // documentation inherited
    protected override function toStringBuf (buf :StringBuilder) :void
    {
        buf.append("UPDATE:");
        super.toStringBuf(buf);
        buf.append(", value=", _value);
        buf.append(", index=", _index);
    }

    protected var _value :Object;
    protected var _index :int;
    protected var _oldValue :Object = UNSET_OLD_ENTRY;
}
}