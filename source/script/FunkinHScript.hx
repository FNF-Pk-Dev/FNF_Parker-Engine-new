package script;

import Type;
import cpp.CPPInterface;
import com.hurlant.crypto.encoding.binary.Base64;
import backend.Paths;
import flixel.FlxBasic;
import flixel.FlxG;
import flixel.util.FlxColor;
import haxe.CallStack;
import haxe.Json;
import haxe.Log;
import openfl.Assets;
import openfl.Lib;
#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
import psych.script.FunkinLua;
#end
import sys.FileSystem;
import sys.io.File;
import crowplexus.iris.IrisConfig;
import crowplexus.iris.Iris;
import crowplexus.hscript.*;

using StringTools;

@:access(crowplexus.iris.Iris)
class FunkinHScript extends FlxBasic
{
	public var scripts:Array<HScript> = [];

	public function executeAllFunc(name:String, ?args:Array<Any>):Array<Dynamic>
	{
		var returns:Array<Dynamic> = [];

		for (_ in scripts)
		{
			if (_ == null)
				continue;

			try
			{
				returns.push(_.executeFunc(name, args));
			}
			catch (e:Dynamic)
			{
				trace('Error executing $name: $e');
				returns.push(null);
			}
		}

		return returns;
	}

	public function error(msg:String, ?code:String = "error"):Void
	{
		for (_ in scripts)
		{
			if (_ == null)
				continue;

			_.error(msg, code);
		}
	}

	public function initScript(name:String, folder:String)
	{
		if (this == null)
			return;

		var hx:Null<String> = null;

		for (extn in HScriptUtil.extns)
		{
			var path:String = Paths.modFolders(folder + "/" + name);
			if (FileSystem.exists(path))
			{
				try
				{
					hx = File.getContent(path);
					break;
				}
				catch (e:Dynamic)
				{
					trace('Failed to load script: $e');
				}
			}
		}

		if (hx == null)
		{
			trace('Script $name not found in $folder');
			return;
		}
	}

	public function setAll(name:String, val:Dynamic)
	{
		for (_ in scripts)
		{
			if (_ == null)
				continue;

			_.set(name, val);
		}
	}

	public function getAll(name:String):Array<Dynamic>
	{
		var returns:Array<Dynamic> = [];

		for (_ in scripts)
		{
			if (_ == null)
				continue;

			returns.push(_.get(name));
		}

		return returns;
	}

	public function getScriptByTag(tag:String):Null<HScript>
	{
		for (_ in scripts)
		{
			if (_ == null)
				continue;

			if (_.name != null && _.name == tag)
				return _;
		}

		return null;
	}

