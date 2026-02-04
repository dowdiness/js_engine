// 100万個のオブジェクトを作っては捨てる
for (var i = 0; i < 1000000; i++) {
  var temp = { id: i, data: "junk" }; // ここでメモリ確保
  // ループが回るとtempは参照されなくなり、ゴミになる
}
console.log("Survived!");
