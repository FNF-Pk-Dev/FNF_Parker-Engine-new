package script.hscript;

import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

class OScriptState extends MusicBeatState
{
	public var customMenu:Bool = false;

	private var hscript:HScript;

	/** Name the script was loaded under, prefixes the messages printed on screen. */
	private var scriptLabel:String = 'Script';

	/** Paused scripts keep their state but stop receiving callbacks, see `GlobalScript.setScriptPaused()`. */
	public var paused(get, never):Bool;

	inline function get_paused():Bool
		return GlobalScript.isScriptPaused(hscript);

	public inline function setPaused(value:Bool):Bool
		return GlobalScript.setScriptPaused(hscript, value);

	public static function fromFile(file:String, ?name:String, ?additionalVars:Map<String, Any>)
	{
		if (name == null)
			name = file;
		var state = new OScriptState();
		state.loadScript(File.getContent(file), name, additionalVars);
		return state;
	}

	public function loadScript(script:String, ?name:String = "Script", ?additionalVars:Map<String, Any>)
	{
		scriptLabel = name;

		try
		{
			hscript = new HScript(script, name, additionalVars);
		}
		catch (e:Dynamic)
		{
			// HScript reports a parse failure through PlayState's debug text, which a scripted state
			// doesn't have, so the failure lands here as a null access instead of a message.
			scriptError('PARSING ERROR: $e');
			return;
		}

		// HScript's logger (FunkinHScript.InitLogger) prints through PlayState, so a scripted state
		// keeps Iris on the on-screen overlay instead of crashing in its error handler.
		ScriptDebugOverlay.hookScriptLog();

		customMenu = hscript.call('customMenu', []);

		trace('is [$name] custom? [$customMenu]');

		hscript.set("state", this);
		hscript.set("add", add);
		hscript.set("remove", remove);
		hscript.set("insert", insert);
		hscript.set("members", members);

		#if android
		hscript.set("addTouchPad", addTouchPad);
		hscript.set("addPadCamera", addPadCamera);
		#end

		// Pause control: the script can suspend/wake itself, see GlobalScript.setScriptPaused()
		hscript.set('pauseScript', function()
		{
			return GlobalScript.setScriptPaused(hscript, true);
		});
		hscript.set('resumeScript', function()
		{
			return GlobalScript.setScriptPaused(hscript, false);
		});
	}

	override function create():Void
	{
		// The script is built by now (the constructor, or setUpScript), so this is where its messages
		// reach the overlay - including anything reported before the state was on screen
		ScriptDebugOverlay.attach(this);
		super.create();
	}

	// 代理HScript的方法
	public function set(name:String, val:Dynamic)
	{
		if (hscript == null)
			return;

		hscript.set(name, val);
	}

	public function call(func:String, ?args:Array<Any>):Dynamic
	{
		if (hscript == null)
			return GlobalScript.Function_Continue;

		try
		{
			return hscript.call(func, args);
		}
		catch (e:Dynamic)
		{
			// A failing script function must not take the caller's update loop down with it
			scriptError(Std.string(e));
			return GlobalScript.Function_Continue;
		}
	}

	private function scriptError(message:String):Void
	{
		ScriptDebugOverlay.report('[$scriptLabel]: $message', FlxColor.RED);
	}
}
