/**
 * A deterministic ASCII dungeon with a BFS route from S to G.
 */
const WIDTH = 29;
const HEIGHT = 15;
const SEED_LABEL = "moonbit-42";
const START_X = 1;
const START_Y = 1;
const GOAL_X = WIDTH - 2;
const GOAL_Y = HEIGHT - 2;
const DIRECTIONS = [
  { dx: 0, dy: -2 },
  { dx: 2, dy: 0 },
  { dx: 0, dy: 2 },
  { dx: -2, dy: 0 },
];
const CARDINAL_DIRECTIONS = [
  { dx: 0, dy: -1 },
  { dx: 1, dy: 0 },
  { dx: 0, dy: 1 },
  { dx: -1, dy: 0 },
];

function seedFromLabel(label) {
  let seed = 2166136261;

  for (let i = 0; i < label.length; i++) {
    seed = Math.imul(seed ^ label.charCodeAt(i), 16777619) >>> 0;
  }

  return seed;
}

let randomState = seedFromLabel(SEED_LABEL);

function nextUint32() {
  randomState ^= randomState << 13;
  randomState ^= randomState >>> 17;
  randomState ^= randomState << 5;
  return randomState >>> 0;
}

function makeGrid() {
  const grid = [];

  for (let y = 0; y < HEIGHT; y++) {
    const row = [];
    for (let x = 0; x < WIDTH; x++) {
      row.push("#");
    }
    grid.push(row);
  }

  return grid;
}

function carveMaze() {
  const grid = makeGrid();
  const stack = [{ x: START_X, y: START_Y }];
  grid[START_Y][START_X] = " ";

  while (stack.length > 0) {
    const current = stack[stack.length - 1];
    const candidates = [];

    for (let i = 0; i < DIRECTIONS.length; i++) {
      const direction = DIRECTIONS[i];
      const nextX = current.x + direction.dx;
      const nextY = current.y + direction.dy;

      if (
        nextX > 0 &&
        nextX < WIDTH - 1 &&
        nextY > 0 &&
        nextY < HEIGHT - 1 &&
        grid[nextY][nextX] === "#"
      ) {
        candidates.push({
          x: nextX,
          y: nextY,
          dx: direction.dx,
          dy: direction.dy,
        });
      }
    }

    if (candidates.length === 0) {
      stack.pop();
      continue;
    }

    const chosen = candidates[nextUint32() % candidates.length];
    grid[current.y + chosen.dy / 2][current.x + chosen.dx / 2] = " ";
    grid[chosen.y][chosen.x] = " ";
    stack.push({ x: chosen.x, y: chosen.y });
  }

  return grid;
}

function makePreviousGrid() {
  const previous = [];

  for (let y = 0; y < HEIGHT; y++) {
    const row = [];
    for (let x = 0; x < WIDTH; x++) {
      row.push(null);
    }
    previous.push(row);
  }

  return previous;
}

function findRoute(grid) {
  const previous = makePreviousGrid();
  const queue = [{ x: START_X, y: START_Y }];
  let queueHead = 0;
  previous[START_Y][START_X] = { x: START_X, y: START_Y };

  while (queueHead < queue.length) {
    const current = queue[queueHead];
    queueHead++;

    if (current.x === GOAL_X && current.y === GOAL_Y) {
      break;
    }

    for (let i = 0; i < CARDINAL_DIRECTIONS.length; i++) {
      const direction = CARDINAL_DIRECTIONS[i];
      const nextX = current.x + direction.dx;
      const nextY = current.y + direction.dy;

      if (
        nextX >= 0 &&
        nextX < WIDTH &&
        nextY >= 0 &&
        nextY < HEIGHT &&
        grid[nextY][nextX] !== "#" &&
        previous[nextY][nextX] === null
      ) {
        previous[nextY][nextX] = { x: current.x, y: current.y };
        queue.push({ x: nextX, y: nextY });
      }
    }
  }

  if (previous[GOAL_Y][GOAL_X] === null) {
    throw new Error("Dungeon goal is unreachable");
  }

  const route = [];
  let current = { x: GOAL_X, y: GOAL_Y };

  while (current.x !== START_X || current.y !== START_Y) {
    route.push(current);
    current = previous[current.y][current.x];
  }
  route.push({ x: START_X, y: START_Y });
  route.reverse();
  return route;
}

function renderRoute(grid, route) {
  const rendered = [];

  for (let y = 0; y < HEIGHT; y++) {
    rendered.push(grid[y].slice());
  }

  for (let i = 1; i < route.length - 1; i++) {
    const point = route[i];
    rendered[point.y][point.x] = ".";
  }

  rendered[START_Y][START_X] = "S";
  rendered[GOAL_Y][GOAL_X] = "G";

  const lines = [];
  for (let y = 0; y < HEIGHT; y++) {
    lines.push(rendered[y].join(""));
  }
  return lines.join("\n");
}

const dungeon = carveMaze();
const route = findRoute(dungeon);

console.log("seed: " + SEED_LABEL);
console.log("path length: " + (route.length - 1));
console.log(renderRoute(dungeon, route));
