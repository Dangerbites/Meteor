extends Node
## Autoload: TapAssetExtractor
##
## ... (original comments unchanged) ...

signal extraction_progress(current: int, total: int, path: String)
signal extraction_finished(result: Dictionary)

const OUTPUT_ROOT := "user://project"
const ASSETS_PREFIX := "Assets/"
const HD_SUFFIX := "-hd.png"

## Characters Windows forbids anywhere in a file/folder name.
const WINDOWS_RESERVED_CHARS := ["<", ">", ":", "\"", "\\", "|", "?", "*"]
## Names Windows forbids outright, regardless of extension.
const WINDOWS_RESERVED_NAMES := [
	"CON", "PRN", "AUX", "NUL",
	"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
]
## --- Python-based audio conversion ---------------------------------------
## Godot has no built-in AAC/M4A decoder, so extracted .m4a files are
## unplayable as-is. m4a_to_ogg.py (bundled with the project) uses PyAV
## to convert .m4a -> .ogg, which Godot's AudioStreamOggVorbis loads
## natively. The script is called synchronously right after each .m4a is
## written to disk, so every playable sound is already an .ogg file when
## extraction finishes.
const PYTHON_SCRIPT_NAME := "m4a_to_ogg.py"

## Tries to locate the Python conversion script in two places:
##   1. The user data folder (OS.get_user_data_dir()) – useful when
##      the script is copied alongside other runtime tooling.
##   2. The project's res:// folder (so it can be versioned directly).
## Returns an empty string if neither location is found.
static func _get_python_script_path() -> String:
	# 1) Look in user data dir (same pattern as the old ffmpeg.exe).
	var user_path := OS.get_user_data_dir().path_join(PYTHON_SCRIPT_NAME)
	if FileAccess.file_exists(user_path):
		return ProjectSettings.globalize_path(user_path)   # Python needs a real path.

	# 2) Fallback: look inside the project folder.
	if ResourceLoader.exists("res://" + PYTHON_SCRIPT_NAME):
		return ProjectSettings.globalize_path("res://" + PYTHON_SCRIPT_NAME)

	return ""


## Converts a just-written .m4a file to .ogg in place via Python.
## Returns true if the .ogg was produced.
static func _convert_m4a_to_ogg(m4a_path: String) -> bool:
	var script_path := _get_python_script_path()
	if script_path.is_empty():
		push_warning("_convert_m4a_to_ogg: %s not found – skipping conversion of '%s'" % [PYTHON_SCRIPT_NAME, m4a_path])
		return false

	var ogg_path := m4a_path.get_basename() + ".ogg"

	# Godot's OS.execute needs real filesystem paths, not user:// URIs.
	var real_m4a_path := ProjectSettings.globalize_path(m4a_path)
	var real_ogg_path := ProjectSettings.globalize_path(ogg_path)

	# Use "python" – if your system requires "python3", adjust here.
	var args := PackedStringArray([script_path, real_m4a_path, real_ogg_path])
	var output := []
	var exit_code := OS.execute("python", args, output, true)

	if exit_code != 0:
		push_warning("_convert_m4a_to_ogg: Python script exited with code %d converting '%s'. Output:\n%s" % [exit_code, m4a_path, "\n".join(output)])
		return false

	if not FileAccess.file_exists(ogg_path):
		push_warning("_convert_m4a_to_ogg: Python script ran but '%s' was not created" % ogg_path)
		return false

	return true
## Windows silently strips trailing dots/spaces ... (original static functions unchanged) ...

static func sanitize_path_segment(segment: String) -> String:
	var cleaned := segment
	for ch in WINDOWS_RESERVED_CHARS:
		cleaned = cleaned.replace(ch, "")
	cleaned = cleaned.rstrip(". ")
	if cleaned.to_upper() in WINDOWS_RESERVED_NAMES:
		cleaned += "_"
	return cleaned if not cleaned.is_empty() else segment

static func sanitize_asset_path(asset_path: String) -> String:
	var parts := asset_path.split("/")
	for i in parts.size():
		parts[i] = sanitize_path_segment(parts[i])
	return "/".join(parts)

