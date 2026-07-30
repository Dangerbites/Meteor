extends Node

var BehaviorStates = {}
var Debug : bool = false

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("tab"):
		Debug = !Debug

	if Debug:
		ImGui.Begin("GlobalBehaviorData.gd")
		for key in BehaviorStates:
			ImGui.Text("%s : %s" % [key, BehaviorStates[key]])
		ImGui.End()