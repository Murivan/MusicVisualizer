#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;
uniform sampler2D idMap;
uniform float audioEnergy;
uniform float time;
uniform float cycleDuration;
uniform float seedOffset;

varying vec4 vertColor;
varying vec4 vertTexCoord;

// Pseudo-random hash function
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
    
    // Generate a permanent random phase 0.0 - 1.0 unique to this pane and mask seed
    float paneHash = hash(vec3(b, g, r) + vec3(seedOffset));
    float panePhase = paneHash * 6.2831853; // 2 * PI
    
    // Calculate slowly cycling value between 0.0 and 1.0.
    float timePhase = (time / max(0.1, cycleDuration)) * 6.2831853;
    float paneValue = (sin(timePhase + panePhase) + 1.0) * 0.5;
    
    // Pane is fully visible if paneValue < audioEnergy.
    // Soft threshold ensures smooth fades as the sine wave passes the energy level.
    float visibility = smoothstep(audioEnergy + 0.02, audioEnergy - 0.02, paneValue);

    vec4 color = texture2D(texture, vertTexCoord.st) * vertColor;
    color.a *= visibility;

    gl_FragColor = color;
}