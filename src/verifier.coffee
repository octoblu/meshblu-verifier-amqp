_ = require 'lodash'
async = require 'async'
MeshbluAmqp = require 'meshblu-amqp'
xml2js = require('xml2js').parseString

class Verifier
  constructor: ({@meshbluConfig, @onError, @nonce}) ->
    @nonce ?= Date.now()

  _connect: (callback) =>
    @meshblu = new MeshbluAmqp @meshbluConfig
    @meshblu.connect callback

  _message: (callback) =>
    @meshblu.on 'message', ({data}) =>
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

  _update: (callback) =>
    params =
      $set:
        nonce: @nonce

    @meshblu.update @meshbluConfig.uuid, params, (error) =>
      return callback error if error?
      @meshblu.whoami (error, data) =>
        return callback new Error 'update failed' unless data?.nonce == @nonce
        callback null, data

  _whoami: (callback) =>
    @meshblu.whoami callback

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
      # @_register
      @_whoami
      @_message
      @_update
      # @_unregister
    ], (error) =>
      @meshblu.close()
      callback error

module.exports = Verifier
