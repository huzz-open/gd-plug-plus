@tool
extends Control

signal updated()

enum VERSION_STATE {
	UNKNOWN, CHECKING, UP_TO_DATE, BEHIND, UPDATING, UPDATED
}

enum TREE_MODE { AVAILABLE, SEARCHING, SEARCHED }

const PLUG_GD_PATH = "res://plug.gd"
const PLUG_BASE_PATH = "res://addons/gd-plug-plus/plug.gd"
const ADDON_INDEX_PATH = "res://addons/gd-plug-plus/addon_index.json"
const COLOR_UNKNOWN = PlugUIConstants.COLOR_UNKNOWN
const COLOR_CHECKING = PlugUIConstants.COLOR_CHECKING
const COLOR_UP_TO_DATE = PlugUIConstants.COLOR_UP_TO_DATE
const COLOR_BEHIND = PlugUIConstants.COLOR_BEHIND
const COLOR_UPDATING = PlugUIConstants.COLOR_UPDATING
const COLOR_UPDATED = PlugUIConstants.COLOR_UPDATED
const COLOR_ACTION = PlugUIConstants.COLOR_ACTION
const COLOR_COMMIT = PlugUIConstants.COLOR_COMMIT
const COLOR_URL = PlugUIConstants.COLOR_URL
const COLOR_CONFLICT = PlugUIConstants.COLOR_CONFLICT

const SELF_REPO_NAME = "huzz-open/gd-plug-plus"
const SELF_REPO_URL = "https://github.com/huzz-open/gd-plug-plus"
const SELF_ADDON_DIR = "addons/gd-plug-plus"

@onready var tab_container: TabContainer = $TabContainer
@onready var installed_tree: Tree = %InstalledTree
@onready var search_input: LineEdit = %SearchInput
@onready var check_version_btn: Button = %CheckVersionBtn
@onready var update_all_btn: Button = %UpdateAllBtn
@onready var loading_overlay: PanelContainer = %LoadingOverlay
@onready var loading_label: Label = %LoadingLabel
@onready var cancel_update_btn: Button = %CancelUpdateBtn
var loading_spinner: TextureRect
@onready var search_result_panel: VBoxContainer = %SearchResultPanel
@onready var search_status_label: Label = %SearchStatusLabel
@onready var search_tree: Tree = %SearchTree
@onready var install_selected_btn: Button = %InstallSelectedBtn

var addon_data: AddonData = AddonData.new()

var _is_executing: bool = false
var _version_info_task_id: int = -1
var _addon_index: Array = []
var _version_cache: Dictionary = {}
var _version_state: Dictionary = {}
var _installing_repos: Dictionary = {}
var _local_info_task_id: int = -1
var _local_info_done: bool = false
var _local_info_active: bool = false
var _search_task_id: int = -1
var _search_done: bool = false
var _search_active: bool = false
var _search_result: Dictionary = {}
var _search_url: String = ""
var _search_branches: PackedStringArray = []
var _search_tags: PackedStringArray = []
var _search_default_branch: String = ""
var _search_head_commit: String = ""
var _search_cancelled: bool = false
var _install_task_id: int = -1
var _install_done: bool = false
var _install_active: bool = false
var _update_task_id: int = -1
var _update_done: bool = false
var _update_active: bool = false
var _version_info_task_id_active: bool = false
var _version_info_done: bool = false
var _tree_mode: int = TREE_MODE.AVAILABLE
var _search_btn: Button
var _search_ref_commits: Dictionary = {}
var _search_overlay: CenterContainer
var _search_spinner: TextureRect
var _search_overlay_label: Label
var _console_collapsed: bool = true
var _console_panel: PanelContainer
var _console_toggle_btn: Button
var _console_log: RichTextLabel
var _console_clear_btn: Button
var _last_log_count: int = 0

var _installed_filter_input: LineEdit

var _selector_popup: SelectorPopup
var _selector_target_item: TreeItem
var _selector_context: String = ""
var _selector_repo_name: String = ""

var _popup_loading: bool = false
var _popup_task_id: int = -1
var _popup_done: bool = false
var _popup_active: bool = false
var _popup_result: Dictionary = {}

var _remote_ref_cache: Dictionary = {}
var _commit_cache: Dictionary = {}
var _pending_changes: Dictionary = {}
var _is_version_switch: bool = false
var _update_cancelled: bool = false

var _console_header_height: int = PlugUIConstants.CONSOLE_HEADER_HEIGHT
var _console_expanded_height: int = PlugUIConstants.CONSOLE_EXPANDED_HEIGHT


# ===========================================================================
# Shared helpers (used by both tabs)
# ===========================================================================

static func _get_editor_scale() -> float:
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_scale()
	return 1.0


static func _scaled(value: float) -> int:
	return int(value * _get_editor_scale())


static func _tr(key: String) -> String:
	return TranslationServer.get_or_add_domain("gd-plug-plus").translate(key)


static func _short_commit(hash: String) -> String:
	return hash.left(PlugUIConstants.SHORT_COMMIT_LENGTH) if hash.length() > PlugUIConstants.SHORT_COMMIT_LENGTH else hash


static func _format_branch_tag(branch: String, tag: String) -> String:
	if not tag.is_empty():
		return tag + " [tag]"
	if not branch.is_empty():
		return branch
	return "--"


func _build_branch_tag_groups(branches: PackedStringArray, tags: PackedStringArray) -> Array:
	var groups: Array = []
	if not branches.is_empty():
		var items: Array = []
		for b in branches:
			items.append({"columns": [b], "meta": {"type": "branch", "name": b}})
		groups.append({"header": tr("BRANCH_HEADER") % branches.size(), "items": items})
	if not tags.is_empty():
		var items: Array = []
		for t in tags:
			items.append({"columns": [t], "meta": {"type": "tag", "name": t}})
		groups.append({"header": tr("TAG_HEADER") % tags.size(), "items": items})
	return groups


func _build_commit_groups(commits: Array) -> Array:
	var groups: Array = []
	var items: Array = []
	for c in commits:
		var hs = c.get("hash_short", _short_commit(c.get("hash", "")))
		items.append({
			"columns": [hs, c.get("message", "")],
			"meta": {"type": "commit", "hash": c.get("hash", ""), "hash_short": hs},
		})
	if not items.is_empty():
		groups.append({"header": "", "items": items})
	return groups


# ===========================================================================
# Lifecycle
# ===========================================================================

func _ready():
	PlugLogger.debug("AddonManager._ready() start")
	PlugLogger.info(_tr("LOG_PLUGGED_DIR") % GitManager.get_plugged_dir())
	_console_header_height = _scaled(PlugUIConstants.CONSOLE_HEADER_HEIGHT)
	_console_expanded_height = _scaled(PlugUIConstants.CONSOLE_EXPANDED_HEIGHT)
	loading_spinner = loading_overlay.get_node("CenterContainer/VBoxContainer/HBoxContainer/TextureRect")
	_load_addon_index()
	_init_data()

	var bottom_panel: MarginContainer = $"TabContainer/Installed/BottomPanel"
	bottom_panel.add_theme_constant_override("margin_left", _scaled(PlugUIConstants.MARGIN_STANDARD))
	bottom_panel.add_theme_constant_override("margin_top", _scaled(PlugUIConstants.MARGIN_COMPACT))
	bottom_panel.add_theme_constant_override("margin_right", _scaled(PlugUIConstants.MARGIN_STANDARD))
	bottom_panel.add_theme_constant_override("margin_bottom", _scaled(PlugUIConstants.MARGIN_COMPACT))
	var bottom_hbox: HBoxContainer = bottom_panel.get_node("HBoxContainer")
	bottom_hbox.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_STANDARD))
	var search_bar: MarginContainer = $"TabContainer/InstallNew/SearchBar"
	search_bar.add_theme_constant_override("margin_left", _scaled(PlugUIConstants.MARGIN_STANDARD))
	search_bar.add_theme_constant_override("margin_top", _scaled(PlugUIConstants.MARGIN_STANDARD))
	search_bar.add_theme_constant_override("margin_right", _scaled(PlugUIConstants.MARGIN_STANDARD))
	search_tree.custom_minimum_size = Vector2(0, _scaled(PlugUIConstants.SEARCH_TREE_MIN_HEIGHT))
	var overlay_vbox: VBoxContainer = loading_overlay.get_node("CenterContainer/VBoxContainer")
	overlay_vbox.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_LARGE))

	installed_tree.columns = PlugUIConstants.INSTALLED_COL_WIDTHS.size()
	installed_tree.column_titles_visible = true
	installed_tree.hide_root = true
	for ci in range(installed_tree.columns):
		installed_tree.set_column_expand(ci, PlugUIConstants.INSTALLED_COL_EXPAND[ci])
		installed_tree.set_column_custom_minimum_width(ci, _scaled(PlugUIConstants.INSTALLED_COL_WIDTHS[ci]))
	for ci in range(installed_tree.columns):
		installed_tree.set_column_clip_content(ci, true)
	installed_tree.item_mouse_selected.connect(_on_installed_tree_mouse_selected)

	search_result_panel.visible = true
	search_status_label.visible = false
	install_selected_btn.disabled = true

	search_tree.columns = PlugUIConstants.SEARCH_COL_WIDTHS.size()
	search_tree.column_titles_visible = true
	search_tree.hide_root = true
	for ci in range(search_tree.columns):
		search_tree.set_column_expand(ci, PlugUIConstants.SEARCH_COL_EXPAND[ci])
		search_tree.set_column_custom_minimum_width(ci, _scaled(PlugUIConstants.SEARCH_COL_WIDTHS[ci]))
	for ci in range(search_tree.columns):
		search_tree.set_column_clip_content(ci, true)
	search_tree.item_edited.connect(_on_search_tree_item_edited)
	search_tree.item_mouse_selected.connect(_on_search_tree_mouse_selected)

	_setup_search_bar()
	_setup_installed_filter()
	_setup_search_overlay()
	_setup_console()
	_apply_translations()

	_refresh_installed_tree()
	_refresh_unified_tree()
	connect("visibility_changed", _on_visibility_changed)
	tab_container.tab_changed.connect(_on_tab_changed)
	_local_info_done = false
	_local_info_active = true
	_local_info_task_id = WorkerThreadPool.add_task(_load_local_version_info)


func _init_data():
	var err = addon_data.load_data()
	if err == ERR_FILE_NOT_FOUND:
		_try_migrate_legacy()
	_ensure_self_tracked()
	check_version_btn.show()
	update_all_btn.show()
	addon_data.check_consistency()


func _ensure_self_tracked():
	if addon_data.has_repo(SELF_REPO_NAME):
		return
	var cfg = ConfigFile.new()
	if cfg.load("res://addons/gd-plug-plus/plugin.cfg") != OK:
		return
	var pname = cfg.get_value("plugin", "name", "gd-plug-plus")
	var pdesc = cfg.get_value("plugin", "description", "")
	var pver = cfg.get_value("plugin", "version", "")
	var pauthor = cfg.get_value("plugin", "author", "")
	var found_addons: Array = [{
		"name": pname,
		"description": pdesc,
		"type": "plugin",
		"addon_dir": SELF_ADDON_DIR,
		"version": pver,
		"author": pauthor,
	}]
	addon_data.add_repo_from_search(SELF_REPO_NAME, SELF_REPO_URL, found_addons, "main")
	addon_data.set_addon_installed(SELF_REPO_NAME, SELF_ADDON_DIR, true)
	addon_data.save_data()
	PlugLogger.info("Self-tracked gd-plug-plus in addons.json")


