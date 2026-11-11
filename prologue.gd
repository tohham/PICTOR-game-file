
extends Control

# =========================================================
# PICTOR — THE LAST STROKE
# Prologue.gd
# 序章：純黑底、白色旁白、自動播放
# 不在序章載入主角；主角在第一章才登場。
# Godot 4.7.1
# =========================================================

@export_group("下一章設定")
@export_file("*.tscn")
var next_scene_path: String = "res://chapter_01.tscn"

@export_group("旁白文字位置")
# 螢幕比例：0.5 表示水平或垂直中央。
@export var story_position_ratio: Vector2 = Vector2(0.20, 0.35)

# 文字區域寬度與高度，相對於螢幕大小。
@export var story_size_ratio: Vector2 = Vector2(0.60, 0.30)

# 在比例定位的基礎上，再以像素微調。
@export var story_position_offset: Vector2 = Vector2.ZERO

@export_group("旁白文字外觀")
@export_range(12, 64, 1) var text_font_size: int = 26
@export var text_color: Color = Color.WHITE

@export_enum("靠左", "置中", "靠右")
var text_alignment: int = HORIZONTAL_ALIGNMENT_CENTER

@export_group("旁白播放")
@export_range(0.0, 10.0, 0.1) var text_hold_seconds: float = 3.5
@export_range(0.0, 3.0, 0.1) var fade_seconds: float = 0.6
@export_range(0.0, 10.0, 0.1) var opening_delay: float = 1.0

const NEXT_CHAPTER_NUMBER: int = 1
const NEXT_CHAPTER_TITLE: String = "序章｜PICTOR"

const DIALOGUE_LINES: Array[String] = [
	"一塊古老的石板寫道:",

	"偃師之偶，丹青之魂，濡翰濟世，鼎革更始",

	"創世之息，盤古之造，天地萬象，化為石色",
	
	"創者若忘其衷，萬象終歸於白。",
	
	"此時，一道聲音忽然響起。",
	
	"..$..__.#.._....#@.../..",
	
	".._滋滋.滋..滋..._滋.滋......",
	
	"?!   檢測到細微能量，難道?",
	
	"PICTOR-iai:啟動"
]

var background: ColorRect
var story_label: Label
var is_playing_prologue: bool = false


# =========================================================
# 初始化
# =========================================================

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_create_background()
	_create_story_text()
	_layout_ui()

	if not get_viewport().size_changed.is_connected(_layout_ui):
		get_viewport().size_changed.connect(_layout_ui)

	await get_tree().create_timer(opening_delay).timeout

	if not is_inside_tree():
		return

	await _play_prologue()


# =========================================================
# 純黑背景
# =========================================================

func _create_background() -> void:
	background = ColorRect.new()
	background.name = "BlackBackground"
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -10

	add_child(background)


# =========================================================
# 純白旁白文字
# =========================================================

func _create_story_text() -> void:
	story_label = Label.new()
	story_label.name = "StoryText"
	story_label.text = ""

	story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	story_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_label.modulate.a = 0.0

	add_child(story_label)

	_apply_text_style()


func _apply_text_style() -> void:
	if not is_instance_valid(story_label):
		return

	story_label.add_theme_font_size_override(
		"font_size",
		text_font_size
	)

	story_label.add_theme_color_override(
		"font_color",
		text_color
	)

	story_label.horizontal_alignment = text_alignment


# =========================================================
# 文字排版：位置由 Inspector 控制
# =========================================================

func _layout_ui() -> void:
	if not is_instance_valid(story_label):
		return

	var screen_size: Vector2 = get_viewport().get_visible_rect().size

	story_label.position = Vector2(
		screen_size.x * story_position_ratio.x,
		screen_size.y * story_position_ratio.y
	) + story_position_offset

	story_label.size = Vector2(
		screen_size.x * story_size_ratio.x,
		screen_size.y * story_size_ratio.y
	)

	_apply_text_style()


# =========================================================
# 自動播放旁白
# =========================================================

func _play_prologue() -> void:
	if is_playing_prologue:
		return

	is_playing_prologue = true

	for line in DIALOGUE_LINES:
		if not is_inside_tree():
			return

		# 顯示當前旁白
		story_label.text = line
		story_label.modulate.a = 0.0

		_apply_text_style()

		# 淡入白字
		var fade_in := create_tween()

		fade_in.tween_property(
			story_label,
			"modulate:a",
			1.0,
			fade_seconds
		)

		await fade_in.finished

		if not is_inside_tree():
			return

		# 依照文字長度決定閱讀時間
		var hold_time: float = maxf(
			text_hold_seconds,
			float(line.length()) * 0.10
		)

		await get_tree().create_timer(hold_time).timeout

		if not is_inside_tree():
			return

		# 淡出白字
		var fade_out := create_tween()

		fade_out.tween_property(
			story_label,
			"modulate:a",
			0.0,
			fade_seconds
		)

		await fade_out.finished

	if is_inside_tree():
		await _enter_first_chapter()


# =========================================================
# 旁白結束，進入第一章
# =========================================================

func _enter_first_chapter() -> void:
	if next_scene_path.is_empty():
		push_error("尚未設定第一章場景路徑。")
		return

	if not ResourceLoader.exists(next_scene_path):
		push_error(
			"找不到第一章場景：" + next_scene_path
		)
		return

	await ChapterManager.change_to_chapter(
		next_scene_path,
		NEXT_CHAPTER_NUMBER,
		NEXT_CHAPTER_TITLE,
		true
	)
