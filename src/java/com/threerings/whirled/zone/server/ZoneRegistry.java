//
// $Id: ZoneRegistry.java,v 1.8 2002/08/14 19:07:58 mdb Exp $

package com.threerings.whirled.zone.server;

import com.samskivert.util.HashIntMap;

import com.threerings.presents.server.InvocationManager;

import com.threerings.crowd.server.PlaceRegistry;
import com.threerings.whirled.server.SceneRegistry;

import com.threerings.whirled.zone.Log;
import com.threerings.whirled.zone.util.ZoneUtil;

/**
 * The zone registry takes care of mapping zone requests to the
 * appropriate registered zone manager.
 */
public class ZoneRegistry
{
    /** Implements the server-side of the zone-related services. */
    public ZoneProvider zoneprov;

    /**
     * Creates a zone manager with the supplied configuration.
     */
    public ZoneRegistry (InvocationManager invmgr, PlaceRegistry plreg,
                         SceneRegistry screg)
    {
        // create a zone provider and register it with the invocation
        // services
        zoneprov = new ZoneProvider(plreg.locprov, this, screg);
        invmgr.registerDispatcher(new ZoneDispatcher(zoneprov), true);
    }

    /**
     * Registers the supplied zone manager as the manager for the
     * specified zone type. Zone types are 7 bits and managers are
     * responsible for making sure they don't use a zone type that
     * collides with another manager (given that we have only three zone
     * types at present, this doesn't seem unreasonable).
     */
    public void registerZoneManager (byte zoneType, ZoneManager manager)
    {
        ZoneManager old = (ZoneManager)_managers.get(zoneType);
        if (old != null) {
            Log.warning("Zone manager already registered with requested " +
                        "type [type=" + zoneType + ", old=" + old +
                        ", new=" + manager + "].");
        } else {
            _managers.put(zoneType, manager);
        }
    }

    /**
     * Returns the zone manager that handles the specified zone id.
     *
     * @param qualifiedZoneId the qualified zone id for which the manager
     * should be looked up.
     */
    public ZoneManager getZoneManager (int qualifiedZoneId)
    {
        int zoneType = ZoneUtil.zoneType(qualifiedZoneId);
        return (ZoneManager)_managers.get(zoneType);
    }

    /** A table of zone managers. */
    protected HashIntMap _managers = new HashIntMap();
}
