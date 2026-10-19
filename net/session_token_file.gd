class_name SessionTokenFile
extends RefCounted
## The reconnect token a client got from a server, kept in user data so a
## relaunched client can rejoin (D6, D96, FT-NET-003). The client library
## saves it after a successful join and removes it when the player leaves.
## A host client also keeps the host secret its launcher gave the server
## (D127), so a relaunched host rejoins its orphan as the host. Kept here, in
## the user's own data, not in the pid file, readable by the user only (0600 where
## the platform has Unix permissions).

const PATH: String = "user://session_token.json"
## rw------- (0600).
const OWNER_ONLY: int = FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER

var token: String = ""
var host: String = ""
var port: int = 0
## Hex host secret (D127); "" for a client that didn't host.
var host_secret: String = ""


static func make(
	token_value: String, host_address: String, ws_port: int, secret: String = ""
) -> SessionTokenFile:
	var t: SessionTokenFile = SessionTokenFile.new()
	t.token = token_value
	t.host = host_address
	t.port = ws_port
	t.host_secret = secret
	return t


## Writes the file, restricting it to the user before the secret goes in.
func save(path: String = PATH) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.close()
	if OS.get_name() in ["Linux", "macOS", "FreeBSD"]:
		var err: Error = FileAccess.set_unix_permissions(path, OWNER_ONLY)
		if err != OK:
			return err
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var d: Dictionary = {"token": token, "host": host, "port": port, "host_secret": host_secret}
	file.store_string(JSON.stringify(d))
	file.close()
	return OK


## The stored token, or null if there is none or the file is malformed.
static func load_from(path: String = PATH) -> SessionTokenFile:
	if not FileAccess.file_exists(path):
		return null
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return null
	var tok: Variant = d.get("token")
	var hst: Variant = d.get("host")
	var prt: Variant = d.get("port")
	var sec: Variant = d.get("host_secret", "")
	if not (tok is String and hst is String and sec is String and (prt is float or prt is int)):
		return null
	if tok == "":
		return null
	return make(tok, hst, int(prt), sec)


static func remove(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
