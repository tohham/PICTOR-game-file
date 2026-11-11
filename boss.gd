extends CharacterBody2D


# ==================================================
# 內建字符子彈
# ==================================================

class BossBullet extends Node2D:
	var player_target: Node2D = null
	var direction: Vector2 = Vector2.LEFT
	var speed: float = 520.0
	var damage: int = 1
	var lifetime: float = 8.0
	var bullet_radius: float = 8.0
	var player_hit_radius: float = 14.0
	var glyph: String = "Σ"
	var initialized: bool = false

	func _ready() -> void:
		add_to_group("projectile")
		add_to_group("boss_attack")
		queue_redraw()

	func setup(
		target: Node2D,
		shot_direction: Vector2,
		projectile_speed: float,
		projectile_damage: int,
		glyph_text: String = "Σ"
	) -> void:
		player_target = target
		direction = shot_direction.normalized()

		if direction.length_squared() < 0.001:
			direction = Vector2.LEFT

		speed = maxf(0.0, projectile_speed)
		damage = maxi(0, projectile_damage)
		glyph = glyph_text
		initialized = true
		queue_redraw()

	func _physics_process(delta: float) -> void:
		if not initialized:
			return

		if not is_instance_valid(player_target):
			queue_free()
			return

		lifetime -= delta

		if lifetime <= 0.0:
			queue_free()
			return

		var start_global: Vector2 = global_position
		var end_global: Vector2 = (
			start_global + direction * speed * delta
		)

		# 先檢查大象，避免子彈穿透。
		var elephants: Array[Node] = (
			get_tree().get_nodes_in_group("defense_elephant")
		)

		for elephant_node: Node in elephants:
			if not is_instance_valid(elephant_node):
				continue

			if not elephant_node.has_method("blocks_projectile"):
				continue

			var blocked: bool = bool(
				elephant_node.call(
					"blocks_projectile",
					start_global,
					end_global
				)
			)

			if blocked:
				print("字符子彈被大象擋下！")
				queue_free()
				return

		# 使用本幀的整條移動路徑判定是否命中玩家。
		var closest_point: Vector2 = _closest_point_on_segment(
			player_target.global_position,
			start_global,
			end_global
		)

		if closest_point.distance_to(
			player_target.global_position
		) <= bullet_radius + player_hit_radius:
			if player_target.has_method("take_damage"):
				player_target.call("take_damage", damage)

			print("字符子彈命中主角！")
			queue_free()
			return

		global_position = end_global

	func _closest_point_on_segment(
		point: Vector2,
		segment_start: Vector2,
		segment_end: Vector2
	) -> Vector2:
		var segment: Vector2 = segment_end - segment_start
		var length_squared: float = segment.length_squared()

		if length_squared <= 0.001:
			return segment_start

		var t: float = clampf(
			(point - segment_start).dot(segment) / length_squared,
			0.0,
			1.0
		)

		return segment_start + segment * t

	func _draw() -> void:
		draw_circle(
			Vector2.ZERO,
			bullet_radius + 4.0,
			Color(0.2, 0.75, 1.0, 0.18)
		)

		draw_circle(
			Vector2.ZERO,
			bullet_radius,
			Color(0.15, 0.55, 0.95, 0.8)
		)

		var font: Font = ThemeDB.fallback_font

		if font != null:
			draw_string(
				font,
				Vector2(-13.0, 7.0),
				glyph,
				HORIZONTAL_ALIGNMENT_CENTER,
				30.0,
				18,
				Color(0.75, 1.0, 1.0)
			)


# ==================================================
# Boss 狀態
# ==================================================

enum BossAction {
	WAITING,
	MOVE_TO_HOVER,
	SHOOTING,
	ASCENDING,
	DIVING,
	RECOVERING
}


# ==================================================
# Boss 基本設定
# ==================================================

@export var max_health: int = 10


@export_group("移動")
@export var move_speed: float = 260.0
@export var hover_height: float = 220.0
@export var move_arrival_distance: float = 14.0


@export_group("俯衝")
@export var dive_ascend_height: float = 280.0
@export var ascend_speed: float = 430.0
@export var dive_speed: float = 850.0
@export var dive_hit_radius: float = 24.0
@export var player_contact_radius: float = 14.0
@export var dive_damage: int = 2


@export_group("字符彈幕")
@export var attack_interval: float = 0.85
@export var bullet_speed: float = 520.0
@export var bullet_damage: int = 1

