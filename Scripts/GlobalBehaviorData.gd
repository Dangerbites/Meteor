extends Node

var Broadcasts = {}
var Broadcasting = {}
var BehaviorStates = {}
var Debug : bool = false
var uuid_registry: Dictionary = {}

# In GlobalBehaviorData.gd
var prof_calls_by_tag: Dictionary = {}   # { tag: {"name": behavior_name, "count": int} }

func prof_record_call(behavior_name: String, tag: String) -> void:
	if not prof_calls_by_tag.has(tag):
		prof_calls_by_tag[tag] = {"name": behavior_name, "count": 0}
	prof_calls_by_tag[tag]["count"] += 1

func register_uuid(uuid: String, node: Node) -> void:
	if not uuid_registry.has(uuid):
		uuid_registry[uuid] = node

func unregister_uuid(uuid: String, node: Node) -> void:
	if uuid_registry.get(uuid) == node:
		uuid_registry.erase(uuid)

# --- PROFILING ---
var prof_run_next_calls := 0
var prof_run_next_time_us := 0
var prof_get_target_calls := 0
var prof_get_target_time_us := 0
var prof_get_uuid_calls := 0
var prof_get_uuid_scan_fallbacks := 0
var prof_move_unique_targets: Dictionary = {}   # instance_id -> true, cleared each report

var _prof_elapsed := 0.0
var _prof_interval := 1.0

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("tab"):
		Debug = !Debug

	_prof_elapsed += _delta
	if _prof_elapsed >= _prof_interval:
		_prof_elapsed = 0.0
		_print_profile_report()

func _print_profile_report() -> void:
	print("=== PERF REPORT (last ~1s) ===")
	print("FPS: ", Engine.get_frames_per_second())
	print("run_next_behavior: calls=%d  total_time=%.2fms  avg=%.3fms" % [
		prof_run_next_calls,
		prof_run_next_time_us / 1000.0,
		(prof_run_next_time_us / 1000.0) / max(prof_run_next_calls, 1)
	])
	print("get_target_nodes:  calls=%d  total_time=%.2fms  avg=%.3fms" % [
		prof_get_target_calls,
		prof_get_target_time_us / 1000.0,
		(prof_get_target_time_us / 1000.0) / max(prof_get_target_calls, 1)
	])
	print("get_node_from_UUID: calls=%d  scan_fallbacks=%d  (fallback%% = %.1f%%)" % [
		prof_get_uuid_calls,
		prof_get_uuid_scan_fallbacks,
		100.0 * prof_get_uuid_scan_fallbacks / max(prof_get_uuid_calls, 1)
	])
	print("uuid_registry size: ", uuid_registry.size())
	print("HyperpadObject group size: ", get_tree().get_nodes_in_group("HyperpadObject").size())

	print("--- calls by behavior tag ---")
	var sorted_tags = prof_calls_by_tag.keys()
	sorted_tags.sort_custom(func(a, b): return prof_calls_by_tag[a]["count"] > prof_calls_by_tag[b]["count"])
	for i in min(10, sorted_tags.size()):
		var tag = sorted_tags[i]
		var entry = prof_calls_by_tag[tag]
		print("  %s (%s): %d" % [entry["name"], tag, entry["count"]])
	print("================================")

	prof_run_next_calls = 0
	prof_run_next_time_us = 0
	prof_get_target_calls = 0
	prof_get_target_time_us = 0
	prof_get_uuid_calls = 0
	prof_get_uuid_scan_fallbacks = 0
	prof_calls_by_tag.clear()

	print("Move unique targets touched: ", prof_move_unique_targets.size())
	prof_move_unique_targets.clear()
