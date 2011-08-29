###
playbox v3 - abstract

server lists poems as small 'programs'

each poem is a simple xml file:
<poem id="bookshelf">
	<style>
		<!-- {{less}}/css style rules -->
		
	</style>
	
	<interface [minwidth="1024"] [minheight="768"] [maxwidth="1600"] [maxheight="1200"]>
		the basic interface of the 'poem' - can be defined multiple times too, representing different interface sizes (mobile, desktop, etc.)
	</interface>
	
	<panel id="mybooks" [data="/books"]>
		
	</panel>
	
	<panel id="book" [data="/book/$1"]>
		<!-- simple book entry. this is styled using the above styles -->
		<title>#{data.title || "unknown"}</title>
		<year>#{data.year || "unknown"}</year>
		<desc>#{data.desc || "no description"}</desc>
	</panel>
	
	<part id="Book" data="/book">
		title: "unknown"
	</part>
	
	<include file="panels/*" />
	
	<function id="ring_doorbell">
		
	</function>
</poem>

TODO:
 - add 'trailers' to the server, with a hash of the poem, to verify its identity - response.addTrailers(headers)
 
	# demo hacker news: http://api.ihackernews.com/
	# add this to styles: https://github.com/khoomeister/coffee-css
	# make graphs like this: http://christopheviau.com/d3_tutorial/
	# physical version of the playbox http://www.raspberrypi.org/
	# keybindings - https://github.com/madrobby/keymaster
	# crypto stuff - http://cryptico.wwwtyro.net/
	# copy a lot of the UI from http://about.me/
###

http = require 'http'
Fs = require 'fs'
Url = require 'url'
QueryString = require 'querystring'
Path = require 'path'
Builder = require './builder'
Mime = require 'mime'
nowjs = require 'now'
CoffeeScript = require 'coffee-script'

String::replace_once = String::replace
String::replace = (f, r) ->
	str = @
	until str.indexOf f is -1
		str = str.replace f, r
	str
	

class Playbox
	poems: {}
	constructor: (port) ->
		# get all poems
		Fs.readdir "poems", (err, poems) =>
			if err 
				if err.code is 'ENOENT'
					Builder.mkdirs('poems')
					return
				else
					throw err

			for poem in poems
				@load_poem poem, "poems/#{poem}/#{poem}.coffee"
				
		#start the server
		@server = http.createServer (req, res) =>
			c = new Connection req, res
			c.start()
			
	
		console.log "listening #{port}"
		@server.listen port
		
		@everyone = nowjs.initialize @server
		nowjs.on 'connect', =>
			console.log "connected: #{@everyone.poem}"
		
		@everyone.now.hello = (lala) ->
			console.log "lala: #{lala}"

	load_poem: (id, path) ->
		console.log "loading #{id} #{path}"
		Fs.readFile path, 'utf8', (err, poem_file) =>
			@everyone.now[id] = {}
			@poems[id] = new Poem @everyone.now[id], path
	

#################################

class Connection
	headers: {}
	constructor: (req, res) ->
		@req = req
		@res = res
		@ret = 200
		@output = ""
		@headers["Content-Type"] = "application/xhtml+xml; charset=utf-8"
		
	start: ->
		@url = Url.parse @req.url
		@get = QueryString.parse @url.query
		path = QueryString.unescape @url.pathname
		if path is '/'
			# static_file_url = "/index.html";
			# @headers["Cache-Control"] = "no-cache, must-revalidate";
			# @headers["Pragma"] = "no-cache";
			# @headers["Expires"] = "Fri, 01 Jan 2010 00:00:01 GMT";
			# @output = "<app>a welcoming poem</app>";
		
			#@file "text/html; charset=utf-8", "./public/poem.html"
			@res.write playbox.poems.poem.render playbox.poems.poem
		else
			# static_file_url = path;
			poem_name = path.substr 1
			poem_path = '/'
			poem_path_offset = poem_name.indexOf '/'
			if poem_path_offset isnt -1
				poem_path = poem_path_offset is poem_name.length-1 ? '/' : poem_name.substr poem_path_offset
				poem_name = poem_name.substr 0, poem_path_offset
			
				if poem_path isnt "/" and poem_path.length > 1
					poem_path = poem_path.substr 1
			
			poem = playbox.poems[poem_name]
			console.log "#{path}: #{poem_name} :: #{poem_path}"
			if poem?
				@end 200, poem.render(poem_path)
			else
				mime = Mime.lookup poem_name
				@file mime, "public#{path}"
		
	end: (ret = @ret, output = @output) ->
		if output isnt false
			console.log "conn.end #{ret} #{output}"
			@output = false
			@res.writeHead ret, @headers
			@res.end output
		
	file: (mime, file_path, callback) ->
		console.log "file: #{file_path} (#{mime})"
		@output = false;
		try
			Fs.stat file_path, (err, stat) =>
				if err then throw err

				if stat.isFile()
					# Stream a single file.
					#@res.headers['Content-Length'] = stat.size;
					#@res.headers['Content-Type'] = mime;
					#@res.statusCode = 200;
					@headers['Content-Length'] = stat.size;
					@headers['Content-Type'] = mime;
					@res.writeHead(200, @headers);

					@offset = 0
					stream = Fs.createReadStream file_path, {
						flags: 'r'
						encoding: 'binary'
						mode: '666'
						bufferSize: 4096
					}
					
					stream.on 'data', (chunk) =>
						#buffer.write(chunk, offset, 'binary');
						@res.write chunk, 'binary'
						@offset += chunk.length
					
					stream.on 'close', =>
						@res.end()
					
					stream.on 'error', (err) =>
						@end 500, "500! - '#{file_path}' is problematic"
						# Sys.error(err)
				
				else if typeof callback isnt 'function' or callback 404
					@end 404, "404! - '#{file_path}' does not exist"
		catch e
			if typeof callback isnt 'function' or callback 500
				@end 500, "#{e.message}\n#{e.stack}"
	
