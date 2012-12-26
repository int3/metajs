#! /usr/bin/env coffee

fs = require 'fs'
esprima = require 'esprima'

`if (typeof global === "undefined" || global === null) global = window;`

Util =
  last: (arr) -> arr[arr.length - 1]

  isString: (s) -> typeof s == 'string' || s instanceof String

  evalMemberExpr: (node, env) ->
    object = interp node.object, env
    propNode = node.property
    property =
      if propNode.type is 'Identifier'
        propNode.name
      else
        interp propNode, env
    [object, property]

unless Map? # polyfill
  class Map
    constructor: ->
      @cache = Object.create null
      @proto_cache = undefined
      @proto_set = false

    get: (key) ->
      key = key.toString()
      return @cache[key] unless key is '__proto__'
      return @proto_cache

    has: (key) ->
      key = key.toString()
      return key of @cache unless key is '__proto__'
      return @proto_set

    set: (key, value) ->
      unless key.toString() is '__proto__'
        @cache[key] = value
      else
        @proto_cache = value
        @proto_set = true

class InterpreterException

class ReturnException extends InterpreterException
  constructor: (@value) ->

class BreakException extends InterpreterException

class ContinueException extends InterpreterException

class JSException extends InterpreterException
  constructor: (@exception) ->

class Environment
  constructor: (@scopeChain=[new Map], @currentScope=0, @strict=false) ->

  copy: -> new Environment @scopeChain[..], @currentScope, @strict

  getGlobalEnv: -> new Environment @scopeChain[..0], 0, @strict

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
        value = global
      else if (t = typeof value) not in ['object', 'function']
        value = new global[t.charAt(0).toUpperCase() + t[1..]] value
    @scopeChain[@currentScope].set(name, value)

  update: (name, value) ->
    for i in [@scopeChain.length - 1 .. 0] by -1
      if @scopeChain[i].has(name)
        return @scopeChain[i].set(name, value)
    throw "Tried to updated nonexistent var '#{name}'"

  globalInsert: (name, value) ->
    @scopeChain[0].set(name, value)

  has: (name) ->
    for i in [@scopeChain.length - 1 .. 0] by -1
      return true if @scopeChain[i].has(name)
    global[name]?

  resolve: (name) ->
    for i in [@scopeChain.length - 1 .. 0] by -1
      return @scopeChain[i].get(name) if @scopeChain[i].has(name)
    return global[name] if name of global
    throw "Unable to resolve #{JSON.stringify name}"

  toString: -> scope.cache for scope in @scopeChain

class InterpretedFunction
  constructor: (@__ctor__, @__call__) ->
    @prototype = @__ctor__.prototype

  apply: (_this, args) ->
    calleeNode = this.__call__
    calleeNode.env.increaseScope()
    argsObject = {}
    calleeNode.env.insert "arguments", argsObject
    for arg, i in args
      calleeNode.env.insert calleeNode.params[i].name, arg
      argsObject[i] = arg
    Object.defineProperty argsObject, 'length',
      value: args.length
      writable: true
      enumerable: false
      configurable: true
    calleeNode.env.insert 'this', _this
    try
      interp calleeNode.body, calleeNode.env
    catch e
      if e instanceof ReturnException
        e.value
      else # internal error
        throw e
    finally
      calleeNode.env.decreaseScope()

  call: (_this) -> @apply _this, Array::slice arguments, 1

