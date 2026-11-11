extends CharacterBody2D

# =====================================
# 移動設定
# =====================================

@export var speed: float = 200.0
@export var gravity: float = 980.0
@export var jump_force: float = -400.0


# =====================================
# 角色音效設定
# =====================================

@export_group("Character Sounds")

@export var stone_run_footstep_sfx: AudioStream
@export var jump_sfx: AudioStream
@export var landing_sfx: AudioStream
@export var drawing_sfx: AudioStream
@export var hurt_sfx: AudioStream
@export var death_sfx: AudioStream

@export var footstep_interval: float = 0.32
@export var footstep_min_speed: float = 5.0

@export var footstep_pitch_min: float = 0.96
@export var footstep_pitch_max: float = 1.04

@export var character_sfx_volume_db: float = 6

var footstep_audio: AudioStreamPlayer2D
var jump_audio: AudioStreamPlayer2D
var landing_audio: AudioStreamPlayer2D
var drawing_audio: AudioStreamPlayer2D
var hurt_audio: AudioStreamPlayer2D
var death_audio: AudioStreamPlayer2D

var footstep_timer: float = 0.0


# =====================================
# 生命值設定
# =====================================

@export var max_health: int = 5

var health: int = 5
var is_dead: bool = false

var damage_flash_timer: float = 0.0
const DAMAGE_FLASH_DURATION: float = 0.15


# =====================================
# 角色狀態
# =====================================

var facing_left: bool = false
var is_drawing_action: bool = false

@onready var sprite: AnimatedSprite2D = (
	get_node_or_null("anmine") as AnimatedSprite2D
)


# =====================================
# 初始化
# =====================================

func _ready() -> void:

	add_to_group("player")

	max_health = maxi(1, max_health)
	health = max_health

	_setup_character_audio()

	# =================================
	# 腳步音效除錯測試
	# =================================

	if stone_run_footstep_sfx != null:
		print(
			"【腳步測試】音效檔：",
			stone_run_footstep_sfx.resource_path
		)
	else:
		print(
			"【腳步測試】錯誤：沒有指派 footsteps_stone.wav"
		)

	print(
		"【腳步測試】播放器：",
		footstep_audio
	)

	if footstep_audio != null:
		print(
			"【腳步測試】音效來源：",
			footstep_audio.stream
		)

		if footstep_audio.stream != null:
			footstep_audio.play()
			print(
				"【腳步測試】啟動測試播放：",
				footstep_audio.playing
			)

	# =================================

	if sprite == null:
		push_error("找不到 AnimatedSprite2D 節點 anmine。")
		return

	if sprite.sprite_frames == null:
		push_error("anmine 沒有設定 SpriteFrames。")
		return

	if sprite.sprite_frames.has_animation("attack"):

		sprite.sprite_frames.set_animation_loop(
			"attack",
			false
		)

		if not sprite.animation_finished.is_connected(
			_on_animation_finished
		):
			sprite.animation_finished.connect(
				_on_animation_finished
			)

	else:
		push_warning(
			"找不到 attack 動畫，繪畫動作將無法播放。"
		)


# =====================================
# 建立角色音效播放器
# =====================================

func _setup_character_audio() -> void:

	footstep_audio = _create_audio_player(
		"StoneRunFootstepAudio",
		stone_run_footstep_sfx
	)

	jump_audio = _create_audio_player(
		"JumpAudio",
		jump_sfx
	)

	landing_audio = _create_audio_player(
		"LandingAudio",
		landing_sfx
	)

	drawing_audio = _create_audio_player(
		"DrawingAudio",
		drawing_sfx
	)

	hurt_audio = _create_audio_player(
		"HurtAudio",
		hurt_sfx
	)

	death_audio = _create_audio_player(
		"DeathAudio",
		death_sfx
	)

	# 腳步音效不受距離衰減影響
	if footstep_audio != null:
		footstep_audio.attenuation = 0.0


func _create_audio_player(
	player_name: String,
	audio_stream: AudioStream
) -> AudioStreamPlayer2D:

	var audio := AudioStreamPlayer2D.new()

	audio.name = player_name
	audio.stream = audio_stream
	audio.volume_db = character_sfx_volume_db
	audio.max_distance = 1200.0

	add_child(audio)

	return audio


func _play_sfx(
	audio: AudioStreamPlayer2D,
	pitch: float = 1.0
) -> void:

	if not is_instance_valid(audio):
		return

	if audio.stream == null:
		return

	audio.pitch_scale = pitch
	audio.play()


# =====================================
# 播放石地腳步聲
# =====================================

func _play_footstep() -> void:

	if not is_instance_valid(footstep_audio):
		return

	if footstep_audio.stream == null:
		return

	var pitch: float = randf_range(
		footstep_pitch_min,
		footstep_pitch_max
	)

	_play_sfx(footstep_audio, pitch)


# =====================================
# 受傷閃爍
# =====================================

func _process(delta: float) -> void:

	if damage_flash_timer > 0.0:

		damage_flash_timer = maxf(
			0.0,
			damage_flash_timer - delta
		)

		if damage_flash_timer <= 0.0:
			if is_instance_valid(sprite):
				sprite.modulate = Color.WHITE


