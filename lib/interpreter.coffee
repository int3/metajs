esprima = require 'esprima'
{Util, Map} = require './util'

root = exports

class InterpreterException

class ReturnException extends InterpreterException
  constructor: (@value) ->

class BreakException extends InterpreterException

class ContinueException extends InterpreterException

class YieldException extends InterpreterException
  constructor: (@cont, @errCont, @value) ->

class JSException
  constructor: (@error, @node, @env) ->
  toString: -> @error.toString()

class StopIteration
  constructor: (@value) ->
  toString: -> "StopIteration"

root.Environment = class Environment
  constructor: (@scopeChain=[new Map], @currentScope=0, @strict=false) ->
    @global = {}
    if global?
      nativeGlobal = global
      globalName = 'global'
    else
      nativeGlobal = window
      globalName = 'window'
    @global[k] = v for k, v of nativeGlobal
    nonEnumerable = ['Object', 'String', 'Function', 'RegExp', 'Number', 'Boolean',
      'Date', 'Math', 'Error', 'JSON', 'eval', 'toString', 'undefined']
    Util.defineNonEnumerable @global, k, nativeGlobal[k] for k in nonEnumerable
    Util.defineNonEnumerable @global, globalName, @global
    Util.defineNonEnumerable @global, 'StopIteration', StopIteration

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
        value = @global
      else if (t = typeof value) not in ['object', 'function']
        value = new @global[t.charAt(0).toUpperCase() + t[1..]] value
    @scopeChain[@currentScope].set(name, value)

  update: (name, value) ->
    for i in [@scopeChain.length - 1 .. 0] by -1
      if @scopeChain[i].has(name)
        return @scopeChain[i].set(name, value)
    throw new ReferenceError "Tried to update nonexistent var '#{name}'"

  globalInsert: (name, value) ->
    @scopeChain[0].set(name, value)

  has: (name) ->
    for i in [@scopeChain.length - 1 .. 0] by -1
      return true if @scopeChain[i].has(name)
    name of @global

  resolve: (name) ->
    for i in [@scopeChain.length - 1 .. 0] by -1
      return @scopeChain[i].get(name) if @scopeChain[i].has(name)
    return @global[name] if name of @global
    throw new ReferenceError "Unable to resolve #{JSON.stringify name}"

  toString: -> scope.cache for scope in @scopeChain

makeArgsObject = (argsArray) ->
  argsObject = {}
  argsObject[i] = arg for arg, i in argsArray
  Util.defineNonEnumerable argsObject, 'length', argsArray.length

root.CPSFunction = class CPSFunction
  constructor: (@name, @__env__, __apply__) ->
    @__apply__ ?= __apply__
    @__ctor__ = (new Function "return function #{@name}() {}")()
    @prototype = @__ctor__.prototype

  apply: (thisArg, args) ->
    await this.__apply__ thisArg, args, defer(result), errCont
    return result

class InterpretedFunction extends CPSFunction
  constructor: (name, __env__, @__node__) ->
    super(name, __env__)

  __apply__: (thisArg, args, cont, errCont) ->
    @__env__.increaseScope()
    @__env__.insert 'arguments', makeArgsObject args
    # must be called after makeArgsObject in case there is a param named
    # 'arguments'
    @__env__.insert(param.name, args[i]) for param, i in @__node__.params
    @__env__.insert 'this', thisArg
    await root.evaluate @__node__.body, @__env__, defer(result), (e) =>
      if e instanceof ReturnException
        @__env__.decreaseScope()
        cont(e.value)
      else
        errCont(e)
    @__env__.decreaseScope()
    cont(result)

class GeneratorFunction extends InterpretedFunction
  __apply__: (thisArg, args, cont, errCont) ->
    cont new Generator thisArg, args, @__node__, @__env__.copy()

