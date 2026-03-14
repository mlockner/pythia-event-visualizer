extends Node3D

const EVENT_PATHS := [
	"res://event_data/pythia_event_1.json",
	"res://event_data/pythia_event_2.json",
	"res://event_data/pythia_event_3.json",
	"res://event_data/pythia_event_4.json",
	"res://event_data/pythia_event_5.json",
]

const EVENT_DURATION := 10.0

const DISPLAY_SPEED_MPS := 2.0
const HEAD_RADIUS := 0.05

const HALO_RADIUS := 0.10
const HALO_EMISSION := 1.5
const HALO_ALPHA := 0.28

const TRAIL_SEGMENTS := 24
const TRAIL_MIN_ALPHA := 0.03
const TRAIL_MAX_ALPHA := 0.55
const TRAIL_ALPHA_EXPONENT := 2.4

const TRAIL_MIN_WIDTH := 0.015
const TRAIL_MAX_WIDTH := 0.08
const TRAIL_WIDTH_EXPONENT := 3.0

const CAMERA_AUTO_YAW_SPEED := 0.15
const CAMERA_PITCH_MIN := -1.2
const CAMERA_PITCH_MAX := 0.2

var particles: Array = []
var t := 0.0

var current_event_index: int = 0
var event_timer: float = 0.0
var event_label: Label

var heads_multimesh_instance: MultiMeshInstance3D
var heads_multimesh: MultiMesh
var halos_multimesh_instance: MultiMeshInstance3D
var halos_multimesh: MultiMesh
var main_camera: Camera3D

var camera_yaw_rig: Node3D
var camera_pitch_rig: Node3D

var camera_yaw := 0.0
var camera_pitch := -0.65


func _ready() -> void:
	setup_camera()
	setup_environment()
	create_vertex_marker()
	create_beamline()
	create_event_label()
	load_event_from_path(EVENT_PATHS[current_event_index])

func _process(delta: float) -> void:
	t = min(t + delta, 10.0)
	event_timer += delta

	if event_timer >= EVENT_DURATION:
		advance_to_next_event()

	camera_yaw += delta * CAMERA_AUTO_YAW_SPEED
	camera_yaw_rig.rotation.y = camera_yaw
	camera_pitch_rig.rotation.x = camera_pitch

	if heads_multimesh == null:
		return
	if main_camera == null:
		return

	for i in range(particles.size()):
		var p: Dictionary = particles[i]
		var dir: Vector3 = p["dir"]
		var color: Color = p["color"]
		var pos: Vector3 = dir * DISPLAY_SPEED_MPS * t

		var xform: Transform3D = Transform3D(Basis(), pos)
		heads_multimesh.set_instance_transform(i, xform)
		halos_multimesh.set_instance_transform(i, xform)

		var mesh: ImmediateMesh = p["trail"]
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

		var trail_dir: Vector3 = dir.normalized()

		for s in range(TRAIL_SEGMENTS + 1):
			var u: float = float(s) / float(TRAIL_SEGMENTS)
			var pt: Vector3 = pos * u

			var to_cam: Vector3 = (main_camera.position - pt).normalized()
			var side: Vector3 = trail_dir.cross(to_cam)
			if side.length_squared() < 1e-8:
				side = trail_dir.cross(Vector3.UP)
			if side.length_squared() < 1e-8:
				side = trail_dir.cross(Vector3.RIGHT)
			side = side.normalized()

			var brightness_u: float = pow(u, TRAIL_ALPHA_EXPONENT)
			var flare_u: float = pow(u, 6.0)
			var alpha: float = lerpf(TRAIL_MIN_ALPHA, TRAIL_MAX_ALPHA, brightness_u) + 0.15 * flare_u
			alpha = clamp(alpha, 0.0, 1.0)

			var width_u: float = pow(u, TRAIL_WIDTH_EXPONENT)
			var half_width: float = 0.5 * lerpf(TRAIL_MIN_WIDTH, TRAIL_MAX_WIDTH, width_u)

			var c: Color = Color(color.r, color.g, color.b, alpha)

			mesh.surface_set_color(c)
			mesh.surface_add_vertex(pt - side * half_width)

			mesh.surface_set_color(c)
			mesh.surface_add_vertex(pt + side * half_width)

		mesh.surface_end()


func _input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		camera_yaw -= event.relative.x * 0.005
		camera_pitch -= event.relative.y * 0.005
		camera_pitch = clamp(camera_pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)

		camera_yaw_rig.rotation.y = camera_yaw
		camera_pitch_rig.rotation.x = camera_pitch

func particle_color_from_pid(pid: int) -> Color:
	var apid : int = abs(pid)

	# photon
	if pid == 22:
		return Color(1.0, 1.0, 0.0)  # yellow

	# electron / positron
	elif apid == 11:
		return Color(0.0, 1.0, 0.0)  # green

	# muon
	elif apid == 13:
		return Color(0.0, 1.0, 1.0)  # cyan

	# tau
	elif apid == 15:
		return Color(0.3, 0.9, 0.9)  # pale cyan

	# neutrinos
	elif apid in [12, 14, 16]:
		return Color(0.1, 0.1, 0.4)  # dark blue

	# pions
	elif apid in [211, 111]:
		return Color(1.0, 0.0, 0.0)  # red

	# kaons
	elif apid in [321, 130, 310]:
		return Color(1.0, 0.5, 0.0)  # orange

	# baryons
	elif apid in [2212, 2112, 3122]:
		return Color(1.0, 0.0, 1.0)  # magenta

	# default
	else:
		return Color(0.65, 0.65, 0.65)  # gray
		