func _try_migrate_legacy():
	if not FileAccess.file_exists(PLUG_GD_PATH) and not FileAccess.file_exists(PLUG_BASE_PATH):
		return
	var base_path = PLUG_GD_PATH if FileAccess.file_exists(PLUG_GD_PATH) else PLUG_BASE_PATH
	var gd_plug_script = load(base_path)
	if gd_plug_script == null:
		return
	var gd_plug = gd_plug_script.new()
	gd_plug._plug_start()
	if FileAccess.file_exists(PLUG_GD_PATH):
		gd_plug._plugging()
	var plugged = gd_plug._plugged_plugins if gd_plug._plugged_plugins else {}
	var installed = gd_plug.installation_config.get_value("plugin", "installed", {})
	gd_plug.free()
	if plugged.is_empty() and installed.is_empty():
		return
	addon_data.migrate_from_legacy(plugged, installed)
	addon_data.save_data()


func _process(_delta):
	if _search_overlay != null and _search_overlay.visible and _search_spinner != null:
		_search_spinner.pivot_offset = _search_spinner.size * 0.5
		_search_spinner.rotation += _delta * TAU * PlugUIConstants.SPINNER_SPEED
	if loading_overlay.visible and loading_spinner != null:
		loading_spinner.pivot_offset = loading_spinner.size * 0.5
		loading_spinner.rotation += _delta * TAU * PlugUIConstants.SPINNER_SPEED
	_update_console()
	if _local_info_done:
		_local_info_done = false
		if _local_info_active:
			WorkerThreadPool.wait_for_task_completion(_local_info_task_id)
			_local_info_task_id = -1
			_local_info_active = false
		_refresh_installed_tree()
	if _search_done:
		_search_done = false
		PlugLogger.debug("search task completed, waiting for thread...")
		if _search_active:
			WorkerThreadPool.wait_for_task_completion(_search_task_id)
			_search_task_id = -1
			_search_active = false
		PlugLogger.debug("calling _on_search_completed")
		_on_search_completed()
	if _version_info_done:
		_version_info_done = false
		if _version_info_task_id_active:
			WorkerThreadPool.wait_for_task_completion(_version_info_task_id)
			_version_info_task_id = -1
			_version_info_task_id_active = false
		_refresh_installed_tree()
		show_overlay(false)
		disable_ui(false)
	if _install_done:
		_install_done = false
		if _install_active:
			WorkerThreadPool.wait_for_task_completion(_install_task_id)
			_install_task_id = -1
			_install_active = false
		_on_install_completed()
	if _update_done:
		_update_done = false
		if _update_active:
			WorkerThreadPool.wait_for_task_completion(_update_task_id)
			_update_task_id = -1
			_update_active = false
		_on_update_completed()
	if _popup_done:
		_popup_done = false
		if _popup_active:
			WorkerThreadPool.wait_for_task_completion(_popup_task_id)
			_popup_task_id = -1
			_popup_active = false
		_on_popup_data_loaded()


func _notification(what):
	match what:
		NOTIFICATION_PREDELETE:
			PlugLogger.debug("PREDELETE — node about to be destroyed")
			_wait_and_cleanup_tasks()
			PlugLogger.debug("PREDELETE — thread cleanup done")
			if is_instance_valid(_selector_popup):
				_selector_popup.queue_free()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if not _is_executing:
				addon_data.load_data()
				_refresh_installed_tree()
		NOTIFICATION_TRANSLATION_CHANGED:
			if is_node_ready():
				_apply_translations()
				_refresh_installed_tree()
				if _tree_mode == TREE_MODE.SEARCHED:
					_update_search_tree_install_status()
					_update_install_selected_count()
				else:
					_refresh_unified_tree(search_input.text if search_input else "")


func _wait_and_cleanup_tasks():
	PlugLogger.debug("request_cancel + waiting for all threads...")
	GitManager.request_cancel()
	var names = ["search", "local_info", "version_info", "install", "update", "popup"]
	var ids = [_search_task_id, _local_info_task_id, _version_info_task_id, _install_task_id, _update_task_id, _popup_task_id]
	var actives = [_search_active, _local_info_active, _version_info_task_id_active, _install_active, _update_active, _popup_active]
	for i in range(ids.size()):
		if actives[i] and ids[i] >= 0:
			PlugLogger.debug("waiting for %s (tid=%d)..." % [names[i], ids[i]])
			WorkerThreadPool.wait_for_task_completion(ids[i])
			PlugLogger.debug("%s completed" % names[i])
	_search_task_id = -1; _search_done = false; _search_active = false
	_local_info_task_id = -1; _local_info_done = false; _local_info_active = false
	_version_info_task_id = -1; _version_info_done = false; _version_info_task_id_active = false
	_install_task_id = -1; _install_done = false; _install_active = false
	_update_task_id = -1; _update_done = false; _update_active = false
	_popup_task_id = -1; _popup_done = false; _popup_active = false
	GitManager.reset_cancel()
	PlugLogger.debug("all threads cleaned up")


# ===========================================================================
# i18n
# ===========================================================================

func _apply_translations():
	if not is_node_ready():
		return
	tab_container.set_tab_title(0, tr("TAB_INSTALLED"))
	tab_container.set_tab_title(1, tr("TAB_INSTALL_NEW"))
	check_version_btn.text = tr("BTN_CHECK_UPDATE")
	update_all_btn.text = tr("BTN_UPDATE_ALL")

	installed_tree.set_column_title(0, tr("COL_NAME"))
	installed_tree.set_column_title(1, tr("COL_DESCRIPTION"))
	installed_tree.set_column_title(2, tr("COL_VERSION"))
	installed_tree.set_column_title(3, tr("COL_BRANCH_TAG"))
	installed_tree.set_column_title(4, tr("COL_COMMIT"))
	installed_tree.set_column_title(5, tr("COL_UPDATE_TIME"))
	installed_tree.set_column_title(6, tr("COL_ACTIONS"))
	installed_tree.set_column_title(7, "")
	installed_tree.set_column_title(8, "")
	installed_tree.set_column_title(9, "")

	search_tree.set_column_title(1, tr("COL_STATUS"))
	search_tree.set_column_title(2, tr("COL_NAME"))
	search_tree.set_column_title(3, tr("COL_VERSION"))
	search_tree.set_column_title(4, tr("COL_TYPE"))
	search_tree.set_column_title(5, tr("COL_BRANCH_TAG"))
	search_tree.set_column_title(6, tr("COL_COMMIT"))
	search_tree.set_column_title(7, tr("COL_REPO_PATH"))
	search_tree.set_column_title(8, tr("COL_AUTHOR"))

	if _search_btn:
		_search_btn.text = tr("BTN_SEARCH")
	if search_input:
		search_input.placeholder_text = tr("SEARCH_PLACEHOLDER")
	if _search_overlay_label:
		_search_overlay_label.text = tr("SEARCHING")
	if _console_toggle_btn:
		_console_toggle_btn.text = tr("CONSOLE_COLLAPSED") if _console_collapsed else tr("CONSOLE_EXPANDED")
	if _console_clear_btn:
		_console_clear_btn.text = tr("CONSOLE_CLEAR")
	if _installed_filter_input:
		_installed_filter_input.placeholder_text = tr("INSTALLED_FILTER_PLACEHOLDER")


# ===========================================================================
# Plugin Index
# ===========================================================================

func _load_addon_index():
	_addon_index.clear()
	if not FileAccess.file_exists(ADDON_INDEX_PATH):
		return
	var file = FileAccess.open(ADDON_INDEX_PATH, FileAccess.READ)
	if file == null:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.data
		if data is Array:
			_addon_index = data
	file.close()


func _get_index_description(repo_url: String) -> String:
	var repo_name = GitManager.repo_name_from_url(repo_url)
	for entry in _addon_index:
		if not entry is Dictionary:
			continue
		var entry_repo = GitManager.repo_name_from_url(entry.get("url", ""))
		if entry_repo == repo_name:
			var addons_arr: Array = entry.get("addons", [])
			if addons_arr.size() > 0 and addons_arr[0] is Dictionary:
				return addons_arr[0].get("description", "")
	return ""


func _refresh_unified_tree(filter_text: String = ""):
	if not is_node_ready():
		return
	if _tree_mode != TREE_MODE.AVAILABLE:
		return
	search_tree.clear()
	search_tree.create_item()
	install_selected_btn.disabled = true
	var _btn_tpl = tr("BTN_INSTALL_SELECTED")
	install_selected_btn.text = _btn_tpl % 0 if "%d" in _btn_tpl else _btn_tpl
	var filter_lower = filter_text.to_lower()
	var existing_addons = _get_existing_addons()

	for entry in _addon_index:
		if not entry is Dictionary:
			continue
		var url: String = entry.get("url", "")
		if url.is_empty():
			continue
		var addons_arr: Array = entry.get("addons", [])
		if addons_arr.is_empty():
			continue

		var repo_name = GitManager.repo_name_from_url(url)
		var already_installed = addon_data.has_repo(repo_name)

		for addon in addons_arr:
			if not addon is Dictionary:
				continue
			var pname: String = addon.get("name", "")
			var desc: String = addon.get("description", "")
			var addon_dir: String = addon.get("addon_dir", "")
			var author: String = addon.get("author", "")
			var branch: String = addon.get("branch", "main")
			var type_raw: String = addon.get("type", "plugin")
			if pname.is_empty():
				continue

			if not filter_lower.is_empty():
				var match_text = (pname + " " + desc + " " + author + " " + url).to_lower()
				if filter_lower not in match_text:
					continue

			var has_conflict := false
			if not addon_dir.is_empty() and not already_installed:
				has_conflict = not addon_data.check_dir_conflicts([addon_dir], existing_addons).is_empty()

			var item = search_tree.create_item(search_tree.get_root())

			item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			item.set_checked(0, false)
			item.set_editable(0, not already_installed)

			if already_installed:
				item.set_text(1, tr("STATUS_INSTALLED"))
				item.set_custom_color(1, COLOR_UP_TO_DATE)
			else:
				item.set_text(1, tr("STATUS_NOT_INSTALLED"))
				item.set_custom_color(1, COLOR_UNKNOWN)
			item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)

			item.set_text(2, pname)
			if has_conflict and not already_installed:
				item.set_custom_color(2, COLOR_CONFLICT)
				item.set_tooltip_text(2, url + "\n" + tr("CONFLICT_DIR_EXISTS") % addon_dir)
			else:
				item.set_tooltip_text(2, url)

			item.set_text(3, "-")
			item.set_text_alignment(3, HORIZONTAL_ALIGNMENT_CENTER)

			var type_text = "Plugin" if type_raw in ["editor_plugin", "plugin"] else "Extension"
			item.set_text(4, type_text)

			item.set_text(5, branch)
			item.set_custom_color(5, COLOR_UPDATED)
			item.set_text_alignment(5, HORIZONTAL_ALIGNMENT_CENTER)
			item.set_tooltip_text(5, tr("BRANCH_CLICK_HINT"))

			item.set_text(6, "-")
			item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)

			item.set_text(7, addon_dir)
			item.set_text(8, author)

			item.set_meta("addon_info", addon)
			item.set_meta("repo", url)
			item.set_meta("is_available", true)
			item.set_meta("selected_branch", branch)
			item.set_meta("selected_tag", "")
			item.set_meta("selected_commit", "")
			item.set_meta("has_conflict", has_conflict)

	_update_install_selected_count()


# ===========================================================================
# Installed tree rendering
# ===========================================================================

func _get_installed_filter_text() -> String:
	if _installed_filter_input and is_instance_valid(_installed_filter_input):
		return _installed_filter_input.text
	return ""


