extends Control

const CELL := 72
const SLOT := CELL + 8
## Horizontal inset; extra vertical top/bottom avoids ScrollContainer clipping the first row.
const BOARD_PAD_H := 16
const BOARD_PAD_TOP := 28
const BOARD_PAD_BOTTOM := 28
## Set false to silence [PoP board] lines in the Godot Output panel.
const BOARD_DEBUG_PRINT := true

var state: PoetryGameState
var _selected_anchor_id: int = -1
var _pressure_selected: Dictionary = {}

var _ref_ids_set: Dictionary = {}
var _shadow_under_ids: Dictionary = {}
var _refs_syncing: bool = false
var _shadow_syncing: bool = false
var _pick_refs_by_click: bool = false

var _shadow_row_ids: Array[int] = []

enum UISession { SETUP_GOAL, SETUP_OPENING, PLAYING }

var _ui_phase: UISession = UISession.SETUP_GOAL

@onready var _vbox: VBoxContainer = $VBox
var _setup_container: VBoxContainer
var _goal_step: VBoxContainer
var _opening_step: VBoxContainer
var _goal_edit: LineEdit
var _btn_goal_continue: Button
var _opening_phrase_edit: LineEdit
var _btn_place_opening: Button
var _opening_goal_reminder: Label
var _play_container: VBoxContainer
var _btn_new_game: Button
var _stats: Label
var _board_scroll: ScrollContainer
var _board_root: Control
var _board_rebuild_queued: bool = false
var _phrase_tier_rebuild_coalesce: bool = false
var _phrase: LineEdit
var _tier: OptionButton
var _relation_pick: OptionButton
var _pick_refs_cb: CheckBox
var _refs: LineEdit
var _shadow_label: Label
var _shadow_list: ItemList
var _shadows_under: LineEdit
var _tie_carried: CheckBox
var _place_btn: Button
var _pressure_label: Label
var _resolve_btn: Button
var _clear_pressure_btn: Button
var _take_btn: Button
var _log: RichTextLabel
var _placement_flow_hint: Label

var _pending_place_anchor_id: int = -1
var _pending_place_relation: PoetryGameState.Relation = PoetryGameState.Relation.WEST
var _has_pending_placement: bool = false


func _ready() -> void:
	state = PoetryGameState.new()
	state.state_changed.connect(_refresh_all)
	state.game_lost.connect(_on_lost)
	state.game_won.connect(_on_won)
	_build_ui()
	_refresh_all()


func _board_dbg(msg: String) -> void:
	if not BOARD_DEBUG_PRINT:
		return
	print("[PoP board] ", msg)


func _queue_board_rebuild() -> void:
	if _board_rebuild_queued:
		return
	_board_rebuild_queued = true
	call_deferred("_flush_board_rebuild")


func _flush_board_rebuild() -> void:
	_board_rebuild_queued = false
	_rebuild_board_ui()


func _reset_board_scroll_pan() -> void:
	if not is_instance_valid(_board_scroll):
		return
	_board_scroll.scroll_horizontal = 0
	_board_scroll.scroll_vertical = 0


func _on_phrase_focus_entered() -> void:
	_reset_board_scroll_pan()


func _cell_of_card(cid: int) -> Vector2i:
	if not state.cards.has(cid):
		_board_dbg("_cell_of_card: missing cards[%d]" % cid)
		return Vector2i.ZERO
	var cd: Dictionary = state.cards[cid]
	var raw: Variant = cd.get("cell", null)
	if raw == null:
		_board_dbg("_cell_of_card: cards[%d] has no 'cell' key, keys=%s" % [cid, str(cd.keys())])
		return Vector2i.ZERO
	if raw is Vector2i:
		return raw as Vector2i
	if raw is Vector2:
		var v2 := raw as Vector2
		return Vector2i(int(v2.x), int(v2.y))
	_board_dbg("_cell_of_card: cards[%d].cell unexpected type %s value=%s" % [cid, str(typeof(raw)), str(raw)])
	return Vector2i.ZERO


