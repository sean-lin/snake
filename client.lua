local SDL = require "SDL"
local image = require "SDL.image"
local ani = require "ani"

function init()
	local ret, err = SDL.init {SDL.flags.Video}
	if not ret then
		error(err)
	end

	local formats, ret, err = image.init {image.flags.PNG}

	if not formats[image.flags.PNG] then
		error(err)
	end
end

local function ensure_texture(rdr, filename)
	filename = "res/" .. filename .. ".png"
	local img, ret = image.load(filename)
	if not img then
		error(err)
	end
	return rdr:createTextureFromSurface(img)
end

local function ensure_animation(rdr, filenames, fps)
	local seq = {}
	for i, f in ipairs(filenames) do
		seq[i] = ensure_texture(rdr, f)
	end
	return ani.Animation.new(seq, fps)
end

local End = {
	{1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1},
	{1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1},
	{1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1},
	{1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1},
	{1, 1, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 1, 1}
}
local CV_TYPE = {
	ERROR = -1,
	EMPTY = 0,
	SB_HEAD = 1,
	SB_BODY = 2,
	SB_TAIL = 3,
	FOOD = 4,
	SB_TURN_LEFT = 5,
	SB_TURN_RIGHT = 6
}

local MOVE = {
	[0] = {0, -1},
	[1] = {1, 0},
	[2] = {0, 1},
	[3] = {-1, 0}
}

local KEY_MAP = {
	[SDL.key.Up] = 0,
	[SDL.key.Right] = 1,
	[SDL.key.Down] = 2,
	[SDL.key.Left] = 3
}

local Snake = {}
local Game = {}

Game.__index = Game
function Game.new()
	local o = {
		w = 20,
		h = 20,
		size = 30,
		logic_fps = 2,
		fps = 30,
		running = false,
		gameover = false,
		snake = nil,
		food = nil,
		res = {}
	}

	o.width = o.w * o.size
	o.height = o.h * o.size
	local win, err =
		SDL.createWindow {
		title = "GREEDY SNAKE",
		width = o.width,
		height = o.height,
		flags = {}
	}
	if not win then
		error(err)
	end
	o.win = win

	local rdr, err = SDL.createRenderer(win, 0, 0)
	if not rdr then
		error(err)
	end
	o.rdr = rdr

	o.res.apple = ensure_texture(rdr, "apple")
	return setmetatable(o, Game)
end

function Game:loop()
	self:start()
	local frame_time = 1000.0 / self.fps
	local rate = self.fps / self.logic_fps
	local frame_count = 0
	self.running = true

	while self.running do
		frame_count = frame_count + 1
		local ticks = SDL.getTicks()
		if frame_count == rate then
			frame_count = 0
			self:update_input()
			self:update_logic()
		end
		self:on_render(ticks)
		local dt = SDL.getTicks() - ticks
		if dt < frame_time then
			SDL.delay(math.floor(frame_time - dt))
		end
	end
end

function Game:check_move(x, y)
	if x < 0 or x >= self.w or y < 0 or y >= self.h then
		return CV_TYPE.ERROR
	end

	if self.food and self.food.x == x and self.food.y == y then
		return CV_TYPE.FOOD
	end

	local type = self.snake:hit(x, y)
	if type ~= CV_TYPE.EMPTY then
		return type
	end

	return CV_TYPE.EMPTY
end

function Game:eat(x, y)
	if self.food and self.food.x == x and self.food.y == y then
		self.food = nil
		return true
	end
	return false
end

function Game:clean_canvas()
	self.rdr:clear()
	self.rdr:setDrawColor(0xFFE4C4)
	self.rdr:fillRect(
		{
			x = 0,
			y = 0,
			w = self.width,
			h = self.height
		}
	)
end

function Game:update_food()
	while not self.food do
		local x = math.floor(math.random() * self.w)
		local y = math.floor(math.random() * self.h)
		if self.snake:hit(x, y) == CV_TYPE.EMPTY then
			local dx = self.snake:head().x - x
			local dy = self.snake:head().y - y
			if dx * dx + dy * dy > 9 then
				self.food = {x = x, y = y}
			end
		end
	end
end

function Game:dot(color, x, y)
	local size = self.size
	self.rdr:setDrawColor(color)
	self.rdr:fillRect(
		{
			x = x * size,
			y = y * size,
			w = size,
			h = size
		}
	)
end

