shader_type canvas_item;

// Palette swap for characters. Recolourable parts are baked in neutral grey and a
// second texture (same atlas layout) says which palette slot each pixel belongs to.
// The grey carries the shading, so slot colour x (grey / neutral) keeps the light.
uniform sampler2D slots : filter_nearest;
uniform vec3 pal[16];
uniform float neutral = 0.784;
// Nothing drawn below this (world y): a hanged man's legs, down through the trap.
uniform float clip_y = 1e9;
// Snow settled on him (a body lying out in Silencio's: see Drifts), 0..1: patchy on
// the lit parts first, then all of him under it, a drift the shape of him.
uniform float snow = 0.0;

varying vec4 tint;
varying float world_y;

void vertex() {
	tint = COLOR;   // modulate (hit flash)
	world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

float hash(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
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
	if (snow > 0.0) {
		float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		vec2 p = UV * vec2(textureSize(TEXTURE, 0)) / 7.0;   // (patches a few pixels across)
		vec2 i = floor(p);
		vec2 f = smoothstep(0.0, 1.0, fract(p));
		float n = mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
		float w = n * 0.7 + (1.0 - lum) * 0.3;   // (the lit tops catch it first)
		float cover = smoothstep(w - 0.08, w + 0.08, snow * 1.15);
		vec3 drift = vec3(0.92, 0.94, 0.98) * mix(0.8, 1.0, clamp(lum * 1.6, 0.0, 1.0));
		c.rgb = mix(mix(c.rgb, drift, snow * 0.25), drift, cover);   // (a frosting all over, and the drifts)
	}
	COLOR = c * tint;
}
