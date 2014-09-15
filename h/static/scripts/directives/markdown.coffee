# This directive controls both the rendering and display of markdown in annotations, as well as 
# the markdown editor interface.

markdown = ['$filter', '$timeout', ($filter, $timeout) ->
  link: (scope, elem, attr, ctrl) ->
    return unless ctrl?

    input = elem.find('textarea')
    output = elem.find('div')

    scope.returnSelection = ->
      # Maybe get selections from other parts of the text? Such as the quote or a reply?
      ourIframeSelection = window.getSelection().toString()
      parentDocumentSelection = parent.window.getSelection().toString()
      if input[0].selectionStart != undefined
        startPos = input[0].selectionStart
        endPos = input[0].selectionEnd
        if ourIframeSelection
          selectedText = ourIframeSelection
        else if parentDocumentSelection
          selectedText = parentDocumentSelection
        else
          selectedText = input[0].value.substring(startPos, endPos)
        textBefore = input[0].value.substring(0, (startPos))
        textAfter = input[0].value.substring(endPos)
        selection = {
          before: textBefore
          after: textAfter
          selection: selectedText
          start: startPos
          end: endPos
        }
      input.focus()
      return selection

    scope.insertBold = (markup="**", innertext="Bold")->
      text = scope.returnSelection()
      if text.selection == ""
        newtext = text.before + markup + innertext + markup + text.after
        input[0].value = newtext
        input[0].selectionStart = (text.before + markup).length
        input[0].selectionEnd = (text.before + innertext + markup).length
      else
        newtext = text.before + markup + text.selection + markup + text.after
        input[0].value = newtext
        input[0].selectionStart = (text.before + markup).length
        input[0].selectionEnd = (text.before + text.selection + markup).length

    scope.insertItalic = ->
      # Shares the same logic as insertBold() but with different markup.
      scope.insertBold("*", "Italic")

    scope.insertMath = ->
      # Shares the same logic as insertBold() but with different markup.
      scope.insertBold("$$", "LaTex")

    scope.insertLink = ->
      text = scope.returnSelection()
      if text.selection == ""
        newtext = text.before + "[Link Text](https://example.com)" + text.after
        input[0].value = newtext
        input[0].selectionStart = text.before.length + 1
        input[0].selectionEnd = text.before.length + 10
      else
        newtext = text.before + '[' + text.selection + '](https://example.com)' + text.after
        input[0].value = newtext
        input[0].selectionStart = (text.before + text.selection).length + 3
        input[0].selectionEnd = (text.before + text.selection).length + 22

    scope.insertIMG = ->
      text = scope.returnSelection()
      if text.selection == ""
        newtext = text.before + "![Image Description](https://yourimage.jpg)" + text.after
        input[0].value = newtext
        input[0].selectionStart = text.before.length + 21
        input[0].selectionEnd = text.before.length + 42
      else
        newtext = text.before + '![' + text.selection + '](https://yourimage.jpg)' + text.after
        input[0].value = newtext
        input[0].selectionStart = (text.before + text.selection).length + 4
        input[0].selectionEnd = (text.before + text.selection).length + 25

    scope.insertList = (markup = "* ") ->
      text = scope.returnSelection()
      # If the character preceeding the curser is a newline just insert a "* ".
      if text.selection != ""
        newstring = ""
        index = text.before.length
        if index == 0
          # The selection takes place at the very start of the textarea
          for char in text.selection
            if char == "\n"
              newstring = newstring + "\n" + markup
            else if index == 0
              newstring = newstring + markup + char
            else
              newstring = newstring + char
            index += 1
        else
          newlinedetected = false
          if input[0].value.substring(index - 1).charAt(0) == "\n"
            # Look to see if the selection falls at the beginning of a new line.
            newstring = newstring + markup
            newlinedetected = true
          for char in text.selection
            if char == "\n"
              newstring = newstring + "\n" + markup
              newlinedetected = true
            else
              newstring = newstring + char
            index += 1
          if not newlinedetected
            # Edge case: The selection does not include any new lines and does not start at 0.
            # We need to find the newline before the currently selected text and add markup there. 
            # console.log input[0].value.substring(0, (text.before + text.selection).length)
            i = 0
            indexoflastnewline = undefined
            newstring = ""
            for char in (text.before + text.selection)
              if char == "\n"
                indexoflastnewline = i
              newstring = newstring + char
              i++
            if indexoflastnewline == undefined
              # The partial selection happens to fall on the firstline
              newstring = markup + newstring
            else
              newstring = newstring.substring(0, (indexoflastnewline + 1)) + markup + newstring.substring(indexoflastnewline + 1)
            input[0].value = newstring + text.after
            input[0].selectionStart = (text.before + markup).length
            input[0].selectionEnd = (text.before + text.selection + markup).length
            return
        # Sets textarea value and selection for cases where there are new lines in the selection 
        # or the selection is at the start
        input[0].value = text.before + newstring + text.after
        input[0].selectionStart = (text.before + newstring).length
        input[0].selectionEnd = (text.before + newstring).length
      else if input[0].value.substring((text.start - 1 ), text.start) == "\n"
        # Edge case, no selection, the cursor is on a new line.
        input[0].value = text.before + markup + text.selection + text.after
        input[0].selectionStart = (text.before + markup).length
        input[0].selectionEnd = (text.before + markup).length
      else
        # No selection, cursor is not on new line. Go to the previous newline and insert markup there.
        i = 0
        for char in text.before
          if char == "\n" and i != 0
            index = i
          i += 1
        if !index
          # If the line of text happens to fall on the first line and index is not set.
          newtext = markup + text.before.substring(0) + text.after
        else
          newtext = text.before.substring(0, (index)) + "\n" + markup + text.before.substring(index + 1) + text.after
        input[0].value = newtext
        input[0].selectionStart = (text.before + markup).length
        input[0].selectionEnd = (text.before + markup).length

    scope.insertNumList = ->
      # Shares the same logic as insertList but with different markup.
      scope.insertList("1. ")

    scope.insertQuote = ->
      # Shares the same logic as insertList but with different markup.
      scope.insertList("> ")
      
    scope.insertCode = ->
      # Shares the same logic as insertList but with different markup.
      scope.insertList("    ")

    scope.renderMath = (textToCheck) ->
      # scope.mathOnPage = $rootScope.math
      # regEx = /\$\$/
      # searchResults = textToCheck.match regEx
      # if searchResults != -1
      #   # Only load KaTex if there is math on the page. 
      #   # $rootScope.math = true
      #   # if !scope.mathOnPage # Check to see if that we haven't loaded MathJax already.
      #   #   $.ajax { 
      #   #     url:"https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML"
      #   #     dataType: 'script'
      #   #   }
      #   # LaTex = textToCheck.substring
      #   console.log searchResults
      katex.renderToString(textToCheck, elem)

    scope.renderLaTex = (LaTex) ->
      katex.renderToString(LaTex)

    # Keyboard shortcuts for bold, italic, and link.
    elem.bind
      keydown: (e) ->
        if e.keyCode == 66 && (e.ctrlKey || e.metaKey)
          e.preventDefault()
          scope.insertBold()
        if e.keyCode == 73 && (e.ctrlKey || e.metaKey)
          e.preventDefault()
          scope.insertItalic()
        if e.keyCode == 75 && (e.ctrlKey || e.metaKey)
          e.preventDefault()
          scope.insertLink()

    scope.preview = false
    scope.togglePreview = ->
      if !scope.readonly
        scope.preview = !scope.preview
        if scope.preview
          output[2].style.height = input[0].style.height
          ctrl.$render()
        else
          input[0].style.height = output[2].style.height
          $timeout -> input.focus()

    # Re-render the markdown when the view needs updating.
    ctrl.$render = ->
      input.val (ctrl.$viewValue or '')
      scope.rendered = ($filter 'converter') scope.renderMath((ctrl.$viewValue or ''))

    # React to the changes to the text area
    input.bind 'blur change keyup', ->
      ctrl.$setViewValue input.val()
      scope.$digest()

    # Reset height of output div incase it has been changed.
    # Re-render when it becomes uneditable.
    # Auto-focus the input box when the widget becomes editable.
    scope.$watch 'readonly', (readonly) ->
      scope.preview = false
      output[2].style.height = ""
      ctrl.$render()
      unless readonly then $timeout -> input.focus()

  require: '?ngModel'
  restrict: 'E'
  scope:
    readonly: '@'
    required: '@'
  templateUrl: 'markdown.html'
]

angular.module('h.directives').directive('markdown', markdown)
