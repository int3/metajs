console.log("testing lexical scope");

function f(a) {
  var b = 2;
  globalVar = "glob";
  return function() {
    console.log(a);
    console.log(b);
  }
}

var g = f(1)

var a = -1;
var b = -2;

g();

console.log(b);
console.log(globalVar);

function Foo() {
  this.baz = 1;
}

Foo.prototype.bar = function() {
  console.log(this instanceof Foo);
  console.log(this === global);
  console.log(this === undefined);
}

console.log("testing `this` binding");

var foo = new Foo();
foo.bar();
var unbound = foo.bar;
unbound();

Number.prototype.bar = function() {
  console.log(typeof this);
}

var num = 1;
num.bar();

(function() {
  "use strict";
  console.log("testing strict mode");

  unbound();
  function Bar() { }

  Bar.prototype.bar = function() {
    console.log(this instanceof Foo);
    console.log(this === global);
    console.log(this === undefined);
  }

  var bar = new Bar();
  bar.bar();
  unbound = bar.bar;
  unbound();

  Number.prototype.baz = function() {
    console.log(typeof this);
  }
  num.baz();
})();
