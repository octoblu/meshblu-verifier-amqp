_ = require 'lodash'
async = require 'async'
MeshbluAmqp = require 'meshblu-amqp'
xml2js = require('xml2js').parseString
debug = require('debug')('meshblu-verifier-amqp')

class Verifier
  constructor: ({@meshbluConfig, @onError, @nonce}) ->
    @nonce ?= Date.now()

  _connect: (callback) =>
    debug '+ connect'
    @meshblu = new MeshbluAmqp @meshbluConfig
    @meshblu.connect (error) =>
      debug '+ connected'
      return callback(error) if error?
      @_firehose callback

  _firehose: (callback) =>
    debug '+ firehose'
    @meshblu.connectFirehose callback

  _message: (callback) =>
    debug '+ message'
    @meshblu.once 'message', ({data}) =>
      return callback new Error 'wrong message received' unless data?.payload == @nonce
      callback()

    message =
      devices: [@meshbluConfig.uuid]
      payload: @nonce

    @meshblu.message message, =>
  # _register: (callback) =>
  #   @_connect()
  #   @meshblu.connect (error) =>
  #     return callback error if error?
  #
  #     @meshblu.once 'error', (data) =>
  #       callback new Error data
  #
  #     @meshblu.once 'registered', (data) =>
  #       @device = data
  #       @meshbluConfig.uuid = @device.uuid
  #       @meshbluConfig.token = @device.token
  #       @meshblu.close()
  #       @_connect()
  #       @meshblu.connect (error) =>
  #         return callback error if error?
  #         callback()
  #
  #     @meshblu.register type: 'meshblu:verifier'
  _subscribeSelf: (callback) =>
    debug '+ subscribeSelf'
    subscription =
      emitterUuid: @meshbluConfig.uuid
      subscriberUuid: @meshbluConfig.uuid
      type: 'message.received'

    @meshblu.subscribe @meshbluConfig.uuid, subscription, (error, data) =>
      debug {error,data}
      callback error

  _subscribeConfig: (callback) =>
    debug '+ subscribeConfig'
    subscription =
      emitterUuid: @meshbluConfig.uuid
      subscriberUuid: @meshbluConfig.uuid
      type: 'configure.sent'

    @meshblu.subscribe @meshbluConfig.uuid, subscription, (error) =>
      return callback error if error?
      subscription.type = 'configure.received'
      @meshblu.subscribe @meshbluConfig.uuid, subscription, callback

  _whoami: (callback) =>
    debug '+ whoami'
    @meshblu.whoami (error, device) =>
      return callback new Error 'whoami failed' unless device.uuid == @meshbluConfig.uuid
      callback error

  _update: (callback) =>
    debug '+ update'
    params =
      $set:
        nonce: @nonce

    whoamiValid = false
    configMessageValid = false

    @meshblu.once 'message', ({data}) =>
      debug '+ update message'
      debug {data}
      return callback new Error 'wrong config message received' unless data?.nonce == @nonce
      configMessageValid = true
      callback null, data if whoamiValid

    @meshblu.update @meshbluConfig.uuid, params, (error) =>
      return callback error if error?
      @meshblu.whoami (error, whoami) =>
        debug '+ whoami'
        debug {whoami}
        return callback new Error 'update failed whoami check' unless whoami?.nonce == @nonce
        whoamiValid = true
        callback null, whoami if configMessageValid

  # _unregister: (callback) =>
  #   return callback() unless @device?
  #   @meshblu.once 'unregistered', (data) =>
  #     callback null, data
  #
  #   @meshblu.removeAllListeners 'error'
  #   @meshblu.once 'error', (data) =>
  #     callback new Error data
  #
  #   @meshblu.unregister @device

  verify: (callback) =>
    async.series [
      @_connect
      @_subscribeSelf
      # @_register
      @_whoami
      @_message
      @_subscribeConfig
      @_update
      # @_unregister
    ], (error) =>
      @meshblu.disconnectFirehose =>
        @meshblu.close()
      callback error

module.exports = Verifier
