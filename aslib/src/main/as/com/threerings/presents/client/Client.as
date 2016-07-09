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
import aspire.util.Throttle;

import com.threerings.presents.data.ClientObject;
import com.threerings.presents.data.InvocationCodes;
import com.threerings.presents.data.TimeBaseMarshaller;
import com.threerings.presents.dobj.DObjectManager;
import com.threerings.presents.net.AuthResponseData;
import com.threerings.presents.net.BootstrapData;
import com.threerings.presents.net.Credentials;
import com.threerings.presents.net.PingRequest;
import com.threerings.presents.net.PongResponse;
import com.threerings.presents.net.ThrottleUpdatedMessage;
import com.threerings.util.DelayUtil;
import com.threerings.util.Long;

import flash.events.EventDispatcher;
import flash.events.TimerEvent;
import flash.utils.Timer;
import flash.utils.getTimer;

public class Client extends EventDispatcher
{
    /** The default port on which the server listens for client connections. */
    public static const DEFAULT_SERVER_PORTS :Array = [ 47624 ];

    /** Our default maximum outgoing message rate in messages per second. */
    public static const DEFAULT_MSGS_PER_SECOND :int = 10;

    private static const log :Log = Log.getLog(Client);

    // statically reference classes we require
    TimeBaseMarshaller;

    public function Client (creds :Credentials = null)
    {
        _creds = creds;
    }

    /**
     * Registers the supplied observer with this client. While registered the observer will receive
     * notifications of state changes within the client. The function will refuse to register an
     * already registered observer.
     *
     * @see ClientObserver
     * @see SessionObserver
     */
    public function addClientObserver (observer :SessionObserver) :void
    {
        addEventListener(ClientEvent.CLIENT_WILL_LOGON, observer.clientWillLogon);
        addEventListener(ClientEvent.CLIENT_DID_LOGON, observer.clientDidLogon);
        addEventListener(ClientEvent.CLIENT_OBJECT_CHANGED, observer.clientObjectDidChange);
        addEventListener(ClientEvent.CLIENT_DID_LOGOFF, observer.clientDidLogoff);
        if (observer is ClientObserver) {
            var cliObs :ClientObserver = (observer as ClientObserver);
            addEventListener(ClientEvent.CLIENT_FAILED_TO_LOGON, cliObs.clientFailedToLogon);
            addEventListener(ClientEvent.CLIENT_CONNECTION_FAILED, cliObs.clientConnectionFailed);
            addEventListener(ClientEvent.CLIENT_WILL_LOGOFF, cliObs.clientWillLogoff);
            addEventListener(ClientEvent.CLIENT_DID_CLEAR, cliObs.clientDidClear);
        }
    }

    /**
     * Unregisters the supplied observer. Upon return of this function, the observer will no longer
     * receive notifications of state changes within the client.
     */
    public function removeClientObserver (observer :SessionObserver) :void
    {
        removeEventListener(ClientEvent.CLIENT_WILL_LOGON, observer.clientWillLogon);
        removeEventListener(ClientEvent.CLIENT_DID_LOGON, observer.clientDidLogon);
        removeEventListener(ClientEvent.CLIENT_OBJECT_CHANGED, observer.clientObjectDidChange);
        removeEventListener(ClientEvent.CLIENT_DID_LOGOFF, observer.clientDidLogoff);
        if (observer is ClientObserver) {
            var cliObs :ClientObserver = (observer as ClientObserver);
            removeEventListener(ClientEvent.CLIENT_FAILED_TO_LOGON, cliObs.clientFailedToLogon);
            removeEventListener(
                ClientEvent.CLIENT_CONNECTION_FAILED, cliObs.clientConnectionFailed);
            removeEventListener(ClientEvent.CLIENT_WILL_LOGOFF, cliObs.clientWillLogoff);
            removeEventListener(ClientEvent.CLIENT_DID_CLEAR, cliObs.clientDidClear);
        }
    }

    public function setServer (hostname :String, ports :Array) :void
    {
        _hostname = hostname;
        _ports = ports;
    }

    public function callLater (fn :Function, args :Array = null) :void
    {
        DelayUtil.delayFrame(fn, args);
    }

    public function getHostname () :String
    {
        return _hostname;
    }

    /**
     * Returns the ports on which this client is configured to connect.
     */
    public function getPorts () :Array
    {
        return _ports;
    }

    public function getCredentials () :Credentials
    {
        return _creds;
    }

    public function setCredentials (creds :Credentials) :void
    {
        _creds = creds;
    }

    public function getVersion () :String
    {
        return _version;
    }

    public function setVersion (version :String) :void
    {
        _version = version;
    }

