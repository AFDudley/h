formInput = ->
  link: (scope, elem, attr, [form, model, validator]) ->
    return unless form?.$name and model?.$name and validator

    fieldClassName = 'form-field'
    errorClassName = 'form-field-error'

    render = model.$render

    resetResponse = (value) ->
      model.$setValidity('response', true)
      value

    toggleClass = (addClass) ->
      elem.toggleClass(errorClassName, addClass)
      elem.parent().toggleClass(errorClassName, addClass)

    model.$parsers.unshift(resetResponse)
    model.$render = ->
      toggleClass(model.$invalid and model.$dirty)
      render()

    validator.addControl(model)
    scope.$on '$destroy', -> validator.removeControl this

    scope.$watch ->
      if model.$modelValue? or model.$pristine
        model.$render()
      return

  require: ['^?form', '?ngModel', '^?formValidate']
  restrict: 'C'


formValidate = ->
  controller: ->
    controls = {}

    addControl: (control) ->
      if control.$name
        controls[control.$name] = control

    removeControl: (control) ->
      if control.$name
        delete controls[control.$name]

    submit: ->
      # make all the controls dirty and re-render them
      for _, control of controls
        control.$setViewValue(control.$viewValue)
        control.$render()

  link: (scope, elem, attr, ctrl) ->
    elem.on 'submit', ->
      ctrl.submit()


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
        input[0].selectionStart = (text.before.length + markup.length)
        input[0].selectionEnd = (text.before.length + innertext.length + markup.length)
      else
        newtext = text.before + markup + text.selection + markup + text.after
        input[0].value = newtext

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
        input[0].selectionStart = (text.before.length + 1)
        input[0].selectionEnd = (text.before.length + 10)
      else
        newtext = text.before + '[' + text.selection + '](https://example.com)' + text.after
        input[0].value = newtext
        input[0].selectionStart = (text.before.length + text.selection.length + 3)
        input[0].selectionEnd = (text.before.length + text.selection.length + 22)

    scope.insertIMG = ->
      text = scope.returnSelection()
      if text.selection == ""
        newtext = text.before + "![Image Description](https://yourimage.jpg)" + text.after
        input[0].value = newtext
        input[0].selectionStart = (text.before.length + 21)
        input[0].selectionEnd = (text.before.length + 42)
      else
        newtext = text.before + '![' + text.selection + '](https://yourimage.jpg)' + text.after
        input[0].value = newtext
        input[0].selectionStart = (text.before.length + text.selection.length + 4)
        input[0].selectionEnd = (text.before.length + text.selection.length + 25)

    scope.insertList = (markup = "* ") ->
      text = scope.returnSelection()
      # If the character preceeding the curser is a newline just insert a "* ".
      if text.selection != ""
        newstring = ""
        index = text.before.length
        if index != 0
          if input[0].value.substring(index - 1).charAt(0) == "\n"
            # Look to see if the selection falls at the beginning of a new line.
            newstring = newstring + markup
          for char in text.selection
            if char == "\n"
              newstring = newstring + "\n" + markup
            else
              newstring = newstring + char
            index += 1
        else
          for char in text.selection
            if char == "\n"
              newstring = newstring + "\n" + markup
            else if index == 0
              newstring = newstring + markup + char
            else
              newstring = newstring + char
            index += 1
        input[0].value = text.before + newstring + text.after
        input[0].selectionStart = text.before.length + newstring.length
        input[0].selectionEnd = text.before.length + newstring.length
      else if input[0].value.substring((text.start - 1 ), text.start) == "\n"
        input[0].value = text.before + markup + text.selection + text.after
        input[0].selectionStart = text.before.length + markup.length
        input[0].selectionEnd = text.before.length + markup.length
      else
        # If not a new line, go to the previous newline and insert a "* " there.
        i = 0
        for char in text.before
          if char == "\n" and i != 0
            index = i
            console.log index
          i += 1
        if !index
          # If the line of text happens to fall on the first line and index is not set.
          newtext = markup + text.before.substring(0) + text.after
        else
          newtext = text.before.substring(0, (index)) + "\n" + markup + text.before.substring(index + 1) + text.after
        input[0].value = newtext
        input[0].selectionStart = text.before.length + markup.length
        input[0].selectionEnd = text.before.length + markup.length

    scope.insertNumList = ->
      # Shares the same logic as insertList but with different markup.
      scope.insertList("1. ")

    scope.insertQuote = ->
      # Shares the same logic as insertList but with different markup.
      scope.insertList("> ")
      
    scope.insertCode = ->
      # Shares the same logic as insertList but with different markup.
      scope.insertList("    ")

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
      scope.preview = !scope.preview
      if scope.preview
        ctrl.$render()

    # Re-render the markdown when the view needs updating.
    ctrl.$render = ->
      input.val (ctrl.$viewValue or '')
      scope.rendered = ($filter 'converter') (ctrl.$viewValue or '')

    # React to the changes to the text area
    input.bind 'blur change keyup', ->
      ctrl.$setViewValue input.val()
      scope.$digest()

    # Auto-focus the input box when the widget becomes editable.
    # Re-render when it becomes uneditable.
    scope.$watch 'readonly', (readonly) ->
      ctrl.$render()
      unless readonly then $timeout -> input.focus()

  require: '?ngModel'
  restrict: 'E'
  scope:
    readonly: '@'
    required: '@'
  templateUrl: 'markdown.html'
]


