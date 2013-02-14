if (true) {
  console.log("True");
}
else {
  console.log("False");
}

console.log(typeof foo === 'undefined' ? 'foo exists' : 'foo does not exist');

for (var i = 0; i < 10; i++) {
  console.log(i);
}

for (var i = 0; i < 10; i++) {
  console.log(i);
  if (i === 5) break;
}

console.log(i);

for (var i = 0; i < 10; i++) {
  console.log(i);
  if (i === 5) continue;
}

console.log(i);

var obj = { a: 1, b: 2, c: 3 };

for (var k in obj) {
  console.log(k, obj[k]);
}

var obj2 = { i: 0 }
for (obj2.i in obj) {
  console.log(obj2.i, obj[obj2.i]);
}

var rv = (function () {
  console.log("foo");
  return;
  console.log("should not be printed");
})();

console.log(rv);

rv = (function() {
  console.log("bar");
  return null;
  console.log("should not be printed");
})();

console.log(rv);

console.log("testing exceptions");

(function() {
  var e = "foo";
  try {
    (function() {
      throw new Error("hello world");
    })();
  }
  catch (e) {
    var catchVar = "hi";
    console.log(e);
    e = "blah";
    console.log(e);
  }
  finally {
    var finVar = "bye";
    console.log("finally");
  }
  console.log(e);
  console.log(catchVar);
  console.log(finVar);
})();

console.log("testing logical operators");

var falseFn = function() {
    console.log("falseFn");
    return false;
};

var trueFn = function() {
    console.log("trueFn");
    return true;
};

console.log('&&');
console.log(falseFn() && falseFn());
console.log('&&');
console.log(falseFn() && trueFn());
console.log('&&');
console.log(trueFn() && falseFn());
console.log('&&');
console.log(trueFn() && trueFn());

console.log('||');
console.log(falseFn() || falseFn());
console.log('||');
console.log(falseFn() || trueFn());
console.log('||');
console.log(trueFn() || falseFn());
console.log('||');
console.log(trueFn() || trueFn());

