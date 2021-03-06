-- LuaServer - A small self contained webserver written entirely in Lua 
-- Copyright (C) 2014 Andreas Rohner
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU Lesser General Public License for more details.
-- 
-- You should have received a copy of the GNU Lesser General Public License
-- along with this program. If not, see <http://www.gnu.org/licenses/>.

-- global vars
-- debug = nil
os.setlocale("C", "numeric");
os.setlocale("C", "time");
os.setlocale("C", "collate");
timestamp = os.time()
-- global vars

local config = require "config"
local db = require "common.db"
local aio = require "common.aio"
local log = require "common.log"

aio.addIdleCallback(db.syncIfChanged)
aio.addIdleCallback(log.flush)

log.info("Starting Server...")

local http, smtp, https
if config.protocol.http then
	http = require "protocol.http.http"
	aio.addIdleCallback(http.cleanup)
	aio.createServer(config.httpport, http.handleConnection)
end

if config.protocol.https then
	https = require "protocol.https.https"
	if not http then
		aio.addIdleCallback(http.cleanup)
	end
	aio.createServer(config.httpsport, https.handleConnection)
end

aio.startEventLoop()

