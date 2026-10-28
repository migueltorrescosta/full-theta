class_name VoicePack
extends RefCounted
## One language's prerendered client lines in one file, voice-<lang>.pack (D294, load
## fix 9): the web export ships no clips in its pack, and a browser station fetches its
## session language's pack once (WebSession) and hands it to LocalLines.add_pack. Format
## (tools/release/voice_pack.py writes it): "FTVP", u32 version 1, u32 header length N,
## N bytes of JSON {"language", "clips": {line id: [offset, size]}}, then the Ogg files;
## offsets count from the end of the header, integers little-endian. Clips are decoded on
## first use.

const MAGIC: String = "FTVP"
const VERSION: int = 1
const HEAD: int = 12

var language: String = ""
var _data: PackedByteArray
var _start: int = 0
var _clips: Dictionary = {}  # line id -> [offset, size]


## The pack in `data`, or null when it is malformed (a clip outside the data counts).
static func parse(data: PackedByteArray) -> VoicePack:
	if data.size() < HEAD or data.slice(0, 4).get_string_from_ascii() != MAGIC:
		return null
	if data.decode_u32(4) != VERSION:
		return null
	var size: int = data.decode_u32(8)
	if HEAD + size > data.size():
		return null
	var header: Variant = JSON.parse_string(data.slice(HEAD, HEAD + size).get_string_from_utf8())
	if not header is Dictionary or not (header as Dictionary).get("clips") is Dictionary:
		return null
	var p: VoicePack = VoicePack.new()
	p.language = str((header as Dictionary).get("language", ""))
	p._data = data
	p._start = HEAD + size
	var clips: Dictionary = (header as Dictionary)["clips"]
	for line: Variant in clips:
		var span: Variant = clips[line]
		if not span is Array or (span as Array).size() != 2:
			return null
		var offset: int = int((span as Array)[0])
		var length: int = int((span as Array)[1])
		if offset < 0 or length <= 0 or p._start + offset + length > data.size():
			return null
		p._clips[str(line)] = [offset, length]
	return p


func has(line_id: String) -> bool:
	return _clips.has(line_id)


func size() -> int:
	return _clips.size()


## The line's Ogg file, or empty when the pack has none.
func clip(line_id: String) -> PackedByteArray:
	if not _clips.has(line_id):
		return PackedByteArray()
	var span: Array = _clips[line_id]
	var at: int = _start + int(span[0])
	return _data.slice(at, at + int(span[1]))


## The line's stream, or null when the pack has none.
func stream(line_id: String) -> AudioStream:
	if not _clips.has(line_id):
		return null
	return AudioStreamOggVorbis.load_from_buffer(clip(line_id))
