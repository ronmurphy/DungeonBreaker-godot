extends Node
## Music Manager — background music for camp and dungeon.
## Autoloaded as "MusicManager".

const CAMP_MUSIC    := "res://assets/music/forestDay.ogg"
const DUNGEON_MUSIC := "res://assets/music/forestNight.ogg"

var _player: AudioStreamPlayer = null
var _current_track: String = ""


func _ready():
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = -10.0
	add_child(_player)


func play_camp() -> void:
	_play(CAMP_MUSIC)


func play_dungeon() -> void:
	_play(DUNGEON_MUSIC)


func stop() -> void:
	_player.stop()
	_current_track = ""


func _play(path: String) -> void:
	if _current_track == path and _player.playing:
		return
	_current_track = path
	var stream = load(path)
	if stream == null:
		push_warning("MusicManager: could not load %s" % path)
		return
	stream.loop = true
	_player.stream = stream
	_player.play()