    public function getAuthResponseData () :AuthResponseData
    {
        return _authData;
    }

    public function setAuthResponseData (data :AuthResponseData) :void
    {
        _authData = data;
    }

    public function getDObjectManager () :DObjectManager
    {
        return _omgr;
    }

    public function getClientOid () :int
    {
        return _cloid;
    }

    public function getClientObject () :ClientObject
    {
        return _clobj;
    }

    public function getInvocationDirector () :InvocationDirector
    {
        return _invdir;
    }

    /**
     * Returns the set of bootstrap service groups needed by this client.
     */
    public function getBootGroups () :Array
    {
        return _bootGroups;
    }

    /**
     * Marks this client as interested in the specified bootstrap services group. Any services
     * registered as bootstrap services with the supplied group name will be included in this
     * clients bootstrap services set. This must be called before {@link #logon}.
     */
    public function addServiceGroup (group :String) :void
    {
        if (isLoggedOn()) {
            throw new Error("Services must be registered prior to logon().");
        }
        if (_bootGroups.indexOf(group) == -1) {
            _bootGroups.push(group);
        }
    }

    public function getService (clazz :Class) :*
    {
        if (_bstrap != null) {
            for each (var isvc :InvocationService in _bstrap.services) {
                if (isvc is clazz) {
                    return isvc;
                }
            }
        }
        return null;
    }

    public function requireService (clazz :Class) :*
    {

        var isvc :InvocationService = getService(clazz);
        if (isvc == null) {
            throw new Error(clazz + " isn't available. I can't bear to go on.");
        }
        return isvc;
    }

    public function getBootstrapData () :BootstrapData
    {
        return _bstrap;
    }

    /**
     * Converts a server time stamp to a value comparable to client clock readings.
     */
    public function fromServerTime (stamp :Long) :Long
    {
        // when we calculated our time delta, we did it such that: C - S = dT, thus to convert
        // server to client time we do: C = S + dT
        return Long.fromNumber(stamp.toNumber() + _serverDelta);
    }

    /**
     * Converts a client clock reading to a value comparable to a server time stamp.
     */
    public function toServerTime (stamp :Long) :Long
    {
        // when we calculated our time delta, we did it such that: C - S = dT, thus to convert
        // server to client time we do: S = C - dT
        return Long.fromNumber(stamp.toNumber() - _serverDelta);
    }

    public function isLoggedOn () :Boolean
    {
        return (_clobj != null);
    }

    /**
     * Detects if the client is currently connected to the server. This can sometimes return false
     * even though <code>isLoggedOn</code> returns true.
     */
    public function isConnected () :Boolean
    {
        return _comm != null && _comm.isConnected();
    }

    /**
     * Detects if we have an external logoff request waiting to go through. If the connection is
     * being throttled, this may return true even though the client <code>isLoggedOn() &&
     * isConnected()</code>.
     */
    public function isLogoffPending () :Boolean
    {
        return _switcher == null && _comm != null && _comm.hasPendingLogoff();
    }

    /**
     * Requests that this client connect and logon to the server with which it was previously
     * configured.
     *
     * @return false if we're already logged on.
     */
    public function logon () :Boolean
    {
        // if we have a communicator, we're already logged on
        if (_comm != null) {
            return false;
        }

        // let our observers know that we're logging on (this will give directors a chance to
        // register invocation service groups)
        notifyObservers(ClientEvent.CLIENT_WILL_LOGON);

        // we need to wait for the CLIENT_WILL_LOGON to have been dispatched before we actually
        // tell the communicator to logon, so we run this through the callLater pipeline
        _comm = new Communicator(this);
        callLater(function () :void {
            _comm.logon(buildClientProps());
        });

        return true;
    }

    /**
     * Runs the given function while collecting any generated messages in a CompoundEvent, which
     * will be sent when the function returns.
     */
    public function inCompoundMessage (run :Function) :void
    {
        _comm.startCompoundMessage();
        try {
            run();
        } finally {
            _comm.finishCompoundMessage();
        }

    }

    /**
     * Create the client property object to pass to {@link ObjectInputStream}. Subclasses may
     * add references useful during e.g. deserialization.
     */
    protected function buildClientProps () :Object
    {
        return { invDir: _invdir };
    }

