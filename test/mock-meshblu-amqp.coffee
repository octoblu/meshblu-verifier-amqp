http = require 'http'
# amqp = require 'node-amqp-server'

class MockMeshbluAmqp
  constructor: (options) ->
    {@onConnection, @port} = options

  start: (callback) =>
    @server = new amqp.C2S.TCPServer
      port: 0xd00d
      domain: 'localhost'

    @server.on 'connection', @_onConnection

    @server.on 'listening', callback

  stop: (callback) =>
    @server.end callback

  _onConnection: (client) =>
    @onConnection client

module.exports = MockMeshbluAmqp
