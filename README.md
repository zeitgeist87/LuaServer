LuaServer
======

A small self contained webserver written entirely in Lua. It supports
fast dynamically generated pages, which can be scripted in Lua. It has
only a few dependencies and is ideal for embedded devices like routers running
OpenWRT. It uses Lua coroutines to handle multiple connections at once and
runs on Lua5.1, Lua5.2 and LuaJIT.

## Dependencies

* [LuaSocket](http://w3.impa.br/~diego/software/luasocket/)
* [LuaSec](https://github.com/brunoos/luasec)
* [LuaFilesystem](https://github.com/keplerproject/luafilesystem)

## Features

* Simple in memory object db
* Cookies
* Sessions
* Dynamic pages
* Cache
* Support for file uploads
* Support for range requests
* HTTPS
* Logging
* URL rewriting

## Usage

Installation on OpenWRT:

```
opkg update
opkg install lua luafilesystem luasec luasocket unzip

wget https://github.com/zeitgeist87/LuaServer/archive/master.zip
unzip master.zip
cd LuaServer*
lua server.lua
```

Installation on Arch Linux:

```
sudo pacman -S lua lua-sec lua-socket lua-filesystem

git clone https://github.com/zeitgeist87/LuaServer.git
cd LuaServer
lua server.lua
```


