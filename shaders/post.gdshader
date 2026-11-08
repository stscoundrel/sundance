shader_type canvas_item;

// Warm spaghetti-western grade, vignette and film grain over the world.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float time_s = 0.0;
uniform float hurt = 0.0;
uniform float desat = 0.0;
uniform vec2 grain = vec2(640.0, 360.0);   // grain cells across the screen: a HUD pixel each
// The grade itself: the desert sun by default; a map's weather sets its own (snow:
// cold, flat and pale under cloud).
uniform vec3 tint = vec3(1.06, 0.99, 0.86);
uniform float sat = 0.86;
uniform float contrast = 1.08;
uniform float lift = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	c *= tint;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat * (1.0 - desat));
	c = (c - 0.5) * contrast + 0.5;
	c = c * (1.0 - lift) + lift;
	c = mix(c, c * vec3(0.95, 0.92, 1.0), smoothstep(0.5, 0.0, l) * 0.3);
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - dot(d * vec2(1.0, 1.25), d * vec2(1.0, 1.25)) * 1.1;
	vec2 px = floor(SCREEN_UV * grain);
	float n = fract(sin(dot(px + floor(time_s * 12.0) * 17.0, vec2(12.9898, 78.233))) * 43758.5453);
	c += (n - 0.5) * 0.04;
	c = mix(c, vec3(0.7, 0.05, 0.03), hurt * 0.35 * (0.4 + length(d) * 1.6));
	COLOR = vec4(c, 1.0);
}
