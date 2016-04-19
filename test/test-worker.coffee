{Client} = require 'amqp10'
Promise = require 'bluebird'

class TestWorker
  connect: (callback) =>
    options =
      reconnect:
        forever: false
        retries: 0

    @client = new Client options
    @client.connect 'amqp://meshblu:judgementday@127.0.0.1'
      .then =>
        @client.createReceiver('meshblu.request')
      .then (receiver) =>
        callback null, {receiver, @client}
        return true
      .catch (error) =>
        callback error
      .error (error) =>
        callback error

  close: (callback) =>
    @client.disconnect()
      .then callback
      .catch callback

module.exports = TestWorker
