#! /usr/bin/env iced

fs = require 'fs'
esprima = require 'esprima'
{Util} = require './util/util'
{interpreterGlobal, InterpreterException, ReturnException, BreakException,
  ContinueException, Environment} = require './util/interp-util'

class YieldException extends InterpreterException
  constructor: (@cont, @errCont, @value) ->

class StopIteration
  constructor: (@value) ->
  toString: -> "StopIteration"

Util.defineNonEnumerable interpreterGlobal, 'StopIteration', StopIteration

makeArgsObject = (argsArray) ->
  argsObject = {}
  argsObject[i] = arg for arg, i in argsArray
  Util.defineNonEnumerable argsObject, 'length', argsArray.length

class CPSFunction
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
    await interp @__node__.body, @__env__, defer(result), (e) =>
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
        await interp thisArg.__node__.body, thisArg.__env__, bodyCont = defer(rv), (e) ->
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

  iterate: -> @

interp = (node, env=new Environment, cont, errCont) ->
  try
    switch node.type
      when 'Program', 'BlockStatement'
        for stmt, i in node.body
          env.strict ||= i == 0 and stmt.expression?.value is 'use strict'
          await interp stmt, env, defer(v), errCont
          return cont(v) if node.type is 'Program' and i == node.body.length - 1 # for eval's return value
        setTimeout cont(), 0 # avoid stack overflow
      when 'FunctionDeclaration', 'FunctionExpression'
        name = node.id?.name ? ''
        ifn = new (if node.generator then GeneratorFunction else InterpretedFunction) name, env.copy(), node
        if node.id?
          env.insert(node.id.name, ifn)
        cont(ifn)
      when 'VariableDeclaration'
        for dec in node.declarations
          await interp dec, env, defer(result), errCont
        cont()
      when 'VariableDeclarator'
        if node.init?
          await interp node.init, env, defer(init), errCont
        else
          init = undefined
        cont(env.insert node.id.name, init, env)
      when 'ExpressionStatement'
        interp node.expression, env, cont, errCont
      when 'CallExpression'
        callee = null
        if node.callee.type is 'MemberExpression'
          await evalMemberExpr node.callee, env, defer(thisArg, calleeName), errCont
          callee = thisArg[calleeName]
        else
          thisArg = undefined
          await interp node.callee, env, defer(callee), errCont
        args =
          for arg in node.arguments
            await interp arg, env, defer(argResult), errCont
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
            interp ast, env, cont, errCont
          else
            interp ast, env.getGlobalEnv(), cont, errCont
        else
          if callee instanceof CPSFunction
            callee.__apply__ thisArg, args, cont, errCont
          else
            cont callee.apply thisArg, args
      when 'NewExpression'
        await interp node.callee, env, defer(callee), errCont
        args =
          for arg in node.arguments
            await interp arg, env, defer(result), errCont
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
        await interp node.test, env, defer(test), errCont
        if (test)
          interp node.consequent, env, cont, errCont
        else if node.alternate?
          interp node.alternate, env, cont, errCont
        else
          cont()
      when 'WhileStatement'
        while (true)
          # Test
          await interp node.test, env, defer(test), errCont
          return cont() if not test
          # Body
          await interp node.body, env, bodyCont = defer(),
            makeLoopCont(node.body, env, bodyCont, cont, errCont)
      when 'DoWhileStatement'
        while (true)
          # Body
          await interp node.body, env, bodyCont = defer(),
            makeLoopCont(node.body, env, bodyCont, cont, errCont)
          # Test
          await interp node.test, env, defer(test), errCont
          return cont() if not test
      when 'ForStatement'
        await interp node.init, env, defer(), errCont
        while (true)
          # Test
          await interp node.test, env, defer(test), errCont
          return cont() if not test
          # Body
          await interp node.body, env, bodyCont = defer(),
            makeLoopCont(node.body, env, bodyCont, cont, errCont)
          # Update
          await interp node.update, env, defer(), errCont
      when 'ForInStatement'
        await interp node.left, env, defer(), errCont
        await interp node.right, env, defer(obj), errCont
        for k of obj
          if node.left.type is 'VariableDeclaration'
            await assign node.left.declarations[0].id, k, env, defer(), errCont
          else
            await assign node.left, k, env, defer(), errCont
          await interp node.body, env, bodyCont = defer(),
            makeLoopCont(node.body, env, bodyCont, cont, errCont)
        cont()
      when 'BreakStatement'
        errCont(new BreakException)
      when 'ContinueStatement'
        errCont(new ContinueException)
      when 'ReturnStatement'
        if node.argument is null
          errCont new ReturnException undefined
        else
          await interp node.argument, env, defer(result), errCont
          errCont new ReturnException result
      when 'ThrowStatement'
        await interp node.argument, env, defer(result), errCont
        errCont result
      # may be called more than once if try statement contains a yield
      when 'TryStatement'
        finalizeAndThrow = (e) ->
          if node.finalizer
            await interp node.finalizer, env, defer(), errCont
          errCont e
        finalizeAndCont = ->
          if node.finalizer then interp node.finalizer, env, cont, errCont else cont()

        await interp node.block, env, defer(), (e) ->
          if e instanceof YieldException
            errCont e
          else if e not instanceof InterpreterException and node.handlers.length > 0
            catchEnv = env.increaseScope true
            catchEnv.set node.handlers[0].param.name, e
            await interp node.handlers[0], env, defer(), (e) ->
              env.decreaseScope()
              finalizeAndThrow(e)
            env.decreaseScope()
            finalizeAndCont()
          else
            finalizeAndThrow(e)
        finalizeAndCont()
      when 'CatchClause'
        interp node.body, env, cont, errCont
      #*** Operator Expressions ***#
      when 'LogicalExpression'
        await interp node.left, env, defer(lhs), errCont
        switch node.operator
          when '&&'
            # `lhs && await ...` will not short-circuit due to a bug in IcedCoffeeScript
            if lhs then await interp node.right, env, defer(rhs), errCont
            cont(lhs && rhs)
          when '||'
            if not lhs then await interp node.right, env, defer(rhs), errCont
            cont(lhs || rhs)
          else
            errCont "Unrecognized operator #{node.operator}"
      when 'BinaryExpression'
        await interp node.left, env, defer(lhs), errCont
        await interp node.right, env, defer(rhs), errCont
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
        await interp node.right, env, defer(value), errCont
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
        await interp node.argument, env, defer(original), errCont
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
          await interp node.argument, env, defer(arg), errCont
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
          await interp prop.value, env, defer(propValue), errCont
          obj[prop.key.name ? prop.key.value] = propValue
        cont(obj)
      when 'ArrayExpression'
        cont(
          for el in node.elements
            await interp el, env, defer(elValue), errCont)
      when 'YieldExpression'
        if node.delegate # yield*
          await interp node.argument, env, defer(gen), errCont
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
          if node.argument? then await interp node.argument, env, defer(yieldValue), errCont
          errCont(new YieldException cont, errCont, yieldValue)
      else
        errCont("Unrecognized node '#{node.type}'!")
  catch e
    errCont e

evalMemberExpr = (node, env, cont, errCont) ->
  await interp node.object, env, defer(object), errCont
  propNode = node.property
  if propNode.type is 'Identifier' and not node.computed
    cont(object, propNode.name)
  else
    await interp propNode, env, defer(property), errCont
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

toplevel = ->
  repl = require 'repl'
  env = new Environment
  repl.start
    eval: (cmd, ctx, filename, callback) ->
      await interp (esprima.parse cmd[1..-2], loc: true), env, callback, (e) ->
        callback("Error: #{e}")

if require.main is module
  {argv} = require 'optimist'
  if argv._.length < 1
    toplevel()
  else
    parsed = esprima.parse (fs.readFileSync argv._[0]), loc: true
    # interp parsed, new Environment
    interp parsed, new Environment, (->), (e) ->
      console.log "Error: #{e}"
      process.exit 1
