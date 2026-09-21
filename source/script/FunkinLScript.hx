package script;

#if (LUA_ALLOWED || lscript)
import flixel.util.FlxSignal.FlxTypedSignal;
import haxe.io.Path;
import llua.Lua;
import lscript.CustomConvert;
import lscript.LScript;
import llua.*;
#end
import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.input.keyboard.FlxKey;
import flixel.system.FlxAssets.FlxShader;
import flixel.system.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.ui.FlxBar;
import flixel.math.FlxMath;
import openfl.display.BlendMode;
import openfl.filters.ShaderFilter;
import openfl.system.Capabilities;
import openfl.Lib;
import flixel.addons.display.FlxRuntimeShader;
import flixel.util.FlxTimer;
import hxvlc.flixel.FlxVideoSprite;
import hxvlc.flixel.FlxVideo;
import hxvlc.util.Handle;
import haxe.Json;
#if sys
import sys.FileSystem;
import sys.io.File;
import Sys;
#end

class FunkinLScript extends GlobalScript
{
	#if (LUA_ALLOWED || lscript)
	public var lua:LScript;
	public var scriptName(default, null):String;

	/**
	 * Every callback the engine can dispatch to a script: the vocabulary of `PlayState.callOnScripts()`
	 * (`callOnLuas()` / `callOnHScripts()` / `callOnLScripts()` / `callOnPScripts()` call sites) plus the
	 * ones `LScriptSState` dispatches itself.
	 *
	 * They are registered as `false` before the script body runs, see `registerCallbacks()`: a script is
	 * not expected to define all of them, and looking up one it didn't define is fatal in this Luau build
	 * (see `call()`). A new engine callback has to be added here, otherwise `call()` reports it on screen
	 * instead of dispatching it.
	 */
	public static final CALLBACKS:Array<String> = [
		'SkinNoteSplash',
		'eventEarlyTrigger',
		'generateModchart',
		'goodNoteHit',
		'noteMiss',
		'noteMissPress',
		'onBeatHit',
		'onCountdownStarted',
		'onCountdownTick',
		'onCreate',
		'onCreatePost',
		'onCustomSubstateCreate',
		'onCustomSubstateCreatePost',
		'onCustomSubstateDestroy',
		'onCustomSubstateUpdate',
		'onCustomSubstateUpdatePost',
		'onDestroy',
		'onDestroyPost',
		'onEndSong',
		'onEvent',
		'onEventSet',
		'onGameOver',
		'onGameOverConfirm',
		'onGameOverStart',
		'onGhostTap',
		'onKeyPress',
		'onKeyRelease',
		'onLoad',
		'onMoveCamera',
		'onNextDialogue',
		'onPause',
		'onRecalculateRating',
		'onResume',
		'onSectionHit',
		'onSkipDialogue',
		'onSongStart',
		'onSpawnNote',
		'onStartCountdown',
		'onStepHit',
		'onUpdate',
		'onUpdateOptions',
		'onUpdatePost',
		'onUpdateScore',
		'opponentNoteHit',
		'popUpScore',
		'postModifierRegister',
		'preModifierRegister'
	];

	private var filePath:Null<String>;
	private var closed:Bool = false;

	public var foreground:FlxTypedGroup<FlxBasic>;

	public static final defaultVars:Map<String, Dynamic> = new Map<String, Dynamic>();

	public function new(script:String, unsafe:Bool = false)
	{
		var code:String;
		filePath = script;
		scriptName = 'FunkinLScript' + script;

		// Apply FlxColor workarounds
		// code = applyColorWorkarounds();

		// Initialize Lua
		lua = new LScript(Paths.getContent(filePath), unsafe);
		setupLuaEnvironment();

		for (variable => arg in defaultVars)
			set(variable, arg);

		setupErrorHandlers();
		registerCallbacks();
	}