class Generator
  NEWBORN = {}
  EXECUTING = {}
  CLOSED = {}
  SUSPENDED = {}

  constructor: (thisArg, args, @__node__, @__env__) ->
    @__cont__ = null
    @__state__ = NEWBORN
    @__env__.increaseScope()
    @__env__.insert 'arguments', makeArgsObject args
    @__env__.insert(param.name, args[i]) for param, i in @__node__.params
    @__env__.insert 'this', thisArg

  send: new CPSFunction('send', null, (thisArg, args, cont, errCont) ->
    v = args[0]
    thisArg.__calleeCont__ = cont
    thisArg.__calleeErrCont__ = errCont
    switch thisArg.__state__
      when EXECUTING
        errCont new Error "Generator is already executing"
      when CLOSED
        errCont new StopIteration
      when NEWBORN
        if v isnt undefined then throw new TypeError
        thisArg.__state__ = EXECUTING
        await root.evaluate thisArg.__node__.body, thisArg.__env__, bodyCont = defer(rv), (e) ->
          if e instanceof YieldException
            thisArg.__state__ = SUSPENDED
            thisArg.__cont__ = e.cont
            thisArg.__errCont__ = e.errCont
            thisArg.__calleeCont__ e.value
          else if e instanceof ReturnException
            bodyCont(e.value)
          else
            thisArg.__calleeErrCont__ e
        thisArg.__state__ = CLOSED
        thisArg.__calleeErrCont__ new StopIteration rv
      else # SUSPENDED
        thisArg.__cont__ v)

  next: new CPSFunction('next', null, (thisArg, args, cont, errCont) ->
    thisArg.send.__apply__ thisArg, [], cont, errCont)

  close: new CPSFunction('close', null, (thisArg, args, cont, errCont) ->
    thisArg.__calleeCont__ = cont
    thisArg.__calleeErrCont__ = (e) ->
      if e instanceof StopIteration
        cont()
      else
        errCont(e)
    switch thisArg.__state__
      when EXECUTING
        errCont new Error "Generator is currently executing"
      when NEWBORN
        thisArg.__state__ = CLOSED
      when SUSPENDED
        thisArg.__state__ = EXECUTING
        thisArg.__errCont__ new ReturnException
      when CLOSED
        cont())

  throw: new CPSFunction('_throw', null, (thisArg, args, cont, errCont) ->
    thisArg.__calleeCont__ = cont
    thisArg.__calleeErrCont__ = errCont
    switch thisArg.__state__
      when EXECUTING
        errCont new Error "Generator is currently executing"
      when CLOSED
        errCont new Error "Generator is closed"
      when NEWBORN
        thisArg.__state__ = CLOSED
        thisArg.__calleeErrCont__ args[0]
      when SUSPENDED
        thisArg.__state__ = EXECUTING
        thisArg.__errCont__ args[0])

  iterator: new CPSFunction('iterator', null, (thisArg, args, cont, errCont) ->
    cont thisArg)

