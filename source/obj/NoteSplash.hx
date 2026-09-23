package obj;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;

class NoteSplash extends FlxSprite
{
	public var colorSwap:ColorSwap = null;

	private var idleAnim:String;
	private var textureLoaded:String = null;

	/** Where the burst is meant to be centred, in world coords. */
	private var targetX:Float = 0;

	private var targetY:Float = 0;

	public function new(x:Float = 0, y:Float = 0, ?note:Int = 0)
	{
		super(x, y);

		var skin:String = 'noteSplashes';
		if (PlayState.SONG.splashSkin != null && PlayState.SONG.splashSkin.length > 0)
			skin = PlayState.SONG.splashSkin;

		loadAnims(skin);

		colorSwap = new ColorSwap();
		shader = colorSwap.shader;

		setupNoteSplash(x, y, note);
		antialiasing = ClientPrefs.globalAntialiasing;
	}

	public function setupNoteSplash(x:Float, y:Float, note:Int = 0, texture:String = null, hueColor:Float = 0, satColor:Float = 0, brtColor:Float = 0)
	{
		// `x`/`y` is the point the burst should be centred on (callers pass the receptor's
		// midpoint). The atlas frames are not centred in their own declared canvas, so the sprite
		// is re-anchored per frame from the frame's real content rect rather than from `frameWidth`.
		targetX = x;
		targetY = y;

		alpha = 0.6;

		if (texture == null)
		{
			texture = 'noteSplashes';
			if (PlayState.SONG.splashSkin != null && PlayState.SONG.splashSkin.length > 0)
				texture = PlayState.SONG.splashSkin;
		}

		if (textureLoaded != texture)
		{
			loadAnims(texture);
		}
		colorSwap.hue = hueColor;
		colorSwap.saturation = satColor;
		colorSwap.brightness = brtColor;
		offset.set(0, 0);

		var animNum:Int = FlxG.random.int(1, 2);
		animation.play('note' + note + '-' + animNum, true);
		if (animation.curAnim != null)
			animation.curAnim.frameRate = 24 + FlxG.random.int(-2, 2);

		alignToTarget();
	}

	/**
	 * Pins the frame's actual content centre onto `targetX`/`targetY`.
	 *
	 * `frame.offset` is the negated `frameX` and `frame.frame` is the atlas trim rect, so
	 * `offset + frame/2` is where the visible pixels sit inside the sprite's frame box. Using that
	 * instead of `frameWidth/2` is what keeps the burst on the arrow: the shipped splash art places
	 * its content well off its own declared canvas centre, so a plain centring is tens of pixels out.
	 */
	private function alignToTarget():Void
	{
		if (frame == null)
			return;

		x = targetX - (frame.offset.x + frame.frame.width * 0.5) * scale.x;
		y = targetY - (frame.offset.y + frame.frame.height * 0.5) * scale.y;
	}

	function loadAnims(skin:String)
	{
		frames = Paths.getSparrowAtlas(skin);
		for (i in 1...3)
		{
			animation.addByPrefix("note1-" + i, "note splash blue " + i, 24, false);
			animation.addByPrefix("note2-" + i, "note splash green " + i, 24, false);
			animation.addByPrefix("note0-" + i, "note splash purple " + i, 24, false);
			animation.addByPrefix("note3-" + i, "note splash red " + i, 24, false);
		}
	}

	override function update(elapsed:Float)
	{
		if (animation.curAnim != null)
			if (animation.curAnim.finished)
				kill();

		super.update(elapsed);

		// Re-anchor after `super.update` has advanced the frame: the content centre drifts across a
		// splash animation, so a spawn-time-only anchor would let the burst slide off the arrow.
		alignToTarget();
	}
}
