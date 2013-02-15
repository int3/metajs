var gen = function* () {
  try {
    for (var i = 0; i < 5; i++) {
      console.log("Iterator received", yield i);
    }
  }
  catch (e) {
    console.log("Iterator caught", e);
  }
  finally {
    console.log("Shutting down iterator");
  }
}

console.log("Generator 1");

var it = gen();
it.send();

while (true) {
  try {
    console.log(it.send("hi"));
  }
  catch (e) {
    if (e instanceof StopIteration) {
      console.log("iterator exhausted");
      break;
    }
    else
      throw e;
  }
}

console.log("Generator 2");

it = gen();
it.next();
console.log(it.close());

try {
  console.log(it.next());
}
catch (e) {
  if (e instanceof StopIteration) {
    console.log("iterator exhausted");
  }
  else
    throw e;
}

console.log("Generator 3");

it = gen();
it.next();
try {
  it.throw(new Error("injected error"));
}
catch (e) {
  if (e instanceof StopIteration)
    console.log("iterator exhausted");
  else
    throw e;
}
