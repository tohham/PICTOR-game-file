extends Area2D
class_name SpiritBird

# =====================================
# 靈鳥狀態
# =====================================

enum BirdState {
	FOLLOW,
	AIMING,
	FLYING
}

const IDLE_ANIMATION: StringName = &"idle"
const ATTACK_ANIMATION: StringName = &"attack"

@export_group("Movement")
@export var flight_speed: float = 650.0
@export var orbit_radius: float = 48.0
@export var min_flight_distance: float = 50.0
@export var max_flight_distance: float = 2000.0

@export_group("Attack")
@export var attack_damage: int = 1

var state: int = BirdState.FOLLOW
var follow_target: Node2D = null

var orbit_time: float = 0.0
var orbit_phase: float = 0.0

var flight_direction: Vector2 = Vector2.RIGHT
var remaining_distance: float = 0.0
var has_hit: bool = false

var animation_sprite: AnimatedSprite2D = null


func _ready() -> void:
	animation_sprite = get_node_or_null(
		"AnimatedSprite2D"
	) as AnimatedSprite2D

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	if animation_sprite == null:
		push_error(
			"SpiritBird：找不到 AnimatedSprite2D，請檢查節點名稱。"
		)
		return

	if animation_sprite.sprite_frames == null:
		push_error(
			"SpiritBird：AnimatedSprite2D 尚未設定 SpriteFrames。"
		)
		return

	var frames: SpriteFrames = animation_sprite.sprite_frames

	if frames.has_animation(IDLE_ANIMATION):
		frames.set_animation_loop(IDLE_ANIMATION, true)
	else:
		push_warning("SpiritBird：找不到 idle 動畫。")

	if frames.has_animation(ATTACK_ANIMATION):
		frames.set_animation_loop(ATTACK_ANIMATION, false)
	else:
		push_warning("SpiritBird：找不到 attack 動畫。")

	if not animation_sprite.animation_finished.is_connected(
		_on_animation_finished
	):
		animation_sprite.animation_finished.connect(
			_on_animation_finished
		)

	_play_idle()


# =====================================
# 設定環繞位置
# =====================================

func set_follow_target(
	target: Node2D,
	formation_index: int = 0,
	formation_count: int = 1
) -> void:
	follow_target = target

	var safe_count: int = maxi(formation_count, 1)
	orbit_phase = TAU * float(formation_index) / float(safe_count)
	orbit_time = orbit_phase
	state = BirdState.FOLLOW

	_play_idle()


# 只有 FOLLOW 狀態的鳥能被下一條線選中。
func can_aim() -> bool:
	return state == BirdState.FOLLOW


func is_aiming() -> bool:
	return state == BirdState.AIMING


func begin_aim() -> void:
	if state == BirdState.FOLLOW:
		state = BirdState.AIMING


func cancel_aim() -> void:
	if state == BirdState.AIMING:
		state = BirdState.FOLLOW
		_play_idle()


# =====================================
# 動畫
# =====================================

func _play_idle() -> void:
	if not is_instance_valid(animation_sprite):
		return

	if animation_sprite.sprite_frames == null:
		return

	if animation_sprite.sprite_frames.has_animation(IDLE_ANIMATION):
		animation_sprite.play(IDLE_ANIMATION)


func _play_attack() -> void:
	if not is_instance_valid(animation_sprite):
		return

	if animation_sprite.sprite_frames == null:
		return

	if animation_sprite.sprite_frames.has_animation(ATTACK_ANIMATION):
		animation_sprite.play(ATTACK_ANIMATION)


func _set_facing(direction: Vector2) -> void:
	if not is_instance_valid(animation_sprite):
		return

	# 原始靈鳥朝右，向左飛行時水平翻轉。
	if direction.x < -0.01:
		animation_sprite.flip_h = true
	elif direction.x > 0.01:
		animation_sprite.flip_h = false


func _on_animation_finished() -> void:
	# 飛行途中持續循環攻擊動畫，直到命中或飛行距離用完。
	if state == BirdState.FLYING:
		_play_attack()


# =====================================
# 發射：SpellSystem 每次只會呼叫一隻
# =====================================

func launch(direction: Vector2, distance: float) -> void:
	if state != BirdState.AIMING:
		return

	if direction.length() < 1.0:
		cancel_aim()
		return

	flight_direction = direction.normalized()

	remaining_distance = clampf(
		distance,
		min_flight_distance,
		max_flight_distance
	)

	has_hit = false
	state = BirdState.FLYING

	_set_facing(flight_direction)
	_play_attack()


# =====================================
# 更新
# =====================================

func _physics_process(delta: float) -> void:
	match state:
		BirdState.FOLLOW:
			_update_follow(delta)

		BirdState.AIMING:
			pass

		BirdState.FLYING:
			_update_flying(delta)


func _update_follow(delta: float) -> void:
	if not is_instance_valid(follow_target):
		queue_free()
		return

	orbit_time += delta * 2.0

	var angle: float = orbit_time
	var offset := Vector2(
		cos(angle) * orbit_radius,
		sin(angle) * orbit_radius * 0.45 - 24.0
	)

	var target_position: Vector2 = follow_target.global_position + offset

	global_position = global_position.lerp(
		target_position,
		minf(1.0, delta * 8.0)
	)

	_set_facing(follow_target.global_position - global_position)


func _update_flying(delta: float) -> void:
	var step: float = minf(
		flight_speed * delta,
		remaining_distance
	)

	global_position += flight_direction * step
	remaining_distance -= step

	if remaining_distance <= 0.0:
		queue_free()


# =====================================
# 碰撞與單次攻擊
# =====================================

func _on_body_entered(body: Node2D) -> void:
	_try_attack(body)


func _on_area_entered(area: Area2D) -> void:
	_try_attack(area)


func _try_attack(hit_node: Node) -> void:
	if state != BirdState.FLYING or has_hit:
		return

	var receiver: Node = _find_damage_receiver(hit_node)
	if receiver == null:
		return

	has_hit = true

	# 使用一般傷害介面，不再呼叫舊的 BREAK 法術分支。
	if receiver.has_method("take_damage"):
		receiver.call("take_damage", attack_damage)

	# 每隻鳥命中一次後消失。
	queue_free()


func _find_damage_receiver(node: Node) -> Node:
	var current: Node = node

	while current != null:
		if current == follow_target:
			return null

		if current.has_method("take_damage"):
			return current

		current = current.get_parent()

	return null
