extends CanvasLayer
## Add/remove/reorder Control children of Pages in the scene to edit the guide.
## Each page can contain arbitrary UI; Image and Placeholder are optional.

@onready var screen: Control = %Screen
@onready var pages_root: Control = %Pages
@onready var empty_state: Label = %EmptyState
@onready var previous_button: Button = %Previous
@onready var next_button: Button = %Next
@onready var close_button: Button = %Close
@onready var page_counter: Label = %PageCounter
var pages: Array[Control] = []
var page_index: int = 0

func _ready() -> void:
	screen.hide()
	previous_button.pressed.connect(change_page.bind(-1))
	next_button.pressed.connect(change_page.bind(1))
	close_button.pressed.connect(GameManager.close_tutorial)
	GameManager.tutorial_changed.connect(_on_tutorial_changed)
	_refresh_pages()
	if GameManager.tutorial_open: _on_tutorial_changed(true)

func _refresh_pages() -> void:
	pages.clear()
	for child in pages_root.get_children():
		if child is Control: pages.append(child)
	_show_page(0)

func _on_tutorial_changed(open: bool) -> void:
	if not is_inside_tree(): return
	screen.visible = open
	if open:
		_refresh_pages()
		if next_button.disabled: close_button.grab_focus()
		else: next_button.grab_focus()
	else:
		previous_button.release_focus()
		next_button.release_focus()
		close_button.release_focus()

func change_page(step: int) -> void:
	if not GameManager.tutorial_open: return
	_show_page(page_index + step)
	# Keep keyboard navigation usable when the focused button becomes disabled.
	if previous_button.disabled and previous_button.has_focus(): next_button.grab_focus()
	if next_button.disabled and next_button.has_focus(): previous_button.grab_focus()

func _show_page(index: int) -> void:
	page_index = clampi(index, 0, maxi(0, pages.size() - 1))
	for i in pages.size():
		var page := pages[i]
		page.visible = i == page_index
		var picture := page.get_node_or_null("Image") as TextureRect
		var placeholder := page.get_node_or_null("Placeholder") as Label
		if placeholder != null:
			placeholder.text = "PAGE %d" % (i + 1)
			placeholder.visible = picture == null or picture.texture == null
	pages_root.visible = not pages.is_empty()
	empty_state.visible = pages.is_empty()
	page_counter.text = "%d / %d" % [page_index + 1 if not pages.is_empty() else 0, pages.size()]
	previous_button.disabled = pages.is_empty() or page_index == 0
	next_button.disabled = pages.is_empty() or page_index == pages.size() - 1

func _unhandled_key_input(event: InputEvent) -> void:
	if not GameManager.tutorial_open: return
	if event.is_action_pressed("ui_left"):
		change_page(-1)
	elif event.is_action_pressed("ui_right"):
		change_page(1)
	else:
		return
	get_viewport().set_input_as_handled()
