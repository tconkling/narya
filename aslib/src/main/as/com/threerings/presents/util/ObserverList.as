//
// aspire

package com.threerings.presents.util {

import aspire.util.*;

public class ObserverList
{
    /** A notification ordering policy indicating that the observers
     * should be notified in the order they were added and that the
     * notification should be done on a snapshot of the array. */
    public static const SAFE_IN_ORDER_NOTIFY :int = 1;

    /** A notification ordering policy wherein the observers are notified
     * last to first so that they can be removed during the notification
     * process and new observers added will not inadvertently be notified
     * as well, but no copy of the observer list need be made. This will
     * not work if observers are added or removed from arbitrary positions
     * in the list during a notification call. */
    public static const FAST_UNSAFE_NOTIFY :int = 2;

    /**
     * Constructor
     */
    public function ObserverList (notifyPolicy :int = 2)
    {
        _notifyPolicy = notifyPolicy;
    }

    /**
     * Add an observer to this list.
     *
     * @param index the index at which to add the observer, or -1 for the end.
     */
    public function add (observer :Object, index :int = -1) :void
    {
        if (!Arrays.contains(_list, observer)) {
            _list.splice(index, 0, observer); // -1 to splice means "end"
        }
    }

    /**
     * Return the size of the list.
     */
    public function size () :int
    {
        return _list.length;
    }

    /**
     * Remove an observer from this list.
     */
    public function remove (observer :Object) :void
    {
        Arrays.removeFirst(_list, observer);
    }

    /**
     * Apply some operation to all observers.
     * The function to be passed in should expect one argument and either
     * return void or a Boolean. If returning a Boolean, returning false
     * indicates that the observer should be removed from the list.
     */
    public function apply (func :Function) :void
    {
        var list :Array = _list;
        if (_notifyPolicy == SAFE_IN_ORDER_NOTIFY) {
            list = list.concat(); // make a duplicate
            list.reverse(); // reverse it so that we start with earlier obs
        }
        for (var ii :int = list.length-1; ii >= 0; ii--) {
            try {
                var result :* = func(list[ii]);
                if (result !== undefined && !Boolean(result)) {
                    // remove it if directed to do so
                    remove(list[ii]);
                }
            } catch (err :Error) {
                Log.getLog(this).warning("ObserverOp choked during notification.", err);
            }
        }
    }

    /** Our notification policy. */
    protected var _notifyPolicy :int;

    /** The actual list of observers. */
    protected var _list :Array = new Array();
}
}