# =====================================
# 移動與跳躍
# =====================================

func _physics_process(delta: float) -> void:

	if is_dead:
		return

	var was_on_floor: bool = is_on_floor()

	# 重力
	if not was_on_floor:
		velocity.y += gravity * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0

	# 左右移動
	var direction: float = Input.get_axis(
		"move_left",
		"move_right"
	)

	velocity.x = direction * speed

	# 面向
	if direction < 0.0:
		facing_left = true
	elif direction > 0.0:
		facing_left = false

	# 跳躍
	if (
		Input.is_action_just_pressed("jump")
		and was_on_floor
	):
		velocity.y = jump_force
		_play_sfx(jump_audio)

	# 移動
	move_and_slide()

	# 判斷落地
	var just_landed: bool = (
		not was_on_floor
		and is_on_floor()
	)

	# 落地音效
	if just_landed:
		_play_sfx(landing_audio)

	# 腳步聲
	_update_footsteps(delta, just_landed)

	# 更新動畫
	if not is_drawing_action:
		update_animation(direction)


# =====================================
# 石地跑步腳步聲
# =====================================

func _update_footsteps(
	delta: float,
	just_landed: bool = false
) -> void:

	if not is_instance_valid(footstep_audio):
		return

	if footstep_audio.stream == null:
		return

	# 落地時不立即播放腳步聲
	if just_landed:
		footstep_timer = maxf(
			0.12,
			footstep_interval
		)
		return

	# 判斷是否真的在地面移動
	var is_running: bool = (
		is_on_floor()
		and absf(velocity.x) > footstep_min_speed
	)

	# 停止移動或跳躍
	if not is_running:
		footstep_timer = 0.0
		return

	# 計時
	footstep_timer -= delta

	# 時間到，播放腳步聲
	if footstep_timer <= 0.0:

		print(
			"【腳步測試】觸發播放！",
			" 地面：",
			is_on_floor(),
			" 水平速度：",
			velocity.x
		)

		_play_footstep()

		footstep_timer = maxf(
			0.12,
			footstep_interval
		)


# =====================================
# 主角繪畫動作
# 由 SpellSystem 呼叫
# =====================================

func play_drawing_animation() -> void:

	if is_dead or is_drawing_action:
		return

	if not is_instance_valid(sprite):
		return

	if sprite.sprite_frames == null:
		return

	if not sprite.sprite_frames.has_animation("attack"):
		push_warning("找不到 attack 動畫。")
		return

	is_drawing_action = true

	sprite.flip_h = facing_left
	sprite.play("attack")

	_play_sfx(drawing_audio)


func _on_animation_finished() -> void:

	if not is_instance_valid(sprite):
		return

	if sprite.animation == "attack":
		is_drawing_action = false


# =====================================
# 一般動畫處理
# =====================================

func update_animation(direction: float) -> void:

	if not is_instance_valid(sprite):
		return

	if sprite.sprite_frames == null:
		return

	if not is_on_floor():
		play_animation_if_exists("jump")
		return

	if absf(direction) > 0.01:

		if (
			facing_left
			and sprite.sprite_frames.has_animation("left")
		):
			sprite.flip_h = false
			play_animation_if_exists("left")

		else:
			sprite.flip_h = facing_left
			play_animation_if_exists("right")

		return

	if (
		facing_left
		and sprite.sprite_frames.has_animation("idle_left")
	):
		sprite.flip_h = false
		play_animation_if_exists("idle_left")

	else:
		sprite.flip_h = facing_left
		play_animation_if_exists("idle")


func play_animation_if_exists(
	animation_name: String
) -> void:

	if not is_instance_valid(sprite):
		return

	if sprite.sprite_frames == null:
		return

	if not sprite.sprite_frames.has_animation(animation_name):
		return

	if (
		sprite.animation != animation_name
		or not sprite.is_playing()
	):
		sprite.play(animation_name)


# =====================================
# 主角受傷
# =====================================

func take_damage(amount: int = 1) -> void:

	if is_dead or amount <= 0:
		return

	health = maxi(0, health - amount)

	print(
		"玩家生命值：%d / %d"
		% [health, max_health]
	)

	if health <= 0:
		die()
		return

	_play_sfx(hurt_audio)

	if is_instance_valid(sprite):

		sprite.modulate = Color(
			1.0,
			0.35,
			0.35,
			1.0
		)

		damage_flash_timer = DAMAGE_FLASH_DURATION


# =====================================
# 玩家死亡
# =====================================

func die() -> void:

	if is_dead:
		return

	is_dead = true
	is_drawing_action = false

	velocity = Vector2.ZERO
	footstep_timer = 0.0

	if is_instance_valid(footstep_audio):
		footstep_audio.stop()

	_play_sfx(death_audio)

	print("玩家倒下")

	set_physics_process(false)
	set_process_input(false)

	if is_instance_valid(sprite):

		sprite.modulate = Color.WHITE

		if (
			sprite.sprite_frames != null
			and sprite.sprite_frames.has_animation("idle")
		):
			sprite.play("idle")