function Game:draw(texture, x, y, angle, flip)
	local size = self.size
	self.rdr:copyEx(
		{
			texture = texture,
			source = nil,
			destination = {
				x = x * size,
				y = y * size,
				w = size,
				h = size
			},
			center = nil,
			angle = angle,
			flip = flip
		}
	)
end

function Game:render_food()
	if self.food then
		self:draw(self.res.apple, self.food.x, self.food.y)
	end
end

function Game:on_render(tick)
	self:clean_canvas()
	self:render_food()
	self.snake:on_render(self, tick)
	if self.gameover then
		for y, l in ipairs(End) do
			for x, v in ipairs(l) do
				if v == 1 then
					self:dot(0x000080, x + 1, y + 3)
				end
			end
		end
	end
	self.rdr:present()
end

function Game:start()
	self.snake = Snake.new(self, 10, 10)
	self.food = nil
	self.gameover = false
end

function Game:update_input()
	for e in SDL.pollEvent() do
		if e.type == SDL.event.Quit then
			self.running = false
		elseif e.type == SDL.event.KeyDown then
			local op = KEY_MAP[e.keysym.sym]
			if op then
				self.op = op
			end
			if e.keysym.sym == SDL.key.r then
				self:start()
			end
		end
	end
end

function Game:update_logic()
	if self.gameover then
		return
	end
	self:update_food()

	if self.op then
		self.snake:set_direct(self.op)
		self.op = nil
	end

	if not self.snake:move(self) then
		self.gameover = true
	end
end

Snake.__index = Snake
function Snake.new(game, x, y)
	local o = {
		body = {
			{x = x, y = y, d = 0, type = CV_TYPE.SB_HEAD},
			{x = x, y = y + 1, d = 0, type = CV_TYPE.SB_BODY},
			{x = x, y = y + 2, d = 0, type = CV_TYPE.SB_TAIL}
		},
		direction = 0,
		res = {
			[CV_TYPE.SB_BODY] = ensure_texture(game.rdr, "snakebody"),
			[CV_TYPE.SB_HEAD] = ensure_animation(game.rdr, {"snakehead_0", "snakehead_1"}, 4),
			[CV_TYPE.SB_TAIL] = ensure_animation(game.rdr, {"snaketail_0", "snaketail_1", "snaketail_2"}, 6),
			[CV_TYPE.SB_TURN_LEFT] = ensure_texture(game.rdr, "snaketurn")
		}
	}

	return setmetatable(o, Snake)
end

function Snake:head()
	return self.body[1]
end

function Snake:move(game)
	local move = MOVE[self.direction]
	local x = self.body[1].x + move[1]
	local y = self.body[1].y + move[2]

	local target = game:check_move(x, y)
	if target == CV_TYPE.FOOD then
		game:eat(x, y)
	elseif target == CV_TYPE.EMPTY then
		self.body[#self.body] = nil
		self.body[#self.body].type = CV_TYPE.SB_TAIL
		self.body[#self.body].d = self.body[#self.body - 1].d
	else
		return false
	end

	local last_direction = self.body[1].d
	if self.direction == last_direction then
		self.body[1].type = CV_TYPE.SB_BODY
	else
		if (self.direction - last_direction) % 4 == 1 then
			self.body[1].type = CV_TYPE.SB_TURN_RIGHT
		else
			self.body[1].type = CV_TYPE.SB_TURN_LEFT
		end
	end
	table.insert(self.body, 1, {x = x, y = y, d = self.direction, type = CV_TYPE.SB_HEAD})
	return true
end

function Snake:set_direct(op)
	if math.abs(op - self.direction) == 2 then
		return
	end
	self.direction = op
end

function Snake:hit(x, y)
	for _i, v in ipairs(self.body) do
		if x == v.x and y == v.y then
			return v.type
		end
	end
	return CV_TYPE.EMPTY
end

function Snake:on_render(game, tick)
	for i, v in ipairs(self.body) do
		local flip = SDL.rendererFlip.None
		local res = self.res[v.type]

		if v.type == CV_TYPE.SB_TURN_RIGHT then
			res = self.res[CV_TYPE.SB_TURN_LEFT]
			flip = SDL.rendererFlip.Horizontal
		end
		if getmetatable(res) == ani.Animation then
			res = res:get_texture(tick)
		end
		game:draw(res, v.x, v.y, v.d * 90, flip)
	end
end

function main()
	init()
	local game = Game.new()
	game:loop()
end

main()
