//
// $Id: ScrollingTestApp.java,v 1.14 2002/06/11 00:04:43 mdb Exp $

package com.threerings.miso.scene;

import java.awt.DisplayMode;
import java.awt.GraphicsConfiguration;
import java.awt.GraphicsDevice;
import java.awt.GraphicsEnvironment;
import java.awt.Image;
import java.awt.Point;

import java.io.IOException;
import java.util.Iterator;

import com.samskivert.swing.util.SwingUtil;
import com.samskivert.util.Config;

import com.threerings.resource.ResourceManager;
import com.threerings.media.FrameManager;
import com.threerings.media.ImageManager;

import com.threerings.media.sprite.Sprite;
import com.threerings.media.sprite.MultiFrameImage;
import com.threerings.media.sprite.MultiFrameImageImpl;

import com.threerings.media.tile.bundle.BundledTileSetRepository;
import com.threerings.media.util.LinePath;

import com.threerings.cast.CharacterComponent;
import com.threerings.cast.CharacterDescriptor;
import com.threerings.cast.CharacterManager;
import com.threerings.cast.NoSuchComponentException;
import com.threerings.cast.bundle.BundledComponentRepository;

import com.threerings.miso.Log;
import com.threerings.miso.MisoConfig;
import com.threerings.miso.tile.MisoTileManager;
import com.threerings.miso.util.MisoContext;

/**
 * Tests the scrolling capabilities of the IsoSceneView.
 */
public class ScrollingTestApp
{
    /**
     * Construct and initialize the scrolling test app.
     */
    public ScrollingTestApp (String[] args)
        throws IOException
    {
        // get the graphics environment
        GraphicsEnvironment env =
            GraphicsEnvironment.getLocalGraphicsEnvironment();

        // get the target graphics device
        GraphicsDevice gd = env.getDefaultScreenDevice();
        Log.info("Graphics device [dev=" + gd +
                 ", mem=" + gd.getAvailableAcceleratedMemory() +
                 ", displayChange=" + gd.isDisplayChangeSupported() +
                 ", fullScreen=" + gd.isFullScreenSupported() + "].");

        // get the graphics configuration and display mode information
        GraphicsConfiguration gc = gd.getDefaultConfiguration();
        DisplayMode dm = gd.getDisplayMode();
        Log.info("Display mode [bits=" + dm.getBitDepth() +
                 ", wid=" + dm.getWidth() + ", hei=" + dm.getHeight() +
                 ", refresh=" + dm.getRefreshRate() + "].");

        // create the window
	_frame = new ScrollingFrame(gc);

        // set up our frame manager
        _framemgr = new FrameManager(_frame);

        // we don't need to configure anything
        ResourceManager rmgr = new ResourceManager(
            "rsrc", null, "config/resource/manager.properties");
        ImageManager imgr = new ImageManager(rmgr, _frame);
	_tilemgr = new MisoTileManager(rmgr, imgr);
        _tilemgr.setTileSetRepository(
            new BundledTileSetRepository(rmgr, imgr, "tilesets"));

        // hack in some different MisoProperties
        MisoConfig.config = new Config("rsrc/config/miso/scrolling");

	// create the context object
	MisoContext ctx = new ContextImpl();

        // create the various managers
        BundledComponentRepository crepo =
            new BundledComponentRepository(rmgr, imgr, "components");
        CharacterManager charmgr = new CharacterManager(crepo);
        charmgr.setCharacterClass(MisoCharacterSprite.class);

        // create our scene view panel
        _panel = new SceneViewPanel(_framemgr, new IsoSceneViewModel()) {
            protected void viewFinishedScrolling () {
                // keep scrolling for a spell
                if (++_sidx < DX.length) {
                    int x = _viewmodel.bounds.width/2,
                        y = _viewmodel.bounds.height/2;
                    LinePath path = new LinePath(
                        x, y, x + DX[_sidx], y + DY[_sidx], 3000l);
                    setPath(path);
                }
            }
            protected int _sidx = -1;
            protected final int[] DX = { 162, 0, 1000, -1000, 1000, 2000 };
            protected final int[] DY = { 140, 1000, 0, 1000, -1000, 1000 };
        };
        _panel.setScrolling(0, 1000, 3000l);
        _frame.setPanel(_panel);

        // create our "ship" sprite
        String scclass = "navsail", scname = "smsloop";
        try {
            CharacterComponent ccomp = crepo.getComponent(scclass, scname);
            CharacterDescriptor desc = new CharacterDescriptor(
                new int[] { ccomp.componentId }, null);

            // now create the actual sprite and stick 'em in the scene
            MisoCharacterSprite s =
                (MisoCharacterSprite)charmgr.getCharacter(desc);
            if (s != null) {
                s.setRestingAction("sailing");
                s.setActionSequence("sailing");
                s.setLocation(160, 144);
                _panel.addSprite(s);
            }

        } catch (NoSuchComponentException nsce) {
            Log.warning("Can't locate ship component [class=" + scclass +
                        ", name=" + scname + "].");
        }

        // set the scene to our scrolling scene
        try {
            _panel.setScene(new ScrollingScene(ctx));

        } catch (Exception e) {
            Log.warning("Error creating scene: " + e);
            Log.logStackTrace(e);
        }

        // size and position the window, entering full-screen exclusive
        // mode if available
        if (gd.isFullScreenSupported()) {
            Log.info("Entering full-screen exclusive mode.");
            gd.setFullScreenWindow(_frame);
            _frame.setUndecorated(true);

        } else {
            Log.warning("Full-screen exclusive mode not available.");
            // _frame.pack();
            _frame.setSize(200, 300);
            SwingUtil.centerWindow(_frame);
        }
    }

    /**
     * The implementation of the MisoContext interface that provides
     * handles to the manager objects that offer commonly used services.
     */
    protected class ContextImpl implements MisoContext
    {
	public MisoTileManager getTileManager ()
	{
	    return _tilemgr;
	}
    }

    /**
     * Run the application.
     */
    public void run ()
    {
        // show the window
        _frame.show();
        _framemgr.start();
    }

    /**
     * Instantiate the application object and start it running.
     */
    public static void main (String[] args)
    {
        try {
            ScrollingTestApp app = new ScrollingTestApp(args);
            app.run();
        } catch (IOException ioe) {
            System.err.println("Error initializing scrolling app.");
            ioe.printStackTrace();
        }
    }

    /** The tile manager object. */
    protected MisoTileManager _tilemgr;

    /** The frame manager. */
    protected FrameManager _framemgr;

    /** The main application window. */
    protected ScrollingFrame _frame;

    /** The main panel. */
    protected SceneViewPanel _panel;
}
