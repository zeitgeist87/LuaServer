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
-- Defines the Request object, which holds all the necessary data of one single
-- HTTP request. It implements many convenience methods to make it easy to
-- interact with
-- 
-- @module Request

local decode = require "socket.url"
local config = require "config"
local random = require "common.random"
local log = require "common.log"

local sessions = {}
local sessionCleanup = timestamp
local Request = {}
Request.__index = Request

function Request.cleanupSessions()
	if timestamp - sessionCleanup > config.sessiontimeout then
		-- cleanup old sessions every 20 minutes or so
		for k, v in pairs(sessions) do
			if timestamp - v.timestamp > config.sessiontimeout then
				-- cleanup session
				sessions[k] = nil
			end
		end
		sessionCleanup = timestamp
	end
end

local function parseUrl(url)
	local params = {}

	-- shortcut
	if url == "/" or url == "/index.lua" then
		return url, params
	end

	local path = url:match("^(/[%a%d/%.%-_%%%+]*)")
	if not path then
		return nil
	end

	local query = url:match("%?([%.%%&%a%d=_%+]+)$")


	if query then
		for k, v in query:gmatch("([%a%d_]+)=([^&]+)") do
			-- always check for null bytes (white lists gsub("\0","") does not work)
			-- filter CR so the param can be output safely
			params[k] = decode.unescape(v:gsub("%+", " "):gsub("%%00", "")):gsub("\r+\n?", "\n")
		end
	end
	-- do not allow null bytes in path
	-- /index.lua%00.jpg downloads the source code of index.lua
	-- because null bytes are allowed in lua but not in the c functions underneath
	-- http://en.wikipedia.org/wiki/Directory_traversal_attack
	-- UTF8 Directory Traversal Vulnerability?
	-- path=decode.unescape(path:gsub("%+"," "):gsub("%%00",""))

	-- path was checked above to only contain a-z0-9 and a few special chars
	-- url decoding the path would be too risky
	path = path:gsub("%.+%s*/", ""):gsub("%+", " "):gsub("%%20", " ")
	return path, params
end

function Request.new(con, method, url, version, headers)
	local path, params = parseUrl(url)
	if not path then
		return nil
	end

	local self = {
		response = true,
		con = con,
		method = method,
		url = url,
		path = path,
		get = params,
		version = version,
		headers = headers,
		multipartLen = 0,
		receivedLen = 0
	}
	headers.CONTENT_LENGTH = (headers.CONTENT_LENGTH and tonumber(headers.CONTENT_LENGTH)) or 0

	-- all instances share the same metatable
	setmetatable(self, Request)
	return self
end

