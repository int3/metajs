#! /usr/bin/env coffee

fs = require 'fs'
esprima = require 'esprima'

Util =
  last: (arr) -> arr[arr.length - 1]

  isString: (s) -> typeof s == 'string' || s instanceof String

  defineNonEnumerable: (obj, k, v) ->
    Object.defineProperty obj, k,
      value: v
      writable: true
      enumerable: false
      configurable: true

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
      value

interpreterGlobal = do ->
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
        value = interpreterGlobal
      else if (t = typeof value) not in ['object', 'function']
        value = new interpreterGlobal[t.charAt(0).toUpperCase() + t[1..]] value
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
    name of interpreterGlobal

  resolve: (name) ->
    for i in [@scopeChain.length - 1 .. 0] by -1
      return @scopeChain[i].get(name) if @scopeChain[i].has(name)
    return interpreterGlobal[name] if name of interpreterGlobal
    throw "Unable to resolve #{JSON.stringify name}"

  toString: -> scope.cache for scope in @scopeChain

class InterpretedFunction
  constructor: (@__ctor__, @__call__) ->
    @prototype = @__ctor__.prototype

  apply: (_this, args) ->
    await this.applyCps _this, args, defer(e, result)
    throw e if e?
    return result

  applyCps: (appliedThis, args, cont) ->
    calleeNode = this.__call__
    calleeNode.env.increaseScope()
    argsObject = {}
    calleeNode.env.insert "arguments", argsObject
    for arg, i in args
      calleeNode.env.insert calleeNode.params[i].name, arg
      argsObject[i] = arg
    Util.defineNonEnumerable argsObject, 'length', args.length
    calleeNode.env.insert 'this', appliedThis
    await interp calleeNode.body, calleeNode.env, defer(e, result)
    calleeNode.env.decreaseScope()
    return cont(null, e.value) if e instanceof ReturnException
    return cont(e) if e?
    return cont(null, result)

  call: (_this) -> @apply _this, Array::slice arguments, 1

  callCps: (_this, cont) -> applyCps _this, (Array::slice arguments, 1), cont