static func sanitize_full_path(path: String) -> String:
	var parts := path.split("/")
	for i in parts.size():
		if i == parts.size() - 1:
			var ext := parts[i].get_extension()
			var base := parts[i].get_basename()
			base = sanitize_path_segment(base)
			parts[i] = base if ext.is_empty() else "%s.%s" % [base, ext]
		else:
			parts[i] = sanitize_path_segment(parts[i])
	return "/".join(parts)


## Original synchronous extraction (unchanged, + m4a conversion).
func extract_tap_assets(tap_file_path: String, prefer_hd: bool = true, verbose: bool = true) -> Dictionary:
	var result := {
		"success": false,
		"extracted": [],
		"skipped": [],
		"errors": [],
	}

	var reader := ZIPReader.new()
	var open_err := reader.open(tap_file_path)
	if open_err != OK:
		var msg := "Could not open '%s' as a zip archive (error code %d)" % [tap_file_path, open_err]
		push_error(msg)
		result.errors.append([tap_file_path, msg])
		extraction_finished.emit(result)
		return result

	var all_files := reader.get_files()
	var total := all_files.size()

	var plain_has_hd := {}
	if prefer_hd:
		for path in all_files:
			if path.ends_with(HD_SUFFIX):
				var plain_path := path.substr(0, path.length() - HD_SUFFIX.length()) + ".png"
				plain_has_hd[plain_path] = true

	var i := 0
	for entry_path in all_files:
		i += 1
		extraction_progress.emit(i, total, entry_path)

		if entry_path.ends_with("/"):
			continue

		if not entry_path.begins_with(ASSETS_PREFIX):
			result.skipped.append([entry_path, "outside Assets/"])
			continue

		var file_name := entry_path.get_file()

		if file_name.begins_with("."):
			result.skipped.append([entry_path, "hidden editor metadata"])
			continue

		var is_hd := file_name.ends_with(HD_SUFFIX)
		var target_entry_path := entry_path

		if is_hd:
			if not prefer_hd:
				result.skipped.append([entry_path, "hd variant (prefer_hd is false)"])
				continue
			target_entry_path = entry_path.substr(0, entry_path.length() - HD_SUFFIX.length()) + ".png"
		elif prefer_hd and file_name.ends_with(".png") and plain_has_hd.get(entry_path, false):
			result.skipped.append([entry_path, "superseded by -hd sibling"])
			continue

		var data := reader.read_file(entry_path)
		if data.is_empty():
			result.errors.append([entry_path, "archive returned no data for this entry"])
			continue

		var sanitized_entry_path := sanitize_full_path(target_entry_path)
		var target_path := OUTPUT_ROOT.path_join(sanitized_entry_path)
		var target_dir := target_path.get_base_dir()

		var dir_err := DirAccess.make_dir_recursive_absolute(target_dir)
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			result.errors.append([entry_path, "could not create dir '%s' (error %d)" % [target_dir, dir_err]])
			continue

		var f := FileAccess.open(target_path, FileAccess.WRITE)
		if f == null:
			result.errors.append([entry_path, "could not open '%s' for writing (error %d)" % [target_path, FileAccess.get_open_error()]])
			continue
		f.store_buffer(data)
		f.close()

		result.extracted.append(target_path)
		if verbose:
			print("Extracted: ", target_path)

		if target_path.get_extension().to_lower() == "m4a":
			if _convert_m4a_to_ogg(target_path):
				if verbose:
					print("Converted to .ogg: ", target_path.get_basename() + ".ogg")

	reader.close()

	result.success = result.errors.is_empty()

	if verbose:
		print("--- extract_tap_assets('%s') ---" % tap_file_path)
		print("Extracted: %d   Skipped: %d   Errors: %d" % [result.extracted.size(), result.skipped.size(), result.errors.size()])
		for e in result.errors:
			push_warning("extract_tap_assets error on %s: %s" % [e[0], e[1]])

	extraction_finished.emit(result)
	return result


