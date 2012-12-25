if (true) {
  console.log("True");
}
else {
  console.log("False");
}

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