	/**
	 * Puts every name in `CALLBACKS` into the script's globals as `false`.
	 *
	 * `LScript` closes the script body with `setmetatable(_G, ...)`, whose `__index` forwards every global
	 * the script never defined to a Lua C callback that reflects the name onto `script.parent`. Depending on
	 * the name that reflection fails, and it runs outside any protected call: the error it raises ends the
	 * whole process (Luau panics on an unprotected error) instead of the lookup returning nil, which is how
	 * dispatching a callback a script doesn't implement took the game down with no crash log - see `call()`.
	 *
	 * With the names already in the globals table that path is never reached: dispatch finds `false`,
	 * `isfunction()` says no and the callback is skipped, while a script that does define one overwrites the
	 * placeholder with its function (writing a global that already exists never reaches the metatable
	 * either). Registering happens before the script body runs for that same reason.
	 */
	function registerCallbacks():Void
	{
		for (name in CALLBACKS)
			set(name, false);
	}

	private function applyColorWorkarounds(code:String):String
	{
		var workarounds:Map<String, String> = [
			"FlxColor:fromRGB(" => "FlxColor:new():setRGB(",
			"FlxColor.fromRGB(" => "FlxColor:new():setRGB(",
			"FlxColor:fromRGBFloat(" => "FlxColor:new():setRGBFloat(",
			"FlxColor.fromRGBFloat(" => "FlxColor:new():setRGBFloat(",
			"FlxColor:fromHSV(" => "FlxColor:new():setHSV(",
			"FlxColor.fromHSV(" => "FlxColor:new():setHSV(",
			"FlxColor:fromHSB(" => "FlxColor:new():setHSB(",
			"FlxColor.fromHSB(" => "FlxColor:new():setHSB(",
			"FlxColor:fromCMYK(" => "FlxColor:new():setCMYK(",
			"FlxColor.fromCMYK(" => "FlxColor:new():setCMYK("
		];
		for (from => to in workarounds)
		{
			code = StringTools.replace(code, from, to);
		}
		return code;
	}

