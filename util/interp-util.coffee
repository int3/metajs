{Util, Map} = require './util'

root = window ? exports

root.interpreterGlobal = do ->
  interpreterGlobal = {}
  if global?
    nativeGlobal = global
    globalName = 'global'
  else
    nativeGlobal = window
    globalName = 'window'
  interpreterGlobal[k] = v for k, v of nativeGlobal
  nonEnumerable = ['Object', 'String', 'Function', 'RegExp', 'Number', 'Boolean',
    'Date', 'Math', 'Error', 'JSON', 'eval', 'toString', 'undefined']
  Util.defineNonEnumerable interpreterGlobal, k, nativeGlobal[k] for k in nonEnumerable
  Util.defineNonEnumerable interpreterGlobal, 'global', interpreterGlobal

class root.InterpreterException

class root.ReturnException extends root.InterpreterException
  constructor: (@value) ->

class root.BreakException extends root.InterpreterException

class root.ContinueException extends root.InterpreterException

class root.JSException extends root.InterpreterException
  constructor: (@exception) ->

class root.Environment
  constructor: (@scopeChain=[new Map], @currentScope=0, @strict=false) ->

  copy: -> new root.Environment @scopeChain[..], @currentScope, @strict

  getGlobalEnv: -> new root.Environment @scopeChain[..0], 0, @strict

  increaseScope: (lexicalOnly) ->
    @scopeChain.push new Map
    @currentScope++ unless lexicalOnly
    Util.last(@scopeChain)

  decreaseScope: ->
    @scopeChain.pop()
    @currentScope = Math.min @currentScope, @scopeChain.length - 1
    Util.last(@scopeChain)

  insert: (name, value) ->
    if name is 'this' and not @strict
      if not value?
        value = root.interpreterGlobal
      else if (t = typeof value) not in ['object', 'function']
        value = new root.interpreterGlobal[t.charAt(0).toUpperCase() + t[1..]] value
    @scopeChain[@currentScope].set(name, value)

  update: (name, value) ->
    for i in [@scopeChain.length - 1 .. 0] by -1
      if @scopeChain[i].has(name)
        return @scopeChain[i].set(name, value)
    throw "Tried to update nonexistent var '#{name}'"

  globalInsert: (name, value) ->
    @scopeChain[0].set(name, value)

  has: (name) ->
    for i in [@scopeChain.length - 1 .. 0] by -1
      return true if @scopeChain[i].has(name)
    name of root.interpreterGlobal

  resolve: (name) ->
    for i in [@scopeChain.length - 1 .. 0] by -1
      return @scopeChain[i].get(name) if @scopeChain[i].has(name)
    return root.interpreterGlobal[name] if name of root.interpreterGlobal
    throw "Unable to resolve #{JSON.stringify name}"

  toString: -> scope.cache for scope in @scopeChain
