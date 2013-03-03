metajs
======

A CPS Javascript metacircular interpreter that visualizes script execution.

Written in [IcedCoffeeScript][2]. Uses [Esprima][1] for the parser and
[CodeMirror][3] for the front-end.

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
[3]: http://codemirror.net/
