request = require 'request'

exports.setup = (callback) ->

	if not @config.consumer_io?.site_id or not @config.consumer_io.api_key
		console.log 'Warning: consumer.io plugin is not configured'
		return callback()

	customerio = request.defaults
		auth:
			user: @config.consumer_io.site_id
			pass: @config.consumer_io.api_key

	timestamp = (v) -> Math.floor(v/1000)

	updateUser = (user, data) =>
		mkData = (cb) =>
			cpydata = {}
			cpydata[k] = v for k,v of data
			if user.mail
				cpydata.email = user.mail
				return cb null, cpydata
			@db.redis.get 'u:' + user.id + ':mail', (e,mail) ->
				return cb e if e
				cpydata.email = mail
				cb null, cpydata
		mkData (e,data) =>
			return if e
			customerio.put {
				url: 'https://track.customer.io/api/v1/customers/' + user.id
				json: data
			}, (e, r, body) ->
				console.error "Error while updating contact to consumer.io", e, data, body, r.statusCode if e or r.statusCode != 200

	sendEvent = (user, name, data) =>
		reqData = name: name
		reqData.data = data if data
		customerio.post {
			url: 'https://track.customer.io/api/v1/customers/' + user.id + '/events'
			json: reqData
		}, (e, r, body) ->
			console.error "Error while sending event to consumer.io", e, user.id, name, data, body, r.statusCode if e or r.statusCode != 200

	@on 'cohort.inscr', (user, now) =>
		updateUser user, date_inscr:timestamp(now)
	@on 'cohort.validate', (user, now) =>
		updateUser user, date_validate:timestamp(now)
	@on 'cohort.activation', (user, now) =>
		updateUser user, date_activation:timestamp(now)
	@on 'cohort.development', (user, now) =>
		updateUser user, date_development:timestamp(now)
	@on 'cohort.production', (user, now) =>
		updateUser user, date_production:timestamp(now)
	@on 'cohort.consumer', (user, now) =>
		updateUser user, date_consumer:timestamp(now)

	@on 'user.login', (user) =>
		sendEvent user, 'login'

	# todo: user.pay (pricing)

	@on 'app.create', (req, app) =>
		sendEvent req.user, 'app.create', app
	@on 'app.remove', (req, app) =>
		sendEvent req.user, 'app.remove', app

	@on 'app.remkeyset', (data) =>
		@db.apps.getOwner data.app, (e, user) =>
			return if e
			sendEvent user, 'app.remkeyset', data

	@on 'app.addkeyset', (data) =>
		@db.apps.getOwner data.app, (e, user) =>
			return if e
			sendEvent user, 'app.addkeyset', data
	@on 'app.updatekeyset', (data) =>
		@db.apps.getOwner data.app, (e, user) =>
			return if e
			sendEvent user, 'app.updatekeyset', data

	@on 'request', (data) =>
		@db.apps.getOwner data.key, (e, user) =>
			return if e
			sendEvent user, 'app.request', data

	@on 'connect.auth', (data) =>
		@db.apps.getOwner data.key, (e, user) =>
			return if e
			sendEvent user, 'connect.auth', provider:data.provider, key:data.key

	@on 'connect.callback', (data) =>
		@db.apps.getOwner data.key, (e, user) =>
			return if e
			eventData = provider:data.provider, key:data.key, origin:data.origin, status:data.status
			for apiname, apivalue of data.parameters
				eventData['_' + apiname] = apivalue if Array.isArray(apivalue)
			sendEvent user, 'connect.callback', eventData

	@server.post @config.base_api + '/adm/customerio/update', @auth.adm, (req, res, next) =>
		@db.redis.hgetall 'u:mails', (err, users) =>
			return next err if err
			cmds = []
			for mail,iduser of users
				cmds.push 'u:' + iduser + ':date_inscr'
				cmds.push 'u:' + iduser + ':date_validate'
				cmds.push 'u:' + iduser + ':date_activation'
				cmds.push 'u:' + iduser + ':date_development'
				cmds.push 'u:' + iduser + ':date_production'
				cmds.push 'u:' + iduser + ':date_consumer'
			@db.redis.mget cmds, (err, r) =>
				return next err if err
				i = 0
				for mail,iduser of users
					updateUser {id:iduser, mail:mail},
						date_inscr:timestamp(r[i*6]),
						date_validate:timestamp(r[i*6+1]),
						date_activation:timestamp(r[i*6+2]),
						date_development:timestamp(r[i*6+3]),
						date_production:timestamp(r[i*6+4]),
						date_consumer:timestamp(r[i*6+5]),
					i++
				res.send @check.nullv
				next()

	callback()