//
// $Id: TableListView.java,v 1.4 2002/03/18 23:21:26 mdb Exp $

package com.threerings.micasa.lobby.table;

import java.util.Iterator;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;

import javax.swing.BorderFactory;
import javax.swing.JButton;
import javax.swing.JLabel;
import javax.swing.JPanel;
import javax.swing.JScrollPane;
import javax.swing.JSlider;
import javax.swing.JTabbedPane;

import javax.swing.event.ChangeEvent;
import javax.swing.event.ChangeListener;

import com.samskivert.swing.HGroupLayout;
import com.samskivert.swing.VGroupLayout;

import com.threerings.crowd.client.PlaceView;
import com.threerings.crowd.data.PlaceObject;

import com.threerings.parlor.client.TableDirector;
import com.threerings.parlor.client.TableObserver;
import com.threerings.parlor.client.SeatednessObserver;
import com.threerings.parlor.data.Table;
import com.threerings.parlor.data.TableConfig;
import com.threerings.parlor.game.GameConfig;

import com.threerings.micasa.Log;
import com.threerings.micasa.lobby.LobbyConfig;
import com.threerings.micasa.util.MiCasaContext;

/**
 * A view that displays the tables in a table lobby. It displays two
 * separate lists, one of tables being matchmade and another of games in
 * progress. These tables are updated dynamically as they proceed through
 * the matchmaking process. UI mechanisms for creating and joining tables
 * are also provided.
 */
