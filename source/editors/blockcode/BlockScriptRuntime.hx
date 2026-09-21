package editors.blockcode;

import psych.script.FunkinLua;

/**
 * Runs the Lua the block-code editor generated inside the PlayState that is already playing, so a
 * save is visible and audible without restarting the song, and seeks the song for the timeline
 * scrubber.
 *
 * `attach()` builds a `FunkinLua` for the file and pushes it into `PlayState.instance.luaArray` -
 * that array is the registration that makes PlayState dispatch every Lua callback to the script -
 * then replays the setup a script loaded at song start has already been through: the song variables
 * of the current moment, its section flags and the `onCreatePost` / `onLoad` calls. `reload()` is
 * `detach()` + `attach()`, which is what a save from the substate calls.
 *
 * Only the script this module created is ever stopped or removed; scripts the song, a mod or the
 * engine loaded are left exactly where they are. A script PlayState has torn down (song change,
 * restart, game over) is dropped from the tracking as soon as it is noticed, so `activeName` and
 * `activePath` never describe a script that is gone.
 *
 * PlayState / FunkinLua internals relied on, all public: `PlayState.instance`, `PlayState.luaArray`,
 * `PlayState.startingSong`, `PlayState.SONG`, `PlayState.vocals`, `PlayState.opponentVocals`,
 * `new FunkinLua(script)` (executes the chunk and fires `onCreate` before returning),
 * `FunkinLua.call()/set()/stop()`, `FunkinLua.closed`, `FunkinLua.lua`, `FunkinLua.scriptName`,
 * `GlobalScript.releaseScript()`, `Conductor.songPosition`, `Conductor.getStep()`,
 * `FlxG.sound.music`, `Paths.modFolders()` and `SUtil.getPath()`.
 *
 * Compiles to inert stubs without `LUA_ALLOWED`, outside a running song and without a filesystem,
 * and no failure of the attached script is allowed to reach the song.
 */
class BlockScriptRuntime
{
	/** `name` the last successful `attach()`/`reload()` was called with, `""` when nothing is attached. */
	public static var activeName(default, null):String = "";

	/** Resolved file path the last successful `attach()`/`reload()` loaded, `""` when nothing is attached. */
	public static var activePath(default, null):String = "";

	#if LUA_ALLOWED
	/** The one script this runtime pushed into `luaArray`; never a script it did not create. */
	static var attached:FunkinLua = null;
	#end

	/** Whether this runtime can attach anything right now: `LUA_ALLOWED` and a running PlayState. */
	public static function isAvailable():Bool
	{
		#if LUA_ALLOWED
		forgetDeadScript();
		return PlayState.instance != null;
		#else
		return false;
		#end
	}

	/**
	 * Loads and runs `path` live in the running song, replacing whatever this runtime attached
	 * before. `name` is the editor's display name for the script, used when it is empty.
	 *
	 * @return whether a script is now attached and receiving callbacks.
	 */
	public static function attach(path:String, name:String):Bool
	{
		#if LUA_ALLOWED
		forgetDeadScript();

		var playState:PlayState = PlayState.instance;
		if (playState == null)
			return false;

		#if sys
		var filePath:String = resolvePath(path);
		#else
		// No filesystem on this target, so there is no generated script to pick up.
		var filePath:String = "";
		#end

		if (filePath.length == 0)
		{
			report('Block code: script not found - ' + path, FlxColor.RED);
			return false;
		}

		// One live block script at a time: this replaces the script of a previous attach(). The
		// scripts the song itself loaded are untouched, even when they read the same folder.
		detach();

		var script:FunkinLua = null;
		try
		{
			script = new FunkinLua(filePath);
		}
		catch (e:Dynamic)
		{
			report('Block code: could not load ' + filePath + ' (' + e + ')', FlxColor.RED);
			return false;
		}

		// A chunk that fails to load or to run leaves a dead wrapper behind: FunkinLua closes the
		// Lua state and reports the error itself, so there is nothing to push into the song.
		if (script == null || script.lua == null || script.scriptName.length == 0)
		{
			dispose(script);
			return false;
		}

		try
		{
			playState.luaArray.push(script);
		}
		catch (e:Dynamic)
		{
			report('Block code: could not register ' + filePath + ' (' + e + ')', FlxColor.RED);
			dispose(script);
			return false;
		}

		attached = script;
		activePath = filePath;
		activeName = (name == null || name.length == 0) ? CoolUtil.getFileStringFromPath(filePath) : name;

		initialiseAttachedScript(script);
		return true;
		#else
		return false;
		#end
	}