interp = (node, env=new Environment, cont) ->
  try
    switch node.type
      when 'Program', 'BlockStatement'
        for stmt, i in node.body
          env.strict ||= i == 0 and stmt.expression?.value is 'use strict'
          await interp(stmt, env, defer(e, v))
          return cont(e) if e?
          return cont(null, v) if node.type is 'Program' and i == node.body.length - 1 # for eval's return value
        return cont()
      when 'FunctionDeclaration', 'FunctionExpression'
        node.env = env.copy()
        fn = (new Function "return function #{node.id?.name ? ''}() {}")()
        ifn = new InterpretedFunction fn, node
        if node.id?
          env.insert(node.id.name, ifn)
        return cont(null, ifn)
      when 'VariableDeclaration'
        for dec in node.declarations
          await interp dec, env, defer(e, result)
          return cont(e) if e?
        return cont()
      when 'VariableDeclarator'
        await interp node.init, env, defer(e, result)
        return cont(e) if e?
        declaratorResult = env.insert node.id.name, result, env
        return cont(null, declaratorResult)
      when 'ExpressionStatement'
        await interp node.expression, env, defer(e, result)
        return cont(e, result)
      when 'CallExpression'
        callee = null
        if node.callee.type is 'MemberExpression'
          await evalMemberExpr node.callee, env, defer(e, result)
          return cont(e) if e?
          [_this, calleeName] = result
          callee = _this[calleeName]
        else
          _this = undefined
          await interp(node.callee, env, defer(e, callee))
          return cont(e) if e?
        args = []
        for arg in node.arguments
          await interp(arg, env, defer(e, argResult))
          return cont(e) if e?
          args.push(argResult)
        if callee == eval
          return cont(null, args[0]) unless Util.isString args[0]
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
            await interp ast, env, defer(e, result)
            return cont(e, result)
          else
            await interp ast, env.getGlobalEnv(), defer(e, result)
            return cont(e, result)
        else
          if callee instanceof InterpretedFunction
            await callee.applyCps _this, args, defer(e, applied)
            return cont(e) if e?
            return cont(null, applied)
          else 
            applied = callee.apply _this, args
            return cont(null, applied)
      when 'NewExpression'
        await interp node.callee, env, defer(e, callee)
        return cont(e) if e?
        args = []
        for arg in node.arguments
          await interp(arg, env, defer(e, result))
          return cont(e) if e?
          args.push(result)
        if callee.__ctor__?
          obj = new callee.__ctor__
          if callee instanceof InterpretedFunction
            await callee.applyCps obj, args, defer(e, result)
            return cont(e) if e?
          else
            callee.apply obj, args
        else
          if callee instanceof InterpretedFunction
            await callee.bind.applyCps callee, ([null].concat args), defer(e, result)
            return cont(e) if e?
          else
            obj = new (callee.bind.apply callee, [null].concat args)
        return cont(null, obj)
      #*** Control Flow ***#
      when 'IfStatement'
        await interp node.test, env, defer(e, test)
        return cont(e) if e?
        if (test)
          await interp node.consequent, env, defer(e, result)
          return cont(e, result)
        else if node.alternate?
          await interp node.alternate, env, defer(e, result)
          return cont(e, result)
        else
          return cont()
      when 'WhileStatement'
        while (true)
          # Test
          await interp node.test env, defer(e, test)
          return cont(e) if e?
          return cont() if not test
          # Body
          await interp node.body, env, defer(e)
          return cont() if e instanceof BreakException
          return cont(e) if e? and not (e instanceof ContinueException)
        return cont()
      when 'DoWhileStatement'
        while (true)
          # Body
          await interp node.body, env, defer(e)
          return cont() if e instanceof BreakException
          return cont(e) if e? and not (e instanceof ContinueException)
          # Test
          await interp node.test, env, defer(e, test)
          return cont(e) if e?
          return cont() if not test
        return cont()
      when 'ForStatement'
        await interp node.init, env, defer(e)
        return cont(e) if e?
        while (true)
          # Test
          await interp node.test, env, defer(e, test)
          return cont(e) if e?
          return cont() if not test
          # Body
          await interp node.body, env, defer(e) 
          return cont() if e instanceof BreakException
          return cont(e) if e? and not (e instanceof ContinueException)
          # Update
          await interp node.update, env, defer(e)
          return cont() if e instanceof BreakException
          return cont(e) if e? and not (e instanceof ContinueException)
      when 'ForInStatement'
        await interp node.left, env, defer(e)
        return cont(e) if e?
        await interp node.right, env, defer(e, obj)
        return cont(e) if e?
        for k of obj
          if node.left.type is 'VariableDeclaration'
            await assign node.left.declarations[0].id, k, env, defer(e, result)
            return cont(e) if e?
          else
            await assign node.left, k, env, defer(e, result)
            return cont(e) if e?
          await interp node.body, env, defer(e)
          return cont(e) if e?
        return cont()
      when 'BreakStatement'
        return cont(new BreakException)
      when 'ContinueStatement'
        return cont(new ContinueException)
      when 'ReturnStatement'
        return cont(new ReturnException undefined) if node.argument is null
        await interp node.argument, env, defer(e, result)
        return cont(e || new ReturnException result)
      when 'ThrowStatement'
        await interp node.argument, env, defer(e, result)
        return cont(e || new JSException result)
      when 'TryStatement'        
        await interp node.block, env, defer(errorInTry, result)
        if errorInTry instanceof JSException and node.handlers.length > 0
          catchEnv = env.increaseScope true
          catchEnv.set node.handlers[0].param.name, errorInTry.exception
          await interp node.handlers[0], env, defer(errorInCatch, result)
          env.decreaseScope() # unless errorInCatch?
          if node.finalizer # try->catch->finally
            await interp node.finalizer, env, defer(errorInFinalizer, result)
            return cont(errorInFinalizer || errorInCatch)
          # TODO: test throw from finalizer .. how does it work?
          else # try->catch
            return cont(eInCatch);
        else if node.finalizer
          # TODO: test return from finalizer
          await interp node.finalizer, env, defer(errorInFinalizer, result)
          return cont(errorInFinalizer || errorInTry) # try->finally
        else
          return cont(errorInTry) # try
      when 'CatchClause'
        await interp node.body, env, defer(e, result)
        return cont(e, result)
      #*** Operator Expressions ***#
      when 'BinaryExpression'
        await interp node.left, env, defer(e, lhs)
        return cont(e) if e?
        await interp node.right, env, defer(e, rhs)
        return cont(e) if e?
        switch node.operator
          when '+'
            return cont(null, lhs + rhs)
          when '-'
            return cont(null, lhs - rhs)
          when '*'
            return cont(null, lhs * rhs)
          when '/'
            return cont(null, lhs / rhs)
          when '&'
            return cont(null, lhs & rhs)
          when '|'
            return cont(null, lhs | rhs)
          when '^'
            return cont(null, lhs ^ rhs)
          when '>>'
            return cont(null, lhs >> rhs)
          when '<<'
            return cont(null, lhs << rhs)
          when '>>>'
            return cont(null, lhs >>> rhs)
          when '<'
            return cont(null, lhs < rhs)
          when '>'
            return cont(null, lhs > rhs)
          when '<='
            return cont(null, lhs <= rhs)
          when '>='
            return cont(null, lhs >= rhs)
          when '=='
            return cont(null, `lhs == rhs`)
          when '==='
            return cont(null, `lhs === rhs`)
          when '!='
            return cont(null, `lhs != rhs`)
          when '!=='
            return cont(null, `lhs !== rhs`)
          when 'instanceof'
            return cont(null, lhs instanceof rhs.__ctor__)
          else
            return cont("Unrecognized operator #{node.operator}")
      when 'AssignmentExpression'
        await interp node.right, env, defer(e, value)
        return cont(e) if e?
        if node.operator is '='
          await assign node.left, value, env, defer(e, result)
          return cont(e, result)
        else
          if node.left.type is 'Identifier'
            original = env.resolve node.left.name
          else if node.left.type is 'MemberExpression'
            evalMemberExpr node.left, env, cont(e, result)
            return cont(e) if e?
            [object, property] = result
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
          return cont(null, original)
      when 'UpdateExpression'
        await interp node.argument, env, defer(e, original)
        return cont(e) if e?
        if node.operator is '++'
          newValue = original + 1
        else # '--'
          newValue = original - 1
        if node.argument.type is 'Identifier'
          env.insert node.argument.name, newValue
        else if node.argument.type is 'MemberExpression'
          await evalMemberExpr node.argument, env, defer(e, result)
          return cont(e) if e?
          [object, property] = result
          object[property] = newValue
        if node.prefix 
          return cont(null, newValue)
        else 
          return cont(null, original)
      when 'UnaryExpression'
        if node.operator is 'delete'
          if node.argument.type is 'MemberExpression'
            await evalMemberExpr node.argument, env, defer(e, result)
            return cont(e) if e?
            [object, property] = result
            return cont(null, delete object[property])
          else
            throw "NYI"
        else
          await interp node.argument, env, defer(e, arg)
          return cont(e) if e?
          switch node.operator
            when '-'
              return cont(null, -arg)
            when '~'
              return cont(null, ~arg)
            when '!'
              return cont(null, !arg)
            when 'typeof'
              return cont(null, typeof arg)
            else
              return cont("NYI")
      #*** Identifiers and Literals ***#
      when 'Identifier'
        return cont(null, env.resolve node.name)
      when 'MemberExpression'
        await evalMemberExpr node, env, defer(e, result)
        return cont(e) if e?
        [object, property] = result
        return cont(null, object[property])
      when 'ThisExpression'
        return cont(null, env.resolve 'this')
      when 'Literal'
        return cont(null, node.value)
      when 'ObjectExpression'
        obj = {}
        for prop in node.properties
          await interp prop.value, env, defer(e, propValue)
          return cont(e) if e?
          obj[prop.key.name ? prop.key.value] = propValue
        return cont(null, obj)
      when 'ArrayExpression'
        arr = []
        for el in node.elements
          await interp el, env, defer(e, elValue)
          return cont(e) if e?          
          arr.push elValue
        return cont(null, arr)
      else
        console.log "Unrecognized node!"
        console.log node
        return cont('Unrecognized node!')
  catch e
    unless e instanceof InterpreterException
      console.log "Line #{node.loc.start.line}: Error in #{node.type}"
    return cont(e)

evalMemberExpr = (node, env, cont) ->
  await interp node.object, env, defer(e, object)
  return cont(e) if e?
  propNode = node.property
  if propNode.type is 'Identifier' and not node.computed
    cont(null, [object, propNode.name])
  else
    await interp propNode, env, defer(e, property)
    return cont(e, [object, property])

assign = (node, value, env, cont) ->
  if node.type is 'Identifier'
    try
      env.update node.name, value
    catch e
      env.globalInsert node.name, value
    return cont(null, value)
  else if node.type is 'MemberExpression'
    await evalMemberExpr node, env, defer(e, result)
    return cont(e) if e?
    [object, property] = result
    object[property] = value
    return cont(null, value)
  else
    return cont("Invalid LHS in assignment")

if require.main is module
  {argv} = require 'optimist'
  if argv._.length < 1
    console.log "Usage: interp.coffee [filename]"
    process.exit 1
  parsed = esprima.parse (fs.readFileSync argv._[0]), loc: true

  # interp parsed, new Environment
  await interp parsed, new Environment, defer(e, result)
  throw e if e?
  result