func _build_ui() -> void:
	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_setup_container = VBoxContainer.new()
	_setup_container.add_theme_constant_override("separation", 10)

	_goal_step = VBoxContainer.new()
	var step1 := Label.new()
	step1.text = "Setup — step 1 of 2: your goal"
	_goal_edit = LineEdit.new()
	_goal_edit.placeholder_text = "What you’re reaching for in this place (character or story goal)"
	_goal_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_goal_continue = Button.new()
	_btn_goal_continue.text = "Continue"
	_btn_goal_continue.pressed.connect(_on_goal_continue)
	_goal_step.add_child(step1)
	_goal_step.add_child(_goal_edit)
	_goal_step.add_child(_btn_goal_continue)

	_opening_step = VBoxContainer.new()
	var step2 := Label.new()
	step2.text = "Setup — step 2 of 2: opening landscape"
	step2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_opening_goal_reminder = Label.new()
	_opening_goal_reminder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var step2_detail := Label.new()
	step2_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step2_detail.text = "This becomes the first card on the board (center / origin)."
	_opening_phrase_edit = LineEdit.new()
	_opening_phrase_edit.placeholder_text = "Image phrase for the first landscape"
	_opening_phrase_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_place_opening = Button.new()
	_btn_place_opening.text = "Place opening landscape & begin"
	_btn_place_opening.pressed.connect(_on_place_opening)
	_opening_step.add_child(step2)
	_opening_step.add_child(_opening_goal_reminder)
	_opening_step.add_child(step2_detail)
	_opening_step.add_child(_opening_phrase_edit)
	_opening_step.add_child(_btn_place_opening)
	_opening_step.visible = false

	_setup_container.add_child(_goal_step)
	_setup_container.add_child(_opening_step)

	_play_container = VBoxContainer.new()
	_play_container.add_theme_constant_override("separation", 8)
	_play_container.visible = false

	_btn_new_game = Button.new()
	_btn_new_game.text = "New game (reset)"
	_btn_new_game.pressed.connect(_on_new_game)
	_play_container.add_child(_btn_new_game)

	_board_scroll = ScrollContainer.new()
	_board_scroll.custom_minimum_size = Vector2(420, 280)
	_board_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_board_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_board_scroll.follow_focus = false
	_board_root = Control.new()
	_board_root.clip_contents = false
	_board_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_board_root.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_board_root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_board_scroll.add_child(_board_root)
	_board_root.anchor_left = 0.0
	_board_root.anchor_top = 0.0
	_board_root.anchor_right = 0.0
	_board_root.anchor_bottom = 0.0
	_phrase = LineEdit.new()
	_phrase.placeholder_text = "Image phrase"
	_phrase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phrase.text_changed.connect(_on_phrase_or_tier_changed)
	_phrase.focus_entered.connect(_on_phrase_focus_entered)
	_tier = OptionButton.new()
	for t: int in [
		PoetryGameState.Tier.LANDSCAPE,
		PoetryGameState.Tier.STRUCTURE,
		PoetryGameState.Tier.ROOM,
		PoetryGameState.Tier.CONTAINER,
		PoetryGameState.Tier.OBJECT,
	]:
		_tier.add_item(PoetryGameState.tier_display(t), t)
	_tier.item_selected.connect(_on_phrase_or_tier_changed)
	_relation_pick = OptionButton.new()
	_relation_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_relation_pick.item_selected.connect(_on_relation_pick_selected)
	_pick_refs_cb = CheckBox.new()
	_pick_refs_cb.text = "Pick references by clicking cards (does not change anchor)"
	_pick_refs_cb.toggled.connect(_on_pick_refs_toggled)
	_refs = LineEdit.new()
	_refs.placeholder_text = "Reference card IDs (type, paste, or click mode above)"
	_refs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refs.text_changed.connect(_on_refs_text_changed)
	_shadow_label = Label.new()
	_shadow_label.text = "Loose shadows — click to toggle “under” next placement:"
	_shadow_list = ItemList.new()
	_shadow_list.select_mode = ItemList.SELECT_MULTI
	_shadow_list.allow_reselect = true
	_shadow_list.custom_minimum_size = Vector2(0, 120)
	_shadow_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shadow_list.multi_selected.connect(_on_shadow_multi_selected)
	_shadows_under = LineEdit.new()
	_shadows_under.placeholder_text = "Shadow IDs under (syncs with list; you can still type)"
	_shadows_under.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shadows_under.text_changed.connect(_on_shadows_under_text_changed)
	_tie_carried = CheckBox.new()
	_tie_carried.text = "Use carried object as tie (adds it to refs, clears carry)"
	_place_btn = Button.new()
	_place_btn.text = "Place card"
	_place_btn.disabled = true
	_place_btn.pressed.connect(_on_place)
	_pressure_label = Label.new()
	_pressure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resolve_btn = Button.new()
	_resolve_btn.text = "Resolve pressure (send selected to shadows)"
	_resolve_btn.pressed.connect(_on_resolve_pressure)
	_clear_pressure_btn = Button.new()
	_clear_pressure_btn.text = "Clear pressure selection"
	_clear_pressure_btn.pressed.connect(_on_clear_pressure_sel)
	_take_btn = Button.new()
	_take_btn.text = "Take object (selected card)"
	_take_btn.pressed.connect(_on_take_object)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.scroll_active = true
	_log.custom_minimum_size.y = 120
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 120
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_play_container.add_child(_board_scroll)
	_placement_flow_hint = Label.new()
	_placement_flow_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_play_container.add_child(_placement_flow_hint)
	_play_container.add_child(_phrase)
	_play_container.add_child(_tier)
	var dir_lbl := Label.new()
	dir_lbl.text = "Side (from blue anchor card — pick one):"
	_play_container.add_child(dir_lbl)
	_play_container.add_child(_relation_pick)
	_hrow(_place_btn, _take_btn)
	var play_hint := Label.new()
	play_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	play_hint.text = "Pick tier → choose a side above (or a green ＋ on the board) → type a phrase → Place card. References & shadows optional below."
	_play_container.add_child(play_hint)
	_play_container.add_child(_pick_refs_cb)
	_play_container.add_child(_refs)
	_play_container.add_child(_shadow_label)
	_play_container.add_child(_shadow_list)
	_play_container.add_child(_shadows_under)
	_play_container.add_child(_tie_carried)
	_play_container.add_child(_pressure_label)
	_hrow(_resolve_btn, _clear_pressure_btn)
	_play_container.add_child(scroll)

	_vbox.add_child(_stats)
	_vbox.add_child(_setup_container)
	_vbox.add_child(_play_container)
	_update_phase_ui()


