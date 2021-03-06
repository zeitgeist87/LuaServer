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
-- Defines the Response object, which buffers data, concatenates strings
-- and eventually generates a HTTP response.
-- 
-- @module Response

local config = require "config"
local Response = {}
Response.__index = Response

function Response.new(request)
	local self = {
		request = request,
		status = 200,
		statusmsg = "OK",
		headers = {TRANSFER_ENCODING = "chunked"},
		buffer = nil, len = 0,
		headersindex = 1
	}
	
	if request.headers.CONNECTION == "keep-alive" then
		self.headers.CONNECTION = "keep-alive"
	end

	if request.version ~= "1.1" then
		self.headers.TRANSFER_ENCODING = nil
	end

	-- all instances share the same metatable
	setmetatable(self, Response)
	return self
end

function Response:setCookie(k, v, s, h)
	-- with Path=/ the cookie is valid for the whole domain
	local cookie = k .. "=" .. v .. "; Path=/"

	if s then
		cookie = cookie .. "; secure"
	end

	if h then
		cookie = cookie .. "; HttpOnly"
	end

	local headers = self.headers
	if headers.SET_COOKIE then
		headers.SET_COOKIE = headers.SET_COOKIE .. "; " .. cookie
	else
		headers.SET_COOKIE = cookie
	end
end

function Response:redirect(location)
	self.headers.LOCATION = location
	self.headers.TRANSFER_ENCODING = nil
	self.headers.CONTENT_LENGTH = 0
	self.status = 302
	self.statusmsg = "Found"
	self:sendHeaders()
end

function Response:send_with_headers(...)
	self:sendHeaders()
	self:send(...)
end

local insert = table.insert
local buffersize = config.buffersize

function Response:sendFile(fd)
	local ret = fd:read(buffersize)
	local count = 0
	while ret do
		count = count + 1
		if count == 50 then
			-- let others do something
			count = 0
			coroutine.yield()
		end
		self:send(ret)
		ret = fd:read(buffersize)
	end
end

function Response:flush(lastchunk)
	local chunked = self.headers.TRANSFER_ENCODING == "chunked"
	local buffer = self.buffer
	local bsize = #buffer

	if chunked and lastchunk then
		bsize = bsize + 1
		buffer[bsize] = "\r\n0\r\n\r\n"
		if self.len <= 0 then
			chunked = false
		end
	end

	if bsize > 0 then
		if chunked then
			local pattern = "%X"
			insert(buffer, self.headersindex, "\r\n")
			insert(buffer, self.headersindex, pattern:format(self.len))
			if self.headersindex == 1 then
				insert(buffer, self.headersindex, "\r\n")
			end
			self.headersindex = 1
		end

		local data = nil
		if bsize == 1 then
			data = buffer[1]
		else
			data = table.concat(buffer)
		end

		buffer = nil
		-- initialize buffer with 4 opcode NEWTABLE 0 4 0 instead of NEWTABLE 0 0 0
		self.buffer = {nil, nil, nil, nil}
		self.len = 0
		self.request.con:send(data)
	end
end

function Response:send_data(...)
	local buffer = self.buffer
	local bsize = #buffer
	local len = self.len
	local tostring = tostring
	local select = select

	for n = 1, select('#', ...) do
		local v = tostring(select(n, ...))
		buffer[bsize + n] = v
		len = len + v:len()
	end

	self.len = len
	if len >= buffersize then
		self:flush()
	end
end

function Response:send_single_data(input)
	local v = tostring(input)
	self.buffer[#self.buffer + 1] = v
	self.len = self.len + v:len()

	if self.len >= buffersize then
		self:flush()
	end
end

function Response:send_double_data(i1, i2)
	local v = tostring(i1)
	local buffer = self.buffer
	local bsize = #buffer + 1
	
	buffer[bsize] = v
	self.len = self.len + v:len()

	v = tostring(i2)
	buffer[bsize + 1] = v
	self.len = self.len + v:len()

	if self.len >= buffersize then
		self:flush()
	end
end

-- initially "send" also includes headers
Response.send = Response.send_with_headers
Response.send_single = Response.send_with_headers
Response.send_double = Response.send_with_headers

function Response:sendHeaders()
	if self.buffer then
		return
	end
	local headers = self.headers
	local buffer = {"HTTP/", self.request.version, " ", self.status, " ", self.statusmsg, "\r\n"}
	local bsize = #buffer + 1

	if headers.CONTENT_LENGTH then
		headers.TRANSFER_ENCODING = nil
	end

	for k, v in pairs(headers) do
		buffer[bsize] = k:gsub("_", "-")
		buffer[bsize + 1] = ": "
		buffer[bsize + 2] = v
		buffer[bsize + 3] = "\r\n"
		bsize = bsize + 4
	end
	buffer[bsize] = "\r\n"

	self.buffer = buffer
	-- headers have been sent, send only data
	self.send = self.send_data
	self.send_single = self.send_single_data
	self.send_double = self.send_double_data
	self.headersindex = #buffer + 1
end

return Response
