#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;
uniform vec2 revealCenter;
uniform float revealRadius;
uniform float revealFeather;
uniform float imageAspect;

varying vec4 vertColor;
varying vec4 vertTexCoord;

void main() {
  vec4 color = texture2D(texture, vertTexCoord.st) * vertColor;
  vec2 offset = vertTexCoord.st - revealCenter;
  offset.x *= imageAspect;

  float innerRadius = max(0.0, revealRadius - revealFeather);
  float reveal = 1.0 - smoothstep(innerRadius, revealRadius, length(offset));
  color.a *= reveal;

  gl_FragColor = color;
}