func _update_phase_ui() -> void:
	match _ui_phase:
		UISession.SETUP_GOAL:
			_setup_container.visible = true
			_goal_step.visible = true
			_opening_step.visible = false
			_play_container.visible = false
		UISession.SETUP_OPENING:
			_setup_container.visible = true
			_goal_step.visible = false
			_opening_step.visible = true
			_play_container.visible = false
			_update_opening_step_goal_line()
		UISession.PLAYING:
			_setup_container.visible = false
			_play_container.visible = true


func _update_opening_step_goal_line() -> void:
	_opening_goal_reminder.text = "Goal: %s" % state.goal


func _hrow(a: Control, b: Control) -> void:
	var h := HBoxContainer.new()
	h.add_child(a)
	h.add_child(b)
	_play_container.add_child(h)


func _current_tier_safe() -> PoetryGameState.Tier:
	if not is_instance_valid(_tier) or _tier.get_item_count() == 0:
		return PoetryGameState.Tier.LANDSCAPE
	var idx := _tier.selected
	if idx < 0 or idx >= _tier.get_item_count():
		_tier.select(0)
		idx = 0
	return _tier.get_item_id(idx) as PoetryGameState.Tier


func _on_pick_refs_toggled(pressed: bool) -> void:
	_pick_refs_by_click = pressed
	_clear_pending_placement()
	_queue_board_rebuild()


func _clear_pending_placement() -> void:
	_has_pending_placement = false
	_pending_place_anchor_id = -1


func _should_show_placement_highlights() -> bool:
	if _ui_phase != UISession.PLAYING:
		return false
	if state.cards.is_empty() or state.pressure_pending or state.game_ended:
		return false
	if _pick_refs_by_click:
		return false
	return true


func _on_phrase_or_tier_changed(_arg: Variant = null) -> void:
	_clear_pending_placement()
	if _phrase_tier_rebuild_coalesce:
		return
	_phrase_tier_rebuild_coalesce = true
	call_deferred("_flush_phrase_tier_board_rebuild")


func _flush_phrase_tier_board_rebuild() -> void:
	_phrase_tier_rebuild_coalesce = false
	_queue_board_rebuild()


func _update_place_button_state() -> void:
	if not is_instance_valid(_place_btn):
		return
	var place_enabled := _ui_phase == UISession.PLAYING \
		and not state.cards.is_empty() \
		and not state.pressure_pending \
		and not state.game_ended \
		and not _phrase.text.strip_edges().is_empty() \
		and _has_pending_placement
	_place_btn.disabled = not place_enabled
	_refresh_placement_flow_hint()


func _refresh_placement_flow_hint() -> void:
	if not is_instance_valid(_placement_flow_hint):
		return
	if _ui_phase != UISession.PLAYING:
		_placement_flow_hint.text = ""
		return
	if state.pressure_pending:
		_placement_flow_hint.text = "Pressure: pick cards to remove, then Resolve — not placing now."
		return
	if state.game_ended:
		_placement_flow_hint.text = "Game over — start a new game."
		return
	if _pick_refs_by_click:
		_placement_flow_hint.text = "Reference-click mode: turn off the checkbox to place cards."
		return
	if _phrase.text.strip_edges().is_empty():
		if _has_pending_placement:
			_placement_flow_hint.text = "Side chosen — type an image phrase, then press Place card."
		else:
			_placement_flow_hint.text = "Use the Side dropdown (under Tier) or a green + next to the blue anchor. Then type a phrase and press Place card."
	else:
		if not _has_pending_placement:
			_placement_flow_hint.text = "Phrase set — pick Left/Right/Above/Below in the Side dropdown (or a green +), then Place card."
		else:
			_placement_flow_hint.text = "Ready — press Place card (enabled) to confirm."


