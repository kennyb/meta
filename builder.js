
var Fs = require("fs"),
	Path = require("path"),
	exec = require('child_process').exec,
	spawn = require('child_process').spawn,
	sys = require('sys');
	

function run() {
	var args = Array.prototype.slice.call(arguments, 0),
		prog = args.shift(),
		lastarg = args[args.length-1],
		callback = typeof lastarg === 'function' || !lastarg ? args.pop() : null,
		child;

	if(!args.length) {
		args.push("-c", prog);
		prog = "sh";
	}

	child = spawn(prog, args);
	child.stdout.addListener("data", function (chunk) { chunk && sys.print(chunk) });
	child.stderr.addListener("data", function (chunk) { chunk && sys.debug(chunk) });
	if(callback) {
		child.addListener("exit", callback); // code, signal
	}
}

function symlink(src, dest, callback) {
	src = Path.resolve(src);
	dest = Path.normalize(dest);
	if(typeof callback !== "function") {
		callback = function(err) {
			if(err) throw new Error("symlink('"+src+"', '"+dest+"')\n"+err);
		};
	}

	//console.log("symlink(", src, dest, ")");
	Fs.lstat(dest, function(err, dest_st) {
		if(err) {
			if(err.code === 'ENOENT') {
				Fs.symlink(src, dest, callback);
			} else {
				callback(err);
			}
		} else if(dest_st.isSymbolicLink()) {
			callback(Fs.readlinkSync(dest) == src ? null : new Error("symlink exists and points to something else"));
		} else {
			callback(new Error("destination exists and is not a symlink"));
		}
	});
}

function cp(src, dest, callback) {
	if(typeof cp.i !== 'number') {
		cp.i = 0;
		cp.q = [];
	}

	if(cp.i > 4) {
		cp.q.push(arguments);
	} else {
		cp.i++;
		callback = function(c) {
			return function() {
				cp.i--;
				if(cp.q && cp.q.length) {
					cp.apply(this, cp.q.shift());
				}

				if(typeof c === 'function') {
					c.apply(this, arguments);
				}
			}
		}(callback);
		sys.pump(Fs.createReadStream(src), Fs.createWriteStream(dest), callback);
	}
}


function copy(src, dest, opts, callback) {
	src = Path.resolve(src);
	dest = Path.normalize(dest);
	if(typeof opts === 'function') {
		callback = opts;
		opts = {};
	} else if(typeof opts !== 'object') {
		opts = {};
	}

	callback = function(c) {
		return function() {
			if((--copy.i) === 0 && typeof c === 'function') {
				c.apply(this, arguments);
			}
		}
	}(callback);

	var monitor = opts.monitor || 0,
		monitored_exts = opts.monitored_exts || ['.js', '.html', '.css', '.less'],
		onupdate = opts.onupdate;

	if(typeof copy.i !== 'number') {
		copy.i = 0;
	}

	var ext = Path.extname(src);
	switch(ext) {
		case '.so':
		case '.dll':
		case '.dylib':
			var base_src = src.substr(0, src.length - ext.length);
			var base_dest = dest.substr(0, dest.length - ext.length);
			var platform = process.platform;

			if(platform === "darwin") {
				src = base_src+".dylib";
				dest = base_dest+".dylib";
			} else if(platform === 'linux') {
				src = base_src+".so";
				dest = base_dest+".so";
			} else {
				console.error("platform '"+platform+"' is not yet supported"); 
			}
	}

	Fs.stat(dest, function(err, dest_st) {
		if(err && err.code !== 'ENOENT') {
			return callback(err);
		} else {
			Fs.stat(src, function(err, src_st) {
				if(err) return callback(err);
				if(src_st.isFile()) {
					copy.i++;

					if(monitor && monitored_exts.indexOf(Path.extname(src)) !== -1) {
						var watch_func = function(old_st, new_st) {
							if(old_st.mtime.getTime() !== new_st.mtime.getTime()) {
								console.log("file modified: "+dest);
								check(src, function(code, signal) {
									if(code <= 1) {
										cp(src, dest, function(err) {
											if(err) {
												throw err;
											} else {
												console.log("updated", dest);
												if(typeof onupdate === 'function') {
													onupdate.apply(this, arguments);
												}
											}
										});
									} else {
										console.log("fatal code errors... not updating");
									}
								});
							} else {
								console.log("file not modified: "+dest);
							}
						},
						cp_callback = function(err) {
							if(!err && global.mode === 'dev') {
								console.log("watching", src, "...");
								Fs.watchFile(src, watch_func);
							}

							if(typeof callback === 'function') {
								callback(err);
							} else {
								throw err;
							}
						};

						/*
						watch_func = typeof callback !== "function" ? watch_func : function(old_st, new_st) {
							watch_func(old_st, new_st);
							callback(src, old_st, new_st);
						};
						*/

						if(!dest_st || src_st.mtime.getTime() !== dest_st.mtime.getTime()) {
							cp(src, dest, function(err) {
								if(err) {
									throw err;
								}

								console.log('set utimes');
								Fs.utimes(dest, src_st.atime, src_st.mtime, cp_callback);
							});
						} else {
							cp_callback(0);
						}
					} else if(!dest_st || src_st.mtime.getTime() !== dest_st.mtime.getTime()) {
						cp(src, dest, function(err) {
							if(err) {
								throw err;
							}

							Fs.utimes(dest, src_st.atime, src_st.mtime, callback);
						});
					} else {
						callback(0);
					}
				} else if(src_st.isDirectory()) {
					mkdirs(dest, function() {
						Fs.readdir(src, function(err, files) {
							if(err) throw err;

							var i = files.length-1, f;
							if(i >= 0) {
								do {
									f = files[i];
									if(f.charAt(0) !== '.' && f.indexOf('test') !== 0) {
										copy(src+"/"+f, dest+"/"+f, opts, callback);
									}
								} while(i--);
							}
						});
					});
				}
			});
		}
	});
}

