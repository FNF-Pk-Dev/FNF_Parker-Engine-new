package shaders;

import flixel.system.FlxAssets.FlxShader;

class CoolShader extends FlxShader
{
	@:glFragmentSource('
		#pragma header

		uniform float uTime;
		uniform vec3 uColor;

		void main()
		{
			vec2 uv = openfl_TextureCoordv;
			
			// Glitch: Horizontal Displacement
			// Random-ish jitter based on time and Y position
			float jitter = step(0.9, sin(uTime * 20.0 + uv.y * 50.0)) * 0.01 * sin(uTime);
			uv.x += jitter;
			
			vec4 tex = flixel_texture2D(bitmap, uv);
			
			// FORCE COLOR: Ignore texture RGB, use uColor directly
			// This ensures the border is ALWAYS the correct color, never white
			vec3 baseColor = uColor;
			
			// --- EFFECTS ---
			
			// 1. Noise / Grain (Animated)
			float noise = fract(sin(dot(uv + uTime * 0.5, vec2(12.9898, 78.233))) * 43758.5453);
			
			// 2. Plasma / Energy Field (More intense)
			float plasma = sin(uv.x * 12.0 + uTime * 2.0) * sin(uv.y * 12.0 + uTime * 3.0) * sin(uTime * 4.0);
			plasma = step(0.3, plasma) * 0.5; 
			
			// 3. Pulsing Glow (Stronger)
			float glow = sin(uTime * 6.0) * 0.3 + 0.7; // 0.4 to 1.0
			
			// 4. Scanline
			float scanline = sin(uv.y * 200.0 + uTime * 15.0) * 0.2;
			
			// --- COMBINE ---
			
			// Add Noise
			baseColor += vec3(noise * 0.15);
			
			// Add Plasma (tinted with uColor)
			baseColor += uColor * plasma;
			
			// Apply Glow & Scanline
			vec3 finalColor = baseColor * glow;
			finalColor += uColor * scanline;
			
			// Chromatic Aberration for Glitch
			if (jitter != 0.0) {
				// Sample alpha for glitch
				float alphaR = flixel_texture2D(bitmap, uv + vec2(0.01, 0.0)).a;
				float alphaB = flixel_texture2D(bitmap, uv - vec2(0.01, 0.0)).a;
				
				finalColor.r = uColor.r * alphaR; // Use uColor.r instead of texture.r
				finalColor.b = uColor.b * alphaB; // Use uColor.b instead of texture.b
			}
			
			gl_FragColor = vec4(finalColor, tex.a);
		}
	')

	public function new()
	{
		super();
		uTime.value = [0.0];
		uColor.value = [1.0, 1.0, 1.0];
	}

	public function update(elapsed:Float)
	{
		uTime.value[0] += elapsed;
	}
	
	public function setColor(color:Array<Float>)
	{
		uColor.value = color;
	}
}