func _on_placement_slot_pressed(cell_key: String) -> void:
	var tier: PoetryGameState.Tier = _current_tier_safe()
	var m := state.valid_placement_slots_from_anchor(tier, _selected_anchor_id)
	if not m.has(cell_key):
		return
	var d: Dictionary = m[cell_key]
	_pending_place_anchor_id = int(d["anchor_id"])
	_pending_place_relation = int(d["relation"]) as PoetryGameState.Relation
	_has_pending_placement = true
	_update_place_button_state()
	_queue_board_rebuild()


const _REL_DROPDOWN_PLACEHOLDER := -999
const _REL_DROPDOWN_CHOOSE := -998


func _sync_relation_placement_dropdown() -> void:
	if not is_instance_valid(_relation_pick):
		return
	var had_pick_sig := _relation_pick.item_selected.is_connected(_on_relation_pick_selected)
	if had_pick_sig:
		_relation_pick.item_selected.disconnect(_on_relation_pick_selected)
	_do_sync_relation_placement_dropdown()
	if had_pick_sig:
		_relation_pick.item_selected.connect(_on_relation_pick_selected)


func _do_sync_relation_placement_dropdown() -> void:
	_relation_pick.clear()
	if _ui_phase != UISession.PLAYING:
		_relation_pick.add_item("—", _REL_DROPDOWN_PLACEHOLDER)
		_relation_pick.disabled = true
		return
	if state.cards.is_empty():
		_relation_pick.add_item("—", _REL_DROPDOWN_PLACEHOLDER)
		_relation_pick.disabled = true
		return
	if state.pressure_pending or state.game_ended or _pick_refs_by_click:
		_relation_pick.add_item("—", _REL_DROPDOWN_PLACEHOLDER)
		_relation_pick.disabled = true
		return
	if _selected_anchor_id < 0:
		_relation_pick.add_item("Click a board card to pick anchor (blue)", _REL_DROPDOWN_PLACEHOLDER)
		_relation_pick.disabled = true
		return
	var tier: PoetryGameState.Tier = _current_tier_safe()
	var rels: Array[int] = state.valid_relations_from_anchor(tier, _selected_anchor_id)
	if rels.is_empty():
		_relation_pick.add_item("No legal side for this tier from this anchor", _REL_DROPDOWN_PLACEHOLDER)
		_relation_pick.disabled = true
		return
	_relation_pick.disabled = false
	if rels.size() > 1:
		_relation_pick.add_item("Choose side…", _REL_DROPDOWN_CHOOSE)
	for r_int in rels:
		var r: PoetryGameState.Relation = r_int as PoetryGameState.Relation
		_relation_pick.add_item(
			"%s of card #%d" % [PoetryGameState.relation_display(r), _selected_anchor_id],
			r_int)
	if rels.size() == 1:
		_relation_pick.select(0)
		_pending_place_anchor_id = _selected_anchor_id
		_pending_place_relation = rels[0] as PoetryGameState.Relation
		_has_pending_placement = true
	else:
		var restored := false
		if _has_pending_placement and _pending_place_anchor_id == _selected_anchor_id:
			for i in range(_relation_pick.get_item_count()):
				if _relation_pick.get_item_id(i) == int(_pending_place_relation):
					_relation_pick.select(i)
					restored = true
					break
		if not restored:
			_clear_pending_placement()
			_relation_pick.select(0)


func _on_relation_pick_selected(_index: int) -> void:
	if not is_instance_valid(_relation_pick):
		return
	var sel := _relation_pick.selected
	if sel < 0 or sel >= _relation_pick.get_item_count():
		return
	var id: int = _relation_pick.get_item_id(sel)
	if id == _REL_DROPDOWN_PLACEHOLDER or id == _REL_DROPDOWN_CHOOSE:
		_clear_pending_placement()
		_update_place_button_state()
		_queue_board_rebuild()
		return
	if id < int(PoetryGameState.Relation.WEST) or id > int(PoetryGameState.Relation.SOUTH):
		return
	if _selected_anchor_id < 0:
		return
	_pending_place_anchor_id = _selected_anchor_id
	_pending_place_relation = id as PoetryGameState.Relation
	_has_pending_placement = true
	_update_place_button_state()
	_queue_board_rebuild()


func _sorted_int_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys


func _set_refs_line_from_set() -> void:
	_refs_syncing = true
	var parts: PackedStringArray = PackedStringArray()
	for k in _sorted_int_keys(_ref_ids_set):
		parts.append(str(int(k)))
	_refs.text = ",".join(parts)
	_refs_syncing = false


