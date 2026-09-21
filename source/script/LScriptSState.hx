package script;

#if LUA_ALLOWED
#if sys
import sys.FileSystem;
#end

/**
 * Scripted state override for LScript scripts (`states/<StateName>.lscript`), the LScript
 * counterpart of OScriptState (HScript) and LuaSState (Lua).
 *
 * The script runs *on* the state it replaces: `script.parent` (and `this`) is this state,
 * so every global the script assigns lands on it, and the `game`, `add`, `remove`, `insert`
 * and `members` globals the wrapper binds to `PlayState.instance` / `FlxG.state` on its own
 * are pointed at this state instead of the outgoing one.
 *
 * Callback order: `loadScript()` binds the state first and then runs the script body plus
 * `onCreate` through `FunkinLScript.execute()` (the same contract PlayState uses for its
 * lscriptArray), all in the constructor — the wrapper holds its own Luau state and runs
 * nothing by itself, so `setParent()` and `set()` are always in place before the first line
 * of the script runs. Then `onLoad`, then `onCreatePost` right after `super.create()`. From
 * there `onStepHit`/`onBeatHit`, `onUpdate`/`onUpdatePost` and `onDestroy`/`onDestroyPost`
 * follow the state's lifecycle.
 */
class LScriptSState extends MusicBeatState
{
	public var lscript:FunkinLScript;

	public function new(fileName:String)
	{
		super(false);

		if (loadScript('states/$fileName.lscript'))
			callOnLScript('onLoad', []);
	}

	/** Loads `file` (mods first, then the preload folder) and runs its body. */
	public function loadScript(file:String):Bool
	{
		var scriptPath:String = null;

		#if MODS_ALLOWED
		final modPath = Paths.modFolders(file);
		if (FileSystem.exists(modPath))
			scriptPath = modPath;
		#end

		if (scriptPath == null)
		{
			final preloadPath = Paths.getPreloadPath(file);
			if (FileSystem.exists(preloadPath))
				scriptPath = preloadPath;
		}

		if (scriptPath == null)
		{
			final missing:String = 'LScriptSState: State script not found: $file';
			trace(missing);
			// Nothing on screen says so otherwise, and a state script that silently does nothing is
			// exactly what the overlay is for
			ScriptDebugOverlay.report(missing, FlxColor.RED);
			return false;
		}

		// The body runs on `execute()` below, not here, so the bindings come first.
		lscript = new FunkinLScript(scriptPath);

		// The script runs on this state: `this` / `script.parent` are it, and the globals the
		// wrapper bound to `PlayState.instance` (`game`, null outside a song) / `FlxG.state`
		// (still the outgoing state here) are pointed at it instead.
		lscript.setParent(this);
		lscript.set('this', this);
		lscript.set('game', this);
		lscript.set('add', add);
		lscript.set('remove', remove);
		lscript.set('insert', insert);
		lscript.set('members', members);

		lscript.execute();
		return true;
	}

	public function callOnLScript(event:String, args:Array<Dynamic>):Dynamic
	{
		if (lscript == null || lscript.paused)
			return GlobalScript.Function_Continue;

		final myValue = lscript.call(event, args);
		return (myValue != null) ? myValue : GlobalScript.Function_Continue;
	}

	override function create():Void
	{
		// Also flushes whatever the script reported while this state wasn't on screen yet
		ScriptDebugOverlay.attach(this);

		// onCreate already ran with the script body in the constructor
		super.create();
		callOnLScript('onCreatePost', []);
	}

	override function update(elapsed:Float):Void
	{
		if (callOnLScript('onUpdate', [elapsed]) == GlobalScript.Function_Stop)
			return;

		super.update(elapsed);
		callOnLScript('onUpdatePost', [elapsed]);
	}

	override function beatHit():Void
	{
		callOnLScript('onBeatHit', []);
		super.beatHit();
	}

	override function stepHit():Void
	{
		callOnLScript('onStepHit', [curStep]);
		super.stepHit();
	}

	override function destroy():Void
	{
		if (callOnLScript('onDestroy', []) != GlobalScript.Function_Stop)
			callOnLScript('onDestroyPost', []);

		if (lscript != null)
		{
			lscript.stop();
			lscript = null;
		}

		super.destroy();
	}
}
#end
