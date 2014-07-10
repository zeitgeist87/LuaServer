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
-- Generates unique ids and reseeds the random number generator automatically
-- 
-- @module Random

local log = require "common.log"

local Random = {}

function Random.seedRandom()
	local function bytes_to_int(b1, b2, b3, b4)
		local n = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
		return n
	end

	local f = io.open("/dev/urandom", "r")
	local t

	if f then
		t = bytes_to_int(f:read(4):byte(1, 4))
	else
		t = os.time()
	end

	-- t = 2147483648
	t = (t > 2147483647) and (t - 4294967296) or t
	log.debug(t)
	math.randomseed(t)
end

local idcount = 0
Random.seedRandom()

function Random.uniqueId()
	idcount = idcount + 1
	-- reseed every 1000 ids
	if idcount > 1000 then
		idcount = 0
		Random.seedRandom()
	end

	local r = math.random
	local buffer = {r(65536) - 1, r(65536) - 1, r(65536) - 1, r(65536) - 1,
					r(65536) - 1, r(65536) - 1, r(65536) - 1, r(65536) - 1}

	return table.concat(buffer)
end

return Random