func _refresh_installed_tree(filter_text: String = ""):
	if not is_node_ready():
		return
	if filter_text.is_empty():
		filter_text = _get_installed_filter_text()
	installed_tree.clear()
	installed_tree.create_item()

	var repos = addon_data.get_all_repos_for_ui()
	var filter_lower = filter_text.to_lower()

	for repo_entry in repos:
		var repo_name: String = repo_entry["repo_name"]
		var url: String = repo_entry["url"]
		var addons: Array = repo_entry["addons"]
		var is_multi = addons.size() > 1

		if not filter_lower.is_empty():
			var match_text = (repo_name + " " + url).to_lower()
			var any_addon_match = false
			for a in addons:
				if filter_lower in (a.get("name", "") + " " + a.get("description", "")).to_lower():
					any_addon_match = true
					break
			if filter_lower not in match_text and not any_addon_match:
				continue

		var first_addon = _first_installed_or_first(addons)
		var child = installed_tree.create_item(installed_tree.get_root())
		var is_locked = addon_data.is_repo_locked(repo_name)
		var has_pending = _pending_changes.has(repo_name)
		var pending = _pending_changes.get(repo_name, {}) as Dictionary
		var vstate = _version_state.get(repo_name, VERSION_STATE.UNKNOWN)

		var plugin_name = first_addon.get("name", "")
		var display_name = plugin_name if not plugin_name.is_empty() else repo_name
		if is_multi:
			display_name = tr("MULTI_ADDONS_COUNT") % [display_name, addons.size()]
		child.set_text(0, display_name)
		child.set_tooltip_text(0, url)

		var desc_text = first_addon.get("description", "")
		if desc_text.is_empty():
			desc_text = _get_index_description(url)
		child.set_text(1, desc_text)
		child.set_custom_color(1, COLOR_URL)

		var ver = first_addon.get("version", "")
		child.set_text(2, ("v" + ver) if not ver.is_empty() else "")
		child.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)

		# Col 3: branch/tag
		var bt_text: String
		var bt_color: Color
		var cur_branch = first_addon.get("branch", "")
		var cur_tag = first_addon.get("tag", "")
		if has_pending:
			var p_tag = pending.get("tag", "") if pending.has("tag") else cur_tag
			var p_branch = pending.get("branch", "") if pending.has("branch") else cur_branch
			if pending.has("tag"):
				p_branch = ""
			elif pending.has("branch"):
				p_tag = ""
			bt_text = _format_branch_tag(p_branch, p_tag)
			var bt_changed = (p_branch != cur_branch) or (p_tag != cur_tag)
			bt_color = COLOR_CHECKING if bt_changed else COLOR_UPDATED
		else:
			bt_text = _format_branch_tag(cur_branch, cur_tag)
			bt_color = COLOR_UPDATED if not is_locked else COLOR_UNKNOWN
		child.set_text(3, bt_text)
		child.set_custom_color(3, bt_color)
		child.set_text_alignment(3, HORIZONTAL_ALIGNMENT_CENTER)

		# Col 4: commit
		var cached = _version_cache.get(repo_name, {})
		var commit_text = ""
		var commit_color: Color
		if has_pending and not pending.get("commit_preview", "").is_empty():
			commit_text = pending["commit_preview"]
			commit_color = COLOR_CHECKING
		elif repo_name in _installing_repos:
			commit_text = "..."
			commit_color = COLOR_UPDATED
		else:
			if cached.has("current_commit") and not cached["current_commit"].is_empty():
				commit_text = _short_commit(cached["current_commit"])
			elif not first_addon.is_empty():
				commit_text = _short_commit(first_addon.get("commit", ""))
			commit_color = _commit_color(vstate != VERSION_STATE.BEHIND)
			if is_locked and not has_pending and vstate != VERSION_STATE.BEHIND:
				commit_color = COLOR_UNKNOWN
		child.set_text(4, commit_text)
		child.set_custom_color(4, commit_color)
		child.set_text_alignment(4, HORIZONTAL_ALIGNMENT_CENTER)

		child.set_text(5, cached.get("commit_date", ""))

		# Col 6: detail
		child.set_text(6, tr("ACTION_DETAIL"))
		child.set_custom_color(6, COLOR_ACTION)
		child.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)

		# Col 7: lock/unlock
		if is_locked:
			child.set_text(7, tr("BTN_UNLOCK"))
			child.set_custom_color(7, COLOR_CHECKING)
		else:
			child.set_text(7, tr("BTN_LOCK"))
			child.set_custom_color(7, COLOR_ACTION)
		child.set_text_alignment(7, HORIZONTAL_ALIGNMENT_CENTER)

		# Col 8: update/apply/locked
		if is_locked:
			child.set_text(8, tr("STATUS_LOCKED"))
			child.set_custom_color(8, COLOR_UNKNOWN)
		elif has_pending:
			child.set_text(8, tr("BTN_APPLY"))
			child.set_custom_color(8, COLOR_BEHIND)
		else:
			var action_text = _get_update_action_text(repo_name, first_addon)
			var action_color = _get_update_action_color(repo_name, first_addon)
			child.set_text(8, action_text)
			child.set_custom_color(8, action_color)
		child.set_text_alignment(8, HORIZONTAL_ALIGNMENT_CENTER)

		# Col 9: uninstall (self plugin excluded)
		if repo_name != SELF_REPO_NAME:
			child.set_text(9, tr("ACTION_UNINSTALL"))
			child.set_custom_color(9, COLOR_ACTION)
			child.set_text_alignment(9, HORIZONTAL_ALIGNMENT_CENTER)

		child.set_meta("repo_name", repo_name)

		if is_multi:
			child.set_collapsed(true)
			for sp in addons:
				var sub_item = installed_tree.create_item(child)
				sub_item.set_text(0, sp.get("name", ""))
				sub_item.set_custom_color(0, COLOR_URL if sp.get("installed", false) else COLOR_UNKNOWN)
				sub_item.set_text(1, sp.get("description", ""))
				sub_item.set_custom_color(1, COLOR_URL)
				var sp_ver = sp.get("version", "")
				sub_item.set_text(2, ("v" + sp_ver) if not sp_ver.is_empty() else "")
				sub_item.set_text(5, tr("SUB_INSTALLED") if sp.get("installed", false) else tr("SUB_NOT_INSTALLED"))
				sub_item.set_custom_color(5, COLOR_UP_TO_DATE if sp.get("installed", false) else COLOR_UNKNOWN)
				sub_item.set_text(6, tr("ACTION_DETAIL"))
				sub_item.set_custom_color(6, COLOR_ACTION)
				sub_item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)
				sub_item.set_meta("repo_name", repo_name)
				sub_item.set_meta("addon_dir", sp.get("addon_dir", ""))
				for sci in [3, 4, 7, 8, 9]:
					sub_item.set_selectable(sci, false)


func _first_installed_or_first(addons: Array) -> Dictionary:
	for p in addons:
		if p.get("installed", false):
			return p
	return addons[0] if addons.size() > 0 else {}


# ===========================================================================
# Display helpers
# ===========================================================================

## Commit color: latest=blue, behind=red, unknown=gray.
## Both Installed and Search tabs use this for consistency.
static func _commit_color(is_latest: bool) -> Color:
	return COLOR_UPDATED if is_latest else COLOR_BEHIND


func _get_update_action_text(repo_name: String, addon: Dictionary) -> String:
	if repo_name in _installing_repos:
		return tr("STATUS_INSTALLING")
	var vstate = _version_state.get(repo_name, VERSION_STATE.UNKNOWN)
	match vstate:
		VERSION_STATE.CHECKING:
			return tr("STATUS_CHECKING")
		VERSION_STATE.UPDATING:
			return tr("STATUS_UPDATING")
		VERSION_STATE.UP_TO_DATE, VERSION_STATE.UPDATED:
			return tr("STATUS_LATEST")
		VERSION_STATE.BEHIND:
			return tr("STATUS_UPDATE")
	if not AddonData.is_updatable(addon):
		return tr("STATUS_LOCKED")
	return tr("STATUS_UPDATE")


func _get_update_action_color(repo_name: String, addon: Dictionary) -> Color:
	if repo_name in _installing_repos:
		return COLOR_CHECKING
	var vstate = _version_state.get(repo_name, VERSION_STATE.UNKNOWN)
	match vstate:
		VERSION_STATE.CHECKING, VERSION_STATE.UPDATING:
			return COLOR_CHECKING
		VERSION_STATE.UP_TO_DATE:
			return COLOR_UP_TO_DATE
		VERSION_STATE.UPDATED:
			return COLOR_UPDATED
		VERSION_STATE.BEHIND:
			return COLOR_BEHIND
	if not AddonData.is_updatable(addon):
		return COLOR_UNKNOWN
	return COLOR_ACTION


# ===========================================================================
# Version info
# ===========================================================================

func _fetch_all_version_info():
	for repo_name in addon_data.get_repos():
		_version_state[repo_name] = VERSION_STATE.CHECKING
	_refresh_installed_tree()
	show_overlay(true, tr("OVERLAY_CHECKING_VERSION"))
	disable_ui(true)
	_remote_ref_cache.clear()
	_commit_cache.clear()
	_version_info_done = false
	_version_info_task_id_active = true
	_version_info_task_id = WorkerThreadPool.add_task(_collect_version_info)


func _collect_version_info():
	for repo_name in addon_data.get_repos():
		var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
		if not DirAccess.dir_exists_absolute(plug_dir.path_join(".git")):
			if not _ensure_repo_cloned(repo_name):
				_version_state[repo_name] = VERSION_STATE.UNKNOWN
				continue
		var info = GitManager.get_current_info(plug_dir)
		var result: Dictionary = {
			"current_branch": info.get("branch", ""),
			"current_commit": info.get("commit_short", ""),
			"current_tag": info.get("tag", ""),
			"commit_date": info.get("date", ""),
		}
		var plugins = addon_data.get_installed_addons(repo_name)
		var max_behind := 0
		for p in plugins:
			if not AddonData.is_updatable(p):
				continue
			var branch = p.get("branch", "")
			if branch.is_empty():
				branch = GitManager.get_remote_default_branch(plug_dir)
			var compare_result = GitManager.fetch_and_compare(plug_dir, branch)
			var behind = compare_result.get("behind", 0)
			if behind > max_behind:
				max_behind = behind
		result["behind"] = max_behind
		_version_cache[repo_name] = result
		_version_state[repo_name] = VERSION_STATE.BEHIND if max_behind > 0 else VERSION_STATE.UP_TO_DATE
	_version_info_done = true


func _load_local_version_info():
	for repo_name in addon_data.get_repos():
		if _version_cache.has(repo_name):
			continue
		var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
		var info = GitManager.get_current_info(plug_dir)
		if info.get("commit_short", "").is_empty():
			continue
		var branch: String = info.get("branch", "")
		var behind := GitManager.local_behind_count(plug_dir, branch)
		_version_cache[repo_name] = {
			"current_branch": branch,
			"current_commit": info.get("commit_short", ""),
			"current_tag": info.get("tag", ""),
			"commit_date": info.get("date", ""),
			"behind": behind,
		}
		if not _version_state.has(repo_name) or _version_state[repo_name] == VERSION_STATE.UNKNOWN:
			_version_state[repo_name] = VERSION_STATE.BEHIND if behind > 0 else VERSION_STATE.UP_TO_DATE
	_local_info_done = true


# ===========================================================================
# UI helpers
# ===========================================================================

func disable_ui(disabled: bool = true):
	check_version_btn.disabled = disabled
	update_all_btn.disabled = disabled
	if _search_btn:
		_search_btn.disabled = disabled


func show_overlay(show: bool = true, text: String = ""):
	loading_overlay.visible = show
	loading_label.text = text
	if cancel_update_btn:
		cancel_update_btn.visible = show
		cancel_update_btn.disabled = false
		cancel_update_btn.text = tr("BTN_CANCEL")


func _ensure_repo_cloned(repo_name: String, fallback_url: String = "") -> bool:
	var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
	if DirAccess.dir_exists_absolute(plug_dir.path_join(".git")):
		return true
	var url: String = fallback_url
	if url.is_empty():
		var repo = addon_data.get_repo(repo_name)
		url = repo.get("url", "")
	if url.is_empty():
		return false
	if DirAccess.dir_exists_absolute(plug_dir):
		GitManager.delete_directory(plug_dir)
	var exit = GitManager.shallow_clone(url, plug_dir)
	return exit == OK


# ===========================================================================
# Search flow
# ===========================================================================