	private function setupLuaEnvironment():Void
	{
		foreground = new FlxTypedGroup<FlxBasic>();

		// Core Flixel classes
		setVars([
			["Function_Stop", GlobalScript.Function_Stop],
			["Function_Continue", GlobalScript.Function_Continue],
			["Function_Halt", GlobalScript.Function_Halt],
			["FlxG", FlxG],
			["FlxSprite", FlxSprite],
			["FlxGraphic", FlxGraphic],
			["FlxBasic", FlxBasic],
			["FlxObject", FlxObject],
			// Video and media
			["FlxVideo", FlxVideo],
			["FlxVideoSprite", FlxVideoSprite],
			["PsychVideoSprite", PsychVideoSprite],
			["ParkerVideoSprite", PsychVideoSprite],
			["Handle", Handle],
			// Animation and effects
			["FlxTween", FlxTween],
			["FlxEase", FlxEase],
			["FlxTimer", FlxTimer],
			// UI and text
			["FlxText", FlxText],
			["FlxTextFormat", FlxTextFormat],
			// Shaders and graphics
			["FlxShader", FlxShader],
			["FlxRuntimeShader", FlxRuntimeShader],
			["ShaderFilter", ShaderFilter],
			// Sound
			["FlxSound", FlxSound],
			// Axes enum
			[
				"FlxAxes",
				{X: flixel.util.FlxAxes.X, Y: flixel.util.FlxAxes.Y, XY: flixel.util.FlxAxes.XY}
			],
			// OpenFL utilities
			["Lib", Lib],
			["Capabilities", Capabilities],
			// Blend modes
			[
				"BlendMode",
				{
					SUBTRACT: BlendMode.SUBTRACT,
					ADD: BlendMode.ADD,
					MULTIPLY: BlendMode.MULTIPLY,
					ALPHA: BlendMode.ALPHA,
					DARKEN: BlendMode.DARKEN,
					DIFFERENCE: BlendMode.DIFFERENCE,
					INVERT: BlendMode.INVERT,
					HARDLIGHT: BlendMode.HARDLIGHT,
					LIGHTEN: BlendMode.LIGHTEN,
					OVERLAY: BlendMode.OVERLAY,
					SHADER: BlendMode.SHADER,
					SCREEN: BlendMode.SCREEN
				}
			],
			// Standard Haxe utilities
			["Std", Std],
			["Type", Type],
			["Reflect", Reflect],
			["Math", Math],
			["StringTools", StringTools],
			["Json", {parse: Json.parse, stringify: Json.stringify}],
			// Game-specific classes
			["PlayState", PlayState],
			["game", PlayState.instance],
			["Paths", Paths],
			["ClientPrefs", ClientPrefs],
			["Note", Note],
			["StrumNote", StrumNote],
			["NoteSplash", NoteSplash],
			["Character", Character],
			["Boyfriend", Boyfriend],
			["Section", Section],
			["Conductor", Conductor],
			["WeekData", WeekData],
			["Highscore", Highscore],
			["StageData", StageData],
			["Song", Song],
			[
				"import",
				function(className:String)
				{ // 原来构思script不能用呵呵
					var classSplit:Array<String> = className.split(".");
					var daClassName = classSplit[classSplit.length - 1]; // last one

					if (daClassName == '*')
					{
						var daClass = Type.resolveClass(className);

						while (classSplit.length > 0 && daClass == null)
						{
							daClassName = classSplit.pop();
							daClass = Type.resolveClass(classSplit.join("."));
							if (daClass != null)
								break;
						}
						if (daClass != null)
						{
							for (field in Reflect.fields(daClass))
								set(field, Reflect.field(daClass, field));
						}
						else
						{
							scriptMessage('Could not import class $className', FlxColor.RED);
						}
					}
					else
					{
						lua.setVar(daClassName, Type.resolveClass(className));
					}
				}
			]
		]);

		if ((FlxG.state is PlayState) && PlayState.instance != null)
		{
			final state:PlayState = PlayState.instance;

			setVars([
				["modManager", state.modManager], // lol ModChart
				["global", state.variables],
				["setGlobalFunc", (name:String, func:Dynamic) -> state.variables.set(name, func)],
				[
					"callGlobalFunc",
					function(name:String, ?args:Dynamic)
					{
						if (state.variables.exists(name))
							return state.variables.get(name)(args);
						else
							return null;
					}
				]
			]);

			setVars([
				[
					"createGlobalCallback",
					function(name:String, func:Dynamic)
					{
						for (script in PlayState.instance.luaArray)
							if (script != null && script.lua != null && !script.closed)
								Lua_helper.add_callback(script.lua, name, func);
						psych.script.FunkinLua.customFunctions.set(name, func);
					}
				]
			]);
		}

		setVars([
			["FlxCamera", flixel.FlxCamera],
			["FlxSpriteGroup", flixel.group.FlxSpriteGroup],
			["FlxTypedGroup", flixel.group.FlxTypedGroup],
		]);

		set("add", FlxG.state.add);
		set("remove", FlxG.state.remove);
		set("insert", FlxG.state.insert);
		set("members", FlxG.state.members);
		set('foreground', foreground);
		set('this', getCurrentState());

		// Pause control: the script can suspend/wake itself, or another one through its name
		set("pauseScript", function()
		{
			return setPaused(true);
		});
		set("resumeScript", function()
		{
			return setPaused(false);
		});
		set("setScriptPaused", function(tag:String, paused:Bool)
		{
			if (PlayState.instance != null)
				return PlayState.instance.setScriptPaused(tag, paused);

			return false;
		});

		#if android
		set("addTouchPad", function(DPad:String, Action:String)
		{
			if (PlayState.instance != null)
			{
				PlayState.instance.addTouchPad(DPad, Action);
			}
			else
			{
				callCurrentState('addTouchPad', [DPad, Action]);
			}
			return true;
		});

		set("removeTouchPad", function()
		{
			if (PlayState.instance != null)
			{
				PlayState.instance.removeTouchPad();
			}
			else
			{
				callCurrentState('removeTouchPad', []);
			}
			return true;
		});
		#end

		#if sys
		// System utilities
		setVars([["FileSystem", FileSystem], ["File", File], ["Sys", Sys]]);
		#end
	}

	/**
	 * The state scripts act on: the ongoing song if there is one, otherwise the current state.
	 */
	private function getCurrentState():Dynamic
	{
		return PlayState.instance != null ? PlayState.instance : FlxG.state;
	}

