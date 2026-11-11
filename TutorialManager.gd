extends CanvasLayer

# PICTOR — THE LAST STROKE
# 教學內容：
# A / D 移動、跳躍、攻擊、繪素、
# 畫直線召喚大象、畫圈召喚靈鳥、畫直線指揮靈鳥。
#
# 教學換頁只使用 Enter。
# 移動操作只有 A、D，不使用類比搖桿。
# 保留原本的畫圈與直線筆劃示意圖。

const MANAGER_GROUP: StringName = &"pictor_single_tutorial_manager"

@export_group("角色進場")
@export var sprite_path: NodePath = NodePath("../ikay/anmine")
@export var entry_animation: StringName = &"right"
@export var idle_animation: StringName = &"idle"
@export var wait_for_entry: bool = true
@export_range(1.0, 10.0, 0.5) var entry_wait_limit: float = 5.0

@export_group("Demo 畫筆系統")
@export var spell_system_path: NodePath = NodePath("../SpellSystem")
@export var auto_find_spell_system := true

var player_sprite: AnimatedSprite2D
var spell_system: Node

var overlay: Control
var tutorial_panel: PanelContainer
var title_label: Label
var description_label: Label
var key_hint_label: Label
var stroke_diagram: StrokeDiagram

var tutorial_running := false
var continue_requested := false


# =========================================================
# 筆劃示意圖：保留原本的畫圈、直線兩張圖
# =========================================================

class StrokeDiagram extends Control:
	const MODE_CIRCLE := 0
	const MODE_LINE := 1

	var mode := MODE_CIRCLE

	func _ready() -> void:
		custom_minimum_size = Vector2(620, 145)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_mode(value: int) -> void:
		mode = value
		queue_redraw()

	func _draw() -> void:
		var gap := 14.0
		var card_width: float = maxf(120.0, (size.x - gap) * 0.5)
		var card_height: float = size.y - 8.0

		var circle_card := Rect2(
			Vector2(0, 4),
			Vector2(card_width, card_height)
		)

		var line_card := Rect2(
			Vector2(card_width + gap, 4),
			Vector2(card_width, card_height)
		)

		_draw_card(
			circle_card,
			"召喚靈鳥：畫圈",
			mode == MODE_CIRCLE
		)

		_draw_card(
			line_card,
			"指揮靈鳥：畫直線",
			mode == MODE_LINE
		)

		_draw_circle_stroke(circle_card)
		_draw_line_stroke(line_card)

	func _draw_card(
		rect: Rect2,
		caption: String,
		active: bool
	) -> void:
		var fill := Color(0.035, 0.075, 0.13, 0.96)
		var border := Color(0.22, 0.42, 0.62, 0.72)
		var text_color := Color(0.62, 0.72, 0.83)

		if active:
			fill = Color(0.045, 0.12, 0.20, 0.98)
			border = Color(0.25, 0.82, 1.0, 1.0)
			text_color = Color(0.75, 0.94, 1.0)

		draw_rect(rect, fill, true)
		draw_rect(rect, border, false, 2.0, true)

		draw_string(
			ThemeDB.fallback_font,
			rect.position + Vector2(12, 23),
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 24,
			15,
			text_color
		)

	func _draw_circle_stroke(rect: Rect2) -> void:
		var center := Vector2(
			rect.position.x + rect.size.x * 0.5,
			rect.position.y + 82
		)

		var radius := 26.0
		var ink := Color(0.22, 0.86, 1.0, 1.0)
		var start_color := Color(0.46, 1.0, 0.76, 1.0)

		if mode != MODE_CIRCLE:
			ink = Color(0.30, 0.48, 0.60, 0.55)
			start_color = Color(0.40, 0.55, 0.62, 0.55)

		draw_arc(
			center,
			radius,
			0.0,
			TAU,
			64,
			ink,
			4.5,
			true
		)

		# 起點
		draw_circle(
			center + Vector2(0, -radius),
			5.0,
			start_color
		)

		# 繞圈方向箭頭
		var angle := -PI / 4.0
		var tip := center + Vector2(
			cos(angle),
			sin(angle)
		) * radius

		var tangent := Vector2(
			-sin(angle),
			cos(angle)
		).normalized()

		_draw_arrowhead(tip, tangent, ink)

	func _draw_line_stroke(rect: Rect2) -> void:
		var start := Vector2(
			rect.position.x + 38,
			rect.position.y + 82
		)

		var finish := Vector2(
			rect.position.x + rect.size.x - 38,
			rect.position.y + 82
		)

		var ink := Color(0.22, 0.86, 1.0, 1.0)
		var start_color := Color(0.46, 1.0, 0.76, 1.0)

		if mode != MODE_LINE:
			ink = Color(0.30, 0.48, 0.60, 0.55)
			start_color = Color(0.40, 0.55, 0.62, 0.55)

		draw_line(start, finish, ink, 4.5, true)
		draw_circle(start, 5.0, start_color)

		_draw_arrowhead(
			finish,
			(finish - start).normalized(),
			ink
		)

	func _draw_arrowhead(
		tip: Vector2,
		direction: Vector2,
		color: Color
	) -> void:
		var dir := direction.normalized()
		var side := Vector2(-dir.y, dir.x)

		var triangle := PackedVector2Array([
			tip,
			tip - dir * 13.0 + side * 7.0,
			tip - dir * 13.0 - side * 7.0
		])

		draw_colored_polygon(triangle, color)


