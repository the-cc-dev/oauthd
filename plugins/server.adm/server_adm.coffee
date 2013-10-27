# oauthd
# http://oauth.io
#
# Copyright (c) 2013 thyb, bump
# For private use only.

async = require 'async'
Mailer = require '../../lib/mailer'

exports.setup = (callback) ->

	@on 'connect.callback', (data) =>
		@db.timelines.addUse target:'co:' + data.status, (->)
		@db.ranking_timelines.addScore 'p:co:' + data.status, id:data.provider, (->)
		@db.redis.hget 'a:keys', data.key, (e,app) =>
			@db.ranking_timelines.addScore 'a:co:' + data.status, id:app, (->)

	@on 'connect.auth', (data) =>
		@db.timelines.addUse target:'co', (->)
		@db.ranking_timelines.addScore 'p:co', id:data.provider, (->)
		@db.redis.hget 'a:keys', data.key, (e,app) =>
			@db.ranking_timelines.addScore 'a:co', id:app, (->)

	@userInvite = (iduser, callback) =>
		prefix = 'u:' + iduser + ':'
		@db.redis.mget [
			prefix+'mail',
			prefix+'key',
			prefix+'validated'
		], (err, replies) =>
			return callback err if err
			if replies[2] == '1'
				return callback new check.Error "not validable"
			options =
				to:
					email: replies[0]
				from:
					name: 'OAuth.io'
					email: 'team@oauth.io'
				subject: 'Validate your OAuth.io Beta account'
				body: 'Welcome on OAuth.io Beta!\n\n
In order to validate your email address, please click the following link: https://' + @config.url.host + '/validate/' + iduser + '/' + replies[1] + '.\n
Your feedback is über-important to us: it would help improve developer\'s life even more.\n\n
So don\'t hesitate to reply to this email.\n\n
Thanks for trying out OAuth.io beta!\n\n
--\n
OAuth.io Team'

			data =
				body: options.body.replace(/\n/g, "<br />")
				id: iduser
				key: replies[1]
			mailer = new Mailer options, data
			mailer.send (err, result) =>
				return callback err if err
				@db.redis.set prefix+'validated', '2'
				callback()

	@server.post @config.base_api + '/adm/users/:id/invite', @auth.adm, (req, res, next) =>
		@userInvite req.params.id, @server.send(res, next)

	# get users list
	@server.get @config.base_api + '/adm/users', @auth.adm, (req, res, next) =>
		@db.redis.hgetall 'u:mails', (err, users) =>
			return next err if err
			cmds = []
			for mail,iduser of users
				cmds.push ['get', 'u:' + iduser + ':date_inscr']
				cmds.push ['smembers', 'u:' + iduser + ':apps']
				cmds.push ['get', 'u:' + iduser + ':key']
				cmds.push ['get', 'u:' + iduser + ':validated']
			@db.redis.multi(cmds).exec (err, r) =>
				return next err if err
				i = 0
				for mail,iduser of users
					users[mail] = email:mail, id:iduser, date_inscr:r[i*4], apps:r[i*4+1], key:r[i*4+2], validated:r[i*4+3]
					i++
				res.send users
				next()

	# get app info with ID
	@server.get @config.base_api + '/adm/app/:id', @auth.adm, (req, res, next) =>
		id_app = req.params.id
		prefix = 'a:' + id_app + ':'
		cmds = []
		cmds.push ['mget', prefix + 'name', prefix + 'key']
		cmds.push ['smembers', prefix + 'domains']
		cmds.push ['keys', prefix + 'k:*']

		@db.redis.multi(cmds).exec (err, results) ->
			return next err if err
			app = id:id_app, name:results[0][0], key:results[0][1], domains:results[1], providers:( result.substr(prefix.length + 2) for result in results[2] )
			res.send app
			next()

	# delete a user
	@server.del @config.base_api + '/adm/users/:id', @auth.adm, (req, res, next) =>
		@db.users.remove req.params.id, @server.send(res, next)

	# get any statistics
	@server.get new RegExp('^' + @config.base_api + '/adm/stats/(.+)'), @auth.adm, (req, res, next) =>
		async.parallel [
			(cb) => @db.timelines.getTimeline req.params[0], req.query, cb
			(cb) => @db.timelines.getTotal req.params[0], cb
		], (e, r) ->
			return next e if e
			res.send total:r[1], timeline:r[0]
			next()

	# regenerate all private keys
	@server.get @config.base_api + '/adm/secrets/reset', @auth.adm, (req, res, next) =>
		@db.redis.hgetall 'a:keys', (e, apps) =>
			return next e if e
			mset = []
			for k,id of apps
				mset.push 'a:' + id + ':secret'
				mset.push @db.generateUid()
			@db.redis.mset mset, @server.send(res,next)

	# refresh rankings
	@server.get @config.base_api + '/adm/rankings/refresh', @auth.adm, (req, res, next) =>
		providers = {}
		@db.redis.hgetall 'a:keys', (e, apps) =>
			return next e if e
			tasks = []
			for k,id of apps
				do (id) => tasks.push (cb) =>
					@db.redis.keys 'a:' + id + ':k:*', (e, keysets) =>
						return cb e if e
						for keyset in keysets
							prov = keyset.match /^a:.+?:k:(.+)$/
							continue if not prov?[1]
							providers[prov[1]] ?= 0
							providers[prov[1]]++
						@db.rankings.setScore 'a:k', id:id, val:keysets.length, cb
			async.parallel tasks, (e) =>
				return next e if e
				for p,keysets of providers
					@db.rankings.setScore 'p:k', id:p, val:keysets, (->)
				res.send @check.nullv
				next()

	# get a ranking
	@server.post @config.base_api + '/adm/ranking', @auth.adm, (req, res, next) =>
		@db.ranking_timelines.getRanking req.body.target, req.body, @server.send(res, next)

	# get a ranking related to apps
	@server.post @config.base_api + '/adm/ranking/apps', @auth.adm, (req, res, next) =>
		@db.ranking_timelines.getRanking req.body.target, req.body, (e, infos) =>
			return next e if e
			cmds = []
			for info in infos
				cmds.push ['get', 'a:' + info.name + ':name']
				cmds.push ['smembers', 'a:' + info.name + ':domains']
				# ... add more ? domains ? owner ?
			@db.redis.multi(cmds).exec (e, r) ->
				infos[i].name = r[i*2] + ' (' + r[i*2+1].join(', ') + ')' for i of infos
				res.send infos
				next()

	# get provider list
	@server.get @config.base_api + '/adm/wishlist', @auth.adm, (req, res, next) =>
		@db.wishlist.getList full:true, @server.send(res, next)

	@server.del @config.base_api + '/adm/wishlist/:provider', @auth.adm, (req, res, next) =>
		@db.wishlist.remove req.params.provider, @server.send(res, next)

	@server.post @config.base_api + '/adm/wishlist/:provider/status/:status', @auth.adm, (req, res, next) =>
		@db.wishlist.setStatus req.params.provider, req.params.status , @server.send(res, next)

	callback()