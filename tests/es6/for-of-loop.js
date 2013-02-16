var gen = function*() {
  yield 1;
  yield 5;
};

for (var v of gen()) {
  console.log(v);
}
