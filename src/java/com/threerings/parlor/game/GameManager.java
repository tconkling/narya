//
// $Id: GameManager.java,v 1.38 2002/08/14 19:07:53 mdb Exp $

package com.threerings.parlor.game;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;

import com.threerings.presents.data.ClientObject;
import com.threerings.presents.dobj.AttributeChangeListener;
import com.threerings.presents.dobj.AttributeChangedEvent;
import com.threerings.presents.dobj.MessageEvent;

import com.threerings.crowd.chat.SpeakProvider;

import com.threerings.crowd.data.BodyObject;
import com.threerings.crowd.data.PlaceObject;

import com.threerings.crowd.server.PlaceManager;
import com.threerings.crowd.server.CrowdServer;
import com.threerings.crowd.server.CrowdServer;
import com.threerings.crowd.server.PlaceManagerDelegate;

import com.threerings.parlor.Log;
import com.threerings.parlor.data.ParlorCodes;
import com.threerings.parlor.server.ParlorSender;

/**
 * The game manager handles the server side management of a game. It
 * manipulates the game state in accordance with the logic of the game
 * flow and generally manages the whole game playing process.
 *
 * <p> The game manager extends the place manager because games are
 * implicitly played in a location, the players of the game implicitly
 * bodies in that location.
 */
