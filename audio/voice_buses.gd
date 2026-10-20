class_name VoiceBuses
extends RefCounted
## The voice audio buses, created at runtime when the layout lacks them: `Voice` (sent to
## Master) for NPC radio, and `VoiceComputer` (sent to Voice) for the ship computer, which
## carries the robotic/radio filter (FT-AUD-004, D71). The filter approximates the S7 chain
## (docs/spikes/S7.md, "Ship-computer filter") with built-in effects: a 6 ms feedforward
## comb, a 300-3,400 Hz band-pass and a light lo-fi bitcrush. Built-in effects have no ring
## modulator, so the S7 70 Hz ring modulation is left out. Alert tones (FT-AUD-009) use
## their own bus, never these.

const VOICE: String = "Voice"
const COMPUTER: String = "VoiceComputer"

## PROVISIONAL filter settings (S7: comb 6 ms at gain 0.45, band 300-3,400 Hz, 6-bit crush).
const COMB_DELAY_MS: float = 6.0
const COMB_LEVEL_DB: float = -6.9
const BAND_LOW_HZ: float = 300.0
const BAND_HIGH_HZ: float = 3400.0
const CRUSH_DRIVE: float = 0.3


## The bus a line of `role` plays on.
static func bus_for(role: String) -> String:
	return COMPUTER if role == "computer" else VOICE


## Creates the missing buses (with the computer filter); existing buses are left as they are.
static func ensure() -> void:
	_ensure_bus(VOICE, "Master")
	if _ensure_bus(COMPUTER, VOICE):
		var index: int = AudioServer.get_bus_index(COMPUTER)
		for effect: AudioEffect in computer_effects():
			AudioServer.add_bus_effect(index, effect)


## The ship-computer filter chain, in order.
static func computer_effects() -> Array[AudioEffect]:
	var comb: AudioEffectDelay = AudioEffectDelay.new()
	comb.dry = 1.0
	comb.tap1_active = true
	comb.tap1_delay_ms = COMB_DELAY_MS
	comb.tap1_level_db = COMB_LEVEL_DB
	comb.tap1_pan = 0.0
	comb.tap2_active = false
	comb.feedback_active = false
	var high_pass: AudioEffectHighPassFilter = AudioEffectHighPassFilter.new()
	high_pass.cutoff_hz = BAND_LOW_HZ
	var low_pass: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
	low_pass.cutoff_hz = BAND_HIGH_HZ
	var crush: AudioEffectDistortion = AudioEffectDistortion.new()
	crush.mode = AudioEffectDistortion.MODE_LOFI
	crush.drive = CRUSH_DRIVE
	return [comb, high_pass, low_pass, crush]


## Adds bus `bus_name` sending to `send` if it is missing; true when it was added.
static func _ensure_bus(bus_name: String, send: String) -> bool:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return false
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)
	return true