@export_range(1, 12, 1)
var bullet_count: int = 5

@export_range(0.0, 120.0, 1.0)
var bullet_spread_degrees: float = 36.0

@export var projectile_spawn_offset: Vector2 = Vector2(0.0, -20.0)
@export var projectile_delay: float = 0.18
@export var shooting_duration: float = 0.65
@export var recovery_duration: float = 0.45

@export_range(1, 10, 1)
var volleys_before_dive: int = 4


@export_group("朝向")
@export var art_faces_right_when_unflipped: bool = true


@export_group("法術控制")
@export var stun_duration: float = 2.0
@export var counter_stun_duration: float = 1.2


# ==================================================
# 狀態變數
# ==================================================

const BULLET_GLYPHS: Array[String] = [
	"Σ", "λ", "Φ", "0", "1", "Δ", "Ω", "∞"
]

var current_health: int = 10
var player: Node2D = null
var health_bar: Range = null
var boss_anim: AnimatedSprite2D = null

var action_state: int = BossAction.WAITING

var action_timer: float = 0.85
var shooting_timer: float = 0.0
var projectile_delay_timer: float = 0.0

var volleys_completed: int = 0

var bullet_pending: bool = false
var volley_fired_this_shot: bool = false

# 升空目標只計算一次，不能每幀重新往上加高度。
var ascend_target_position: Vector2 = Vector2.ZERO

var dive_target_position: Vector2 = Vector2.ZERO

var stun_timer: float = 0.0
var hacking_timer: float = 0.0

var is_dead: bool = false


# ==================================================
# 初始化
# ==================================================

func _ready() -> void:
	add_to_group("boss")

	is_dead = false
	current_health = maxi(1, max_health)
	action_timer = maxf(0.1, attack_interval)

	health_bar = get_node_or_null("HealthBar") as Range
	_update_health_bar()

	boss_anim = get_node_or_null("anmin2d") as AnimatedSprite2D

	if boss_anim == null:
		boss_anim = _find_animated_sprite(self)

	if boss_anim != null and boss_anim.sprite_frames != null:
		var frames: SpriteFrames = boss_anim.sprite_frames

		if frames.has_animation("boss_idie"):
			frames.set_animation_loop("boss_idie", true)

		if frames.has_animation("boss_atk"):
			frames.set_animation_loop("boss_atk", false)

		if not boss_anim.animation_finished.is_connected(
			_on_boss_animation_finished
		):
			boss_anim.animation_finished.connect(
				_on_boss_animation_finished
			)

		_play_idle_animation(true)
	else:
		push_warning(
			"Boss 找不到有效的 AnimatedSprite2D 或 SpriteFrames。"
		)

	_find_player()
	_update_facing()

	print(
		"蒙娜麗莎 Boss 初始化完成，HP = ",
		current_health,
		" / ",
		max_health
	)


func _find_animated_sprite(node: Node) -> AnimatedSprite2D:
	for child in node.get_children():
		if child is AnimatedSprite2D:
			return child as AnimatedSprite2D

		var found: AnimatedSprite2D = _find_animated_sprite(child)

		if found != null:
			return found

	return null


# ==================================================
# 動畫
# ==================================================

func _play_idle_animation(force_restart: bool = false) -> void:
	if not is_instance_valid(boss_anim):
		return

	if boss_anim.sprite_frames == null:
		return

	if not boss_anim.sprite_frames.has_animation("boss_idie"):
		push_warning("SpriteFrames 找不到 boss_idie。")
		return

	if (
		force_restart
		or boss_anim.animation != "boss_idie"
		or not boss_anim.is_playing()
	):
		boss_anim.play("boss_idie")


func _play_attack_animation() -> void:
	if not is_instance_valid(boss_anim):
		return

	if boss_anim.sprite_frames == null:
		return

	if not boss_anim.sprite_frames.has_animation("boss_atk"):
		push_warning("SpriteFrames 找不到 boss_atk。")
		return

	if (
		boss_anim.animation != "boss_atk"
		or not boss_anim.is_playing()
	):
		boss_anim.play("boss_atk")


func _on_boss_animation_finished() -> void:
	if is_dead:
		return

	if not is_instance_valid(boss_anim):
		return

	if boss_anim.animation == "boss_atk":
		# 攻擊動畫播完後立刻回待機。
		_play_idle_animation(true)


# ==================================================
# 面向玩家
# ==================================================