	/**
		Registers every default variable the engine hands to an HScript: std/openfl/flixel classes,
		the FNF-specific API (`Paths`, `PlayState`, `Conductor`, objects) and the `this` binding.

		`HScript.setDefaultVars()` delegates here, so subclasses like `HScriptUtil` can still
		override the entry point and extend the result.
	**/
	public static function setDefaultVars(hscript:HScript):Void
	{
		hscript._script.preset();

		// `this` follows the interpreter's parent (normally the state the script was made in)
		hscript.set('this', getScriptThis(hscript));

		hscript.set("StringTools", StringTools);

		hscript.set("Type", Type);
		hscript.set("script", hscript);
		hscript.set("Dynamic", Dynamic);
		hscript.set('StringMap', haxe.ds.StringMap);
		hscript.set('IntMap', haxe.ds.IntMap);
		hscript.set('ObjectMap', haxe.ds.ObjectMap);

		hscript.set("Main", Main);
		hscript.set("Lib", openfl.Lib);
		hscript.set("Assets", lime.utils.Assets);
		hscript.set("OpenFlAssets", openfl.utils.Assets);

		hscript.set("FlxG", flixel.FlxG);
		hscript.set("FlxTypedGroup", flixel.group.FlxGroup.FlxTypedGroup);
		hscript.set("FlxSpriteGroup", flixel.group.FlxSpriteGroup);
		hscript.set("FlxSprite", flixel.FlxSprite);
		hscript.set("FlxCamera", flixel.FlxCamera);
		hscript.set("FlxMath", flixel.math.FlxMath);
		hscript.set("FlxTimer", flixel.util.FlxTimer);
		hscript.set("FlxTween", flixel.tweens.FlxTween);
		hscript.set("FlxEase", flixel.tweens.FlxEase);
		hscript.set("FlxSound", flixel.sound.FlxSound);
		hscript.set('FlxColor', script.hscript.HScriptUtil.CustomFlxColor);
		hscript.set("FlxRuntimeShader", flixel.addons.display.FlxRuntimeShader);
		hscript.set("FlxFlicker", flixel.effects.FlxFlicker);
		hscript.set('FlxSpriteUtil', flixel.util.FlxSpriteUtil);
		hscript.set("FlxBackdrop", flixel.addons.display.FlxBackdrop);
		hscript.set("FlxTiledSprite", flixel.addons.display.FlxTiledSprite);

		hscript.set("add", FlxG.state.add);
		hscript.set("remove", FlxG.state.remove);
		hscript.set("insert", FlxG.state.insert);
		hscript.set("members", FlxG.state.members);
		hscript.set('foreground', hscript.foreground);

		hscript.set('FlxCameraFollowStyle', flixel.FlxCamera.FlxCameraFollowStyle);
		hscript.set("FlxTextBorderStyle", flixel.text.FlxText.FlxTextBorderStyle);
		hscript.set("FlxBarFillDirection", flixel.ui.FlxBar.FlxBarFillDirection);

		hscript.set('FlxPoint', flixel.math.FlxPoint.FlxBasePoint); // redirects to flxbasepoint because thats all flxpoints are
		hscript.set("FlxBasePoint", flixel.math.FlxPoint.FlxBasePoint);

		// abstracts
		hscript.set("FlxTextAlign", script.MacroPro.buildAbstract(flixel.text.FlxText.FlxTextAlign));
		hscript.set('FlxAxes', script.MacroPro.buildAbstract(flixel.util.FlxAxes));
		hscript.set('BlendMode', script.MacroPro.buildAbstract(openfl.display.BlendMode));
		hscript.set("FlxKey", script.MacroPro.buildAbstract(flixel.input.keyboard.FlxKey));

		// FNF-specific things
		hscript.set("MusicBeatState", backend.MusicBeatState);
		hscript.set("Paths", Paths);
		hscript.set("Conductor", Conductor);
		hscript.set("Song", Song);
		hscript.set("ClientPrefs", ClientPrefs);
		hscript.set("CoolUtil", CoolUtil);
		hscript.set("StageData", StageData);
		hscript.set("PlayState", PlayState);
		hscript.set("FunkinLua", FunkinLua);
		hscript.set("HScript", HScript);

		// FNF-specific things
		hscript.set("MusicBeatState", backend.MusicBeatState);
		hscript.set("Paths", Paths);
		hscript.set("Conductor", Conductor);
		hscript.set("Song", Song);
		hscript.set("ClientPrefs", ClientPrefs);
		hscript.set("CoolUtil", CoolUtil);
		hscript.set("StageData", StageData);
		hscript.set("PlayState", PlayState);
		hscript.set("FunkinLua", FunkinLua);

		// objects
		hscript.set("Note", Note);
		hscript.set("HealthIcon", HealthIcon);
		hscript.set("Character", Character);
		hscript.set("NoteSplash", NoteSplash);
		hscript.set("BGSprite", BGSprite);
		hscript.set("StrumNote", StrumNote);
		hscript.set("Alphabet", Alphabet);
		hscript.set("AttachedSprite", AttachedSprite);
		hscript.set("AttachedText", AttachedText);

		hscript.set("GameOverSubstate", substates.game.GameOverSubstate);

		if ((FlxG.state is PlayState) && PlayState.instance != null)
		{
			final state:PlayState = PlayState.instance;

			hscript.set("game", state);
			hscript.set("global", state.variables);
			hscript.set("getInstance", HScript.getInstance);

			// why is ther hscriptglobals and variables when they achieve the same thign maybe kill off one or smth
			hscript.set('setGlobalFunc', (name:String, func:Dynamic) -> state.variables.set(name, func));
			hscript.set('callGlobalFunc', (name:String, ?args:Dynamic) ->
			{
				if (state.variables.exists(name))
					return state.variables.get(name)(args);
				else
					return null;
			});

			#if LUA_ALLOWED
			hscript.set('createGlobalCallback', function(name:String, func:Dynamic)
			{
				for (script in PlayState.instance.luaArray)
					if (script != null && script.lua != null && !script.closed)
						Lua_helper.add_callback(script.lua, name, func);
				FunkinLua.customFunctions.set(name, func);
			});
			#end

			#if LUA_ALLOWED
			if (Lua_helper.callbacks != null)
			{
				for (i => value in Lua_helper.callbacks) // 直接遍历键值对
					hscript.set(i, value);
			}
			#end
		}

		// todo rework this
		hscript.set("newShader", function(fragFile:String = null, vertFile:String = null)
		{ // returns a FlxRuntimeShader but with file names lol
			var runtime:flixel.addons.display.FlxRuntimeShader = null;

			try
			{
				runtime = new flixel.addons.display.FlxRuntimeShader(fragFile == null ? null : Paths.getContent(Paths.modsShaderFragment(fragFile)),
					vertFile == null ? null : Paths.getContent(Paths.modsShaderVertex(vertFile)));
			}
			catch (e:Dynamic)
			{
				trace("Shader compilation error:" + e.message);
			}

			return new flixel.addons.display.FlxRuntimeShader();
		});
	}

