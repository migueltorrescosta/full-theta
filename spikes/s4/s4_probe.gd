extends SceneTree
## S4 probe (FT-NET-038): reads the WebSocketPeer buffer defaults at runtime and
## tries single unchunked messages of growing size over loopback, in one
## process, reporting what send() returns and what the other side receives.
##
## godot --headless --path . -s res://spikes/s4/s4_probe.gd -- [--port 47819]

var _port: int = 47819
var _tcp: TCPServer = TCPServer.new()
var _server_peer: WebSocketPeer
var _client: WebSocketPeer = WebSocketPeer.new()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--port":
		_port = args[1].to_int()
	print(
		(
			"defaults: inbound_buffer_size=%d outbound_buffer_size=%d max_queued_packets=%d"
			% [
				_client.inbound_buffer_size,
				_client.outbound_buffer_size,
				_client.max_queued_packets
			]
		)
	)
	for size: int in [16393, 60000, 65535, 70000, 132440]:
		_try(size, 0)
	# Sender outbound raised to 1 MiB, receiver inbound left at its default.
	for size: int in [70000, 132440]:
		_try(size, 1 << 20)
	quit()


func _try(size: int, sender_outbound: int) -> void:
	_tcp = TCPServer.new()
	_tcp.listen(_port, "127.0.0.1")
	_client = WebSocketPeer.new()
	_client.connect_to_url("ws://127.0.0.1:%d" % _port)
	_server_peer = null
	var deadline: int = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		if _server_peer == null and _tcp.is_connection_available():
			_server_peer = WebSocketPeer.new()
			if sender_outbound > 0:
				_server_peer.outbound_buffer_size = sender_outbound
			_server_peer.accept_stream(_tcp.take_connection())
		_client.poll()
		if _server_peer != null:
			_server_peer.poll()
			var both_open: bool = (
				_server_peer.get_ready_state() == WebSocketPeer.STATE_OPEN
				and _client.get_ready_state() == WebSocketPeer.STATE_OPEN
			)
			if both_open:
				break
		OS.delay_msec(1)
	var data: PackedByteArray = PackedByteArray()
	data.resize(size)
	var err: Error = _server_peer.send(data)
	var buffered: int = _server_peer.get_current_outbound_buffered_amount()
	var received: int = -1
	deadline = Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline and received < 0:
		_server_peer.poll()
		_client.poll()
		if _client.get_available_packet_count() > 0:
			received = _client.get_packet().size()
		OS.delay_msec(1)
	print(
		(
			(
				"send %d bytes (sender outbound %d): err=%s buffered_after=%d received=%d"
				+ " client_state=%d close_code=%d"
			)
			% [
				size,
				_server_peer.outbound_buffer_size,
				error_string(err),
				buffered,
				received,
				_client.get_ready_state(),
				_client.get_close_code(),
			]
		)
	)
	_client.close()
	_server_peer.close()
	for i: int in range(20):
		_client.poll()
		_server_peer.poll()
		OS.delay_msec(1)
	_tcp.stop()
