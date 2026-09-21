package script;

// lol
class GlobalScript
{
	public static var Function_Stop:Dynamic = 'FUNC_STOP';
	public static var Function_Continue:Dynamic = 'FUNC_CONT'; // i take back what i said
	public static var Function_Halt:Dynamic = 'FUNC_HALT';

	/**
		Pause flags of the wrappers that can't inherit `paused` (HScript lives in FunkinHScript.hx,
		FunkinPython is a FlxBasic): they are tracked by identity through the static helpers below.
		Scripts that get stopped while paused have to be released from here, otherwise the array
		keeps them alive (see `releaseScript()`).
	**/
	static final pausedScripts:Array<Dynamic> = [];

	/**
		A paused script stays in its script array but is inert: the state never dispatches a
		callback to it (see `PlayState.callOnLuas()` and friends) and its per frame `onUpdate`
		never runs. `resume()` picks up right where it left off.
	**/
	public var paused:Bool = false;

	public function setPaused(value:Bool):Bool
	{
		paused = value;
		return paused;
	}

	public function pause():Void
	{
		setPaused(true);
	}

	public function resume():Void
	{
		setPaused(false);
	}

	/**
		Pauses or resumes any script wrapper, including the ones that don't extend this class.
		Returns the state `script` ended up in, `false` when there was no script to pause.
	**/
	public static function setScriptPaused(script:Dynamic, value:Bool):Bool
	{
		if (script == null)
			return false;

		if (Std.isOfType(script, GlobalScript))
			return (cast script : GlobalScript).setPaused(value);

		pausedScripts.remove(script);
		if (value)
			pausedScripts.push(script);

		return value;
	}

	/**
		Whether the engine has to skip dispatching callbacks to `script`, works for every wrapper.
	**/
	public static function isScriptPaused(script:Dynamic):Bool
	{
		if (script == null)
			return false;

		if (Std.isOfType(script, GlobalScript))
			return (cast script : GlobalScript).paused;

		return pausedScripts.contains(script);
	}

	/**
		Forgets the pause flag of a script that is being stopped for good, so the pause registry
		doesn't keep a dead wrapper alive.
	**/
	public static function releaseScript(script:Dynamic):Void
	{
		if (script != null && !Std.isOfType(script, GlobalScript))
			pausedScripts.remove(script);
	}

	/**
		Whether a script's `scriptName` answers to `tag`: either the name itself (HScript names are
		notetypes, characters, stages...) or the file name, since Lua and Python scripts hand out
		their full path.
	**/
	public static function scriptMatchesTag(scriptName:String, tag:String):Bool
	{
		if (scriptName == null || tag == null)
			return false;

		return scriptName == tag || CoolUtil.getFileStringFromPath(scriptName) == tag;
	}
}
