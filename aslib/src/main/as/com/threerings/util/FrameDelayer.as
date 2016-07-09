//
// aspire

package com.threerings.util {

import aspire.util.Log;
import aspire.util.Preconditions;

import flash.events.TimerEvent;
import flash.utils.Timer;

/**
 * Delays invocation of a function by one or more frames.
 * Similar to UIComponent's callLater, only flex-free.
 * If not running in the flash player, but instead in some tamarin environment like
 * thane, "frames" are a minimum of 1ms apart, but may be more if other code doesn't yield.
 */
public class FrameDelayer
{
    public function FrameDelayer () {
        _t.addEventListener(TimerEvent.TIMER, handleTimer);
    }

    /**
     * Delay invocation of the specified function closure by one frame.
     */
    public function delayFrame (fn :Function, args :Array = null) :void {
        delayFrames(1, fn, args);
    }

    /**
     * Delay invocation of the specified function closure by the given number of frames.
     */
    public function delayFrames (frames :int, fn :Function, args :Array = null) :void {
        if (_t == null) {
            throw new Error("Can't delay frames after the delayer has been shutdown");
        }
        Preconditions.checkArgument(frames > 0);
        Preconditions.checkNotNull(fn);
        var index :int = frames - 1;
        var frameData :Array = _queue[index] as Array;
        if (frameData == null) {
            _queue[index] = frameData = [];
        }
        frameData.push(fn, args);
        // start the timer if not already running
        _t.start();
    }

    /**
     * Cancels any delayed functions waiting to be called and prevents any future calls to delay.
     */
    public function cancel () :void {
        _t.stop();
        _t = null;
    }

    /**
     * Execute the closures for this "frame".
     * @private
     */
    protected function handleTimer (event :TimerEvent) :void {
        // get this frame's frameData
        var frameData :Array = _queue.shift() as Array;
        if (frameData != null) { // it could be a "placeholder frame" for a later frame..
            for (var ii :int = 0; ii < frameData.length; ii += 2) {
                var fn :Function = frameData[ii] as Function;
                var args :Array = frameData[ii + 1] as Array;
                try {
                    fn.apply(null, args);

                } catch (e :Error) {
                    Log.getLog(DelayUtil).warning("Error calling function", "args", args, e);
                }
            }
        }

        // if there is nothing else on the queue, stop the timer for now
        if (_queue.length == 0) {
            _t.stop();
        }
    }

    /** The queue of frameDatas. @private */
    protected var _queue :Array = [];

    /** A timer that will fire every "frame". @private */
    protected var _t :Timer = new Timer(1);
}
}