func _update_facing() -> void:
	if not is_instance_valid(player):
		return

	if not is_instance_valid(boss_anim):
		return

	var player_is_right: bool = (
		player.global_position.x > global_position.x
	)

	boss_anim.flip_h = (
		art_faces_right_when_unflipped != player_is_right
	)


# ==================================================
# 每幀更新
# ==================================================

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_find_player()
	_update_facing()

	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		return

	if hacking_timer > 0.0:
		hacking_timer = maxf(0.0, hacking_timer - delta)

	if not is_instance_valid(player):
		return

	match action_state:
		BossAction.WAITING:
			_process_waiting(delta)

		BossAction.MOVE_TO_HOVER:
			_process_move_to_hover(delta)

		BossAction.SHOOTING:
			_process_shooting(delta)

		BossAction.ASCENDING:
			_process_ascending(delta)

		BossAction.DIVING:
			_process_diving(delta)

		BossAction.RECOVERING:
			_process_recovering(delta)


# ==================================================
# 找到玩家
# ==================================================

func _find_player() -> void:
	if is_instance_valid(player):
		return

	player = null

	for node: Node in get_tree().get_nodes_in_group("player"):
		if node is Node2D and is_instance_valid(node):
			player = node as Node2D
			return


# ==================================================
# 等待攻擊
# ==================================================

func _process_waiting(delta: float) -> void:
	# 等待時確保待機動畫在播放。
	_play_idle_animation()

	action_timer -= delta

	if action_timer > 0.0:
		return

	if volleys_completed < maxi(1, volleys_before_dive):
		action_state = BossAction.MOVE_TO_HOVER
	else:
		_begin_dive_attack()


# ==================================================
# 飄到主角上方
# ==================================================

func _process_move_to_hover(delta: float) -> void:
	if not is_instance_valid(player):
		_begin_recovery()
		return

	_play_idle_animation()

	var hover_target: Vector2 = _clamp_to_visible_world(
		player.global_position + Vector2(0.0, -hover_height)
	)

	_move_toward_point(hover_target, move_speed, delta)

	if global_position.distance_to(hover_target) <= move_arrival_distance:
		_begin_shooting()


# ==================================================
# 開始發射
# ==================================================

func _begin_shooting() -> void:
	action_state = BossAction.SHOOTING

	bullet_pending = true
	volley_fired_this_shot = false

	projectile_delay_timer = maxf(0.0, projectile_delay)
	shooting_timer = maxf(shooting_duration, projectile_delay)

	_play_attack_animation()


func _process_shooting(delta: float) -> void:
	if bullet_pending:
		projectile_delay_timer -= delta

		if projectile_delay_timer <= 0.0:
			bullet_pending = false

			var fired: bool = _spawn_bullet_volley()

			if fired and not volley_fired_this_shot:
				volley_fired_this_shot = true
				volleys_completed += 1

				print(
					"彈幕輪數：",
					volleys_completed,
					" / ",
					volleys_before_dive
				)

	shooting_timer -= delta

	if shooting_timer <= 0.0 and not bullet_pending:
		_begin_recovery()


# ==================================================
# 發射扇形字符彈幕
# 回傳是否成功發射
# ==================================================

func _spawn_bullet_volley() -> bool:
	if is_dead or not is_instance_valid(player):
		return false

	var scene: Node = get_tree().current_scene

	if scene == null:
		push_error("找不到目前主場景，無法發射字符子彈。")
		return false

	var spawn_offset: Vector2 = projectile_spawn_offset

	if is_instance_valid(boss_anim) and boss_anim.flip_h:
		spawn_offset.x = -spawn_offset.x

	var spawn_position: Vector2 = global_position + spawn_offset

	var aim_direction: Vector2 = (
		player.global_position - spawn_position
	).normalized()

	var count: int = maxi(1, bullet_count)
	var half_spread: float = bullet_spread_degrees * 0.5

	for i in range(count):
		var angle_degrees: float = 0.0

		if count > 1:
			var ratio: float = float(i) / float(count - 1)

			angle_degrees = lerpf(
				-half_spread,
				half_spread,
				ratio
			)

		var shot_direction: Vector2 = aim_direction.rotated(
			deg_to_rad(angle_degrees)
		)

		var projectile := BossBullet.new()

		scene.add_child(projectile)
		projectile.global_position = spawn_position

		projectile.setup(
			player,
			shot_direction,
			bullet_speed,
			bullet_damage,
			BULLET_GLYPHS[i % BULLET_GLYPHS.size()]
		)

	print("蒙娜麗莎發射 ", count, " 顆字符子彈！")

	return true