	/** Stops the attached script and removes it from the song; a no-op when nothing is attached. */
	public static function detach():Void
	{
		#if LUA_ALLOWED
		var script:FunkinLua = attached;
		attached = null;
		activeName = "";
		activePath = "";

		if (script == null)
			return;

		var playState:PlayState = PlayState.instance;
		if (playState != null && playState.luaArray != null)
			playState.luaArray.remove(script);

		dispose(script);
		#end
	}

	/** `detach()` + `attach()`, the hot reload a save performs. */
	public static function reload(path:String, name:String):Bool
	{
		#if LUA_ALLOWED
		detach();
		return attach(path, name);
		#else
		return false;
		#end
	}

	/**
	 * Moves the song clock - and the vocals with it - to `ms`, clamped to the song, for the timeline
	 * scrubber. The music keeps whatever play/pause state it had.
	 */
	public static function seekTo(ms:Float):Void
	{
		#if LUA_ALLOWED
		if (Math.isNaN(ms))
			return;

		var playState:PlayState = PlayState.instance;
		if (playState == null || FlxG.sound == null)
			return;

		var music:FlxSound = FlxG.sound.music;
		if (music == null)
			return;

		var target:Float = ms;
		if (target < 0)
			target = 0;
		if (music.length > 0 && target > music.length)
			target = music.length;

		// Assigned directly instead of through PlayState.setSongTime(), which re-plays the music and
		// the vocals and would therefore un-pause the song while the game is paused behind the editor.
		music.time = target;
		if (playState.vocals != null)
			playState.vocals.time = target;
		if (playState.opponentVocals != null)
			playState.opponentVocals.time = target;

		Conductor.songPosition = target;
		#end
	}

	/** Length of the current song in milliseconds, `0` when there is nothing loaded. */
	public static function songLength():Float
	{
		#if LUA_ALLOWED
		if (FlxG.sound == null || FlxG.sound.music == null)
			return 0;

		var length:Float = FlxG.sound.music.length;
		return (length > 0) ? length : 0;
		#else
		return 0;
		#end
	}

	#if LUA_ALLOWED
	/** Reports a failure on the song's own debug text, the only place a player can see it on Android. */
	static function report(text:String, color:FlxColor = FlxColor.RED):Void
	{
		ScriptDebugOverlay.report(text, color);
	}

