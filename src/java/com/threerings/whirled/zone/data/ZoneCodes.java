//
// $Id: ZoneCodes.java,v 1.2 2002/08/14 19:07:58 mdb Exp $

package com.threerings.whirled.zone.data;

import com.threerings.whirled.data.SceneCodes;

/**
 * Contains codes used by the zone services.
 */
public interface ZoneCodes extends SceneCodes
{
    /** An error code indicating that a zone identified by a particular
     * zone id does not exist. Usually generated by a failed moveTo
     * request. */
    public static final String NO_SUCH_ZONE = "m.no_such_zone";
}