func _on_refs_text_changed(_new_text: String) -> void:
	if _refs_syncing:
		return
	_ref_ids_set.clear()
	for x in _parse_id_list(_refs.text):
		_ref_ids_set[int(x)] = true


func _set_shadow_line_from_set() -> void:
	_shadow_syncing = true
	var parts: PackedStringArray = PackedStringArray()
	for k in _sorted_int_keys(_shadow_under_ids):
		parts.append(str(int(k)))
	_shadows_under.text = ",".join(parts)
	_shadow_syncing = false


func _on_shadows_under_text_changed(_new_text: String) -> void:
	if _shadow_syncing:
		return
	_shadow_under_ids.clear()
	for x in _parse_id_list(_shadows_under.text):
		_shadow_under_ids[int(x)] = true
	_refresh_shadow_list_selection_only()


func _on_shadow_multi_selected(_index: int, _selected: bool) -> void:
	if _shadow_syncing:
		return
	_shadow_under_ids.clear()
	for row in _shadow_list.get_selected_items():
		if row >= 0 and row < _shadow_row_ids.size():
			_shadow_under_ids[_shadow_row_ids[row]] = true
	_set_shadow_line_from_set()


func _prune_shadow_under_selection() -> void:
	var loose: Dictionary = {}
	for sid in state.loose_shadow_ids():
		loose[int(sid)] = true
	for k in _shadow_under_ids.keys():
		if not loose.has(int(k)):
			_shadow_under_ids.erase(k)


func _refresh_shadow_list() -> void:
	if not is_instance_valid(_shadow_list):
		return
	_prune_shadow_under_selection()
	_shadow_syncing = true
	_shadow_list.clear()
	_shadow_row_ids.clear()
	if state.cards.is_empty():
		_shadow_syncing = false
		return
	for sid in state.loose_shadow_ids():
		var ph := str(state.cards[int(sid)].phrase)
		if ph.length() > 36:
			ph = ph.substr(0, 33) + "…"
		_shadow_list.add_item("%d · %s" % [int(sid), ph])
		_shadow_row_ids.append(int(sid))
	for r in range(_shadow_list.item_count):
		if _shadow_under_ids.has(_shadow_row_ids[r]):
			_shadow_list.select(r)
	_shadow_syncing = false


func _refresh_shadow_list_selection_only() -> void:
	if not is_instance_valid(_shadow_list) or _shadow_syncing:
		return
	_shadow_syncing = true
	for r in range(_shadow_list.item_count):
		var sid := _shadow_row_ids[r] if r < _shadow_row_ids.size() else -1
		if sid < 0:
			continue
		if _shadow_under_ids.has(sid):
			if not _shadow_list.is_selected(r):
				_shadow_list.select(r)
		else:
			if _shadow_list.is_selected(r):
				_shadow_list.deselect(r)
	_shadow_syncing = false


func _ref_ids_for_place() -> Array:
	var merged: Dictionary = {}
	for k in _ref_ids_set:
		merged[int(k)] = true
	for x in _parse_id_list(_refs.text):
		merged[int(x)] = true
	return _sorted_int_keys(merged)


func _shadow_ids_for_place() -> Array:
	var merged: Dictionary = {}
	for k in _shadow_under_ids:
		merged[int(k)] = true
	for x in _parse_id_list(_shadows_under.text):
		merged[int(x)] = true
	return _sorted_int_keys(merged)


func _on_goal_continue() -> void:
	state.set_goal(_goal_edit.text)
	_ui_phase = UISession.SETUP_OPENING
	_update_phase_ui()
	_refresh_stats()


func _on_place_opening() -> void:
	var err := state.place_opening_landscape(_opening_phrase_edit.text)
	if not err.is_empty():
		_log_append("[color=red]%s[/color]" % err)
		return
	_board_dbg("_on_place_opening ok cards=%d cell_to_id keys=%s" % [state.cards.size(), str(state.cell_to_id.keys())])
	_ui_phase = UISession.PLAYING
	_update_phase_ui()
	_opening_phrase_edit.text = ""
	_log_append("[b]Play.[/b] Opening landscape placed. Goal: %s" % state.goal)
	_refresh_stats()
	_refresh_all()


func _clear_play_transient() -> void:
	_clear_pending_placement()
	_pressure_selected.clear()
	_ref_ids_set.clear()
	_shadow_under_ids.clear()
	_refs_syncing = true
	_refs.text = ""
	_refs_syncing = false
	_shadow_syncing = true
	_shadows_under.text = ""
	_shadow_syncing = false
	_pick_refs_cb.button_pressed = false
	_pick_refs_by_click = false
	_selected_anchor_id = -1