# ==================================================
# 開始升空俯衝
# ==================================================

func _begin_dive_attack() -> void:
	if not is_instance_valid(player):
		_begin_recovery(true)
		return

	# 畫面範圍。
	var screen_rect: Rect2 = _get_visible_world_rect()
	var margin: Vector2 = _get_boss_screen_margin()

	var min_x: float = screen_rect.position.x + margin.x
	var max_x: float = screen_rect.end.x - margin.x
	var min_y: float = screen_rect.position.y + margin.y
	var max_y: float = screen_rect.end.y - margin.y

	# X 對準玩家，但不超出畫面。
	var target_x: float = clampf(
		player.global_position.x,
		min_x,
		max_x
	)

	# 升空位置只計算一次，並限制在畫面內。
	var desired_y: float = global_position.y - dive_ascend_height

	var target_y: float = clampf(
		desired_y,
		min_y,
		max_y
	)

	ascend_target_position = Vector2(target_x, target_y)

	action_state = BossAction.ASCENDING
	_play_idle_animation()


# ==================================================
# 升空：朝固定目標移動
# ==================================================

func _process_ascending(delta: float) -> void:
	if not is_instance_valid(player):
		_begin_recovery(true)
		return

	_move_toward_point(
		ascend_target_position,
		ascend_speed,
		delta
	)

	if global_position.distance_to(
		ascend_target_position
	) <= move_arrival_distance:
		# 鎖定玩家目前位置，然後開始俯衝。
		dive_target_position = _clamp_to_visible_world(
			player.global_position
		)

		action_state = BossAction.DIVING
		_play_attack_animation()


# ==================================================
# 俯衝：只有真正接觸玩家才扣血
# ==================================================

func _process_diving(delta: float) -> void:
	if not is_instance_valid(player):
		_begin_recovery(true)
		return

	var start_global: Vector2 = global_position

	var end_global: Vector2 = start_global.move_toward(
		dive_target_position,
		dive_speed * delta
	)

	# 檢查 Boss 本幀移動路徑是否真的經過玩家。
	var closest_point: Vector2 = _closest_point_on_segment(
		player.global_position,
		start_global,
		end_global
	)

	var distance: float = closest_point.distance_to(
		player.global_position
	)

	global_position = end_global

	if distance <= dive_hit_radius + player_contact_radius:
		damage_player(dive_damage)

		print("蒙娜麗莎俯衝命中主角！")
		_begin_recovery(true)
		return

	# 沒有碰到玩家就結束，不扣血。
	if global_position.distance_to(dive_target_position) <= 2.0:
		_begin_recovery(true)


# ==================================================
# 取得可視世界矩形
# ==================================================

func _get_visible_world_rect() -> Rect2:
	var viewport := get_viewport()
	var screen_rect: Rect2 = viewport.get_visible_rect()

	var inverse_transform: Transform2D = (
		viewport.get_canvas_transform().affine_inverse()
	)

	var corners: Array[Vector2] = [
		inverse_transform * screen_rect.position,
		inverse_transform * Vector2(
			screen_rect.end.x,
			screen_rect.position.y
		),
		inverse_transform * screen_rect.end,
		inverse_transform * Vector2(
			screen_rect.position.x,
			screen_rect.end.y
		)
	]

	var min_x: float = corners[0].x
	var max_x: float = corners[0].x
	var min_y: float = corners[0].y
	var max_y: float = corners[0].y

	for point: Vector2 in corners:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)

	return Rect2(
		Vector2(min_x, min_y),
		Vector2(max_x - min_x, max_y - min_y)
	)


func _get_boss_screen_margin() -> Vector2:
	var margin := Vector2(70.0, 70.0)

	if (
		is_instance_valid(boss_anim)
		and boss_anim.sprite_frames != null
		and boss_anim.sprite_frames.has_animation(boss_anim.animation)
	):
		var texture: Texture2D = (
			boss_anim.sprite_frames.get_frame_texture(
				boss_anim.animation,
				boss_anim.frame
			)
		)

		if texture != null:
			margin.x = maxf(
				margin.x,
				texture.get_width()
				* absf(boss_anim.global_scale.x) * 0.5 + 12.0
			)

			margin.y = maxf(
				margin.y,
				texture.get_height()
				* absf(boss_anim.global_scale.y) * 0.5 + 12.0
			)

	var screen_rect: Rect2 = _get_visible_world_rect()

	margin.x = minf(margin.x, screen_rect.size.x * 0.4)
	margin.y = minf(margin.y, screen_rect.size.y * 0.4)

	return margin