privacy = ->
  levels = ['Public', 'Only Me']

  link: (scope, elem, attrs, controller) ->
    return unless controller?

    controller.$formatters.push (permissions) ->
      return unless permissions?

      if 'group:__world__' in (permissions.read or [])
        'Public'
      else
        'Only Me'

    controller.$parsers.push (privacy) ->
      return unless privacy?

      permissions = controller.$modelValue
      if privacy is 'Public'
        if permissions.read
          unless 'group:__world__' in permissions.read
            permissions.read.push 'group:__world__'
        else
          permissions.read = ['group:__world__']
      else
        read = permissions.read or []
        read = (role for role in read when role isnt 'group:__world__')
        permissions.read = read

      permissions

    controller.$render = ->
      scope.level = controller.$viewValue

    scope.levels = levels
    scope.setLevel = (level) ->
      controller.$setViewValue level
      controller.$render()
  require: '?ngModel'
  restrict: 'E'
  scope: {}
  templateUrl: 'privacy.html'


recursive = ['$compile', '$timeout', ($compile, $timeout) ->
  compile: (tElement, tAttrs, transclude) ->
    placeholder = angular.element '<!-- recursive -->'
    attachQueue = []
    tick = false

    template = tElement.contents().clone()
    tElement.html ''

    transclude = $compile template, (scope, cloneAttachFn) ->
      clone = placeholder.clone()
      cloneAttachFn clone
      $timeout ->
        transclude scope, (el, scope) -> attachQueue.push [clone, el]
        unless tick
          tick = true
          requestAnimationFrame ->
            tick = false
            for [clone, el] in attachQueue
              clone.after el
              clone.bind '$destroy', -> el.remove()
            attachQueue = []
      clone
    post: (scope, iElement, iAttrs, controller) ->
      transclude scope, (contents) -> iElement.append contents
  restrict: 'A'
  terminal: true
]


tabReveal = ['$parse', ($parse) ->
  compile: (tElement, tAttrs, transclude) ->
    panes = []
    hiddenPanesGet = $parse tAttrs.tabReveal

    pre: (scope, iElement, iAttrs, [ngModel, tabbable] = controller) ->
      # Hijack the tabbable controller's addPane so that the visibility of the
      # secret ones can be managed. This avoids traversing the DOM to find
      # the tab panes.
      addPane = tabbable.addPane
      tabbable.addPane = (element, attr) =>
        removePane = addPane.call tabbable, element, attr
        panes.push
          element: element
          attr: attr
        =>
          for i in [0..panes.length]
            if panes[i].element is element
              panes.splice i, 1
              break
          removePane()

    post: (scope, iElement, iAttrs, [ngModel, tabbable] = controller) ->
      tabs = angular.element(iElement.children()[0].childNodes)
      render = angular.bind ngModel, ngModel.$render

      ngModel.$render = ->
        render()
        hiddenPanes = hiddenPanesGet scope
        return unless angular.isArray hiddenPanes

        for i in [0..panes.length-1]
          pane = panes[i]
          value = pane.attr.value || pane.attr.title
          if value == ngModel.$viewValue
            pane.element.css 'display', ''
            angular.element(tabs[i]).css 'display', ''
          else if value in hiddenPanes
            pane.element.css 'display', 'none'
            angular.element(tabs[i]).css 'display', 'none'
  require: ['ngModel', 'tabbable']
]


