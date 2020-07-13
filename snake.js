const height = 25;
const width = 25;
let game;

const MOVE = {
    0: [0, -1],
    1: [-1, 0],
    2: [0, 1],
    3: [1, 0],
}

const CV_TYPE = {
    EMPTY: 0,
    SB_HEAD: 1,
    SB_BODY: 2,
    SB_TAIL: 3,
    FOOD: 4,
};

class Snake {
    body = [];
    constructor(x, y) {
        this.body.push({x: x, y: y, d: 0, type: CV_TYPE.SB_HEAD});
        this.body.push({ x: x, y: y + 1, d: 0, type: CV_TYPE.SB_BODY});
        this.body.push({ x: x, y: y + 2, d: 0, type: CV_TYPE.SB_TAIL});
    }

    head() {
        return this.body[0];
    }

    move(type, game) {
        let canvas = game.canvas;
        if(Math.abs(type - this.body[0].d) == 2) {
            type = this.body[0].d;
        }
        
        let move = MOVE[type];
        let x = this.body[0].x + move[0];
        let y = this.body[0].y + move[1];

        if(x < 0 || x >= width || y < 0 || y >= height ) {
            return false;
        }

        let target = canvas[y][x];
        if(target.type !== CV_TYPE.EMPTY && target.type !== CV_TYPE.FOOD) {
            return false;
        }
        
        if(target.type === CV_TYPE.FOOD) {
            game.food = undefined;
        } else {
            let tail = this.body[this.body.length - 1];
            canvas[tail.y][tail.x].type = CV_TYPE.EMPTY;
            this.body.pop();
            this.body[this.body.length - 1].type = CV_TYPE.SB_TAIL;
        }
        
        this.body[0].type = CV_TYPE.SB_BODY;
        target.type = CV_TYPE.SB_HEAD;
        this.body.unshift({x: x, y: y, d: type, type: CV_TYPE.SB_HEAD});

        return true;
    }

    render(canvas) {
        this.body.forEach((bodyNode) => {
            let node = canvas[bodyNode.y][bodyNode.x];
            node.obj.style.backgroundColor = "green";
        });
    }
};

class Game {
    canvas;
    snake;
    timerRef;
    lastFrame;
    moveType;
    food;

    constructor() {
        this.snake = new Snake(10, 10);

        let tbl = document.getElementById("canvas");

        let data = [];
        for (let i = 0; i < height; i++) {
            data.push([]);
            let tr = document.createElement("tr");
            for (let j = 0; j < width; j++) {
                let domNode = document.createElement("td");
                tr.appendChild(domNode);
                let node = {
                    obj: domNode,
                    type: 0,
                }
                data[i].push(node);
            }
            tbl.appendChild(tr);
        }
        this.canvas = data;
        this.snake.render(this.canvas)
        
        this.lastFrame = undefined;
        this.moveType = 0;
    }

    moveSnake() {
        let ret = this.snake.move(this.moveType, this);
        if(ret === false){
            this.gameOver();
        }
    }

    gameOver() {
        window.cancelAnimationFrame(this.timerRef);
        this.timerRef = undefined;
    }

    setFood() {
        while(this.food == undefined) {
            let x = Math.floor(Math.random() * width);
            let y = Math.floor(Math.random() * height);
            let head = this.snake.head();
            let dx = Math.pow(head.x - x, 2);
            let dy = Math.pow(head.y - y, 2);
            if(dx + dy > 10 && this.canvas[y][x].type === CV_TYPE.EMPTY){
                this.canvas[y][x].type = CV_TYPE.FOOD;
                this.food = [x, y];
                break;
            }
        }
    }

    onRender() {
        for (let i = 0; i < height; i++) {
            for (let j = 0; j < width; j++) {
                this.canvas[i][j].obj.style.backgroundColor = "bisque";
            }
        }
        this.snake.render(this.canvas);
        if(this.food) {
            this.canvas[this.food[1]][this.food[0]].obj.style.backgroundColor = "blue";
        }
    }

    onFrame() {
        this.setFood();
        this.moveSnake();
    }

    onTimer(now) {
        if(this.lastFrame == undefined){
            this.lastFrame = now;
        }
        let dt = now - this.lastFrame;
        if(dt > 300.0) {
            this.onFrame();
            this.onRender();
            this.lastFrame = now;
        }
        if(this.timerRef) {
            this.timerRef = window.requestAnimationFrame((now) => {
                this.onTimer(now);
            })
        }
    }

    run() {
        this.timerRef = window.requestAnimationFrame((now) => {
            this.onTimer(now);
        })
    }
}

function init() {
    game = new Game();
    game.run();
}

init();