interp = (node, env=new Environment) ->
  try
    switch node.type
      when 'Program', 'BlockStatement'
        for stmt, i in node.body
          env.strict ||= i == 0 and stmt.expression?.value is 'use strict'
          v = interp(stmt, env)
          return v if i == node.body.length - 1 # for eval's return value
      when 'FunctionDeclaration', 'FunctionExpression'
        node.env = env.copy()
        fn = (new Function "return function #{node.id?.name ? ''}() {}")()
        ifn = new InterpretedFunction fn, node
        if node.id?
          env.insert(node.id.name, ifn)
        ifn
      when 'VariableDeclaration'
        interp dec, env for dec in node.declarations
      when 'VariableDeclarator'
        env.insert node.id.name, interp node.init, env
      when 'ExpressionStatement'
        interp node.expression, env
      when 'CallExpression'
        if node.callee.type is 'MemberExpression'
          [_this, calleeName] = Util.evalMemberExpr node.callee, env
          callee = _this[calleeName]
        else
          _this = undefined
          callee = interp(node.callee, env)
        args = (interp(arg, env) for arg in node.arguments)
        if callee == eval
          return args[0] unless Util.isString args[0]
          ast = esprima.parse args[0]
          fnName =
            if node.callee.type is 'MemberExpression' and
             node.callee.property.type is 'Identifier'
              node.callee.property.name
            else if node.callee.type is 'Identifier'
              node.callee.name
            else
              null
          if fnName is 'eval'
            interp ast, env
          else
            interp ast, env.getGlobalEnv()
        else
          callee.apply _this, args
      when 'NewExpression'
        callee = interp node.callee, env
        args = (interp(arg, env) for arg in node.arguments)
        if callee.__ctor__?
          obj = new callee.__ctor__
          callee.apply obj, args
        else
          obj = new (callee.bind.apply callee, [null].concat args)
        obj
      #*** Control Flow ***#
      when 'IfStatement'
        test = interp node.test, env
        if (test)
          interp node.consequent, env
        else if node.alternate?
          interp node.alternate, env
      when 'WhileStatement'
        while (interp node.test, env)
          try
            interp node.body, env
          catch e
            break if e instanceof BreakException
            continue if e instanceof ContinueException
      when 'DoWhileStatement'
        `do {
          try {
            interp(node.body, env)
          }
          catch (e) {
            if (e instanceof BreakException) break;
            else if (e instanceof ContinueException) continue;
            throw e;
          }
        } while (interp(node.test, env))`
        null
      when 'ForStatement'
        interp node.init, env
        while (interp node.test, env)
          try
            interp node.body, env
            interp node.update, env
          catch e
            if e instanceof BreakException
              break
            else if e instanceof ContinueException
              interp node.update, env
              continue
            else
              throw e
      when 'BreakStatement'
        throw new BreakException
      when 'ContinueStatement'
        throw new ContinueException
      when 'ReturnStatement'
        throw new ReturnException undefined if node.argument is null
        throw new ReturnException interp node.argument, env
      when 'ThrowStatement'
        throw new JSException interp node.argument, env
      when 'TryStatement'
        try
          interp node.block, env
        catch e
          if e instanceof JSException and node.handlers.length > 0
            catchEnv = env.increaseScope true
            catchEnv.set node.handlers[0].param.name, e.exception
            interp node.handlers[0], env
            env.decreaseScope()
          else
            throw e
        finally
          if node.finalizer
            interp node.finalizer, env
      when 'CatchClause'
        interp node.body, env
      #*** Operator Expressions ***#
      when 'BinaryExpression'
        switch node.operator
          when '+'
            interp(node.left, env) + interp(node.right, env)
          when '-'
            interp(node.left, env) - interp(node.right, env)
          when '*'
            interp(node.left, env) * interp(node.right, env)
          when '/'
            interp(node.left, env) / interp(node.right, env)
          when '&'
            interp(node.left, env) & interp(node.right, env)
          when '|'
            interp(node.left, env) | interp(node.right, env)
          when '^'
            interp(node.left, env) ^ interp(node.right, env)
          when '>>'
            interp(node.left, env) >> interp(node.right, env)
          when '<<'
            interp(node.left, env) << interp(node.right, env)
          when '>>>'
            interp(node.left, env) >>> interp(node.right, env)
          when '<'
            interp(node.left, env) < interp(node.right, env)
          when '>'
            interp(node.left, env) > interp(node.right, env)
          when '<='
            interp(node.left, env) <= interp(node.right, env)
          when '>='
            interp(node.left, env) >= interp(node.right, env)
          when '=='
            `interp(node.left, env) == interp(node.right, env)`
          when '==='
            interp(node.left, env) == interp(node.right, env)
          when '!='
            `interp(node.left, env) != interp(node.right, env)`
          when '!=='
            interp(node.left, env) != interp(node.right, env)
          when 'instanceof'
            interp(node.left, env) instanceof interp(node.right, env).__ctor__
          else
            throw "Unrecognized operator #{node.operator}"
      when 'AssignmentExpression'
        value = interp node.right, env
        if node.left.type is 'MemberExpression'
          [object, property] = Util.evalMemberExpr node.left, env

        if node.operator is '='
          if node.left.type is 'Identifier'
            try
              env.update node.left.name, value
            catch e
              env.globalInsert node.left.name, interp node.right, env
          else if node.left.type is 'MemberExpression'
            object[property] = value
          else
            throw "Invalid LHS in assignment"
        else
          if node.left.type is 'Identifier'
            original = env.resolve node.left.name
          else if node.left.type is 'MemberExpression'
            original = object[property]
          else
            throw "Invalid LHS in assignment"
          switch node.operator
            when '+='
              original += value
            when '-='
              original -= value
            when '*='
              original *= value
            when '/='
              original /= value
            when '&='
              original &= value
            when '|='
              original |= value
            else
              throw "Unrecognized compound assignment #{node.operator}"
          if node.left.type is 'Identifier'
            env.insert node.left.name, original
          else if node.left.type is 'MemberExpression'
            object[property] = original
      when 'UpdateExpression'
        original = interp node.argument, env
        if node.operator is '++'
          newValue = original + 1
        else # '--'
          newValue = original - 1
        if node.argument.type is 'Identifier'
          env.insert node.argument.name, newValue
        else if node.argument.type is 'MemberExpression'
          [object, property] = Util.evalMemberExpr node.argument, env
          object[property] = newValue
        if node.prefix then newValue else original
      when 'UnaryExpression'
        if node.operator is 'delete'
          if node.argument.type is 'MemberExpression'
            [object, property] = Util.evalMemberExpr node.argument, env
            delete object[property]
          else
            throw "NYI"
        else
          arg = interp node.argument, env
          switch node.operator
            when '-'
              -arg
            when '~'
              ~arg
            when '!'
              !arg
            when 'typeof'
              typeof arg
            else
              throw "NYI"
      #*** Identifiers and Literals ***#
      when 'Identifier'
        env.resolve node.name
      when 'MemberExpression'
        [object, property] = Util.evalMemberExpr node, env
        object[property]
      when 'ThisExpression'
        env.resolve 'this'
      when 'Literal'
        node.value
      when 'ObjectExpression'
        obj = {}
        for prop in node.properties
          obj[prop.key.name ? prop.key.value] = interp(prop.value, env)
        obj
      when 'ArrayExpression'
        arr = []
        for el in node.elements
          arr.push interp el, env
        arr
      else
        console.log "Unrecognized node!"
        console.log node
  catch e
    unless e instanceof InterpreterException
      console.log "Line #{node.loc.start.line}: Error in #{node.type}"
    throw e

if require.main is module
  {argv} = require 'optimist'
  if argv._.length < 1
    console.log "Usage: interp.coffee [filename]"
    process.exit 1
  interp esprima.parse (fs.readFileSync argv._[0]), loc: true
