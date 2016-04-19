TestWorker = require './test-worker'
Verifier   = require '../src/verifier'
debug      = require('debug')('meshblu-verifier-amqp:test')

describe 'Verifier', ->
  beforeEach (done) ->
    @testWorker = new TestWorker
    @testWorker.connect (error, {@client, @receiver}) =>
      return done error if error?
      done()

  afterEach (done) ->
    @testWorker.close done

  beforeEach ->
    @nonce = Date.now()
    meshbluConfig = uuid: 'some-uuid', token: 'some-token', hostname: '127.0.0.1'
    @sut = new Verifier {meshbluConfig, @nonce}

  beforeEach ->
    @updatedDevice = @registeredDevice = uuid:'a-new-uuid', token:'lol-a-token'
    @updatedDevice.nonce = @sut.nonce

    @amqp = sinon.stub()

    @responses =
      registerDevice: @registeredDevice
      unregisterDevice: 'null'
      createSubscription: 'null'
      sendMessage: 'null'
      updateDevice: 'null'
      getDeviceFirst: @registeredDevice
      getDeviceSecond: @updatedDevice
      getDeviceThird: 'null'

    @amqp.withArgs(sinon.match applicationProperties: jobType: 'RegisterDevice')
      .yields null, 'registerDevice'
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'UnregisterDevice')
      .yields null, 'unregisterDevice'
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'CreateSubscription')
      .yields null, 'createSubscription'
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'SendMessage')
      .yields null, 'sendMessage'
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'UpdateDevice')
      .yields null, 'updateDevice'
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'GetDevice')
      .onFirstCall()
      .yields null, 'getDeviceFirst'
      .onSecondCall()
      .yields null, 'getDeviceSecond'
      .onThirdCall()
      .yields null, 'getDeviceThird'

    @receiver.on 'message', (@message) =>
      debug JSON.stringify(message: {
        applicationProperties: @message.applicationProperties
        body: @message.body
      }, null, 2)
      @client.createSender().then (sender) =>
        options =
          properties:
            subject: @message.properties.replyTo
            correlationId: @message.properties.correlationId
          applicationProperties:
            code: 200

        @amqp @message, (error, responseKey) =>
          response = @responses[responseKey]
          debug sendResponse: {error, response}
          sender.send response, options

        if @message.applicationProperties.jobType == 'SendMessage'
          options =
            properties:
              subject: @sut.meshblu.firehoseQueueName
          debug sendMessage: {options}
          response = @responses.sendMessageResponse
          response ?= @message.body
          sender.send response, options

        if @message.applicationProperties.jobType == 'UpdateDevice'
          options =
            properties:
              subject: @sut.meshblu.firehoseQueueName
          message = nonce: @nonce
          debug {message, options}
          response = @responses.updateDeviceResponse
          response ?= JSON.stringify(message)
          sender.send response, options

  describe '-> verify', ->
    context 'when everything works', ->
      beforeEach (done) ->
        @sut.verify (@error) =>
          done @error

      it 'should not error', ->
        expect(@error).not.to.exist

    context 'when register fails', ->
      beforeEach (done) ->
        @responses.registerDevice = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist

    context 'when first whoami after register fails', ->
      beforeEach (done) ->
        @responses.getDeviceFirst = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist

    context 'when second whoami after update fails', ->
      beforeEach (done) ->
        @responses.getDeviceSecond = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist

    context 'when third whoami after unregister fails', ->
      beforeEach (done) ->
        @responses.getDeviceThird = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist

    context 'when message fails', ->
      beforeEach (done) ->
        @responses.sendMessageResponse = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist

    context 'when update fails', ->
      beforeEach (done) ->
        @updatedDevice.nonce = 0
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
