extends Node3D

const EVENT_PATH := "res://event_data/pythia_event.json"
const DISPLAY_SPEED_MPS := 2.0
const HEAD_RADIUS := 0.05

const TRAIL_SEGMENTS := 24
const TRAIL_MIN_ALPHA := 0.05
const TRAIL_MAX_ALPHA := 0.95

var particles: Array = []
var t := 0.0

var heads_multimesh_instance: MultiMeshInstance3D
var heads_multimesh: MultiMesh


func _ready():
	load_event()
	create_vertex_marker()
	create_beamline()
	setup_camera()
	setup_environment()


func _process(delta):
	t += delta

	if heads_multimesh == null:
		return

	for i in range(particles.size()):
		var p = particles[i]

		var dir: Vector3 = p["dir"]
		var color: Color = p["color"]
		var pos: Vector3 = dir * DISPLAY_SPEED_MPS * t

		# Move particle head
		var xform := Transform3D(Basis(), pos)
		heads_multimesh.set_instance_transform(i, xform)

		# Draw gradient trail from origin to current position
		var mesh: ImmediateMesh = p["trail"]
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

		for s in range(TRAIL_SEGMENTS + 1):
			var u := float(s) / float(TRAIL_SEGMENTS)
			var pt := pos * u

			var brightness_u := pow(u, 2.2)
			var alpha := lerpf(TRAIL_MIN_ALPHA, TRAIL_MAX_ALPHA, brightness_u)

			var c := Color(color.r, color.g, color.b, alpha)
			mesh.surface_set_color(c)
			mesh.surface_add_vertex(pt)

		mesh.surface_end()


func _input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		rotate_y(-event.relative.x * 0.005)
		$Camera3D.rotate_x(-event.relative.y * 0.005)


func load_event():
	var file = FileAccess.open(EVENT_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % EVENT_PATH)
		return

	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON parse failed")
		return

	var data = json.data
	if not data.has("particles"):
		push_error("No particles array in JSON")
		return

	var visible_items: Array = []
	for item in data["particles"]:
		if item.has("visible") and not item["visible"]:
			continue
		visible_items.append(item)

	if visible_items.is_empty():
		push_error("No visible particles found in JSON")
		return

	create_heads_multimesh(visible_items.size())

	for i in range(visible_items.size()):
		var item = visible_items[i]

		var d = item["direction"]
		var dir := Vector3(d["x"], d["y"], d["z"]).normalized()
		var color := Color.html(item["color"])

		heads_multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3.ZERO))
		heads_multimesh.set_instance_color(i, color)

		var trail := MeshInstance3D.new()
		var trail_mesh := ImmediateMesh.new()
		trail.mesh = trail_mesh

		var trail_mat := StandardMaterial3D.new()
		trail_mat.albedo_color = Color.WHITE
		trail_mat.vertex_color_use_as_albedo = true
		trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		trail_mat.no_depth_test = true
		trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = trail_mat

		add_child(trail)

		particles.append({
			"dir": dir,
			"trail": trail_mesh,
			"color": color
		})


func create_heads_multimesh(count: int):
	heads_multimesh_instance = MultiMeshInstance3D.new()
	heads_multimesh = MultiMesh.new()

	heads_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	heads_multimesh.use_colors = true
	heads_multimesh.instance_count = count

	var sphere := SphereMesh.new()
	sphere.radius = HEAD_RADIUS
	sphere.height = 2.0 * HEAD_RADIUS

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = mat

	heads_multimesh.mesh = sphere
	heads_multimesh_instance.multimesh = heads_multimesh

	add_child(heads_multimesh_instance)


func create_vertex_marker():
	var marker := MeshInstance3D.new()

	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	marker.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat

	marker.position = Vector3.ZERO
	add_child(marker)


func create_beamline():
	var beam := MeshInstance3D.new()

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 100.0
	beam.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.8, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.8, 0.8)
	mat.emission_energy_multiplier = 0.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = mat

	# CylinderMesh points along Y by default; rotate so beam lies along Z
	beam.rotation_degrees.x = 90.0
	beam.position = Vector3.ZERO

	add_child(beam)


func setup_camera():
	var cam := $Camera3D
	cam.position = Vector3(12.0, 12.0, 0.0)
	cam.look_at(Vector3.ZERO, Vector3.UP)


func setup_environment():
	if has_node("WorldEnvironment"):
		var env_node: WorldEnvironment = $WorldEnvironment

		if env_node.environment == null:
			env_node.environment = Environment.new()

		var env: Environment = env_node.environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.BLACK

		env.glow_enabled = true
		env.glow_intensity = 0.8
		env.glow_strength = 1.2
		env.glow_bloom = 0.2
