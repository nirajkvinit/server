#
# FastChat
# 2015
#

# Initialize Helpers
require('./lib/helpers/helpers')()
Server = require './lib/server'
Mongo = require './lib/model/mongo'
log = require './lib/helpers/log'

s = new Server(port: process.env.PORT or 6190)
s.setup().then ->
  Mongo()
.then ->
  log.debug 'Starting...'
  s.start()
.fail (err)->
  log.error '************* ERROR STARTING SERVER *************'
  log.error err
  log.error '************* ERROR STARTING SERVER *************'
  log.error 'What most likely happened?'
  log.error 'The Server FAILED to get the correct configuration values for Startup!'
  log.error '    Are the Config values correct?'
  log.error '    Are the Config values valid JSON?'
  log.error '    Did you use the Makefile? This is what it\'s there for.'
  log.error '    Did you start the process with the correct ENV Variables?'
  process.exit(1)
.done()
