class_name Sfx
extends Node

# Procedural sound: every effect is synthesized at boot into AudioStreamWAV
# (no audio files). A small pool of players lets effects overlap.

const MIX_RATE := 22050

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_streams["shot"] = _noise_burst(0.14, 0.9, 1800.0)
	_streams["shotgun"] = _noise_burst(0.22, 1.0, 900.0)
	_streams["boom"] = _tone(90.0, 38.0, 0.8, 0.9, true)
	_streams["groan"] = _tone(110.0, 62.0, 0.7, 0.5, false)
	_streams["hit"] = _tone(1400.0, 900.0, 0.06, 0.35, false)
	_streams["hurt"] = _tone(220.0, 140.0, 0.25, 0.6, false)
	_streams["reload"] = _tone(700.0, 500.0, 0.08, 0.3, false)
	_streams["beep"] = _tone(1200.0, 1200.0, 0.09, 0.3, false)
	_streams["splash"] = _noise_burst(0.25, 0.4, 500.0)
	_streams["sting"] = _tone(55.0, 55.0, 1.2, 0.7, true)
	_streams["drip"] = _tone(900.0, 300.0, 0.12, 0.25, false)
	_streams["trap"] = _tone(300.0, 900.0, 0.18, 0.4, false)

func play(name: String, volume_db: float = 0.0) -> void:
	var s: AudioStreamWAV = _streams.get(name, null)
	if s == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.play()
			return
	# All busy: steal the first player.
	_players[0].stream = s
	_players[0].volume_db = volume_db
	_players[0].play()

func _make_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = bytes
	return w

# Decaying white noise, roughly low-passed by averaging neighbours.
func _noise_burst(dur: float, vol: float, _cutoff: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := (1.0 - t) * (1.0 - t)
		var white := randf() * 2.0 - 1.0
		prev = prev * 0.55 + white * 0.45
		samples[i] = prev * env * vol
	return _make_stream(samples)

# Sine / square-ish tone sweeping from f0 to f1 with exponential decay.
func _tone(f0: float, f1: float, dur: float, vol: float, low: bool) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(f0, f1, t)
		phase += TAU * f / float(MIX_RATE)
		var env := exp(-3.5 * t)
		var s := sin(phase)
		if low:
			# Add a little square edge for industrial weight.
			s = s * 0.7 + (1.0 if sin(phase) > 0.0 else -1.0) * 0.3
		samples[i] = s * env * vol
	return _make_stream(samples)
