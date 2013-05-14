#! /usr/bin/env iced
{evaluate,Environment} = require './lib/interpreter'
esprima = require 'esprima'

toplevel = ->
  repl = require 'repl'
  env = new Environment
  repl.start
    eval: (cmd, ctx, filename, callback) ->
      evaluate (esprima.parse cmd[1..-2], loc: true), env, callback, (e) ->
        callback("Error: #{e}")

{argv} = require 'optimist'
if argv._.length < 1
  toplevel()
else
  fs = require 'fs'
  ast = esprima.parse (fs.readFileSync argv._[0]), loc: true
  evaluate ast, new Environment, (->), (e) ->
    console.log "Error: #{e}"
    process.exit 1