	/**
		The object a script sees as `this`: the interpreter's parent when it has one,
		otherwise the running PlayState (or the current Flixel state, if there is none).
	**/
	public static function getScriptThis(?hscript:HScript):Dynamic
	{
		if (hscript != null && hscript._script != null && hscript._script.interp != null)
		{
			final interp:Dynamic = hscript._script.interp;

			if (Std.isOfType(interp, InterpPro))
			{
				final pro:InterpPro = cast interp;
				if (pro.parent != null)
					return pro.parent;
			}
		}

		return PlayState.instance != null ? PlayState.instance : FlxG.state;
	}
}

class Script
{
	public var scriptName:String = '';
	public var scriptType:ScriptType = '';

	/**
		Called when the script should be stopped
	**/
	public function stop()
	{
		throw new haxe.exceptions.NotImplementedException();
	}

	/**
		Called to output debug information
	**/
	public function scriptTrace(text:String)
	{
		trace(text); // wow for once its not NotImplementedException
	}

	/**
		Called to set a variable defined in the script
	**/
	public function set(variable:String, data:Dynamic):Void
	{
		throw new haxe.exceptions.NotImplementedException();
	}

	/**
		Called to get a variable defined in the script
	**/
	public function get(key:String):Dynamic
	{
		throw new haxe.exceptions.NotImplementedException();
	}

	/**
		Called to call a function within the script
	**/
	public function call(func:String, ?args:Array<Dynamic>):Dynamic
	{
		throw new haxe.exceptions.NotImplementedException();
	}
}

interface IFunkinScript
{
	public var scriptName:String;
	public var scriptType:ScriptType;
	public function set(variable:String, data:Dynamic):Void;
	public function get(key:String):Dynamic;
	public function call(func:String, ?args:Array<Dynamic>):Dynamic;
	public function stop():Void;
}

enum abstract ScriptType(String) to String from String
{
	public var HSCRIPT:String = 'hscript';
}

