//
// $Id: SceneService.java,v 1.3 2001/10/01 22:16:02 mdb Exp $

package com.threerings.whirled.client;

import com.threerings.cocktail.cher.client.Client;
import com.threerings.cocktail.cher.client.InvocationManager;

import com.threerings.whirled.Log;

/**
 * The scene service class provides the client interface to the scene
 * related invocation services (e.g. moving from scene to scene).
 */
public class SceneService implements SceneCodes
{
    /**
     * Requests that that this client's body be moved to the specified
     * scene.
     *
     * @param sceneId the scene id to which we want to move.
     * @param sceneVers the version number of the scene object that we
     * have in our local repository.
     */
    public static void moveTo (Client client, int sceneId,
                               int sceneVers, SceneDirector rsptarget)
    {
        InvocationManager invmgr = client.getInvocationManager();
        Object[] args = new Object[] {
            new Integer(sceneId), new Integer(sceneVers) };
        invmgr.invoke(MODULE_NAME, MOVE_TO_REQUEST, args, rsptarget);
        Log.info("Sent moveTo request [scene=" + sceneId +
                 ", version=" + sceneVers + "].");
    }
}