    /**
     * Transitions a logged on client from its current server to the specified new server.
     * Currently this simply logs the client off of its current server (if it is logged on) and
     * logs it onto the new server, but in the future we may aim to do something fancier.
     *
     * <p> If we fail to connect to the new server, the client <em>will not</em> be automatically
     * reconnected to the old server. It will be in a logged off state. However, it will be
     * reconfigured with the hostname and ports of the old server so that the caller can notify the
     * user of the failure and then simply call {@link #logon} to attempt to reconnect to the old
     * server.
     *
     * @param observer an observer that will be notified when we have successfully logged onto the
     * other server, or if the move failed.
     */
    public function moveToServer (hostname :String, ports :Array,
                                  obs :InvocationService_ConfirmListener) :void
    {
        // the server switcher will take care of everything for us
        _switcher = new ServerSwitcher(this, hostname, ports, obs);
        _switcher.switchServers();
    }

    /**
     * Requests that the client log off of the server to which it is connected.
     *
     * @param abortable if true, the client will call clientWillDisconnect on allthe client
     * observers and abort the logoff process if any of them return false. If false,
     * clientWillDisconnect will not be called.
     *
     * @return true if the logoff succeeded, false if it failed due to a disagreeable observer.
     */
    public function logoff (abortable :Boolean) :Boolean
    {
        if (_comm == null) {
            log.warning("Ignoring request to log off: not logged on.");
            return true;
        }

        // if this is an externally initiated logoff request, clear our active session status
        if (_switcher == null) {
            _activeSession = false;
        }

        // if the request is abortable, let's run it past the observers.  if any of them call
        // preventDefault() then the logoff will be cancelled
        if (abortable && !notifyObservers(ClientEvent.CLIENT_WILL_LOGOFF)) {
            _activeSession = true; // restore our active session status
            return false;
        }

        if (_tickInterval != null) {
            _tickInterval.stop();
            _tickInterval = null;
        }

        _comm.logoff();
        return true;
    }

    public function gotBootstrap (data :BootstrapData, omgr :DObjectManager) :void
    {
        // log.debug("Got bootstrap " + data + ".");

        _bstrap = data;
        _omgr = omgr;
        _cloid = data.clientOid;

        _invdir.init(omgr, _cloid, this);

        // send a few pings to the server to establish the clock offset between this client and
        // server standard time
        establishClockDelta(getTimer());

        // log.debug("TimeBaseService: " + requireService(TimeBaseService));
    }

    /**
     * Called every five seconds; ensures that we ping the server if we haven't communicated in a
     * long while.
     */
    protected function tick (event :TimerEvent) :void
    {
        if (_comm == null) {
            return;
        }

        var now :uint = getTimer();
        if (_dcalc != null) {
            // if our current calculator is done, clear it out
            if (_dcalc.isDone()) {
                //log.debug("Time offset from server: " + _serverDelta + "ms.");
                _dcalc = null;
            } else if (_dcalc.shouldSendPing()) {
                // otherwise, send another ping
                var req :PingRequest = new PingRequest();
                _comm.postMessage(req);
                _dcalc.sentPing(req);
            }

        } else if (now - _comm.getLastWrite() > PingRequest.PING_INTERVAL) {
            _comm.postMessage(new PingRequest());
        } else if (now - _lastSync > CLOCK_SYNC_INTERVAL) {
            // resync our clock with the server
            establishClockDelta(now);
        }
    }

    /**
     * Called during initialization to initiate a sequence of ping/pong messages which will be used
     * to determine (with "good enough" accuracy) the difference between the client clock and the
     * server clock so that we can later interpret server timestamps.
     */
    protected function establishClockDelta (now :Number) :void
    {
        if (_comm != null) {
            // create a new delta calculator and start the process
            _dcalc = new DeltaCalculator();
            var req :PingRequest = new PingRequest();
            _comm.postMessage(req);
            _dcalc.sentPing(req);
            _lastSync = now;
        }
    }

    /**
     * Called by the {@link Communicator} if it is experiencing trouble logging on but is still
     * trying fallback strategies.
     */
    internal function reportLogonTribulations (cause :LogonError) :void
    {
        notifyObservers(ClientEvent.CLIENT_FAILED_TO_LOGON, cause);
    }

    /**
     * Called by the invocation director when it successfully subscribes to the client object
     * immediately following logon.
     */
    public function gotClientObject (clobj :ClientObject) :void
    {
        // keep our client object around
        _clobj = clobj;
        // and start up our tick interval (which will send pings when necessary)
        if (_tickInterval == null) {
            _tickInterval = new Timer(5000);
            _tickInterval.addEventListener(TimerEvent.TIMER, tick);
            _tickInterval.start();
        }

        notifyObservers(ClientEvent.CLIENT_DID_LOGON);

        // now that we've logged on at least once, we're in the middle of an active session and
        // will remain so until we receive an externally initiated logoff request
        _activeSession = true;
    }

    /**
     * Called by the invocation director if it fails to subscribe to the client object after logon.
     */
    public function getClientObjectFailed (cause :Error) :void
    {
        notifyObservers(ClientEvent.CLIENT_FAILED_TO_LOGON, cause);
    }

