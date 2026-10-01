extends SceneTree

# Renders SCENE_arena from a few fixed viewpoints and saves PNGs. Needs a display
# (it renders), so on a headless box run it under a virtual one:
#
#   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s tools/TOOL_arena_shots.gd -- <out_dir>
#
# Waits for the loading screen to finish (terrain prewarm + both scatters), then
# for each view parks FlyCamera, lets streaming settle, and grabs the frame.

const SCENE := "res://scenes/SCENE_arena.tscn"
const SETTLE_FRAMES := 90
const LOAD_TIMEOUT_S := 600.0

# name -> [eye, look_at target]
const VIEWS := {
	"game": [],  # the scene's own FlyCamera pose
	"high": [Vector3(0, 260, 200), Vector3(0, 0, -10)],
	"maze_low": [Vector3(-14, 9, 34), Vector3(0, 0, 0)],
	"meadow_low": [Vector3(0, 4, 70), Vector3(0, 1, 0)],
}

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene := (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	var cam := scene.get_node("FlyCamera") as Camera3D
	cam.set_process(false)
	cam.set_process_unhandled_input(false)
	var loading := scene.get_node_or_null("LoadingScreen") as CanvasLayer
	var t0 := Time.get_ticks_msec()
	await process_frame
	while loading != null and loading.visible:
		if (Time.get_ticks_msec() - t0) / 1000.0 > LOAD_TIMEOUT_S:
			push_warning("loading screen still up after %ds; shooting anyway" % LOAD_TIMEOUT_S)
			break
		await process_frame
	print("loaded in %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var game_pose := cam.global_transform
	for view_name in VIEWS:
		var v: Array = VIEWS[view_name]
		if v.is_empty():
			cam.global_transform = game_pose
		else:
			cam.global_position = v[0]
			cam.look_at(v[1], Vector3.UP if absf((v[1] - v[0]).normalized().y) < 0.99 else Vector3.FORWARD)
		for i in SETTLE_FRAMES:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := out_dir.path_join("arena_%s.png" % view_name)
		img.save_png(path)
		print("saved ", path)
	quit()