func _clamp_to_visible_world(target_position: Vector2) -> Vector2:
	var screen_rect: Rect2 = _get_visible_world_rect()
	var margin: Vector2 = _get_boss_screen_margin()

	return Vector2(
		clampf(
			target_position.x,
			screen_rect.position.x + margin.x,
			screen_rect.end.x - margin.x
		),
		clampf(
			target_position.y,
			screen_rect.position.y + margin.y,
			screen_rect.end.y - margin.y
		)
	)


# ==================================================
# 移動工具
# ==================================================

func _move_toward_point(
	target_position: Vector2,
	speed: float,
	delta: float
) -> void:
	global_position = global_position.move_toward(
		target_position,
		speed * delta
	)


func _closest_point_on_segment(
	point: Vector2,
	segment_start: Vector2,
	segment_end: Vector2
) -> Vector2:
	var segment: Vector2 = segment_end - segment_start
	var length_squared: float = segment.length_squared()

	if length_squared <= 0.001:
		return segment_start

	var t: float = clampf(
		(point - segment_start).dot(segment) / length_squared,
		0.0,
		1.0
	)

	return segment_start + segment * t


# ==================================================
# 攻擊結束，回到待機
# ==================================================

func _begin_recovery(reset_volley_cycle: bool = false) -> void:
	bullet_pending = false

	action_state = BossAction.RECOVERING
	action_timer = maxf(0.1, recovery_duration)

	if reset_volley_cycle:
		volleys_completed = 0
		print("俯衝結束，開始下一輪彈幕。")

	# 強制切換回待機，修正 Idle 不出現的問題。
	_play_idle_animation(true)


func _process_recovering(delta: float) -> void:
	# 只在需要時切換，不會每幀重播動畫。
	_play_idle_animation()

	action_timer -= delta

	if action_timer <= 0.0:
		action_state = BossAction.WAITING
		action_timer = maxf(0.1, attack_interval)
		_play_idle_animation()


# ==================================================
# 玩家受傷
# ==================================================

func damage_player(amount: int) -> void:
	if not is_instance_valid(player):
		return

	if amount <= 0:
		return

	if player.has_method("take_damage"):
		player.call("take_damage", amount)


# ==================================================
# 舊介面保留，避免其他程式呼叫時報錯
# ==================================================

func _start_sword_windup() -> void:
	pass


func _perform_sword_attack() -> void:
	pass


func _start_hack() -> void:
	hacking_timer = maxf(0.0, 2.4)


func is_currently_hacking() -> bool:
	return hacking_timer > 0.0


# ==================================================
# Boss 受到傷害
# ==================================================

func take_damage(amount: int) -> void:
	if is_dead or amount <= 0:
		return

	current_health = maxi(0, current_health - amount)

	_update_health_bar()

	print(
		"Boss HP：",
		current_health,
		" / ",
		max_health
	)

	if current_health <= 0:
		_die()


func _update_health_bar() -> void:
	if not is_instance_valid(health_bar):
		return

	health_bar.min_value = 0.0
	health_bar.max_value = float(maxi(1, max_health))
	health_bar.value = float(current_health)
	health_bar.show()


# ==================================================
# 法術介面
# ==================================================

func apply_spell(spell_name: String) -> void:
	if is_dead:
		return

	match spell_name.to_upper():
		"BREAK":
			take_damage(1)

		"OVERLOAD":
			take_damage(2)

		"STUN":
			_apply_stun(stun_duration)

		"COUNTER":
			take_damage(2)
			_apply_stun(counter_stun_duration)

		_:
			push_warning("未知法術：" + spell_name)


func _apply_stun(duration: float) -> void:
	stun_timer = maxf(
		stun_timer,
		maxf(0.0, duration)
	)


# ==================================================
# Boss 死亡
# ==================================================

func _die() -> void:
	if is_dead:
		return

	is_dead = true
	bullet_pending = false
	current_health = 0

	_update_health_bar()

	print("蒙娜麗莎 Boss 被擊敗。")
	queue_free()
