var a = 0;
var b = 1;
while (b < 100) {
  console.log(b);
  var temp = a + b;
  a = b;
  b = temp;
}
