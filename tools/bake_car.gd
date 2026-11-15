extends SceneTree
## One-off tool: bakes a car model into a copy that draws in a handful of calls instead of 50-80.
##
##   godot --headless --path . --script res://tools/bake_car.gd -- <in.gltf> <out.tscn>
##   Run it, then `godot --headless --import`, then run it again: the first run writes the atlas
##   PNGs, the second (after they are imported) writes the scene. The output is deterministic.
##
## Every part is merged into one mesh per material setting, with its colour and metallic/roughness
## textures packed into two atlases with the same layout, EXCEPT what car_model.gd animates or
## repaints at runtime: wheels, siren lenses and PAINT_MATERIALS surfaces, plus surfaces whose UVs
## really tile. Node names and hierarchy are kept, so car_model.gd finds wheels and sirens as before.

const CarModel = preload("res://car_model.gd")
const PAD: int = 4          # texels of edge-extended border round each atlas tile (no bleeding)
const MAX_SIZE: int = 4096


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("usage: -- <in model> <out.tscn>")
		quit(1)
		return
	quit(bake(args[0], args[1]))


func bake(in_path: String, out_path: String) -> int:
	var root: Node3D = (load(in_path) as PackedScene).instantiate() as Node3D
	var named: Dictionary = CarModel._find_named(root)
	var skip: Array = []      # sirens: left alone (car_model.gd flashes their materials)
	var wheels: Array = []    # each wheel node gets its own merged mesh, so it still spins and steers
	for k in named:
		if String(k).begins_with("wheel"):
			wheels.append_array(named[k])
		else:
			skip.append_array(named[k])

	# 1) pick the parts to merge (a part is merged whole or left exactly as it is)
	var entries: Array = []      # {arrays, xf, mat, tile, holder}
	var tiles: Array = []        # [colour Image, metal/rough Image], both padded, same size
	var tile_of: Dictionary = {}
	var kept: int = 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null or CarModel._under(mi, skip):
			continue
		var holder: Node3D = root   # the node the merged mesh hangs under: a wheel, or the model root
		for wn in wheels:
			if CarModel._under(mi, [wn]):
				holder = wn
		var all_ok: bool = true
		for si in range(mi.mesh.get_surface_count()):
			if not _mergeable(mi.mesh, si, mi.get_active_material(si), mi.mesh.surface_get_arrays(si)):
				all_ok = false
		if not all_ok:
			kept += mi.mesh.get_surface_count()
			continue
		var xf: Transform3D = CarModel._rel(mi, holder)
		for si in range(mi.mesh.get_surface_count()):
			var mat: StandardMaterial3D = mi.get_active_material(si)
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
				arrays[c] = null   # unused by StandardMaterial3D (copying them would need format flags)
			var key: Array = [mat.albedo_texture, mat.albedo_color, _mr_tex(mat)]
			if not tile_of.has(key):
				tile_of[key] = tiles.size()
				tiles.append(_tiles_for(mat))
			entries.append({"arrays": arrays, "xf": xf, "mat": mat, "tile": tile_of[key], "holder": holder})
		mi.mesh = null   # node kept (it may parent other parts); its geometry now lives in BakedBody

	# 2) pack (shelf packing, tallest first) into a colour atlas and a matching metal/rough atlas
	var order: Array = range(tiles.size())
	order.sort_custom(func(a, b): return (tiles[a][0] as Image).get_height() > (tiles[b][0] as Image).get_height())
	var area: int = 0
	for t in tiles:
		area += (t[0] as Image).get_width() * (t[0] as Image).get_height()
	# no power-of-two rounding (Godot 4 doesn't need it; rounding would waste up to half the memory)
	var widest: int = 0
	for t in tiles:
		widest = maxi(widest, (t[0] as Image).get_width())
	var w: int = mini(MAX_SIZE, _up4(maxi(widest, int(ceil(sqrt(float(area) * 1.1))))))
	var pos: Dictionary = {}
	var x: int = 0
	var y: int = 0
	var shelf: int = 0
	for t in order:
		var im: Image = tiles[t][0]
		if x + im.get_width() > w:
			x = 0
			y += shelf
			shelf = 0
		pos[t] = Vector2i(x, y)
		x += im.get_width()
		shelf = maxi(shelf, im.get_height())
	var h: int = _up4(y + shelf)
	if h > MAX_SIZE:
		push_error("atlas would be %dx%d, over %d" % [w, h, MAX_SIZE])
		return 1
	var pngs: Array = [out_path.get_basename() + "_atlas.png", out_path.get_basename() + "_atlas_mr.png"]
	for a in range(2):
		var atlas := Image.create(w, h, false, Image.FORMAT_RGBA8)
		atlas.fill(Color.WHITE)
		for t in order:
			var im: Image = tiles[t][a]
			atlas.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), pos[t])
		if a == 1:   # metal/rough is near-flat per part: half resolution is plenty (same UVs)
			atlas.resize(w / 2, h / 2, Image.INTERPOLATE_BILINEAR)
		atlas.save_png(pngs[a])
	if not (ResourceLoader.exists(pngs[0]) and ResourceLoader.exists(pngs[1])):
		print("[bake] wrote the atlases (%dx%d). Run `godot --headless --import`, then this tool again." % [w, h])
		return 0
	var tex: Texture2D = load(pngs[0])
	var tex_mr: Texture2D = load(pngs[1])

	# 3) one merged surface per material setting, UVs moved into each part's tile
	var mats: Dictionary = {}     # setting key -> shared baked material
	var groups: Dictionary = {}   # [holder, setting key] -> {st, mat, holder}
	for e in entries:
		var m: StandardMaterial3D = e["mat"]
		var sk: String = _setting_key(m)
		var gk: Array = [e["holder"], sk]
		if not mats.has(sk):
			var gm: StandardMaterial3D = m.duplicate()
			gm.resource_name = "baked_%d" % mats.size()
			gm.albedo_texture = tex
			gm.albedo_color = Color(1, 1, 1, m.albedo_color.a)
			gm.metallic_texture = tex_mr
			gm.roughness_texture = tex_mr
			gm.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE   # glTF metal/rough layout,
			gm.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN # rebuilt that way in _tiles_for
			mats[sk] = gm
		if not groups.has(gk):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[gk] = {"st": st, "mat": mats[sk], "holder": e["holder"]}
		var arrays: Array = e["arrays"]
		var src: Image = tiles[e["tile"]][0]
		var p: Vector2i = pos[e["tile"]]
		var inner := Vector2(src.get_width() - PAD * 2, src.get_height() - PAD * 2)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		if uv.is_empty():   # no UVs: every vertex samples the middle of its (flat) tile
			uv.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			uv.fill(Vector2(0.5, 0.5))
		for i in range(uv.size()):
			uv[i] = (Vector2(p) + Vector2(PAD, PAD) + uv[i] * inner) / Vector2(w, h)
		arrays[Mesh.ARRAY_TEX_UV] = uv
		var one := ArrayMesh.new()
		one.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		(groups[gk]["st"] as SurfaceTool).append_from(one, 0, e["xf"])
	var baked: Dictionary = {}    # holder -> ArrayMesh
	for gk in groups:
		var hn: Node3D = groups[gk]["holder"]
		if not baked.has(hn):
			baked[hn] = ArrayMesh.new()
		(groups[gk]["st"] as SurfaceTool).commit(baked[hn])
		(baked[hn] as ArrayMesh).surface_set_material((baked[hn] as ArrayMesh).get_surface_count() - 1, groups[gk]["mat"])
	var draws: int = 0
	for hn in baked:
		var mi := MeshInstance3D.new()
		mi.name = "BakedBody" if hn == root else "BakedWheel"
		mi.mesh = baked[hn]
		hn.add_child(mi)
		mi.owner = root
		draws += (baked[hn] as ArrayMesh).get_surface_count()

	var ps := PackedScene.new()
	var err: int = ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, out_path)
	print("[bake] %s -> %s: %d parts merged into %d draws, %d kept as they were (+ wheels/sirens), atlas %dx%d, err=%d" % [in_path, out_path, entries.size(), draws, kept, w, h, err])
	root.free()
	return err


