module(..., package.seeall)

local lfs=require "lfs"

--global vars
local bytecache={}
local bytecachecleanup=timestamp
local monthtable={Jan=1,Feb=2,Mar=3,Apr=4,May=5,Jun=6,Jul=7,Aug=8,Sep=9,Oct=10,Nov=11,Dec=12}
local domains=nil
if defaultdomain then
	domains={}
	for file in lfs.dir(wwwdir) do
		if file ~= "." and file ~= ".." then
			local path=wwwdir .. "/" .. file
			local attr=lfs.attributes(path)
			if attr and attr.mode == "directory" and file:match("^[%a%d%.]+$") then
				domains[file]=path
			end
		end
	end
end

do
	local statcache
	if usestatcache then
		statcache={}
		--statcache is weak table
		--setmetatable(statcache, { __mode = 'v' })
		local old=lfs.attributes
		function lfs.attributes(path,att)
			local entry=statcache[path]
			if not entry or entry.timestamp<timestamp-2 then
				entry={timestamp=timestamp,attributes=old(path,att)}
				statcache[path]=entry
			end

			if att then
				return entry.attributes[att]
			end
			return entry.attributes
		end
	end

	function cleanupCache()
		--cleanup bytecache every now and then
		if timestamp-bytecachecleanup>bytecachetimeout then
			for p,e in pairs(bytecache) do
				if timestamp-e.used>bytecachetimeout then
					--cleanup cache
					bytecache[p]=nil
				end
			end
			bytecachecleanup=timestamp
		end
		--cleanup statcache every timeout
		if usestatcache then
			statcache={}
		end
	end
end
--global vars

local function handleFileNotFound(request,response,errormsg)
	response.status=404
	response.statusmsg="File Not Found"
	response.headers.CONTENT_TYPE="text/plain;charset=UTF-8"

	errormsg = errormsg or "404 File Not Found"
	response.headers.CONTENT_LENGTH=errormsg:len()
	response:send(errormsg)
end


local function parseHttpDate(date)
	if date then
		local day,month,year,hour,min,sec=date:match("^%a%a%a, (%d%d) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT$")
		if day then
			return os.time({day=tonumber(day),month=monthtable[month],year=tonumber(year),hour=tonumber(hour),min=tonumber(min),sec=tonumber(sec),isdst=false})
		end
	end
	return nil
end

local function printHttpDate(date)
	return os.date("!%a, %d %b %Y %X GMT",date)
end

local function include(path,attr,request,response,rootdir)
	if not attr then
		attr=lfs.attributes(path)
		if not attr or attr.mode ~= "file" then
			path=rootdir .. "/" .. path
			attr=lfs.attributes(path)
			if not attr or attr.mode ~= "file" then
				handleFileNotFound(request,response,errormsg)
				return
			end
		end
	end

	local modification=attr.modification

	local script,errormsg
	--lookup cache
	local entry=bytecache[path]
	if entry and entry.modification==modification then
		entry.used=timestamp
		script=entry.script
	else
		--reload file
		local fd=io.open(path,"r")
		local input=fd:read("*all")
		fd:close()
		local start=input:sub(1,2)
		if start=="<?" then
			--allow to set headers
			input=input:sub(3)
		end

		--minify probably not safe for lua/js code!!!
		input=input:gsub("\n%s+","\n")
		input=input:gsub("%s+\n","\n")
		--minify probably not safe for lua/js code!!!

		input=input:gsub("send%(([^%)]+)%)%s*%?>","send(%1,[===[")
		input=input:gsub("<%?%s*send%(","]===],")
		input=input:gsub("<%?","]===])\n")
		input=input:gsub("%?>","\nres:send([===[")

		--experimentell
		--input=input:gsub("%ssend%(","\nres:send(")
		input=input:gsub("([^:%w_])send%(","%1res:send(")
		input=input:gsub("([%s,;%(%)])include%(([^%),]+)%)","%1include(%2,nil,req,res,root)")

		input=input:gsub("send%(([^%)]+)%)%s*res:send%(","send(%1,")
		input=input:gsub("send%(([^%)]+)%)%s*res:send%(","send(%1,")


		if start=="<?" then
			start=""
		else
			start="res:send([===["
		end

		input="return function(req,res,include,root)\n" .. start .. input .. "]===])\nend"
		
		--avoid overhead of select
		input=input:gsub("res:send%(([^,]+)%)","res:send_single(%1)")
		
		input,errormsg=loadstring(input)
		if input then
			script=input()
			input=nil
			if script then
				entry={}
				entry.modification=modification
				entry.used=timestamp
				entry.script=script
				bytecache[path]=entry
			end
		end
	end

	if script then
		response.headers.CONTENT_TYPE="text/html;charset=UTF-8"
		script(request,response,include,rootdir)
	else
		handleFileNotFound(request,response,errormsg)
	end
