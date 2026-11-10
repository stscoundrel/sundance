shader_type canvas_item;

// Silencio's flakes (see Snowfall), every one worked out here from where it started
// and how far the wind and the fall have carried everything since, so the script
// only says how far that is. A flake's custom data: x, y, depth (0 far .. 1 near),
// sway phase. Drawn twice from the one MultiMesh: the grey undersides first
// (`underside`), then the flakes. White on white is nothing: the nearer flakes carry
// a grey underside, so they show against the snow on the ground as well as against a
// wall or a man. In a squall they're driven near flat, streaks more than flakes.
uniform vec4 view = vec4(0.0, 0.0, 1280.0, 720.0);   // the world the camera shows, and a margin: x, y, w, h
uniform float drift = 0.0;    // px the wind's carried a flake of depth 0.5 east, all told
uniform float fall = 0.0;     // s of falling, a squall's counting for more
uniform float t = 0.0;        // s: the sway
uniform float streak = 1.0;   // how far a squall draws the near ones out flat
uniform vec2 fall_px = vec2(12.0, 32.0);   // px/s, far to near
uniform bool underside = false;

varying vec4 col;

void vertex() {
	vec4 f = INSTANCE_CUSTOM;
	vec2 at = vec2(f.x + drift * (0.5 + f.z) - cos(t * 1.3 + f.w) * 6.0 / 1.3,
		f.y + fall * mix(fall_px.x, fall_px.y, f.z));
	at = floor(view.xy + mod(at - view.xy, view.zw));
	float s = f.z > 0.6 ? 2.0 : 1.0;
	float w = f.z > 0.35 ? s * streak : s;
	vec2 corner = VERTEX + 0.5;   // (the quad's 0..1)
	if (underside) {
		VERTEX = f.z > 0.35 ? at + vec2(0.0, s) + corner * vec2(w, 1.0) : vec2(0.0);
		col = vec4(0.42, 0.46, 0.56, 0.45 * f.z);
	} else {
		VERTEX = at + corner * vec2(w, s);
		col = vec4(0.94, 0.96, 1.0, mix(0.4, 1.0, f.z));
	}
}

void fragment() {
	COLOR = col;
}
