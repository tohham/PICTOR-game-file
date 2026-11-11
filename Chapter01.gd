extends Node2D

# PICTOR — THE LAST STROKE
# 第一章流程控制：角色進場後啟動教學。

@export_group("角色")
@export var player_path: NodePath = NodePath("ikay")
@export var sprite_path: NodePath = NodePath("ikay/anmine")

@export_group("進場動畫")
@export var entry_animation: StringName = &"right"
@export var idle_animation: StringName = &"idle"

@export_range(100.0, 2000.0, 50.0)
var entry_distance: float = 700.0

@export_range(0.2, 5.0, 0.1)
var entry_duration: float = 1.5

@export_group("教學")
@export var tutorial_manager_path: NodePath = NodePath("TutorialManager")

var player: Node2D
var player_sprite: AnimatedSprite2D
var tutorial_manager: Node


func _ready() -> void:
	await get_tree().process_frame

	if not is_inside_tree():
		return

	player = get_node_or_null(player_path) as Node2D
	player_sprite = get_node_or_null(sprite_path) as AnimatedSprite2D
	tutorial_manager = get_node_or_null(tutorial_manager_path)

	if player == null:
		push_error("Chapter01：找不到主角，請檢查 Player Path。")
		return

	await _play_entry()

	if not is_inside_tree():
		return

	_start_tutorial()


func _play_entry() -> void:
	if not is_instance_valid(player):
		return

	if not is_instance_valid(player_sprite):
		return

	if player_sprite.sprite_frames == null:
		return

	if not player_sprite.sprite_frames.has_animation(entry_animation):
		return

	var old_process: bool = player.is_processing()
	var old_physics: bool = player.is_physics_processing()
	var old_input: bool = player.is_processing_input()
	var old_unhandled_input: bool = player.is_processing_unhandled_input()
	var old_unhandled_key: bool = player.is_processing_unhandled_key_input()

	# 進場期間暫停玩家控制。
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.set_process_unhandled_key_input(false)

	var destination: Vector2 = player.position

	# 從左側跑進場景。
	player.position = destination - Vector2(entry_distance, 0.0)
	player_sprite.play(entry_animation)

	var tween: Tween = create_tween()

	tween.tween_property(
		player,
		"position",
		destination,
		entry_duration
	).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(
		Tween.EASE_OUT
	)

	await tween.finished

	if not is_inside_tree():
		return

	if not is_instance_valid(player):
		return

	if is_instance_valid(player_sprite):
		if (
			player_sprite.sprite_frames != null
			and player_sprite.sprite_frames.has_animation(idle_animation)
		):
			player_sprite.play(idle_animation)

	# 恢復角色原本的處理狀態。
	player.set_process(old_process)
	player.set_physics_process(old_physics)
	player.set_process_input(old_input)
	player.set_process_unhandled_input(old_unhandled_input)
	player.set_process_unhandled_key_input(old_unhandled_key)


func _start_tutorial() -> void:
	tutorial_manager = get_node_or_null(tutorial_manager_path)

	if not is_instance_valid(tutorial_manager):
		push_error(
            "Chapter01：找不到 TutorialManager，請檢查場景樹。"
		)
		return

	if tutorial_manager.has_method("start_tutorial"):
		tutorial_manager.call("start_tutorial")
	else:
		# TutorialManager 目前會在 _ready() 自動啟動教學。
		# 沒有公開啟動方法時，不要把已正常運作的自動流程誤判成錯誤。
		if not tutorial_manager.has_method("_play_tutorial"):
			push_error(
				"Chapter01：TutorialManager 缺少 start_tutorial() 或自動教學流程。"
			)