func _on_SearchUrlBtn_pressed():
	var url = search_input.text.strip_edges()
	PlugLogger.debug("search button pressed, raw input='%s'" % url)
	if url.is_empty():
		return
	if not url.begins_with("http://") and not url.begins_with("https://") and not url.begins_with("git@"):
		if "/" in url:
			url = "https://github.com/" + url
			PlugLogger.debug("expanded to GitHub URL: %s" % url)
		else:
			return

	_start_search(url)


func _show_repo_exists_dialog(repo_name: String, url: String):
	var dialog = ConfirmationDialog.new()
	dialog.title = tr("TOAST_INFO")
	dialog.dialog_text = tr("TOAST_REPO_EXISTS") % repo_name
	dialog.ok_button_text = tr("BTN_VIEW_INSTALLED")
	dialog.get_cancel_button().text = tr("BTN_SEARCH_ANYWAY")
	dialog.confirmed.connect(func():
		_jump_to_installed_tab(repo_name)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		_start_search(url)
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()


func _jump_to_installed_tab(repo_name: String):
	tab_container.current_tab = 0
	if _installed_filter_input:
		_installed_filter_input.text = repo_name
	_refresh_installed_tree(repo_name)


func _start_search(url: String):
	_search_url = url
	_search_cancelled = false
	_search_head_commit = ""
	_tree_mode = TREE_MODE.SEARCHING
	search_tree.clear()
	search_tree.create_item()
	install_selected_btn.disabled = true
	_search_btn.text = tr("BTN_CANCEL")
	_search_overlay.visible = true
	PlugLogger.info(_tr("LOG_SEARCH_START") % url)
	_search_done = false
	_search_active = true
	_search_task_id = WorkerThreadPool.add_task(_run_search_task)


func _run_search_task():
	PlugLogger.debug("search thread started, url=%s" % _search_url)
	GitManager.reset_cancel()
	var url = _search_url
	var repo_name = GitManager.repo_name_from_url(url)
	var cache_dir = GitManager.get_plugged_dir().path_join(repo_name)
	var has_local = DirAccess.dir_exists_absolute(cache_dir.path_join(".git"))

	# 1) Local cache
	if has_local:
		PlugLogger.debug("local repo cache hit: %s" % cache_dir)
		var local_refs = GitManager.get_local_refs(cache_dir)
		_search_branches = local_refs.get("branches", PackedStringArray())
		_search_tags = local_refs.get("tags", PackedStringArray())
		_search_default_branch = local_refs.get("default_branch", "main")
		_search_ref_commits = local_refs.get("ref_commits", {})
		var head_commit = GitManager.rev_parse_head(cache_dir)
		_search_head_commit = _short_commit(head_commit)
		_search_result = GitManager.scan_addons_in_dir(cache_dir)
		PlugLogger.info(_tr("LOG_SEARCH_DONE"))
		_search_done = true
		return

	# 2) addon_index.json lookup
	var index_match = _find_index_entry(url)
	if not index_match.is_empty():
		PlugLogger.debug("addon_index hit for: %s" % url)
		var addons_arr: Array = index_match.get("addons", [])
		var found: Array = []
		for a in addons_arr:
			if not a is Dictionary:
				continue
			found.append({
				"name": a.get("name", ""),
				"description": a.get("description", ""),
				"addon_dir": a.get("addon_dir", ""),
				"author": a.get("author", ""),
				"type": a.get("type", "plugin"),
				"version": "",
			})
		var branch: String = ""
		if not addons_arr.is_empty() and addons_arr[0] is Dictionary:
			branch = addons_arr[0].get("branch", "main")
		if branch.is_empty():
			branch = "main"
		_search_branches = PackedStringArray([branch])
		_search_tags = PackedStringArray()
		_search_default_branch = branch
		_search_ref_commits = {}
		_search_head_commit = ""
		_search_result = {"addons": found, "warnings": []}
		PlugLogger.info(_tr("LOG_SEARCH_DONE"))
		_search_done = true
		return

	# 3) Remote clone
	var remote_info = GitManager.ls_remote(url)
	if remote_info.get("cancelled", false):
		PlugLogger.info(_tr("LOG_SEARCH_CANCELLED"))
		_search_done = true
		return
	if remote_info.has("error"):
		_search_result = {"error": remote_info["error"]}
		_search_done = true
		return
	_search_branches = remote_info.get("branches", PackedStringArray())
	_search_tags = remote_info.get("tags", PackedStringArray())
	_search_default_branch = remote_info.get("default_branch", "main")
	_search_ref_commits = remote_info.get("ref_commits", {})

	if _search_cancelled:
		_search_done = true
		return

	if DirAccess.dir_exists_absolute(cache_dir):
		GitManager.delete_directory(cache_dir)
	PlugLogger.debug("shallow_clone -> %s" % cache_dir)
	var clone_exit = GitManager.shallow_clone(url, cache_dir)
	if clone_exit == GitManager.ERR_CANCELLED:
		_search_done = true
		return
	if clone_exit != OK:
		var detail = GitManager.last_error
		if detail.is_empty():
			detail = tr("ERR_REMOTE_READ").replace("{SEP}", ",")
		_search_result = {"error": detail}
		_search_done = true
		return

	var head_commit = GitManager.rev_parse_head(cache_dir)
	_search_head_commit = _short_commit(head_commit)
	_search_result = GitManager.scan_addons_in_dir(cache_dir)
	PlugLogger.info(_tr("LOG_SEARCH_DONE"))
	_search_done = true


func _find_index_entry(search_url: String) -> Dictionary:
	var search_repo = GitManager.repo_name_from_url(search_url)
	for entry in _addon_index:
		if not entry is Dictionary:
			continue
		var entry_repo = GitManager.repo_name_from_url(entry.get("url", ""))
		if entry_repo == search_repo:
			return entry
	return {}


func _on_search_completed():
	_search_btn.disabled = false
	_search_btn.text = tr("BTN_SEARCH")
	_search_overlay.visible = false

	if _search_cancelled:
		_search_cancelled = false
		_tree_mode = TREE_MODE.AVAILABLE
		_refresh_unified_tree(search_input.text)
		return

	if _search_result.has("error"):
		_tree_mode = TREE_MODE.AVAILABLE
		_refresh_unified_tree(search_input.text)
		_show_toast(_search_result["error"], true)
		return

	_tree_mode = TREE_MODE.SEARCHED

	var _sr_name = GitManager.repo_name_from_url(_search_url)
	if not _search_branches.is_empty() or not _search_tags.is_empty():
		_remote_ref_cache[_sr_name] = {"branches": _search_branches, "tags": _search_tags, "ref_commits": _search_ref_commits}

	var found_addons: Array = _search_result.get("addons", [])
	var warnings: Array = _search_result.get("warnings", [])

	if found_addons.is_empty():
		var msg = tr("TOAST_NO_ADDON_FOUND")
		if not warnings.is_empty():
			msg += "\n" + "\n".join(warnings)
		_show_toast(msg, true)
		install_selected_btn.disabled = false
		install_selected_btn.text = tr("BTN_MANUAL_INSTALL")
		return

	var addon_dirs: Array = []
	for p in found_addons:
		addon_dirs.append(p.get("addon_dir", ""))
	var existing_addons = _get_existing_addons()
	var conflicts = addon_data.check_dir_conflicts(addon_dirs, existing_addons)

	var default_commit_raw = _search_ref_commits.get(_search_default_branch, _search_head_commit)
	var default_commit = _short_commit(default_commit_raw)
	var search_repo_name = GitManager.repo_name_from_url(_search_url)
	var already_installed = addon_data.has_repo(search_repo_name)

	search_tree.clear()
	search_tree.create_item()
	for p in found_addons:
		var item = search_tree.create_item(search_tree.get_root())
		var pdir = p.get("addon_dir", "")
		var has_conflict = pdir in conflicts

		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_checked(0, not has_conflict and not already_installed)
		item.set_editable(0, not already_installed)

		if already_installed:
			item.set_text(1, tr("STATUS_INSTALLED"))
			item.set_custom_color(1, COLOR_UP_TO_DATE)
		else:
			item.set_text(1, tr("STATUS_NOT_INSTALLED"))
			item.set_custom_color(1, COLOR_UNKNOWN)
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)

		var name_text = p.get("name", "Unknown")
		item.set_text(2, name_text)
		if has_conflict and not already_installed:
			item.set_custom_color(2, COLOR_CONFLICT)
			item.set_tooltip_text(2, _search_url + "\n" + tr("CONFLICT_DIR_EXISTS") % pdir)
		else:
			item.set_tooltip_text(2, _search_url)

		var ver = p.get("version", "")
		item.set_text(3, ("v" + ver) if not ver.is_empty() else "")

		var type_text = "Plugin" if p.get("type", "") in ["editor_plugin", "plugin"] else "Extension"
		item.set_text(4, type_text)

		# Col 5: branch/tag
		item.set_text(5, _search_default_branch)
		item.set_custom_color(5, COLOR_UPDATED)
		item.set_text_alignment(5, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_tooltip_text(5, tr("BRANCH_CLICK_HINT"))

		# Col 6: commit (initial = branch head = latest)
		item.set_text(6, default_commit)
		item.set_custom_color(6, _commit_color(true))
		item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)

		item.set_text(7, pdir)
		item.set_text(8, p.get("author", ""))

		item.set_meta("addon_info", p)
		item.set_meta("selected_branch", _search_default_branch)
		item.set_meta("selected_tag", "")
		item.set_meta("selected_commit", "")
		item.set_meta("has_conflict", has_conflict)

	_update_install_selected_count()