	#if android
	/**
	 * Calls a method of the current state, used for states that have no `PlayState.instance`.
	 */
	private function callCurrentState(name:String, ?args:Array<Dynamic>):Void
	{
		final state:Dynamic = getCurrentState();
		if (state == null)
			return;

		final method:Dynamic = Reflect.field(state, name);
		if (method == null || !Reflect.isFunction(method))
			return;

		Reflect.callMethod(state, method, args != null ? args : []);
	}
	#end

	private function setVars(vars:Array<Array<Dynamic>>):Void
	{
		for (v in vars)
		{
			lua.setVar(v[0], v[1]);
		}
	}

	private function setupErrorHandlers():Void
	{
		var location = filePath != null ? filePath : "inline script";
		lua.parseError = (err:String) ->
		{
			scriptMessage('Failed to parse script at ${location}: ${err}', FlxColor.RED);
		};
		lua.functionError = (func:String, err:String) ->
		{
			scriptMessage('Failed to call function "${func}" at ${location}: ${err}', FlxColor.RED);
		};
		lua.tracePrefix = scriptName;
		lua.print = (line:Int, s:String) ->
		{
			scriptMessage('${scriptName}:${line}: ${s}', FlxColor.WHITE);
		};
	}

	/**
	 * Script messages normally go to PlayState's debug text, which only exists while a song
	 * is running — scripted states (see LScriptSState) have none, so print those on the shared
	 * on-screen overlay (ScriptDebugOverlay) instead of dropping them.
	 */
	private function scriptMessage(msg:String, color:FlxColor):Void
	{
		final playState:PlayState = PlayState.instance;
		if (playState != null)
			playState.addTextToDebug(msg, color);
		else
			ScriptDebugOverlay.report(msg, color);
	}

	public function execute():Void
	{
		if (closed)
			return;
		lua.execute();
		call("onCreate", []);
	}

	public function get(name:String):Dynamic
	{
		if (closed)
			return null;
		return lua.getVar(name);
	}

	public function set(name:String, value:Dynamic):Void
	{
		if (closed)
			return;
		lua.setVar(name, value);
	}

	public function setClass(value:Class<Dynamic>):Void
	{
		if (closed)
			return;
		var className = Type.getClassName(value).split('.').pop();
		lua.setVar(className, value);
	}

	public function call(method:String, ?args:Array<Dynamic>):Dynamic
	{
		if (closed)
			return GlobalScript.Function_Continue;

		// Only dispatch what `registerCallbacks()` put in the script's globals: any other name would be a
		// lookup of a global that may not exist, which is fatal (see `registerCallbacks()`). Reporting it
		// keeps a callback that's missing from that list visible instead of turning it into another crash.
		if (!CALLBACKS.contains(method))
		{
			scriptMessage('${scriptName}: "$method" is not a dispatchable callback, skipping it', FlxColor.RED);
			return GlobalScript.Function_Continue;
		}

		var result = lua.callFunc(method, args != null ? args : []);
		return result != null ? result : GlobalScript.Function_Continue;
	}

	public function setParent(parent:Dynamic):Void
	{
		if (closed)
			return;
		lua.parent = parent;
		// The owning state also becomes the script's `this`, scripts are usually created before their state is known
		set('this', parent != null ? parent : getCurrentState());
	}

	public function stop():Void
	{
		if (closed)
			return;
		closed = true;
		Lua.close(lua.luaState);
		lua = null;
	}
	#else
	public var scriptName(default, null):String;

	public function new(script:String, unsafe:Bool = false)
	{
		scriptName = Path.withoutDirectory(script);
		// PlayState may not exist (scripted states), ScriptDebugOverlay reports either way
		ScriptDebugOverlay.report("LUA support is disabled. Script functionality is limited.", FlxColor.YELLOW);
	}

	public function execute():Void
	{
	}

	public function get(name:String):Dynamic
		return null;

	public function set(name:String, value:Dynamic):Void
	{
	}

	public function setClass(value:Class<Dynamic>):Void
	{
	}

	public function call(method:String, ?args:Array<Dynamic>):Dynamic
		return GlobalScript.Function_Continue;

	public function setParent(parent:Dynamic):Void
	{
	}

	public function stop():Void
	{
	}
	#end
}
