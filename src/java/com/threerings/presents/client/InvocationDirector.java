//
// $Id: InvocationDirector.java,v 1.6 2001/08/04 02:54:01 mdb Exp $

package com.threerings.cocktail.cher.client;

import java.lang.reflect.Method;
import java.util.HashMap;

import com.samskivert.util.StringUtil;

import com.threerings.cocktail.cher.Log;
import com.threerings.cocktail.cher.data.*;
import com.threerings.cocktail.cher.dobj.*;
import com.threerings.cocktail.cher.util.ClassUtil;
import com.threerings.cocktail.cher.util.IntMap;

/**
 * The invocation services provide client to server invocations (service
 * requests) and server to client invocations (responses and
 * notifications). Via this mechanism, the client can make requests of the
 * server, be notified of its response and the server can asynchronously
 * invoke code on the client.
 *
 * <p> Invocations are like remote procedure calls in that they are named
 * and take arguments. They are simple in that the arguments can only be
 * of a small set of supported types (the set of distributed object field
 * types) and there is no special facility provided for referencing
 * non-local objects (it is assumed that the distributed object facility
 * will already be in use for any objects that should be shared).
 *
 * <p> The client invocation manager delivers invocation requests to the
 * server invocation manager and maps the responses back to the proper
 * response target objects when they arrive. It also maintains the mapping
 * of invocation receivers that can receive asynchronous invocation
 * notifications at any time from the server.
 */