@:access(crowplexus.iris.Iris)
class HScript extends Script
{
	public var _script:Iris;
	public var parsingException:Null<String> = null;
	public var name:Null<String> = "_hscript";
	public var parentLua:psych.script.FunkinLua;

	public static final defaultVars:Map<String, Dynamic> = new Map<String, Dynamic>();

	var _group:Null<FunkinHScript>;

	public var foreground:FlxTypedGroup<FlxBasic>;

	public static final exts:Array<String> = ['hx', 'hxs', 'hscript'];

	public static function getPath(path:String)
	{
		for (extension in exts)
		{
			if (path.endsWith(extension))
				return path;

			final file = '$path.$extension';

			for (i in [Paths.modFolders(file)])
			{
				if (!FileSystem.exists(i))
					continue;
				return i;
			}
		}
		return path;
	}

	public static function fromString(script:String, ?name:String = "Script", ?additionalVars:Map<String, Any>)
	{
		return new HScript(script, name, additionalVars);
	}

	public static function fromFile(file:String, ?name:String, ?additionalVars:Map<String, Any>)
	{
		if (name == null)
			name = file;

		return new HScript(File.getContent(file), name, additionalVars);
	}

	public function InitLogger()
	{
		Iris.warn = (x, ?pos) ->
		{
			final message:String = '[${pos.fileName}]: WARN: ${pos.lineNumber} -> $x';
			PlayState.instance.addTextToDebug(message, FlxColor.YELLOW);

			FlxG.log.warn(message);
			// trace(message);

			Iris.logLevel(ERROR, x, pos);
		}

		Iris.error = (x, ?pos) ->
		{
			final message:String = '[${pos.fileName}]: ERROR: ${pos.lineNumber} -> $x';
			PlayState.instance.addTextToDebug(message, FlxColor.RED);
			error(message);

			FlxG.log.error(message);
			// trace(message);

			Iris.logLevel(NONE, x, pos);
		}

		Iris.print = (x, ?pos) ->
		{
			final message:String = '[${pos.fileName}]: TRACE: ${pos.lineNumber} -> $x';
			PlayState.instance.addTextToDebug(message, FlxColor.WHITE);

			// FlxG.log.add(message);

			// trace(message);

			Iris.logLevel(NONE, x, pos);
		}
	}

	public function new(?script:String, ?names:String = "Script", ?additionalVars:Map<String, Any>)
	{
		scriptType = ScriptType.HSCRIPT;
		scriptName = names;

		foreground = new FlxTypedGroup<FlxBasic>();

		_script = new Iris(script, {name: names, autoRun: false, autoPreset: false});
		_script.interp = new InterpPro(FlxG.state);
		_script.interp.showPosOnLog = false;

		setDefaultVars();

		for (variable => arg in defaultVars)
			set(variable, arg);

		if (additionalVars != null)
		{
			for (key => obj in additionalVars)
				set(key, additionalVars.get(obj));
		}

		tryExecute();
		InitLogger();
	}

	override function stop()
	{
		if (_script == null)
			return;
		_script.destroy();
		_script = null;
	}

	override function set(variable:String, data:Dynamic):Void
	{
		_script.set(variable, data);
	}

	override function get(key:String):Dynamic
	{
		return _script.get(key);
	}

	override function call(func:String, ?args:Array<Dynamic>):Dynamic
	{
		var ret:Dynamic = GlobalScript.Function_Continue;
		if (exists(func))
		{
			var result = _script.call(func, args);
			ret = (result != null && result.returnValue != null) ? result.returnValue : GlobalScript.Function_Continue;
		}
		return ret;
	}

	public function exists(varName:String)
	{
		return _script.exists(varName);
	}