## Plain triangle surfaces with colour (+ optional glTF metal/rough) textures and UVs that stay
## inside the texture, give or take what the tile border covers.
func _mergeable(mesh: Mesh, si: int, mat: Material, arrays: Array) -> bool:
	if not (mat is StandardMaterial3D) or mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
		return false
	var m: StandardMaterial3D = mat
	if CarModel._is_listed_paint(m) or m.uv1_scale != Vector3.ONE or m.uv1_offset != Vector3.ZERO or m.uv1_triplanar:
		return false
	if m.normal_enabled or m.detail_enabled or m.emission_texture != null or m.ao_enabled or m.heightmap_enabled:
		return false
	if m.metallic_texture != m.roughness_texture and m.metallic_texture != null and m.roughness_texture != null:
		return false   # separate metal and rough maps: not the glTF layout this tool rebuilds
	if m.metallic_texture != null and (m.metallic_texture_channel != BaseMaterial3D.TEXTURE_CHANNEL_BLUE or m.roughness_texture_channel != BaseMaterial3D.TEXTURE_CHANNEL_GREEN):
		return false
	if arrays[Mesh.ARRAY_BONES] != null or mesh.get_blend_shape_count() > 0:
		return false
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		var size: Vector2 = Vector2(m.albedo_texture.get_size()) if m.albedo_texture != null else Vector2(4, 4)
		var slack: Vector2 = Vector2(PAD - 1, PAD - 1) / size   # overshoot the border can absorb
		for u in (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array):
			if u.x < -slack.x or u.x > 1.0 + slack.x or u.y < -slack.y or u.y > 1.0 + slack.y:
				return false
	return true


