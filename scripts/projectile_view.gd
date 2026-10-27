extends Node3D
## Presentation only. Combat owns trajectories, lifetime and damage.
var views: Dictionary = {}
var depths: Dictionary = {}
var heart_mesh: ArrayMesh
var peach_scene: PackedScene
var cake_scene: PackedScene
var warnings:Dictionary={}
var font: Font

func _ready() -> void:
	font = load("res://assets/ui_font.otf")
	heart_mesh = make_heart_mesh()
	peach_scene = load("res://assets/peach.glb")
	if ResourceLoader.exists("res://assets/cake.glb"): cake_scene=load("res://assets/cake.glb")

func note_emission(id: int, depth: float) -> void:
	depths[id] = depth

func sync_projectiles(projectiles: Array) -> void:
	var alive: Dictionary = {}
	for p: Dictionary in projectiles:
		var id: int = p.id
		alive[id] = true
		if not views.has(id):
			var node: Node3D
			if p.kind == "meow":
				var label := Label3D.new()
				label.text = "喵"
				label.font = font
				label.font_size = 96
				label.pixel_size = 0.005
				label.outline_size = 12
				label.modulate = Color("f1d8ff")
				label.outline_modulate = Color("392447")
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.no_depth_test = false
				node = label
			elif p.kind == "heart":
				var mesh := MeshInstance3D.new()
				mesh.mesh = heart_mesh
				var material := StandardMaterial3D.new()
				material.albedo_color = Color("f284bd")
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.vertex_color_use_as_albedo = true
				mesh.material_override = material
				node = mesh
			elif p.kind=="cake":
				node=cake_scene.instantiate() if cake_scene else Node3D.new()
			elif p.kind == "peach":
				node = peach_scene.instantiate()
			else:
				var mesh:=MeshInstance3D.new();var shape:=BoxMesh.new()
				shape.size=Vector3(0.22,0.055,0.055);mesh.mesh=shape
				var material:=StandardMaterial3D.new();material.albedo_color=Color("b9e9ff")
				material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mesh.material_override=material;node=mesh
			add_child(node)
			views[id] = node
		var pos: Vector2 = p.pos
		views[id].position = Vector3(pos.x, pos.y, float(depths.get(id, 0.15)))
		# Neither letters nor hearts inherit fighter facing or a negative scale.
		views[id].scale = Vector3.ONE
	for id in views.keys():
		if not alive.has(id):
			views[id].queue_free()
			views.erase(id)
			depths.erase(id)

func sync_cake_warnings(items:Array) -> void:
	var alive:Dictionary={}
	for item:Dictionary in items:
		var id:int=item.id
		alive[id]=true
		if not warnings.has(id):
			var ring:=MeshInstance3D.new();var mesh:=TorusMesh.new()
			mesh.inner_radius=0.23;mesh.outer_radius=0.29;mesh.rings=24;mesh.ring_segments=6
			ring.mesh=mesh
			var material:=StandardMaterial3D.new();material.albedo_color=Color("ffb45b")
			material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			ring.material_override=material;add_child(ring);warnings[id]=ring
		warnings[id].position=Vector3(float(item.x),0.025,0.0)
		warnings[id].scale=Vector3(1,0.15,1)
	for id in warnings.keys():
		if not alive.has(id): warnings[id].queue_free();warnings.erase(id)

func clear() -> void:
	for node in warnings.values():
		if is_instance_valid(node): node.queue_free()
	warnings.clear()
	for node in views.values():
		if is_instance_valid(node): node.queue_free()
	views.clear()
	depths.clear()

func make_heart_mesh() -> ArrayMesh:
	var polygon := PackedVector2Array([
		Vector2(0,-0.25),Vector2(0.25,-0.01),Vector2(0.29,0.12),
		Vector2(0.23,0.23),Vector2(0.11,0.25),Vector2(0,0.14),
		Vector2(-0.11,0.25),Vector2(-0.23,0.23),Vector2(-0.29,0.12),Vector2(-0.25,-0.01)])
	var triangles := Geometry2D.triangulate_polygon(polygon)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		for t in range(0,triangles.size(),3):
			for j in ([2,1,0] if side<0 else [0,1,2]):
				var v: Vector2=polygon[triangles[t+j]]
				surface.set_color(Color.WHITE if side>0 else Color(0.76,0.62,0.74))
				surface.add_vertex(Vector3(v.x,v.y,side*0.055))
	for i in range(polygon.size()):
		var a: Vector2=polygon[i]
		var b: Vector2=polygon[(i+1)%polygon.size()]
		for v in [Vector3(a.x,a.y,-0.055),Vector3(b.x,b.y,-0.055),Vector3(b.x,b.y,0.055),Vector3(a.x,a.y,-0.055),Vector3(b.x,b.y,0.055),Vector3(a.x,a.y,0.055)]:
			surface.set_color(Color(0.78,0.64,0.75))
			surface.add_vertex(v)
	surface.generate_normals()
	return surface.commit()
