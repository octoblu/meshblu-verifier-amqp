TestWorker = require './test-worker'
Verifier   = require '../src/verifier'
debug      = require('debug')('meshblu-verifier-amqp:test')
_          = require 'lodash'

describe 'Verifier', ->
  beforeEach (done) ->
    @testWorker = new TestWorker
    @testWorker.connect (error, {@client, @receiver}={}) =>
      return done error if error?
      done()
    return # promises

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
      RegisterDevice     : @registeredDevice
      UnregisterDevice   : 'null'
      CreateSubscription : 'null'
      SendMessage        : 'null'
      UpdateDevice       : 'null'
      GetDevice          : [ @registeredDevice, @updatedDevice, 'null' ]

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

        response = @responses[@message.applicationProperties.jobType]
        response = response.shift() if _.isArray response
        debug 'response:'
        debug {response, options}
        sender.send response, options

        if @message.applicationProperties.jobType == 'SendMessage'
          options =
            properties:
              subject: @sut.meshblu.firehoseQueueName
          response = @responses['SendMessage-Response']
          response ?= @message.body
          debug 'sendMessageResponse:'
          debug {response, options}
          sender.send response, options

        if @message.applicationProperties.jobType == 'UpdateDevice'
          options =
            properties:
              subject: @sut.meshblu.firehoseQueueName
          message = nonce: @nonce
          response = @responses['UpdateDevice-Response']
          response ?= JSON.stringify(message)
          debug 'updateDeviceResponse:'
          debug {response, options}
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
        @responses.RegisterDevice = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@error.message).to.equals 'missing registered uuid & token'

    context 'when first whoami after register fails', ->
      beforeEach (done) ->
        @responses.GetDevice[0] = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@error.message).to.equals 'whoami failed'

    context 'when second whoami after update fails', ->
      beforeEach (done) ->
        @responses.GetDevice[1] = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@error.message).to.equals 'update failed whoami check'

    context 'when third whoami after unregister fails', ->
      beforeEach (done) ->
        @responses.GetDevice[2] = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@error.message).to.equals 'whoami is not null'

    context 'when message fails', ->
      beforeEach (done) ->
        @responses['SendMessage-Response'] = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@error.message).to.equals 'nonce in message does not match'

    context 'when update fails', ->
      beforeEach (done) ->
        @responses['UpdateDevice-Response'] = {}
        @sut.verify (@error) =>
          done()

      it 'should error', ->
        expect(@error).to.exist
        expect(@error.message).to.equals 'nonce in config does not match'
