//
// $Id: ForwardEventRequest.java,v 1.1 2001/05/22 06:07:59 mdb Exp $

package com.samskivert.cocktail.cher.net;

import java.io.IOException;
import java.io.DataInputStream;
import java.io.DataOutputStream;

import com.samskivert.cocktail.cher.dobj.Event;
import com.samskivert.cocktail.cher.dobj.EventFactory;

public class ForwardEventNotification extends UpstreamMessage
{
    /** The code for a forward event notification. */
    public static final short TYPE = TYPE_BASE + 4;

    /**
     * Zero argument constructor used when unserializing an instance.
     */
    public ForwardEventNotification ()
    {
        super();
    }

    /**
     * Constructs a forward event notification for the supplied event.
     */
    public ForwardEventNotification (Event event)
    {
        _event = event;
    }

    public short getType ()
    {
        return TYPE;
    }

    public void writeTo (DataOutputStream out)
        throws IOException
    {
        super.writeTo(out);
        _event.writeTo(out);
    }

    public void readFrom (DataInputStream in)
        throws IOException
    {
        super.readFrom(in);
        _event = EventFactory.readFrom(in);
    }

    /** The event which we are forwarding. */
    protected Event _event;
}
