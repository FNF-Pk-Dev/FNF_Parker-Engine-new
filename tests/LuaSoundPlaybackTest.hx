class LuaSoundPlaybackTest
{
	static function expect(condition:Bool, message:String):Void
	{
		if (!condition)
			throw message;
	}

	static function play(api:LuaSoundCallbacks, name:String, tag:String = null):Void
	{
		Reflect.callMethod(api, api.callbacks.get('playSound'), [name, 0.24, tag]);
	}

	static function main():Void
	{
		Paths.effects.set('click', 'sounds/click');
		Paths.musicTracks.set('click', 'music/click');
		Paths.musicTracks.set('gameOver', 'music/gameOver');
		var api = new LuaSoundCallbacks();

		// Missing assets must never reach the native pool or stop an existing tagged sound.
		play(api, 'click', 'keep');
		var keep = api.sounds.get('keep');
		play(api, 'missing', 'keep');
		play(api, 'missing');
		expect(FlxG.sound.played.length == 1, 'A missing asset reached the sound pool');
		expect(api.sounds.get('keep') == keep && !keep.stopped, 'A missing replacement stopped a valid sound');
		expect(api.warnings.length == 2 && api.warnings[0].indexOf('missing') >= 0, 'Missing audio must identify the key');

		play(api, 'click');
		var effect = FlxG.sound.played[1];
		expect(effect.asset == 'sounds/click' && effect.volume == 0.24, 'SFX lookup or volume changed');
		play(api, 'gameOver', 'death.music');
		var owner = api.sounds;
		var death = owner.get('deathmusic');
		expect(death != null && death.asset == 'music/gameOver', 'Music fallback failed');
		// Completion must use the captured owner even after the current menu/game registry changes.
		api.sounds = [];
		api.sounds.set('deathmusic', keep);
		death.finish();
		expect(!owner.exists('deathmusic') && api.sounds.get('deathmusic') == keep, 'Completion removed the wrong registry entry');
		expect(api.finished.length == 1 && api.finished[0] == 'deathmusic', 'Completion was not dispatched');
		death.finish();
		expect(api.finished.length == 1, 'A stale completion was dispatched twice');

		play(api, 'click', 'replace');
		var old = api.sounds.get('replace');
		var oldCallback = old.onComplete;
		play(api, 'gameOver', 'replace');
		var replacement = api.sounds.get('replace');
		expect(old.stopped && old.onComplete == null, 'Replacement left the old callback attached');
		oldCallback();
		expect(api.sounds.get('replace') == replacement && api.finished.length == 1, 'Stale completion removed a replacement');
		replacement.finish();
		expect(!api.sounds.exists('replace') && api.finished.length == 2, 'Replacement did not complete');
		Sys.println('PASS: missing audio, sounds/music priority, tagged replacement and completion ownership');
	}
}

class Paths
{
	public static var effects:Map<String, String> = [];
	public static var musicTracks:Map<String, String> = [];

	public static function sound(key:String):String
	{
		return effects.get(key);
	}

	public static function music(key:String):String
	{
		return musicTracks.get(key);
	}
}

class FlxG
{
	public static var sound:RecordingSoundFrontEnd = new RecordingSoundFrontEnd();
}

class FlxColor
{
	public static inline var RED:Int = 0xFFFF0000;
}

class RecordingSoundFrontEnd
{
	public var played:Array<FlxSound> = [];

	public function new()
	{
	}

	public function play(asset:String, volume:Float = 1, looped:Bool = false, ?group:SoundGroup, autoDestroy:Bool = true, ?onComplete:Void->Void):FlxSound
	{
		if (asset == null)
			throw 'Null asset passed to native sound playback';
		if (looped || group != null || !autoDestroy)
			throw 'Unexpected playback options';
		var result = new FlxSound(asset, volume, onComplete);
		played.push(result);
		return result;
	}
}

class SoundGroup
{
}

class FlxSound
{
	public var asset:String;
	public var volume:Float;
	public var onComplete:Void->Void;
	public var stopped:Bool = false;

	public function new(asset:String, volume:Float, onComplete:Void->Void)
	{
		this.asset = asset;
		this.volume = volume;
		this.onComplete = onComplete;
	}

	public function stop():Void
	{
		stopped = true;
	}

	public function finish():Void
	{
		if (onComplete != null)
			onComplete();
	}
}
