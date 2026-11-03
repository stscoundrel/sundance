shader_type canvas_item;

// Palette swap for characters. Recolourable parts are baked in neutral grey and a
// second texture (same atlas layout) says which palette slot each pixel belongs to.
// The grey carries the shading, so slot colour x (grey / neutral) keeps the light.
uniform sampler2D slots : filter_nearest;
uniform vec3 pal[16];
uniform float neutral = 0.784;
// Nothing drawn below this (world y): a hanged man's legs, down through the trap.
uniform float clip_y = 1e9;

varying vec4 tint;
varying float world_y;

void vertex() {
	tint = COLOR;   // modulate (hit flash)
	world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

void fragment() {
	if (world_y > clip_y) {
		discard;
	}
	vec4 c = texture(TEXTURE, UV);
	int s = int(texture(slots, UV).r * 255.0 + 0.5);
	if (s > 0 && s < 16) {
		c.rgb = pal[s] * (c.rgb / neutral);
	}
	COLOR = c * tint;
}
