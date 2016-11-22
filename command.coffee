_             = require 'lodash'
async         = require 'async'
colors        = require 'colors'
dashdash      = require 'dashdash'
MeshbluConfig = require 'meshblu-config'
moment        = require 'moment'
request       = require 'request'

packageJSON = require './package.json'
Verifier    = require './src/verifier'

VERIFIER_NAME ='meshblu-verifier-amqp'
debug         = require('debug')("#{VERIFIER_NAME}:command")

OPTIONS = [
  {
    names: ['help', 'h']
    type: 'bool'
    help: 'Print this help and exit.'
  }
  {
    names: ['log-expiration', 'e']
    type: 'integer'
    env: 'LOG_EXPIRATION'
    help: 'number of seconds the verification status is good for. (default: 300)'
    helpWrap: true
    default: 300
  }
  {
    names: ['log-url', 'u']
    type: 'string'
    env: 'LOG_URL'
    help: 'The fully qualified url to post the verifier status to.'
    helpArg: 'URL'
  }
  {
    names: ['forever', 'f']
    type: 'bool'
    env: 'FOREVER'
    help: 'The fully qualified url to post the verifier status to. (default: false)'
    default: false
  }
  {
    names: ['interval', 'i']
    type: 'integer'
    env: 'INTERVAL_SECONDS'
    help: 'Interval delay in seconds when running in forever mode'
    default: 60
  }
  {
    names: ['timeout', 't']
    type: 'integer'
    env: 'TIMEOUT_SECONDS'
    help: 'Time to wait before configuring a test as failed'
    default: 30
  }
  {
    names: ['version', 'v']
    type: 'bool'
    help: 'Print the version and exit.'
  }
]

class Command
  constructor: ->
    process.on 'uncaughtException', @printAndDie
    @parser = dashdash.createParser options: OPTIONS
    options = @parseOptions()
    debug 'got options', options
    {
      @log_expiration,
      @log_url,
      @forever,
      @interval,
      @timeout,
    } = options

  printHelp: =>
    options = {includeEnv: true, includeDefault: true}
    console.log "usage: #{VERIFIER_NAME} [OPTIONS]\noptions:\n#{@parser.help(options)}"

  parseOptions: =>
    options = @parser.parse(process.argv)

    if options.help
      @printHelp()
      process.exit 0

    if options.version
      console.log packageJSON.version
      process.exit 0

    if !options.log_url
      @printHelp()
      console.error colors.red 'Missing required parameter --log-url, -u, or env: LOG_URL'
      process.exit 1

    return options

  run: =>
    @runOnce (error) =>
      return @die(error) unless @forever
      return @die(error) if error?
      async.forever (callback) =>
        _.delay @runOnce, (@interval * 1000), callback
      , @die

  runOnce: (callback) =>
    timeoutSeconds = (@timeout * 1000)
    debug 'running with timeout', timeoutSeconds
    run = async.timeout @_runOnce, timeoutSeconds
    run (error) =>
      error = new Error 'Timeout Exceeded' if error?.code == 'ETIMEDOUT'
      @logResult error, callback

  _runOnce: (callback) =>
    meshbluConfig = new MeshbluConfig().toJSON()
    verifier = new Verifier {meshbluConfig}
    verifier.verify callback

  logResult: (error, callback) =>
    debug 'logging results', { error }
    request.post @log_url, {
      json:
        success: !error?
        expires: moment().add(@log_expiration, 'seconds').utc().format()
        error:
          message: error?.message
    }, (httpError, response) =>
      debug 'log results http error', httpError, response?.statusCode
      error ?= httpError
      @print error
      return callback error if error?
      callback null

  print: (error) =>
    return console.log "#{VERIFIER_NAME} successful" unless error?
    console.log "#{VERIFIER_NAME} error"
    console.error error.stack

  die: (error) =>
    process.exit(0) unless error?
    process.exit(1) if error?

  printAndDie: (error) =>
    @print error
    @die error

commandWork = new Command()
commandWork.run()
