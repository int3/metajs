metajs
======

A CPS Javascript metacircular interpreter, written in [IcedCoffeeScript][2].

[Esprima][1] is used for the parser.

Setup
-----

    npm install
    npm install -g browserify@1.17.3 iced-coffee-script

Usage
-----

To start the REPL:

    ./interpreter.coffee

To execute a file:

    ./interpreter.coffee [filename]

To run in the browser:

    make browser
    cd browser
    python -m SimpleHTTPServer

Then point your browser to http://localhost:8000/.

Testing
-------

    make test

Contributors
------------

* [omphalos](https://github.com/omphalos)

[1]: http://esprima.org/
[2]: http://maxtaco.github.com/coffee-script/
