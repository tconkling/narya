//
// $Id: SpotSceneDirector.java,v 1.21 2003/02/12 07:23:31 mdb Exp $

package com.threerings.whirled.spot.client;

import java.util.Iterator;
import com.samskivert.util.ResultListener;
import com.samskivert.util.StringUtil;

import com.threerings.presents.client.BasicDirector;
import com.threerings.presents.client.Client;
import com.threerings.presents.dobj.AttributeChangeListener;
import com.threerings.presents.dobj.AttributeChangedEvent;

import com.threerings.presents.dobj.DObject;
import com.threerings.presents.dobj.DObjectManager;
import com.threerings.presents.dobj.ObjectAccessException;
import com.threerings.presents.dobj.Subscriber;

import com.threerings.crowd.chat.ChatCodes;
import com.threerings.crowd.chat.ChatDirector;
import com.threerings.crowd.client.LocationAdapter;
import com.threerings.crowd.client.LocationDirector;
import com.threerings.crowd.data.PlaceObject;

import com.threerings.whirled.client.SceneDirector;
import com.threerings.whirled.data.SceneModel;
import com.threerings.whirled.util.WhirledContext;

import com.threerings.whirled.spot.Log;
import com.threerings.whirled.spot.data.ClusteredBodyObject;
import com.threerings.whirled.spot.data.Location;
import com.threerings.whirled.spot.data.Portal;
import com.threerings.whirled.spot.data.SpotCodes;
import com.threerings.whirled.spot.data.SpotScene;

/**
 * Extends the standard scene director with facilities to move between
 * locations within a scene.
 */
