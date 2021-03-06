assert = chai.assert
sinon.assert.expose assert, prefix: null

describe 'h', ->
  $scope = null
  fakeIdentity = null
  fakeLocation = null
  fakeParams = null
  fakeSocket = null
  sandbox = null

  beforeEach module('h')

  beforeEach module ($provide) ->
    sandbox = sinon.sandbox.create()

    fakeAnnotator = {
      plugins: {
        Auth: {withToken: sandbox.spy()}
      }
      options: {}
      socialView: {name: 'none'}
      addPlugin: sandbox.spy()
    }
    fakeIdentity = {
      watch: sandbox.spy()
      request: sandbox.spy()
    }
    fakeLocation = {
      search: sandbox.stub().returns({})
    }
    fakeParams = {id: 'test'}
    fakeSocket = sandbox.stub().returns({
      onclose: null
      close: sandbox.spy()
    })

    $provide.value 'annotator', fakeAnnotator
    $provide.value 'identity', fakeIdentity
    $provide.value 'socket', fakeSocket
    $provide.value '$location', fakeLocation
    $provide.value '$routeParams', fakeParams
    return

  afterEach ->
    sandbox.restore()

  describe 'AppController', ->
    createController = null

    beforeEach inject ($controller, $rootScope) ->
      $scope = $rootScope.$new()

      createController = ->
        $controller('AppController', {$scope: $scope})

    it 'watches the identity service for identity change events', ->
      app = createController()
      assert.calledOnce(fakeIdentity.watch)

    it 'sets the persona to null when the identity has been checked', ->
      app = createController()
      {onlogin, onlogout, onready} = fakeIdentity.watch.args[0][0]
      onready()
      assert.isNull($scope.persona)

    it 'does not set the persona to null while token is still being checked', ->
      app = createController()
      {onlogin, onlogout, onready} = fakeIdentity.watch.args[0][0]
      onlogin()
      onready()
      assert.isNotNull($scope.persona)

    it 'shows login form for logged out users on first run', ->
      fakeLocation.search.returns({'firstrun': ''})
      app = createController()
      {onlogin, onlogout, onready} = fakeIdentity.watch.args[0][0]
      onready()
      assert.isTrue($scope.dialog.visible)

    it 'does not show login form for logged out users if not first run', ->
      app = createController()
      {onlogin, onlogout, onready} = fakeIdentity.watch.args[0][0]
      onready()
      assert.isFalse($scope.dialog.visible)

    it 'does not show login form for logged in users', ->
      app = createController()
      {onlogin, onlogout, onready} = fakeIdentity.watch.args[0][0]
      onlogin('abcdef123')
      onready()
      assert.isFalse($scope.dialog.visible)

  describe 'AnnotationViewerController', ->
    annotationViewer = null

    beforeEach inject ($controller, $rootScope) ->
      $scope = $rootScope.$new()
      $scope.search = {}
      annotationViewer = $controller 'AnnotationViewerController',
        $scope: $scope

    it 'sets the isEmbedded property to false', ->
      assert.isFalse($scope.isEmbedded)
