//
// $Id$
//
// Narya library - tools for developing networked games
// Copyright (C) 2002-2012 Three Rings Design, Inc., All Rights Reserved
// http://code.google.com/p/narya/
//
// This library is free software; you can redistribute it and/or modify it
// under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation; either version 2.1 of the License, or
// (at your option) any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

package com.threerings.crowd.chat.client {

import aspire.util.StringUtil;

import com.threerings.crowd.chat.data.ChatCodes;
import com.threerings.crowd.data.BodyObject;
import com.threerings.crowd.util.CrowdContext;
import com.threerings.util.MessageBundle;

public class BroadcastHandler extends CommandHandler
{
    override public function handleCommand (
        ctx :CrowdContext, speakSvc :SpeakService,
        cmd :String, args :String, history :Array) :String
    {
        if (StringUtil.isBlank(args)) {
            return "m.usage_broadcast";
        }

        // mogrify and verify length
        var chatdir :ChatDirector = ctx.getChatDirector();
        args = chatdir.mogrifyChat(args);
        args = chatdir.filter(args, null, true);
        if (args == null) {
            return MessageBundle.compose("m.broadcast_failed", "m.filtered");
        }
        var err :String = chatdir.checkLength(args);
        if (err != null) {
            return err;
        }

        doBroadcast(ctx, args);

        history[0] = cmd + " ";
        return ChatCodes.SUCCESS;
    }

    override public function checkAccess (user :BodyObject) :Boolean
    {
        return (null == user.checkAccess(ChatCodes.BROADCAST_ACCESS, null));
    }

    /**
     * Actually do the broadcast.
     */
    protected function doBroadcast (ctx :CrowdContext, msg :String) :void
    {
        ctx.getChatDirector().requestBroadcast(msg);
    }
}
}
