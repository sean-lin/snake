local Animation = {}
Animation.__index = Animation

function Animation.new(texture_seq, fps)
    local o = {
        seq = texture_seq,
        n = #texture_seq,
        fps = fps,
    }
    return setmetatable(o, Animation)
end

function Animation:get_texture(tick)
    local index = math.floor(tick * self.fps / 1000) % self.n
    return self.seq[index + 1]
end

local M = {
    Animation = Animation
}
return M