# =========================================================
# 初始化
# =========================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50

	if not _claim_single_manager():
		queue_free()
		return

	player_sprite = get_node_or_null(
		sprite_path
	) as AnimatedSprite2D

	_find_spell_system()

	var scene_root := get_tree().current_scene

	if is_instance_valid(scene_root):
		_remove_legacy_tutorials(scene_root)

	await get_tree().process_frame

	if not is_inside_tree():
		return

	scene_root = get_tree().current_scene

	if is_instance_valid(scene_root):
		_remove_legacy_tutorials(scene_root)

	await get_tree().process_frame

	if not is_inside_tree():
		return

	scene_root = get_tree().current_scene

	if is_instance_valid(scene_root):
		_remove_legacy_tutorials(scene_root)

	await _wait_for_entry()

	if not is_inside_tree():
		return

	_build_ui()

	tutorial_running = true
	await _play_tutorial()


func _claim_single_manager() -> bool:
	for node in get_tree().get_nodes_in_group(MANAGER_GROUP):
		if node != self and is_instance_valid(node):
			return false

	add_to_group(MANAGER_GROUP)
	return true


func _find_spell_system() -> void:
	spell_system = get_node_or_null(spell_system_path)

	if is_instance_valid(spell_system):
		return

	if not auto_find_spell_system:
		return

	var scene_root := get_tree().current_scene

	if not is_instance_valid(scene_root):
		return

	spell_system = _find_node_by_name(
		scene_root,
		"SpellSystem"
	)


func _find_node_by_name(
	parent_node: Node,
	target_name: String
) -> Node:
	if String(parent_node.name).to_lower() == target_name.to_lower():
		return parent_node

	for child in parent_node.get_children():
		var found := _find_node_by_name(child, target_name)

		if is_instance_valid(found):
			return found

	return null


# =========================================================
# 清除舊教學介面
# =========================================================

func _remove_legacy_tutorials(parent_node: Node) -> void:
	for child in parent_node.get_children():
		if child == self:
			continue

		if child == overlay:
			continue

		if _is_legacy_tutorial(child):
			child.queue_free()
		else:
			_remove_legacy_tutorials(child)


func _is_legacy_tutorial(node: Node) -> bool:
	var node_name := String(node.name).to_lower()

	var name_markers: Array[String] = [
		"tutorial",
		"teaching",
		"controlguide",
		"教學介面",
		"教學面板",
		"操作教學",
		"操作提示"
	]

	for marker in name_markers:
		if node_name.contains(marker):
			return true

	if node is Control and _subtree_has_old_tutorial_text(node):
		return true

	return false