	public function executeFunc(func:String, ?parameters:Array<Dynamic>, ?theObject:Any, ?extraVars:Map<String, Dynamic>):Dynamic
	{
		if (extraVars == null)
			extraVars = [];

		if (exists(func))
		{
			var daFunc = get(func);
			if (Reflect.isFunction(daFunc))
			{
				var returnVal:Any = null;
				var defaultShit:Map<String, Dynamic> = [];

				if (theObject != null)
					extraVars.set("this", theObject);

				for (key in extraVars.keys())
				{
					defaultShit.set(key, get(key));
					set(key, extraVars.get(key));
				}

				try
				{
					returnVal = Reflect.callMethod(theObject, daFunc, parameters);
				}
				catch (e:haxe.Exception)
				{
					error(e.message, '${scriptName}: Script Execution Error');
					#if sys
					Sys.println(e.message);
					#end
				}

				for (key in defaultShit.keys())
				{
					set(key, defaultShit.get(key));
				}

				return returnVal;
			}
		}
		return null;
	}

	public function executeString(script:String, ?names:String = "Script", ?additionalVars:Map<String, Any>):Dynamic
	{
		return new HScript(script, names, additionalVars);
	}

	inline function tryExecute()
	{
		var ret:Dynamic = null;
		try
		{
			ret = _script.execute();
		}
		catch (e)
		{
			parsingException = Std.string(e);
			error('PARSING ERROR: $e', '${scriptName}: Script Error');
			PlayState.instance.addTextToDebug('[${scriptName}]: PARSING ERROR: $e', FlxColor.RED);
		}
		return ret;
	}

	public function update(elapsed:Float)
	{
		executeFunc("onUpdate", [elapsed]);
	}

	public function error(errorMsg:String, ?winTitle:Null<String>)
	{
		try
		{
			// Handle null error message
			if (errorMsg == null)
				errorMsg = "Unknown error occurred";

			// Only show error once
			if (alreadyShownError)
				return;
			alreadyShownError = true;

			trace(errorMsg);
			var fullMsg = 'Script Error: $errorMsg';
			var line = getCurLine();
			if (line != null)
			{
				fullMsg += '\n\nLine: $line';
			}
			#if windows
			if (CPPInterface != null)
			{
				CPPInterface.messageBox(fullMsg, winTitle != null ? winTitle : '${scriptName}: Script Error');
			}
			#elseif desktop
			var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
			if (stack != null && stack.length > 0)
			{
				fullMsg += '\n\nStack Trace:\n$stack';
			}
			CoolUtil.showPopUp(fullMsg, winTitle != null ? winTitle : '${scriptName}: Script Error');
			#else
			// Android and web: CoolUtil.showPopUp() is a native dialog (a JNI/UI-thread call on Android)
			// and this runs from script *loading* paths, where it can fail or kill the process instead of
			// reporting the error. Print on the on-screen script overlay the engine already uses outside
			// a song; inside a song that still lands in PlayState's debug text.
			var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
			if (stack != null && stack.length > 0)
			{
				fullMsg += '\n\nStack Trace:\n$stack';
			}
			ScriptDebugOverlay.report(fullMsg, FlxColor.RED);
			#end
		}
		catch (e:Dynamic)
		{
			trace('Failed to display error: $e');
		}
	}

	var alreadyShownError:Bool = false;

	function getCurLine():Null<Int>
	{
		return _script.interp.posInfos() != null ? _script.interp.posInfos().lineNumber : null;
	}

	/**
		The engine's default HScript API lives in `FunkinHScript.setDefaultVars()`; this is kept
		as the overridable entry point (`HScriptUtil` extends it) that the core is registered through.
	**/
	function setDefaultVars():Void
	{
		FunkinHScript.setDefaultVars(this);
	}

	public static inline function getInstance()
	{
		return PlayState.instance.isDead ? GameOverSubstate.instance : PlayState.instance;
	}
}

