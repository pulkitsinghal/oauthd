# oauthd
# http://oauth.io
#
# Copyright (c) 2013 thyb, bump
# For private use only.

restify = require 'restify'
dbusers = require './db_users'

exports.setup = (callback) ->

	# register an account
	@server.post @config.base + '/api/users', (req, res, next) =>
		dbusers.register req.body, @server.send(res,next)

	# get my infos
	@server.get @config.base + '/api/me', @auth.needed, (req, res, next) ->
		dbusers.get req.user.id, (e, user) ->
			return next(e) if e
			dbusers.getApps user.id, (e, appkeys) ->
				return next(e) if e
				user.apps = appkeys
				res.send user
				next()

	# update mail or password
	@server.post @config.base + '/api/me', @auth.needed, (req, res, next) =>
		next new @check.Error "Implemented soon !"

	# delete my account
	@server.del @config.base + '/api/me', @auth.needed, (req, res, next) =>
		dbusers.remove req.user.id, @server.send(res,next)

	callback()