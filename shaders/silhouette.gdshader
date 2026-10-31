shader_type canvas_item;

// A character hidden behind a building, drawn as a flat tinted silhouette on top.
uniform vec4 tint : source_color = vec4(1.0, 0.35, 0.25, 0.5);

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(tint.rgb, tint.a * step(0.5, a));   // the body only, not the shadow
}