func _up4(v: int) -> int:
	return (v + 3) / 4 * 4


func _mr_tex(m: StandardMaterial3D) -> Texture2D:
	return m.metallic_texture if m.metallic_texture != null else m.roughness_texture


## Everything about a material except its textures: parts sharing it can share one draw.
func _setting_key(m: StandardMaterial3D) -> String:
	return "%d|%d|%d|%d|%.3f|%.3f|%.3f|%.3f|%s|%s|%.3f|%d|%d|%s|%.3f" % [m.transparency, m.cull_mode, m.shading_mode, m.blend_mode,
		m.metallic, m.roughness, m.metallic_specular, m.alpha_scissor_threshold, m.emission_enabled, m.emission,
		m.emission_energy_multiplier, m.texture_filter, m.depth_draw_mode, m.vertex_color_use_as_albedo, m.albedo_color.a]


## [colour tile, metal/rough tile] for one material, same size, PAD-texel border copied from the edges.
## Colour = texture x albedo colour (alpha kept in the material). Metal/rough = the glTF map
## (B = metal, G = rough), or white when the material has none (white x scalar = the scalar).
func _tiles_for(m: StandardMaterial3D) -> Array:
	var col: Image = _img(m.albedo_texture)
	var tint := Color(m.albedo_color.r, m.albedo_color.g, m.albedo_color.b, 1.0)
	if tint != Color.WHITE:
		for yy in range(col.get_height()):
			for xx in range(col.get_width()):
				col.set_pixel(xx, yy, col.get_pixel(xx, yy) * tint)
	var mr: Image = _img(_mr_tex(m))
	if mr.get_size() != col.get_size():
		mr.resize(col.get_width(), col.get_height(), Image.INTERPOLATE_BILINEAR)
	return [_padded(col), _padded(mr)]


func _img(tex: Texture2D) -> Image:
	var src: Image
	if tex == null:
		src = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		src.fill(Color.WHITE)
		return src
	src = tex.get_image().duplicate()
	if src.is_compressed():
		src.decompress()
	src.clear_mipmaps()
	src.convert(Image.FORMAT_RGBA8)
	return src


func _padded(src: Image) -> Image:
	var sw: int = src.get_width()
	var sh: int = src.get_height()
	var out := Image.create(sw + PAD * 2, sh + PAD * 2, false, Image.FORMAT_RGBA8)
	for yy in range(sh + PAD * 2):
		for xx in range(sw + PAD * 2):
			out.set_pixel(xx, yy, src.get_pixel(clampi(xx - PAD, 0, sw - 1), clampi(yy - PAD, 0, sh - 1)))
	return out
