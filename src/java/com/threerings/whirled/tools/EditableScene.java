//
// $Id: EditableScene.java,v 1.1 2001/11/12 20:56:56 mdb Exp $

package com.threerings.whirled.tools;

import com.threerings.whirled.client.DisplayScene;
import com.threerings.whirled.data.SceneModel;

/**
 * The editable scene interface is used in the offline scene building
 * tools as well as by the tools that load those prototype scenes into the
 * runtime database. Accordingly, it provides a means for modifying scene
 * values and for obtaining access to the underlying scene models that
 * represent the underlying scene information.
 *
 * <p> Because the editable scene is used in the scene editor, where it is
 * displayed, the editable scene interface extends the {@link
 * DisplayScene} interface so that the same display mechanisms can be used
 * in the client and the editor. This leaves one anomaly, however which is
 * that {@link #getPlaceConfig} is out of place in the editor or in
 * loading tools. Instead of complicating things with an additional
 * interface that factors out that method, we instead recommend that
 * editable scene implementations simply return null from that method with
 * the expectation that it will never be called.
 */
public interface EditableScene extends DisplayScene
{
    /**
     * Sets this scene's unique identifier.
     */
    public void setId (int sceneId);

    /**
     * Sets this scene's version number.
     */
    public void setVersion (int version);

    /**
     * Sets the ids of the neighbors of this scene.
     */
    public void setNeighborIds (int[] neighborIds);

    /** 
     * Implementations must provide a scene model that represents the
     * current state of this editable scene in response to a call to this
     * method. Whether they maintain an up to date scene model all along
     * or generate one at the time this method is called is up to the
     * implementation.
     */
    public SceneModel getSceneModel ();
}