## --- Asynchronous threaded extraction with progress bar ---
func extract_tap_assets_async(tap_file_path: String, prefer_hd: bool = true, verbose: bool = true, progress_ui_node: Node = null) -> void:
	# Store the UI reference (only used on the main thread via deferred calls).
	progress_ui = progress_ui_node

	# If a previous thread is still running, wait for it (or handle as needed).
	if _worker_thread and _worker_thread.is_alive():
		_worker_thread.wait_to_finish()

	_worker_thread = Thread.new()
	# Pass self so the worker can call deferred methods on this autoload.
	var err := _worker_thread.start(_extract_worker.bind(tap_file_path, prefer_hd, verbose, self))
	if err != OK:
		push_error("Failed to start extraction thread (error %d)" % err)
		_worker_thread = null
		if progress_ui:
			progress_ui.set_progress("Thread start failed", 0.0)

## --- Progress UI support (thread‑safe) ---
var progress_ui : Node = null
var _worker_thread : Thread = null

## Static worker – everything in this method runs on the background thread.
## OS.execute() is safe to call from a background thread (it's a blocking
## subprocess call, not a Godot-object operation), so m4a->ogg conversion
## works here the same way it does in the main-thread extraction paths.
static func _extract_worker(tap_file_path: String, prefer_hd: bool, verbose: bool, autoload_instance: Node) -> void:
	# The worker builds the result dict locally, then passes it to the main thread.
	var result := {
		"success": false,
		"extracted": [],
		"skipped": [],
		"errors": [],
	}

	var reader := ZIPReader.new()
	var open_err := reader.open(tap_file_path)
	if open_err != OK:
		var msg := "Could not open '%s' as a zip archive (error code %d)" % [tap_file_path, open_err]
		result.errors.append([tap_file_path, msg])
		# Defer finished signal + result
		autoload_instance.call_deferred("_on_extraction_finished", result)
		return

	var all_files := reader.get_files()
	var total := all_files.size()

	var plain_has_hd := {}
	if prefer_hd:
		for path in all_files:
			if path.ends_with(HD_SUFFIX):
				var plain_path := path.substr(0, path.length() - HD_SUFFIX.length()) + ".png"
				plain_has_hd[plain_path] = true

	var i := 0
	for entry_path in all_files:
		i += 1
		# Notify main thread about progress
		autoload_instance.call_deferred("_on_extraction_progress", i, total, entry_path)

		if entry_path.ends_with("/"):
			continue

		if not entry_path.begins_with(ASSETS_PREFIX):
			result.skipped.append([entry_path, "outside Assets/"])
			continue

		var file_name := entry_path.get_file()

		if file_name.begins_with("."):
			result.skipped.append([entry_path, "hidden editor metadata"])
			continue

		var is_hd := file_name.ends_with(HD_SUFFIX)
		var target_entry_path := entry_path

		if is_hd:
			if not prefer_hd:
				result.skipped.append([entry_path, "hd variant (prefer_hd is false)"])
				continue
			target_entry_path = entry_path.substr(0, entry_path.length() - HD_SUFFIX.length()) + ".png"
		elif prefer_hd and file_name.ends_with(".png") and plain_has_hd.get(entry_path, false):
			result.skipped.append([entry_path, "superseded by -hd sibling"])
			continue

		var data := reader.read_file(entry_path)
		if data.is_empty():
			result.errors.append([entry_path, "archive returned no data for this entry"])
			continue

		var sanitized_entry_path := sanitize_full_path(target_entry_path)
		var target_path := OUTPUT_ROOT.path_join(sanitized_entry_path)
		var target_dir := target_path.get_base_dir()

		var dir_err := DirAccess.make_dir_recursive_absolute(target_dir)
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			result.errors.append([entry_path, "could not create dir '%s' (error %d)" % [target_dir, dir_err]])
			continue

		var f := FileAccess.open(target_path, FileAccess.WRITE)
		if f == null:
			result.errors.append([entry_path, "could not open '%s' for writing (error %d)" % [target_path, FileAccess.get_open_error()]])
			continue
		f.store_buffer(data)
		f.close()

		result.extracted.append(target_path)
		# No print here – console logging from a thread is okay but deferred prints
		# are possible if needed. We skip verbose prints for thread cleanliness.

		if target_path.get_extension().to_lower() == "m4a":
			_convert_m4a_to_ogg(target_path)

	reader.close()
	result.success = result.errors.is_empty()

	if verbose:
		# We can defer a print call if you want to see the summary.
		autoload_instance.call_deferred("print", "--- extract_tap_assets('%s') ---" % tap_file_path)
		autoload_instance.call_deferred("print", "Extracted: %d   Skipped: %d   Errors: %d" % [result.extracted.size(), result.skipped.size(), result.errors.size()])
		for e in result.errors:
			autoload_instance.call_deferred("push_warning", "extract error on %s: %s" % [e[0], e[1]])

	# When done, call the main‑thread completion handler.
	autoload_instance.call_deferred("_on_extraction_finished", result)


