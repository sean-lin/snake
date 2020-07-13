#!/bin/env python3

import os.path
import pathlib
from select import epoll
import socket
import select
import struct
import random
import json
import time
from collections import namedtuple

PORT = 15320


MOVE = {0: (0, -1), 1: (1, 0), 2: (0, 1), 3: (-1, 0)}


class CV_TYPE:
    ERROR = -1
    EMPTY = 0
    SB_HEAD = 1
    SB_BODY = 2
    SB_TAIL = 3
    FOOD = 4
    SB_TURN_LEFT = 5
    SB_TURN_RIGHT = 6


def need_login(func):
    def f(self, package):
        if self.logined:
            return func(self, package)
        else:
            self.on_error("need login")

    return f


class Body(object):
    def __init__(self, x, y, d, type_):
        self.x = x
        self.y = y
        self.d = d
        self.type = type_

    def info(self):
        return {i: getattr(self, i) for i in ["x", "y", "d", "type"]}


class FileDB(object):
    def __init__(self, path):
        self.path = path
        pathlib.Path(self.path).mkdir(parents=True, exist_ok=True)

    def load(self, name):
        path = os.path.join(self.path, name)
        if not os.path.exists(path):
            return None
        with open(path, "r") as f:
            return json.load(f)

    def save(self, name, data):
        path = os.path.join(self.path, name)
        with open(path, "w+") as f:
            json.dump(data, f)


class Player(object):
    def __init__(self, game, conn):
        self.game = game
        self.conn = conn
        self.peername = conn.getpeername()
        self.score = 0
        self.total_score = 0
        self.buf = b""
        self.logined = False
        self.name = "not login"
        self.is_error = False
        self.direction = 0
        self.gameover = False
        self.body = []
        self.restart()

    def head(self):
        return self.body[0]

    def restart(self):
        self.body = []
        self.gameover = False
        self.direction = 0
        self.score = 0
        x, y = self.game.alloc()
        if x == None:
            self.on_error("allocate pos failed")
        else:
            self.body = [
                Body(x, y, 0, CV_TYPE.SB_HEAD),
                Body(x, y + 1, 0, CV_TYPE.SB_BODY),
                Body(x, y + 2, 0, CV_TYPE.SB_TAIL),
            ]

    def move(self):
        if self.gameover:
            return False

        move = MOVE[self.direction]
        x = self.body[0].x + move[0]
        y = self.body[0].y + move[1]

        target = self.game.check_move(x, y)
        if target == CV_TYPE.FOOD:
            self.game.eat(x, y)
            self.score += 1 
            self.total_score += 1
        elif target == CV_TYPE.EMPTY:
            del self.body[-1]
            self.body[-1].type = CV_TYPE.SB_TAIL
            self.body[-1].d = self.body[-2].d
        else:
            self.gameover = True
            return False

        last_direction = self.body[0].d
        if self.direction == last_direction:
            self.body[0].type = CV_TYPE.SB_BODY
        else:
            if (self.direction - last_direction) % 4 == 1:
                self.body[0].type = CV_TYPE.SB_TURN_RIGHT
            else:
                self.body[0].type = CV_TYPE.SB_TURN_LEFT
        self.body.insert(0, Body(x, y, self.direction, CV_TYPE.SB_HEAD))
        return True

    def hit(self, x, y):
        for i in self.body:
            if x == i.x and y == i.y:
                return i.type
        return CV_TYPE.EMPTY

    def on_data(self):
        data = self.conn.recv(1024)
        if data:
            self.buf += data
            self.buf = self.process(self.buf)
            return not self.is_error
        else:
            self.conn.close()
            return False

    def process(self, data):
        while len(data) > 2:
            package_len, = struct.unpack("<H", data[:2])
            if len(data) >= package_len + 2:
                package = json.loads(data[2 : package_len + 2])
                self.on_package(package)
                data = data[package_len + 2 :]
        return data

    def get_info(self):
        info = {
            "role_id": self.name,
            "gameover": self.gameover,
            "score": self.score,
            "total_score": self.total_score,
            "body": [i.info() for i in self.body],
        }
        return info

    def on_package(self, package):
        print("get package:", package)
        cmd = package["cmd"]
        func = getattr(self, "handle_" + cmd)
        if func:
            func(package)
        else:
            pass

    def send_package(self, package):
        body = json.dumps(package).encode("utf-8")
        head = struct.pack("<H", len(body))
        self.conn.send(head)
        self.conn.send(body)

    def offline(self):
        if self.logined:
            self.game.save(self.name, {"total_score": self.total_score})
        self.conn.close()

    def on_error(self, err):
        print("player %s err: %s" % (self.name, err))
        self.is_error = True

    def handle_login(self, package):
        if self.logined:
            self.on_error("always logined")
            return
        if self.game.check_logined(package['name']):
            self.on_error("conflicted")
            return
        self.name = package["name"]
        data = self.game.load(self.name)
        if data:
            self.total_score = data["total_score"]
        self.logined = True
        game_info = self.game.get_game_info()
        game_info["role_id"] = self.name
        self.send_package(game_info)
        self.restart()

    @need_login
    def handle_restart(self, package):
        self.restart()

    @need_login
    def handle_move(self, package):
        op = package["op"]
        if abs(op - self.direction) == 2:
            return
        self.direction = op