public class InvocationManager
    implements Subscriber
{
    /**
     * Constructs a new invocation manager with the specified invocation
     * manager oid. It will obtain its distributed object manager and
     * client object references from the supplied client instance. The
     * invocation manager oid is the oid of the object on the server to
     * which to deliver invocation requests.
     */
    public InvocationManager (Client client, int imoid)
    {
        _client = client;
        _omgr = client.getDObjectManager();
        _imoid = imoid;

        // add ourselves as a subscriber to the client object
        _omgr.subscribeToObject(client.getClientOid(), this);
    }

    /**
     * Sends an invocation request to the server. If a response target is
     * supplied, the response will be delivered to that object by calling
     * a member function on it whose name is defined in the response
     * generated by the invocation implementation. In general, this is a
     * derivative of the invocation procedure name. For example, if the
     * caller invoked a procedure named <code>Switch</code>, the response
     * may be delivered via a call to the <code>handleSwitchSuccess</code>
     * method on the response target object. The signature of that method
     * would be defined by the arguments provided in the response message
     * with the addition of a first argument which is the invocation
     * identifier for this particular request (that is also returned by
     * this function).
     *
     * @param module the name of the invocation module to use.
     * @param procedure the name of the procedure within that module.
     * @param args the arguments of the invocation.
     * @param rsptarget the object that will receive the response, or null
     * if no response is desired.
     *
     * @return a unique identifier associated with this invocation
     * request. This identifier will be passed as the first argument to
     * the response function.
     */
    public int invoke (String module, String procedure, Object[] args,
                       Object rsptarget)
    {
        int invid = nextInvocationId();

        // we need an args array for a message that can contain the
        // invocation names, an invocation id and the invocation arguments
        Object[] iargs = new Object[args.length+3];
        iargs[0] = module;
        iargs[1] = procedure;
        iargs[2] = new Integer(invid);
        System.arraycopy(args, 0, iargs, 3, args.length);

        // create a message event on the invocation manager object
        MessageEvent event = new MessageEvent(
            _imoid, InvocationObject.REQUEST_NAME, iargs);

        // if we have a response target, register that for later receipt
        // of the response
        if (rsptarget != null) {
            _targets.put(invid, rsptarget);
        }

        // and finally ship off the invocation message
        _omgr.postEvent(event);

        return invid;
    }

    /**
     * Registers the supplied invocation receiver instance as the handler
     * for all invocation notifications for the specified module.
     */
    public void registerReceiver (String module, InvocationReceiver receiver)
    {
        _receivers.put(module, receiver);
    }

    public void objectAvailable (DObject object)
    {
        // let the client know that we're ready to go now that we've got
        // our subscription to the client object
        _client.invocationManagerReady();
    }

    public void requestFailed (int oid, ObjectAccessException cause)
    {
        // aiya! we were unable to subscribe to the client object. we're
        // hosed, hosed, hosed
        Log.warning("Invocation manager unable to subscribe to client " +
                    "object. All is wrong in the universe.");
    }

    /**
     * Process incoming message requests on user object.
     */
    public boolean handleEvent (DEvent event, DObject target)
    {
        // we only care about message events
        if (!(event instanceof MessageEvent)) {
            return true;
        }

        // and only those of proper name
        MessageEvent mevt = (MessageEvent)event;
        String name = mevt.getName();
        if (name.equals(InvocationObject.RESPONSE_NAME)) {
            handleInvocationResponse(mevt.getArgs());
        } else if (name.equals(InvocationObject.NOTIFICATION_NAME)) {
            handleInvocationNotification(mevt.getArgs());
        }

        return true;
    }

    /**
     * Processes an invocation response message.
     */
    protected void handleInvocationResponse (Object[] args)
    {
        String name = (String)args[0];
        int invid = ((Integer)args[1]).intValue();

        Object rsptarg = _targets.get(invid);
        if (rsptarg == null) {
            Log.warning("No target for invocation response " +
                        "[args=" + StringUtil.toString(args) + "].");
            return;
        }

        // prune the invocation id and method arguments from the full
        // message arguments
        Object[] rargs = new Object[args.length-1];
        System.arraycopy(args, 1, rargs, 0, rargs.length);

        // and invoke the response method
        String mname = "handle" + name;
        Method rspmeth = ClassUtil.getMethod(mname, rsptarg, _methcache);
        if (rspmeth == null) {
            Log.warning("Unable to resolve response method " +
                        "[target=" + rsptarg.getClass().getName() +
                        ", method=" + mname + "].");
            return;
        }

        // and invoke it
        try {
            rspmeth.invoke(rsptarg, rargs);
        } catch (Exception e) {
            Log.warning("Error invoking response target method " +
                        "[target=" + rsptarg + ", method=" + rspmeth +
                        ", error=" + e + "].");
        }
    }

    /**
     * Processes an invocation notification message.
     */
    protected void handleInvocationNotification (Object[] args)
    {
        String module = (String)args[0];
        String proc = (String)args[1];

        InvocationReceiver receiver =
            (InvocationReceiver)_receivers.get(module);
        if (receiver == null) {
            Log.warning("No receiver registered for notification " +
                        "[args=" + StringUtil.toString(args) + "].");
            return;
        }

        // prune the method arguments from the full message arguments
        Object[] nargs = new Object[args.length-2];
        System.arraycopy(args, 2, nargs, 0, nargs.length);

        // and invoke the receiver method
        String mname = "handle" + proc + "Notification";
        Method rspmeth = ClassUtil.getMethod(mname, receiver, _methcache);
        if (rspmeth == null) {
            Log.warning("Unable to resolve receiver method " +
                        "[target=" + receiver.getClass().getName() +
                        ", method=" + mname + "].");
            return;
        }

        // and invoke it
        try {
            rspmeth.invoke(receiver, nargs);
        } catch (Exception e) {
            Log.warning("Error invoking receiver method " +
                        "[receiver=" + receiver + ", method=" + rspmeth +
                        ", error=" + e + "].");
        }
    }

    public synchronized int nextInvocationId ()
    {
        return _invocationId++;
    }

    protected static class Response
    {
        public String name;
        public Object target;
        public Response (String name, Object target)
        {
            this.name = name;
            this.target = target;
        }
    }

    protected Client _client;
    protected DObjectManager _omgr;
    protected int _imoid;
    protected ClientObject _clobj;

    protected int _invocationId;
    protected IntMap _targets = new IntMap();
    protected HashMap _receivers = new HashMap();
    protected HashMap _methcache = new HashMap();
}
