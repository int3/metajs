esprima = require 'esprima'
{Util} = require './lib/util'
interpreter = require './lib/interpreter'
{Environment} = interpreter

Message = do ->
  messageMap = {}
  silence = {}
  {
    listen: (msg, cb) -> (messageMap[msg] ?= []).push cb
    once: (msg, cb) ->
      @listen msg, (args) ->
        cb args...
        for fn, i in messageMap[msg]
          if fn is cb
            messageMap[msg].splice i, 1
            break
    squelch: (msg) -> silence[msg] = true
    unsquelch: (msg) -> delete silence[msg]
    send: (msg, args...) ->
      return if msg of silence
      for cb in messageMap[msg]
        cb args...
  }

activeStates = []

await $(document).ready defer()

Continuers =
  toFinish: (cont, v) -> cont v
  toNextStep: (cont, v) ->
    if cont is Continuations.bottom
      cont v
    else
      Continuations.next = -> cont v
  autoStep: (cont, v) ->
    await setTimeout defer(), 400
    cont v

interpreter.evaluate = do (original = interpreter.evaluate) ->
  interpreter.continuer = -> Continuers.toFinish
  (node, env, cont, errCont) ->
    Message.send 'interpreter:eval', node, env, cont
    newCont = (v) ->
      Message.send 'interpreter:continue', node, env, cont, v
      await interpreter.continuer defer(w), v
      Message.send 'interpreter:call-continue'
      cont w
    original node, env, newCont, errCont

Message.listen 'interpreter:eval', (node, env, cont) ->
  cont.id = activeStates.length
  activeStates.push {node, env}

Message.listen 'interpreter:continue', (node, env, cont, v) ->
  activeStates.length = cont.id + 1
  Util.last(activeStates).value = v
  Message.send 'state:render'

Message.listen 'interpreter:call-continue', ->
  activeStates.pop()

Message.listen 'interpreter:done', -> Message.send 'state:render'

editor = $('.CodeMirror')[0].CodeMirror

editor.disableEditing = () ->
  if not $('.CodeMirror').hasClass('readOnly')
    editor.setOption('readOnly', true)
    $('.CodeMirror').addClass('readOnly')

editor.enableEditing = () ->
  if $('.CodeMirror').hasClass('readOnly')
    editor.setOption('readOnly', false)
    $('.CodeMirror').removeClass('readOnly')

editor.on 'change', ->
  activeStates = []
  Message.send 'state:render'
  Continuations.bottom()

editor.on 'focus', ->
  mark.clear() if (mark = $('#code').data('mark'))?

loadFile = ->
  url = $('#example-box option:selected')[0].getAttribute('href')
  await $.ajax(url:url,dataType:'text').done defer(data)
  editor.setValue data

$('#example-box').change loadFile

loadFile()

class Continuations
  @bottom: =>
    Message.send 'interpreter:done'
    @next = @top

  @top: =>
    ast = esprima.parse editor.getValue(), loc: true
    interpreter.evaluate ast, new Environment, @bottom, (e) =>
      console.log "Error: #{e}", @bottom()

  @next: @top

RenderUtils =
  pprintNode: (node) ->
    switch node.type
      when 'Identifier'
        "Identifier '#{node.name}'"
      when 'VariableDeclarator'
        "VariableDeclarator '#{node.id.name}'"
      else
        node.type

  pprintValue: (value) ->
    if value instanceof interpreter.CPSFunction or typeof value is 'function'
      'function'
    else if value is null or value is undefined
      $('<span>', text: value + '', class: 'atom-value')
    else if typeof value is 'number'
      $('<span>', text: value, class: 'number-value')
    else if typeof value is 'object'
      a = $('<a>', text: value, href: '#', class:'object')
      a.data 'value', value
    else
      value + ""

  htmlifyObject: (obj) ->
    rv = $("<div>")
    for k,v of obj
      rv.append "#{k}: ", (@pprintValue v), "<br/>"
    if rv.html() is ''
      rv.append "No enumerable properties found"
    else
      rv

  selectionFromNode: (node) ->
    {start, end} = node.loc
    [{line:start.line-1,ch:start.column}, {line:end.line-1,ch:end.column}]

Message.listen 'state:render', ->
  activeStatesDisplay = $('#activeStates > ul')
  activeStatesDisplay.html('')
  for state in activeStates
    content = $('<span>', text: (RenderUtils.pprintNode state.node), class:'node')
    content.data 'node', state.node
    li = activeStatesDisplay.append $('<li>', html: content)
    content.after " &rarr; #{RenderUtils.pprintValue state.value}" if state.value

  envDisplay = $('#currentEnv')
  envDisplay.html ''

  unless activeStates.length > 0
    editor.setSelection editor.getCursor() # deselect
  else
    mark.clear() if (mark = $('#code').data('mark'))?
    latest = Util.last(activeStates)
    $('#code').data 'mark',
      editor.markText (RenderUtils.selectionFromNode latest.node)..., className: 'execlight'
    for scope in latest.env.scopeChain
      envDisplay.append $('<div>', html: ul = $('<ul>'))
      for [k,v] in scope.items()
        ul.append $('<li>', html: "#{k} &rarr; ").append(RenderUtils.pprintValue v)

$('#activeStates').on 'mouseover', 'li > span.node', ->
  mark = editor.markText (RenderUtils.selectionFromNode $(@).data 'node')..., className: 'mouselight'
  $('#activeStates').one 'mouseout', 'li > span.node', -> mark.clear()

$('#currentEnv, #modalContent').on 'click', 'a.object', ->
   $('#modalContent').html(RenderUtils.htmlifyObject  $(@).data 'value')
   $('#modal').show()

$(document).keydown (e) ->
  if e.keyCode is 27 # ESC
    $('#modal').hide()

$('#modalClose').click -> $('#modal').hide()

$('#run-btn').click ->
  editor.disableEditing()
  interpreter.continuer = Continuers.toFinish
  Message.squelch 'state:render' # optimization
  latestState = null
  Message.listen 'interpreter:continue', (node, env, cont, v) ->
    latestState = {node,env}
  Message.once 'interpreter:done', ->
    Message.unsquelch 'state:render'
    activeStates.push latestState
    Message.send 'state:render'
    activeStates.pop()
  Continuations.next()

$('#step-btn').click ->
  editor.disableEditing()
  interpreter.continuer = Continuers.toNextStep
  Continuations.next()

$('#auto-step-btn').click ->
  editor.disableEditing()
  if $(@).attr('value') is 'Pause'
    interpreter.continuer = Continuers.toNextStep
    $(@).attr 'value', 'Auto Step'
    $('#example-box').removeAttr 'disabled'
    $('#step-btn').removeAttr 'disabled'
    $('#run-btn').removeAttr 'disabled', 'disabled'
  else
    interpreter.continuer = Continuers.autoStep
    $(@).attr 'value', 'Pause'
    $('#example-box').attr 'disabled', 'disabled'
    $('#step-btn').attr 'disabled', 'disabled'
    $('#run-btn').attr 'disabled', 'disabled'
    Continuations.next()

Message.listen 'interpreter:done', -> 
  $('#auto-step-btn').removeAttr 'disabled'
  $('#example-box').removeAttr 'disabled'
  $('#step-btn').removeAttr 'disabled'
  $('#run-btn').removeAttr 'disabled'
  $('#auto-step-btn').attr 'value', 'Auto Step'
  editor.enableEditing()

