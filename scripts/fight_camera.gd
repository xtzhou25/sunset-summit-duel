extends RefCounted
## Presentation only: never writes to simulation, attack directions or world bounds.
const BASE_WIDTH := 7.2
const HORIZONTAL_MAX_WIDTH := 8.2
const ACTOR_MARGIN := 1.2
const DEAD_ZONE := 0.20
const FOLLOW_SECONDS := 0.16
const ZOOM_OUT_SECONDS := 0.12
const ZOOM_IN_SECONDS := 0.45
const DECOR_HALF_WIDTH := 6.4
var center_x := 0.0
var width := BASE_WIDTH
var viewport_min_width := BASE_WIDTH
var initialized := false

func configure(minimum_width:float) -> void:
	viewport_min_width=maxf(BASE_WIDTH,minimum_width)

func update(left_x:float,right_x:float,delta:float,snap:bool=false) -> void:
	var lo:float=minf(left_x,right_x)
	var hi:float=maxf(left_x,right_x)
	var midpoint:float=(lo+hi)*0.5
	var maximum:float=maxf(viewport_min_width,HORIZONTAL_MAX_WIDTH)
	var desired_width:float=clampf(hi-lo+ACTOR_MARGIN*2.0,viewport_min_width,maximum)
	if snap or not initialized:
		width=desired_width
		center_x=midpoint
		initialized=true
	else:
		var zoom_time:float=ZOOM_OUT_SECONDS if desired_width>width else ZOOM_IN_SECONDS
		width=lerpf(width,desired_width,1.0-exp(-maxf(delta,0.0)/zoom_time))
		# A gentle center dead-zone avoids reacting to idle/root rounding.
		var target:float=center_x
		if midpoint>center_x+DEAD_ZONE: target=midpoint-DEAD_ZONE
		elif midpoint<center_x-DEAD_ZONE: target=midpoint+DEAD_ZONE
		center_x=lerpf(center_x,target,1.0-exp(-maxf(delta,0.0)/FOLLOW_SECONDS))
	# Visibility outranks easing during sudden separation, crossover and heavy pushback.
	width=maxf(width,desired_width)
	var center_limit:float=maxf(0.0,DECOR_HALF_WIDTH-width*0.5)
	center_x=clampf(center_x,-center_limit,center_limit)
	var safe_left:float=hi+ACTOR_MARGIN-width*0.5
	var safe_right:float=lo-ACTOR_MARGIN+width*0.5
	if safe_left<=safe_right:
		center_x=clampf(center_x,safe_left,safe_right)
	# No pitch/yaw/height tracking: jumps and falling cake use the fixed vertical envelope.
