const height = 25;
const width = 25;
let game;

const CV_TYPE = {
    EMPTY: 0,
    SB_HEAD: 1,
    SB_BODY: 2,
    SB_TAIL: 3,
};

class Snake {
    body = [];
    constructor(x, y) {
        this.body.push({x: x, y: y, d: 0, type: CV_TYPE.SB_HEAD});
        this.body.push({ x: x, y: y + 1, d: 0, type: CV_TYPE.SB_BODY});
        this.body.push({ x: x, y: y + 2, d: 0, type: CV_TYPE.SB_TAIL});
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
                }
                data[i].push(node);
            }
            tbl.appendChild(tr);
        }
        this.canvas = data;
        this.snake.render(this.canvas)
    }

    onRender() {
        for (let i = 0; i < height; i++) {
            for (let j = 0; j < width; j++) {
                this.canvas[i][j].obj.style.backgroundColor = "bisque";
            }
        }
        this.snake.render(this.canvas);
    }
}

function init() {
    game = new Game();
}

init();