func _subtree_has_old_tutorial_text(node: Node) -> bool:
	if node is Label:
		var text_value := (node as Label).text.to_lower()

		var text_markers: Array[String] = [
			"wasd",
			"類比搖桿",
			"方向搖桿",
			"空白鍵繼續",
			"操作教學",
			"教學完成",
			"操作提示"
		]

		for marker in text_markers:
			if text_value.contains(marker):
				return true

	for child in node.get_children():
		if _subtree_has_old_tutorial_text(child):
			return true

	return false


# =========================================================
# 建立教學 UI
# =========================================================

func _build_ui() -> void:
	overlay = Control.new()
	overlay.name = "PictorTutorialOverlay"
	overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var shade := ColorRect.new()
	shade.name = "PictorTutorialShade"
	shade.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	shade.color = Color(0.0, 0.015, 0.04, 0.24)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)

	tutorial_panel = PanelContainer.new()
	tutorial_panel.name = "PictorTutorialPanel"

	tutorial_panel.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_WIDE
	)

	tutorial_panel.offset_left = 30
	tutorial_panel.offset_right = -30
	tutorial_panel.offset_top = 24
	tutorial_panel.offset_bottom = 290
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	overlay.add_child(tutorial_panel)

	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(0.025, 0.04, 0.075, 0.96)
	skin.border_color = Color(0.28, 0.57, 0.82, 0.9)
	skin.set_border_width_all(2)
	skin.set_corner_radius_all(10)
	skin.content_margin_left = 22
	skin.content_margin_right = 22
	skin.content_margin_top = 16
	skin.content_margin_bottom = 14

	tutorial_panel.add_theme_stylebox_override(
		"panel",
		skin
	)

	var content := VBoxContainer.new()
	content.name = "PictorTutorialContent"
	content.add_theme_constant_override("separation", 9)
	tutorial_panel.add_child(content)

	title_label = Label.new()
	title_label.name = "PictorTutorialTitle"
	title_label.add_theme_font_size_override("font_size", 25)
	title_label.add_theme_color_override(
		"font_color",
		Color(0.80, 0.91, 1.0)
	)
	content.add_child(title_label)

	description_label = Label.new()
	description_label.name = "PictorTutorialDescription"
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_font_size_override("font_size", 18)
	description_label.add_theme_color_override(
		"font_color",
		Color(0.91, 0.93, 0.97)
	)
	content.add_child(description_label)

	# 保留原本的兩張筆劃示意圖。
	stroke_diagram = StrokeDiagram.new()
	stroke_diagram.name = "PictorStrokeDiagram"
	stroke_diagram.visible = false
	content.add_child(stroke_diagram)

	key_hint_label = Label.new()
	key_hint_label.name = "PictorTutorialHint"
	key_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_hint_label.add_theme_font_size_override("font_size", 14)
	key_hint_label.add_theme_color_override(
		"font_color",
		Color(0.52, 0.76, 1.0)
	)
	content.add_child(key_hint_label)


# =========================================================
# 等待角色進場動畫
# =========================================================

func _wait_for_entry() -> void:
	if not wait_for_entry:
		return

	if not is_instance_valid(player_sprite):
		return

	if player_sprite.sprite_frames == null:
		return

	if not player_sprite.sprite_frames.has_animation(entry_animation):
		return

	if player_sprite.animation == idle_animation:
		await get_tree().create_timer(0.25).timeout
		return

	var saw_entry := player_sprite.animation == entry_animation
	var started := Time.get_ticks_msec()

	while Time.get_ticks_msec() - started < int(entry_wait_limit * 1000.0):
		if not is_instance_valid(player_sprite):
			return

		if player_sprite.animation == entry_animation:
			saw_entry = true

		if saw_entry and player_sprite.animation == idle_animation:
			await get_tree().create_timer(0.25).timeout
			return

		await get_tree().process_frame


# =========================================================
# 教學操作提示
# =========================================================

