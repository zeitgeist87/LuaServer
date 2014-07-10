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
-- Manages connections and coroutines for various protocols
-- 
-- @module Aio

local Aio = {}

local rlist = {}
local slist = {}
local connections = {}
local threads = {}
local timeouts = {}
local servers = {}
local idle = {}

local config = require "config"
local socket = require "socket"
local ssl = require "ssl"
local log = require "common.log"

local function removeByValue(list, value)
	for i, v in ipairs(list) do
		if value == v then
			table.remove(list, i)
			break
		end
	end
end

function Aio.getUDPSocket(address, port)
	local s = socket.udp()
	if s then
		if s:setpeername(address, port) then
			s:settimeout(0)
			return s
		end
	end
	return nil
end

function Aio.suspendConnection(socket)
	if socket then
		removeByValue(rlist, socket)
		removeByValue(slist, socket)
		timeouts[socket] = nil
	end
end

function Aio.removeConnection(socket)
	if not socket then
		return
	end
	removeByValue(rlist, socket)
	removeByValue(slist, socket)
	connections[socket] = nil
	timeouts[socket] = nil
	local thread = coroutine.running()
	if thread then
		connections[thread] = nil
	end
end

function Aio.closeConnection(socket)
	Aio.removeConnection(socket)
	socket:close()
end

function Aio.getCurrentSocket(thread)
	if not thread then
		thread = coroutine.running()
	end
	if thread then
		return connections[thread]
	end
	return nil
end

function Aio.addConnection(socket, thread, mode)
	if not socket then
		return
	end
	socket:settimeout(0)
	if not thread then
		thread = coroutine.running()
	end
	if mode == "wantread" then
		table.insert(rlist, socket)
	elseif mode == "wantwrite" then
		table.insert(slist, socket)
	end
	if thread then
		connections[socket] = thread
		connections[thread] = socket
	end
end

function Aio.switchConnection(socket)
	local currentsocket = Aio.getCurrentSocket()
	if currentsocket then
		Aio.removeConnection(currentsocket)
		Aio.addConnection(socket)
	end
end

local function resumeConnection(socket)
	local thread = connections[socket]
	timeouts[socket] = nil
	local status, msg, timeout = coroutine.resume(thread, socket)
	socket = connections[thread]
	timeouts[socket] = nil

	if timeout then
		timeouts[socket] = timestamp + timeout
	end

	if msg == "wantread" then
		removeByValue(rlist, socket)
		removeByValue(slist, socket)
		table.insert(rlist, socket)
	elseif msg == "wantwrite" or (status and not msg and coroutine.status(connections[socket]) ~= "dead") then
		removeByValue(rlist, socket)
		removeByValue(slist, socket)
		table.insert(slist, socket)
	else
		if status == false then
			log.error(msg)
		end
		connections[socket] = nil
		connections[thread] = nil
		timeouts[socket] = nil
		removeByValue(rlist, socket)
		removeByValue(slist, socket)
		socket:close()
	end
end

function Aio.removeThread(thread)
	removeByValue(threads, thread)
end

function Aio.addThread(thread)
	threads[#threads + 1] = thread
end

-- add a coroutine/thread that is independent of any socket
-- if it yields it will be run at least within the next 5 seconds
function Aio.createThread(handler)
	threads[#threads + 1] = coroutine.create(handler)
	return threads[#threads + 1]
end

function Aio.createServer(port, handler)
	local socket, msg = socket.bind("*", port)
	if not socket then
		log.error(msg)
		return false
	end
	socket:settimeout(0)
	servers[socket] = handler

	local ip, port = socket:getsockname()
	log.info("Port: ",port)
	log.info("Ip: ",ip)
	return true
end

function Aio.addIdleCallback(callback)
	-- check if already in the list
	for _, v in ipairs(idle) do
		if v == callback then
			return
		end
	end
	idle[#idle + 1] = callback
end

local function cleanupGarbage()
	timestamp = os.time()
	rlist = {}
	slist = {}
	connections = {}
	timeouts = {}

	for _, callback in ipairs(idle) do
		callback()
	end

	for s in pairs(servers) do
		rlist[#rlist + 1] = s
	end

	collectgarbage("collect")
end

function Aio.startEventLoop()
	local timeoutcount = 0

	-- after timeoutcountlimit timeouts a cleanup
	-- is forced (for session and bytecode cleanup
	local timeoutcountlimit = config.sessiontimeout/5
	local timeoutdiff = config.sockettimeout/5

	collectgarbage("setpause",500)

	cleanupGarbage()

	while true do
		-- select blocks max for 5 secs, so lua is max for 5 secs unresponsive
		local r, s,err = socket.select(rlist, slist, 5)
		timestamp = os.time()
		if err == "timeout" then
			timeoutcount = timeoutcount + 1
			-- process is idle so do some cleanup
			if timeoutcount > timeoutcountlimit then
				r = nil
				s = nil
				err = nil
				timeoutcount = 0
				cleanupGarbage()
			end
		else
			-- force cleanup next sockettimeout
			timeoutcount = timeoutcountlimit - timeoutdiff
			if r then
				for _, v in ipairs(r) do
					if servers[v] then
						-- v is a server socket
						local client = v:accept()
						if client then
							Aio.addConnection(client, coroutine.create(servers[v]))
							resumeConnection(client)
						end
					elseif connections[v] then
						resumeConnection(v)
					end
				end
			end

			if s then
				for _, v in ipairs(s) do
					if connections[v] then
						resumeConnection(v)
					end
				end
			end
		end

		-- run threads
		if #threads > 0 then
			local livethreads = {}
			for _, t in ipairs(threads) do
				local status, msg = coroutine.resume(t)
				if coroutine.status(t) ~= "dead" then
					livethreads[#livethreads + 1] = t
				end
			end
			threads = livethreads
		end

		if next(timeouts) ~= nil then
			local temptimeouts = {}
			for socket, timeout in pairs(timeouts) do
				temptimeouts[socket] = timeout
			end
			for socket, timeout in pairs(temptimeouts) do
				if timeout < timestamp then
					resumeConnection(socket)
				end
			end
			temptimeouts = nil
		end
	end
end

return Aio
