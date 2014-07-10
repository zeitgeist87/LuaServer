local Config = {
	protocol = {http = true, https = false},
	wwwdir = "www",
	dbfile = "data/db/data.db",
	-- set to nil if you don't want vhosts
	defaultdomain = "example.com",
	usestatcache = true,

	buffersize = 4096,
	mimetypes = {
		["js.gz"] = "application/x-javascript",
		js = "application/x-javascript",
		htm = "text/html;charset=UTF-8",
		["htm.gz"] = "text/html;charset=UTF-8",
		html = "text/html;charset=UTF-8",
		["html.gz"] = "text/html;charset=UTF-8",
		txt = "text/plain;charset=UTF-8",
		css = "text/css",
		["css.gz"] = "text/css",
		jpg = "image/jpeg",
		jpeg = "image/jpeg",
		ogv = "video/ogg",
		ico = "image/vnd.microsoft.icon",
		png = "image/png"
	},

	httpsparams = {
		mode = "server",
		protocol = "tlsv1",
		key = "certs/server.pem",
		certificate = "certs/server.cert",
		verify = {},
		options = {"all", "no_sslv2"},
		ciphers = "ALL:!ADH:@STRENGTH",
	},

	httpport = 8080,
	httpsport = 8081,
	localtimeoffset = 2 * 60 * 60,
	sessiontimeout = 30 * 60,
	bytecachetimeout = 24 * 60 * 60,
	sockettimeout = 5 * 60,
	-- hard limit on uploads
	uploadlimit = 500 * 1024 * 1024,
	-- limit on the memory an upload can use
	-- (more is more efficient but uses more memory)
	uploadmemlimit = 1024 * 1024,
	rewriterules = {},
	logger = {
		stdout = true,
		file = "data/log/server.log",
		level = "debug"
	},
}

-- rewrite rules
local r = {}
r[#r + 1] = function(req)
	local year, month, day, id = req.path:match("^/(%d%d%d%d)/(%d%d)/(%d%d)/([%w%-_]+)")
	if year then
		id = id:gsub("%-", "_")
		req.path = "/article.lua"
		req.get.year = year
		req.get.month = month
		req.get.day = day
		req.get.id = id
		return true
	end
	return false
end
Config.rewriterules[Config.defaultdomain] = r
-- rewrite rules

return Config