func _get_existing_addons() -> PackedStringArray:
	var result: PackedStringArray = []
	var addons_path = ProjectSettings.globalize_path("res://addons")
	if not DirAccess.dir_exists_absolute(addons_path):
		return result
	var dir = DirAccess.open(addons_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname = dir.get_next()
	while not fname.is_empty():
		if dir.current_is_dir():
			result.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return result


func _on_search_tree_item_edited():
	_update_install_selected_count()


func _update_install_selected_count():
	var count = 0
	var root = search_tree.get_root()
	if root:
		var child = root.get_first_child()
		while child:
			if child.is_checked(0):
				count += 1
			child = child.get_next()
	install_selected_btn.disabled = count == 0
	var _sel_tpl = tr("BTN_INSTALL_SELECTED")
	install_selected_btn.text = _sel_tpl % count if "%d" in _sel_tpl else _sel_tpl


# ===========================================================================
# Install flow
# ===========================================================================

func _on_InstallSelectedBtn_pressed():
	if _tree_mode == TREE_MODE.AVAILABLE:
		_install_from_available()
		return

	var found: Array = _search_result.get("addons", [])

	if found.is_empty():
		install_selected_btn.disabled = true
		install_selected_btn.text = tr("BTN_INSTALLING")
		_install_repo_manual(_search_url)
		return

	var selected: Array[Dictionary] = []
	var root = search_tree.get_root()
	if root:
		var child = root.get_first_child()
		while child:
			if child.is_checked(0):
				var info = child.get_meta("addon_info")
				if info:
					var entry = info.duplicate()
					entry["_branch"] = child.get_meta("selected_branch")
					entry["_tag"] = child.get_meta("selected_tag")
					entry["_commit"] = child.get_meta("selected_commit") if child.has_meta("selected_commit") else ""
					selected.append(entry)
			child = child.get_next()

	if selected.is_empty():
		return

	var selected_dirs: Array = []
	for s in selected:
		selected_dirs.append(s.get("addon_dir", ""))
	var fresh_conflicts = addon_data.check_dir_conflicts(selected_dirs, _get_existing_addons())

	var conflicts_in_selected: Array[Dictionary] = []
	for s in selected:
		if s.get("addon_dir", "") in fresh_conflicts:
			conflicts_in_selected.append(s)
	if not conflicts_in_selected.is_empty():
		_show_conflict_dialog(conflicts_in_selected, selected)
		return
	_execute_install(selected)


func _install_from_available():
	var by_url: Dictionary = {}
	var root = search_tree.get_root()
	if root:
		var child = root.get_first_child()
		while child:
			if child.is_checked(0) and child.has_meta("is_available"):
				var url: String = child.get_meta("repo", "")
				var info: Dictionary = child.get_meta("addon_info", {})
				if not url.is_empty() and not info.is_empty():
					var entry = info.duplicate()
					entry["_branch"] = child.get_meta("selected_branch", "main")
					entry["_tag"] = child.get_meta("selected_tag", "")
					entry["_commit"] = child.get_meta("selected_commit", "")
					if not by_url.has(url):
						by_url[url] = []
					by_url[url].append(entry)
			child = child.get_next()

	if by_url.is_empty():
		return

	var selected_dirs: Array = []
	for url in by_url:
		for s in by_url[url]:
			selected_dirs.append(s.get("addon_dir", ""))
	var fresh_conflicts = addon_data.check_dir_conflicts(selected_dirs, _get_existing_addons())
	var has_conflict := false
	for d in selected_dirs:
		if d in fresh_conflicts:
			has_conflict = true
			break
	if has_conflict:
		var all_selected: Array[Dictionary] = []
		for url in by_url:
			for s in by_url[url]:
				all_selected.append(s)
		var conflicts_in_selected: Array[Dictionary] = []
		for s in all_selected:
			if s.get("addon_dir", "") in fresh_conflicts:
				conflicts_in_selected.append(s)
		_show_conflict_dialog(conflicts_in_selected, all_selected)
		return

	install_selected_btn.disabled = true
	install_selected_btn.text = tr("BTN_INSTALLING")
	_is_executing = true
	disable_ui(true)
	_install_done = false
	_install_active = true
	_install_task_id = WorkerThreadPool.add_task(_run_available_install.bind(by_url))


func _run_available_install(by_url: Dictionary):
	var project_root = ProjectSettings.globalize_path("res://")
	for url in by_url:
		var repo_name = GitManager.repo_name_from_url(url)
		var addons_list: Array = by_url[url]
		var default_branch: String = addons_list[0].get("_branch", "main")

		for s in addons_list:
			var tag_val: String = s.get("_tag", "")
			var commit_val: String = s.get("_commit", "")
			var branch_val: String = s.get("_branch", s.get("branch", "main"))
			if not tag_val.is_empty():
				s["tag"] = tag_val
				s.erase("branch")
			elif not commit_val.is_empty():
				s["commit"] = commit_val
			elif not branch_val.is_empty():
				s["branch"] = branch_val

		addon_data.add_repo_from_search(repo_name, url, addons_list, default_branch)
		for s in addons_list:
			addon_data.set_addon_installed(repo_name, s.get("addon_dir", ""), true)
			var tag_val: String = s.get("_tag", "")
			var commit_val: String = s.get("_commit", "")
			var branch_val: String = s.get("_branch", "")
			if not commit_val.is_empty():
				addon_data.set_addon_commit_lock(repo_name, s.get("addon_dir", ""), commit_val)
			elif not tag_val.is_empty():
				addon_data.set_addon_tag(repo_name, s.get("addon_dir", ""), tag_val)
			elif not branch_val.is_empty():
				addon_data.set_addon_branch(repo_name, s.get("addon_dir", ""), branch_val)

		var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
		if not _ensure_repo_cloned(repo_name, url):
			continue

		var groups = AddonData.group_addons_by_version(addons_list)
		for ref in groups:
			if ref != "__default__":
				GitManager.fetch_ref(plug_dir, ref)
				GitManager.checkout(plug_dir, ref)
			var commit_hash = GitManager.rev_parse_head(plug_dir)
			for p in groups[ref]:
				var pdir: String = p.get("addon_dir", "")
				if pdir.is_empty():
					continue
				GitManager.copy_addon_dir(plug_dir, pdir, project_root)
				addon_data.set_addon_commit(repo_name, pdir, commit_hash)

		var scanned = GitManager.scan_local_addons(plug_dir)
		for sp in scanned:
			sp["type"] = AddonData._normalize_type(sp.get("type", ""))
		addon_data.merge_scan_results(repo_name, scanned)

	addon_data.save_data()
	_install_done = true


func _execute_install(selected: Array[Dictionary]):
	var url = _search_url
	var repo_name = GitManager.repo_name_from_url(url)
	var all_found = _search_result.get("addons", [])

	addon_data.add_repo_from_search(repo_name, url, all_found, _search_default_branch)

	var repos_to_cleanup: Dictionary = {}
	for s in selected:
		var pdir = s.get("addon_dir", "")
		var old_owner = addon_data.find_owner_repo(pdir)
		if not old_owner.is_empty() and old_owner != repo_name:
			addon_data.set_addon_installed(old_owner, pdir, false)
			repos_to_cleanup[old_owner] = true
		addon_data.set_addon_installed(repo_name, pdir, true)
		var commit_val: String = s.get("_commit", "")
		var tag_val: String = s.get("_tag", "")
		var branch_val: String = s.get("_branch", _search_default_branch)
		if not commit_val.is_empty():
			addon_data.set_addon_commit_lock(repo_name, pdir, commit_val)
		elif not tag_val.is_empty():
			addon_data.set_addon_tag(repo_name, pdir, tag_val)
		elif not branch_val.is_empty():
			addon_data.set_addon_branch(repo_name, pdir, branch_val)

	for old_repo in repos_to_cleanup:
		if addon_data.get_installed_addons(old_repo).is_empty():
			addon_data.remove_repo(old_repo)

	addon_data.save_data()
	_installing_repos[repo_name] = true
	_refresh_installed_tree()
	_set_checked_items_status(tr("STATUS_INSTALLING"), COLOR_CHECKING)
	install_selected_btn.disabled = true
	install_selected_btn.text = tr("BTN_INSTALLING")
	_is_executing = true
	disable_ui(true)
	PlugLogger.info(_tr("LOG_INSTALL_START") % repo_name)
	_install_done = false
	_install_active = true
	_install_task_id = WorkerThreadPool.add_task(_run_install.bind(repo_name))


func _install_repo_manual(url: String):
	var repo_name = GitManager.repo_name_from_url(url)
	addon_data.add_repo_from_search(repo_name, url, [], _search_default_branch)
	addon_data.save_data()
	_installing_repos[repo_name] = true
	_refresh_installed_tree()
	_is_executing = true
	disable_ui(true)
	_install_done = false
	_install_active = true
	_install_task_id = WorkerThreadPool.add_task(_run_install.bind(repo_name))


func _run_install(repo_name: String):
	var repo = addon_data.get_repo(repo_name)
	var url: String = repo.get("url", "")
	var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
	var project_root = ProjectSettings.globalize_path("res://")

	if not DirAccess.dir_exists_absolute(plug_dir.path_join(".git")):
		if DirAccess.dir_exists_absolute(plug_dir):
			GitManager.delete_directory(plug_dir)
		var exit = GitManager.shallow_clone(url, plug_dir)
		if exit != OK:
			_install_done = true
			return

	var installed_plugins = addon_data.get_installed_addons(repo_name)
	var groups = AddonData.group_addons_by_version(installed_plugins)

	for ref in groups:
		if ref != "__default__":
			GitManager.fetch_ref(plug_dir, ref)
			GitManager.checkout(plug_dir, ref)
		var commit_hash = GitManager.rev_parse_head(plug_dir)
		for p in groups[ref]:
			var pdir: String = p.get("addon_dir", "")
			if pdir.is_empty():
				continue
			GitManager.copy_addon_dir(plug_dir, pdir, project_root)
			addon_data.set_addon_commit(repo_name, pdir, commit_hash)

	addon_data.save_data()
	_install_done = true


func _on_install_completed():
	_installing_repos.clear()
	_is_executing = false
	disable_ui(false)
	_version_cache.clear()
	_remote_ref_cache.clear()
	_commit_cache.clear()
	_pending_changes.clear()
	_local_info_done = false
	_local_info_active = true
	_local_info_task_id = WorkerThreadPool.add_task(_load_local_version_info)
	_refresh_installed_tree()
	_update_search_tree_install_status()
	_set_checked_items_status(tr("STATUS_INSTALLED"), COLOR_UP_TO_DATE)
	install_selected_btn.text = tr("BTN_INSTALL_DONE")
	PlugLogger.info(_tr("LOG_INSTALL_DONE"))
	emit_signal("updated")


# ===========================================================================
# Conflict dialog
# ===========================================================================

func _show_conflict_dialog(conflicts: Array[Dictionary], all_selected: Array[Dictionary]):
	var dialog = ConfirmationDialog.new()
	dialog.title = tr("CONFLICT_TITLE")
	dialog.ok_button_text = tr("CONFLICT_OVERWRITE")
	dialog.get_cancel_button().text = tr("BTN_CANCEL")
	var vbox = VBoxContainer.new()
	for c in conflicts:
		var pdir = c.get("addon_dir", "")
		var owner = addon_data.find_owner_repo(pdir)
		var label = Label.new()
		if not owner.is_empty():
			label.text = tr("CONFLICT_DIR_OWNED") % [pdir, owner]
		else:
			label.text = tr("CONFLICT_DIR_EXISTS") % pdir
		label.add_theme_color_override("font_color", COLOR_CONFLICT)
		vbox.add_child(label)
	dialog.add_child(vbox)
	dialog.confirmed.connect(func():
		_execute_install(all_selected)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


# ===========================================================================
# Update operations
# ===========================================================================

func _on_CheckVersionBtn_pressed():
	_version_cache.clear()
	_version_state.clear()
	_remote_ref_cache.clear()
	_commit_cache.clear()
	_pending_changes.clear()
	_fetch_all_version_info()


func _on_UpdateAllBtn_pressed():
	var updatable_repos: Array[String] = []
	for repo_name in addon_data.get_repos():
		if addon_data.is_repo_locked(repo_name):
			continue
		var plugins = addon_data.get_installed_addons(repo_name)
		for p in plugins:
			if AddonData.is_updatable(p):
				updatable_repos.append(repo_name)
				break
	if updatable_repos.is_empty():
		return
	for rn in updatable_repos:
		_version_state[rn] = VERSION_STATE.UPDATING
	_refresh_installed_tree()
	show_overlay(true, tr("OVERLAY_UPDATING_ALL"))
	_is_executing = true
	disable_ui(true)
	_update_done = false
	_update_active = true
	_update_task_id = WorkerThreadPool.add_task(_run_update_repos.bind(updatable_repos))


func _update_single_repo(repo_name: String):
	if _is_executing:
		return
	_version_state[repo_name] = VERSION_STATE.UPDATING
	call_deferred("_refresh_installed_tree", "")
	show_overlay(true, tr("OVERLAY_UPDATING_ONE") % repo_name)
	_is_executing = true
	disable_ui(true)
	_update_done = false
	_update_active = true
	_update_task_id = WorkerThreadPool.add_task(_run_update_repos.bind([repo_name]))


func _run_update_repos(repo_names: Array):
	var project_root = ProjectSettings.globalize_path("res://")
	for repo_name in repo_names:
		var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
		if not DirAccess.dir_exists_absolute(plug_dir.path_join(".git")):
			continue
		var installed = addon_data.get_installed_addons(repo_name)
		var groups = AddonData.group_addons_by_version(installed)
		for ref in groups:
			var plugins_in_group = groups[ref]
			var first_p = plugins_in_group[0]
			if not AddonData.is_updatable(first_p):
				continue
			var branch = first_p.get("branch", "")
			if branch.is_empty():
				branch = GitManager.get_remote_default_branch(plug_dir)
			GitManager.git(plug_dir, ["fetch", "origin", branch])
			GitManager.checkout(plug_dir, branch)
			GitManager.pull_current(plug_dir)
			var commit_hash = GitManager.rev_parse_head(plug_dir)
			var scanned = GitManager.scan_local_addons(plug_dir)
			for sp in scanned:
				sp["type"] = AddonData._normalize_type(sp.get("type", ""))
			for p in plugins_in_group:
				var pdir = p.get("addon_dir", "")
				for sp in scanned:
					if sp.get("addon_dir", "") == pdir:
						addon_data.update_addon_metadata(repo_name, pdir, sp)
						break
				GitManager.copy_addon_dir(plug_dir, pdir, project_root)
				addon_data.set_addon_commit(repo_name, pdir, commit_hash)
	addon_data.save_data()
	_update_done = true


func _on_update_completed():
	_is_executing = false
	disable_ui(false)
	show_overlay(false)
	var was_cancelled = _update_cancelled
	_update_cancelled = false
	var keys_to_clear: Array = []
	for repo_name in _version_state:
		if _version_state[repo_name] == VERSION_STATE.UPDATING:
			keys_to_clear.append(repo_name)
	if was_cancelled or _is_version_switch:
		for rn in keys_to_clear:
			_version_state.erase(rn)
		_is_version_switch = false
		if was_cancelled:
			PlugLogger.info(_tr("LOG_UPDATE_CANCELLED"))
	else:
		for rn in keys_to_clear:
			_version_state[rn] = VERSION_STATE.UPDATED
	_version_cache.clear()
	_remote_ref_cache.clear()
	_commit_cache.clear()
	_pending_changes.clear()
	_local_info_done = false
	_local_info_active = true
	_local_info_task_id = WorkerThreadPool.add_task(_load_local_version_info)
	_refresh_installed_tree()
	if not was_cancelled:
		if SELF_REPO_NAME in keys_to_clear:
			_load_addon_index()
			if _tree_mode == TREE_MODE.AVAILABLE:
				_refresh_unified_tree()
			_show_toast(tr("TOAST_SELF_UPDATED"))
		emit_signal("updated")


func _on_CancelUpdateBtn_pressed():
	GitManager.request_cancel()
	show_overlay(false)
	if _is_executing:
		_update_cancelled = true
		PlugLogger.info(_tr("LOG_UPDATE_CANCELLED"))
	elif _version_info_task_id_active:
		var check_keys: Array = []
		for repo_name in _version_state:
			if _version_state[repo_name] == VERSION_STATE.CHECKING:
				check_keys.append(repo_name)
		for rn in check_keys:
			_version_state.erase(rn)
		disable_ui(false)
		_refresh_installed_tree()
		PlugLogger.info(_tr("LOG_CHECK_CANCELLED"))


# ===========================================================================
# Uninstall
# ===========================================================================

func _confirm_remove_repo(repo_name: String):
	if _is_executing:
		return
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = tr("UNINSTALL_CONFIRM") % repo_name
	confirm.ok_button_text = tr("BTN_CONFIRM")
	confirm.get_cancel_button().text = tr("BTN_CANCEL")
	confirm.confirmed.connect(func():
		_uninstall_repo(repo_name)
		confirm.queue_free()
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()


func _uninstall_repo(repo_name: String):
	var installed = addon_data.get_installed_addons(repo_name)
	for p in installed:
		var dest = p.get("addon_dir", "")
		GitManager.delete_installed_dir(dest)
	addon_data.remove_repo(repo_name)
	addon_data.save_data()
	_version_cache.erase(repo_name)
	_version_state.erase(repo_name)
	_remote_ref_cache.erase(repo_name)
	_pending_changes.erase(repo_name)
	_erase_commit_cache_for_repo(repo_name)
	_refresh_installed_tree()
	_update_search_tree_install_status()


# ===========================================================================
# Version switching
# ===========================================================================

func _switch_repo_version(repo_name: String, version_type: String, version_value: String, extra_commit: String = ""):
	if _is_executing:
		return
	_version_state[repo_name] = VERSION_STATE.UPDATING
	call_deferred("_refresh_installed_tree", "")
	show_overlay(true, tr("OVERLAY_SWITCHING") % [repo_name, version_type, version_value])
	_is_executing = true
	disable_ui(true)
	_update_done = false
	_update_active = true
	_update_task_id = WorkerThreadPool.add_task(func():
		var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
		var project_root = ProjectSettings.globalize_path("res://")
		if not DirAccess.dir_exists_absolute(plug_dir.path_join(".git")):
			_update_done = true
			return
		match version_type:
			"branch":
				GitManager.fetch_ref(plug_dir, version_value)
				GitManager.checkout(plug_dir, version_value)
				GitManager.pull_current(plug_dir)
				if not extra_commit.is_empty():
					GitManager.checkout(plug_dir, extra_commit)
			"tag":
				GitManager.fetch_ref(plug_dir, "tag " + version_value)
				GitManager.checkout(plug_dir, version_value)
			"commit":
				GitManager.git(plug_dir, ["fetch", "origin"])
				GitManager.checkout(plug_dir, version_value)
		var commit_hash = GitManager.rev_parse_head(plug_dir)
		var installed_addons = addon_data.get_installed_addons(repo_name)
		for p in installed_addons:
			var pdir = p.get("addon_dir", "")
			match version_type:
				"branch":
					addon_data.set_addon_branch(repo_name, pdir, version_value, commit_hash)
				"tag":
					addon_data.set_addon_tag(repo_name, pdir, version_value, commit_hash)
				"commit":
					addon_data.set_addon_commit_lock(repo_name, pdir, version_value)
			GitManager.copy_addon_dir(plug_dir, pdir, project_root)
		var scanned = GitManager.scan_local_addons(plug_dir)
		for sp in scanned:
			sp["type"] = AddonData._normalize_type(sp.get("type", ""))
		addon_data.merge_scan_results(repo_name, scanned)
		addon_data.save_data()
		_remote_ref_cache.erase(repo_name)
		_erase_commit_cache_for_repo(repo_name)
		_update_done = true
	)


func _erase_commit_cache_for_repo(repo_name: String):
	var keys_to_erase: Array = []
	for key in _commit_cache:
		if (key as String).begins_with(repo_name + ":"):
			keys_to_erase.append(key)
	for key in keys_to_erase:
		_commit_cache.erase(key)


# ===========================================================================
# Shared SelectorPopup (branch/tag + commit, both tabs)
# ===========================================================================

func _get_or_create_selector_popup() -> SelectorPopup:
	if not is_instance_valid(_selector_popup):
		_selector_popup = SelectorPopup.new()
		add_child(_selector_popup)
	return _selector_popup


func _open_branch_tag_popup(branches: PackedStringArray, tags: PackedStringArray):
	var groups = _build_branch_tag_groups(branches, tags)
	var popup = _get_or_create_selector_popup()
	if popup.item_selected.is_connected(_on_selector_item_selected):
		popup.item_selected.disconnect(_on_selector_item_selected)
	popup.setup({
		"title": tr("BRANCH_POPUP_TITLE"),
		"size": Vector2i(_scaled(PlugUIConstants.BRANCH_POPUP_SIZE.x), _scaled(PlugUIConstants.BRANCH_POPUP_SIZE.y)),
		"filter_placeholder": tr("BRANCH_POPUP_FILTER"),
		"columns": 1,
		"show_column_titles": false,
		"groups": groups,
	})
	popup.item_selected.connect(_on_selector_item_selected, CONNECT_ONE_SHOT)
	popup.popup_centered()


func _open_commit_popup(commits: Array):
	var groups = _build_commit_groups(commits)
	var popup = _get_or_create_selector_popup()
	if popup.item_selected.is_connected(_on_selector_item_selected):
		popup.item_selected.disconnect(_on_selector_item_selected)
	popup.setup({
		"title": tr("COL_COMMIT"),
		"size": Vector2i(_scaled(PlugUIConstants.COMMIT_POPUP_SIZE.x), _scaled(PlugUIConstants.COMMIT_POPUP_SIZE.y)),
		"filter_placeholder": tr("BRANCH_POPUP_FILTER"),
		"columns": 2,
		"column_widths": [_scaled(PlugUIConstants.COMMIT_POPUP_HASH_COL_WIDTH), 0],
		"show_column_titles": false,
		"groups": groups,
	})
	popup.item_selected.connect(_on_selector_item_selected, CONNECT_ONE_SHOT)
	popup.popup_centered()


# --- Branch/tag selector (both tabs) ---

func _show_branch_tag_selector(repo_name: String, context: String):
	if _popup_loading:
		return
	_selector_context = context
	_selector_repo_name = repo_name

	if _remote_ref_cache.has(repo_name):
		var cached = _remote_ref_cache[repo_name]
		_open_branch_tag_popup(cached["branches"], cached["tags"])
		return

	var popup = _get_or_create_selector_popup()
	popup.show_loading(tr("BRANCH_POPUP_TITLE"), tr("SELECTOR_LOADING"))
	popup.popup_centered()
	_popup_loading = true

	var url = ""
	if context == "search_branch":
		url = _search_url
	elif context.begins_with("available_"):
		if _selector_target_item != null and _selector_target_item.has_meta("repo"):
			url = _selector_target_item.get_meta("repo")
	else:
		url = addon_data.get_repo(repo_name).get("url", "")

	_popup_done = false
	_popup_active = true
	_popup_task_id = WorkerThreadPool.add_task(func():
		GitManager.reset_cancel()
		var remote_info = GitManager.ls_remote(url)
		_popup_result = {
			"type": "branch_tag",
			"branches": remote_info.get("branches", PackedStringArray()),
			"tags": remote_info.get("tags", PackedStringArray()),
			"ref_commits": remote_info.get("ref_commits", {}),
			"error": remote_info.get("error", ""),
		}
		_popup_done = true
	)


func _show_search_branch_popup(item: TreeItem):
	_selector_target_item = item
	var repo_name = GitManager.repo_name_from_url(_search_url)
	if not _search_branches.is_empty() or not _search_tags.is_empty():
		_selector_context = "search_branch"
		_selector_repo_name = repo_name
		_open_branch_tag_popup(_search_branches, _search_tags)
	else:
		_show_branch_tag_selector(repo_name, "search_branch")


# --- Commit selector (both tabs) ---

func _get_effective_ref(repo_name: String) -> Dictionary:
	if _pending_changes.has(repo_name):
		var p = _pending_changes[repo_name]
		if not p.get("tag", "").is_empty():
			return {"type": "tag", "ref": p["tag"]}
		if not p.get("branch", "").is_empty():
			return {"type": "branch", "ref": p["branch"]}
	var first = _first_installed_or_first(addon_data.get_installed_addons(repo_name))
	if not first.get("tag", "").is_empty():
		return {"type": "tag", "ref": first["tag"]}
	var br = first.get("branch", "")
	if br.is_empty():
		var cached_info = _version_cache.get(repo_name, {})
		br = cached_info.get("current_branch", "")
	return {"type": "branch", "ref": br}


func _show_commit_selector(repo_name: String, context: String):
	if _popup_loading:
		return
	_selector_context = context
	_selector_repo_name = repo_name

	var eff: Dictionary
	if context == "available_commit" and _selector_target_item != null:
		var branch: String = _selector_target_item.get_meta("selected_branch", "main")
		eff = {"type": "branch", "ref": branch}
	else:
		eff = _get_effective_ref(repo_name)
	var eff_type: String = eff.get("type", "branch")
	var eff_ref: String = eff.get("ref", "")

	if eff_type == "tag" and not eff_ref.is_empty():
		var ref_commits_dict = _remote_ref_cache.get(repo_name, {}).get("ref_commits", _search_ref_commits)
		var tag_hash = ref_commits_dict.get(eff_ref, "")
		if tag_hash.is_empty():
			tag_hash = eff_ref
		var single = [{"hash": tag_hash, "hash_short": _short_commit(tag_hash), "message": "Tag: " + eff_ref}]
		_open_commit_popup(single)
		return

	var cache_key = repo_name + ":" + eff_ref
	if _commit_cache.has(cache_key):
		_open_commit_popup(_commit_cache[cache_key])
		return

	var popup = _get_or_create_selector_popup()
	popup.show_loading(tr("COL_COMMIT"), tr("SELECTOR_LOADING"))
	popup.popup_centered()
	_popup_loading = true

	var _clone_url = ""
	if context.begins_with("available_") and _selector_target_item != null:
		_clone_url = _selector_target_item.get_meta("repo", "")

	_popup_done = false
	_popup_active = true
	_popup_task_id = WorkerThreadPool.add_task(func():
		GitManager.reset_cancel()
		if not _ensure_repo_cloned(repo_name, _clone_url):
			_popup_result = {"type": "commit", "error": GitManager.last_error if not GitManager.last_error.is_empty() else "Clone failed", "commits": [], "cache_key": cache_key}
			_popup_done = true
			return
		var plug_dir = GitManager.get_plugged_dir().path_join(repo_name)
		GitManager.git(plug_dir, ["fetch", "origin", "--deepen=%d" % PlugUIConstants.FETCH_DEEPEN_COUNT])
		var commits: Array[Dictionary] = []
		if not eff_ref.is_empty():
			commits = GitManager.get_commit_log(plug_dir, "origin/" + eff_ref, PlugUIConstants.COMMIT_LOG_LIMIT)
		if commits.is_empty():
			var info = GitManager.get_current_info(plug_dir)
			var branch = info.get("branch", "")
			if not branch.is_empty():
				commits = GitManager.get_commit_log(plug_dir, "origin/" + branch, PlugUIConstants.COMMIT_LOG_LIMIT)
		if commits.is_empty():
			commits = GitManager.get_commit_log(plug_dir, "--all", PlugUIConstants.COMMIT_LOG_LIMIT)
		if commits.is_empty():
			commits = GitManager.get_commit_log(plug_dir, "HEAD", PlugUIConstants.COMMIT_LOG_LIMIT)
		_popup_result = {"type": "commit", "commits": commits, "error": "", "cache_key": cache_key}
		_popup_done = true
	)


func _on_popup_data_loaded():
	_popup_loading = false
	var popup = _get_or_create_selector_popup()
	var err: String = _popup_result.get("error", "")
	if not err.is_empty():
		popup.show_error(err)
		return
	var ptype: String = _popup_result.get("type", "")
	if ptype == "branch_tag":
		var branches: PackedStringArray = _popup_result.get("branches", PackedStringArray())
		var tags: PackedStringArray = _popup_result.get("tags", PackedStringArray())
		var ref_commits: Dictionary = _popup_result.get("ref_commits", {})
		_remote_ref_cache[_selector_repo_name] = {"branches": branches, "tags": tags, "ref_commits": ref_commits}
		_open_branch_tag_popup(branches, tags)
	elif ptype == "commit":
		var commits: Array = _popup_result.get("commits", [])
		var ck: String = _popup_result.get("cache_key", _selector_repo_name)
		_commit_cache[ck] = commits
		_open_commit_popup(commits)


# --- Unified selection handler ---

func _on_selector_item_selected(meta: Dictionary):
	var version_type: String = meta.get("type", "")

	# Search / Available tab: branch/tag selection → update item display
	if _selector_context in ["search_branch", "available_branch"]:
		_apply_search_ref_selection(meta)
		return

	# Search / Available tab: commit selection → update item display + store for install
	if _selector_context in ["search_commit", "available_commit"]:
		_apply_search_commit_selection(meta)
		return

	# Installed tab: branch/tag/commit → store as pending
	if _selector_context in ["installed_branch", "installed_commit"]:
		var rn = _selector_repo_name
		var pending = _pending_changes.get(rn, {}).duplicate() as Dictionary

		match version_type:
			"branch":
				var branch_name = meta.get("name", "")
				if branch_name.is_empty():
					return
				pending["branch"] = branch_name
				pending.erase("tag")
				var ref_commits = _remote_ref_cache.get(rn, {}).get("ref_commits", {})
				var latest_hash = ref_commits.get(branch_name, "")
				pending["commit"] = latest_hash
				pending["commit_preview"] = _short_commit(latest_hash) if not latest_hash.is_empty() else ""
			"tag":
				var tag_name = meta.get("name", "")
				if tag_name.is_empty():
					return
				pending["tag"] = tag_name
				pending.erase("branch")
				var ref_commits = _remote_ref_cache.get(rn, {}).get("ref_commits", {})
				var tag_hash = ref_commits.get(tag_name, "")
				pending["commit"] = tag_hash
				pending["commit_preview"] = _short_commit(tag_hash) if not tag_hash.is_empty() else ""
			"commit":
				var hash_full = meta.get("hash", "")
				if hash_full.is_empty():
					return
				pending["commit"] = hash_full
				pending["commit_preview"] = meta.get("hash_short", _short_commit(hash_full))

		_pending_changes[rn] = pending
		if _pending_matches_current(rn, pending):
			_pending_changes.erase(rn)
		_refresh_installed_tree()


func _pending_matches_current(repo_name: String, pending: Dictionary) -> bool:
	var first = _first_installed_or_first(addon_data.get_installed_addons(repo_name))
	var cur_branch = first.get("branch", "")
	var cur_tag = first.get("tag", "")
	var cur_commit = first.get("commit", "")
	var cached = _version_cache.get(repo_name, {})
	if cached.has("current_commit") and not cached["current_commit"].is_empty():
		cur_commit = cached["current_commit"]

	var eff_branch = pending.get("branch", "") if pending.has("branch") else cur_branch
	var eff_tag = pending.get("tag", "") if pending.has("tag") else cur_tag
	if pending.has("tag"):
		eff_branch = ""
	elif pending.has("branch"):
		eff_tag = ""
	var eff_commit = pending.get("commit", "")

	if eff_branch != cur_branch or eff_tag != cur_tag:
		return false
	if not eff_commit.is_empty() and not cur_commit.is_empty():
		var len_cmp = mini(eff_commit.length(), cur_commit.length())
		if eff_commit.left(len_cmp) != cur_commit.left(len_cmp):
			return false
	return true


func _apply_search_ref_selection(meta: Dictionary):
	var item = _selector_target_item
	if item == null:
		return
	var ref_name: String = meta.get("name", "")
	var is_tag: bool = meta.get("type", "") == "tag"
	if is_tag:
		item.set_text(5, ref_name + " [tag]")
		item.set_meta("selected_branch", "")
		item.set_meta("selected_tag", ref_name)
	else:
		item.set_text(5, ref_name)
		item.set_meta("selected_branch", ref_name)
		item.set_meta("selected_tag", "")
	var commit = _search_ref_commits.get(ref_name, _search_head_commit)
	item.set_text(6, _short_commit(commit))
	item.set_custom_color(6, _commit_color(true))
	item.set_meta("selected_commit", "")


func _apply_search_commit_selection(meta: Dictionary):
	var item = _selector_target_item
	if item == null:
		return
	var hash_full: String = meta.get("hash", "")
	var hash_short: String = meta.get("hash_short", _short_commit(hash_full))
	item.set_text(6, hash_short)
	item.set_meta("selected_commit", hash_full)
	var branch: String = item.get_meta("selected_branch", "")
	var tag: String = item.get_meta("selected_tag", "")
	var ref = tag if not tag.is_empty() else branch
	var head = _search_ref_commits.get(ref, _search_head_commit)
	item.set_custom_color(6, _commit_color(hash_full == head))


# ===========================================================================
# Signal callbacks
# ===========================================================================

func _on_visibility_changed():
	if visible and not _is_executing:
		addon_data.load_data()
		_remote_ref_cache.clear()
		_commit_cache.clear()
		_refresh_installed_tree()


func _on_tab_changed(tab: int):
	if tab == 1:
		_update_search_tree_install_status()
		_update_install_selected_count()


func _on_installed_tree_mouse_selected(position: Vector2, mouse_button_index: int):
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var item = installed_tree.get_selected()
	if item == null or not item.has_meta("repo_name"):
		return
	var col = installed_tree.get_column_at_position(position)
	var repo_name: String = item.get_meta("repo_name")
	if repo_name.is_empty():
		return

	var is_locked = addon_data.is_repo_locked(repo_name)

	match col:
		3:
			if not is_locked:
				_show_branch_tag_selector(repo_name, "installed_branch")
		4:
			if not is_locked:
				_show_commit_selector(repo_name, "installed_commit")
		6:
			_show_detail_dialog(repo_name)
		7:
			_toggle_repo_lock(repo_name)
		8:
			if is_locked:
				return
			if _pending_changes.has(repo_name):
				_apply_pending_changes(repo_name)
			else:
				var action = item.get_text(8)
				if action != tr("STATUS_LATEST") and action != tr("STATUS_INSTALLING") and action != tr("STATUS_CHECKING") and action != tr("STATUS_UPDATING"):
					_update_single_repo(repo_name)
		9:
			if repo_name != SELF_REPO_NAME:
				_confirm_remove_repo(repo_name)


func _toggle_repo_lock(repo_name: String):
	var is_locked = addon_data.is_repo_locked(repo_name)
	if is_locked:
		addon_data.set_repo_locked(repo_name, false)
	else:
		_pending_changes.erase(repo_name)
		addon_data.set_repo_locked(repo_name, true)
	addon_data.save_data()
	call_deferred("_refresh_installed_tree", "")


func _apply_pending_changes(repo_name: String):
	if not _pending_changes.has(repo_name):
		return
	var pending = _pending_changes[repo_name] as Dictionary
	var has_tag = not pending.get("tag", "").is_empty()
	var has_branch = not pending.get("branch", "").is_empty()
	var commit = pending.get("commit", "")
	_pending_changes.erase(repo_name)
	_is_version_switch = true

	if has_tag:
		_switch_repo_version(repo_name, "tag", pending["tag"])
	elif has_branch:
		_switch_repo_version(repo_name, "branch", pending["branch"], commit)
	elif not commit.is_empty():
		var first = _first_installed_or_first(addon_data.get_installed_addons(repo_name))
		var cur_branch = first.get("branch", "")
		if not cur_branch.is_empty():
			_switch_repo_version(repo_name, "branch", cur_branch, commit)
		else:
			_switch_repo_version(repo_name, "commit", commit)


func _on_search_tree_mouse_selected(position: Vector2, mouse_button_index: int):
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return

	if _tree_mode == TREE_MODE.SEARCHED:
		var col = search_tree.get_column_at_position(position)
		var item = search_tree.get_item_at_position(position)
		if item and item.has_meta("addon_info"):
			if col == 1 and item.get_text(1) == tr("STATUS_INSTALLED"):
				var repo_name = GitManager.repo_name_from_url(_search_url)
				_jump_to_installed_tab(repo_name)
			elif col == 5:
				_selector_target_item = item
				_show_search_branch_popup(item)
			elif col == 6:
				_selector_target_item = item
				var repo_name = GitManager.repo_name_from_url(_search_url)
				_show_commit_selector(repo_name, "search_commit")
		return

	if _tree_mode != TREE_MODE.AVAILABLE:
		return
	var col = search_tree.get_column_at_position(position)
	var item = search_tree.get_item_at_position(position)
	if item == null or not item.has_meta("is_available"):
		return
	if col == 1 and item.get_text(1) == tr("STATUS_INSTALLED"):
		var repo_name = GitManager.repo_name_from_url(item.get_meta("repo"))
		_jump_to_installed_tab(repo_name)
	elif col == 5:
		_selector_target_item = item
		var url: String = item.get_meta("repo")
		var repo_name = GitManager.repo_name_from_url(url)
		_show_branch_tag_selector(repo_name, "available_branch")
	elif col == 6:
		_selector_target_item = item
		var url: String = item.get_meta("repo")
		var repo_name = GitManager.repo_name_from_url(url)
		_show_commit_selector(repo_name, "available_commit")


func _on_SearchInput_text_changed(new_text: String):
	if _tree_mode != TREE_MODE.AVAILABLE:
		_tree_mode = TREE_MODE.AVAILABLE
	_refresh_unified_tree(new_text)


# ===========================================================================
# Search bar setup
# ===========================================================================

func _setup_search_bar():
	var search_bar_margin = search_input.get_parent()
	search_bar_margin.set("theme_override_constants/margin_top", _scaled(PlugUIConstants.MARGIN_COMPACT))
	search_bar_margin.set("theme_override_constants/margin_bottom", 0)
	var search_hbox = HBoxContainer.new()
	search_hbox.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_STANDARD))
	search_bar_margin.remove_child(search_input)
	search_hbox.add_child(search_input)
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.text_submitted.connect(_on_SearchInput_submitted)
	_search_btn = Button.new()
	_search_btn.pressed.connect(_on_SearchBtn_pressed)
	search_hbox.add_child(_search_btn)
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(_scaled(PlugUIConstants.SEARCH_BAR_SPACER_WIDTH), 0)
	search_hbox.add_child(spacer)
	install_selected_btn.get_parent().remove_child(install_selected_btn)
	search_hbox.add_child(install_selected_btn)
	search_bar_margin.add_child(search_hbox)


func _setup_installed_filter():
	var installed_vbox = installed_tree.get_parent()
	_installed_filter_input = LineEdit.new()
	_installed_filter_input.placeholder_text = tr("INSTALLED_FILTER_PLACEHOLDER")
	_installed_filter_input.clear_button_enabled = true
	_installed_filter_input.text_changed.connect(_on_installed_filter_changed)
	var margin = MarginContainer.new()
	margin.set("theme_override_constants/margin_left", _scaled(PlugUIConstants.MARGIN_STANDARD))
	margin.set("theme_override_constants/margin_top", _scaled(PlugUIConstants.MARGIN_COMPACT))
	margin.set("theme_override_constants/margin_right", _scaled(PlugUIConstants.MARGIN_STANDARD))
	margin.set("theme_override_constants/margin_bottom", 0)
	margin.add_child(_installed_filter_input)
	installed_vbox.add_child(margin)
	installed_vbox.move_child(margin, 0)


func _on_installed_filter_changed(new_text: String):
	_refresh_installed_tree(new_text)


func _is_url_like(text: String) -> bool:
	if text.begins_with("http://") or text.begins_with("https://") or text.begins_with("git@"):
		return true
	if "/" in text and " " not in text:
		return true
	return false


func _on_SearchBtn_pressed():
	if _tree_mode == TREE_MODE.SEARCHING:
		_on_CancelSearchBtn_pressed()
		return
	var text = search_input.text.strip_edges()
	if text.is_empty():
		_refresh_unified_tree("")
		return
	if _is_url_like(text):
		_on_SearchUrlBtn_pressed()
	else:
		_refresh_unified_tree(text)


func _on_SearchInput_submitted(_text: String):
	_on_SearchBtn_pressed()


func _on_CancelSearchBtn_pressed():
	_search_cancelled = true
	GitManager.request_cancel()
	_search_overlay.visible = false
	_search_btn.disabled = false
	_search_btn.text = tr("BTN_SEARCH")
	PlugLogger.info(_tr("LOG_SEARCH_CANCELLED"))


# ===========================================================================
# Status refresh for install-new tab
# ===========================================================================

func _update_search_tree_install_status():
	var root = search_tree.get_root()
	if root == null:
		return
	var existing_addons = _get_existing_addons()
	var child = root.get_first_child()
	while child:
		var repo_url = ""
		if child.has_meta("repo"):
			repo_url = child.get_meta("repo")
		elif child.has_meta("addon_info"):
			repo_url = _search_url
		if not repo_url.is_empty():
			var rn = GitManager.repo_name_from_url(repo_url)
			var is_installed = addon_data.has_repo(rn)
			child.set_text(1, tr("STATUS_INSTALLED") if is_installed else tr("STATUS_NOT_INSTALLED"))
			child.set_custom_color(1, COLOR_UP_TO_DATE if is_installed else COLOR_UNKNOWN)
			if child.has_meta("addon_info"):
				child.set_editable(0, not is_installed)
				var info: Dictionary = child.get_meta("addon_info")
				var pdir: String = info.get("addon_dir", "")
				var has_conflict := false
				if not pdir.is_empty() and not is_installed:
					has_conflict = not addon_data.check_dir_conflicts([pdir], existing_addons).is_empty()
				child.set_meta("has_conflict", has_conflict)
				if is_installed:
					child.set_checked(0, false)
					child.clear_custom_color(2)
					child.set_tooltip_text(2, repo_url)
					_refresh_available_item_from_installed(child, rn, pdir)
				elif has_conflict:
					child.set_custom_color(2, COLOR_CONFLICT)
					child.set_tooltip_text(2, repo_url + "\n" + tr("CONFLICT_DIR_EXISTS") % pdir)
					child.set_checked(0, false)
				else:
					child.clear_custom_color(2)
					child.set_tooltip_text(2, repo_url)
		child = child.get_next()


func _refresh_available_item_from_installed(item: TreeItem, repo_name: String, addon_dir: String):
	var installed_addons = addon_data.get_installed_addons(repo_name)
	var match_addon: Dictionary = {}
	for p in installed_addons:
		if p.get("addon_dir", "") == addon_dir:
			match_addon = p
			break
	if match_addon.is_empty() and not installed_addons.is_empty():
		match_addon = installed_addons[0]
	if match_addon.is_empty():
		return

	var ver: String = match_addon.get("version", "")
	item.set_text(3, ("v" + ver) if not ver.is_empty() else "-")
	item.set_text_alignment(3, HORIZONTAL_ALIGNMENT_CENTER)

	var branch: String = match_addon.get("branch", "")
	var tag: String = match_addon.get("tag", "")
	item.set_text(5, _format_branch_tag(branch, tag))
	item.set_custom_color(5, COLOR_UPDATED)
	item.set_text_alignment(5, HORIZONTAL_ALIGNMENT_CENTER)

	var cached = _version_cache.get(repo_name, {})
	var commit_str: String = ""
	if cached.has("current_commit") and not cached["current_commit"].is_empty():
		commit_str = _short_commit(cached["current_commit"])
	elif not match_addon.get("commit", "").is_empty():
		commit_str = _short_commit(match_addon["commit"])
	item.set_text(6, commit_str if not commit_str.is_empty() else "-")
	item.set_custom_color(6, COLOR_UPDATED)
	item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)


