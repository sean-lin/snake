local SDL = require "SDL"

function init()
	local ret, err = SDL.init {SDL.flags.Video}
	if not ret then
		error(err)
	end
end

local End = {
	{1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1},
	{1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1},
	{1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1},
	{1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1},
	{1, 1, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 1, 1},
}
local CV_TYPE = {
	ERROR = -1,
	EMPTY = 0,
	SB_HEAD = 1,
	SB_BODY = 2,
	SB_TAIL = 3,
	FOOD = 4
}

local MOVE = {
	[0] = {0, -1},
	[1] = {-1, 0},
	[2] = {0, 1},
	[3] = {1, 0}
}

local KEY_MAP = {
	[SDL.key.Up] = 0,
	[SDL.key.Left] = 1,
	[SDL.key.Down] = 2,
	[SDL.key.Right] = 3
}

local Snake = {}
local Game = {}

Game.__index = Game
function Game.new()
	local o = {
		w = 20,
		h = 20,
		size = 30,
		snake = Snake.new(10, 10),
		fps = 2,
		running = false,
		gameover = false,
		food = nil
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
	return setmetatable(o, Game)
end

function Game:loop()
	local frame_time = 1000.0 / self.fps
	self.running = true

	while self.running do
		local ticks = SDL.getTicks()
		self:on_update()
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

function Game:dot(color, x, y)
	local size = self.width / self.w
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

function Game:render_food()
	if self.food then
		self:dot(0x800000, self.food.x, self.food.y)
	end
end

function Game:on_render()
	self:clean_canvas()
	self:render_food()
	self.snake:on_render(self)
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
	self.snake = Snake.new(10, 10)
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

function Game:on_update()
	self:update_input()
	self:update_logic()
	self:on_render()
end

Snake.__index = Snake
function Snake.new(x, y)
	local o = {
		body = {
			{x = x, y = y, d = 0, type = CV_TYPE.SB_HEAD},
			{x = x, y = y + 1, d = 0, type = CV_TYPE.SB_BODY},
			{x = x, y = y + 2, d = 0, type = CV_TYPE.SB_TAIL}
		},
		direction = 0
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
	else
		return false
	end

	self.body[1].type = CV_TYPE.SB_BODY
	table.insert(self.body, 1, {x = x, y = y, d = type, type = CV_TYPE.SB_HEAD})
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

function Snake:on_render(game)
	for i, v in ipairs(self.body) do
		game:dot(0x008000, v.x, v.y)
	end
end

function main()
	init()
	local game = Game.new()
	game:loop()
end

main()
