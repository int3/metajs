function Foo() {
  this.bar = 1;
}

Foo.prototype.baz = 2;

var foo1 = new Foo();
var foo2 = new Foo();
console.log(foo1.bar);
console.log(foo1.baz);
console.log(delete foo1.bar);
console.log(delete foo1.baz);
console.log(foo1.bar);
console.log(foo1.baz);
console.log(foo2.bar);
console.log(foo2.baz);
