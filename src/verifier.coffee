_           = require 'lodash'
async       = require 'async'
MeshbluAmqp = require 'meshblu-amqp'
xml2js      = require('xml2js').parseString
debug       = require('debug')('meshblu-verifier-amqp:verifier')

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

  _close: (callback) =>
    debug '+ close'
    @meshblu.close callback

  _firehose: (callback) =>
    debug '+ firehose'
    @meshblu.connectFirehose callback

  _message: (callback) =>
    debug '+ message'
    @meshblu.once 'message', (message) =>
      {data} = message
      debug '+ message received'
      debug {message}
      return callback new Error 'wrong message received' unless data?.payload == @nonce
      callback()

    message =
      devices: [@meshbluConfig.uuid]
      payload: @nonce

    @meshblu.message message, =>
      debug "+ message sent"

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

  _whoamiNull: (callback) =>
    debug '+ whoami = null ?'
    @meshblu.whoami (error, device) =>
      debug {error, device}
      return callback new Error 'whoami failed' unless !device?
      callback error

  _update: (callback) =>
    debug '+ update'
    params =
      $set:
        nonce: @nonce

    whoamiValid = false
    configMessageValid = false

    @meshblu.once 'message', (message) =>
      {data} = message
      debug '+ got update message'
      debug {message}
      return callback new Error 'wrong config message received' unless data?.nonce == @nonce
      configMessageValid = true
      callback null if whoamiValid

    @meshblu.update @meshbluConfig.uuid, params, (error) =>
      return callback error if error?
      debug '+ update sent'
      @meshblu.whoami (error, whoami) =>
        debug '+ got whoami'
        debug {whoami}
        return callback new Error 'update failed whoami check' unless whoami?.nonce == @nonce
        whoamiValid = true
        callback error if configMessageValid

  _register: (callback) =>
    debug '+ register'
    @meshblu.register type: 'meshblu:verifier', (error, device) =>
      debug {uuid: device.uuid, token: device.token}
      return callback new Error 'missing registered uuid & token' unless device?.uuid? and device?.token?
      @meshbluConfig.uuid = device.uuid
      @meshbluConfig.token = device.token
      callback error

  _unregister: (callback) =>
    debug '+ unregister'
    @meshblu.unregister @meshbluConfig.uuid, callback

  verify: (callback) =>
    async.series [
      @_connect
      @_register
      @_close
      @_connect
      @_subscribeSelf
      @_whoami
      @_message
      @_subscribeConfig
      @_update
      @_unregister
      @_whoamiNull
    ], (error) =>
      @_close =>
        callback(error)

module.exports = Verifier
