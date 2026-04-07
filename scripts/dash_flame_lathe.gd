class_name DashFlameLathe
extends RefCounted
## Procedural lathe mesh for the stylized dash flame.
##
## Replaces the old SphereMesh + CylinderMesh composite. The previous attempt
## (hemisphere + power-curve taper) still showed a visible band at the equator
## because the tail was almost cylindrical near the join — and the
## stylized_flame.gdshader bands by dot(NORMAL, VIEW), which is nearly constant
## on a cylinder, producing a hard stripe.
##
## This version uses a single cubic Bezier profile from the tail tip up to the
## dome cap. The whole curve is C-infinity (no piecewise join anywhere), and
## radius varies continuously along the length so the dot(NORMAL, VIEW) gradient
## is smooth top-to-bottom and the shader bands fade cleanly.
##
## Control polygon (revolved around +Y):
##   P0 = (0, -tail_length)              tail tip
##   P1 = (bulge * 1.10, -tail_length*0.55)  pulls width out near the tail
##   P2 = (bulge * 0.95,  dome_radius*0.55)  pulls width back near the dome
##   P3 = (0, dome_radius)               top of dome cap
## P1.x slightly exceeds `bulge` so the widest point sits below the equator,
## giving a teardrop silhouette that matches what the cone+sphere composite
## was approximating with cone.top_radius > sphere.radius.

const _DEFAULT_RADIAL_SEGMENTS: int = 48
const _DEFAULT_PROFILE_SAMPLES: int = 56


static func build(
	bulge_radius: float,
	tail_length: float,
	dome_radius: float,
	radial_segments: int = _DEFAULT_RADIAL_SEGMENTS,
	profile_samples: int = _DEFAULT_PROFILE_SAMPLES
) -> ArrayMesh:
	# Cubic Bezier control points (r, y).
	var p0: Vector2 = Vector2(0.0, -tail_length)
	var p1: Vector2 = Vector2(bulge_radius * 1.10, -tail_length * 0.55)
	var p2: Vector2 = Vector2(bulge_radius * 0.95, dome_radius * 0.55)
	var p3: Vector2 = Vector2(0.0, dome_radius)

	# Sample the profile bottom-to-top. UV.y maps 0 at the tip to 1 at the cap
	# so the noise scrolls along the flame's length.
	var profile_y: PackedFloat32Array = PackedFloat32Array()
	var profile_r: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(profile_samples + 1):
		var t: float = float(i) / float(profile_samples)
		var u: float = 1.0 - t
		var pt: Vector2 = (
			(u * u * u) * p0 + (3.0 * u * u * t) * p1 + (3.0 * u * t * t) * p2 + (t * t * t) * p3
		)
		profile_r.append(maxf(0.0, pt.x))
		profile_y.append(pt.y)

	var ring_count: int = profile_y.size()
	var total_y_span: float = tail_length + dome_radius

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Emit ring vertices.
	for ring: int in range(ring_count):
		var y: float = profile_y[ring]
		var r: float = profile_r[ring]
		var v: float = (y + tail_length) / total_y_span  # 0 at tip, 1 at top
		for seg: int in range(radial_segments + 1):
			var u: float = float(seg) / float(radial_segments)
			var theta: float = u * TAU
			var cs: float = cos(theta)
			var sn: float = sin(theta)
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(r * cs, y, r * sn))

	# Emit triangle indices for the lathe quad strip.
	var verts_per_ring: int = radial_segments + 1
	for ring: int in range(ring_count - 1):
		for seg: int in range(radial_segments):
			var i00: int = ring * verts_per_ring + seg
			var i01: int = i00 + 1
			var i10: int = i00 + verts_per_ring
			var i11: int = i10 + 1
			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i00)
			st.add_index(i11)
			st.add_index(i01)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()
