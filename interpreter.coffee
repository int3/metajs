#! /usr/bin/env coffee

fs = require 'fs'
esprima = require 'esprima'
{Util} = require './util/util'
{interpreterGlobal, InterpreterException, ReturnException, BreakException,
  ContinueException, JSException, Environment} = require './util/interp-util'

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
    Util.defineNonEnumerable argsObject, 'length', args.length
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
          return v if node.type is 'Program' and i == node.body.length - 1 # for eval's return value
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
          [_this, calleeName] = evalMemberExpr node.callee, env
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
      when 'ForInStatement'
        interp node.left, env
        obj = interp node.right, env
        for k of obj
          if node.left.type is 'VariableDeclaration'
            assign node.left.declarations[0].id, k, env
          else
            assign node.left, k, env
          interp node.body, env
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
        if node.operator is '='
          assign node.left, value, env
        else
          if node.left.type is 'Identifier'
            original = env.resolve node.left.name
          else if node.left.type is 'MemberExpression'
            [object, property] = evalMemberExpr node.left, env
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
          [object, property] = evalMemberExpr node.argument, env
          object[property] = newValue
        if node.prefix then newValue else original
      when 'UnaryExpression'
        if node.operator is 'delete'
          if node.argument.type is 'MemberExpression'
            [object, property] = evalMemberExpr node.argument, env
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
        [object, property] = evalMemberExpr node, env
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

evalMemberExpr = (node, env) ->
  object = interp node.object, env
  propNode = node.property
  property =
    if propNode.type is 'Identifier' and not node.computed
      propNode.name
    else
      interp propNode, env
  [object, property]

assign = (node, value, env) ->
  if node.type is 'Identifier'
    try
      env.update node.name, value
    catch e
      env.globalInsert node.name, value
  else if node.type is 'MemberExpression'
    [object, property] = evalMemberExpr node, env
    object[property] = value
  else
    throw "Invalid LHS in assignment"

if require.main is module
  {argv} = require 'optimist'
  if argv._.length < 1
    console.log "Usage: interp.coffee [filename]"
    process.exit 1
  interp esprima.parse (fs.readFileSync argv._[0]), loc: true