func _set_checked_items_status(status_text: String, color: Color):
	var root = search_tree.get_root()
	if root == null:
		return
	var child = root.get_first_child()
	while child:
		if child.is_checked(0):
			child.set_text(1, status_text)
			child.set_custom_color(1, color)
			child.set_editable(0, false)
		child = child.get_next()


# ===========================================================================
# Detail dialog
# ===========================================================================

func _show_detail_dialog(repo_name: String):
	var repo = addon_data.get_repo(repo_name)
	if repo.is_empty():
		return
	var url: String = repo.get("url", "")
	var first_addon = _first_installed_or_first(repo.get("addons", []))
	var dialog = AcceptDialog.new()
	dialog.title = tr("DETAIL_TITLE")
	dialog.ok_button_text = tr("BTN_CLOSE")
	dialog.min_size = Vector2i(_scaled(PlugUIConstants.DETAIL_DIALOG_MIN_WIDTH), 0)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _scaled(PlugUIConstants.DETAIL_H_SEPARATION))
	grid.add_theme_constant_override("v_separation", _scaled(PlugUIConstants.DETAIL_V_SEPARATION))
	var fields = [
		[tr("DETAIL_NAME"), first_addon.get("name", repo_name)],
		[tr("DETAIL_DESC"), first_addon.get("description", "")],
		[tr("DETAIL_VERSION"), first_addon.get("version", "")],
		[tr("DETAIL_AUTHOR"), first_addon.get("author", "")],
		[tr("DETAIL_TYPE"), "Plugin" if first_addon.get("type", "") == "plugin" else "Extension"],
		[tr("DETAIL_URL"), url],
		[tr("DETAIL_INSTALL_PATH"), first_addon.get("addon_dir", "")],
		[tr("COL_BRANCH_TAG"), AddonData.get_version_label(first_addon)],
		[tr("COL_COMMIT"), _short_commit(first_addon.get("commit", ""))],
	]
	for f in fields:
		var key_label = Label.new()
		key_label.text = f[0] + ":"
		key_label.add_theme_color_override("font_color", COLOR_URL)
		grid.add_child(key_label)
		var val_label = Label.new()
		val_label.text = str(f[1])
		val_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val_label.custom_minimum_size = Vector2(_scaled(PlugUIConstants.DETAIL_LABEL_MIN_WIDTH), 0)
		grid.add_child(val_label)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_LARGE))
	vbox.add_child(grid)
	if not url.is_empty():
		var open_btn = Button.new()
		open_btn.text = tr("BTN_OPEN_REPO")
		open_btn.pressed.connect(func(): OS.shell_open(url))
		vbox.add_child(open_btn)
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


