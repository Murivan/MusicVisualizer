#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;
uniform sampler2D idMap;
uniform float audioEnergy;
uniform float shuffleSeed;

varying vec4 vertColor;
varying vec4 vertTexCoord;

// Pseudo-random hash function based on fractional parts of sines
float hash(vec3 p) {
    return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}

void main() {
    // Look up the shape ID from the RGB channels (encoded by OpenCV)
    vec4 idColor = texture2D(idMap, vertTexCoord.st);
    
    // idColor in GLSL is 0.0 to 1.0. Multiply by 255 to recover the integer ID components
    float b = floor(idColor.b * 255.0 + 0.5);
    float g = floor(idColor.g * 255.0 + 0.5);
    float r = floor(idColor.r * 255.0 + 0.5);
    
    // If the ID is exactly 0 (the black background space), we remain completely transparent
    if (b == 0.0 && g == 0.0 && r == 0.0) {
        gl_FragColor = vec4(0.0);
        return;
    }
    
    // Generate a pseudo-random activation threshold unique to this pane and current shuffle seed
    float paneThreshold = hash(vec3(b, g, r) + vec3(shuffleSeed));
    
    // Display the underlying original color pixel only if its pane is "active" for the current audio level
    vec4 color = texture2D(texture, vertTexCoord.st) * vertColor;
    
    // We can fade softly into existence instead of binary cutoffs using smoothstep
    float visibility = smoothstep(paneThreshold - 0.05, paneThreshold + 0.05, audioEnergy);
    color.a *= visibility;
    
    gl_FragColor = color;
}