## Called on the main thread (by call_deferred) for every file processed.
func _on_extraction_progress(current: int, total: int, path: String) -> void:
	# Emit the original signal for anyone still listening.
	extraction_progress.emit(current, total, path)

	# Update the ProgressUI node if we have one.
	if progress_ui:
		var percent = clamp(float(current) / total * 100.0, 0.0, 100.0)
		var info := "Extracting " + path
		progress_ui.set_progress(info, percent)


## Called on the main thread when extraction finishes (or fails early).
func _on_extraction_finished(result: Dictionary) -> void:
	# Emit the original finished signal.
	extraction_finished.emit(result)

	# Make sure the progress bar reaches 100% and hides.
	if progress_ui:
		progress_ui.set_progress("Done", 100.0)

	# Clean up the thread.
	if _worker_thread:
		_worker_thread.wait_to_finish()
		_worker_thread = null


## Convenience helper – unchanged.
#func get_asset_user_path(asset_path) -> String:
#	if not (asset_path is String):
#		push_error("get_asset_user_path: Expected a non-null String, got: %s" % asset_path)
#		return ""   # fallback – adjust as needed
#	var sanitized_dir := sanitize_asset_path(asset_path)
#	var base_name := sanitize_path_segment(asset_path.get_file())
#	return OUTPUT_ROOT.path_join(sanitized_dir).path_join(base_name + ".png")

## Extracts assets spread over multiple frames so the game never freezes.
## progress_ui_node: optional ProgressUI node to update.
## prefer_hd, verbose: same as the sync version.
## Returns control when finished (the caller can `await` it).
func extract_tap_assets_non_blocking(tap_file_path: String, prefer_hd: bool = true, verbose: bool = true, progress_ui_node: Node = null) -> void:
	var result := {
		"success": false,
		"extracted": [],
		"skipped": [],
		"errors": [],
	}

	var reader := ZIPReader.new()
	var open_err := reader.open(tap_file_path)
	if open_err != OK:
		var msg := "Could not open '%s' as a zip archive (error code %d)" % [tap_file_path, open_err]
		push_error(msg)
		result.errors.append([tap_file_path, msg])
		extraction_finished.emit(result)
		if progress_ui_node:
			progress_ui_node.set_progress(msg, 0.0)
		return

	var all_files := reader.get_files()
	var total := all_files.size()
	var plain_has_hd := {}

	if prefer_hd:
		for path in all_files:
			if path.ends_with(HD_SUFFIX):
				var plain_path := path.substr(0, path.length() - HD_SUFFIX.length()) + ".png"
				plain_has_hd[plain_path] = true

	var i := 0
	const BATCH_SIZE := 5   # Process this many files per frame

	for entry_path in all_files:
		i += 1

		# Update the progress bar on every file (still very fast)
		extraction_progress.emit(i, total, entry_path)
		if progress_ui_node:
			var percent = clamp(float(i) / total * 100.0, 0.0, 100.0)
			progress_ui_node.set_progress("Extracting " + entry_path, percent)

		# --- skip logic (same as original) ---
		if entry_path.ends_with("/"):
			continue
		if not entry_path.begins_with(ASSETS_PREFIX):
			result.skipped.append([entry_path, "outside Assets/"])
			continue
		var file_name := entry_path.get_file()
		if file_name.begins_with("."):
			result.skipped.append([entry_path, "hidden editor metadata"])
			continue

		var is_hd := file_name.ends_with(HD_SUFFIX)
		var target_entry_path := entry_path

		if is_hd:
			if not prefer_hd:
				result.skipped.append([entry_path, "hd variant (prefer_hd is false)"])
				continue
			target_entry_path = entry_path.substr(0, entry_path.length() - HD_SUFFIX.length()) + ".png"
		elif prefer_hd and file_name.ends_with(".png") and plain_has_hd.get(entry_path, false):
			result.skipped.append([entry_path, "superseded by -hd sibling"])
			continue

		var data := reader.read_file(entry_path)
		if data.is_empty():
			result.errors.append([entry_path, "archive returned no data for this entry"])
			continue

		var sanitized_entry_path := sanitize_full_path(target_entry_path)
		var target_path := OUTPUT_ROOT.path_join(sanitized_entry_path)
		var target_dir := target_path.get_base_dir()

		# Main‑thread file I/O is completely safe.
		var dir_err := DirAccess.make_dir_recursive_absolute(target_dir)
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			result.errors.append([entry_path, "could not create dir '%s' (error %d)" % [target_dir, dir_err]])
			continue

		var f := FileAccess.open(target_path, FileAccess.WRITE)
		if f == null:
			result.errors.append([entry_path, "could not open '%s' for writing (error %d)" % [target_path, FileAccess.get_open_error()]])
			continue
		f.store_buffer(data)
		f.close()

		result.extracted.append(target_path)

		if target_path.get_extension().to_lower() == "m4a":
			if _convert_m4a_to_ogg(target_path):
				if verbose:
					print("Converted to .ogg: ", target_path.get_basename() + ".ogg")

		# Yield control every BATCH_SIZE files so the engine can render and process input.
		if i % BATCH_SIZE == 0:
			await get_tree().process_frame

	reader.close()
	result.success = result.errors.is_empty()

	if verbose:
		print("--- extract_tap_assets_non_blocking('%s') ---" % tap_file_path)
		print("Extracted: %d   Skipped: %d   Errors: %d" % [result.extracted.size(), result.skipped.size(), result.errors.size()])
		for e in result.errors:
			push_warning("extract error on %s: %s" % [e[0], e[1]])

	# Final UI update + signal
	extraction_finished.emit(result)
	if progress_ui_node:
		progress_ui_node.set_progress("Done", 100.0)

