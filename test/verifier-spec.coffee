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
    @amqp = sinon.stub()
    updatedDevice = registeredDevice = uuid:'a-new-uuid', token:'lol-a-token'
    updatedDevice.nonce = @sut.nonce
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'RegisterDevice')
      .yields null, registeredDevice
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'UnregisterDevice')
      .yields null, null
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'CreateSubscription')
      .yields null, null
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'SendMessage')
      .yields null, null
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'UpdateDevice')
      .yields null, null
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'GetDevice')
      .onFirstCall()
      .yields null, registeredDevice
      .onSecondCall()
      .yields null, updatedDevice
      .onThirdCall()
      .yields null, 'null'

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

        @amqp @message, (error, response) =>
          debug sendResponse: {error, response}
          sender.send response, options

        if @message.applicationProperties.jobType == 'SendMessage'
          options =
            properties:
              subject: @sut.meshblu.firehoseQueueName
          debug sendMessage: {options}
          sender.send @message.body, options

        if @message.applicationProperties.jobType == 'UpdateDevice'
          options =
            properties:
              subject: @sut.meshblu.firehoseQueueName
          message = nonce: @nonce
          debug {message, options}
          sender.send JSON.stringify(message), options

  describe '-> verify', ->
    context 'when everything works', ->

      beforeEach (done) ->
        @sut.verify (@error) =>
          done @error

      it 'should not error', ->
        expect(@error).not.to.exist

    xcontext 'when register fails', ->
      beforeEach (done) ->
        @registerHandler.yields error: 'something wrong'

        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@registerHandler).to.be.called

    xcontext 'when whoami fails', ->
      beforeEach (done) ->
        @registerHandler.yields uuid: 'some-device'
        @whoamiHandler.yields error: 'something wrong'

        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@registerHandler).to.be.called
        expect(@whoamiHandler).to.be.called

    xcontext 'when message fails', ->
      beforeEach (done) ->
        @registerHandler.yields uuid: 'some-device'
        @whoamiHandler.yields uuid: 'some-device', type: 'meshblu:verifier'
        @messageHandler.yields null

        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@registerHandler).to.be.called
        expect(@whoamiHandler).to.be.called
        expect(@messageHandler).to.be.called

    xcontext 'when update fails', ->
      beforeEach (done) ->
        @registerHandler.yields uuid: 'some-device'
        @whoamiHandler.yields uuid: 'some-device', type: 'meshblu:verifier'
        @messageHandler.yields payload: @nonce
        @updateHandler.yields error: 'something wrong'

        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@registerHandler).to.be.called
        expect(@whoamiHandler).to.be.called
        expect(@updateHandler).to.be.called

    xcontext 'when unregister fails', ->
      beforeEach (done) ->
        @registerHandler.yields uuid: 'some-device'
        @whoamiHandler.yields uuid: 'some-device', type: 'meshblu:verifier'
        @messageHandler.yields payload: @nonce
        @updateHandler.yields nonce: @nonce
        @unregisterHandler.yields error: 'something wrong'

        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@registerHandler).to.be.called
        expect(@whoamiHandler).to.be.called
        expect(@updateHandler).to.be.called
        expect(@unregisterHandler).to.be.called
