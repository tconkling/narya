//
// $Id: GameObject.java,v 1.6 2002/08/14 19:07:53 mdb Exp $

package com.threerings.parlor.game;

import com.samskivert.util.ListUtil;
import com.samskivert.util.StringUtil;

import com.threerings.crowd.data.PlaceObject;

/**
 * A game object hosts the shared data associated with a game played by
 * one or more players. The game object extends the place object so that
 * the game can act as a place where players actually go when playing the
 * game. Only very basic information is maintained in the base game
 * object. It serves as the base for a hierarchy of game object
 * derivatives that handle basic gameplay for a suite of different game
 * types (ie. turn based games, party games, board games, card games,
 * etc.).
 */
public class GameObject extends PlaceObject
{
    /** The field name of the <code>service</code> field. */
    public static final String SERVICE = "service";

    /** The field name of the <code>state</code> field. */
    public static final String STATE = "state";

    /** The field name of the <code>isRated</code> field. */
    public static final String IS_RATED = "isRated";

    /** The field name of the <code>players</code> field. */
    public static final String PLAYERS = "players";

    /** The field name of the <code>roundId</code> field. */
    public static final String ROUND_ID = "roundId";

    /** A game state constant indicating that the game has not yet started
     * and is still awaiting the arrival of all of the players. */
    public static final int AWAITING_PLAYERS = 0;

    /** A game state constant indicating that the game is in play. */
    public static final int IN_PLAY = AWAITING_PLAYERS+1;

    /** A game state constant indicating that the game ended normally. */
    public static final int GAME_OVER = IN_PLAY+2;

    /** A game state constant indicating that the game was cancelled. */
    public static final int CANCELLED = GAME_OVER+3;

    /** Provides general game invocation services. */
    public GameMarshaller service;

    /** The game state, one of {@link #AWAITING_PLAYERS}, {@link #IN_PLAY},
     * {@link #GAME_OVER}, or {@link #CANCELLED}. */
    public int state;

    /** Indicates whether or not this game is rated. */
    public boolean isRated;

    /** The username of the players involved in this game. */
    public String[] players;

    /** The unique round identifier for the current round. */
    public int roundId;

    /**
     * Returns the player index of the given user in the game, or 
     * <code>-1</code> if the player is not involved in the game.
     */
    public int getPlayerIndex (String username)
    {
        return (players == null) ? -1 : 
            ListUtil.indexOfEqual(players, username);
    }

    /**
     * Requests that the <code>service</code> field be set to the specified
     * value. The local value will be updated immediately and an event
     * will be propagated through the system to notify all listeners that
     * the attribute did change. Proxied copies of this object (on
     * clients) will apply the value change when they received the
     * attribute changed notification.
     */
    public void setService (GameMarshaller service)
    {
        this.service = service;
        requestAttributeChange(SERVICE, service);
    }

    /**
     * Requests that the <code>state</code> field be set to the specified
     * value. The local value will be updated immediately and an event
     * will be propagated through the system to notify all listeners that
     * the attribute did change. Proxied copies of this object (on
     * clients) will apply the value change when they received the
     * attribute changed notification.
     */
    public void setState (int state)
    {
        this.state = state;
        requestAttributeChange(STATE, new Integer(state));
    }

    /**
     * Requests that the <code>isRated</code> field be set to the specified
     * value. The local value will be updated immediately and an event
     * will be propagated through the system to notify all listeners that
     * the attribute did change. Proxied copies of this object (on
     * clients) will apply the value change when they received the
     * attribute changed notification.
     */
    public void setIsRated (boolean isRated)
    {
        this.isRated = isRated;
        requestAttributeChange(IS_RATED, new Boolean(isRated));
    }

    /**
     * Requests that the <code>players</code> field be set to the specified
     * value. The local value will be updated immediately and an event
     * will be propagated through the system to notify all listeners that
     * the attribute did change. Proxied copies of this object (on
     * clients) will apply the value change when they received the
     * attribute changed notification.
     */
    public void setPlayers (String[] players)
    {
        this.players = players;
        requestAttributeChange(PLAYERS, players);
    }

    /**
     * Requests that the <code>index</code>th element of
     * <code>players</code> field be set to the specified value. The local
     * value will be updated immediately and an event will be propagated
     * through the system to notify all listeners that the attribute did
     * change. Proxied copies of this object (on clients) will apply the
     * value change when they received the attribute changed notification.
     */
    public void setPlayersAt (String value, int index)
    {
        this.players[index] = value;
        requestElementUpdate(PLAYERS, value, index);
    }

    /**
     * Requests that the <code>roundId</code> field be set to the specified
     * value. The local value will be updated immediately and an event
     * will be propagated through the system to notify all listeners that
     * the attribute did change. Proxied copies of this object (on
     * clients) will apply the value change when they received the
     * attribute changed notification.
     */
    public void setRoundId (int roundId)
    {
        this.roundId = roundId;
        requestAttributeChange(ROUND_ID, new Integer(roundId));
    }
}
