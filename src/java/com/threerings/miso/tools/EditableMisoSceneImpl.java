//
// $Id: EditableMisoSceneImpl.java,v 1.9 2002/02/06 17:13:06 mdb Exp $

package com.threerings.miso.scene.tools;

import com.threerings.media.tile.NoSuchTileException;
import com.threerings.media.tile.NoSuchTileSetException;
import com.threerings.media.tile.ObjectTile;
import com.threerings.media.tile.Tile;
import com.threerings.media.tile.TileManager;

import com.threerings.miso.tile.BaseTile;

import com.threerings.miso.scene.DisplayMisoSceneImpl;
import com.threerings.miso.scene.MisoSceneModel;

/**
 * The default implementation of the {@link EditableMisoScene} interface.
 */
public class EditableMisoSceneImpl
    extends DisplayMisoSceneImpl implements EditableMisoScene
{
    /**
     * Constructs an instance that will be used to display and edit the
     * supplied miso scene data. The tiles identified by the scene model
     * will be loaded via the supplied tile manager.
     *
     * @param model the scene data that we'll be displaying.
     * @param tmgr the tile manager from which to load our tiles.
     *
     * @exception NoSuchTileException thrown if the model references a
     * tile which is not available via the supplied tile manager.
     */
    public EditableMisoSceneImpl (MisoSceneModel model, TileManager tmgr)
        throws NoSuchTileException, NoSuchTileSetException
    {
        super(model, tmgr);
        unpackObjectLayer();
    }

    /**
     * Constructs an instance that will be used to display and edit the
     * supplied miso scene data. The tiles identified by the scene model
     * will not be loaded until a tile manager is provided via {@link
     * #setTileManager}.
     *
     * @param model the scene data that we'll be displaying.
     */
    public EditableMisoSceneImpl (MisoSceneModel model)
    {
        super(model);
        unpackObjectLayer();
    }

    // documentation inherited
    public void setMisoSceneModel (MisoSceneModel model)
    {
        super.setMisoSceneModel(model);
        unpackObjectLayer();
    }

    // documentation inherited
    public BaseTile getDefaultBaseTile ()
    {
        return _defaultBaseTile;
    }

    // documentation inherited
    public void setDefaultBaseTile (BaseTile defaultBaseTile, int fqTileId)
    {
        _defaultBaseTile = defaultBaseTile;
        _defaultBaseTileId = fqTileId;
    }

    // documentation inherited
    public void setBaseTile (int x, int y, BaseTile tile, int fqTileId)
    {
        _base.setTile(x, y, tile);
        // update the model as well
        _model.baseTileIds[_model.width*y + x] = fqTileId;
    }

    // documentation inherited
    public void setFringeTile (int x, int y, Tile tile, int fqTileId)
    {
        _fringe.setTile(x, y, tile);
        // update the model as well
        _model.fringeTileIds[_model.width*y + x] = fqTileId;
    }

    // documentation inherited
    public void setObjectTile (int x, int y, ObjectTile tile, int fqTileId)
    {
        ObjectTile prev = _object.getTile(x, y);
        // clear out any previous tile to ensure that everything is
        // properly cleaned up
        if (prev != null) {
            clearObjectTile(x, y);
        }
        // stick the new object into the layer
        _object.setTile(x, y, tile);
        // toggle the "covered" flag on in all base tiles below this
        // object tile
        setObjectTileFootprint(tile, x, y, true);
        // stick this value into our non-sparse object layer
        _objectTileIds[_model.width*y + x] = fqTileId;
    }

    // documentation inherited from interface
    public void setObjectAction (int x, int y, String action)
    {
        _actions.put(objectKey(x, y), action);
    }

    // documentation inherited
    public void clearBaseTile (int x, int y)
    {
        _base.setTile(x, y, _defaultBaseTile);
        // clear it out in the model
        _model.baseTileIds[_model.width*y + x] = _defaultBaseTileId;
    }

    // documentation inherited
    public void clearFringeTile (int x, int y)
    {
        _fringe.setTile(x, y, null);
        // clear it out in the model
        _model.fringeTileIds[_model.width*y + x] = 0;
    }

    // documentation inherited
    public void clearObjectTile (int x, int y)
    {
        ObjectTile tile = _object.getTile(x, y);
        if (tile != null) {
            // toggle the "covered" flag off on the base tiles in this
            // object tile's footprint
            setObjectTileFootprint(tile, x, y, false);
            // clear out the tile itself
            _object.setTile(x, y, null);
        }
        // clear it out in our non-sparse array
        _objectTileIds[_model.width*y + x] = 0;
        // clear out any action for this tile as well
        _actions.remove(objectKey(x, y));
    }

    // documentation inherited from interface
    public void clearObjectAction (int x, int y)
    {
        _actions.remove(objectKey(x, y));
    }

    // documentation inherited
    public MisoSceneModel getMisoSceneModel ()
    {
        // we need to flush the object layer to the model prior to
        // returning it
        int otileCount = 0;
        int cols = _object.getWidth();
        int rows = _object.getHeight();

        // first count how many object tiles we have
        for (int i = 0; i < _objectTileIds.length; i++) {
            if (_objectTileIds[i] != 0) {
                otileCount++;
            }
        }

        // now create and populate the new tileid and actions arrays
        int[] otids = new int[otileCount*3];
        String[] actions = new String[otileCount];
        int otidx = 0, actidx = 0;
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                int tsid = _objectTileIds[_model.width*r + c];
                if (tsid == 0) {
                    continue;
                }
                otids[otidx++] = c;
                otids[otidx++] = r;
                otids[otidx++] = tsid;
                actions[actidx++] = (String)_actions.get(objectKey(c, r));
            }
        }

        // stuff the new arrays into the model
        _model.objectTileIds = otids;
        _model.objectActions = actions;

        // and we're ready to roll
        return _model;
    }

    /**
     * Unpacks the object layer into an array that we can update along
     * with the other layers.
     */
    protected void unpackObjectLayer ()
    {
        // we need this to track object layer mods
        _objectTileIds = new int[_model.baseTileIds.length];

        // populate our non-spare array
        int[] otids = _model.objectTileIds;
        for (int i = 0; i < otids.length; i += 3) {
            int x = otids[i];
            int y = otids[i+1];
            int fqTileId = otids[i+2];
            _objectTileIds[_model.width*y + x] = fqTileId;
        }
    }

    /** A non-sparse array where we can keep track of the object tile
     * ids. */
    protected int[] _objectTileIds;

    /** The default tile with which to fill the base layer. */
    protected BaseTile _defaultBaseTile;

    /** The fully qualified tile id of the default base tile. */
    protected int _defaultBaseTileId;
}
