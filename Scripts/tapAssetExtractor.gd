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

## --- Progress UI support (thread‑safe) ---
var progress_ui : Node = null
var _worker_thread : Thread = null

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


## Original synchronous extraction (unchanged).
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

## Static worker – everything in this method runs on the background thread.
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
func get_asset_user_path(asset_path: String) -> String:
	var sanitized_dir := sanitize_asset_path(asset_path)
	var base_name := sanitize_path_segment(asset_path.get_file())
	return OUTPUT_ROOT.path_join(sanitized_dir).path_join(base_name + ".png")

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