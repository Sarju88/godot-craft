shader_type canvas_item;
render_mode unshaded;

uniform sampler2D front : filter_linear, repeat_disable;
uniform sampler2D left_face : filter_linear, repeat_disable;
uniform sampler2D back : filter_linear, repeat_disable;
uniform sampler2D right_face : filter_linear, repeat_disable;
uniform sampler2D top : filter_linear, repeat_disable;
uniform sampler2D bottom : filter_linear, repeat_disable;
uniform float yaw = 0.0;

vec4 sample_panorama(vec3 direction) {
	vec3 axes = abs(direction);
	if (axes.y >= max(axes.x, axes.z)) {
		if (direction.y > 0.0) {
			return texture(top, vec2(direction.x, direction.z) / axes.y * 0.5 + 0.5);
		}
		return texture(bottom, vec2(direction.x, -direction.z) / axes.y * 0.5 + 0.5);
	}
	if (axes.x >= axes.z) {
		if (direction.x > 0.0) {
			return texture(right_face, vec2(direction.z, -direction.y) / axes.x * 0.5 + 0.5);
		}
		return texture(left_face, vec2(-direction.z, -direction.y) / axes.x * 0.5 + 0.5);
	}
	if (direction.z < 0.0) {
		return texture(front, vec2(direction.x, -direction.y) / axes.z * 0.5 + 0.5);
	}
	return texture(back, vec2(-direction.x, -direction.y) / axes.z * 0.5 + 0.5);
}

void fragment() {
	vec2 frame = UV * 2.0 - 1.0;
	frame.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec3 ray = vec3(frame.x * 0.60, -frame.y * 0.60 + 0.11, -1.0);
	float c = cos(yaw);
	float s = sin(yaw);
	vec3 view = vec3(c * ray.x + s * ray.z, ray.y, -s * ray.x + c * ray.z);
	COLOR = vec4(sample_panorama(view).rgb, 1.0);
}
