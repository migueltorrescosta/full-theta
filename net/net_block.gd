class_name NetBlock
extends RefCounted
## Schema-driven encoding of a block of named fields (station field sets,
## StationViews.BLOCKS). A schema is an Array of [name, type] pairs written in order;
## a type is one of the strings below, or ["rows", schema] for a list of rows (u8
## count, then each row in the sub-schema). Values come as a Dictionary (rows as an
## Array of Dictionaries) and decode the same way, with floats where the type is one.
##
## Types: "bool" and "u8" (1 B), "u16", "s16" (2 B), "u32", "s32" (4 B), "f32"
## (4 B float), "v3f" (3 x f32), "v3n" (a unit vector, 3 x s16 over [-1, 1]).

const ROWS: String = "rows"


static func encode(schema: Array, values: Dictionary) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	put(buf, schema, values)
	return buf.data_array


static func decode(schema: Array, data: PackedByteArray) -> Dictionary:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = data
	return read(buf, schema)


static func put(buf: StreamPeerBuffer, schema: Array, values: Dictionary) -> void:
	for field: Array in schema:
		var name: String = field[0]
		var value: Variant = values.get(name)
		if field[1] is Array:
			var rows: Array = value if value is Array else []
			buf.put_u8(rows.size())
			for row: Dictionary in rows:
				put(buf, field[1][1], row)
			continue
		match field[1]:
			"bool", "u8":
				buf.put_u8(int(value))
			"u16":
				buf.put_u16(int(value))
			"s16":
				buf.put_16(int(value))
			"u32":
				buf.put_u32(int(value))
			"s32":
				buf.put_32(int(value))
			"f32":
				buf.put_float(float(value))
			"v3f":
				var v: Vector3 = value
				buf.put_float(v.x)
				buf.put_float(v.y)
				buf.put_float(v.z)
			"v3n":
				var n: Vector3 = (value as Vector3).clampf(-1.0, 1.0)
				buf.put_16(roundi(n.x * 32767.0))
				buf.put_16(roundi(n.y * 32767.0))
				buf.put_16(roundi(n.z * 32767.0))
			_:
				push_error("NetBlock: unknown type %s" % [field[1]])


static func read(buf: StreamPeerBuffer, schema: Array) -> Dictionary:
	var out: Dictionary = {}
	for field: Array in schema:
		var name: String = field[0]
		if field[1] is Array:
			var rows: Array[Dictionary] = []
			for i: int in range(buf.get_u8()):
				rows.append(read(buf, field[1][1]))
			out[name] = rows
			continue
		match field[1]:
			"bool":
				out[name] = buf.get_u8() != 0
			"u8":
				out[name] = buf.get_u8()
			"u16":
				out[name] = buf.get_u16()
			"s16":
				out[name] = buf.get_16()
			"u32":
				out[name] = buf.get_u32()
			"s32":
				out[name] = buf.get_32()
			"f32":
				out[name] = buf.get_float()
			"v3f":
				out[name] = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
			"v3n":
				out[name] = Vector3(buf.get_16(), buf.get_16(), buf.get_16()) / 32767.0
	return out
