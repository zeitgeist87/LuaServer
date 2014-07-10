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
-- A simple in memory key/value store that serializes its data to a file
-- 
-- @module Db

local config = require"config"
local Db = {}
-- global vars
local dbTable = {}

local function serializeInit(o, f, n, t)
	if type(o) == "table" and not t[o] then
		t[o] = "v" .. n
		n = n + 1
		f:write("local " .. t[o] .. "={}\n")
		for k, v in pairs(o) do
			n = serializeInit(v, f, n, t)
		end
	end
	return n
end

local function serializeSimple(o, f, t)
	if type(o) == "number" then
		f:write(tostring(o))
	elseif type(o) == "string" then
		f:write(string.format("%q", o))
	elseif type(o) == "boolean" then
		if o then
			f:write("true")
		else
			f:write("false")
		end
	elseif type(o) == "table" then
		f:write(t[o])
	end
end

local function serialize (o, f)
	if type(o) == "table" then
		local t = {}
		serializeInit(o, f, 0, t)
		for table, name in pairs(t) do
			for k, v in pairs(table) do
				f:write(name)
				f:write("[")
				serializeSimple(k, f, t)
				f:write("]=")
				serializeSimple(v, f, t)
				f:write("\n")
			end
		end
		f:write("return " .. t[o])
	else
		f:write("return ")
		serializeSimple(o, f)
	end
end


local changed = false
function Db.put(name, object)
	dbTable[name] = object
	changed = true
end

function Db.changed()
	changed = true
end

function Db.sync()
	local fd = io.open(config.dbfile, "w")
	serialize(dbTable, fd)
	fd:close()
end

function Db.syncIfChanged()
	if changed then
		Db.sync()
		changed = false
	end
end

function Db.load()
	local data = loadfile(config.dbfile, nil, {})
	if not data then
		dbTable = {}
		return
	end

	if setfenv then
		setfenv(data, {})
	end

	data = data()
	if type(data) == "table" then
		dbTable = data
	else
		dbTable = {}
	end
	return
end

function Db.get(name)
	return dbTable[name]
end

Db.load()

return Db
