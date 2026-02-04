function makeCounter() {
  var count = 0;
  return function() {
    count = count + 1;
    return count;
  };
}

var counter = makeCounter();
console.log(counter()); // 1
console.log(counter()); // 2
console.log(counter()); // 3