    /**
     * Called by the invocation director when it discovers that the client object has changed.
     */
    protected function clientObjectDidChange (clobj :ClientObject) :void
    {
        _clobj = clobj;
        _cloid = clobj.getOid();

        notifyObservers(ClientEvent.CLIENT_OBJECT_CHANGED);
    }

    /**
     * Convenience method to dispatch a client event to any listeners and return the result of
     * dispatchEvent.
     */
    public function notifyObservers (evtCode :String, cause :Error = null) :Boolean
    {
        return dispatchEvent(new ClientEvent(evtCode, this, _activeSession, cause));
    }

    /**
     * Called by the omgr when we receive a pong packet.
     */
    internal function gotPong (pong :PongResponse) :void
    {
        // if we're not currently calculating our delta, then we can throw away the pong
        if (_dcalc != null) {
            // we update the delta after every receipt so as to immediately obtain an estimate of
            // the clock delta and then refine it as more packets come in
            _dcalc.gotPong(pong);
            _serverDelta = _dcalc.getTimeDelta();
        }
    }

    internal function setOutgoingMessageThrottle (messagesPerSec :int) :void
    {
        _comm.postMessage(new ThrottleUpdatedMessage(messagesPerSec));
    }

    internal function finalizeOutgoingMessageThrottle (messagesPerSec :int) :void
    {
        // when the throttle update message goes out to the server
        _outThrottle.reinit(messagesPerSec, 1000);
        log.info("Updated outgoing throttle", "messagesPerSec", messagesPerSec);
    }

    internal function getOutgoingMessageThrottle () :Throttle
    {
        return _outThrottle;
    }

    internal function cleanup (logonError :Error) :void
    {
        // tell the object manager that we're no longer connected to the server
        if (_omgr is ClientDObjectMgr) {
            ClientDObjectMgr(_omgr).cleanup();
        }

        // clear out our references
        _comm = null;
        _bstrap = null;
        _omgr = null;
        _clobj = null;
        _cloid = -1;

        // and let our invocation director know we're logged off
        _invdir.cleanup();

        // if this was due to a logon error, we can notify our listeners now that we're cleaned up:
        // they may want to retry logon on another port, or something
        if (logonError != null) {
            notifyObservers(ClientEvent.CLIENT_FAILED_TO_LOGON, logonError);
        } else {
            notifyObservers(ClientEvent.CLIENT_DID_CLEAR, null);
        }

        // clear out any server switcher reference
        _switcher = null;
    }

    /** The credentials we used to authenticate with the server. */
    protected var _creds :Credentials;

    /** The version string reported to the server at auth time. */
    protected var _version :String = "";

    /** The distributed object manager we're using during this session. */
    protected var _omgr :DObjectManager;

    /** The data associated with our authentication response. */
    protected var _authData :AuthResponseData;

    /** Our client distributed object id. */
    protected var _cloid :int = -1;

    /** Our client distributed object. */
    protected var _clobj :ClientObject;

    /** The game server host. */
    protected var _hostname :String;

    /** The port on which we connect to the game server. */
    protected var _ports :Array; /* of int */

    /** The entity that manages our network communications. */
    protected var _comm :Communicator;

    /** Our outgoing message throttle. */
    protected var _outThrottle :Throttle = new Throttle(DEFAULT_MSGS_PER_SECOND, 1000);

    /** The set of bootstrap service groups this client cares about. */
    protected var _bootGroups :Array = new Array(InvocationCodes.GLOBAL_GROUP);

    /** General startup information provided by the server. */
    protected var _bstrap :BootstrapData;

    /** Manages invocation services. */
    protected var _invdir :InvocationDirector = new InvocationDirector();

    /** The difference between the server clock and the client clock (estimated immediately after
     * logging on). */
    protected var _serverDelta :Number;

    /** Used when establishing our clock delta between the client and server. */
    protected var _dcalc :DeltaCalculator;

    /** The last time at which we synced our clock with the server. */
    protected var _lastSync :Number;

    /** Ticks. */
    protected var _tickInterval :Timer;

    /** This flag is used to distinguish our *first* willLogon/didLogon and a caller-initiated
     * willLogoff/didLogoff from similar events generated during server switches. Thus it is true
     * for most of a normal client session. */
    protected var _activeSession :Boolean;

    /** Used to temporarily track our server switcher so that we can tell when we're logging off
     * whether or not we're switching servers or actually ending our session. */
    protected var _switcher :ServerSwitcher;

    /** How often we recompute our time offset from the server. */
    protected static const CLOCK_SYNC_INTERVAL :Number = 600 * 1000;
}
}