/**
	The engine's HScript interpreter: everything `crowplexus.hscript.Interp` does, plus the
	"parent" object (usually the state the script was created in) that backs `resolve`,
	`assign` and `evalAssignOp`.
**/
class InterpPro extends crowplexus.hscript.Interp
{
	override function makeIterator(v:Dynamic):Iterator<Dynamic>
	{
		#if ((flash && !flash9) || (php && !php7 && haxe_ver < '4.0.0'))
		if (v.iterator != null)
			v = v.iterator();
		#else
		// DATA CHANGE //does a null check because this crashes on debug build
		if (v.iterator != null)
			try
				v = v.iterator()
			catch (e:Dynamic)
			{
			};
		#end
		if (v.hasNext == null || v.next == null)
			error(EInvalidIterator(v));
		return v;
	}

	public var parent(default, set):Dynamic = [];

	var parentFields:Array<String> = [];

	public function new(?parent:Dynamic)
	{
		super();
		if (parent == null)
			parent = FlxG.state;
		this.parent = parent;
		showPosOnLog = false;
	}

	function set_parent(value:Dynamic):Dynamic
	{
		parent = value;
		parentFields = value != null ? Type.getInstanceFields(Type.getClass(value)) : [];
		return parent;
	}

	override function fcall(o:Dynamic, funcToRun:String, args:Array<Dynamic>):Dynamic
	{
		for (_using in usings)
		{
			var v = _using.call(o, funcToRun, args);
			if (v != null)
				return v;
		}

		var f = get(o, funcToRun);

		if (f == null)
		{
			Iris.error('Tried to call null function $funcToRun', posInfos());
			return null;
		}

		return Reflect.callMethod(o, f, args);
	}

	override function resolve(id:String):Dynamic
	{
		if (locals.exists(id))
		{
			var l = locals.get(id);
			return l.r;
		}

		if (variables.exists(id))
		{
			var v = variables.get(id);
			return v;
		}

		if (imports.exists(id))
		{
			var v = imports.get(id);
			return v;
		}

		if (parent != null && parentFields.contains(id))
		{
			var v = Reflect.getProperty(parent, id);
			if (v != null)
				return v;
		}

		error(EUnknownVariable(id));

		return null;
	}

	// better direct access to the parent
	override function evalAssignOp(op, fop, e1, e2):Dynamic
	{
		var v;
		switch (Tools.expr(e1))
		{
			case EIdent(id):
				var l = locals.get(id);
				v = fop(expr(e1), expr(e2));
				if (l == null)
				{
					if (parentFields.contains(id))
					{
						Reflect.setProperty(parent, id, v);
					}
					else
					{
						setVar(id, v);
					}
				}
				else
				{
					if (l.const != true)
						l.r = v;
					else
						warn(ECustom("Cannot reassign final, for constant expression -> " + id));
				}
			case EField(e, f, s):
				var obj = expr(e);
				if (obj == null)
					if (!s)
						error(EInvalidAccess(f));
					else
						return null;
				v = fop(get(obj, f), expr(e2));
				v = set(obj, f, v);
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr))
				{
					v = fop(getMapValue(arr, index), expr(e2));
					setMapValue(arr, index, v);
				}
				else
				{
					v = fop(arr[index], expr(e2));
					arr[index] = v;
				}
			default:
				return error(EInvalidOp(op));
		}
		return v;
	}

	// better direct access to the parent
	override function assign(e1:Expr, e2:Expr):Dynamic
	{
		var v = expr(e2);
		switch (Tools.expr(e1))
		{
			case EIdent(id):
				var l = locals.get(id);
				if (l == null)
				{
					if (!variables.exists(id) && parentFields.contains(id))
					{
						Reflect.setProperty(parent, id, v);
					}
					else
					{
						setVar(id, v);
					}
				}
				else
				{
					if (l.const != true)
						l.r = v;
					else
						warn(ECustom("Cannot reassign final, for constant expression -> " + id));
				}
			case EField(e, f, s):
				var e = expr(e);
				if (e == null)
					if (!s)
						error(EInvalidAccess(f));
					else
						return null;
				v = set(e, f, v);
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr))
				{
					setMapValue(arr, index, v);
				}
				else
				{
					arr[index] = v;
				}

			default:
				error(EInvalidOp("="));
		}
		return v;
	}
}