func _input(event: InputEvent) -> void:
	if not tutorial_running:
		return

	if not (event is InputEventKey):
		return

	var key := event as InputEventKey

	if not key.pressed or key.echo:
		return

	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		continue_requested = true
		get_viewport().set_input_as_handled()


# =========================================================
# 教學步驟
# =========================================================

func _build_steps() -> Array[Dictionary]:
	return [
		{
			"title": "PICTOR｜任務開始",
			"description":
				"PICTOR 已進入任務區。\n\n" +
				"先熟悉移動與戰鬥，再學習如何透過筆劃創造力量。",
			"stroke_mode": -1,
			"height": 290
		},
		{
			"title": "01｜移動",
			"description":
				"按 A 向左移動，按 D 向右移動。\n\n",
			"stroke_mode": -1,
			"height": 290
		},
		{
			"title": "02｜跳躍",
			"description":
				"使用遊戲原本設定的跳躍按鍵，練習起跳與落地。\n\n" ,
			"stroke_mode": -1,
			"height": 290
		},
		{
			"title": "03｜攻擊",
			"description":
				"使用遊戲原本設定的攻擊按鍵，熟悉角色的攻擊動作與出手時機。",
			"stroke_mode": -1,
			"height": 290
		},
		{
			"title": "04｜繪素",
			"description":
				"繪素是施展繪畫能力所需的資源。\n\n" +
				"目前教學設定：繪素上限 100，每秒恢復 8 點。\n" +
				"召喚靈鳥預設消耗 30 點，召喚大象預設消耗 50 點。",
			"stroke_mode": -1,
			"height": 320
		},
		{
			"title": "05｜畫直線召喚大象",
			"description":
				"按住滑鼠左鍵，畫出一條接近垂直的直線，再放開滑鼠。\n\n" +
				"若符合畫筆系統的直線判定，便會嘗試召喚大象。\n" +
				"是否成功仍取決於目前畫筆系統的判定與繪素。",
			"stroke_mode": -1,
			"height": 320
		},
		{
			"title": "06｜畫圈召喚靈鳥",
			"description":
				"按住滑鼠左鍵畫一個圈，盡量回到起點附近，再放開。\n\n" +
				"符合畫筆系統的圓形判定時，便會嘗試召喚靈鳥。\n" +
				"注意下方的畫圈示意圖。",
			"stroke_mode": StrokeDiagram.MODE_CIRCLE,
			"height": 440
		},
		{
			"title": "07｜畫直線指揮靈鳥",
			"description":
				"靈鳥出現後，按住滑鼠左鍵畫出一條足夠長的直線，再放開。\n\n" +
				"直線的方向會用來指揮靈鳥飛行。\n" +
				"注意下方的直線示意圖。",
			"stroke_mode": StrokeDiagram.MODE_LINE,
			"height": 440
		},
		{
			"title": "教學完成",
			"description":
				"你已經了解基本操作、繪素與主要筆劃。\n\n" +
				"接下來，運用 A、D 移動，配合跳躍、攻擊與畫筆能力，繼續探索 PICTOR 的世界。",
			"stroke_mode": -1,
			"height": 310
		}
	]


# =========================================================
# 播放教學
# =========================================================

func _play_tutorial() -> void:
	for step in _build_steps():
		if not is_inside_tree():
			return

		await _show_step(step)

	tutorial_running = false

	if is_instance_valid(overlay):
		overlay.queue_free()

	if is_in_group(MANAGER_GROUP):
		remove_from_group(MANAGER_GROUP)


func _show_step(step: Dictionary) -> void:
	continue_requested = false

	title_label.text = str(
		step.get("title", "操作提示")
	)

	description_label.text = str(
		step.get("description", "")
	)

	var mode := int(step.get("stroke_mode", -1))

	stroke_diagram.visible = mode >= 0

	if mode >= 0:
		stroke_diagram.set_mode(mode)

	tutorial_panel.offset_bottom = int(
		step.get("height", 290)
	)

	key_hint_label.text = "按 Enter 繼續"

	while is_inside_tree() and not continue_requested:
		await get_tree().process_frame
