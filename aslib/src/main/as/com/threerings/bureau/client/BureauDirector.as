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

package com.threerings.bureau.client {

import aspire.util.Log;
import aspire.util.Map;
import aspire.util.Maps;

import com.threerings.presents.client.BasicDirector;
import com.threerings.presents.client.Client;
import com.threerings.presents.client.ClientEvent;
import com.threerings.presents.dobj.ObjectAccessError;
import com.threerings.presents.util.SafeSubscriber;

import com.threerings.bureau.data.AgentObject;
import com.threerings.bureau.data.BureauClientObject;
import com.threerings.bureau.data.BureauCodes;
import com.threerings.bureau.util.BureauContext;

/**
 * Allows the server to create and destroy agents on a client.
 * @see BureauRegistry
 */
public class BureauDirector extends BasicDirector
{
    BureauClientObject;

    /**
     * Creates a new BureauDirector.
     */
    public function BureauDirector (ctx :BureauContext)
    {
        super(ctx);
    }

    // from BasicDirector
    public override function clientDidLogon (event :ClientEvent) :void
    {
        super.clientDidLogon(event);
        var id :String = BureauContext(_ctx).getBureauId();
        _bureauService.bureauInitialized(id);
    }

    /**
     * Lets the server know that a fatal error has occurred and the bureau needs to be terminated.
     */
    public function fatalError (message :String) :void
    {
        _bureauService.bureauError(message);
    }

    /**
     * Creates a new agent when the server requests it.
     */
    protected function createAgentFromId (agentId :int) :void
    {
        log.info("Subscribing to object", "agentId", agentId);

        var subscriber :SafeSubscriber =
            new SafeSubscriber(agentId, objectAvailable, requestFailed);
        _subscribers.put(agentId, subscriber);
        subscriber.subscribe(_ctx.getDObjectManager());
    }

    /**
     * Destroys an agent at the server's request.
     */
    protected function destroyAgent (agentId :int) :void
    {
        var agent :Agent = null;
        agent = _agents.remove(agentId);

        if (agent == null) {
            log.warning("Lost an agent", "id", agentId);
        }
        else {
            try {
                agent.stop();
            } catch (e :Error) {
                log.warning("Stopping an agent caused an exception", e);
            }
            var subscriber :SafeSubscriber = _subscribers.remove(agentId);
            if (subscriber == null) {
                log.warning("Lost a subscriber for agent", "agent", agent);
            }
            else {
                subscriber.unsubscribe(_ctx.getDObjectManager());
            }
            _bureauService.agentDestroyed(agentId);
        }
    }

    /**
     * Callback for when the a request to subscribe to an object finishes and the object is available.
     */
    protected function objectAvailable (agentObject :AgentObject) :void
    {
        var oid :int = agentObject.getOid();

        log.info("Object available", "oid", oid);

        var agent :Agent;
        try {
            agent = createAgent(agentObject);
            agent.init(agentObject);
            agent.start();
        }
        catch (e :Error) {
            log.warning("Could not create agent", "obj", agentObject, e);
            _bureauService.agentCreationFailed(oid);
            return;
        }

        _agents.put(oid, agent);
        _bureauService.agentCreated(oid);
    }

    /**
     * Callback for when the a request to subscribe to an object fails.
     */
    protected function requestFailed (oid :int, cause :ObjectAccessError) :void
    {
        log.warning("Could not subscribe to agent", "oid", oid, cause);
    }

    // from BasicDirector
    protected override function registerServices (client :Client) :void
    {
        super.registerServices(client);

        // Require the bureau services
        client.addServiceGroup(BureauCodes.BUREAU_GROUP);

        // Set up our decoder so we can receive method calls
        // from the server
        var receiver :BureauReceiver =
            new ReceiverDelegator(createAgentFromId, destroyAgent);

        client.getInvocationDirector().
            registerReceiver(new BureauDecoder(receiver));
    }

    // from BasicDirector
    protected override function fetchServices (client :Client) :void
    {
        super.fetchServices(client);

        _bureauService = client.getService(BureauService) as BureauService;
    }

    /**
     * Called when it is time to create an Agent. Subclasses should read the
     * <code>agentObject</code>'s type and/or properties to determine what kind of Agent to
     * create.
     * @param agentObj the distributed and object
     * @return a new Agent that will govern the distributed object
     */
    protected function createAgent (agentObj :AgentObject) :Agent
    {
        throw new Error("Abstract function");
    }

    /** Create a logger for the entire package.. */
    protected var log :Log = Log.getLog("com.threerings.bureau");

    protected var _bureauService :BureauService;
    protected var _agents :Map = Maps.newMapOf(int);
    protected var _subscribers :Map = Maps.newMapOf(int);
}
}

import com.threerings.bureau.client.BureauReceiver;

class ReceiverDelegator implements BureauReceiver
{
    public function ReceiverDelegator (createFn :Function, destroyFn :Function)
    {
        _createFn = createFn;
        _destroyFn = destroyFn;
    }

    public function createAgent (agentId :int) :void
    {
        _createFn(agentId);
    }

    public function destroyAgent (agentId :int) :void
    {
        _destroyFn(agentId);
    }

    protected var _createFn :Function;
    protected var _destroyFn :Function;
}

