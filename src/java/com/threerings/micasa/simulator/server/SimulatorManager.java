//
// $Id: SimulatorManager.java,v 1.13 2002/10/06 00:53:15 mdb Exp $

package com.threerings.micasa.simulator.server;

import java.util.ArrayList;

import com.threerings.presents.data.ClientObject;
import com.threerings.presents.dobj.RootDObjectManager;
import com.threerings.presents.server.ClientManager;
import com.threerings.presents.server.ClientResolutionListener;
import com.threerings.presents.server.InvocationManager;
import com.threerings.presents.server.InvocationProvider;

import com.threerings.crowd.data.BodyObject;
import com.threerings.crowd.data.PlaceObject;
import com.threerings.crowd.server.PlaceManager;
import com.threerings.crowd.server.PlaceRegistry.CreationObserver;
import com.threerings.crowd.server.PlaceRegistry;

import com.threerings.parlor.game.GameConfig;
import com.threerings.parlor.game.GameManager;
import com.threerings.parlor.game.GameObject;

import com.threerings.micasa.Log;

/**
 * The simulator manager is responsible for handling the simulator
 * services on the server side.
 */
public class SimulatorManager
{
    /**
     * Initializes the simulator manager manager. This should be called by
     * the server that is making use of the simulator services on the
     * single instance of simulator manager that it has created.
     *
     * @param invmgr a reference to the invocation manager in use by this
     * server.
     */
    public void init (InvocationManager invmgr, PlaceRegistry plreg,
                      ClientManager clmgr, RootDObjectManager omgr,
                      SimulatorServer simserv)
    {
        // register our simulator provider
        SimulatorProvider sprov = new SimulatorProvider(this);
        invmgr.registerDispatcher(new SimulatorDispatcher(sprov), true);

        // keep these for later
        _plreg = plreg;
        _clmgr = clmgr;
        _omgr = omgr;
        _simserv = simserv;
    }

    /**
     * Creates a game along with the specified number of simulant players
     * and forcibly moves all players into the game room.
     */
    public void createGame (
        BodyObject source, GameConfig config, String simClass, int playerCount)
    {
        new CreateGameTask(source, config, simClass, playerCount);
    }

    public class CreateGameTask implements CreationObserver
    {
        public CreateGameTask (
            BodyObject source, GameConfig config, String simClass,
            int playerCount)
        {
            // save off game request info
            _source = source;
            _config = config;
            _simClass = simClass;
            _playerCount = playerCount;

            // determine the AI player skill level
            byte skill;
            try {
                skill = Byte.parseByte(System.getProperty("skill"));
            } catch (NumberFormatException nfe) {
                skill = DEFAULT_SKILL;
            }

            try {
                // create the game manager and begin its initialization
                // process. the game manager will take care of notifying
                // the players that the game has been created once it has
                // been started up (which is done by the place registry
                // once the game object creation has completed)

                // configure the game config with the player names
                config.players = new String[_playerCount];
                config.players[0] = _source.username;
                for (int ii = 1; ii < _playerCount; ii++) {
                    config.players[ii] = "simulant" + ii;
                }

                // we needn't hang around and wait for game object
                // creation if it's just us
                CreationObserver obs = (_playerCount == 1) ? null : this;
                _gmgr = (GameManager)_plreg.createPlace(config, obs);

                for (int ii = 1; ii < _playerCount; ii++) {
                    // mark all simulants as AI players
                    _gmgr.setAI(ii, skill);
                }

            } catch (Exception e) {
                Log.warning("Unable to create game manager [e=" + e + "].");
                Log.logStackTrace(e);
            }
        }

        // documentation inherited
        public void placeCreated (PlaceObject place, PlaceManager pmgr)
        {
            // cast the place to the game object for the game we're creating
            _gobj = (GameObject)place;

            // resolve the simulant body objects
            ClientResolutionListener listener = new ClientResolutionListener()
            {
                public void clientResolved (String username, ClientObject clobj)
                {
                    // hold onto the body object for later game creation
                    _sims.add(clobj);

                    // create the game if we've received all body objects
                    if (_sims.size() == (_playerCount - 1)) {
                        createSimulants();
                    }
                }

                public void resolutionFailed (String username, Exception cause)
                {
                    Log.warning("Unable to create simulant body object " +
                                "[error=" + cause + "].");
                }
            };

            // resolve client objects for all of our simulants
            for (int ii = 1; ii < _playerCount; ii++) {
                String username = "simulant" + ii;
                _clmgr.resolveClientObject(username, listener);
            }
        }

        /**
         * Called when all simulant body objects are present and the
         * simulants are ready to be created.
         */
        protected void createSimulants ()
        {
            // finish setting up the simulants
            for (int ii = 1; ii < _playerCount; ii++) {
                // create the simulant object
                Simulant sim;
                try {
                    sim = (Simulant)Class.forName(_simClass).newInstance();
                } catch (Exception e) {
                    Log.warning("Unable to create simulant " +
                                "[class=" + _simClass + "].");
                    return;
                }

                // give the simulant its body
                BodyObject bobj = (BodyObject)_sims.get(ii - 1);
                sim.init(bobj, _config, _gmgr, _omgr);

                // give the simulant a chance to engage in place antics
                sim.willEnterPlace(_gobj);

                // move the simulant into the game room since they have no
                // location director to move them automagically
                try {
                    _plreg.locprov.moveTo(bobj, _gobj.getOid());
                } catch (Exception e) {
                    Log.warning("Failed to move simulant into room " +
                                "[e=" + e + "].");
                    return;
                }
            }
        }

        /** The simulant body objects. */
        protected ArrayList _sims = new ArrayList();

        /** The game object for the game being created. */
        protected GameObject _gobj;

        /** The game manager for the game being created. */
        protected GameManager _gmgr;

        /** The number of players in the game. */
        protected int _playerCount;

        /** The simulant class instantiated on game creation. */
        protected String _simClass;

        /** The game config object. */
        protected GameConfig _config;

        /** The body object of the player requesting the game creation. */
        protected BodyObject _source;
    }

    // needed for general operation
    protected PlaceRegistry _plreg;
    protected ClientManager _clmgr;
    protected RootDObjectManager _omgr;
    protected SimulatorServer _simserv;

    /** The default skill level for AI players. */
    protected static final byte DEFAULT_SKILL = 50;
}