func load_event_from_path(event_path: String) -> void:
	clear_current_event()

	var file: FileAccess = FileAccess.open(event_path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % event_path)
		return

	var text: String = file.get_as_text()
	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		push_error("JSON parse failed for %s" % event_path)
		return

	var data: Variant = json.data
	if not data.has("particles"):
		push_error("No particles array in JSON for %s" % event_path)
		return

	var visible_items: Array = []
	for item in data["particles"]:
		if item.has("visible") and not item["visible"]:
			continue
		visible_items.append(item)

	if visible_items.is_empty():
		push_error("No visible particles found in %s" % event_path)
		return

	create_heads_multimesh(visible_items.size())
	create_halos_multimesh(visible_items.size())

	for i in range(visible_items.size()):
		var item: Dictionary = visible_items[i]
		var d: Dictionary = item["direction"]
		var dir: Vector3 = Vector3(d["x"], d["y"], d["z"]).normalized()
		var pid: int = int(item["pid"])
		var color: Color = particle_color_from_pid(pid)

		heads_multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3.ZERO))
		heads_multimesh.set_instance_color(i, color)

		halos_multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3.ZERO))
		halos_multimesh.set_instance_color(i, Color(color.r, color.g, color.b, HALO_ALPHA))

		var trail: MeshInstance3D = MeshInstance3D.new()
		var trail_mesh: ImmediateMesh = ImmediateMesh.new()
		trail.mesh = trail_mesh

		var trail_shader: Shader = Shader.new()
		trail_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * COLOR.a * 2.0;
	ALPHA = COLOR.a;
}
"""

		var trail_mat: ShaderMaterial = ShaderMaterial.new()
		trail_mat.shader = trail_shader
		trail.material_override = trail_mat

		add_child(trail)

		particles.append({
			"dir": dir,
			"trail": trail_mesh,
			"trail_node": trail,
			"color": color
		})

	update_event_label()
	t = 0.0
	event_timer = 0.0


func advance_to_next_event() -> void:
	current_event_index = (current_event_index + 1) % EVENT_PATHS.size()
	load_event_from_path(EVENT_PATHS[current_event_index])


func clear_current_event() -> void:
	for p in particles:
		var particle_dict: Dictionary = p
		if particle_dict.has("trail_node"):
			var trail_node: MeshInstance3D = particle_dict["trail_node"]
			if is_instance_valid(trail_node):
				trail_node.queue_free()

	particles.clear()

	if heads_multimesh_instance != null and is_instance_valid(heads_multimesh_instance):
		heads_multimesh_instance.queue_free()
		heads_multimesh_instance = null
		heads_multimesh = null

	if halos_multimesh_instance != null and is_instance_valid(halos_multimesh_instance):
		halos_multimesh_instance.queue_free()
		halos_multimesh_instance = null
		halos_multimesh = null


func create_event_label() -> void:
	var canvas_layer: CanvasLayer = CanvasLayer.new()
	add_child(canvas_layer)

	event_label = Label.new()
	event_label.text = ""
	event_label.position = Vector2(20, 180)
	event_label.add_theme_font_size_override("font_size", 26)
	event_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

	canvas_layer.add_child(event_label)
	update_event_label()


func update_event_label() -> void:
	if event_label == null:
		return

	event_label.text = "Event %d / %d" % [current_event_index + 1, EVENT_PATHS.size()]


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


func create_halos_multimesh(count: int):
	halos_multimesh_instance = MultiMeshInstance3D.new()
	halos_multimesh = MultiMesh.new()

	halos_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	halos_multimesh.use_colors = true
	halos_multimesh.instance_count = count

	var sphere := SphereMesh.new()
	sphere.radius = HALO_RADIUS
	sphere.height = 2.0 * HALO_RADIUS

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = HALO_EMISSION
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	sphere.material = mat

	halos_multimesh.mesh = sphere
	halos_multimesh_instance.multimesh = halos_multimesh

	add_child(halos_multimesh_instance)


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


func create_detector():
	create_detector_layer(0.15, 40.0, Color(0.7, 0.7, 0.7), 0.15) # beam pipe
	create_detector_layer(2.0, 40.0, Color(0.3, 0.8, 1.0), 0.10)  # tracker
	create_detector_layer(4.0, 40.0, Color(1.0, 0.6, 0.2), 0.08)  # calorimeter


func create_detector_layer(radius: float, length: float, color: Color, alpha: float):

	var cyl := MeshInstance3D.new()

	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length

	cyl.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = color * 0.3

	cyl.material_override = mat

	# Cylinder axis is Y, rotate to align with beamline (Z)
	cyl.rotation_degrees.x = 90.0

	add_child(cyl)
	

func setup_camera():
	camera_yaw_rig = $CameraYawRig
	camera_pitch_rig = $CameraYawRig/CameraPitchRig
	main_camera = $CameraYawRig/CameraPitchRig/Camera3D

	camera_yaw_rig.position = Vector3.ZERO
	camera_pitch_rig.position = Vector3.ZERO

	camera_yaw = 90.0
	camera_pitch = -0.65

	camera_yaw_rig.rotation.y = camera_yaw
	camera_pitch_rig.rotation.x = camera_pitch

	main_camera.position = Vector3(0.0, 0.0, 22.0)
	main_camera.look_at(Vector3.ZERO, Vector3.UP)


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