#################################

class Interface
	constructor: ->
		console.log 'new Interface!'
	
	render: ->
		# technically, this is a dev workspace... cause all the script compilation is done in the browser
		# obviously in the future, when poems are distributed, they will be compiled for fast delivery
		# (also because some devices won't be able to compile, and will need boring html/css/js files)
		"""
		<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
		<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
			<head>
				<title>#{@title}</title>
				<!-- <link rel="stylesheet/less" href="#{@id}/style.less" type="text/css" media="screen" charset="utf-8" /> -->
				<link rel="stylesheet" type="text/css" href="/css/reset.css" media="screen" />
				<link rel="stylesheet" type="text/css" href="/css/text.css" media="screen" />
				<link rel="stylesheet" type="text/css" href="/css/grid.css" media="screen" />
				<!-- <link rel="stylesheet" type="text/css" href="/css/layout.css" media="screen" /> -->
				<!-- <link rel="stylesheet" type="text/css" href="/css/nav.css" media="screen" /> -->
				<!-- <link rel="stylesheet" href="closure-library/closure/goog/css/tree.css" type="text/css" charset="utf-8" /> -->
				<script type="text/javascript" src="/head.js"></script>
				<script type="text/javascript" src="/less-1.1.4.js"></script>
				<!-- <script type="text/javascript" src="/closure-library/closure/goog/base.js"></script> -->
				<script src="/nowjs/now.js"></script>
			</head>
			<body>
				<script type="text/javascript">
					/* goog.require('goog.ui.tree.TreeControl'); */
					head.js(
						"lib.js",
						"site.js",
						//"socket.io/socket.io.js",
						//"zepto.js?1",
						//"jquery-1.4.4.js",
						//"underscore.js?1",
						//"backbone.js?1",
						//"backbone-storage.js?1",
						//"closure-library/closure/goog/base.js",
						//"#{@id}/poem.js",
						function() {
							//jQuery = Zepto;
							
						}
					);
				</script>
			</body>
		</html>
		"""
		
#################################

class Element
	el: 'div'
	opts: 0
	constructor: (el, opts) ->
		@el ?= el
		@opts ?= opts
		@style = opts.style || ''
		@children = opts.childrend || []
		console.log "Element", @el, @opts
		
	render: (children) ->
		ret = "<#{@el}"
		console.log "Element ", @opts
		if @opts isnt 0
			ret += ' '
			for id, val of @opts
				console.log id, val
				ret += "#{id}=\"#{val.replace '"', '\\"'}\""
			
		ret += if children then '>'+children+'</'+@el+'>' else '/>'
		ret

class Panel extends Element
	constructor: (opts) ->
		super 'panel', opts
		@template = opts.template || 'cacas!'
		
	render: ->
		super @template


#################################

class Poem extends Element
	style: ''
	panels: {}
	constructor: (client, path) ->
		@el = 'poem'
		@client = client
		Fs.readFile path, 'utf8', (err, poem_file) =>
			@path = path
			@id = 'test'
			@title = 'test poem'
			@interface = new Interface
			@panels.test1 = new Panel({
				id: 'test1'
				template: '''
				<h1>totally cool!</h1>
				'''
			})
			
			@client.templates = @templates()
			@client.func = (id, opts, callback) ->
				console.log 'testing...'
				callback "testing..."
			
	render: (d) ->
		@interface.render.apply d
		
	templates: ->
		ret = {}
		for id, panel of @panels
			ret[id] = panel.render()
		console.log("templates", ret)
		ret
	
	style: ->
		@styles + super.style

	
Poem.create = (opts, connection) ->
	id = opts.id || "test"
	dir = "poems/#{id}"
	Fs.mkdir dir, '777', (err) ->
		if err
			connection.error err
		else
			Fs.writeFile "#{dir}/#{id}.coffee", """
			# test file
			"""


playbox = new Playbox 1157
