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
-- Implements the HTTP protocol and handles HTTP connections
-- 
-- @module Http

local lfs = require "lfs"
local Request = require "protocol.http.request"
local Response = require "protocol.http.response"
local Connection = require "common.connection"
local config = require "config"
local log = require "common.log"
local dynscript = require "protocol.http.dynscript"


local Http = {}

local monthTable = {Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
					Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12}
local domains = nil
local statCache

local function readDomainDirectories()
	if config.defaultdomain then
		domains = {}
		for file in lfs.dir(config.wwwdir) do
			if file ~= "." and file ~= ".." then
				local path = config.wwwdir .. "/" .. file
				local attr = lfs.attributes(path)
				if attr and attr.mode == "directory" and file:match("^[%a%d%.]+$") then
					domains[file] = path
				end
			end
		end
	end
end

local function initStatCache()
	if config.usestatcache then
		statCache = {}
		-- statcache is weak table
		-- setmetatable(statcache, { __mode = 'v' })
		local old = lfs.attributes
		lfs.attributes = function(path, att)
			local entry = statCache[path]
			if not entry or entry.timestamp < timestamp - 2 then
				entry = {timestamp = timestamp, attributes = old(path, att)}
				statCache[path] = entry
			end

			if att then
				return entry.attributes[att]
			end
			return entry.attributes
		end
	end
end

function Http.cleanupCache()
	-- cleanup bytecache every now and then
	dynscript.cleanup()
	-- cleanup statcache every timeout
	if config.usestatcache then
		statCache = {}
	end
end

local function findEndOfHeader(buffer, bsize)
	local start, stop = buffer[bsize]:find("\r\n\r\n", 1, true)
	if start then
		return stop
	elseif bsize > 1 then
		local first = buffer[bsize - 1]:sub( - 3)
		local second = buffer[bsize]:sub(1, 3)
		local start, stop = (first .. second):find("\r\n\r\n", 1, true)
		if start then
			return stop - first:len()
		elseif bsize > 2 and buffer[bsize - 1]:len() < 3 then
			local first = buffer[bsize - 2]:sub( - 2)
			local second = buffer[bsize - 1]
			local third = buffer[bsize]:sub(1, 2)
			local start, stop = (first .. second .. third):find("\r\n\r\n", 1, true)
			if start then
				return stop - first:len() - second:len()
			elseif bsize > 3 and buffer[bsize - 1]:len() == 1 and buffer[bsize - 2]:len() == 1 then
				if buffer[bsize - 3]:sub( - 1) == "\r"
						and buffer[bsize - 2] == "\n"
						and buffer[bsize - 1] == "\r"
						and buffer[bsize]:sub(1, 1) == "\n" then
					return 1
				end
			end
		end
	end
	return nil
end

local function receiveRequest(con)
	local buffer = {}
	local bsize = 0
	local len = 0

	while len <= config.buffersize do
		local s = con:receive()
		bsize = bsize + 1
		buffer[bsize] = s
		len = len + s:len()

		if s and len > 17 then
			local stop = findEndOfHeader(buffer, bsize)
			if stop then
				-- found end of header
				if stop ~= s:len() then
					con:unreceive(s:sub(stop + 1))
					s = s:sub(1, stop)
					buffer[bsize] = s
				end
				if bsize == 1 then
					s = buffer[bsize]
				else
					s = table.concat(buffer)
				end
				-- free buffer for gc
				buffer = nil

				local p1, p2, method, url, version =s:find("^(%a%a%a%a?) (/[^%s]*) HTTP/(%d%.%d)\r\n")
				if method == "GET" or method == "POST" then
					local headers = {}
					local key, value
					while p1 do
						p1, p2, key, value =s:find("^([%a%-%.]+):%s+([^\r]+)\r\n",p2 + 1)
						if p1 then
							headers[key:upper():gsub("%-", "_")] = value
						end
					end
					
					headers.CONNECTION = headers.CONNECTION and headers.CONNECTION:lower()

					-- free buffer for gc
					s = nil

					local request = Request.new(con, method, url, version, headers)
					if not request then
						return
					end

					local response = Response.new(request)
					request.response = response

					return request, response
				else
					log.error("unsupported method bad request")
					-- unsupported method bad request
					return nil
				end
			end
		end
	end
	-- request too big
	log.error("request too big")
	return nil
end

local function handleFileNotFound(req, res, errormsg)
	res.status = 404
	res.statusmsg = "File Not Found"
	res.headers.CONTENT_TYPE = "text/plain;charset=UTF-8"

	errormsg = errormsg or "404 File Not Found"
	res.headers.CONTENT_LENGTH = errormsg:len()
	res:send(errormsg)
end