class Game(object):
    def __init__(self):
        self.w = 20
        self.h = 20
        self.fps = 2
        self.players = {}
        self.snake = None
        self.food = None
        self.db = FileDB("db")

        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("", PORT))
        sock.listen(5)
        sock.setblocking(0)
        self.sock = sock

    def load(self, name):
        return self.db.load(name)

    def save(self, name, data):
        self.db.save(name, data)

    def on_logic(self):
        self.snake.move()

    def alloc(self):
        count = 0
        while count < 20:
            x = random.randrange(5, self.w - 5)
            y = random.randrange(5, self.h - 5)
            body = [(x, y), (x, y - 1), (x, y - 2)]
            if all(self.check_body(self.players[i], body) for i in self.players):
                return x, y
            count += 1
        return None, None

    def check_body(self, player, body):
        for b in body:
            if player.hit(b[0], b[1]) != CV_TYPE.EMPTY:
                return False
        return True

    def update_food(self):
        count = 0
        while not self.food and count < 20:
            x = random.randrange(0, self.w)
            y = random.randrange(0, self.h)
            if all(self.check_food(self.players[i], x, y) for i in self.players):
                self.food = (x, y)
                self.sync_food()
            count += 1

    def check_food(self, player, x, y):
        if player.hit(x, y) == CV_TYPE.EMPTY:
            dx = player.head().x - x
            dy = player.head().y - y
            if dx * dx + dy * dy > 9:
                return True
        return False

    def sync_food(self):
        package = {"cmd": "sync_food"}
        if self.food:
            package["x"] = self.food[0]
            package["y"] = self.food[1]
        for i in self.players:
            self.players[i].send_package(package)

    def check_logined(self, name):
        return any(i.name == name for i in self.players.values())

    def check_move(self, x, y):
        if x < 0 or x >= self.w or y < 0 or y >= self.h:
            return CV_TYPE.ERROR

        if self.food and self.food[0] == x and self.food[1] == y:
            return CV_TYPE.FOOD

        for i in self.players:
            type_ = self.players[i].hit(x, y)
            if type_ != CV_TYPE.EMPTY:
                return type_

        return CV_TYPE.EMPTY

    def eat(self, x, y):
        if self.food[0] == x and self.food[1] == y:
            self.food = None
            self.sync_food()
            return True
        return False

    def update(self):
        self.update_food()
        for player in self.players.values():
            if player.logined and not player.gameover:
                player.move()
                info = player.get_info()
                info["cmd"] = "sync_snake"
                self.send_all(info)

    def send_all(self, package):
        [i.send_package(package) for i in self.players.values() if i.logined]

    def player_online(self, conn):
        conn.setblocking(0)
        self.poll.register(conn.fileno(), select.POLLIN)
        player = Player(self, conn)
        self.players[conn.fileno()] = player

    def player_offline(self, fileno):
        self.poll.unregister(fileno)
        self.players[fileno].offline()
        del self.players[fileno]

    def get_game_info(self):
        info = {
            "cmd": "init",
            "w": self.w,
            "h": self.h,
            "snakes": [self.players[i].get_info() for i in self.players],
        }
        if self.food:
            info["food"] = {"x": self.food[0], "y": self.food[1]}

        return info

    def loop_poll(self):
        max_timeout = 1 / self.fps
        passed = 0
        while True:
            start = time.time()
            events = self.poll.poll(max(max_timeout - passed, 0))

            for fileno, event in events:
                if fileno == self.sock.fileno():
                    conn, addr = self.sock.accept()
                    print("accpet from " + str(addr))
                    self.player_online(conn)

                elif event & select.EPOLLHUP:
                    print("lost connection " + str(self.players[fileno].peername))
                    self.player_offline(fileno)

                elif event & select.POLLIN:
                    if not self.players[fileno].on_data():
                        print("close connection" + str(self.players[fileno].peername))
                        self.player_offline(fileno)

            if passed + (time.time() - start) >= max_timeout:
                self.update()
                passed = passed + (time.time() - start) - max_timeout
            else:
                passed += time.time() - start

    def loop(self):
        with select.epoll() as poll:
            self.poll = poll
            poll.register(self.sock.fileno(), select.EPOLLIN)
            self.loop_poll()


def main():
    game = Game()
    game.loop()


if __name__ == "__main__":
    main()
