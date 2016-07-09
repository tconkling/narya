//
// aspire

package com.threerings.util {

import aspire.util.*;

import flash.errors.IllegalOperationError;
import flash.events.Event;
import flash.events.IEventDispatcher;

public class CommandEvent extends Event
{
    /** The event type for all controller events. */
    public static const COMMAND :String = "commandEvt";

    /**
     * Use this method to dispatch CommandEvents.
     */
    public static function dispatch (
        disp :IEventDispatcher, cmdOrFn :Object, arg :Object = null) :void
    {
        if (cmdOrFn is Function) {
            var fn :Function = (cmdOrFn as Function);
            // build our args array
            var args :Array;
            if (arg == null) {
                args = null;

            } else if (arg is Array) {
                // if we were passed an array, treat it as the arg array.
                // Note: if you want to pass a single array param, you've
                // got to wrap it in another array, so sorry.
                args = arg as Array;

            } else {
                args = [ arg ];
            }

            // now trying calling it
            try {
                // TODO: Tim Conkling has determined that fn.length will tell you the required
                // number of args to a function. We may be able to do something smarter here
                // with that, but I'll wait until it's a problem.
                fn.apply(null, args);
            } catch (err :Error) {
                Log.getLog(CommandEvent).warning("Unable to call callback.", err);
            }

        } else if (cmdOrFn is String) {
            var cmd :String = String(cmdOrFn);
            // Create the event to dispatch
            var event :CommandEvent = create(cmd, arg);

            // Dispatch it. A return value of true means that the event was
            // never cancelled, so we complain.
            if (disp == null || disp.dispatchEvent(event)) {
                Log.getLog(CommandEvent).warning("Unhandled controller command",
                    "cmd", cmd, "arg", arg, "disp", disp);
            }

        } else {
            throw new ArgumentError("Argument 'cmdOrFn' must be a command (String) or a Function");
        }
    }

    /**
     * Configure a bridge from something like a pop-up window to an alternate target.
     */
    public static function configureBridge (
        source :IEventDispatcher, target :IEventDispatcher) :void
    {
        source.addEventListener(COMMAND,
            function (event :CommandEvent) :void {
                event.markAsHandled();
                dispatch(target, event.command, event.arg);
            },
            false, -1);
    }

    /** The command. */
    public var command :String;

    /** An optional argument. */
    public var arg :Object;

    /**
     * Command events may not be directly constructed, use the dispatch
     * method to do your work.
     */
    public function CommandEvent (command :String, arg :Object)
    {
        super(COMMAND, true, true);
        if (_blockConstructor) {
            throw new IllegalOperationError();
        }
        this.command = command;
        this.arg = arg;
    }

    /**
     * Mark this command as handled, stopping its propagation up the
     * hierarchy.
     */
    public function markAsHandled () :void
    {
        preventDefault();
        stopImmediatePropagation();
    }

    override public function clone () :Event
    {
        return create(command, arg);
    }

    override public function toString () :String
    {
        return "CommandEvent[" + command + " (" + arg + ")]";
    }

    /**
     * A factory method for privately creating command events.
     */
    protected static function create (cmd :String, arg :Object) :CommandEvent
    {
        var event :CommandEvent;
        _blockConstructor = false;
        try {
            event = new CommandEvent(cmd, arg);
        } finally {
            _blockConstructor = true;
        }
        return event;
    }

    /** Used to prevent unauthorized construction. */
    protected static var _blockConstructor :Boolean = true;
}
}