local function parseHttpDate(date)
	if date then
		local day, month, year,
			hour, min, sec = date:match("^%a%a%a, (%d%d) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT$")
		if day then
			return os.time({day = tonumber(day), month = monthTable[month],
							year = tonumber(year), hour = tonumber(hour),
							min = tonumber(min), sec = tonumber(sec),
							isdst = false})
		end
	end
	return nil
end

local function printHttpDate(date)
	return os.date("!%a, %d %b %Y %X GMT",date)
end

local function handleRequest(req, res)
	if not req.path or req.path == "/" then
		req.path = "/index.lua"
	end

	local path = config.wwwdir
	local defaultdomain = config.defaultdomain
	if defaultdomain then
		-- vhost
		local host = req.headers.HOST
		if not host then
			host = defaultdomain
		else
			host = host:match("^[%d%a%.]+")
		end


		path = domains[host]
		req.host = host
		if not path then
			path = domains[defaultdomain]
			req.host = defaultdomain
			if not path then
				handleFileNotFound(req, res)
				return
			end
		end
	end

	-- try rewrite rules
	local rules = config.rewriterules[req.host]
	if rules then
		for _, rule in pairs(rules) do
			if rule(req) then
				break
			end
		end
	end

	local cwd = path
	req.cwd = cwd
	path = path .. req.path

	local attr = lfs.attributes(path)
	if attr and attr.mode == "directory" then
		path = path .. "/index.lua"
		attr = lfs.attributes(path)
	end

	if attr and attr.mode == "file" then
		-- file found
		-- res.headers.DATE=printHttpDate(timestamp)

		local ext = path:match("%.([%a]+)$")
		local gzext

		if ext == "gz" then
			gzext = path:match("%.([%a]+)%.gz$")
			if gzext then
				ext = gzext
				gzext = "gz"
			end
		end

		if ext == "lua" then
			local errmsg = dynscript.loadScript(path, req, res, attr)
			if errmsg then
				handleFileNotFound(req, res, errmsg)
			end
		elseif ext == "lsp" then
			handleFileNotFound(req, res)
		else
			log.info("Opening file",path)
			-- static files expire after the time
			-- since the last modification + 20 minutes
			local expires = 2 * timestamp - attr.modification + 2 * 24 * 60 * 60
			res.headers.EXPIRES = printHttpDate(expires)
			res.headers.LAST_MODIFIED = printHttpDate(attr.modification)
			-- res.headers.ACCEPT_RANGES="bytes"

			local modsince = parseHttpDate(req.headers.IF_MODIFIED_SINCE)
			if modsince and attr.modification - modsince <= 0 then
				res.status = 304
				res.statusmsg = "Not Modified"
				res.headers.TRANSFER_ENCODING = nil
				res:sendHeaders()
				return
			end

			local mtype = config.mimetypes[ext]
			res.headers.CONTENT_TYPE = mtype or "application/octet"

			-- support for html.gz js.gz ...
			if mtype and gzext and req.headers.ACCEPT_ENCODING
				and req.headers.ACCEPT_ENCODING:match("gzip") then
				res.headers.CONTENT_ENCODING = "gzip"
			end

			-- send file
			local range = nil
			if req.headers.RANGE then
				local r = req.headers.RANGE:match("bytes%s*=%s*(%d+)%s*%-")
				if r then
					range = tonumber(r)
				end
			end


			local fd = io.open(path, "r")
			if fd then
				res.headers.CONTENT_LENGTH = attr.size
				if range and range < attr.size then
					fd:seek("set",range)
					res.status = 206
					res.statusmsg = "Partial content"
					res.headers.CONTENT_LENGTH = attr.size - range
					res.headers.CONTENT_RANGE = "bytes " .. range .. "-" ..
											attr.size - 1 .. "/" .. attr.size
				end
				res:sendFile(fd)
				fd:close()
			else
				handleFileNotFound(req, res)
			end
		end
	else
		handleFileNotFound(req, res)
	end
end

function Http.handleConnection(socket)
	-- check if its a socket or a connection
	local con = socket
	if not socket.unreceive then
		con = Connection.new(socket)
	end

	log.info("New HTTP-Connection:",con:getIp(), con:getPort())
	while true do
		timestamp = os.time()
		local req, res = receiveRequest(con)
		if req then
			handleRequest(req, res)

			res:flush(true)

			if res.headers.CONNECTION ~= "keep-alive" then
				return
			end
			
			if not req:isFullyReceived() then
				log.error("Request was not fully received, closing connection")
				return
			end
		else
			return
		end
	end
end

function Http.cleanup()
	Request.cleanupSessions()
	Http.cleanupCache()
end

readDomainDirectories()
initStatCache()

return Http