func _on_new_game() -> void:
	_ui_phase = UISession.SETUP_GOAL
	state.new_session()
	_goal_edit.text = ""
	_opening_phrase_edit.text = ""
	_phrase.text = ""
	_clear_play_transient()
	_update_phase_ui()
	_log_append("[b]New session.[/b] Enter your goal again.")


func _board_sorted_ids() -> Array[int]:
	var ids: Array[int] = []
	for bid in state.cell_to_id.values():
		ids.append(int(bid))
	ids.sort()
	return ids


func _apply_board_control_layout(ctrl: Control, lx: int, ly: int) -> void:
	# Top-left anchors + offsets (reliable in ScrollContainer; position/size alone often ignored).
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = float(lx)
	ctrl.offset_top = float(ly)
	ctrl.offset_right = float(lx + CELL)
	ctrl.offset_bottom = float(ly + CELL)
	ctrl.custom_minimum_size = Vector2(CELL, CELL)


func _rebuild_board_ui() -> void:
	_board_dbg("_rebuild_board_ui start phase=%s cards=%d cell_to_id=%d play_visible=%s" % [
		str(_ui_phase), state.cards.size(), state.cell_to_id.size(), str(_play_container.visible if is_instance_valid(_play_container) else false),
	])
	while _board_root.get_child_count() > 0:
		var ch: Node = _board_root.get_child(0)
		_board_root.remove_child(ch)
		ch.free()
	if state.cards.is_empty():
		_board_dbg("_rebuild_board_ui early exit (no cards)")
		_board_root.custom_minimum_size = Vector2(
			BOARD_PAD_H * 2 + SLOT,
			BOARD_PAD_TOP + BOARD_PAD_BOTTOM + SLOT)
		_board_root.offset_right = _board_root.custom_minimum_size.x
		_board_root.offset_bottom = _board_root.custom_minimum_size.y
		_sync_relation_placement_dropdown()
		_update_place_button_state()
		call_deferred("_reset_board_scroll_pan")
		return

	var tier: PoetryGameState.Tier = _current_tier_safe()
	var valid_by_cell: Dictionary = {}
	if _should_show_placement_highlights() and _selected_anchor_id >= 0:
		valid_by_cell = state.valid_placement_slots_from_anchor(tier, _selected_anchor_id)

	var min_x := 999999
	var min_y := 999999
	var max_x := -999999
	var max_y := -999999
	for cid_bounds in _board_sorted_ids():
		var cv_b: Vector2i = _cell_of_card(cid_bounds)
		min_x = mini(min_x, cv_b.x)
		min_y = mini(min_y, cv_b.y)
		max_x = maxi(max_x, cv_b.x)
		max_y = maxi(max_y, cv_b.y)
	for ck_bounds in valid_by_cell.keys():
		var ent_bounds: Dictionary = valid_by_cell[ck_bounds]
		var vc: Vector2i = ent_bounds["cell"]
		min_x = mini(min_x, vc.x)
		min_y = mini(min_y, vc.y)
		max_x = maxi(max_x, vc.x)
		max_y = maxi(max_y, vc.y)

	var span_x := max_x - min_x + 1
	var span_y := max_y - min_y + 1
	_board_root.custom_minimum_size = Vector2(
		BOARD_PAD_H * 2 + span_x * SLOT,
		BOARD_PAD_TOP + BOARD_PAD_BOTTOM + span_y * SLOT)

	for cid in _board_sorted_ids():
		var cv: Vector2i = _cell_of_card(cid)
		var lx := BOARD_PAD_H + (cv.x - min_x) * SLOT
		var ly := BOARD_PAD_TOP + (cv.y - min_y) * SLOT
		var b := Button.new()
		b.z_index = 0
		_apply_board_control_layout(b, lx, ly)
		b.clip_text = true
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_on_board_card_pressed.bind(cid))
		_style_board_button(b, cid)
		_board_root.add_child(b)

	for ck in valid_by_cell.keys():
		var entry: Dictionary = valid_by_cell[ck]
		var cl: Vector2i = entry["cell"]
		if state.card_at(cl) >= 0:
			continue
		var lx2: int = BOARD_PAD_H + (cl.x - min_x) * SLOT
		var ly2: int = BOARD_PAD_TOP + (cl.y - min_y) * SLOT
		var sb := Button.new()
		sb.z_index = 2
		_apply_board_control_layout(sb, lx2, ly2)
		sb.flat = true
		sb.text = "＋"
		var d: Dictionary = valid_by_cell[ck]
		var aid := int(d["anchor_id"])
		var rel_i := int(d["relation"])
		var rel: PoetryGameState.Relation = rel_i as PoetryGameState.Relation
		var tip_phrase := str(state.cards[aid].phrase)
		if tip_phrase.length() > 28:
			tip_phrase = tip_phrase.substr(0, 25) + "…"
		sb.tooltip_text = "%s — %s of #%d “%s”" % [
			PoetryGameState.tier_display(tier),
			PoetryGameState.relation_display(rel),
			aid,
			tip_phrase,
		]
		var pending_cell := Vector2i(999999, 999999)
		if _has_pending_placement and state.cards.has(_pending_place_anchor_id):
			pending_cell = state.cell_for_relation(_pending_place_anchor_id, _pending_place_relation)
		if pending_cell == cl:
			sb.modulate = Color(0.2, 1.0, 0.45, 0.95)
		else:
			sb.modulate = Color(0.5, 0.88, 0.55, 0.7)
		sb.pressed.connect(_on_placement_slot_pressed.bind(ck))
		_board_root.add_child(sb)

	var sz: Vector2 = _board_root.custom_minimum_size
	_board_root.offset_left = 0.0
	_board_root.offset_top = 0.0
	_board_root.offset_right = sz.x
	_board_root.offset_bottom = sz.y
	_board_dbg("_rebuild_board_ui built card_btns+slots=%d min=(%d,%d) max=(%d,%d) root_min=%s scroll_size=%s" % [
		_board_root.get_child_count(), min_x, min_y, max_x, max_y, str(_board_root.custom_minimum_size),
		str(_board_scroll.size) if is_instance_valid(_board_scroll) else "?",
	])
	for i in range(_board_root.get_child_count()):
		var w: Control = _board_root.get_child(i) as Control
		if w:
			_board_dbg("  child[%d] %s rect off LTRB=(%.0f,%.0f,%.0f,%.0f) visible=%s text=%s" % [
				i, w.get_class(), w.offset_left, w.offset_top, w.offset_right, w.offset_bottom, str(w.visible), str(w is Button and (w as Button).text.substr(0, 12)),
			])
	_sync_relation_placement_dropdown()
	_update_place_button_state()
	call_deferred("_reset_board_scroll_pan")


