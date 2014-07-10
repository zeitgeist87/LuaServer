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

-------------------------------------------------------------------------------
-- Implements the HTTPS protocol by simply starting a TLS connection and using
-- the Http protocol to handle the rest. For this to work, httpsparams
-- in config.lua must be properly set.
-- 
-- @module Https

local config = require "config"
local http = require "protocol.http.http"
local Connection = require "common.connection"
local log = require "common.log"

local Https = {}

function Https.handleConnection(socket)
	local con = Connection.new(socket)
	local succ, errmsg = con:startTLS()

	if succ then
		http.handleConnection(con)
	else
		log.error(errmsg)
		socket:close()
	end
end

return Https
