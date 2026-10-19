extends GdUnitTestSuite
## ServerPidFile and SessionTokenFile: the records a host keeps in user data.

const PID_FILE: String = "user://host_test_pid.json"
const TOKEN_FILE: String = "user://host_test_token.json"


func after_test() -> void:
	ServerPidFile.remove(PID_FILE)
	SessionTokenFile.remove(TOKEN_FILE)


func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# FT: FT-NET-003
func test_pid_file_round_trip() -> void:
	var info: ServerPidFile = ServerPidFile.for_this_process(47800, "127.0.0.1")
	info.session_active = true
	assert_int(info.pid).is_equal(OS.get_process_id())
	assert_str(info.executable).is_equal(OS.get_executable_path())
	assert_int(info.started_unix).is_greater(1_700_000_000)
	assert_int(info.save(PID_FILE)).is_equal(OK)
	assert_bool(FileAccess.file_exists(PID_FILE + ".tmp")).is_false()
	var back: ServerPidFile = ServerPidFile.load_from(PID_FILE)
	assert_object(back).is_not_null()
	assert_dict(back.to_dict()).is_equal(info.to_dict())
	ServerPidFile.remove(PID_FILE)
	assert_bool(FileAccess.file_exists(PID_FILE)).is_false()
	assert_object(ServerPidFile.load_from(PID_FILE)).is_null()


# FT: FT-NET-003
func test_pid_file_rewrite_replaces_the_record() -> void:
	var info: ServerPidFile = ServerPidFile.for_this_process(47800, "127.0.0.1")
	info.save(PID_FILE)
	info.session_active = true
	info.save(PID_FILE)
	assert_bool(ServerPidFile.load_from(PID_FILE).session_active).is_true()


func test_malformed_pid_files_read_as_none() -> void:
	_write(PID_FILE, "not json")
	assert_object(ServerPidFile.load_from(PID_FILE)).is_null()
	_write(PID_FILE, "[1, 2]")
	assert_object(ServerPidFile.load_from(PID_FILE)).is_null()
	var d: Dictionary = ServerPidFile.for_this_process(1, "127.0.0.1").to_dict()
	d.erase("session_active")
	assert_object(ServerPidFile.from_dict(d)).is_null()
	d = ServerPidFile.for_this_process(1, "127.0.0.1").to_dict()
	d["format"] = 99
	assert_object(ServerPidFile.from_dict(d)).is_null()
	d = ServerPidFile.for_this_process(1, "127.0.0.1").to_dict()
	d["pid"] = 0
	assert_object(ServerPidFile.from_dict(d)).is_null()


func test_token_file_round_trip() -> void:
	assert_object(SessionTokenFile.load_from(TOKEN_FILE)).is_null()
	(
		assert_int(SessionTokenFile.make("abc123", "127.0.0.1", 47800, "5ec7").save(TOKEN_FILE))
		. is_equal(OK)
	)
	var back: SessionTokenFile = SessionTokenFile.load_from(TOKEN_FILE)
	assert_str(back.token).is_equal("abc123")
	assert_str(back.host).is_equal("127.0.0.1")
	assert_int(back.port).is_equal(47800)
	assert_str(back.host_secret).is_equal("5ec7")
	# A file without a secret (a client that didn't host) still reads.
	SessionTokenFile.make("t", "10.0.0.2", 47800).save(TOKEN_FILE)
	assert_str(SessionTokenFile.load_from(TOKEN_FILE).host_secret).is_equal("")
	SessionTokenFile.remove(TOKEN_FILE)
	assert_object(SessionTokenFile.load_from(TOKEN_FILE)).is_null()


# FT: FT-NET-001
# D127: the token file holds the host secret, so only its user can read it (0600),
# also when it replaces a file another program left world-readable.
func test_token_file_is_private_to_the_user() -> void:
	if not OS.get_name() in ["Linux", "macOS", "FreeBSD"]:
		return
	_write(TOKEN_FILE, "{}")
	FileAccess.set_unix_permissions(TOKEN_FILE, 0x1A4)  # 0644
	assert_int(SessionTokenFile.make("t", "10.0.0.2", 1, "5ec7").save(TOKEN_FILE)).is_equal(OK)
	assert_int(FileAccess.get_unix_permissions(TOKEN_FILE)).is_equal(0x180)  # 0600
	assert_str(SessionTokenFile.load_from(TOKEN_FILE).host_secret).is_equal("5ec7")
	SessionTokenFile.remove(TOKEN_FILE)
	assert_object(SessionTokenFile.load_from(TOKEN_FILE)).is_null()


func test_malformed_token_files_read_as_none() -> void:
	_write(TOKEN_FILE, "{")
	assert_object(SessionTokenFile.load_from(TOKEN_FILE)).is_null()
	_write(TOKEN_FILE, '{"token": "", "host": "h", "port": 1}')
	assert_object(SessionTokenFile.load_from(TOKEN_FILE)).is_null()
	_write(TOKEN_FILE, '{"token": "t", "host": "h"}')
	assert_object(SessionTokenFile.load_from(TOKEN_FILE)).is_null()
