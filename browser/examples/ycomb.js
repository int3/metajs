var Y = function (F) {
  return (function (x) {
    return F(function (y) { return x(x)(y); });
  })(function (x) {
    return F(function (y) { return x(x)(y); });
  });
};

var factorial = function (self) {
  return function(n) {
    return n === 0 ? 1 : n * self(n-1);
  };
};

var result;
console.log(result = Y(factorial)(4));