func _style_board_button(b: Button, cid: int) -> void:
	var c: Dictionary = state.cards[cid]
	var abbr := PoetryGameState.tier_display(c.tier).substr(0, 1)
	b.text = "%s%d\n%s" % [abbr, int(c.impact), _short_phrase(str(c.phrase))]
	var tip := "ID %d · %s\n%s" % [cid, PoetryGameState.tier_display(c.tier), str(c.phrase)]
	var su: Array = c.shadows_under
	if su.size() > 0:
		var ids_txt: PackedStringArray = PackedStringArray()
		for x in su:
			ids_txt.append(str(x))
		tip += "\nShadows under: " + ", ".join(ids_txt)
	b.tooltip_text = tip
	if state.pressure_pending and _pressure_selected.has(cid):
		b.modulate = Color(1.0, 0.82, 0.65)
	elif not state.pressure_pending and cid == _selected_anchor_id:
		b.modulate = Color(0.85, 0.95, 1.0)
	elif _pick_refs_by_click and not state.pressure_pending and _ref_ids_set.has(cid):
		b.modulate = Color(0.75, 1.0, 0.75)
	else:
		b.modulate = Color.WHITE


func _on_board_card_pressed(card_id: int) -> void:
	if state.pressure_pending:
		_clear_pending_placement()
		if _pressure_selected.has(card_id):
			_pressure_selected.erase(card_id)
		else:
			_pressure_selected[card_id] = true
	elif _pick_refs_by_click:
		if _ref_ids_set.has(card_id):
			_ref_ids_set.erase(card_id)
		else:
			_ref_ids_set[card_id] = true
		_set_refs_line_from_set()
	else:
		if _selected_anchor_id != card_id:
			_clear_pending_placement()
			_selected_anchor_id = card_id
	# Same-card click must still rebuild (shows green + slots). Cannot free emitting Button same frame.
	_queue_board_rebuild()


func _parse_id_list(raw_line: String) -> Array:
	var out: Array = []
	var raw := raw_line.strip_edges()
	if raw.is_empty():
		return out
	for part in raw.split(","):
		var s := part.strip_edges()
		if s.is_valid_int():
			out.append(s.to_int())
	return out