public class GameManager extends PlaceManager
    implements ParlorCodes, GameProvider, AttributeChangeListener
{
    /**
     * Provides the game manager with a list of the usernames of all
     * players in the game. This happens before startup and before the
     * game object has been created.
     *
     * @param players the usernames of all of the players in this game or
     * a zero-length array if the game has no specific set of players.
     */
    public void setPlayers (String[] players)
    {
        // keep this around for now, we'll need it later
        _players = players;

        // instantiate a player oid array which we'll fill in later
        _playerOids = new int[players.length];
    }

    /**
     * Sets the specified player as an AI with the specified skill.  It is
     * assumed that this will be set soon after the player names for all
     * AIs present in the game. (It should be done before human players
     * start trickling into the game.)
     *
     * @param pidx the player index of the AI.
     * @param skill the skill level, from 0 to 100 inclusive.
     */
    public void setAI (final int pidx, final byte skill)
    {
        if (_AIs == null) {
            // create and initialize the AI skill level array
            _AIs = new byte[_players.length];
            Arrays.fill(_AIs, (byte)-1);
            // set up a delegate op for AI ticking
            _tickAIOp = new TickAIDelegateOp();
        }

        // save off the AI's skill level
        _AIs[pidx] = skill;

        // let the delegates know that the player's been made an AI
        applyToDelegates(new DelegateOp() {
            public void apply (PlaceManagerDelegate delegate) {
                ((GameManagerDelegate)delegate).setAI(pidx, skill);
            }
        });
    }

    /**
     * Returns the name of the player with the specified index.
     */
    public String getPlayerName (int index)
    {
        return _players[index];
    }

    /**
     * Returns the user object oid of the player with the specified index.
     */
    public int getPlayerOid (int index)
    {
        return _playerOids[index];
    }

    /**
     * Returns the number of players in the game.
     */
    public int getPlayerCount ()
    {
        return _players.length;
    }

    /**
     * Returns whether the player at the specified player index is an AI.
     */
    public boolean isAI (int pidx)
    {
        return (_AIs != null && _AIs[pidx] != -1);
    }

    /**
     * Returns whether the game is over.
     */
    public boolean isGameOver ()
    {
        return (_gameobj.state == GameObject.GAME_OVER);
    }

    /**
     * Returns the unique round identifier for the current round.
     */
    public int getRoundId ()
    {
        return _gameobj.roundId;
    }

    /**
     * Sends a system message to the players in the game room.
     */
    public void systemMessage (String msgbundle, String msg)
    {
        systemMessage(msgbundle, msg, false);
    }

    /**
     * Sends a system message to the players in the game room.
     *
     * @param waitForStart if true, the message will not be sent until the
     * game has started.
     */
    public void systemMessage (
        String msgbundle, String msg, boolean waitForStart)
    {
        if (waitForStart &&
            ((_gameobj == null) ||
             (_gameobj.state == GameObject.AWAITING_PLAYERS))) {
            // queue up the message.
            if (_startmsgs == null) {
                _startmsgs = new ArrayList();
            }
            _startmsgs.add(msgbundle);
            _startmsgs.add(msg);
            return;
        }

        // otherwise, just deliver the message
        SpeakProvider.sendSystemSpeak(_gameobj, msgbundle, msg);
    }

    // documentation inherited
    protected Class getPlaceObjectClass ()
    {
        return GameObject.class;
    }

    // documentation inherited
    protected void didStartup ()
    {
        super.didStartup();

        // obtain a casted reference to our game object
        _gameobj = (GameObject)_plobj;

        // stick the players into the game object
        _gameobj.setPlayers(_players);

        // create and fill in our game service object
        GameMarshaller service = (GameMarshaller)
            _invmgr.registerDispatcher(new GameDispatcher(this), false);
        _gameobj.setService(service);

        // let the players of this game know that we're ready to roll (if
        // we have a specific set of players)
        if (_players != null) {
            int gameOid = _gameobj.getOid();
            for (int i = 0; i < _players.length; i++) {
                BodyObject bobj = CrowdServer.lookupBody(_players[i]);
                if (bobj == null) {
                    Log.warning("Unable to deliver game ready to " +
                                "non-existent player " +
                                "[gameOid=" + gameOid +
                                ", player=" + _players[i] + "].");
                    continue;
                }

                // deliver a game ready notification to the player
                ParlorSender.gameIsReady(bobj, gameOid);
            }
        }
    }

    // documentation inherited
    protected void bodyLeft (int bodyOid)
    {
        super.bodyLeft(bodyOid);

        // deal with disappearing players
    }

    /**
     * When a game room becomes empty, we cancel the game if it's still in
     * progress and close down the game room.
     */
    protected void placeBecameEmpty ()
    {
        Log.info("Game room empty. Going away. " +
                 "[gameOid=" + _gameobj.getOid() + "].");

        // cancel the game if it wasn't over.
        if (_gameobj.state != GameObject.GAME_OVER) {
            _gameobj.setState(GameObject.CANCELLED);
        }

        // shut down the place (which will destroy the game object and
        // clean up after everything)
        shutdown();
    }

    /**
     * Called when all players have arrived in the game room. By default,
     * this starts up the game, but a manager may wish to override this
     * and start the game according to different criterion.
     */
    protected void playersAllHere ()
    {
        // start up the game (if we haven't already)
        if (_gameobj.state == GameObject.AWAITING_PLAYERS) {
            startGame();
        }
    }

    /**
     * This is called when the game is ready to start (all players
     * involved have delivered their "am ready" notifications). It calls
     * {@link #gameWillStart}, sets the necessary wheels in motion and
     * then calls {@link #gameDidStart}.  Derived classes should override
     * one or both of the calldown functions (rather than this function)
     * if they need to do things before or after the game starts.
     */
    public void startGame ()
    {
        // complain if we're already started
        if (_gameobj.state == GameObject.IN_PLAY) {
            Log.warning("Requested to start an already in-play game " +
                        "[game=" + _gameobj + "].");
            return;
        }

        // let the derived class do its pre-start stuff
        gameWillStart();

        // transition the game to started
        _gameobj.setState(GameObject.IN_PLAY);

        // do post-start processing
        gameDidStart();
    }

    /**
     * Called when the game is about to start, but before the game start
     * notification has been delivered to the players. Derived classes
     * should override this if they need to perform some pre-start
     * activities.
     */
    protected void gameWillStart ()
    {
        // let our delegates do their business
        applyToDelegates(new DelegateOp() {
            public void apply (PlaceManagerDelegate delegate) {
                ((GameManagerDelegate)delegate).gameWillStart();
            }
        });
    }

    /**
     * Called after the game start notification was dispatched.  Derived
     * classes can override this to put whatever wheels they might need
     * into motion now that the game is started (if anything other than
     * transitioning the game to <code>IN_PLAY</code> is necessary).
     */
    protected void gameDidStart ()
    {
        // let our delegates do their business
        applyToDelegates(new DelegateOp() {
            public void apply (PlaceManagerDelegate delegate) {
                ((GameManagerDelegate)delegate).gameDidStart();
            }
        });

        // inform the players of any pending messages.
        if (_startmsgs != null) {
            for (Iterator iter = _startmsgs.iterator(); iter.hasNext(); ) {
                systemMessage((String) iter.next(), // bundle
                              (String) iter.next()); // message
            }
            _startmsgs = null;
        }

        // and register ourselves to receive AI ticks
        if (_AIs != null) {
            AIGameTicker.registerAIGame(this);
        }
    }

    /**
     * Called by the AIGameTicker if we're registered as an AI game.
     */
    protected void tickAIs ()
    {
        for (int ii=0; ii < _AIs.length; ii++) {
            byte level = _AIs[ii];
            if (level != -1) {
                tickAI(ii, level);
            }
        }
    }

    /**
     * Called by tickAIs to tick each AI in the game.
     */
    protected void tickAI (int pidx, byte level)
    {
        _tickAIOp.setAI(pidx, level);
        applyToDelegates(_tickAIOp);
    }

    /**
     * Called when the game is known to be over. This will call some
     * calldown functions to determine the winner of the game and then
     * transition the game to the <code>GAME_OVER</code> state.
     */
    public void endGame ()
    {
        // figure out who won...

        // transition to the game over state
        _gameobj.setState(GameObject.GAME_OVER);

        // wait until we hear the game state transition on the game object
        // to invoke our game over code so that we can be sure that any
        // final events dispatched on the game object prior to the call to
        // endGame() have been dispatched
    }

    /**
     * Called after the game has transitioned to the
     * <code>GAME_OVER</code> state. Derived classes should override this
     * to perform any post-game activities.
     */
    protected void gameDidEnd ()
    {
        // remove ourselves from the AIticker, if applicable
        if (_AIs != null) {
            AIGameTicker.unregisterAIGame(this);
        }

        // let our delegates do their business
        applyToDelegates(new DelegateOp() {
            public void apply (PlaceManagerDelegate delegate) {
                ((GameManagerDelegate)delegate).gameDidEnd();
            }
        });

        // calculate ratings and all that...
    }

    /**
     * Called when the game is to be reset to its starting state in
     * preparation for a new game without actually ending the current
     * game. It calls {@link #gameWillReset} and {@link #gameDidReset}.
     * The standard game start processing ({@link #gameWillStart} and
     * {@link #gameDidStart}) will also be called (in between the calls to
     * will and did reset). Derived classes should override one or both of
     * the calldown functions (rather than this function) if they need to
     * do things before or after the game resets.
     */
    public void resetGame ()
    {
        // let the derived class do its pre-reset stuff
        gameWillReset();

        // increment the round identifier
        _gameobj.setRoundId(_gameobj.roundId + 1);

        // do the standard game start processing
        gameWillStart();
        _gameobj.setState(GameObject.IN_PLAY);
        gameDidStart();

        // let the derived class do its post-reset stuff
        gameDidReset();
    }

    /**
     * Called when the game is about to reset, but before the board has
     * been re-initialized or any other clearing out of game data has
     * taken place.  Derived classes should override this if they need to
     * perform some pre-reset activities.
     */
    protected void gameWillReset ()
    {
        // let our delegates do their business
        applyToDelegates(new DelegateOp() {
            public void apply (PlaceManagerDelegate delegate) {
                ((GameManagerDelegate)delegate).gameWillReset();
            }
        });
    }

    /**
     * Called after the game has been reset.  Derived classes can override
     * this to put whatever wheels they might need into motion now that
     * the game is reset.
     */
    protected void gameDidReset ()
    {
        // let our delegates do their business
        applyToDelegates(new DelegateOp() {
            public void apply (PlaceManagerDelegate delegate) {
                ((GameManagerDelegate)delegate).gameDidReset();
            }
        });
    }

    // documentation inherited from interface
    public void playerReady (ClientObject caller)
    {
        BodyObject plobj = (BodyObject)caller;

        // make a note of this player's oid
        int pidx = _gameobj.getPlayerIndex(plobj.username);
        if (pidx == -1) {
            Log.warning("Received playerReady() from non-player? " +
                        "[caller=" + caller + "].");
            return;
        }
        _playerOids[pidx] = plobj.getOid();

        // and check to see if we're all set
        boolean allSet = true;
        for (int ii = 0; ii < _players.length; ii++) {
            if ((_playerOids[ii] == 0) &&
                ((_AIs == null) || (_AIs[ii] == -1))) {
                allSet = false;
            }
        }

        // if everyone is now ready to go, make a note of it
        if (allSet) {
            playersAllHere();
        }
    }

    // documentation inherited
    public void attributeChanged (AttributeChangedEvent event)
    {
        if (event.getName().equals(GameObject.STATE)) {
            switch (event.getIntValue()) {
            case GameObject.CANCELLED:
                // fall through to GAME_OVER case
            case GameObject.GAME_OVER:
                // now we do our end of game processing
                gameDidEnd();
                break;
            }
        }
    }

    /**
     * A helper operation to distribute AI ticks to our delegates.
     */
    protected class TickAIDelegateOp implements DelegateOp
    {
        public void apply (PlaceManagerDelegate delegate) {
            ((GameManagerDelegate) delegate).tickAI(_pidx, _level);
        }

        public void setAI (int pidx, byte level)
        {
            _pidx = pidx;
            _level = level;
        }

        protected int _pidx;
        protected byte _level;
    }

    /** A reference to our game object. */
    protected GameObject _gameobj;

    /** The usernames of the players of this game. */
    protected String[] _players;

    /** The oids of our player and AI body objects. */
    protected int[] _playerOids;

    /** If AIs are present, contains their skill levels, or -1 at human
     * player indexes. */
    protected byte[] _AIs;

    /** If non-null, contains bundles and messages that should be sent
     * as system messages once the game has started. */
    protected ArrayList _startmsgs;

    /** Our delegate operator to tick AIs. */
    protected TickAIDelegateOp _tickAIOp;
}
