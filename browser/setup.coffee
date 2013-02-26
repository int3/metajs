$(document).ready ->
  CodeMirror.fromTextArea(document.getElementById('code'), mode: 'javascript', readOnly: true)
