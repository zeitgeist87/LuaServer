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
-- A simple logger, which supports multiple logging values. It can log
-- to stdout and to a file at the same time
-- 
-- @module Logger

local config = require "config"
config = config.logger

local Logger = {}
local fd

if config.file then
	fd = io.open(config.file, "a")
	if not fd then
		config.file = nil
	else
		fd:setvbuf("full", 2000)
	end
end

function Logger.flush()
	if fd then
		fd:flush()
	end
end

local levels = {debug = 1, info = 2, warn = 3, error = 4, fatal = 5, disable = 6}
local level = levels[config.level] or 3

if not config.stdout and not config.file then
	config.stdout = true
end

-- default handlers to nothing
local function doNothing()
end

local function log(levelstring, ...)
	local info = debug.getinfo(3, "Sl")
	local message = string.format("%d [%s] [%s] %d:", timestamp,
							levelstring, info.short_src, info.currentline)

	if config.stdout then
		print(message, ...)
	end

	if fd then
		fd:write(message)
		for n = 1, select('#', ...) do
			local v = tostring(select(n, ...))
			fd:write("\t", v)
		end
		fd:write("\n")
	end
end

Logger.debug = doNothing
Logger.info = doNothing
Logger.warn = doNothing
Logger.error = doNothing
Logger.fatal = doNothing

if level <= 1 then
	Logger.debug = function(...) log("debug", ...) end
end

if level <= 2 then
	Logger.info = function(...) log("info", ...) end
end

if level <= 3 then
	Logger.warn = function(...) log("warn", ...) end
end

if level <= 4 then
	Logger.error = function(...) log("error", ...) end
end

if level <= 5 then
	Logger.fatal = function(...) log("fatal", ...) end
end

return Logger