func _on_place() -> void:
	if state.cards.is_empty():
		_log_append("Start a game first.")
		return
	if not _has_pending_placement:
		_log_append("Enter a phrase, pick a tier, then click a green slot for where the card goes.")
		return
	var phrase := _phrase.text.strip_edges()
	if phrase.is_empty():
		_log_append("Enter an image phrase first.")
		return
	var tier: PoetryGameState.Tier = _current_tier_safe()
	var pa := _pending_place_anchor_id
	var pr := _pending_place_relation
	var refs := _ref_ids_for_place()
	var under := _shadow_ids_for_place()
	var err := state.place_card(
		phrase, tier, pa, pr, refs, under, _tie_carried.button_pressed)
	if err.is_empty():
		var tgt: Vector2i = state.cell_for_relation(pa, pr)
		_log_append("Placed [%s] “%s” %s #%d → cell %s — board impact %d." % [
			PoetryGameState.tier_display(tier),
			phrase,
			PoetryGameState.relation_display(pr),
			pa,
			tgt,
			state.board_impact_sum(),
		])
		if not under.is_empty():
			_log_append("Shadows under: %s" % str(under))
		if state.pressure_pending:
			_log_append("[color=yellow]Pressure: total impact above 7. Select cards to remove, then Resolve.[/color]")
		_clear_pending_placement()
		_phrase.text = ""
		_ref_ids_set.clear()
		_shadow_under_ids.clear()
		_refs_syncing = true
		_refs.text = ""
		_refs_syncing = false
		_shadow_syncing = true
		_shadows_under.text = ""
		_shadow_syncing = false
		_tie_carried.button_pressed = false
	else:
		_log_append("[color=red]%s[/color]" % err)


func _on_resolve_pressure() -> void:
	var ids: Array = _pressure_selected.keys()
	var err := state.resolve_pressure(ids)
	if err.is_empty():
		_log_append("Pressure resolved. Shadows: %d. Board impact: %d." % [
			state.shadow_count(), state.board_impact_sum()
		])
		_pressure_selected.clear()
	else:
		_log_append("[color=red]%s[/color]" % err)


func _on_clear_pressure_sel() -> void:
	_pressure_selected.clear()
	_queue_board_rebuild()


func _on_take_object() -> void:
	if _selected_anchor_id < 0:
		_log_append("Select a card (the object) on the board.")
		return
	var err := state.take_object(_selected_anchor_id)
	if err.is_empty():
		_selected_anchor_id = -1
		_log_append("Object taken. Carried: “%s”." % state.carried_phrase())
	else:
		_log_append("[color=red]%s[/color]" % err)


func _on_lost(reason: String) -> void:
	_log_append("[color=red][b]%s[/b][/color]" % reason)


func _on_won(reason: String) -> void:
	_log_append("[color=green][b]%s[/b][/color]" % reason)


func _anchor_on_board() -> bool:
	if _selected_anchor_id < 0:
		return false
	for bid in state.cell_to_id.values():
		if int(bid) == _selected_anchor_id:
			return true
	return false


## When only one card is on the board, select it as anchor so the first placement works without an extra click.
func _ensure_default_anchor() -> void:
	if state.pressure_pending:
		return
	if _anchor_on_board():
		return
	if state.cell_to_id.size() != 1:
		return
	for bid in state.cell_to_id.values():
		_selected_anchor_id = int(bid)
		return


func _refresh_all() -> void:
	_board_rebuild_queued = false
	_board_dbg("_refresh_all cards=%d anchor_id=%d" % [state.cards.size(), _selected_anchor_id])
	_refresh_shadow_list()
	if not _anchor_on_board():
		_selected_anchor_id = -1
	_ensure_default_anchor()
	if state.pressure_pending or state.game_ended:
		_clear_pending_placement()
	_rebuild_board_ui()
	_refresh_stats()


func _refresh_stats() -> void:
	match _ui_phase:
		UISession.SETUP_GOAL:
			_stats.text = "Step 1 of 2 — Set your goal, then Continue."
			_pressure_label.text = ""
			return
		UISession.SETUP_OPENING:
			_stats.text = "Step 2 of 2 — Goal: %s\nDescribe the opening landscape and place it on the board." % state.goal
			_pressure_label.text = ""
			return
		UISession.PLAYING:
			pass
	if state.cards.is_empty():
		_stats.text = "No cards on board."
		_pressure_label.text = ""
		return
	var parts: PackedStringArray = PackedStringArray([
		"Goal: %s" % state.goal,
		"Cards used: %d / %d · Shadows: %d / %d · Board impact: %d" % [
			PoetryGameState.MAX_CARDS - state.cards_remaining(),
			PoetryGameState.MAX_CARDS,
			state.shadow_count(),
			PoetryGameState.SHADOW_LOSS_COUNT,
			state.board_impact_sum(),
		],
	])
	if state.carried_object_id >= 0:
		parts.append("Carrying object: “%s”" % state.carried_phrase())
	parts.append(state.shadow_pile_hint())
	_stats.text = "\n".join(parts)
	if state.pressure_pending:
		_pressure_label.text = "Pressure: remove cards until total impact is below 7. Selected: %d card(s)." % _pressure_selected.size()
	else:
		_pressure_label.text = ""


func _short_phrase(s: String) -> String:
	if s.length() <= 40:
		return s
	return s.substr(0, 37) + "…"


func _log_append(bb: String) -> void:
	_log.append_text(bb + "\n")