function mkdirs(dirname, mode, callback) {
	if(typeof mode === 'function') {
		callback = mode;
		mode = undefined;
	}

	if(mode === undefined) {
		mode = 0x1ff ^ process.umask();
	}

	//console.log("mkdir(", dirname, mode.toString(8), ")");
	var pathsCreated = [];
	var pathsFound = [];

	var makeNext = function() {
		var fn = pathsFound.pop();
		if (!fn) {
			if (callback) callback(null, pathsCreated);
		}
		else {
			Fs.mkdir(fn, mode, function(err) {
				if (!err) {
					pathsCreated.push(fn);
					makeNext();
				}
				else if (callback) {
					callback(err);
				}
			});
		}
	};

	var findNext = function(fn) {
		Fs.stat(fn, function(err, stats) {
			if(err) {
				if(err.code === 'ENOENT') {
					pathsFound.push(fn);
					findNext(Path.dirname(fn));
				} else if(callback) {
					callback(err);
				}
			} else if(stats.isDirectory()) {
				// create all dirs we found up to this dir
				makeNext();
			} else if(callback) {
				callback(new Error('Unable to create directory at '+fn));
			}
		});
	};

	findNext(dirname);
}


function check(file, callback) {
	if(file.charAt(0) !== '/') {
		file = './'+file;
	}

	file = Path.resolve(process.cwd(), file);
	switch(Path.extname(file)) {
		case '.js':
			// if jsl is turned on
			run('deps/jsl/jsl', '-nologo', '-nofilelisting', '-nosummary', '-conf', 'jsl.conf', '-process', file, callback);
			break;

		default:
			if(typeof callback === 'function') {
				callback(0);
			}
	}
}

function src(src, dest, callback, opts) {
	if(typeof opts !== 'object') {
		opts = {};
	}

	opts.monitor = 1;
	return copy(src, dest, opts, callback);
}

function app(app, callback) {
	src('apps/'+app, 'build/release/apps/'+app, callback, {
		onupdate: function() {
			console.log("restart app: "+app);
		}
	});
}


exports.run = run;
exports.cp = cp;
exports.symlink = symlink;
exports.mkdirs = mkdirs;
exports.copy = copy;
exports.check = check;
exports.src = src;
exports.app = app;