thread = ['$rootScope', '$window', ($rootScope, $window) ->
  # Helper -- true if selection ends inside the target and is non-empty
  ignoreClick = (event) ->
    sel = $window.getSelection()
    if sel.focusNode?.compareDocumentPosition(event.target) & 8
      if sel.toString().length
        return true
    return false

  link: (scope, elem, attr, ctrl) ->
    childrenEditing = {}

    # If this is supposed to be focused, then open it
    if scope.annotation in ($rootScope.focused or [])
      scope.collapsed = false

    scope.$on "focusChange", ->
      # XXX: This not needed to be done when the viewer and search will be unified
      ann = scope.annotation ? scope.thread.message
      if ann in $rootScope.focused
        scope.collapsed = false
      else
        unless ann.references?.length
          scope.collapsed = true

    scope.toggleCollapsed = (event) ->
      event.stopPropagation()
      return if (ignoreClick event) or Object.keys(childrenEditing).length
      scope.collapsed = !scope.collapsed
      # XXX: This not needed to be done when the viewer and search will be unified
      ann = scope.annotation ? scope.thread.message
      if scope.collapsed
        $rootScope.unFocus ann, true
      else
        scope.openDetails ann
        $rootScope.focus ann, true

    scope.$on 'toggleEditing', (event) ->
      {$id, editing} = event.targetScope
      if editing
        scope.collapsed = false
        unless childrenEditing[$id]
          event.targetScope.$on '$destroy', ->
            delete childrenEditing[$id]
          childrenEditing[$id] = true
      else
        delete childrenEditing[$id]
  restrict: 'C'
]


# TODO: Move this behaviour to a route.
showAccount = ->
  restrict: 'A'
  link: (scope, elem, attr) ->
    elem.on 'click', (event) ->
      event.preventDefault()
      scope.$emit('nav:account')


repeatAnim = ->
  restrict: 'A'
  scope:
    array: '='
  template: '<div ng-init="runAnimOnLast()"><div ng-transclude></div></div>'
  transclude: true

  controller: ($scope, $element, $attrs) ->
    $scope.runAnimOnLast = ->
      #Run anim on the item's element
      #(which will be last child of directive element)
      item=$scope.array[0]
      itemElm = jQuery($element)
        .children()
        .first()
        .children()

      unless item._anim?
        return
      if item._anim is 'fade'
        itemElm
          .css({ opacity: 0 })
          .animate({ opacity: 1 }, 1500)
      else
        if item._anim is 'slide'
          itemElm
            .css({ 'margin-left': itemElm.width() })
            .animate({ 'margin-left': '0px' }, 1500)
      return


username = ['$filter', '$window', ($filter, $window) ->
  link: (scope, elem, attr) ->
    scope.$watch 'user', ->
      scope.uname = $filter('persona')(scope.user, 'username')

    scope.uclick = (event) ->
      event.preventDefault()
      $window.open "/u/#{scope.uname}"
      return

  scope:
    user: '='
  restrict: 'E'
  template: '<span class="user" ng-click="uclick($event)">{{uname}}</span>'
]

fuzzytime = ['$filter', '$window', ($filter, $window) ->
  link: (scope, elem, attr, ctrl) ->
    return unless ctrl?

    elem
    .find('a')
    .bind 'click', (event) ->
      event.stopPropagation()

    ctrl.$render = ->
      scope.ftime = ($filter 'fuzzyTime') ctrl.$viewValue

      # Determining the timezone name
      timezone = jstz.determine().name()
      # The browser language
      userLang = navigator.language || navigator.userLanguage

      # Now to make a localized hint date, set the language
      momentDate = moment ctrl.$viewValue
      momentDate.lang(userLang)

      # Try to localize to the browser's timezone
      try
        scope.hint = momentDate.tz(timezone).format('LLLL')
      catch error
        # For invalid timezone, use the default
        scope.hint = momentDate.format('LLLL')

    timefunct = ->
      $window.setInterval =>
        scope.ftime = ($filter 'fuzzyTime') ctrl.$viewValue
        scope.$digest()
      , 5000

    scope.timer = timefunct()

    scope.$on '$destroy', ->
      $window.clearInterval scope.timer

  require: '?ngModel'
  restrict: 'E'
  scope: true
  template: '<a target="_blank" href="{{shared_link}}" title="{{hint}}">{{ftime | date:mediumDate}}</a>'
]

whenscrolled = ->
  link: (scope, elem, attr) ->
    elem.bind 'scroll', ->
      {clientHeight, scrollHeight, scrollTop} = elem[0]
      if scrollHeight - scrollTop <= clientHeight + 40
        scope.$apply attr.whenscrolled

match = ->
  link: (scope, elem, attr, input) ->
    validate = ->
      scope.$evalAsync ->
        input.$setValidity('match', scope.match == input.$modelValue)

    elem.on('keyup', validate)
    scope.$watch('match', validate)
  scope:
    match: '='
  restrict: 'A'
  require: 'ngModel'


angular.module('h.directives', ['ngSanitize', 'ngTagsInput'])
.directive('formInput', formInput)
.directive('formValidate', formValidate)
.directive('fuzzytime', fuzzytime)
.directive('markdown', markdown)
.directive('privacy', privacy)
.directive('recursive', recursive)
.directive('tabReveal', tabReveal)
.directive('thread', thread)
.directive('username', username)
.directive('showAccount', showAccount)
.directive('repeatAnim', repeatAnim)
.directive('whenscrolled', whenscrolled)
.directive('match', match)
