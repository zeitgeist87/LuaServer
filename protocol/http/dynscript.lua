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
-- Implements the on the fly loading, caching and optimization of scripts that
-- render web pages
-- 
-- @module DynScript

local lfs = require "lfs"
local config = require "config"
local log = require "common.log"


local DynScript = {}
local byteCache = {}
local byteCacheCleanup = timestamp

function DynScript.cleanup()
	-- cleanup bytecache every now and then
	if timestamp - byteCacheCleanup > config.bytecachetimeout then
		for p, e in pairs(byteCache) do
			if timestamp - e.used > config.bytecachetimeout then
				-- cleanup cache
				byteCache[p] = nil
			end
		end
		byteCacheCleanup = timestamp
	end
end

local function loadCode(code)
	if setfenv and loadstring then
		local f, errormsg = loadstring(code)
		setfenv(f, {})
		return f, errormsg
	else
		return load(code, nil, "t",{})
	end
end

local function callScript(script, env)
	if setfenv then
		setfenv(script, env)
	end
	-- pcall prevents yield pcall(script, env)
	script(env)
	return true
end

local function optimizeTemplate(input, cwd)
	-- optimizations
	-- inline printTemplates with constant path
	local pos = 1
	while pos do
		local start, stop, path = input:find("%sprintTemplate%([\"\']([^\"\']+)[\"\']%)%s",pos)
		pos = stop
		if path then
			local fd = io.open(cwd .. "/" .. path, "r")
				if fd then
				local input2 = fd:read("*all")
				fd:close()
				if input2 then
					input = input:sub(1, start) .. "?>" .. input2 .. "<?" .. input:sub(stop + 1)
					pos = start
				end
			end
		end
	end	

	-- cleanup from inline
	input = input:gsub("<%?%s*%?>","")

	input = input:gsub("<%?","]===])\n")
	input = input:gsub("%?>","\nres:send([===[")

	-- minify probably not safe for lua/js code!!!
	input = input:gsub("\n%s+","\n")
	input = input:gsub("%s+\n","\n")

	-- inline echo
	input = input:gsub("%secho%(","\nres:send(")

	-- merge consecutive echo calls
	local count
	repeat
		input, count = input:gsub("res:send%(([^%)]+)%)%s*res:send%(", "res:send(%1,")
	until count == 0

	-- merge consecutive strings
	repeat
		input, count = input:gsub("%]===%]%s*,%s*%[===%[", "")
	until count == 0

	repeat
		input, count = input:gsub("%]===%]%s*,%s*\"([^\"\\]*)\"", "%1]===]")
	until count == 0

	repeat
		input, count = input:gsub("\"([^\"\\]*)\"%s*,%s*%[===%[", "[===[%1")
	until count == 0

	repeat
		input, count = input:gsub("%]===%]%s*,%s*%[===%[", "")
	until count == 0

	return input
end

-------------------------------------------------------------------------------
-- Loads and compiles a HTML template. It simply wraps all normal html text into
-- multiline lua strings but leaves everything in between <? ?> tags intact.
-- That way the template is turned into a lua script, which can be executed to
-- produce the finished HTML output. The resulting script is stored in the
-- byte cache.
-- 
-- @function loadTemplate
-- @param #string path			path to the script file
-- @param #boolean optimize		if true optimizsations are disabled
-- @param #table req			the request object
-- @param #table res			the response object
-- @param #table context		execution context
local function loadTemplate(path, optimize, req, res, context)
	path = req.cwd .. "/" .. path
	local attr = lfs.attributes(path)

	if not attr or attr.mode ~= "file" then
		res:send("File not Found: ",path)
		return
	end

	log.info("Loading Template", path)

	local mod = attr.modification

	local script, errormsg
	-- lookup cache
	local entry = byteCache[path]
	if entry and entry.modification == mod then
		entry.used = timestamp
		script = entry.script
	else
		-- reload file
		local fd = io.open(path, "r")
		local input = fd:read("*all")
		fd:close()

		input = "return function(_ENV)\nlocal req=req;local res=res\nres:send([===[" .. input .. "]===])\nend"
		
		if not optimize then
			input = optimizeTemplate(input, req.cwd)
		else
			input = input:gsub("<%?", "]===])\n")
			input = input:gsub("%?>", "\nres:send([===[")
		end

		input, errormsg = loadCode(input)

		if input then
			script = input()
			input = nil
			if script then
				entry = {}
				entry.modification = mod
				entry.used = timestamp
				entry.script = script
				byteCache[path] = entry
			end
		end		
	end

	if script then
		return function()
				local succ, err = callScript(script, context)
				if not succ then
					-- print script error to stdout
					log.error(err)
					res:send(err)
				end
			end
	else
		res:send("File not Found: ", path)
	end
end

-------------------------------------------------------------------------------
-- Loads and executes a script file. It first checks if the script is
-- allready available in compiled and optimized form in the byte cache. If not
-- it reads it in and generates the proper sandboxed environment for it to run.
-- 
-- @function [parent=#DynScript] loadScript
-- @param #string path			path to the script file
-- @param #table req			the request object
-- @param #table res			the response object
-- @param #table attr			the output of lfs.attributes
-- @return #string errmsg
function DynScript.loadScript(path, req, res, attr)
	log.info("Loading Script", path)
	local mod = attr.modification

	local script, errormsg
	-- lookup cache
	local entry = byteCache[path]
	if entry and entry.modification == mod then
		entry.used = timestamp
		script = entry.script
	else
		-- reload file
		local fd = io.open(path, "r")
		local input = fd:read("*all")
		fd:close()

		input = "return function(_ENV)\nlocal req=req;local res=res\n" .. input .. "\nend"
		
		input, errormsg = loadCode(input)
		if input then
			script = input()
			input = nil
			if script then
				entry = {}
				entry.modification = mod
				entry.used = timestamp
				entry.script = script
				byteCache[path] = entry
			end
		end		
	end

	if script then
		res.headers.CONTENT_TYPE = "text/html;charset=UTF-8"
		local context = {req = req, res = res, echo = function(...) res:send(...) end}
		function context.loadTemplate(path, disableoptimization) 
			-- shouldn't be necessary in lua 5.2
			return loadTemplate(path, disableoptimization, req, res, context)
		end

		function context.printTemplate(path, disableoptimization) 
			-- shouldn't be necessary in lua 5.2
			return loadTemplate(path, disableoptimization, req, res, context)()
		end

		-- replace require to modify package.path on the fly
		local oldpath = package.path
		local oldrequire = require
		function context.require(...)
			package.path = oldpath .. ";./" .. req.cwd .. "/?.lua;./" .. req.cwd .. "/?"
			local result = oldrequire(...)
			package.path = oldpath
			return result
		end

		local context_mt = { __index = _G }
		if _ENV then
			context_mt.__index = _ENV
		end
		setmetatable(context, context_mt)

		local succ, err = callScript(script, context)
		if not succ then
			-- print script error to stdout
			log.error(err)
			res:send(err)
		end
	end
	
	return errormsg
end

return DynScript