## Convenience helper – now resolves by scanning the folder instead of
## assuming the file is named after the last path segment.
##
## hyperPad's exported asset folders sometimes contain a single file whose
## name has nothing to do with the asset_path (e.g. "Grass Ground End/"
## containing "grassRight.png"). Since each of these folders only ever has
## one relevant file, we just open the directory and grab the first file
## with a recognized image/font extension rather than constructing a name.
##
## extensions_to_try lets callers ask for a font instead of an image
## (used by load_ttf_from_folder-style lookups if you want to unify those
## through this same helper later); defaults to image extensions since
## that's what every Sprite2D/TextureProgressBar/etc. caller wants today.
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]
const FONT_EXTENSIONS := ["ttf", "otf", "ttc"]

func get_asset_user_path(asset_path, extensions: PackedStringArray = PackedStringArray(IMAGE_EXTENSIONS)) -> String:
	if not (asset_path is String):
		push_error("get_asset_user_path: Expected a non-null String, got: %s" % asset_path)
		return ""

	var sanitized_dir := sanitize_asset_path(asset_path)
	var dir_path := OUTPUT_ROOT.path_join(sanitized_dir)

	var found_path := _find_first_file_with_extension(dir_path, extensions)
	if not found_path.is_empty():
		return found_path

	# Fallback to the old name-guessing behavior, in case the folder is
	# missing/unreadable or genuinely uses the expected filename. This
	# keeps old behavior as a safety net rather than a hard break.
	var base_name := sanitize_path_segment(asset_path.get_file())
	push_warning("get_asset_user_path: no file found in '%s' - falling back to guessed name '%s.png'" % [dir_path, base_name])
	return dir_path.path_join(base_name + ".png")


## Scans dir_path (a user:// path) for the first file whose extension is
## in `extensions`. Returns "" if the dir doesn't exist or has no match.
func _find_first_file_with_extension(dir_path: String, extensions: PackedStringArray) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var ext := file_name.get_extension().to_lower()
			if ext in extensions:
				dir.list_dir_end()
				return dir_path.path_join(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	return ""