var gen = function*() {
  for (var i = 0; i < 3; i++) {
    var inner = innerGen(i + 1);
    yield* inner;
  }
};

var innerGen = function*(j) {
  for (var i = 0; i < 3; i++)
    yield i * j;
};

for (var n of gen()) {
  console.log(n);
}