public class SpotSceneDirector extends BasicDirector
    implements SpotCodes, Subscriber, SpotService.ChangeLocListener,
               AttributeChangeListener
{
    /**
     * This is used to communicate back to the caller of {@link
     * #changeLocation}.
     */
    public static interface ChangeObserver
    {
        /**
         * Indicates that the requested location change succeeded.
         */
        public void locationChangeSucceeded (Location loc);

        /**
         * Indicates that the requested location change failed and
         * provides a reason code explaining the failure.
         */
        public void locationChangeFailed (Location loc, String reason);
    }

    /**
     * Creates a new spot scene director with the specified context and
     * which will cooperate with the supplied scene director.
     *
     * @param ctx the active client context.
     * @param locdir the location director with which we will be
     * cooperating.
     * @param scdir the scene director with which we will be cooperating.
     */
    public SpotSceneDirector (WhirledContext ctx, LocationDirector locdir,
                              SceneDirector scdir)
    {
        super(ctx);

        _ctx = ctx;
        _scdir = scdir;

        // wire ourselves up to hear about leave place notifications
        locdir.addLocationObserver(new LocationAdapter() {
            public void locationDidChange (PlaceObject place) {
                // we need to clear some things out when we leave a place
                handleDeparture();
            }
        });
    }

    /**
     * Configures this spot scene director with a chat director, with
     * which it will coordinate to implement cluster chatting.
     */
    public void setChatDirector (ChatDirector chatdir)
    {
        _chatdir = chatdir;
    }

    /**
     * Requests that this client move to the location specified by the
     * supplied portal id. A request will be made and when the response is
     * received, the location observers will be notified of success or
     * failure.
     *
     * @return true if the request was issued, false if it was rejected by
     * a location observer or because we have another request outstanding.
     */
    public boolean traversePortal (int portalId)
    {
        return traversePortal(portalId, null);
    }

    /**
     * Requests that this client move to the location specified by the
     * supplied portal id. A request will be made and when the response is
     * received, the location observers will be notified of success or
     * failure.
     */
    public boolean traversePortal (int portalId, ResultListener rl)
    {
        // look up the destination scene and location
        SpotScene scene = (SpotScene)_scdir.getScene();
        if (scene == null) {
            Log.warning("Requested to traverse portal when we have " +
                        "no scene [portalId=" + portalId + "].");
            return false;
        }

        // find the portal they're talking about
        Portal dest = scene.getPortal(portalId);
        if (dest == null) {
            Log.warning("Requested to traverse non-existent portal " +
                        "[portalId=" + portalId + ", portals=" +
                        StringUtil.toString(scene.getPortals()) + "].");
            return false;
        }

        // prepare to move to this scene (sets up pending data)
        if (!_scdir.prepareMoveTo(dest.targetSceneId, rl)) {
            return false;
        }

        // check the version of our cached copy of the scene to which
        // we're requesting to move; if we were unable to load it, assume
        // a cached version of zero
        int sceneVer = 0;
        SceneModel pendingModel = _scdir.getPendingModel();
        if (pendingModel != null) {
            sceneVer = pendingModel.version;
        }

        // issue a traversePortal request
        _sservice.traversePortal(_ctx.getClient(), portalId, sceneVer, _scdir);
        return true;
    }

    /**
     * Issues a request to change our location within the scene to the
     * specified location. Depending on the value of <code>cluster</code>
     * the client will be made to create a new cluster, join and existing
     * cluster or join no cluster at all.
     *
     * @param loc the new location to which to move.
     * @param cluster if zero, a new cluster will be created and assigned
     * to the calling user; if -1, the calling user will be removed from
     * any cluster they currently occupy and not made to occupy a new
     * cluster; if the bodyOid of another user, the calling user will be
     * made to join the target user's cluster.
     * @param obs will be notified of success or failure. Most client
     * entities find out about location changes via changes to the
     * occupant info data, but the initiator of a location change request
     * can be notified of its success or failure, primarily so that it can
     * act in anticipation of a successful location change (like by
     * starting a sprite moving toward the new location), but backtrack if
     * it finds out that the location change failed.
     */
    public void changeLocation (Location loc, int cluster, ChangeObserver obs)
    {
        // refuse if there's a pending location change or if we're already
        // at the specified location
        if (loc.equals(_location) || (_pendingLoc != null)) {
            Log.info("Not going to " + loc + "; we're at " + _location +
                     " and we're headed to " + _pendingLoc + ".");
            return;
        }

        SpotScene scene = (SpotScene)_scdir.getScene();
        if (scene == null) {
            Log.warning("Requested to change locations, but we're not " +
                        "currently in any scene [loc=" + loc + "].");
            return;
        }

        Log.info("Changing location [loc=" + loc + ", clus=" + cluster + "].");

        _pendingLoc = (Location)loc.clone();
        _changeObserver = obs;
        _sservice.changeLoc(_ctx.getClient(), loc, cluster, this);
    }

    /**
     * Sends a chat message to the other users in the cluster to which the
     * location that we currently occupy belongs.
     *
     * @return true if a cluster speak message was delivered, false if we
     * are not in a valid cluster and refused to deliver the request.
     */
    public boolean requestClusterSpeak (String message)
    {
        return requestClusterSpeak(message, ChatCodes.DEFAULT_MODE);
    }

    /**
     * Sends a chat message to the other users in the cluster to which the
     * location that we currently occupy belongs.
     *
     * @return true if a cluster speak message was delivered, false if we
     * are not in a valid cluster and refused to deliver the request.
     */
    public boolean requestClusterSpeak (String message, byte mode)
    {
        // make sure we're currently in a scene
        SpotScene scene = (SpotScene)_scdir.getScene();
        if (scene == null) {
            Log.warning("Requested to speak to cluster, but we're not " +
                        "currently in any scene [message=" + message + "].");
            return false;
        }

        // make sure we're part of a cluster
        if (_self.getClusterOid() <= 0) {
            Log.info("Ignoring cluster speak as we're not in a cluster " +
                     "[cloid=" + _self.getClusterOid() + "].");
            return false;
        }

        _sservice.clusterSpeak(_ctx.getClient(), message, mode);
        return true;
    }

    // documentation inherited from interface
    public void changeLocSucceeded ()
    {
        ChangeObserver obs = _changeObserver;
        _location = _pendingLoc;

        // clear out our pending location info
        _pendingLoc = null;
        _changeObserver = null;

        // if we had an observer, let them know things went well
        if (obs != null) {
            obs.locationChangeSucceeded(_location);
        }
    }

    // documentation inherited from interface
    public void requestFailed (String reason)
    {
        ChangeObserver obs = _changeObserver;
        Location loc = _pendingLoc;

        // clear out our pending location info
        _pendingLoc = null;
        _changeObserver = null;

        // if we had an observer, let them know things went well
        if (obs != null) {
            obs.locationChangeFailed(loc, reason);
        }
    }

    // documentation inherited
    public void objectAvailable (DObject object)
    {
        // we've got our cluster chat object, configure the chat director
        // with it and keep a reference ourselves
        if (_chatdir != null) {
            // unwire and clear out our cluster chat object if we've got one
            clearCluster();

            // set up the new cluster object
            _chatdir.addAuxiliarySource(object, CLUSTER_CHAT_TYPE);
            _clobj = object;
        }
    }

    // documentation inherited
    public void requestFailed (int oid, ObjectAccessException cause)
    {
        Log.warning("Unable to subscribe to cluster chat object " +
                    "[oid=" + oid + ", cause=" + cause + "].");
    }

    // documentation inherited from interface
    public void attributeChanged (AttributeChangedEvent event)
    {
        // if our cluster oid changes from the one we're currently
        // subscribed to, give it the boot
        if (_clobj != null && _self.getClusterOid() != _clobj.getOid()) {
            clearCluster();
        }

        // if there's a new cluster object, subscribe to it
        if (_chatdir != null && _self.getClusterOid() > 0) {
            DObjectManager omgr = _ctx.getDObjectManager();
            // we'll wire up to the chat director when this completes
            omgr.subscribeToObject(_self.getClusterOid(), this);
        }
    }

    // documentation inherited from interface
    public void clientDidLogon (Client client)
    {
        super.clientDidLogon(client);

        // listen to the client object
        client.getClientObject().addListener(this);
        _self = (ClusteredBodyObject)client.getClientObject();
    }

    // documentation inherited from interface
    public void clientObjectDidChange (Client client)
    {
        super.clientObjectDidChange(client);

        // listen to the client object
        client.getClientObject().addListener(this);
        _self = (ClusteredBodyObject)client.getClientObject();
    }

    // documentation inherited
    public void clientDidLogoff (Client client)
    {
        super.clientDidLogoff(client);

        // clear out our business
        _location = null;
        _pendingLoc = null;
        _changeObserver = null;
        _sservice = null;
        clearCluster();

        // stop listening to the client object
        client.getClientObject().removeListener(this);
        _self = null;
    }

    // documentation inherited
    protected void fetchServices (Client client)
    {
        _sservice = (SpotService)client.requireService(SpotService.class);
    }

    /**
     * Clean up after a few things when we depart from a scene.
     */
    protected void handleDeparture ()
    {
        // clear out our last known location id
        _location = null;

        // unwire and clear out our cluster chat object if we've got one
        clearCluster();
    }

    /**
     * Convenience routine to unwire chat for and unsubscribe from our
     * current cluster, if any.
     */
    protected void clearCluster ()
    {
        if (_chatdir != null && _clobj != null) {
            // unwire the auxiliary chat object
            _chatdir.removeAuxiliarySource(_clobj);
            // unsubscribe as well
            DObjectManager omgr = _ctx.getDObjectManager();
            omgr.unsubscribeFromObject(_clobj.getOid(), this);
            _clobj = null;
        }
    }

    /** The active client context. */
    protected WhirledContext _ctx;

    /** Access to spot scene services. */
    protected SpotService _sservice;

    /** The scene director with which we are cooperating. */
    protected SceneDirector _scdir;

    /** A casted reference to our clustered body object. */
    protected ClusteredBodyObject _self;

    /** A reference to the chat director with which we coordinate. */
    protected ChatDirector _chatdir;

    /** The location we currently occupy. */
    protected Location _location;

    /** The location to which we have an outstanding change location
     * request. */
    protected Location _pendingLoc;

    /** The cluster chat object for the cluster we currently occupy. */
    protected DObject _clobj;

    /** An entity that wants to know if a requested location change
     * succeeded or failed. */
    protected ChangeObserver _changeObserver;
}
