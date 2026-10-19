class_name OrphanCheck
extends RefCounted
## Finds an orphaned server child on client start (FT-NET-003, D96, TECH-8):
## a server left running by a host client that crashed. `decide` is the pure
## decision table; `inspect` gathers the facts from the pid file, the process
## table and the stored token; `apply_automatic` and `terminate` act on it.
##
## A server with a session is never killed without asking, since other players
## may still be playing on it: the client offers to rejoin with its stored token
## or, without one, asks before terminating.

enum Action {
	## No pid file: nothing to do.
	NONE,
	## The recorded process is gone, or its pid now belongs to another program:
	## remove the pid file and touch no process.
	CLEAR_STALE,
	## Our server with no session: terminate it without asking.
	TERMINATE,
	## Our server with a session and a stored token for it: offer to rejoin;
	## terminate only if the player chooses.
	OFFER_REJOIN,
	## A server we can't rejoin or can't verify: ask before terminating.
	OFFER_TERMINATE,
	## A server from another install of the game: leave it alone.
	LEAVE,
}

enum Identity {
	## The pid runs something other than the recorded server.
	NOT_SERVER,
	## The recorded server, running from another executable (another install).
	OTHER_INSTALL,
	## The recorded server, running from this executable.
	OURS,
	## The pid is alive but this platform can't read its command line.
	UNVERIFIED,
}

var info: ServerPidFile
var token: SessionTokenFile
var action: Action = Action.NONE
var pid_file: String = ServerPidFile.PATH


## The decision table. `alive`: the recorded pid runs; `identity`: what runs
## there; `has_token`: a stored token names this server's port.
static func decide(file: ServerPidFile, alive: bool, identity: Identity, has_token: bool) -> Action:
	if file == null:
		return Action.NONE
	if not alive or identity == Identity.NOT_SERVER:
		return Action.CLEAR_STALE
	if identity == Identity.OTHER_INSTALL:
		return Action.LEAVE
	if file.session_active:
		return Action.OFFER_REJOIN if has_token else Action.OFFER_TERMINATE
	# Provisional: without a way to verify the process, ask rather than risk
	# killing whatever reused the pid.
	return Action.TERMINATE if identity == Identity.OURS else Action.OFFER_TERMINATE


## Classifies a process's argument list against the recorded and the running
## executable. An empty list means the command line couldn't be read.
static func identify(cmdline: PackedStringArray, recorded: String, ours: String) -> Identity:
	if cmdline.is_empty():
		return Identity.UNVERIFIED
	if cmdline[0] != recorded or not cmdline.has("--server"):
		return Identity.NOT_SERVER
	return Identity.OURS if recorded == ours else Identity.OTHER_INSTALL


## Splits a /proc/<pid>/cmdline buffer (NUL-separated, NUL-terminated).
static func split_cmdline(raw: PackedByteArray) -> PackedStringArray:
	var out: PackedStringArray = []
	var start: int = 0
	for i: int in range(raw.size()):
		if raw[i] == 0:
			out.append(raw.slice(start, i).get_string_from_utf8())
			start = i + 1
	if start < raw.size():
		out.append(raw.slice(start).get_string_from_utf8())
	return out


## True if `pid` runs. `OS.is_process_running` only sees our own children on
## Linux and macOS, so this asks /proc there and `kill -0` on macOS.
static func process_alive(pid: int) -> bool:
	if pid <= 0:
		return false
	match OS.get_name():
		"Linux":
			return DirAccess.dir_exists_absolute("/proc/%d" % pid)
		"macOS":
			return OS.execute("kill", ["-0", str(pid)]) == 0
	return OS.is_process_running(pid)


## The process's arguments, or [] where they can't be read (only Linux reads
## them, from /proc; elsewhere the identity stays UNVERIFIED, provisional).
static func read_cmdline(pid: int) -> PackedStringArray:
	if OS.get_name() != "Linux":
		return []
	var file: FileAccess = FileAccess.open("/proc/%d/cmdline" % pid, FileAccess.READ)
	if file == null:
		return []
	# /proc files report length 0, so read a fixed-size buffer.
	return split_cmdline(file.get_buffer(65536))


## Gathers the facts and decides; changes nothing.
static func inspect(
	pid_path: String = ServerPidFile.PATH, token_path: String = SessionTokenFile.PATH
) -> OrphanCheck:
	var check: OrphanCheck = OrphanCheck.new()
	check.pid_file = pid_path
	check.info = ServerPidFile.load_from(pid_path)
	if check.info == null:
		return check
	check.token = SessionTokenFile.load_from(token_path)
	var has_token: bool = check.token != null and check.token.port == check.info.port
	var alive: bool = process_alive(check.info.pid)
	var identity: Identity = Identity.NOT_SERVER
	if alive:
		identity = identify(
			read_cmdline(check.info.pid), check.info.executable, OS.get_executable_path()
		)
	check.action = decide(check.info, alive, identity, has_token)
	return check


## Does what needs no player: clears a stale pid file or terminates an idle
## orphan. Returns true if the player must be asked (OFFER_REJOIN or
## OFFER_TERMINATE).
func apply_automatic() -> bool:
	match action:
		Action.CLEAR_STALE:
			ServerPidFile.remove(pid_file)
		Action.TERMINATE:
			terminate()
		Action.OFFER_REJOIN, Action.OFFER_TERMINATE:
			return true
	return false


## Kills the orphan and removes its pid file. Also what the player's
## "terminate" choice calls.
func terminate() -> void:
	if info == null:
		return
	if process_alive(info.pid):
		OS.kill(info.pid)
	ServerPidFile.remove(pid_file)
