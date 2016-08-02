colors        = require 'colors'
dashdash      = require 'dashdash'
MeshbluConfig = require 'meshblu-config'
moment        = require 'moment'
request       = require 'request'

packageJSON = require './package.json'
Verifier    = require './src/verifier'

OPTIONS = [{
  names: ['help', 'h']
  type: 'bool'
  help: 'Print this help and exit.'
}, {
  names: ['log-expiration', 'e']
  type: 'integer'
  env: 'LOG_EXPIRATION'
  help: 'number of seconds the verification status is good for. (default: 300)'
  helpWrap: true
  default: 300
}, {
  names: ['log-url', 'u']
  type: 'string'
  env: 'LOG_URL'
  help: 'The fully qualified url to post the verifier status to.'
  helpArg: 'URL'
}, {
  names: ['version', 'v']
  type: 'bool'
  help: 'Print the version and exit.'
}]

class Command
  constructor: ->
    process.on 'uncaughtException', @die
    {@log_expiration, @log_url} = @parseOptions()

  parseOptions: =>
    parser = dashdash.createParser({options: OPTIONS})
    options = parser.parse(process.argv)

    if options.help
      console.log "usage: meshblu-verifier-http [OPTIONS]\noptions:\n#{parser.help({includeEnv: true})}"
      process.exit 0

    if options.version
      console.log packageJSON.version
      process.exit 0

    if !options.log_url
      console.error "usage: meshblu-verifier-http [OPTIONS]\noptions:\n#{parser.help({includeEnv: true})}"
      console.error colors.red 'Missing required parameter --log-url, -u, or env: LOG_URL'
      process.exit 1

    return options

  run: =>
    timeoutSeconds = 30
    timeoutSeconds = parseInt(process.env.TIMEOUT_SECONDS) if process.env.TIMEOUT_SECONDS
    setTimeout @timeoutAndDie, timeoutSeconds * 1000
    meshbluConfig = new MeshbluConfig().toJSON()
    verifier = new Verifier {meshbluConfig}
    verifier.verify @logResult

  logResult: (error) =>
    request.post @log_url, {
      json:
        success: !error?
        expires: moment().add(@log_expiration, 'seconds')
    }, (httpError) =>
      @die httpError if httpError?
      @die error if error?
      console.log 'meshblu-verifier-amqp successful'
      process.exit 0

  die: (error) =>
    return process.exit(0) unless error?
    console.log 'meshblu-verifier-amqp error'
    console.error error.stack
    process.exit 1

  timeoutAndDie: =>
    console.log 'meshblu-verifier-amqp timeout'
    @logResult new Error 'Timeout Exceeded'



commandWork = new Command()
commandWork.run()
