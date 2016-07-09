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

package com.threerings.crowd.client {

import aspire.util.Log;

import com.threerings.crowd.data.BodyObject;
import com.threerings.crowd.data.CrowdCodes;
import com.threerings.crowd.data.LocationMarshaller;
import com.threerings.crowd.data.PlaceConfig;
import com.threerings.crowd.data.PlaceObject;
import com.threerings.crowd.util.CrowdContext;
import com.threerings.presents.client.BasicDirector;
import com.threerings.presents.client.Client;
import com.threerings.presents.client.ClientEvent;
import com.threerings.presents.dobj.DObject;
import com.threerings.presents.dobj.ObjectAccessError;
import com.threerings.presents.dobj.Subscriber;
import com.threerings.presents.dobj.SubscriberAdapter;
import com.threerings.presents.util.ObserverList;
import com.threerings.util.ResultListener;

import flash.utils.getTimer;

/**
 * The location director provides a means by which entities on the client can request to move from
 * place to place and can be notified if other entities have caused the client to move to a new
 * place. It also provides a mechanism for ratifying a request to move to a new place before
 * actually issuing the request.
 */
public class LocationDirector extends BasicDirector
    implements Subscriber, LocationReceiver
{
    // statically reference classes we require
    LocationMarshaller;

    /**
     * Constructs a location director which will configure itself for operation using the supplied
     * context.
     */
    public function LocationDirector (ctx :CrowdContext)
    {
        super(ctx);

        // keep this around for later
        _cctx = ctx;

        // register for location notifications
        _cctx.getClient().getInvocationDirector().registerReceiver(new LocationDecoder(this));
    }

    /**
     * Adds a location observer to the list. This observer will subsequently be notified of
     * potential, effected and failed location changes.
     */
    public function addLocationObserver (observer :LocationObserver) :void
    {
        _observers.add(observer);
    }

    /**
     * Removes a location observer from the list.
     */
    public function removeLocationObserver (observer :LocationObserver) :void
    {
        _observers.remove(observer);
    }

    /**
     * Returns the place object for the location we currently occupy or null if we're not currently
     * occupying any location.
     */
    public function getPlaceObject () :PlaceObject
    {
        return _plobj;
    }

    /**
     * Returns the controller for the location we currently occupy or null if we're not currently
     * occupying any location.
     */
    public function getPlaceController () :PlaceController
    {
        return _controller;
    }

    /**
     * Returns true if there is a pending move request.
     */
    public function movePending () :Boolean
    {
        return (_pendingPlaceId > 0);
    }

    /**
     * Requests that this client be moved to the specified place. A request will be made and when
     * the response is received, the location observers will be notified of success or failure.
     *
     * @return true if the move to request was issued, false if it was rejected by a location
     * observer or because we have another request outstanding.
     */
    public function moveTo (placeId :int) :Boolean
    {
        // make sure the placeId is valid
        if (placeId < 0) {
            log.warning("Refusing moveTo(): invalid placeId", "placeId", placeId);
            return false;
        }

        // first check to see if our observers are happy with this move request
        if (!mayMoveTo(placeId, null)) {
            return false;
        }

        // we need to call this both to mark that we're issuing a move request and to check to see
        // if the last issued request should be considered stale
        var refuse :Boolean = checkRepeatMove();

        // complain if we're over-writing a pending request
        if (_pendingPlaceId != -1) {
            // if the pending request has been outstanding more than a minute, go ahead and let
            // this new one through in an attempt to recover from dropped moveTo requests
            if (refuse) {
                log.warning("Refusing moveTo; We have a request outstanding",
                    "ppid", _pendingPlaceId, "npid", placeId);
                return false;

            } else {
                log.warning("Overriding stale moveTo request",
                    "ppid", _pendingPlaceId, "npid", placeId);
            }
        }

        // make a note of our pending place id
        _pendingPlaceId = placeId;

        // documentation inherited from interface MoveListener
        var success :Function = function (config :PlaceConfig) :void {
            // handle the successful move
            didMoveTo(_pendingPlaceId, config);

            // and clear out the tracked pending oid
            _pendingPlaceId = -1;

            handlePendingForcedMove();
        };

        // documentation inherited from interface MoveListener
        var failure :Function = function (reason :String) :void {
            // clear out our pending request oid
            var placeId :int = _pendingPlaceId;
            _pendingPlaceId = -1;

            log.info("moveTo failed", "pid", placeId, "reason", reason);

            // let our observers know that something has gone horribly awry
            notifyFailure(placeId, reason);

            handlePendingForcedMove();
        };

        // issue a moveTo request
        log.info("Issuing moveTo", "placeId", placeId);
        _lservice.moveTo(placeId, new MoveAdapter(success, failure));
        return true;
    }

    /**
     * Requests to move to the room that we last occupied, if such a room exists.
     *
     * @return true if we had a previous room and we requested to move to it, false if we had no
     * previous room.
     */
    public function moveBack () :Boolean
    {
        if (_previousPlaceId == -1) {
            return false;

        } else {
            moveTo(_previousPlaceId);
            return true;
        }
    }

    /**
     * Issues a request to leave our current location.
     *
     * @return true if we were able to leave, false if we are in the middle of moving somewhere and
     * can't yet leave.
     */
    public function leavePlace () :Boolean
    {
        if (_pendingPlaceId != -1) {
            return false;
        }

        // if we're not actually in a place, then no need to do anything
        if (_placeId > 0) {
            _lservice.leavePlace();
            didLeavePlace();

            // let our observers know that we're no longer in a location
            _observers.apply(didChangeOp);
        }

        return true;
    }

    /**
     * This can be called by cooperating directors that need to coopt the moving process to extend
     * it in some way or other. In such situations, they should call this method before moving to a
     * new location to check to be sure that all of the registered location observers are amenable
     * to a location change.
     *
     * @param placeId the place oid of our tentative new location.
     *
     * @return true if everyone is happy with the move, false if it was vetoed by one of the
     * location observers.
     */
    public function mayMoveTo (placeId :int, rl :ResultListener) :Boolean
    {
        var vetoed :Boolean = false;
        _observers.apply(function (obs :Object) :void {
            var lobs :LocationObserver = (obs as LocationObserver);
            vetoed = vetoed || !lobs.locationMayChange(placeId);
        });

        // if we're actually going somewhere, let the controller know that we might be leaving
        mayLeavePlace();

        // if we have a result listener, let it know if we failed or keep it for later if we're
        // still going
        if (rl != null) {
            if (vetoed) {
                rl.requestFailed(new MoveVetoedError());
            } else {
                _moveListener = rl;
            }
        }
        // and return the result
        return !vetoed;
    }

    /**
     * Called to inform our controller that we may be leaving the current place.
     */
    protected function mayLeavePlace () :void
    {
        if (_controller != null) {
            try {
                _controller.mayLeavePlace(_plobj);
            } catch (e :Error) {
                log.warning("Place controller choked in mayLeavePlace", "plobj", _plobj, e);
            }
        }
    }

    /**
     * This can be called by cooperating directors that need to coopt the moving process to extend
     * it in some way or other. In such situations, they will be responsible for receiving the
     * successful move response and they should let the location director know that the move has
     * been effected.
     *
     * @param placeId the place oid of our new location.
     * @param config the configuration information for the new place.
     */
    public function didMoveTo (placeId :int, config :PlaceConfig) :void
    {
        if (_moveListener != null) {
            _moveListener.requestCompleted(config);
            _moveListener = null;
        }

        // keep track of our previous place id
        _previousPlaceId = _placeId;

        // clear out our last request time
        _lastRequestTime = 0;

        // do some cleaning up in case we were previously in a place
        didLeavePlace();

        // make a note that we're now mostly in the new location
        _placeId = placeId;

        // check whether we should use a custom class loader
        _controller = config.createController();
        if (_controller == null) {
            log.warning("Place config returned null controller", "config", config);
            return;
        }
        _controller.init(_cctx, config);

        // subscribe to our new place object to complete the move
        _cctx.getDObjectManager().subscribeToObject(_placeId, this);
    }

    /**
     * Called when we're leaving our current location. Informs the location's controller that we're
     * departing, unsubscribes from the location's place object, and clears out our internal place
     * information.
     */
    public function didLeavePlace () :void
    {
        if (_plobj != null) {
            // let the old controller know that things are going away
            if (_controller != null) {
                try {
                    _controller.didLeavePlace(_plobj);
                } catch (e :Error) {
                    log.warning("Place controller choked in didLeavePlace", "plobj", _plobj, e);
                }
                _controller = null;
            }

            // let the chat director know that we're leaving this place
            _cctx.getChatDirector().leftLocation(_plobj);

            // unsubscribe from our old place object
            _cctx.getDObjectManager().unsubscribeFromObject(_plobj.getOid(), this);
            _plobj = null;

            // and clear out the associated place id
            _placeId = -1;
        }
    }

    /**
     * This can be called by cooperating directors that need to coopt the moving process to extend
     * it in some way or other. If the coopted move request fails, this failure can be propagated
     * to the location observers if appropriate.
     *
     * @param placeId the place oid to which we failed to move.
     * @param reason the reason code given for failure.
     */
    public function failedToMoveTo (placeId :int, reason :String) :void
    {
        if (_moveListener != null) {
            _moveListener.requestFailed(new MoveFailedError(reason));
            _moveListener = null;
        }

        // clear out our last request time
        _lastRequestTime = 0;

        // let our observers know what's up
        notifyFailure(placeId, reason);
    }

    /**
     * Called to test and set a time stamp that we use to determine if a pending moveTo request is
     * stale.
     */
    public function checkRepeatMove () :Boolean
    {
        var now :Number = getTimer();
        if (now - _lastRequestTime < STALE_REQUEST_DURATION) {
            return true;

        } else {
            _lastRequestTime = now;
            return false;
        }
    }

    // documentation inherited from interface
    override public function clientDidLogon (event :ClientEvent) :void
    {
        super.clientDidLogon(event);

        var success :Function = function (object :DObject) :void {
            gotBodyObject(object as BodyObject);
        };
        var failure :Function = function (oid :int, cause :ObjectAccessError) :void {
            log.warning("Unable to fetch body object; all has gone horribly wrong", cause);
        };

        var client :Client = event.getClient();
        client.getDObjectManager().subscribeToObject(
            client.getClientOid(), new SubscriberAdapter(success, failure));
    }

    // documentation inherited
    override public function clientDidLogoff (event :ClientEvent) :void
    {
        super.clientDidLogoff(event);

        // clear ourselves out and inform observers of our departure
        mayLeavePlace();
        didLeavePlace();

        // let our observers know that we're no longer in a location
        _observers.apply(didChangeOp);

        // clear out everything else (it's possible that we were logged off in the middle of a
        // change location request)
        _pendingPlaceId = -1;
        _pendingForcedMoves = [];
        _previousPlaceId = -1;
        _lastRequestTime = 0;
        _lservice = null;
    }

    // from BasicDirector
    override protected function registerServices (client :Client) :void
    {
        client.addServiceGroup(CrowdCodes.CROWD_GROUP);
    }

    // from BasicDirector
    override protected function fetchServices (client :Client) :void
    {
        // obtain our service handle
        _lservice = (client.requireService(LocationService) as LocationService);
    }

    protected function gotBodyObject (clobj :BodyObject) :void
    {
        // check to see if we are already in a location, in which case we'll want to be going there
        // straight away
    }

    // documentation inherited from interface
    public function forcedMove (placeId :int) :void
    {
        // if we're in the middle of a move, we can't abort it or we will screw everything up, so
        // just finish up what we're doing and assume that the repeated move request was the
        // spurious one as it would be in the case of lag causing rapid-fire repeat requests
        if (movePending()) {
            if (_pendingPlaceId == placeId) {
                log.info("Dropping forced move because we have a move pending",
                    "pendId", _pendingPlaceId, "reqId", placeId);
            } else {
                log.info("Delaying forced move because we have a move pending",
                    "pendId", _pendingPlaceId, "reqId", placeId);
                addPendingForcedMove(new function() :void {
                    forcedMove(placeId);
                });
            }
            return;
        }

        log.info("Moving at request of server", "placeId", placeId);

        // clear out our old place information
        mayLeavePlace();
        didLeavePlace();

        // move to the new place
        moveTo(placeId);
    }

    // documentation inherited from interface Subscriber
    public function objectAvailable (object :DObject) :void
    {
        // yay, we have our new place object
        _plobj = (object as PlaceObject);

        // let the place controller know that we're ready to roll
        if (_controller != null) {
            try {
                _controller.willEnterPlace(_plobj);
            } catch (e :Error) {
                log.warning("Controller choked in willEnterPlace", "place", _plobj, e);
            }
        }

        // let the chat director know that we're entering this place
        _cctx.getChatDirector().enteredLocation(_plobj);

        // let our observers know that all is well on the western front
        _observers.apply(didChangeOp);
    }

    // documentation inherited from interface Subscriber
    public function requestFailed (oid :int, cause :ObjectAccessError) :void
    {
        // aiya! we were unable to fetch our new place object; something is badly wrong
        log.warning("Aiya! Unable to fetch place object for new location",
           "plid", oid, "reason", cause);

        // clear out our half initialized place info
        var placeId :int = _placeId;
        _placeId = -1;

        // let the kids know shit be fucked
        notifyFailure(placeId, "m.unable_to_fetch_place_object");

        // we need to sort out what to do about the half-initialized place controller. presently we
        // punt and hope that calling didLeavePlace() without ever having called willEnterPlace()
        // does whatever's necessary

        // try to return to our previous location
        if (_failureHandler != null) {
            _failureHandler.recoverFailedMove(placeId);

        } else {
            // if we were previously somewhere (and that somewhere isn't where we just tried to
            // go), try going back to that happy place
            if (_previousPlaceId != -1 && _previousPlaceId != placeId) {
                moveTo(_previousPlaceId);
            }
        }
    }

    /**
     * Sets the failure handler which will recover from place object fetching failures. In the
     * event that we are unable to fetch our place object after making a successful moveTo request,
     * we attempt to rectify the failure by moving back to the last known working location. Because
     * entites that cooperate with the location director may need to become involved in this
     * failure recovery, we provide this interface whereby they can interject themseves into the
     * failure recovery process and do their own failure recovery.
     */
    public function setFailureHandler (handler :LocationDirector_FailureHandler) :void
    {
        if (_failureHandler != null) {
            log.warning("Requested to set failure handler, but we've already got one. The " +
                "conflicting entities will likely need to perform more sophisticated " +
                "coordination to deal with failures.",
                "old", _failureHandler, "new", handler);

        } else {
            _failureHandler = handler;
        }
    }

    /**
     * The operation used to inform observers that the location changed.
     */
    protected function didChangeOp (obs :Object) :void
    {
        (obs as LocationObserver).locationDidChange(_plobj);
    };

    protected function notifyFailure (placeId :int, reason :String) :void
    {
        _observers.apply(function (obs :Object) :void {
            (obs as LocationObserver).locationChangeFailed(placeId, reason);
        });
    }

    public function addPendingForcedMove (move :Function) :void
    {
        _pendingForcedMoves.push(move);
    }

    protected function handlePendingForcedMove () :void
    {
        if (!_pendingForcedMoves.length == 0) {
            _ctx.getClient().callLater(_pendingForcedMoves.pop());
        }
    }

    protected const log :Log = Log.getLog(this);

    /** The context through which we access needed services. */
    protected var _cctx :CrowdContext;

    /** Provides access to location services. */
    protected var _lservice :LocationService;

    /** Our location observer list. */
    protected var _observers :ObserverList = new ObserverList(ObserverList.SAFE_IN_ORDER_NOTIFY);

    /** The oid of the place we currently occupy. */
    protected var _placeId :int = -1;

    /** The place object that we currently occupy. */
    protected var _plobj :PlaceObject;

    /** The place controller in effect for our current place. */
    protected var _controller :PlaceController;

    /** The place oid to whihc we have an outstanding moveTo request, or -1 if we have none. */
    protected var _pendingPlaceId :int = -1;

    /** The oid of the place we previously occupied. */
    protected var _previousPlaceId :int = -1;

    /** The last time we requested a move to. */
    protected var _lastRequestTime :Number;

    /** The entity that deals when we fail to subscribe to a place object. */
    protected var _failureHandler :LocationDirector_FailureHandler;

    /** A listener that wants to know if we succeeded or how we failed to move.  */
    protected var _moveListener :ResultListener;

    /** Forced move actions we should take once we complete the move we're in the middle of. */
    protected var _pendingForcedMoves :Array = [];

    /** Allow a moveTo request be outstanding for one minute before it is declared to be stale. */
    protected static const STALE_REQUEST_DURATION :int = 60 * 1000;
}
}
