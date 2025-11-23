package obj;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.math.FlxMath;
import flixel.group.FlxGroup.FlxTypedGroup;
import backend.ClientPrefs;
import openfl.display.BlendMode;
import backend.InputFormatter;
import shaders.ColorSwap;
import flixel.util.FlxSpriteUtil;
import backend.MusicBeatState;

class KeystrokesUI extends FlxSpriteGroup
{
	// --- Configuration ---
	public static var CONFIG = {
		BUTTON_SIZE: 65,
		BUTTON_SPACING: 25,
		START_X: 100,
		START_Y: 550,
		MAX_BEAMS: 10,
		MAX_PARTICLES: 80,
		MAX_BURSTS: 12,
		IMPACT_SCALE_X: 1.25,
		IMPACT_SCALE_Y: 0.75,
		BEAM_SPEED: 1200,
		PARTICLE_SPEED: 1100
	};

	var buttons:Array<Dynamic> = [
		{dir: 'left', key: 'note_left', hex: 0xC24B99, noteData: 0}, // Purple
		{dir: 'down', key: 'note_down', hex: 0x00FFFF, noteData: 1}, // Cyan
		{dir: 'up', key: 'note_up', hex: 0x12FA05, noteData: 2}, // Green
		{dir: 'right', key: 'note_right', hex: 0xF9393F, noteData: 3} // Red
	];

	var keyStates:Map<String, Dynamic> = new Map();
	var buttonUIs:Map<String, Dynamic> = new Map();

	// Stats
	var npsCount:Int = 0;
	var totCount:Int = 0;
	var npsTimer:Float = 0;
	var statScale:Float = 1.0;
	var statsBg:FlxSprite;
	var statsLine:FlxSprite;
	var npsText:FlxText;
	var totText:FlxText;

	// Pools
	var beams:FlxTypedGroup<KeyBeam>;
	var particles:FlxTypedGroup<KeyParticle>;
	var bursts:FlxTypedGroup<KeyBurst>;
	var stars:FlxTypedGroup<KeyStar>;

