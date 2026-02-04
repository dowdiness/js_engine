// Array iteration
for (const x of [1, 2, 3]) console.log(x);

// String iteration
for (const c of "abc") console.log(c);

// Array iterator methods
[1, 2, 3].keys();    // Iterator: 0, 1, 2
[1, 2, 3].values();  // Iterator: 1, 2, 3
[1, 2, 3].entries(); // Iterator: [0,1], [1,2], [2,3]

// Custom iterator (if implemented)
const obj = {
  [Symbol.iterator]() {
    let i = 0;
    return {
      next() {
        return i < 3 ? {value: i++, done: false} : {done: true};
      }
    };
  }
};
for (const x of obj) console.log(x); // 0, 1, 2
