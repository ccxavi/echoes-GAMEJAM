extends Node

@onready var music_player: AudioStreamPlayer2D = $MusicPlayer

# Create a dictionary to hold your sounds for easy access
var sounds = {
	"switch": preload("res://assets/audio/switch.wav"),
	"woosh": preload("res://assets/audio/woosh.wav"),
	"hit": preload("res://assets/audio/hit.wav"),
	"crit": preload("res://assets/audio/crit.wav"),
	"fire": preload("res://assets/audio/fire.wav"),
	"grass": preload("res://assets/audio/grass.wav"),
	"dash": preload("res://assets/audio/dash.wav"),
	"torch": preload("res://assets/audio/torch.wav"),
	"enemy_death": preload("res://assets/audio/enemy_death.wav"),
	"heal": preload("res://assets/audio/heal.wav"),
	"healing": preload("res://assets/audio/healing.wav"),
	"hurt": preload("res://assets/audio/hurt.wav"),
	"tnt_throw": preload("res://assets/audio/tnt_throw.wav"),
	"tnt_explode": preload("res://assets/audio/tnt_explode.wav"),
	"exclamation": preload("res://assets/audio/exclamation.wav"),
	"game_over": preload("res://assets/audio/game_over.wav"),
	"unable": preload("res://assets/audio/unable.wav"),
	"horn": preload("res://assets/audio/horn.wav"),
	"click": preload("res://assets/audio/ui/click.mp3"),
}

var music_tracks = {
	"main_menu": preload("res://assets/audio/bgm/main_menu.ogg"),
	"story": preload("res://assets/audio/bgm/story.ogg"),
	"lower_waves": preload("res://assets/audio/bgm/lower_waves.ogg"),
	"higher_waves": preload("res://assets/audio/bgm/higher_waves.ogg"),
	"game_over": preload("res://assets/audio/bgm/game_over.ogg"),
}

const POOL_SIZE = 8
var players: Array[AudioStreamPlayer] = []

func _ready():
	# Create the pool of players dynamically
	for i in range(POOL_SIZE):
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)

func play_sfx(sound_name: String, pitch_randomization: float = 0.0, volume_db: float = -5.0):
	if not sounds.has(sound_name):
		print("Sound not found: ", sound_name)
		return

	# 1. Find a player that isn't busy
	var chosen_player = _get_available_player()
	
	# 2. Setup and Play
	chosen_player.stream = sounds[sound_name]
	chosen_player.volume_db = volume_db
	
	if pitch_randomization > 0:
		chosen_player.pitch_scale = randf_range(1.0 - pitch_randomization, 1.0 + pitch_randomization)
	else:
		chosen_player.pitch_scale = 1.0
		
	chosen_player.play()

func _get_available_player() -> AudioStreamPlayer:
	# Loop through our pool to find a player that is not playing
	for p in players:
		if not p.playing:
			return p
	
	# If all 8 are busy, interrupt the very first one (oldest sound)
	# This keeps the game from crashing or staying silent during chaos
	return players[0]

func play_music(track_name: String, volume_db: float = -10.0, loop: bool = true):
	if not music_tracks.has(track_name):
		print("Music track not found: ", track_name)
		return
	
	var stream = music_tracks[track_name]
	
	# 1. APPLY LOOP SETTING
	# We have to check the type of file because .wav uses a different property name than .ogg/.mp3
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = loop
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	
	# 2. CHECK IF ALREADY PLAYING
	# If it's the same track and playing, we just update volume/loop state but don't restart
	if music_player.stream == stream and music_player.playing:
		music_player.volume_db = volume_db
		return
	
	# 3. PLAY NEW TRACK
	music_player.stream = stream
	music_player.volume_db = volume_db
	music_player.play()

func stop_music():
	music_player.stop()
