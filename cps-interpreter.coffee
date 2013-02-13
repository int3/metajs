#! /usr/bin/env iced

fs = require 'fs'
esprima = require 'esprima'
{Util} = require './util/util'
{interpreterGlobal, InterpreterException, ReturnException, BreakException,
  ContinueException, JSException, Environment} = require './util/interp-util'

class InterpretedFunction
  constructor: (@__ctor__, @__call__) ->
    @prototype = @__ctor__.prototype

  apply: (thisArg, args) ->
    await this.applyCps thisArg, args, defer(result), errCont
    return result

  applyCps: (appliedThis, args, cont, errCont) ->
    calleeNode = this.__call__
    calleeNode.env.increaseScope()
    argsObject = {}
    calleeNode.env.insert "arguments", argsObject
    for arg, i in args
      calleeNode.env.insert calleeNode.params[i].name, arg
      argsObject[i] = arg
    Util.defineNonEnumerable argsObject, 'length', args.length
    calleeNode.env.insert 'this', appliedThis
    await interp calleeNode.body, calleeNode.env, defer(result), (e) ->
      if e instanceof ReturnException
        calleeNode.env.decreaseScope()
        cont(e.value)
      else
        errCont(e)
    calleeNode.env.decreaseScope()
    cont(result)

  call: (thisArg) -> @apply thisArg, Array::slice arguments, 1

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
        node.env = env.copy()
        fn = (new Function "return function #{node.id?.name ? ''}() {}")()
        ifn = new InterpretedFunction fn, node
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
        args = []
        for arg in node.arguments
          await interp arg, env, defer(argResult), errCont
          args.push(argResult)
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
          if callee instanceof InterpretedFunction
            callee.applyCps thisArg, args, cont, errCont
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
          if callee instanceof InterpretedFunction
            await callee.applyCps obj, args, defer(result), errCont
          else
            callee.apply obj, args
        else
          if callee instanceof InterpretedFunction
            await callee.bind.applyCps callee, ([null].concat args), defer(result), errCont
          else
            obj = new (callee.bind.apply callee, [null].concat args)
        cont(obj)
      #*** Control Flow ***#
      when 'IfStatement'
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
          await interp node.test env, defer(test), errCont
          return cont() if not test
          # Body
          await
            interp node.body, env, bodyCont = defer(),
              makeLoopCont(node.body, env, bodyCont, cont, errCont)
      when 'DoWhileStatement'
        while (true)
          # Body
          await
            interp node.body, env, bodyCont = defer(),
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
          await
            interp node.body, env, bodyCont = defer(),
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
          await
            interp node.body, env, bodyCont = defer(),
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
        errCont new JSException result, node
      when 'TryStatement'
        interp node.block, env, cont, (e) ->
          if e instanceof JSException and node.handlers.length > 0
            catchEnv = env.increaseScope true
            catchEnv.set node.handlers[0].param.name, e.exception
            await interp node.handlers[0], env, defer(), errCont
            env.decreaseScope()
          if node.finalizer
            interp node.finalizer, env, cont, errCont
          else
            cont()
      when 'CatchClause'
        await interp node.body, env, cont, errCont
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
      else
        errCont("Unrecognized node '#{node.name}'!")
  catch e
    errCont(new JSException e, node)

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
        if(e instanceof JSException)
          console.log("Line #{e.node.loc.start.line}: Error in #{e.node.type}")
        callback(e?.exception ? e)

if require.main is module
  {argv} = require 'optimist'
  if argv._.length < 1
    toplevel()
  else
    parsed = esprima.parse (fs.readFileSync argv._[0]), loc: true
    # interp parsed, new Environment
    interp parsed, new Environment, (->), (e) ->
      console.log "Error: ", e.exception ? e
      process.exit 1