public class TableListView
    extends JPanel
    implements PlaceView, TableObserver, ActionListener, SeatednessObserver,
               ChangeListener
{
    /**
     * Creates a new table list view, suitable for providing the user
     * interface for table-style matchmaking in a table lobby.
     */
    public TableListView (MiCasaContext ctx, LobbyConfig config)
    {
        // keep track of these
        _config = config;
        _ctx = ctx;

        // create our table director
        _tdtr = new TableDirector(ctx, TableLobbyObject.TABLE_SET, this);

        // add ourselves as a seatedness observer
        _tdtr.addSeatednessObserver(this);

        // set up a layout manager
	HGroupLayout gl = new HGroupLayout(HGroupLayout.STRETCH);
	gl.setOffAxisPolicy(HGroupLayout.STRETCH);
	setLayout(gl);

        // we have two lists of tables, one of tables being matchmade...
        VGroupLayout pgl = new VGroupLayout(VGroupLayout.STRETCH);
        pgl.setOffAxisPolicy(VGroupLayout.STRETCH);
        JPanel panel = new JPanel(pgl);
        panel.add(new JLabel("Pending tables"), VGroupLayout.FIXED);

        VGroupLayout mgl = new VGroupLayout(VGroupLayout.NONE);
        mgl.setOffAxisPolicy(VGroupLayout.STRETCH);
        mgl.setJustification(VGroupLayout.TOP);
        _matchList = new JPanel(mgl);
    	_matchList.setBorder(BorderFactory.createEmptyBorder(5, 5, 5, 5));
        panel.add(new JScrollPane(_matchList));

        // create a prototype game config to configure our slider
        try {
            TableConfig tconfig = (TableConfig)config.getGameConfig();
            JPanel cpanel =
                new JPanel(new HGroupLayout(HGroupLayout.STRETCH));
            cpanel.add(new JLabel("Seats:"), HGroupLayout.FIXED);

            int min = tconfig.getMinimumPlayers();
            _pslide = new JSlider(JSlider.HORIZONTAL, min,
                                  tconfig.getMaximumPlayers(), min);
            _pslide.addChangeListener(this);
            cpanel.add(_pslide);

            _pcount = new JLabel(Integer.toString(min));
            cpanel.add(_pcount, HGroupLayout.FIXED);

            _create = new JButton("Create table");
            _create.addActionListener(this);
            cpanel.add(_create, HGroupLayout.FIXED);

            panel.add(cpanel, VGroupLayout.FIXED);

        } catch (Exception e) {
            Log.warning("Unable to obtain prototype game config to " +
                        "configure matchmaking interface.");
            Log.logStackTrace(e);
        }

        add(panel);

        // ...and one of games in progress
        panel = new JPanel(pgl);
        panel.add(new JLabel("Games in progress"), VGroupLayout.FIXED);

        _playList = new JPanel(mgl);
    	_playList.setBorder(BorderFactory.createEmptyBorder(5, 5, 5, 5));
        panel.add(new JScrollPane(_playList));

        add(panel);
    }

    // documentation inherited
    public void willEnterPlace (PlaceObject place)
    {
        // pass the good word on to our table director
        _tdtr.willEnterPlace(place);

        // iterate over the tables already active in this lobby and put
        // them in their respective lists
        TableLobbyObject tlobj = (TableLobbyObject)place;
        Iterator iter = tlobj.tableSet.entries();
        while (iter.hasNext()) {
            tableAdded((Table)iter.next());
        }
    }

    // documentation inherited
    public void didLeavePlace (PlaceObject place)
    {
        // pass the good word on to our table director
        _tdtr.didLeavePlace(place);

        // clear out our table lists
        _matchList.removeAll();
        _playList.removeAll();
    }

    // documentation inherited
    public void tableAdded (Table table)
    {
        Log.info("Table added [table=" + table + "].");

        // create a table item for this table and insert it into the
        // appropriate list
        JPanel panel = table.inPlay() ? _playList : _matchList;
        panel.add(new TableItem(_ctx, _tdtr, table));
        panel.revalidate();
        panel.repaint();
    }

    // documentation inherited
    public void tableUpdated (Table table)
    {
        Log.info("Table updated [table=" + table + "].");

        // locate the table item associated with this table
        TableItem item = getTableItem(table.getTableId());
        if (item == null) {
            Log.warning("Received table updated notification for " +
                        "unknown table [table=" + table + "].");
            return;
        }

        // let the item perform any updates it finds necessary
        item.tableUpdated(table);

        // and we may need to move the item from the match to the in-play
        // list if it just transitioned
        if (table.gameOid != -1 && item.getParent() == _matchList) {
            _matchList.remove(item);
            _matchList.revalidate();
            _matchList.repaint();
            _playList.add(item);
            _playList.revalidate();
            _playList.repaint();
        }
    }

    // documentation inherited
    public void tableRemoved (int tableId)
    {
        Log.info("Table removed [tableId=" + tableId + "].");

        // locate the table item associated with this table
        TableItem item = getTableItem(tableId);
        if (item == null) {
            Log.warning("Received table removed notification for " +
                        "unknown table [tableId=" + tableId + "].");
            return;
        }

        // remove this item from the user interface
        JPanel panel = (JPanel)item.getParent();
        panel.remove(item);
        panel.revalidate();
        panel.repaint();

        // let the little fellow know that we gave him the boot
        item.tableRemoved();
    }

    // documentation inherited
    public void actionPerformed (ActionEvent event)
    {
        // the create table button was clicked. pass the word on to the
        // table director
        GameConfig config = null;
        try {
            config = _config.getGameConfig();
        } catch (Exception e) {
            Log.warning("Unable to resolve game config class " +
                        "[lconfig=" + _config + ", error=" + e + "].");
            return;
        }

        if (config instanceof TableConfig) {
            // set the desired number of players
            ((TableConfig)config).setDesiredPlayers(_pslide.getValue());
        }

        // and create a table with these values
        _tdtr.createTable(config);
    }

    // documentation inherited
    public void seatednessDidChange (boolean isSeated)
    {
        // update the create table button
        _create.setEnabled(!isSeated);
    }

    // documentation inherited
    public void stateChanged (ChangeEvent e)
    {
        JSlider source = (JSlider)e.getSource();
        if (!source.getValueIsAdjusting()) {
            _pcount.setText(Integer.toString(source.getValue()));
        }
    }

    /**
     * Fetches the table item component associated with the specified
     * table id.
     */
    protected TableItem getTableItem (int tableId)
    {
        // first check the match list
        int ccount = _matchList.getComponentCount();
        for (int i = 0; i < ccount; i++) {
            TableItem child = (TableItem)_matchList.getComponent(i);
            if (child.table.getTableId() == tableId) {
                return child;
            }
        }

        // then the inplay list
        ccount = _playList.getComponentCount();
        for (int i = 0; i < ccount; i++) {
            TableItem child = (TableItem)_playList.getComponent(i);
            if (child.table.getTableId() == tableId) {
                return child;
            }
        }

        // sorry charlie
        return null;
    }

    /** A reference to the client context. */
    protected MiCasaContext _ctx;

    /** A reference to the lobby config for the lobby in which we are
     * doing table-style matchmaking. */
    protected LobbyConfig _config;

    /** A reference to our table director. */
    protected TableDirector _tdtr;

    /** The list of tables currently being matchmade. */
    protected JPanel _matchList;

    /** The list of tables that are in play. */
    protected JPanel _playList;

    /** Our create table button. */
    protected JButton _create;

    /** Our number of players slider. */
    protected JSlider _pslide;

    /** Our number of players indicator. */
    protected JLabel _pcount;
}