# ===========================================================================
# Search overlay
# ===========================================================================

func _setup_search_overlay():
	_search_overlay = CenterContainer.new()
	_search_overlay.visible = false
	_search_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_search_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_STANDARD))
	_search_overlay.add_child(hbox)
	_search_spinner = TextureRect.new()
	_search_spinner.texture = preload("res://addons/gd-plug-plus/assets/icons/loading.svg")
	_search_spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_search_spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_search_spinner.custom_minimum_size = Vector2(_scaled(PlugUIConstants.SPINNER_SIZE), _scaled(PlugUIConstants.SPINNER_SIZE))
	hbox.add_child(_search_spinner)
	_search_overlay_label = Label.new()
	_search_overlay_label.text = tr("SEARCHING")
	hbox.add_child(_search_overlay_label)
	search_result_panel.add_child(_search_overlay)


# ===========================================================================
# Console
# ===========================================================================

func _setup_console():
	_console_panel = PanelContainer.new()
	_console_panel.name = "ConsolePanel"
	_console_panel.anchor_top = 1.0
	_console_panel.anchor_bottom = 1.0
	_console_panel.anchor_left = 0.0
	_console_panel.anchor_right = 1.0
	_console_panel.offset_top = -_console_header_height
	_console_panel.offset_bottom = 0
	var vbox = VBoxContainer.new()
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", _scaled(PlugUIConstants.SEPARATION_STANDARD))
	_console_toggle_btn = Button.new()
	_console_toggle_btn.flat = true
	_console_toggle_btn.pressed.connect(_toggle_console)
	header.add_child(_console_toggle_btn)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_console_clear_btn = Button.new()
	_console_clear_btn.flat = true
	_console_clear_btn.pressed.connect(_clear_console)
	header.add_child(_console_clear_btn)
	vbox.add_child(header)
	_console_log = RichTextLabel.new()
	_console_log.scroll_following = true
	_console_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_console_log.selection_enabled = true
	_console_log.visible = false
	_console_log.add_theme_font_size_override("normal_font_size", _scaled(PlugUIConstants.CONSOLE_FONT_SIZE))
	vbox.add_child(_console_log)
	_console_panel.add_child(vbox)
	add_child(_console_panel)
	tab_container.offset_bottom = -_console_header_height
	move_child(loading_overlay, -1)


func _toggle_console():
	_console_collapsed = not _console_collapsed
	if _console_collapsed:
		_console_toggle_btn.text = tr("CONSOLE_COLLAPSED")
		_console_panel.offset_top = -_console_header_height
		_console_log.visible = false
		tab_container.offset_bottom = -_console_header_height
	else:
		_console_toggle_btn.text = tr("CONSOLE_EXPANDED")
		_console_panel.offset_top = -_console_expanded_height
		_console_log.visible = true
		tab_container.offset_bottom = -_console_expanded_height


func _clear_console():
	_console_log.clear()
	PlugLogger.clear()
	_last_log_count = 0


func _update_console():
	var count = PlugLogger.get_log_count()
	if count > _last_log_count:
		var new_logs = PlugLogger.get_logs_since(_last_log_count)
		for entry in new_logs:
			_console_log.add_text(entry + "\n")
		_last_log_count = count


func _show_toast(msg: String, is_error: bool = false):
	var dialog = AcceptDialog.new()
	dialog.title = tr("TOAST_ERROR") if is_error else tr("TOAST_INFO")
	dialog.dialog_text = msg
	dialog.min_size = Vector2i(_scaled(PlugUIConstants.TOAST_MIN_WIDTH), 0)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


