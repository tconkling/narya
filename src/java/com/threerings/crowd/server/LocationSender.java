//
// $Id: LocationSender.java,v 1.1 2002/08/14 19:07:49 mdb Exp $

package com.threerings.crowd.server;

import com.threerings.crowd.client.LocationDecoder;
import com.threerings.crowd.client.LocationReceiver;
import com.threerings.presents.data.ClientObject;
import com.threerings.presents.server.InvocationSender;

/**
 * Used to issue notifications to a {@link LocationReceiver} instance on a
 * client.
 */
public class LocationSender extends InvocationSender
{
    /**
     * Issues a notification that will result in a call to {@link
     * LocationReceiver#forcedMove} on a client.
     */
    public static void forcedMove (
        ClientObject target, int arg1)
    {
        sendNotification(
            target, LocationDecoder.RECEIVER_CODE, LocationDecoder.FORCED_MOVE,
            new Object[] { new Integer(arg1) });
    }

    // Generated on 11:25:46 08/12/02.
}
