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
-- Implements the Connection object, which handles one TCP connection
-- 
-- @module Connection

local log = require "common.log"
local config = require "config"
local ssl = require "ssl"
local aio = require "common.aio"
local context = ssl.newcontext(config.httpsparams)

local Connection = {}
Connection.__index = Connection


function Connection.new(socket)
	local ip, port = socket:getsockname()
	local self = {socket = socket,ip = ip,port = port,rest = nil}
	-- all instances share the same metatable
	setmetatable(self, Connection)
	return self
end

function Connection:getIp()
	return self.ip
end

function Connection:getPort()
	return self.port
end

function Connection:close()
	self.socket:close()
end

function Connection:startTLS()
	log.debug("StartTLS")
	local s = ssl.wrap(self.socket, context)

	if s then
		-- to make sure the wrapped socket gets switched
		s:settimeout(0)
		aio.switchConnection(s)

		while s.dohandshake do
			local succ,msg = s:dohandshake()
			if succ then
				self.socket = s
				return true
			else
				coroutine.yield(msg)
			end
		end
	end
	return nil,"Error establisching TLS Connection";
end

-- put something we received back
function Connection:unreceive(input)
	if not self.rest then
		self.rest = input
	else
		self.rest = self.rest .. input
	end
end

function Connection:receive()
	if self.rest then
		local ret = self.rest
		self.rest = nil
		return ret
	else
		while true do
			local s, status, p = self.socket:receive(config.buffersize)

			-- checking for empty string is important: could cause infinite loop
			if s and s ~= "" then
				return s
			elseif p  and p ~= "" then
				return p
			elseif status == "timeout" or status == "wantread" then
				coroutine.yield("wantread")
			elseif status == "wantwrite" then
				coroutine.yield("wantwrite")
			else -- if status == "closed" then
				-- close connection and exit
				coroutine.yield("close")
			end
		end
	end
end

local function findEndOfLine(buffer,bsize)
	local start, stop = buffer[bsize]:find("\r\n", 1, true)
	if start then
		return stop
	elseif bsize > 1 then
		local first = buffer[bsize - 1]:sub(-1)
		local second = buffer[bsize]:sub(1, 1)
		if first == "\r" and second == "\n" then
			return 1
		end
	end
	return nil
end

function Connection:receiveLine()
	local buffer = {}
	local i = 0
	local len = 0

	-- no checks performed
	local ret = self:receive()
	while ret do
		i = i + 1
		buffer[i] = ret
		len = len + ret:len()
		local stop = findEndOfLine(buffer, i)
		if stop then
			local s = buffer[i]
			if stop ~= s:len() then
				self:unreceive(s:sub(stop + 1))
				buffer[i] = s:sub(1,stop)
			end
			break
		end
		if len > 1024 then
			log.error("Line too long aborting...")
			coroutine.yield("close")
		end
		ret = self:receive()
	end

	if i == 0 then
		-- close connection and exit
		coroutine.yield("close")
	elseif i == 1 then
		return buffer[1]:sub(1, -2)
	else
		return table.concat(buffer):sub(1, -2)
	end
end

function Connection:isSecure()
	return self.socket.dohandshake ~= nil
end

function Connection:send(data)
	local pos = 0
	local socket = self.socket

	while true do
		local i, status, p = socket:send(data, pos + 1)
		if i then
			return
		elseif status == "timeout" or status == "wantwrite" then
			coroutine.yield("wantwrite")
		elseif status == "wantread" then
			coroutine.yield("wantread")
		elseif status == "closed" then
			-- close connection and exit
			coroutine.yield("close")
		end
		pos = p
	end
end

function Connection:sendLine(data)
	self:send(data .. "\r\n")
end

return Connection
