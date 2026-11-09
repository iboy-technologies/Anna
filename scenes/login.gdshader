shader_type canvas_item;

uniform sampler2D tex;
uniform vec4 color = vec4(0.90);

void fragment() {
    vec4 tex1 = texture(tex, UV);
    COLOR = tex1 * color;
}
