class_name CrossMesh
extends RefCounted

# A PLANT AS CROSSED PLANES: `planes` vertical quads through one vertical axis,
# evenly spaced in yaw (four planes = every 45 degrees), each the size of the old
# billboard quad and carrying the whole sprite. Seen from the side it is the sprite
# from any bearing; seen from above it is a star of the sprite's crown instead of
# a line, which is what a camera-facing quad gives a camera that looks down.
#
# A drop-in for the QuadMesh the scatters used to build: same `size`, same
# `center_offset` (the pivot is the plant's base), and the same UVs — (0, 0) top
# left, V running down — so the shader's sway, `1.0 - UV.y` from the base, and the
# U flip read it exactly as they read the quad. Drawn with `billboard` off in
# SHADER_veg_billboard.gdshader, which then takes the instance's yaw instead of
# turning every plant to face the camera.


static func build(size: Vector2, center_offset := Vector3.ZERO, planes := 4) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	for k in planes:
		var a := PI * float(k) / float(planes)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var n := Vector3(-dir.z, 0.0, dir.x)
		var tl := center_offset - dir * hw + Vector3.UP * hh
		var tr := center_offset + dir * hw + Vector3.UP * hh
		var bl := center_offset - dir * hw - Vector3.UP * hh
		var br := center_offset + dir * hw - Vector3.UP * hh
		for v in [[tl, Vector2(0, 0)], [tr, Vector2(1, 0)], [br, Vector2(1, 1)],
				[tl, Vector2(0, 0)], [br, Vector2(1, 1)], [bl, Vector2(0, 1)]]:
			st.set_normal(n)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()
