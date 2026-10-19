class_name HostSession
extends RefCounted
## The client side of hosting (FT-NET-001, FT-NET-003, FT-M1-002, D7, D96, D127,
## TECH-8), without UI: #7's Host button and orphan dialog call it. Poll-driven like
## NetClient: call poll() every frame.
##
## Host: host() spawns this executable as a headless server child (HostLauncher),
## waits for its pid file, connects a NetClient to ws://127.0.0.1:<port> presenting
## the launcher's host secret, and once welcomed stores the token and secret
## (SessionTokenFile) so a relaunched client can rejoin. stop() says Bye, kills the
## child and removes the pid and token files: call it when the host exits or leaves.
##
## Client start: check_orphan() runs OrphanCheck. A stale pid file or an orphan with
## no session is handled without asking; an orphan with a session asks the player
## (the `choose` callable returns an Answer) and, on REJOIN, returns a HostSession
## that reconnects with the stored token: the same session, ship and pick, as host.

enum State { IDLE, STARTING, CONNECTING, JOINED, FAILED, STOPPED }
## The player's answer to an orphan offer.
enum Answer { REJOIN, TERMINATE, LEAVE }

## The host client connects to its child over loopback (FT-NET-001).
const ADDRESS: String = "127.0.0.1"
## PROVISIONAL: how long the child may take to listen (a cold start on a slow
## machine), and the handshake after that.
const READY_TIMEOUT_MS: int = 30_000
const JOIN_TIMEOUT_MS: int = 10_000

var launcher: HostLauncher = HostLauncher.new()
var client: NetClient = NetClient.new()
var state: State = State.IDLE
## Why the last start or join failed, for the UI.
var error: String = ""
var token_file: String = SessionTokenFile.PATH
var ready_timeout_ms: int = READY_TIMEOUT_MS
var join_timeout_ms: int = JOIN_TIMEOUT_MS

var _deadline_ms: int = 0


func _init(player_name: String = "host") -> void:
	client.name = player_name
	client.client_kind = "desktop"


## Starts a server child on `ws_port` (0: a free port) and joins it as the host.
func host(
	ws_port: int = ServerMain.DEFAULT_PORT,
	idle_exit_min: float = HostLauncher.DEFAULT_IDLE_EXIT_MIN
) -> Error:
	var err: Error = launcher.spawn(ws_port, launcher.pid_file, idle_exit_min)
	if err != OK:
		_fail("can't start the server: %s" % error_string(err))
		return err
	state = State.STARTING
	_deadline_ms = Time.get_ticks_msec() + ready_timeout_ms
	return OK


## Rejoins an orphaned server with the stored token and host secret (OFFER_REJOIN).
func rejoin(check: OrphanCheck) -> Error:
	launcher.adopt(check.info, check.token.host_secret, check.pid_file)
	client.token = check.token.token
	return _connect()


## Advances the start-up and the client; call every frame.
func poll() -> void:
	match state:
		State.STARTING:
			if launcher.is_ready():
				_connect()
			elif not launcher.is_running():
				_fail("the server stopped during start-up")
			elif Time.get_ticks_msec() > _deadline_ms:
				_fail("the server didn't start in time")
		State.CONNECTING:
			client.poll()
			if client.is_welcomed():
				state = State.JOINED
				_save_token()
			elif client.state == NetClient.State.REJECTED:
				_fail("the server refused the host: %s" % client.reject_reason)
			elif client.state == NetClient.State.CLOSED:
				_fail("can't connect to the server")
			elif Time.get_ticks_msec() > _deadline_ms:
				_fail("the server didn't answer in time")
		State.JOINED:
			client.poll()


func is_joined() -> bool:
	return state == State.JOINED


## Leaves and terminates the server: Bye, kill, remove the pid and token files
## (FT-NET-003). Also the clean-up after a failure.
func stop() -> void:
	if client.state == NetClient.State.WELCOMED:
		client.bye()
	launcher.stop()
	SessionTokenFile.remove(token_file)
	state = State.STOPPED


## Client start (FT-NET-003, TECH-8): looks for an orphaned server. Clears a stale
## pid file and terminates an orphan without a session by itself; for one with a
## session (or one it can't verify) it calls `choose(check) -> Answer`. Returns a
## HostSession rejoining the orphan when the answer is REJOIN to OFFER_REJOIN, else
## null. TERMINATE kills the orphan; LEAVE leaves it running.
static func check_orphan(
	choose: Callable,
	pid_path: String = ServerPidFile.PATH,
	token_path: String = SessionTokenFile.PATH
) -> HostSession:
	var check: OrphanCheck = OrphanCheck.inspect(pid_path, token_path)
	var names_it: bool = (
		check.token != null and check.info != null and check.token.port == check.info.port
	)
	if not check.apply_automatic():
		if names_it and check.action != OrphanCheck.Action.LEAVE:
			SessionTokenFile.remove(token_path)
		return null
	var answer: Answer = choose.call(check)
	if answer == Answer.REJOIN and check.action == OrphanCheck.Action.OFFER_REJOIN:
		var s: HostSession = HostSession.new()
		s.token_file = token_path
		s.rejoin(check)
		return s
	if answer == Answer.TERMINATE:
		check.terminate()
		if names_it:
			SessionTokenFile.remove(token_path)
	return null


func _connect() -> Error:
	client.host_secret = launcher.host_secret
	state = State.CONNECTING
	_deadline_ms = Time.get_ticks_msec() + join_timeout_ms
	var err: Error = client.connect_to(JoinAddress.ws_url(ADDRESS, launcher.port))
	if err != OK:
		_fail("can't connect to the server: %s" % error_string(err))
	return err


## The token and host secret go to user data so a relaunched client can rejoin.
func _save_token() -> void:
	var t: SessionTokenFile = SessionTokenFile.make(
		client.token, ADDRESS, launcher.port, launcher.host_secret
	)
	if t.save(token_file) != OK:
		push_warning("can't store the session token in %s" % token_file)


func _fail(why: String) -> void:
	error = why
	state = State.FAILED
