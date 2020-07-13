local SDL = require "SDL"
local image = require "SDL.image"
local font = require "SDL.ttf"

local utils = require "utils"
--local IP = "30.103.92.249"
local IP = "127.0.0.1"

function init()
	local ret, err = SDL.init {SDL.flags.Video}
	if not ret then
		error(err)
	end

	local formats, ret, err = image.init {image.flags.PNG}

	if not formats[image.flags.PNG] then
		error(err)
	end
	local ret, err = font.init()
	if not ret then
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
	return utils.Animation.new(seq, fps)
end

local function make_text(rdr, f, txt)
	local s, err = f:renderUtf8(txt, "solid", 0xFFFFFF)
	if not s then
		error(err)
	end

	local t, err = rdr:createTextureFromSurface(s)
	if not t then
		error(err)
	end
	return t
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
function Game.new(name)
	local o =
		setmetatable(
		{
			w = 20,
			h = 20,
			size = 20,
			logic_fps = 2,
			fps = 30,
			running = false,
			gameover = false,
			snake = {},
			food = nil,
			name = name,
			res = {
				apple = nil,
				score_bar = nil
			}
		},
		Game
	)

	local conn = utils.Connection.new(IP, 15320)
	o.conn = conn
	o:send_package({cmd = "login", name = o.name})

	o.width = o.w * o.size
	o.height = o.h * o.size + o.size -- for bar
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

	local f, err = font.open("res/DejaVuSans.ttf", o.size)
	if not f then
		error(err)
	end
	o.font = f
	o.res.apple = ensure_texture(rdr, "apple")
	return o
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
		self:process_package()
		self:on_render(ticks)
		local dt = SDL.getTicks() - ticks
		if dt < frame_time then
			SDL.delay(math.floor(frame_time - dt))
		end
	end
end

function Game:send_package(package)
	self.conn:send_package(package)
end

function Game:process_package()
	self.conn:read_package(
		function(package)
			local cmd = package["cmd"]
			local func = self["handle_" .. cmd]
			if func then
				func(self, package)
			end
		end
	)
end

function Game:handle_sync_food(package)
	if package.x and package.y then
		self.food = {x = package.x, y = package.y}
	else
		self.food = nil
	end
end

function Game:handle_init(package)
	self.food = package.food
	self.role_id = package.role_id
	self.snakes = {}
	for i, v in ipairs(package.snakes) do
		self.snakes[v.role_id] = Snake.new(self, v.body)
		self.snakes[v.role_id].score = v.score
		self.snakes[v.role_id].total_score = v.total_score
	end
	self:update_bar_texture()
end

function Game:handle_sync_snake(package)
	local role_id = package.role_id
	local snake = self.snake[role_id]
	if snake then
		snake:update_body(package.body)
	else
		snake = Snake.new(self, package.body)
		self.snakes[role_id] = snake
	end
	if role_id == self.role_id then
		self.gameover = package.gameover
		if snake.score ~= package.score then
			snake.score = package.score
			snake.total_score = package.total_score
			self:update_bar_texture()
		end
	end
end

function Game:update_bar_texture()
	local snake = self.snakes[self.role_id]
	local txt = string.format("score: %d  total score: %d", snake.score, snake.total_score)
	self.res.score_bar = make_text(self.rdr, self.font, txt)
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
	self.rdr:setDrawColor(0xFF8080)
	self.rdr:fillRect(
		{
			x = 0,
			y = self.height - self.size,
			w = self.width,
			h = self.size
		}
	)
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

function Game:render_bar()
	if self.res.score_bar then
		local _, _, w, _ = self.res.score_bar:query()
		self.rdr:copy(
			self.res.score_bar,
			nil,
			{
				x = 0,
				y = self.height - self.size,
				w = w,
				h = self.size
			}
		)
	end
end

function Game:on_render(tick)
	self:clean_canvas()
	self:render_food()
	for _, snake in pairs(self.snakes) do
		snake:on_render(self, tick)
	end
	if self.gameover then
		for y, l in ipairs(End) do
			for x, v in ipairs(l) do
				if v == 1 then
					self:dot(0x000080, x + 1, y + 3)
				end
			end
		end
	end
	self:render_bar()
	self.rdr:present()
end

function Game:start()
	self.snakes = {}
	self.role_id = nil
	self.food = nil
	self.gameover = false
end

function Game:restart()
	self:send_package(
		{
			cmd = "restart"
		}
	)
end

function Game:update_input()
	for e in SDL.pollEvent() do
		if e.type == SDL.event.Quit then
			self.running = false
		elseif e.type == SDL.event.KeyDown then
			local op = KEY_MAP[e.keysym.sym]
			if op and self.role_id then
				self.op = op
			end
			if e.keysym.sym == SDL.key.r then
				self:restart()
			end
		end
	end
end

function Game:update_logic()
	if self.op then
		self:send_package(
			{
				cmd = "move",
				op = self.op
			}
		)
		self.op = nil
	end
end

Snake.__index = Snake
function Snake.new(game, body)
	local o = {
		body = body,
		res = {
			[CV_TYPE.SB_BODY] = ensure_texture(game.rdr, "snakebody"),
			[CV_TYPE.SB_HEAD] = ensure_animation(game.rdr, {"snakehead_0", "snakehead_1"}, 4),
			[CV_TYPE.SB_TAIL] = ensure_animation(game.rdr, {"snaketail_0", "snaketail_1", "snaketail_2"}, 6),
			[CV_TYPE.SB_TURN_LEFT] = ensure_texture(game.rdr, "snaketurn")
		}
	}

	return setmetatable(o, Snake)
end

function Snake:update_body(body)
	self.body = body
end

function Snake:on_render(game, tick)
	for i, v in ipairs(self.body) do
		local flip = SDL.rendererFlip.None
		local res = self.res[v.type]

		if v.type == CV_TYPE.SB_TURN_RIGHT then
			res = self.res[CV_TYPE.SB_TURN_LEFT]
			flip = SDL.rendererFlip.Horizontal
		end
		if getmetatable(res) == utils.Animation then
			res = res:get_texture(tick)
		end
		game:draw(res, v.x, v.y, v.d * 90, flip)
	end
end

function main()
	local name = arg[1] or "player"
	init()
	local game = Game.new(name)
	game:loop()
end

main()