end

function handleRequest(request,response)
	if not request.path or request.path == "/" then
		request.path="/index.lua"
	end

	local path=wwwdir
	if defaultdomain then
		--vhost
		local host=request.headers.HOST
		if not host then
			host=defaultdomain
		else
			host=host:match("^[%d%a%.]+")
		end


		path=domains[host]
		request.host=host
		if not path then
			path=domains[defaultdomain]
			request.host=defaultdomain
			if not path then
			--	path=wwwdir (dangerous)
				handleFileNotFound(request,response)
				return
			end
		end
	end

	--try rewrite rules
	for _,rule in ipairs(rewriterules) do
		if rule(request) then
			break
		end
	end

	local rootdir=path
	path=path .. request.path

	local attr=lfs.attributes(path)
	if attr and attr.mode=="directory" then
		path=path .. "/index.lua"
		attr=lfs.attributes(path)
	end

	if attr and attr.mode=="file" then
		--file found
		--response.headers.DATE=printHttpDate(timestamp)

		local ext=path:match("%.([%a%.]+)$")
		local gzext=ext:match("%.(gz)$")
		if ext=="lua" then
			include(path,attr,request,response,rootdir)
		else
			--static files expire after the time since the last modification + 20 minutes
			response.headers.EXPIRES=printHttpDate(2*timestamp-attr.modification+2*24*60*60)
			response.headers.LAST_MODIFIED=printHttpDate(attr.modification)
			--response.headers.ACCEPT_RANGES="bytes"

			local modsince=parseHttpDate(request.headers.IF_MODIFIED_SINCE)
			if modsince and attr.modification-modsince<=0 then
				response.status=304
				response.statusmsg="Not Modified"
				response.headers.TRANSFER_ENCODING=nil
				response:sendHeaders()
				return
			end

			local mtype=mimetypes[ext]
			response.headers.CONTENT_TYPE=mtype or "application/octet"

			--support for html.gz js.gz ...
			if mtype and gzext and request.headers.ACCEPT_ENCODING
				and request.headers.ACCEPT_ENCODING:match("gzip") then
				response.headers.CONTENT_ENCODING="gzip"
			end

			--send file
			local range=nil
			if request.headers.RANGE then
				local r=request.headers.RANGE:match("bytes%s*=%s*(%d+)%s*%-")
				if r then
					range=tonumber(r)
				end
			end


			local fd=io.open(path,"r")
			if fd then
				response.headers.CONTENT_LENGTH=attr.size
				if range and range<attr.size then
					fd:seek("set",range)
					response.status=206
					response.statusmsg="Partial content"
					response.headers.CONTENT_LENGTH=attr.size-range
					response.headers.CONTENT_RANGE="bytes " .. range .. "-" .. attr.size-1 .. "/" .. attr.size
				end
				response:sendFile(fd)
				fd:close()
			else
				handleFileNotFound(request,response)
			end
		end
	else
		handleFileNotFound(request,response)
	end
end