	/**
	 * Gives the freshly pushed script the state a script loaded at song start already has: the song
	 * position of the moment it was attached at, its section flags, and the `onCreatePost` / `onLoad`
	 * calls PlayState fires once after loading scripts. Everything after that needs no wiring,
	 * PlayState dispatches `onUpdate`, `onStepHit`, `onBeatHit`, `onEvent`... to all of `luaArray`.
	 */
	static function initialiseAttachedScript(script:FunkinLua):Void
	{
		try
		{
			script.set('startedCountdown', !PlayState.instance.startingSong);

			// PlayState keeps curStep/curBeat/curSection private and only pushes them on step, beat
			// and section hits, so a script attached mid-song derives them from the conductor the way
			// MusicBeatState.updateCurStep() does.
			var decStep:Float = Conductor.getStep(Conductor.songPosition - ClientPrefs.noteOffset);
			if (decStep < 0)
				decStep = 0;

			var step:Int = Std.int(Math.floor(decStep));
			var section:Int = sectionAtStep(step);

			script.set('curStep', step);
			script.set('curBeat', Std.int(Math.floor(step / 4)));
			script.set('curSection', section);
			script.set('curDecStep', decStep);
			script.set('curDecBeat', decStep / 4);

			var song:SwagSong = PlayState.SONG;
			if (song != null && song.notes != null && section < song.notes.length && song.notes[section] != null)
			{
				var sectionData:SwagSection = song.notes[section];
				script.set('mustHitSection', sectionData.mustHitSection);
				script.set('altAnim', sectionData.altAnim);
				script.set('gfSection', sectionData.gfSection);
			}
		}
		catch (e:Dynamic)
		{
			report('Block code: could not sync the song state (' + e + ')', FlxColor.RED);
		}

		try
		{
			script.call('onCreatePost', []);
		}
		catch (e:Dynamic)
		{
			report('Block code: onCreatePost failed (' + e + ')', FlxColor.RED);
		}

		try
		{
			script.call('onLoad', []);
		}
		catch (e:Dynamic)
		{
			report('Block code: onLoad failed (' + e + ')', FlxColor.RED);
		}
	}

	/**
	 * Section holding `step`, walked from the first section like `MusicBeatState.rollbackSection()`
	 * does, because a section is not always four beats long.
	 */
	static function sectionAtStep(step:Int):Int
	{
		var song:SwagSong = PlayState.SONG;
		if (song == null || song.notes == null)
			return 0;

		var section:Int = 0;
		var stepsToDo:Int = 0;

		for (i in 0...song.notes.length)
		{
			var sectionData:SwagSection = song.notes[i];
			if (sectionData == null)
				continue;

			var beats:Null<Float> = sectionData.sectionBeats;
			if (beats == null || beats <= 0)
				beats = 4;

			stepsToDo += Std.int(Math.round(beats * 4));
			if (stepsToDo > step)
				break;
			section++;
		}

		return section;
	}

	/** Forgets the tracked script once PlayState has torn it down, so the tracking stays honest. */
	static function forgetDeadScript():Void
	{
		if (attached == null)
			return;

		var playState:PlayState = PlayState.instance;
		if (!attached.closed && playState != null && playState.luaArray != null && playState.luaArray.indexOf(attached) > -1)
			return;

		attached = null;
		activeName = "";
		activePath = "";
	}

	/** Tears a script down the way `PlayState.destroy()` does: `onDestroy`, `stop()`, release. */
	static function dispose(script:FunkinLua):Void
	{
		if (script == null)
			return;

		try
		{
			script.call('onDestroy', []);
		}
		catch (e:Dynamic)
		{
			report('Block code: onDestroy failed (' + e + ')', FlxColor.RED);
		}

		try
		{
			script.stop();
		}
		catch (e:Dynamic)
		{
			report('Block code: could not stop the script (' + e + ')', FlxColor.RED);
		}

		try
		{
			GlobalScript.releaseScript(script);
		}
		catch (e:Dynamic)
		{
			report('Block code: could not release the script (' + e + ')', FlxColor.RED);
		}
	}

	#if sys
	/**
	 * Resolves the editor's save path to a file that exists, `""` when none does: as given (relative
	 * to the game directory), storage prefixed on Android, then mod aware for mod relative paths.
	 */
	static function resolvePath(path:String):String
	{
		if (path == null)
			return "";

		var candidate:String = path.trim();
		if (candidate.length == 0)
			return "";
		if (FileSystem.exists(candidate))
			return candidate;

		candidate = SUtil.getPath() + path.trim();
		if (candidate.length > 0 && FileSystem.exists(candidate))
			return candidate;

		candidate = Paths.modFolders(path.trim());
		if (candidate.length > 0 && FileSystem.exists(candidate))
			return candidate;

		return "";
	}
	#end

	#end
}
