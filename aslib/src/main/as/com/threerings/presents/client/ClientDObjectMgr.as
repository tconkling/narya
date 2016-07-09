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

package com.threerings.presents.client {

import aspire.util.Log;
import aspire.util.Map;
import aspire.util.Maps;

import com.threerings.presents.dobj.CompoundEvent;
import com.threerings.presents.dobj.DEvent;
import com.threerings.presents.dobj.DObject;
import com.threerings.presents.dobj.DObjectManager;
import com.threerings.presents.dobj.ObjectAccessError;
import com.threerings.presents.dobj.ObjectDestroyedEvent;
import com.threerings.presents.dobj.Subscriber;
import com.threerings.presents.net.BootstrapNotification;
import com.threerings.presents.net.CompoundDownstreamMessage;
import com.threerings.presents.net.DownstreamMessage;
import com.threerings.presents.net.EventNotification;
import com.threerings.presents.net.FailureResponse;
import com.threerings.presents.net.ForwardEventRequest;
import com.threerings.presents.net.ObjectResponse;
import com.threerings.presents.net.PongResponse;
import com.threerings.presents.net.SubscribeRequest;
import com.threerings.presents.net.UnsubscribeRequest;
import com.threerings.presents.net.UnsubscribeResponse;
import com.threerings.presents.net.UpdateThrottleMessage;

import flash.events.TimerEvent;
import flash.utils.Timer;
import flash.utils.getTimer;

/**
 * The client distributed object manager manages a set of proxy objects
 * which mirror the distributed objects maintained on the server.
 * Requests for modifications, etc. are forwarded to the server and events
 * are dispatched from the server to this client for objects to which this
 * client is subscribed.
 */
public class ClientDObjectMgr
    implements DObjectManager
{
    private static const log :Log = Log.getLog(ClientDObjectMgr);

    /**
     * Constructs a client distributed object manager.
     *
     * @param comm a communicator instance by which it can communicate
     * with the server.
     * @param client a reference to the client that is managing this whole
     * communications and event dispatch business.
     */
    public function ClientDObjectMgr (comm :Communicator, client :Client)
    {
        _comm = comm;
        _client = client;

        // register a flush interval
        _flushInterval = new Timer(FLUSH_INTERVAL);
        _flushInterval.addEventListener(TimerEvent.TIMER, flushObjects);
        _flushInterval.start();
    }

    /**
     * Called when the client is cleaned up due to having disconnected from the server.
     */
    public function cleanup () :void
    {
        // tell any pending object subscribers that they're not getting their bits
        for each (var req :PendingRequest in _penders.values()) {
            for each (var sub :Subscriber in req.targets) {
                sub.requestFailed(req.oid, new ObjectAccessError("Client connection closed"));
            }
        }
        _penders.clear();
        _flushes.clear();
        _dead.clear();
        _ocache.clear();

        _flushInterval.stop();
        _flushInterval.removeEventListener(TimerEvent.TIMER, flushObjects);
        _flushInterval = null;
   }

    // documentation inherited from interface DObjectManager
    public function isManager (object :DObject) :Boolean
    {
        // we are never authoritative in the present implementation
        return false;
    }

    // inherit documentation from the interface DObjectManager
    public function subscribeToObject (oid :int, target :Subscriber) :void
    {
        if (oid <= 0) {
            target.requestFailed(oid, new ObjectAccessError("Invalid oid " + oid + "."));
        } else {
            doSubscribe(oid, target);
        }
    }

    // inherit documentation from the interface DObjectManager
    public function unsubscribeFromObject (oid :int, target :Subscriber) :void
    {
        doUnsubscribe(oid, target);
    }

    // inherit documentation from the interface
    public function postEvent (event :DEvent) :void
    {
        // send a forward event request to the server
        _comm.postMessage(new ForwardEventRequest(event));
    }

    // inherit documentation from the interface
    public function removedLastSubscriber (
            obj :DObject, deathWish :Boolean) :void
    {
        // if this object has a registered flush delay, don't can it just
        // yet, just slip it onto the flush queue
        for each (var dclass :Class in _delays.keys()) {
            if (obj is dclass) {
                var expire :Number = getTimer() + Number(_delays.get(dclass));
                _flushes.put(obj.getOid(), new FlushRecord(obj, expire));
//                 log.info("Flushing " + obj.getOid() + " at " +
//                          new java.util.Date(expire));
                return;
            }
        }

        // if we didn't find a delay registration, flush immediately
        flushObject(obj);
    }

    /**
     * Registers an object flush delay.
     *
     * @see Client#registerFlushDelay
     */
    public function registerFlushDelay (objclass :Class, delay :Number) :void
    {
        _delays.put(objclass, delay);
    }

    /**
     * Called by the communicator when a downstream message arrives from
     * the network layer. We queue it up for processing and request some
     * processing time on the main thread.
     */
    public function processMessage (msg :DownstreamMessage) :void
    {
        // do the proper thing depending on the object
        if (msg is EventNotification) {
            var evt :DEvent = (msg as EventNotification).getEvent();
//             log.info("Dispatch event: " + evt);
            dispatchEvent(evt);

        } else if (msg is BootstrapNotification) {
            _client.gotBootstrap((msg as BootstrapNotification).getData(), this);

        } else if (msg is ObjectResponse) {
            registerObjectAndNotify((msg as ObjectResponse).getObject());

        } else if (msg is UnsubscribeResponse) {
            var oid :int = (msg as UnsubscribeResponse).getOid();
            if (_dead.remove(oid) == null) {
                log.warning("Received unsub ACK from unknown object [oid=" + oid + "].");
            }

        } else if (msg is FailureResponse) {
            notifyFailure((msg as FailureResponse).getOid(), (msg as FailureResponse).getMessage());

        } else if (msg is PongResponse) {
            _client.gotPong(msg as PongResponse);

        } else if (msg is UpdateThrottleMessage) {
            _client.setOutgoingMessageThrottle((msg as UpdateThrottleMessage).messagesPerSec);
        } else if (msg is CompoundDownstreamMessage) {
            for each (var submsg :DownstreamMessage in CompoundDownstreamMessage(msg).msgs) {
                processMessage(submsg);
            }
        }
    }

    /**
     * Called when a new event arrives from the server that should be
     * dispatched to subscribers here on the client.
     */
    protected function dispatchEvent (event :DEvent) :void
    {
        // if this is a compound event, we need to process its contained
        // events in order
        if (event is CompoundEvent) {
            var events :Array = (event as CompoundEvent).getEvents();
            var ecount :int = events.length;
            for (var ii :int = 0; ii < ecount; ii++) {
                dispatchEvent(events[ii] as DEvent);
            }
            return;
        }

        // look up the object on which we're dispatching this event
        var toid :int = event.getTargetOid();
        var target :DObject = (_ocache.get(toid) as DObject);
        if (target == null) {
            if (_dead.get(toid) == null) {
                log.warning("Unable to dispatch event on non-proxied " +
                    "object [event=" + event + "].");
            }
            return;
        }

        try {
            // apply the event to the object
            var notify :Boolean = event.applyToObject(target);

            // if this is an object destroyed event, we need to remove the
            // object from our object table
            if (event is ObjectDestroyedEvent) {
//                 log.info("Pitching destroyed object " +
//                          "[oid=" + toid + ", class=" +
//                          StringUtil.shortClassName(target) + "].");
                _ocache.remove(toid);
            }

            // have the object pass this event on to its listeners
            if (notify) {
                target.notifyListeners(event);
            }

        } catch (e :Error) {
            log.warning("Failure processing event", "event", event, "target", target, e);
        }
    }

    /**
     * Registers this object in our proxy cache and notifies the
     * subscribers that were waiting for subscription to this object.
     */
    protected function registerObjectAndNotify (obj :DObject) :void
    {
        // let the object know that we'll be managing it
        obj.setManager(this);

        var oid :int = obj.getOid();
        // stick the object into the proxy object table
        _ocache.put(oid, obj);

        // let the penders know that the object is available
        var req :PendingRequest = (_penders.remove(oid) as PendingRequest);
        if (req == null) {
            log.warning("Got object, but no one cares?! " +
                "[oid=" + oid + ", obj=" + obj + "].");
            return;
        }
        // log.debug("Got object: pendReq=" + req);

        for each (var target :Subscriber in req.targets) {
            // log.debug("Notifying subscriber: " + target);
            // add them as a subscriber
            obj.addSubscriber(target);
            // and let them know that the object is in
            target.objectAvailable(obj);
        }
    }

    /**
     * Notifies the subscribers that had requested this object (for subscription) that it is not
     * available.
     */
    protected function notifyFailure (oid :int, message :String) :void
    {
        // let the penders know that the object is not available
        var req :PendingRequest = (_penders.remove(oid) as PendingRequest);
        if (req == null) {
            log.warning("Failed to get object, but no one cares?! [oid=" + oid + "].");
            return;
        }

        for each (var target :Subscriber in req.targets) {
            // and let them know that the object is in
            target.requestFailed(oid, new ObjectAccessError(message));
        }
    }

    /**
     * This is guaranteed to be invoked via the invoker and can safely do
     * main thread type things like call back to the subscriber.
     */
    protected function doSubscribe (oid :int, target :Subscriber) :void
    {
        // log.info("doSubscribe: " + oid + ": " + target);

        // first see if we've already got the object in our table
        var obj :DObject = (_ocache.get(oid) as DObject);
        if (obj != null) {
            // clear the object out of the flush table if it's in there
            _flushes.remove(oid);
            // add the subscriber and call them back straight away
            obj.addSubscriber(target);
            target.objectAvailable(obj);
            return;
        }

        // see if we've already got an outstanding request for this object
        var req :PendingRequest = (_penders.get(oid) as PendingRequest);
        if (req != null) {
            // add this subscriber to the list of subscribers to be
            // notified when the request is satisfied
            req.addTarget(target);
            return;
        }

        // otherwise we need to create a new request
        req = new PendingRequest(oid);
        req.addTarget(target);
        _penders.put(oid, req);
        // log.info("Registering pending request [oid=" + oid + "].");

        // and issue a request to get things rolling
        _comm.postMessage(new SubscribeRequest(oid));
    }

    /**
     * This is guaranteed to be invoked via the invoker and can safely do
     * main thread type things like call back to the subscriber.
     */
    protected function doUnsubscribe (oid :int, target :Subscriber) :void
    {
        var dobj :DObject = (_ocache.get(oid) as DObject);
        if (dobj != null) {
            dobj.removeSubscriber(target);

        } else {
            log.info("Requested to remove subscriber from " +
                     "non-proxied object [oid=" + oid +
                     ", sub=" + target + "].");
        }
    }

    /**
     * Flushes a distributed object subscription, issuing an unsubscribe
     * request to the server.
     */
    protected function flushObject (obj :DObject) :void
    {
        // move this object into the dead pool so that we don't claim to
        // have it around anymore; once our unsubscribe message is
        // processed, it'll be 86ed
        var ooid :int = obj.getOid();
        _ocache.remove(ooid);
        obj.setManager(null);
        _dead.put(ooid, obj);

        // ship off an unsubscribe message to the server; we'll remove the
        // object from our table when we get the unsub ack
        _comm.postMessage(new UnsubscribeRequest(ooid));
    }

    /**
     * Called periodically to flush any objects that have been lingering
     * due to a previously enacted flush delay.
     */
    protected function flushObjects (event :TimerEvent) :void
    {
        var now :Number = getTimer();
        for each (var oid :int in _flushes.keys()) {
            var rec :FlushRecord = (_flushes.get(oid) as FlushRecord);
            if (rec.expire <= now) {
                _flushes.remove(oid);
                flushObject(rec.obj);
            }
        }
    }

    /** A reference to the communicator that sends and receives messages
     * for this client. */
    protected var _comm :Communicator;

    /** A reference to our client instance. */
    protected var _client :Client;

    /** All of the distributed objects that are active on this client. */
    protected var _ocache :Map = Maps.newMapOf(int);

    /** Objects that have been marked for death. */
    protected var _dead :Map = Maps.newMapOf(int);

    /** Pending object subscriptions. */
    protected var _penders :Map = Maps.newMapOf(int);

    /** A mapping from distributed object class to flush delay. */
    protected var _delays :Map = Maps.newMapOf(int);

    /** A set of objects waiting to be flushed. */
    protected var _flushes :Map = Maps.newMapOf(int);

    /** Flushes objects every now and again. */
    protected var _flushInterval :Timer;

    /** Flush expired objects every 30 seconds. */
    protected static const FLUSH_INTERVAL :Number = 30 * 1000;
}
}

import com.threerings.presents.dobj.DObject;
import com.threerings.presents.dobj.Subscriber;

class PendingRequest
{
    public var oid :int;
    public var targets :Array = new Array();

    public function PendingRequest (oid :int)
    {
        this.oid = oid;
    }

    public function addTarget (target :Subscriber) :void
    {
        targets.push(target);
    }
}

/** Used to manage pending object flushes. */
class FlushRecord
{
    /** The object to be flushed. */
    public var obj :DObject;

    /** The time at which we flush it. */
    public var expire :Number;

    public function FlushRecord (obj :DObject, expire :Number)
    {
        this.obj = obj;
        this.expire = expire;
    }
}
