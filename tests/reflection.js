console.log("testing the arguments object");

(function(foo) {
  console.log(arguments);
  console.log(arguments.length);
  arguments.length = 0;
  console.log(arguments.length);
  delete arguments.length;
  console.log(arguments.length);
  console.log(Object.getPrototypeOf(arguments));
})("bar");

(function(arguments) {
  console.log(arguments);
  console.log(arguments.length);
  console.log(Object.getPrototypeOf(arguments));
})({});

console.log("testing eval()");

a = -10;
(function() {
  var a = 1;
  console.log(eval("console.log(a); a++"));
  console.log(a);

  console.log(global['eval']("console.log(a); a++"));

  var eeval = eval;
  console.log(eeval("console.log(a); a++"));
  console.log(a);

  console.log(eval({}));
})();
console.log(a);

console.log("check that we have santized '__proto__'");
var __proto__ = null;
console.log(__proto__);
console.log(toString);
console.log(global.__proto__);