	public function new(x:Float, y:Float)
	{
		super(x, y);

		// 1. Initialize Pools
		beams = new FlxTypedGroup<KeyBeam>(CONFIG.MAX_BEAMS);
		for (i in 0...CONFIG.MAX_BEAMS) beams.add(new KeyBeam());

		particles = new FlxTypedGroup<KeyParticle>(CONFIG.MAX_PARTICLES);
		for (i in 0...CONFIG.MAX_PARTICLES) particles.add(new KeyParticle());

		bursts = new FlxTypedGroup<KeyBurst>(CONFIG.MAX_BURSTS);
		for (i in 0...CONFIG.MAX_BURSTS) bursts.add(new KeyBurst());

		stars = new FlxTypedGroup<KeyStar>(16);
		for (i in 0...16) stars.add(new KeyStar());

		// 2. Initialize Buttons
		for (i in 0...buttons.length)
		{
			var btn = buttons[i];
			var xPos = CONFIG.START_X + (i * (CONFIG.BUTTON_SIZE + CONFIG.BUTTON_SPACING));
			var yPos = CONFIG.START_Y;
			
			keyStates.set(btn.key, {pressed: false, beamTimer: 0.0});

			var ui:Dynamic = {};
			ui.baseX = xPos;
			ui.baseY = yPos;

			// --- Color Calculation (Manual HSV Shift) ---
			var baseColor = FlxColor.fromInt(btn.hex);
			if(ClientPrefs.arrowHSV != null && ClientPrefs.arrowHSV.length > btn.noteData) {
				var hsv = ClientPrefs.arrowHSV[btn.noteData];
				// Apply Hue (hsv[0] is in degrees)
				baseColor.hue += hsv[0];
				// Apply Saturation (hsv[1] is percent offset, e.g. -10 to 10)
				baseColor.saturation += (hsv[1] / 100);
				// Apply Brightness (hsv[2] is percent offset)
				baseColor.brightness += (hsv[2] / 100);
			}
			ui.color = baseColor;

			// Setup Shader for effects (Glow/Particles) - Optional, but keeps consistency
			var colorSwap = new ColorSwap();
			// We don't strictly need to set shader params if we use the calculated color directly for sprites,
			// but it's good for things that might use the original texture.
			ui.colorSwap = colorSwap;

			// Layer 1: Glow (Behind everything)
			ui.glow = new FlxSprite(xPos, yPos).makeGraphic(CONFIG.BUTTON_SIZE, CONFIG.BUTTON_SIZE, FlxColor.WHITE);
			ui.glow.color = baseColor;
			ui.glow.alpha = 0;
			ui.glow.blend = BlendMode.ADD;
			add(ui.glow);

			// Layer 2: Background (Black base)
			ui.bg = new FlxSprite(xPos, yPos);
			ui.bg.makeGraphic(CONFIG.BUTTON_SIZE, CONFIG.BUTTON_SIZE, FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(ui.bg, 0, 0, CONFIG.BUTTON_SIZE, CONFIG.BUTTON_SIZE, 12, 12, FlxColor.BLACK);
			ui.bg.alpha = 0.8;
			add(ui.bg);

			// Layer 3: Border (Solid Color)
			ui.border = new FlxSprite(xPos, yPos);
			ui.border.makeGraphic(CONFIG.BUTTON_SIZE, CONFIG.BUTTON_SIZE, FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(ui.border, 0, 0, CONFIG.BUTTON_SIZE, CONFIG.BUTTON_SIZE, 12, 12, baseColor);
			ui.border.antialiasing = ClientPrefs.globalAntialiasing;
			add(ui.border);

			// Layer 4: Inner (Black Overlay to create hollow effect)
			// Inset 4px -> Border width = 4px
			ui.inner = new FlxSprite(xPos + 4, yPos + 4);
			ui.inner.makeGraphic(CONFIG.BUTTON_SIZE - 8, CONFIG.BUTTON_SIZE - 8, FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(ui.inner, 0, 0, CONFIG.BUTTON_SIZE - 8, CONFIG.BUTTON_SIZE - 8, 8, 8, FlxColor.BLACK);
			ui.inner.alpha = 0.8; // Slightly transparent to blend
			add(ui.inner);

			// Layer 5: Flash (White overlay on press)
			ui.flash = new FlxSprite(xPos, yPos);
			ui.flash.makeGraphic(CONFIG.BUTTON_SIZE, CONFIG.BUTTON_SIZE, FlxColor.TRANSPARENT);
			FlxSpriteUtil.drawRoundRect(ui.flash, 0, 0, CONFIG.BUTTON_SIZE, CONFIG.BUTTON_SIZE, 12, 12, FlxColor.WHITE);
			ui.flash.alpha = 0;
			ui.flash.blend = BlendMode.ADD;
			add(ui.flash);

			// Layer 6: Text
			var bindKeys = ClientPrefs.keyBinds.get(btn.key);
			var keyName = InputFormatter.getKeyName(bindKeys[0]);
			ui.txt = new FlxText(xPos, yPos + (CONFIG.BUTTON_SIZE / 2) - 18, CONFIG.BUTTON_SIZE, keyName, 36);
			ui.txt.setFormat(Paths.font("vcr.ttf"), 36, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
			add(ui.txt);

			buttonUIs.set(btn.key, ui);
		}

		// 3. Initialize Stats
		var bgWidth = (4 * CONFIG.BUTTON_SIZE) + (3 * CONFIG.BUTTON_SPACING) + 40;
		var barX = CONFIG.START_X - 20;
		var barY = CONFIG.START_Y + CONFIG.BUTTON_SIZE + 40;

		statsBg = new FlxSprite(barX, barY).makeGraphic(Std.int(bgWidth), 40, FlxColor.WHITE);
		statsBg.color = FlxColor.BLACK;
		statsBg.alpha = 0.85;
		add(statsBg);

		statsLine = new FlxSprite(barX, barY).makeGraphic(Std.int(bgWidth), 3, FlxColor.WHITE);
		statsLine.alpha = 0;
		statsLine.blend = BlendMode.ADD;
		add(statsLine);

		npsText = new FlxText(barX + 20, barY + 8, bgWidth / 2, "NPS: 0", 22);
		npsText.setFormat("vcr.ttf", 22, FlxColor.WHITE, LEFT);
		add(npsText);

		totText = new FlxText(barX + bgWidth - 20 - (bgWidth / 2), barY + 8, bgWidth / 2, "TOT: 0", 22);
		totText.setFormat("vcr.ttf", 22, FlxColor.WHITE, RIGHT);
		add(totText);
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		var dt = Math.min(elapsed, 0.1);
		
		// Stats Logic
		npsTimer += dt;
		if (npsTimer >= 1) {
			npsCount = 0;
			npsTimer = 0;
		}
		if (statScale > 1) {
			statScale = FlxMath.lerp(statScale, 1, dt * 15);
			npsText.scale.set(statScale, statScale);
			totText.scale.set(statScale, statScale);
		}
		npsText.text = "NPS: " + npsCount;
		totText.text = "TOT: " + totCount;

		// Input Logic
		for (btn in buttons)
		{
			var keyName = btn.key;
			var ui = buttonUIs.get(keyName);
			var k = keyStates.get(keyName);
			var color:FlxColor = ui.color;
			var colorSwap:ColorSwap = ui.colorSwap;

			var justPressed = false;
			var pressed = false;
			var justReleased = false;

			// Input Detection
			var controlName = "";
			switch(keyName) {
				case 'note_left': controlName = 'NOTE_LEFT';
				case 'note_down': controlName = 'NOTE_DOWN';
				case 'note_up': controlName = 'NOTE_UP';
				case 'note_right': controlName = 'NOTE_RIGHT';
			}

			var currentState = FlxG.state;
			if (Std.isOfType(currentState, MusicBeatState)) {
				var mbState:MusicBeatState = cast currentState;
				@:privateAccess
				if (mbState.controls != null) {
					if (Reflect.getProperty(mbState.controls, controlName + "_P")) justPressed = true;
					if (Reflect.getProperty(mbState.controls, controlName)) pressed = true;
					if (Reflect.getProperty(mbState.controls, controlName + "_R")) justReleased = true;
				}
			} else {
				var bindKeys = ClientPrefs.keyBinds.get(keyName);
				if (bindKeys != null) {
					if (FlxG.keys.anyJustPressed(bindKeys)) justPressed = true;
					if (FlxG.keys.anyPressed(bindKeys)) pressed = true;
					if (FlxG.keys.anyJustReleased(bindKeys)) justReleased = true;
				}
			}

			// Animation Logic
			if (justPressed)
			{
				npsCount++;
				totCount++;
				statScale = 1.35;

				// Stats Reaction
				statsBg.color = color;
				FlxTween.color(statsBg, 0.3, statsBg.color, FlxColor.BLACK, {ease: FlxEase.quadOut});
				statsLine.color = color;
				statsLine.alpha = 1;
				FlxTween.tween(statsLine, {alpha: 0}, 0.3, {ease: FlxEase.quadOut});

				// Button Reaction
				FlxTween.cancelTweensOf(ui.bg.scale);
				FlxTween.cancelTweensOf(ui.border.scale);
				FlxTween.cancelTweensOf(ui.inner.scale);

				var scaleX = CONFIG.IMPACT_SCALE_X;
				var scaleY = CONFIG.IMPACT_SCALE_Y;
				ui.bg.scale.set(scaleX, scaleY);
				ui.border.scale.set(scaleX, scaleY);
				ui.inner.scale.set(scaleX, scaleY);

				// Flash & Glow
				ui.flash.scale.set(scaleX, scaleY);
				ui.flash.alpha = 1;
				FlxTween.tween(ui.flash, {alpha: 0}, 0.15);

				ui.glow.alpha = 1;
				ui.glow.scale.set(1.1, 1.1);
				FlxTween.tween(ui.glow, {alpha: 0}, 0.25, {ease: FlxEase.quadOut});
				FlxTween.tween(ui.glow.scale, {x: 1.7, y: 1.7}, 0.25, {ease: FlxEase.quadOut});

				// Particles
				var cx = ui.baseX + CONFIG.BUTTON_SIZE / 2;
				var cy = ui.baseY + CONFIG.BUTTON_SIZE / 2;
				spawnLaserBeam(ui.baseX, ui.baseY, color, colorSwap);
				spawnSparkParticles(cx, cy, color);
				spawnShockwave(cx, cy, color);
				spawnStarBurst(cx, cy, color);
			}

			if (pressed)
			{
				k.beamTimer += dt;
				if (k.beamTimer > 0.05) {
					spawnLaserBeam(ui.baseX, ui.baseY, color, colorSwap);
					k.beamTimer = 0;
				}

				// Shake
				var shake = 1.5;
				var rx = FlxG.random.float(-shake, shake);
				var ry = FlxG.random.float(-shake, shake);
				
				ui.bg.x = ui.baseX + rx;
				ui.bg.y = ui.baseY + ry;
				ui.border.x = ui.baseX + rx;
				ui.border.y = ui.baseY + ry;
				ui.inner.x = ui.baseX + 4 + rx;
				ui.inner.y = ui.baseY + 4 + ry;
				ui.txt.x = ui.baseX + rx;
				ui.txt.y = ui.baseY + (CONFIG.BUTTON_SIZE / 2) - 18 + ry;
			}
			else if (justReleased)
			{
				var t = 0.35;
				FlxTween.tween(ui.bg.scale, {x: 1, y: 1}, t, {ease: FlxEase.elasticOut});
				FlxTween.tween(ui.border.scale, {x: 1, y: 1}, t, {ease: FlxEase.elasticOut});
				FlxTween.tween(ui.inner.scale, {x: 1, y: 1}, t, {ease: FlxEase.elasticOut});
				
				// Reset positions
				ui.bg.x = ui.baseX;
				ui.bg.y = ui.baseY;
				ui.border.x = ui.baseX;
				ui.border.y = ui.baseY;
				ui.inner.x = ui.baseX + 4;
				ui.inner.y = ui.baseY + 4;
				ui.txt.x = ui.baseX;
				ui.txt.y = ui.baseY + (CONFIG.BUTTON_SIZE / 2) - 18;
			}
		}
	}

	// --- Spawning Helpers ---

	function spawnLaserBeam(x:Float, y:Float, color:FlxColor, colorSwap:ColorSwap)
	{
		var beam = beams.recycle(KeyBeam);
		beam.spawn(x + (CONFIG.BUTTON_SIZE - 40) / 2, y, color);
		if(colorSwap != null) beam.shader = colorSwap.shader;
		add(beam);
	}

	function spawnStarBurst(cx:Float, cy:Float, color:FlxColor)
	{
		for (i in 0...2) {
			var star = stars.recycle(KeyStar);
			star.spawn(cx, cy, color, i == 1);
			add(star);
		}
	}

	function spawnShockwave(cx:Float, cy:Float, color:FlxColor)
	{
		var burst = bursts.recycle(KeyBurst);
		burst.spawn(cx, cy, color);
		add(burst);
	}

	function spawnSparkParticles(cx:Float, cy:Float, color:FlxColor)
	{
		for (i in 0...7) {
			var p = particles.recycle(KeyParticle);
			p.spawn(cx, cy, color);
			add(p);
		}
	}
}

// --- Helper Classes ---

class KeyBeam extends FlxSprite
{
	public var life:Float = 0;
	public var maxLife:Float = 0.2;

	public function new()
	{
		super();
		makeGraphic(40, 50, FlxColor.WHITE);
		blend = BlendMode.ADD;
	}

	public function spawn(x:Float, y:Float, color:FlxColor)
	{
		this.x = x;
		this.y = y;
		this.color = color;
		this.alpha = 0.8;
		this.scale.set(1, 1);
		this.life = maxLife;
		this.visible = true;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (!visible) return;

		life -= elapsed;
		if (life <= 0) {
			kill();
			return;
		}

		var progress = 1 - (life / maxLife);
		y -= KeystrokesUI.CONFIG.BEAM_SPEED * elapsed;
		scale.y = 1 + progress * 3;
		scale.x = 1 - progress * 0.5;
		alpha = 0.8 * (1 - progress);
	}
}

class KeyStar extends FlxSprite
{
	public var life:Float = 0;
	public var baseAngle:Float = 0;

	public function new()
	{
		super();
		makeGraphic(100, 12, FlxColor.WHITE);
		blend = BlendMode.ADD;
	}

	public function spawn(cx:Float, cy:Float, color:FlxColor, isVertical:Bool)
	{
		this.x = cx - 50;
		this.y = cy - 6;
		this.color = color;
		this.alpha = 1;
		this.life = 0.25;
		
		baseAngle = FlxG.random.float(-15, 15);
		if (isVertical) baseAngle += 90;
		this.angle = baseAngle;
		
		this.scale.set(0.2, 1);
		this.visible = true;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (!visible) return;

		life -= elapsed;
		if (life <= 0) {
			kill();
			return;
		}

		var progress = 1 - (life / 0.25);
		angle = baseAngle + (progress * 45);

		var scaleX:Float = 0;
		if (progress < 0.3) {
			scaleX = FlxMath.lerp(0.2, 1.8, progress / 0.3);
		} else {
			scaleX = FlxMath.lerp(1.8, 0, (progress - 0.3) / 0.7);
		}

		scale.x = scaleX;
		scale.y = 1 - progress;
		alpha = 1 - progress;
	}
}

class KeyBurst extends FlxSprite
{
	public var life:Float = 0;

	public function new()
	{
		super();
		makeGraphic(90, 90, FlxColor.WHITE);
		blend = BlendMode.ADD;
	}

	public function spawn(cx:Float, cy:Float, color:FlxColor)
	{
		this.x = cx - 45;
		this.y = cy - 45;
		this.color = color;
		this.alpha = 0.8;
		this.scale.set(0.5, 0.5);
		this.life = 0.25;
		this.visible = true;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (!visible) return;

		life -= elapsed;
		if (life <= 0) {
			kill();
			return;
		}

		var s = scale.x + 8 * elapsed;
		scale.set(s, s);
		alpha = (life / 0.25) * 0.8;
	}
}

class KeyParticle extends FlxSprite
{
	public var vx:Float = 0;
	public var vy:Float = 0;
	public var particleDrag:Float = 0;
	public var gravity:Float = 0;
	public var life:Float = 0;
	public var maxLife:Float = 0;

	public function new()
	{
		super();
		makeGraphic(4, 4, FlxColor.WHITE);
		blend = BlendMode.ADD;
	}

	public function spawn(cx:Float, cy:Float, color:FlxColor)
	{
		var angle = FlxG.random.float(0, 6.28);
		var speed = FlxG.random.float(KeystrokesUI.CONFIG.PARTICLE_SPEED * 0.3, KeystrokesUI.CONFIG.PARTICLE_SPEED * 1.3);

		this.x = cx - 2;
		this.y = cy - 2;
		this.vx = Math.cos(angle) * speed;
		this.vy = Math.sin(angle) * speed;

		this.particleDrag = FlxG.random.float(0.85, 0.96);
		this.gravity = FlxG.random.float(1000, 2000);
		this.life = FlxG.random.float(0.3, 0.6);
		this.maxLife = this.life;

		this.color = color;
		this.alpha = 1;
		this.visible = true;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (!visible) return;

		life -= elapsed;
		if (life <= 0) {
			kill();
			return;
		}

		x += vx * elapsed;
		y += vy * elapsed;
		vy += gravity * elapsed;
		vx *= particleDrag;
		vy *= particleDrag;

		var velocity = Math.sqrt(vx * vx + vy * vy);
		var stretch = 1 + (velocity / 120);
		var thickness = FlxMath.bound(1.2 - (velocity / 2200), 0.6, 1.3);

		angle = Math.atan2(vy, vx) * (180 / Math.PI);
		scale.set(stretch, thickness);

		var a = life / maxLife;
		alpha = a * a;
	}
}