root.evaluate = (node, env, cont, errCont) ->
  try
    switch node.type
      when 'EmptyStatement'
        cont()
      when 'Program', 'BlockStatement'
        for stmt, i in node.body
          env.strict ||= i == 0 and stmt.expression?.value is 'use strict'
          await root.evaluate stmt, env, defer(v), errCont
          return cont(v) if node.type is 'Program' and i == node.body.length - 1 # for eval's return value
        process.nextTick cont # avoid stack overflow
      when 'FunctionDeclaration', 'FunctionExpression'
        name = node.id?.name ? ''
        ifn = new (if node.generator then GeneratorFunction else InterpretedFunction) name, env.copy(), node
        if node.id?
          env.insert(node.id.name, ifn)
        cont(ifn)
      when 'VariableDeclaration'
        for dec in node.declarations
          await root.evaluate dec, env, defer(result), errCont
        cont()
      when 'VariableDeclarator'
        if node.init?
          await root.evaluate node.init, env, defer(init), errCont
        else
          init = undefined
        cont(env.insert node.id.name, init, env)
      when 'ExpressionStatement'
        root.evaluate node.expression, env, cont, errCont
      when 'CallExpression'
        callee = null
        if node.callee.type is 'MemberExpression'
          await evalMemberExpr node.callee, env, defer(thisArg, calleeName), errCont
          callee = thisArg[calleeName]
        else
          thisArg = undefined
          await root.evaluate node.callee, env, defer(callee), errCont
        args =
          for arg in node.arguments
            await root.evaluate arg, env, defer(argResult), errCont
            argResult
        if callee == eval
          return cont(args[0]) unless Util.isString args[0]
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
            root.evaluate ast, env, cont, errCont
          else
            root.evaluate ast, env.getGlobalEnv(), cont, errCont
        else
          if callee instanceof CPSFunction
            callee.__apply__ thisArg, args, cont, errCont
          else
            cont callee.apply thisArg, args
      when 'NewExpression'
        await root.evaluate node.callee, env, defer(callee), errCont
        args =
          for arg in node.arguments
            await root.evaluate arg, env, defer(result), errCont
            result
        if callee.__ctor__?
          obj = new callee.__ctor__
          if callee instanceof CPSFunction
            await callee.__apply__ obj, args, defer(result), errCont
          else
            callee.apply obj, args
        else
          if callee instanceof CPSFunction
            await callee.bind.__apply__ callee, ([null].concat args), defer(result), errCont
          else
            obj = new (callee.bind.apply callee, [null].concat args)
        cont(obj)
      #*** Control Flow ***#
      when 'IfStatement', 'ConditionalExpression'
        await root.evaluate node.test, env, defer(test), errCont
        if (test)
          root.evaluate node.consequent, env, cont, errCont
        else if node.alternate?
          root.evaluate node.alternate, env, cont, errCont
        else
          cont()
      when 'WhileStatement'
        while (true)
          # Test
          await root.evaluate node.test, env, defer(test), errCont
          return cont() if not test
          # Body
          await root.evaluate node.body, env, bodyCont = defer(),
            makeLoopCont(node.body, env, bodyCont, cont, errCont)
      when 'DoWhileStatement'
        while (true)
          # Body
          await root.evaluate node.body, env, bodyCont = defer(),
            makeLoopCont(node.body, env, bodyCont, cont, errCont)
          # Test
          await root.evaluate node.test, env, defer(test), errCont
          return cont() if not test
      when 'ForStatement'
        await root.evaluate node.init, env, defer(), errCont
        while (true)
          # Test
          await root.evaluate node.test, env, defer(test), errCont
          return cont() if not test
          # Body
          await root.evaluate node.body, env, bodyCont = defer(),
            makeLoopCont(node.body, env, bodyCont, cont, errCont)
          # Update
          await root.evaluate node.update, env, defer(), errCont
      when 'ForInStatement'
        await root.evaluate node.left, env, defer(), errCont
        await root.evaluate node.right, env, defer(obj), errCont
        id =
          if node.left.type is 'VariableDeclaration'
            node.left.declarations[0].id
          else
            node.left
        for k of obj
          await assign id, k, env, defer(), errCont
          await root.evaluate node.body, env, bodyCont = defer(),
            makeLoopCont(node.body, env, bodyCont, cont, errCont)
        cont()
      when 'ForOfStatement'
        await root.evaluate node.left, env, defer(), errCont
        await root.evaluate node.right, env, defer(iterable), errCont
        id =
          if node.left.type is 'VariableDeclaration'
            node.left.declarations[0].id
          else
            node.left
        await iterable.iterator.__apply__ iterable, [], defer(iterator), errCont
        while true
          await iterator.next.__apply__ iterator, [], defer(v), (e) ->
            if e instanceof StopIteration then cont() else errCont e
          await assign id, v, env, defer(), errCont
          await root.evaluate node.body, env, bodyCont = defer(),
            makeLoopCont(node.body, env, bodyCont, cont, errCont)
      when 'BreakStatement'
        errCont(new BreakException)
      when 'ContinueStatement'
        errCont(new ContinueException)
      when 'ReturnStatement'
        if node.argument is null
          errCont new ReturnException undefined
        else
          await root.evaluate node.argument, env, defer(result), errCont
          errCont new ReturnException result
      when 'ThrowStatement'
        await root.evaluate node.argument, env, defer(result), errCont
        errCont(new JSException result, node, env)
      # may be called more than once if try statement contains a yield
      when 'TryStatement'
        finalizeAndThrow = (e) ->
          if node.finalizer
            await root.evaluate node.finalizer, env, defer(), errCont
          errCont e
        finalizeAndCont = ->
          if node.finalizer
            root.evaluate node.finalizer, env, cont, errCont
          else
            cont()

        await root.evaluate node.block, env, defer(), (e) ->
          if e instanceof YieldException
            errCont e
          else if e not instanceof InterpreterException and node.handlers.length > 0
            # if the error is a JSException then we have to unwrap it
            unwrappedError = if e instanceof JSException then e.error else e
            catchEnv = env.increaseScope true
            catchEnv.set node.handlers[0].param.name, unwrappedError
            await root.evaluate node.handlers[0], env, defer(), (unwrappedError) ->
              env.decreaseScope()
              finalizeAndThrow(unwrappedError)
            env.decreaseScope()
            finalizeAndCont()
          else
            finalizeAndThrow(e)
        finalizeAndCont()
      when 'CatchClause'
        root.evaluate node.body, env, cont, errCont
      #*** Operator Expressions ***#
      when 'LogicalExpression'
        await root.evaluate node.left, env, defer(lhs), errCont
        switch node.operator
          when '&&'
            # `lhs && await ...` will not short-circuit due to a bug in IcedCoffeeScript
            if lhs then await root.evaluate node.right, env, defer(rhs), errCont
            cont(lhs && rhs)
          when '||'
            if not lhs then await root.evaluate node.right, env, defer(rhs), errCont
            cont(lhs || rhs)
          else
            errCont "Unrecognized operator #{node.operator}"
      when 'BinaryExpression'
        await root.evaluate node.left, env, defer(lhs), errCont
        await root.evaluate node.right, env, defer(rhs), errCont
        switch node.operator
          when '+'
            cont(lhs + rhs)
          when '-'
            cont(lhs - rhs)
          when '*'
            cont(lhs * rhs)
          when '/'
            cont(lhs / rhs)
          when '&'
            cont(lhs & rhs)
          when '|'
            cont(lhs | rhs)
          when '^'
            cont(lhs ^ rhs)
          when '>>'
            cont(lhs >> rhs)
          when '<<'
            cont(lhs << rhs)
          when '>>>'
            cont(lhs >>> rhs)
          when '<'
            cont(lhs < rhs)
          when '>'
            cont(lhs > rhs)
          when '<='
            cont(lhs <= rhs)
          when '>='
            cont(lhs >= rhs)
          when '=='
            cont(`lhs == rhs`)
          when '==='
            cont(`lhs === rhs`)
          when '!='
            cont(`lhs != rhs`)
          when '!=='
            cont(`lhs !== rhs`)
          when 'instanceof'
            cont(lhs instanceof (rhs?.__ctor__ ? rhs))
          else
            errCont("Unrecognized operator #{node.operator}")
      when 'AssignmentExpression'
        await root.evaluate node.right, env, defer(value), errCont
        if node.operator is '='
          assign node.left, value, env, cont, errCont
        else
          if node.left.type is 'Identifier'
            original = env.resolve node.left.name
          else if node.left.type is 'MemberExpression'
            await evalMemberExpr node.left, env, defer(object, property), errCont
            original = object[property]
          else
            errCont "Invalid LHS in assignment"
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
              errCont "Unrecognized compound assignment #{node.operator}"
          if node.left.type is 'Identifier'
            env.insert node.left.name, original
          else if node.left.type is 'MemberExpression'
            object[property] = original
          cont(original)
      when 'UpdateExpression'
        await root.evaluate node.argument, env, defer(original), errCont
        if node.operator is '++'
          newValue = original + 1
        else # '--'
          newValue = original - 1
        if node.argument.type is 'Identifier'
          env.insert node.argument.name, newValue
        else if node.argument.type is 'MemberExpression'
          await evalMemberExpr node.argument, env, defer(object, property), errCont
          object[property] = newValue
        cont(if node.prefix then newValue else original)
      when 'UnaryExpression'
        if node.operator is 'delete'
          if node.argument.type is 'MemberExpression'
            await evalMemberExpr node.argument, env, defer(object, property), errCont
            cont(delete object[property])
          else
            errCont "NYI"
        else if node.operator is 'typeof' and
            node.argument.type is 'Identifier' and not env.has node.argument.name
          cont('undefined')
        else
          await root.evaluate node.argument, env, defer(arg), errCont
          switch node.operator
            when '-'
              cont(-arg)
            when '~'
              cont(~arg)
            when '!'
              cont(!arg)
            when 'typeof'
              cont(typeof arg)
            else
              errCont("NYI")
      #*** Identifiers and Literals ***#
      when 'Identifier'
        cont(env.resolve node.name)
      when 'MemberExpression'
        await evalMemberExpr node, env, defer(object, property), errCont
        cont(object[property])
      when 'ThisExpression'
        cont(env.resolve 'this')
      when 'Literal'
        cont(node.value)
      when 'ObjectExpression'
        obj = {}
        for prop in node.properties
          await root.evaluate prop.value, env, defer(propValue), errCont
          obj[prop.key.name ? prop.key.value] = propValue
        cont(obj)
      when 'ArrayExpression'
        cont(
          for el in node.elements
            await root.evaluate el, env, defer(elValue), errCont)
      when 'YieldExpression'
        if node.delegate # yield*
          await root.evaluate node.argument, env, defer(gen), errCont
          await gen.send.__apply__ gen, [], defer(yieldValue), errCont
          while true
            rv = new iced.Rendezvous
            # depending on whether send() or throw() got called, call the same
            # method on the child generator
            errCont(new YieldException(rv.id(gen.send).defer(v),
              rv.id(gen.throw).defer(v), yieldValue))
            await rv.wait defer genFn
            await genFn.__apply__ gen, [v], defer(yieldValue), (e) ->
              if e instanceof StopIteration
                cont e.value
              else if v instanceof ReturnException
                cont()
              else
                errCont e
        else
          if node.argument?
            await root.evaluate node.argument, env, defer(yieldValue), errCont
          errCont(new YieldException cont, errCont, yieldValue)
      else
        errCont("Unrecognized node '#{node.type}'!")
  catch e
    errCont(new JSException e, node, env)

evalMemberExpr = (node, env, cont, errCont) ->
  await root.evaluate node.object, env, defer(object), errCont
  propNode = node.property
  if propNode.type is 'Identifier' and not node.computed
    cont(object, propNode.name)
  else
    await root.evaluate propNode, env, defer(property), errCont
    cont(object, property)

assign = (node, value, env, cont, errCont) ->
  if node.type is 'Identifier'
    try
      env.update node.name, value
    catch e
      env.globalInsert node.name, value
    cont(value)
  else if node.type is 'MemberExpression'
    await evalMemberExpr node, env, defer(object, property), errCont
    object[property] = value
    cont(value)
  else
    errCont("Invalid LHS in assignment")

makeLoopCont = (body, env, bodyCont, cont, errCont) ->
  (e) ->
    if e instanceof BreakException
      cont()
    else if e instanceof ContinueException
      bodyCont()
    else
      errCont(e)
