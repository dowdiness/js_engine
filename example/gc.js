// Create and discard one million objects
for (var i = 0; i < 1000000; i++) {
  var temp = { id: i, data: "junk" }; // Allocate memory here
  // As the loop advances, temp is no longer referenced and becomes garbage
}
console.log("Survived!");
