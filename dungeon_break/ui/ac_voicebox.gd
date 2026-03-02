extends AudioStreamPlayer
class_name ACVoiceBox

signal characters_sounded(characters)
signal finished_phrase()

@export var base_pitch: float = 3.5
@export var play_speed: float = 1.0 # Multiplier applied to playback speed (1.0 = normal)

# Expects letter .wav samples in res://assets/sounds/ (a.wav–z.wav, th.wav, sh.wav, blank.wav, longblank.wav).
# Ported from theLongNights ACVoicebox (MIT license).

const PITCH_MULTIPLIER_RANGE := 0.3
const INFLECTION_SHIFT := 0.4

var sounds := {}
var remaining_sounds := []

func _ready():
    var base = "res://assets/sounds/"
    var keys = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z","th","sh"," ","."]
    for k in keys:
        var path = base + k + ".wav"
        if ResourceLoader.exists(path):
            sounds[k] = load(path)
        else:
            sounds[k] = null

    connect("finished", Callable(self, "_on_stream_finished"))

func play_string(in_string: String) -> void:
    remaining_sounds.clear()
    parse_input_string(in_string)
    play_next_sound()

func play_next_sound() -> void:
    if remaining_sounds.size() == 0:
        emit_signal("finished_phrase")
        return

    var next_symbol = remaining_sounds.pop_front()
    emit_signal("characters_sounded", next_symbol.characters)

    # Skip if no mapped sound
    if next_symbol.sound == "" or not sounds.has(next_symbol.sound) or sounds[next_symbol.sound] == null:
        # Small delay based on play_speed
        var gap = max(0.01, 0.05 / play_speed)
        get_tree().create_timer(gap).timeout.connect(Callable(self, "play_next_sound"))
        return

    var sound: AudioStream = sounds[next_symbol.sound]
    pitch_scale = base_pitch + (PITCH_MULTIPLIER_RANGE * randf()) + (INFLECTION_SHIFT if next_symbol.inflective else 0.0)
    stream = sound
    play()

func _on_stream_finished() -> void:
    # Small gap before next sound - scaled by play_speed
    var gap = max(0.01, 0.05 / play_speed)
    get_tree().create_timer(gap).timeout.connect(Callable(self, "play_next_sound"))

func parse_input_string(in_string: String) -> void:
    for word in in_string.split(' '):
        parse_word(word)
        add_symbol(' ', ' ', false)

func parse_word(word: String) -> void:
    var skip_char := false
    var is_inflective := word.ends_with('?')
    for i in range(word.length()):
        if skip_char:
            skip_char = false
            continue

        if i < word.length() - 1:
            var two = word.substr(i, 2).to_lower()
            if two in sounds.keys():
                add_symbol(two, two, is_inflective)
                skip_char = true
                continue

        var letter = word[i].to_lower()
        if letter in sounds.keys():
            add_symbol(letter, letter, is_inflective)
        else:
            add_symbol('', word[i], false)

func add_symbol(sound: String, characters: String, inflective: bool) -> void:
    remaining_sounds.append({
        'sound': sound,
        'characters': characters,
        'inflective': inflective
    })


func stop_speaking() -> void:
    remaining_sounds.clear()
    stop()
