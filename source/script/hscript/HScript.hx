package script.hscript;

import Type;
import cpp.CPPInterface;
import flixel.FlxBasic;
import flixel.FlxG;
import flixel.util.FlxColor;
import haxe.CallStack;
import haxe.Json;
import haxe.Log;
import openfl.Lib;
import sys.FileSystem;
import sys.io.File;
import openfl.Assets;
import com.hurlant.crypto.encoding.binary.Base64;
import backend.Paths;
#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
import psych.script.FunkinLua;
#end
import crowplexus.iris.IrisConfig;
import crowplexus.iris.Iris;
import crowplexus.hscript.*;
import script.FunkinHScript;
import script.hscript.*;

using StringTools;

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
			#else
			var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
			if (stack != null && stack.length > 0)
			{
				fullMsg += '\n\nStack Trace:\n$stack';
			}
			CoolUtil.showPopUp(fullMsg, winTitle != null ? winTitle : '${scriptName}: Script Error');
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
		The engine's default HScript API lives in `script.FunkinHScript.setDefaultVars()`; this is kept
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
