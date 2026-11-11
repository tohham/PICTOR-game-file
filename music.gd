extends AudioStreamPlayer

func _ready() -> void:

	if stream == null:
		push_error("BGM 沒有指定 OGG 音樂！")
		return

	volume_db = 0.0
	bus = &"Master"
	stream_paused = false

	play()

	print("BGM 播放狀態：", is_playing())
