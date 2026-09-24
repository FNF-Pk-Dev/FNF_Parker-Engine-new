package obj;

import flixel.addons.display.FlxPieDial;
import flixel.group.FlxSpriteGroup;
import flixel.FlxSprite;
#if hxvlc
import hxvlc.flixel.FlxVideoSprite;
#end

class VideoSprite extends FlxSpriteGroup
{
	#if VIDEOS_ALLOWED
	public var finishCallback:Void->Void = null;
	public var onSkip:Void->Void = null;
	public var scriptTag:String = null;

	final _timeToSkip:Float = 1;

	public var holdingTime:Float = 0;
	public var videoSprite:FlxVideoSprite;
	public var skipSprite:FlxPieDial;
	public var cover:FlxSprite;
	public var canSkip(default, set):Bool = false;

	private var videoName:String;

	public var waiting:Bool = false;
	public var didPlay:Bool = false;

	public function new(videoName:String, isWaiting:Bool, canSkip:Bool = false, shouldLoop:Dynamic = false)
	{
		super();

		this.videoName = videoName;
		scrollFactor.set();
		// Debug overlays may append cameras. Video opacity belongs to camVideo,
		// independently of HUD/debug opacity and the group's own alpha tween.
		if (PlayState.instance != null && PlayState.instance.camVideo != null)
			cameras = [PlayState.instance.camVideo];

		waiting = isWaiting;
		if (!waiting)
		{
			cover = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
			cover.scale.set(FlxG.width + 100, FlxG.height + 100);
			cover.screenCenter();
			cover.scrollFactor.set();
			add(cover);
		}

		// initialize sprites
		videoSprite = new FlxVideoSprite();
		videoSprite.antialiasing = ClientPrefs.globalAntialiasing;
		add(videoSprite);
		if (canSkip)
			this.canSkip = true;

		// callbacks
		if (!shouldLoop)
		{
			videoSprite.bitmap.onEndReached.add(function()
			{
				if (alreadyDestroyed)
					return;

				destroy();
			});
		}

		videoSprite.bitmap.onFormatSetup.add(function()
		{
			if (alreadyDestroyed || videoSprite == null)
				return;
			videoSprite.setGraphicSize(FlxG.width);
			videoSprite.updateHitbox();
			videoSprite.screenCenter();
		});

		// start video and adjust resolution to screen size
		videoSprite.load(videoName, shouldLoop ? ['input-repeat=65545'] : null);
	}

	var alreadyDestroyed:Bool = false;

	override function destroy()
	{
		if (alreadyDestroyed)
			return;
		alreadyDestroyed = true;

		FlxTween.cancelTweensOf(this);
		if (videoSprite != null)
			FlxTween.cancelTweensOf(videoSprite);
		var playState:PlayState = PlayState.instance;
		if (playState != null)
		{
			if (scriptTag != null && playState.variables.get(scriptTag) == this)
				playState.variables.remove(scriptTag);
			if (playState.videoCutscene == this)
				playState.videoCutscene = null;
			playState.remove(this);
		}

		var callback:Void->Void = finishCallback;
		finishCallback = null;
		onSkip = null;
		super.destroy();
		cover = null;
		videoSprite = null;
		skipSprite = null;
		if (callback != null)
			callback();
	}

	override function update(elapsed:Float)
	{
		if (canSkip)
		{
			if (PlayState.instance.getControl('ACCEPT'))
			{
				holdingTime = Math.max(0, Math.min(_timeToSkip, holdingTime + elapsed));
			}
			else if (holdingTime > 0)
			{
				holdingTime = Math.max(0, FlxMath.lerp(holdingTime, -0.1, FlxMath.bound(elapsed * 3, 0, 1)));
			}
			updateSkipAlpha();

			if (holdingTime >= _timeToSkip)
			{
				if (onSkip != null)
					onSkip();
				finishCallback = null;
				destroy();
				return;
			}
		}
		super.update(elapsed);
	}

	function set_canSkip(newValue:Bool)
	{
		canSkip = newValue;
		if (canSkip)
		{
			if (skipSprite == null)
			{
				skipSprite = new FlxPieDial(0, 0, 40, FlxColor.WHITE, 40, true, 24);
				skipSprite.replaceColor(FlxColor.BLACK, FlxColor.TRANSPARENT);
				skipSprite.x = FlxG.width - (skipSprite.width + 80);
				skipSprite.y = FlxG.height - (skipSprite.height + 72);
				skipSprite.amount = 0;
				add(skipSprite);
			}
		}
		else if (skipSprite != null)
		{
			remove(skipSprite);
			skipSprite.destroy();
			skipSprite = null;
		}
		return canSkip;
	}

	function updateSkipAlpha()
	{
		if (skipSprite == null)
			return;

		skipSprite.amount = Math.min(1, Math.max(0, (holdingTime / _timeToSkip) * 1.025));
		skipSprite.alpha = alpha * FlxMath.bound(FlxMath.remapToRange(skipSprite.amount, 0.025, 1, 0, 1), 0, 1);
	}

	public function resume()
	{
		if (videoSprite != null)
			videoSprite.resume();
	}

	public function pause()
	{
		if (videoSprite != null)
			videoSprite.pause();
	}
	#end
}
