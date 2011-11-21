module(..., package.seeall)
--global vars
local dbtable={}

--hack to get lua to call a function on shutdown
local shutdownproxy = newproxy(true) -- create proxy object with new metatable
assert(type(shutdownproxy) == 'userdata')
getmetatable(shutdownproxy).__gc = function() syncIfChanged() end 
--global vars

function serializeInit(o,f,n,t)
	if type(o) == "table" and not t[o] then
		t[o]="v" .. n
		n=n+1
		f:write("local " .. t[o] .. "={}\n")
		for k,v in pairs(o) do
			n=serializeInit(v,f,n,t)
		end
	end
	return n
end

function serializeSimple(o,f,t)
	if type(o) == "number" then
		f:write(tostring(o))
	elseif type(o) == "string" then
		f:write(string.format("%q", o))
	elseif type(o) == "table" then
		f:write(t[o])
	end
end

function serialize (o,f)
	if type(o) == "table" then
		local t={}
		serializeInit(o,f,0,t)
		for table,name in pairs(t) do
			for k,v in pairs(table) do
				f:write(name)
				f:write("[")
				serializeSimple(k,f,t)
				f:write("]=")
				serializeSimple(v,f,t)
				f:write("\n")
			end
		end
		f:write("return " .. t[o])
	else
		f:write("return ")
		serializeSimple(o,f)
	end
end


local bchanged=false
function put(name,object)
	dbtable[name]=object
	bchanged=true
end

function changed()
	bchanged=true
end

function sync()
	local fd=io.open(dbfile,"w")
	serialize(dbtable,fd)
	fd:close()
end

function syncIfChanged()
	if bchanged then
		sync()
		changed=false
	end
end

function load()
	local data=loadfile(dbfile)
	if not data then
		dbtable={}
		return
	end
	setfenv(data,{})
	data=data()
	if type(data)=="table" then
		dbtable=data
	else
		dbtable={}
	end
	return
end

function get(name)
	return dbtable[name]
end
