extends SceneTree
const Pool = preload("res://scripts/combat_audio.gd")
var failed := 0
func _initialize() -> void:
	call_deferred("run")
func verify(ok:bool,label:String) -> void:
	if not ok: failed+=1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	var pool=Pool.new();root.add_child(pool)
	pool.unlock()
	for cue in Pool.REFINED_CUES:
		pool.clear();pool.tick(1.0)
		verify(pool.play_cue(cue,cue+"-first"),cue+" dispatch")
		verify(not pool.play_cue(cue,cue+"-repeat"),cue+" rate limit")
		verify(pool.played_log.back().stream.begins_with("res://assets/audio/refined/"),cue+" dedicated asset")
		verify(pool.players[pool.played_log.back().voice].pitch_scale==1.0,cue+" no pitch shifting")
		pool.configure(1,1,1,true)
		verify(pool.diagnostics().active_count==0 and not pool.play_cue(cue,cue+"-mute"),cue+" mute stop")
		pool.configure(1,1,1,false)
		verify(not pool.play_cue(cue,cue+"-mute"),cue+" no stale replay")
	pool.clear();await create_timer(0.15).timeout
	pool.queue_free();await process_frame
	print("REFINED_AUDIO failures=",failed," checks=42")
	quit(failed)