--------------------------------------------------------------------------------
-- Reads at least `len` bytes from the connection. The connections `receive`
-- method just returns what is currently in the TCP buffer or blocks otherwise,
-- so it could return the whole request at once, or line by line or even byte
-- by byte. To simplify the parsing this method accumulates the bytes until
-- a minimum length or more is reached.
-- 
-- @function [parent=#Request] receivePart
-- @param #number len	min length of the returned string
-- @return #string a string of at least length `len`
function Request:receivePart(len)
	local clen = self.headers.CONTENT_LENGTH
	local rlen = self.receivedLen
	
	if self.method == "POST" and clen > 0 and rlen < clen then
		local buffer = {}
		local i = 0
		local outlen = 0

		while rlen < clen and outlen < len do
			local ret = self.con:receive()
			i = i + 1
			buffer[i] = ret
			outlen = outlen + ret:len()
			rlen = rlen + ret:len()
		end

		self.receivedLen = rlen

		if i == 0 then
			-- close connection and exit
			coroutine.yield("close")
		elseif i == 1 then
			return buffer[1]
		else
			return table.concat(buffer)
		end
	end
end

-------------------------------------------------------------------------------
-- Reads in the whole content of the request from the connection into memory.
-- 
-- @function [parent=#Request] receiveAll
-- @return #string the whole content of the request

function Request:receiveAll()
	return self:receivePart(self.headers.CONTENT_LENGTH)
end

-------------------------------------------------------------------------------
-- Returns true if the whole request, including all the content of a POST
-- request was read from the connection. This property is important, because
-- Lua server pages are not required to acutally read the data in a POST
-- request. This leads to problems, if the TCP connection is reused, because
-- the old POST data is read in as a new request. Most of the time this is 
-- harmless, because it would just throw an error and terminate the connection,
-- but a malicious attacker could inject requests this way.
-- 
-- @function [parent=#Request] isFullyReceived
-- @return #boolean true if the whole request was read
function Request:isFullyReceived()
	return self.headers.CONTENT_LENGTH == self.receivedLen
end

-------------------------------------------------------------------------------
-- Puts already read data back into the buffer. Can be useful, if a certain
-- function expects the input buffer to be in a certain state.
-- 
-- @function [parent=#Request] unreceive
-- @param #string input		data to be put back into the buffer
function Request:unreceive(input)
	self.con:unreceive(input)
	-- update byte count
	self.receivedLen = self.receivedLen - input:len()
end

local MultipartFile = {}
MultipartFile.__index = MultipartFile

function MultipartFile.new(req, boundary, filename)
	local self = {
		eof = false,
		boundary = boundary,
		req = req,
		name = filename,
		size = 0
	}
	return setmetatable(self, MultipartFile)
end

function MultipartFile:read()
	local req = self.req
	local boundary = self.boundary
	local blen = boundary:len()
	local negblen = blen * -1
	
	if not self.eof then
		-- download chunk of size uploadmemlimit
		local content = req:receivePart(config.uploadmemlimit)

		if content then
			local p1, p2 = content:find(boundary, 1, true)
			if p1 then
				self.eof = true
				req:unreceive(content:sub(p2 + 1))
				content = content:sub(1, p1 - 3)
				self.size = self.size + content:len()
				
				req:parseMultipartFormData(boundary)
				return content
			elseif content:len() <= blen then
				-- we are at the end of the stream and there is no boundary
				-- do not recheck boundary(infinite loop)
				self.size = self.size + content:len()
				return content
			else
				-- boundary could be at the edge we need to recheck at
				-- least boundary:len() bytes next time
				req:unreceive(content:sub(negblen))
				content = content:sub(1, negblen - 1)
				self.size = self.size + content:len()
				
				return content
			end
		end
	end
	return nil
end

function Request:parseMultipartHeader(boundary, data, header, bodyStart)
	local name, filename
	-- very important lua doesn't cope well with null bytes
	-- (excluded by %z) application has to check filenames very
	-- carefully (Directory Traversal)
	name, filename = header:match("\r\nContent%-Disposition:%s*form%-data;%s*name%s*=%s*\"([%a%d_]+)\";%s*filename%s*=%s*\"([^%z\"/\\]*)\"\r\n")
	
	if filename then
		if filename:len() > 255 then
			log.error("Filename too long")
			return
		end
		
		if filename == "" then
			return data, bodyStart
		end
		
		-- delay download to application
		self:unreceive(data:sub(bodyStart + 1))
		data = nil
		
		self.files[name] = MultipartFile.new(self, boundary, filename)
		return
	end
	
	name = header:match("\r\nContent%-Disposition:%s*form%-data;%s*name%s*=%s*\"([%a%d_]+)\"\r\n")
	header = nil

	if not name or name:len() > 255 then
		log.error("Form field name too long")
		return
	end

	-- it's a normal parameter not a file
	local bodyEnd, headerStart = data:find(boundary, bodyStart, true)
	if bodyEnd then
		-- always check for null bytes (white lists gsub("\0","") does not work)
		-- filter CR so the param can be output safely
		self.post[name] = data:sub(bodyStart + 1, bodyEnd - 3):gsub("%z", ""):gsub("\r+\n?", "\n")
	else
		self:unreceive(data:sub(bodyStart + 1))
		data = nil

		-- try again once
		data = self:receivePart(config.uploadmemlimit)

		bodyEnd, headerStart = data:find(boundary, bodyStart, true)
		if not bodyEnd then
			-- error cannot find boundary within uploadmemlimit
			log.error("Upload contains too much data (>upload mem limit)")
			return
		end
		-- always check for null bytes (white lists gsub("\0","") does not work)
		-- filter CR so the param can be output safely
		self.post[name] = data:sub(1, bodyEnd - 3):gsub("%z", ""):gsub("\r+\n?", "\n")
	end

	-- keep track of the memory usage in params
	self.multipartLen = self.multipartLen + self.post[name]:len()
	if self.multipartLen > config.uploadmemlimit then
		log.error("Upload contains too much data (>upload mem limit)")
		return
	end
	
	return data, headerStart
end

-------------------------------------------------------------------------------
-- Parses multipart/form-data requests on demand. On demand means, that the
-- parsing stops if a file is encountered. The Lua page then has to acutally
-- fully read in the file and do something with it, before the rest of the
-- request can be parsed. This design enables the server to accept files
-- of arbitrary length without the need for temporary files.
-- The application has to loop through all files to guarantee
-- that all values are read in (`read()` executes
-- recursive `parseMultipartFormData()`)
-- 
-- Example:
-- --------
--	for name, file in pairs(files) do
--		...
--		local t=file:read()
--		while t do
--			...
--			t=file:read()
--		end
--		...
--	end
--
-- @function [parent=#Request] parseMultipartFormData
-- @param #string boundary		boundary used by the multipart/form-data
-- @return #table			key/value pairs or empty table
-- @return #table, #table	key/value pairs or empty table, and object containing the files
function Request:parseMultipartFormData(boundary)
	local params = self.post
	local files = self.files
	local blen = boundary:len()
	local clen = self.headers.CONTENT_LENGTH
	local negblen = blen * -1
	local con = self.con

	if not params then
		params = {}
		self.post = params
	end

	if not files then
		files = {}
		self.files = files
	end

	while clen - self.receivedLen > blen do
		local data = self:receivePart(config.uploadmemlimit)
		local headerStart, headerEnd, bodyStart
		headerStart = 1
		headerEnd = 1

		while data and headerEnd do
			headerEnd, bodyStart = data:find("\r\n\r\n", headerStart, true)
			if headerEnd then
				if headerEnd - headerStart > 1024 then
					-- error header shouldn't be larger than 1k
					return params, files
				end

				local header = data:sub(headerStart, headerEnd + 2)
				data, headerStart = self:parseMultipartHeader(boundary, data,
															header, bodyStart)
			end
		end

		-- end of header could be at end of buffer
		if data and headerStart and data:len() - headerStart < 1024
				and clen - self.receivedLen > blen then
			self:unreceive(data:sub(headerStart + 1))
			data = nil
		else
			-- error/finished
			return params, files
		end
	end

	-- throw away the rest of the message
	self:receiveAll()

	return params, files
end

-------------------------------------------------------------------------------
-- Parsers the content of the request and returns the parameters as a table
-- containing key/value pairs. If the content is of type `multipart/form-data`
-- and it contains uploaded files, the files are returned in a separate table
-- 
-- @function [parent=#Request] getPost
-- @return #table			key/value pairs or empty table
-- @return #table, #table	key/value pairs or empty table, and object containing the files

function Request:getPost()
	local params = self.post
	local files = self.files
	local headers = self.headers

	if not params and self.method == "POST" and headers.CONTENT_LENGTH > 0 then
		if headers.CONTENT_LENGTH > config.uploadlimit then
			log.warn("Received upload request, which is bigger than the upload limit: " ..
				headers.CONTENT_LENGTH .. " > " .. config.uploadlimit)
			-- close connection and exit
			-- it is necessary to close the connection,because if we do not
			-- read in the data of this request it will be interpreted as
			-- a new request
			coroutine.yield("close")
		end
		local ctype = headers.CONTENT_TYPE

		if ctype == "application/x-www-form-urlencoded"
				and headers.CONTENT_LENGTH < config.uploadmemlimit then
			local query = self:receiveAll()
			params = {}
			for k, v in query:gmatch("([%a%d_]+)=([%a%d%%%+_%-%.%*]+)") do
				-- always check for null bytes (white lists gsub("\0","") does not work)
				-- filter CR so the param can be output safely
				params[k] = decode.unescape(v:gsub("%+", " "):gsub("%%00", "")):gsub("\r+\n?", "\n")
			end
			self.post = params
		elseif ctype and ctype:sub(1, 20) == "multipart/form-data;" then
			local boundary = ctype:match("multipart/form%-data;%s*boundary%s*=%s*([%a%d%-]+)%s*")
			if boundary then
				boundary = "--" .. boundary

				params, files = self:parseMultipartFormData(boundary)
			end
		end
	end

	if not params then
		params = {}
		self.post = params
	end

	return params, files
end

function Request:getCookies()
	local params = self.cookie
	if not params and self.headers.COOKIE then
		local query = self.headers.COOKIE
		params = {}
		for k, v in query:gmatch("(%$?[%a%d_]+)%s*=%s*([%a%d%%%+_%-%.%*]+)") do
			if k:sub(1, 1) ~= "$" then
				params[k] = v
			end
		end
		self.cookie = params
	end

	if not params then
		params = {}
		self.cookie = params
	end

	return params
end

function Request.htmlspecialchars(s)
	if s then
		s = s:gsub("&", "&amp;"):gsub("\"", "&quot;")
			 :gsub("'", "&#039;"):gsub("<", "&lt;")
			 :gsub(">", "&gt;"):gsub("\r+\n?", "\n")
	end
	return s
end

function Request:getExistingSession()
	if self.session then
		return self.session
	end

	local cookies = self:getCookies()
	local sid = cookies.sid
	local sessions = sessions

	if sid then
		local session = sessions[sid]
		if session then
			if timestamp - session.timestamp < config.sessiontimeout then
				session.timestamp = timestamp
				self.session = session
				return session
			else
				sessions[sid] = nil
			end
		end
	end
	return
end

function Request:getSession()
	local s = self:getExistingSession()
	if s then
		return s
	end

	-- create new session
	local sid
	local sessions = sessions
	repeat
		sid = random.uniqueId()
	until not sessions[sid]

	local token = sid:sub(1, 6)
	s = {getToken = function() return token end}
	sessions[sid] = s
	s.timestamp = timestamp
	s.sid = sid
	local cookies = self:getCookies()
	cookies.sid = sid
	self.response:setCookie("sid", sid, self:isSecure(), true)
	return s
end

function Request:changeSessionId()
	local s = self:getExistingSession()
	if s then
		self:killSession()

		-- create new sid
		local sid
		local sessions = sessions
		repeat
			sid = random.uniqueId()
		until not sessions[sid]

		sessions[sid] = s
		s.timestamp = timestamp
		s.sid = sid
		self.cookie.sid = sid
		self.response:setCookie("sid", sid, self:isSecure(), true)
		return s
	end
end

function Request:killSession(sid)
	local cookies = self:getCookies()
	if not sid then
		sid = cookies.sid
	end

	if sid then
		sessions[sid] = nil
		cookies.sid = nil
		self.response.headers.SET_COOKIE = nil
		self.session = nil
	end
end


function Request:isSecure()
	return self.con:isSecure()
end

return Request
