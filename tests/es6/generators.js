function exhaustGenerator(it) {
  while (true) {
    try {
      console.log(it.send("hi"));
    }
    catch (e) {
      if (e instanceof StopIteration) {
        console.log("Generator exhausted, returned", e.value);
        break;
      }
      else
        throw e;
    }
  }
}

var gen = function* () {
  try {
    for (var i = 0; i < 5; i++) {
      console.log("Generator received", yield i);
    }
  }
  catch (e) {
    console.log("Generator caught", e);
  }
  finally {
    console.log("Shutting down generator");
  }
};

console.log("Generator 1");

var it = gen();
it.send();
exhaustGenerator(it);

console.log("Generator 2");

it = gen();
it.next();
console.log(it.close());
exhaustGenerator(it);

console.log("Generator 3");

it = gen();
it.next();
try {
  it.throw(new Error("injected error"));
}
catch (e) {
  if (e instanceof StopIteration)
    console.log("generator exhausted, returned", e.value);
  else
    throw e;
}

console.log("Testing return value"); 

console.log("Generator 4");

gen = function* () {
  yield 1;
  return 2;
};
it = gen();
it.next();
exhaustGenerator(it);

console.log("Testing yield*");

console.log("Generator 5");

gen = function*() {
  for (var i = 0; i < 3; i++) {
    var inner = innerGen(i + 1);
    yield* inner;
  }
};

var innerGen = function*(j) {
  try {
    for (var i = 0; i < 3; i++)
      yield i * j;
  }
  catch (e) {
    console.log("Inner generator caught", e);
  }
};

it = gen();
it.next();
exhaustGenerator(it);

console.log("Generator 6");

it = gen();
it.next();
it.throw(new Error("injected error"));
exhaustGenerator(it);
