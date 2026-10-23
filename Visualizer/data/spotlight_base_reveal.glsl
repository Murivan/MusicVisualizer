#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;
uniform float revealEnergy;
uniform float edgeFeather;
uniform float imageAspect;

varying vec4 vertColor;
varying vec4 vertTexCoord;

void main() {
  vec4 color = texture2D(texture, vertTexCoord.st) * vertColor;
  vec2 offset = vertTexCoord.st - vec2(0.5);
  offset.x *= imageAspect;

  // Squaring energy keeps the visible outer rim thin until the signal becomes stronger.
  float revealAmount = pow(clamp(revealEnergy, 0.0, 1.0), 2.0);
  // The soft edge lies inside the hidden region and shrinks to nothing at full reveal,
  // so the base is hidden at rest and fully visible at maximum energy.
  float innerRadius = (1.0 - revealAmount) * (0.5 + edgeFeather);
  float visibility = smoothstep(innerRadius - edgeFeather, innerRadius, length(offset));
  visibility = visibility * visibility * (3.0 - 2.0 * visibility);
  color.a *= visibility;

  gl_FragColor = color;
}
