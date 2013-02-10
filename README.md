metajs
======

A collection of simple metacircular AST interpreters for Javascript, written in
Coffeescript and IcedCoffeeScript.

[Esprima][1] is used for the parser.

Installation
------------

    npm install esprima

Usage
-----

To start the REPL:

    ./interpreter.coffee

To execute a file:

    ./interpreter.coffee [filename]

Testing
-------

To test a single interpreter, do

    make test INTERPRETER=[interpreter filename]

To test all of them:

    make test-all

[1]: http://esprima.org/
