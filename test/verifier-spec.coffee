shmock = require 'shmock'
Verifier = require '../src/verifier'
MockMeshbluAmqp = require './mock-meshblu-amqp'
xml2js = require('xml2js').parseString
ltx = require 'ltx'
jsontoxml = require 'jsontoxml'
# amqp = require 'node-amqp-server'
TestWorker = require './test-worker'

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
    #meshbluConfig = hostname: 'localhost', port: 0xd00d, uuid: 'some-device', token: 'some-token'
    @sut = new Verifier {meshbluConfig, @nonce}

  beforeEach ->
    @amqp = sinon.stub()
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'RegisterDevice')
      .yields null, {uuid:'a-new-uuid',token:'lol-a-token'}
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'CreateSubscription')
      .yields null, null
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'GetDevice')
      .yields null, {uuid:'a-new-uuid',token:'lol-a-token'}
    @amqp.withArgs(sinon.match applicationProperties: jobType: 'SendMessage')
      .yields null, null

    @receiver.on 'message', (@message) =>
      console.log {@message}
      @client.createSender(@message.properties.replyTo).then (sender) =>
        options =
          properties:
            correlationId: @message.properties.correlationId
          applicationProperties:
            code: 200

        if @message.applicationProperties.jobType == 'SendMessage'
          options = subject: @sut.meshblu.firehoseQueueName
          console.log {options}
          sender.send {}, options

        @amqp @message, (error, response) =>
          console.log {error, response}
          sender.send response, options
#
# describe 'Verifier', ->
#   beforeEach (done) ->
#     @registerHandler = sinon.stub()
#     @whoamiHandler = sinon.stub()
#     @unregisterHandler = sinon.stub()
#     @updateHandler = sinon.stub()
#     @messageHandler = sinon.stub()
#
#     onConnection = (client) =>
#       _sendResponse = ({request, response}) =>
#         responseNode = ltx.parse jsontoxml {response}
#         # client.send new amqp.Stanza('iq',
#         #   type: 'result'
#         #   to: request.attrs.from
#         #   from: request.attrs.to
#         #   id: request.attrs.id
#         # ).cnode responseNode
#
#       onStanza = (request) =>
#         if request.name == 'message'
#           console.log 'message', request
#           return
#
#         metadata = request.getChild('request').getChild('metadata')
#
#         xml2js metadata.toString(), explicitArray: false, (error, job) =>
#           if job.metadata.jobType == 'GetDevice'
#             @whoamiHandler job, (response) =>
#               return _sendResponse {request, response}
#
#           if job.metadata.jobType == 'UpdateDevice'
#             @updateHandler job, (response) =>
#               return _sendResponse {request, response}
#
#           if job.metadata.jobType == 'SendMessage'
#             @messageHandler job, (response) =>
#               # client.send new amqp.Stanza('message',
#               #   to: 'some-device@meshblu.octoblu.com'
#               #   from: 'meshblu.octoblu.com'
#               #   type: 'normal'
#               # ).cnode(ltx.parse """
#               #   <metadata />
#               # """).up().cnode(ltx.parse """
#               #   <raw-data>#{response.rawData}</raw-data>
#               # """)
#
#               return _sendResponse {request, response}
#
#       client.on 'stanza', onStanza
#       client.on 'authenticate', (opts, callback) =>
#         callback(null, opts)
#
#     @meshblu = new MockMeshbluAmqp port: 0xd00d, onConnection: onConnection
#     @meshblu.start done
#
#   afterEach (done) ->
#     @meshblu.stop => done()

  describe '-> verify', ->
    context 'when everything works', ->
      # beforeEach ->
        # @registerHandler.yields rawData: JSON.stringify(uuid: 'some-device')
        # @whoamiHandler.yields rawData: JSON.stringify(uuid: 'some-device', type: 'meshblu:verifier')
        # @messageHandler.yields rawData: JSON.stringify(payload: @nonce)
        # @updateHandler.yields rawData: JSON.stringify(null)
        # @whoamiHandler.yields rawData: JSON.stringify(uuid: 'some-device', type: 'meshblu:verifier', nonce: @nonce)
        # @unregisterHandler.yields rawData: JSON.stringify(null)

      beforeEach (done) ->
        @sut.verify (@error) =>
          done @error

      it 'should not error', ->
        expect(@error).not.to.exist
        # expect(@registerHandler).to.be.called
        # expect(@whoamiHandler).to.be.called
        # expect(@messageHandler).to.be.called
        # expect(@updateHandler).to.be.called
        # expect(@unregisterHandler).to.be.called

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
