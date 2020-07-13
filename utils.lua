local lsocket = require "lsocket"
local SDL = require "SDL"
local json = require "rxi-json-lua"

local Animation = {}
Animation.__index = Animation

function Animation.new(texture_seq, fps)
    local o = {
        seq = texture_seq,
        n = #texture_seq,
        fps = fps
    }
    return setmetatable(o, Animation)
end

function Animation:get_texture(tick)
    local index = math.floor(tick * self.fps / 1000) % self.n
    return self.seq[index + 1]
end

local MAX_CONNECT = 10
local Connection = {}
Connection.__index = Connection

function Connection.new(addr, port)
    local o =
        setmetatable(
        {
            addr = addr,
            port = port,
            buf = ""
        },
        Connection
    )

    local fd, err = lsocket.connect(addr, port)
    if fd == nil then
        error(err)
    end
    o.sock = fd
    o:waiting(0)
    return o
end

function Connection:waiting(connect_time)
    local rr, rw = lsocket.select(nil, {self.sock}, 0)
    if not rr or not rw or next(rw) == nil then
        connect_time = connect_time + 1
        if connect_time < CONNECT_TIMEOUT then
            SDL.delay(100)
            self:waiting(connect_time)
        else
            error("connect reach max times")
        end
    else
        local ok, err = self.sock:status()
        if not ok then
            error("connect status err: " .. tostring(err))
        end
    end
end

function Connection:process(buf, cb)
    if buf == "" then
        return false
    end
    local ok, pack, n = pcall(string.unpack, "<s2", buf)
    if not ok then
        return false
    end
    local package = json.decode(pack)
    cb(package)
    return true, n
end

function Connection:read_package(cb)
    while true do
        local succ, opt = self:process(self.buf, cb)
        if succ then
            local n = opt
            self.buf = self.buf:sub(n)
        else
            local rr = lsocket.select({self.sock}, 0)
            if not rr or next(rr) == nil then
                return
            end
            local p, err = self.sock:recv()
            if not p then
                error(err)
                return
            end
            self.buf = self.buf .. p
        end
    end
end

function Connection:send_package(package)
    local body = json.encode(package)
    self.sock:send(string.pack("<H", #body) .. body)
end

local M = {
    Animation = Animation,
    Connection = Connection
}
return M
