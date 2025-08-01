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
		if (parent == null) parent = FlxG.state;
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

@:access(crowplexus.iris.Iris)
class HScript extends Script
{
	public var _script:Iris;
	public var parsingException:Null<String> = null;
	public var name:Null<String> = "_hscript";
	public var parentLua:FunkinLua;

	var _group:Null<FunkinHScript>;

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

		_script = new Iris(script, {name: names, autoRun: false, autoPreset: false});
		_script.interp = new InterpPro(FlxG.state);
		_script.interp.showPosOnLog = false;

		setDefaultVars();

		if (additionalVars != null)
		{
			for (key => obj in additionalVars)
				set(key, additionalVars.get(obj));
		}

		tryExecute();
		InitLogger();
		
	}
	
	override function stop() {
		if (_script == null) return;
		_script.destroy();
		_script = null;
	}

	override function set(variable:String, data:Dynamic):Void {
		_script.set(variable, data);
	}

	override function get(key:String):Dynamic {
		return _script.get(key);
	}

	override function call(func:String, ?args:Array<Dynamic>):Dynamic {
		var ret:Dynamic = GlobalScript.Function_Continue;
		if (exists(func)) {
			var result = _script.call(func, args);
			ret = (result != null && result.returnValue != null) ? result.returnValue : GlobalScript.Function_Continue;
		}
		return ret;
	}

	public function exists(varName:String) {
		return _script.exists(varName);
	}

	public function executeFunc(func:String, ?parameters:Array<Dynamic>, ?theObject:Any, ?extraVars:Map<String, Dynamic>):Dynamic {
		if (extraVars == null) extraVars = [];

		if (exists(func)) {
			var daFunc = get(func);
			if (Reflect.isFunction(daFunc)) {
				var returnVal:Any = null;
				var defaultShit:Map<String, Dynamic> = [];

				if (theObject != null) extraVars.set("this", theObject);

				for (key in extraVars.keys()) {
					defaultShit.set(key, get(key));
					set(key, extraVars.get(key));
				}

				try {
					returnVal = Reflect.callMethod(theObject, daFunc, parameters);
				}
				catch (e:haxe.Exception) {
					error(e.message, '${scriptName}: Script Execution Error');
					#if sys
					Sys.println(e.message);
					#end
				}

				for (key in defaultShit.keys()) {
					set(key, defaultShit.get(key));
				}

				return returnVal;
			}
		}
		return null;
	}

	public function executeString(script:String, ?names:String = "Script", ?additionalVars:Map<String, Any>):Dynamic {
		return new HScript(script, names, additionalVars);
	}

    inline function tryExecute() {
		var ret:Dynamic = null;
		try {
			ret = _script.execute();
		}
		catch (e) {
			parsingException = Std.string(e);
			error('PARSING ERROR: $e', '${scriptName}: Script Error');
			PlayState.instance.addTextToDebug('[${scriptName}]: PARSING ERROR: $e', FlxColor.RED);
		}
		return ret;
	}

	public function update(elapsed:Float) {
		executeFunc("onUpdate", [elapsed]);
	}

	public function error(errorMsg:String, ?winTitle:Null<String>) {
		try {
			// Handle null error message
			if (errorMsg == null) errorMsg = "Unknown error occurred";
			
			// Only show error once
			if (alreadyShownError) return;
			alreadyShownError = true;
			
			trace(errorMsg);
			var fullMsg = 'Script Error: $errorMsg';
			var line = getCurLine();
			if (line != null) {
				fullMsg += '\n\nLine: $line';
			}
			#if windows
			if (CPPInterface != null) {
				CPPInterface.messageBox(fullMsg, winTitle != null ? winTitle : '${scriptName}: Script Error');
			}
			#else
			var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
			if (stack != null && stack.length > 0) {
				fullMsg += '\n\nStack Trace:\n$stack';
			}
			CoolUtil.showPopUp(fullMsg, winTitle != null ? winTitle : '${scriptName}: Script Error');
			#end
		} catch (e:Dynamic) {

			trace('Failed to display error: $e');
		}
	}

	var alreadyShownError:Bool = false;

	function getCurLine():Null<Int> {
		return _script.interp.posInfos() != null ? _script.interp.posInfos().lineNumber : null;
	}

	function setDefaultVars()
	{
		_script.preset();

		#if LUA_ALLOWED
		if (Lua_helper.callbacks != null) {
			for (i => value in Lua_helper.callbacks) // 直接遍历键值对
				set(i, value);
		}
		#end

		set("StringTools", StringTools);

		set("Type", Type);
		set("script", this);
		set("Dynamic", Dynamic);
		set('StringMap', haxe.ds.StringMap);
		set('IntMap', haxe.ds.IntMap);
		set('ObjectMap', haxe.ds.ObjectMap);

		set("Main", Main);
		set("Lib", openfl.Lib);
		set("Assets", lime.utils.Assets);
		set("OpenFlAssets", openfl.utils.Assets);

		set("FlxG", flixel.FlxG);
		set("FlxTypedGroup", flixel.group.FlxGroup.FlxTypedGroup);
		set("FlxSpriteGroup", flixel.group.FlxSpriteGroup);
		set("FlxSprite", flixel.FlxSprite);
		set("FlxCamera", flixel.FlxCamera);
		set("FlxMath", flixel.math.FlxMath);
		set("FlxTimer", flixel.util.FlxTimer);
		set("FlxTween", flixel.tweens.FlxTween);
		set("FlxEase", flixel.tweens.FlxEase);
		set("FlxSound", flixel.sound.FlxSound);
		set('FlxColor', script.hscript.HScriptUtil.CustomFlxColor);
		set("FlxRuntimeShader", flixel.addons.display.FlxRuntimeShader);
		set("FlxFlicker", flixel.effects.FlxFlicker);
		set('FlxSpriteUtil', flixel.util.FlxSpriteUtil);
		set("FlxBackdrop", flixel.addons.display.FlxBackdrop);
		set("FlxTiledSprite", flixel.addons.display.FlxTiledSprite);

		set("add", FlxG.state.add);
		set("remove", FlxG.state.remove);
		set("insert", FlxG.state.insert);
		set("members", FlxG.state.members);

		set('FlxCameraFollowStyle', flixel.FlxCamera.FlxCameraFollowStyle);
		set("FlxTextBorderStyle", flixel.text.FlxText.FlxTextBorderStyle);
		set("FlxBarFillDirection", flixel.ui.FlxBar.FlxBarFillDirection);

		set('FlxPoint', flixel.math.FlxPoint.FlxBasePoint); // redirects to flxbasepoint because thats all flxpoints are
		set("FlxBasePoint", flixel.math.FlxPoint.FlxBasePoint);

		// abstracts
		set("FlxTextAlign", script.MacroPro.buildAbstract(flixel.text.FlxText.FlxTextAlign));
		set('FlxAxes', script.MacroPro.buildAbstract(flixel.util.FlxAxes));
		set('BlendMode', script.MacroPro.buildAbstract(openfl.display.BlendMode));
		set("FlxKey", script.MacroPro.buildAbstract(flixel.input.keyboard.FlxKey));

		// FNF-specific things
		set("MusicBeatState", backend.MusicBeatState);
		set("Paths", Paths);
		set("Conductor", Conductor);
		set("Song", Song);
		set("ClientPrefs", ClientPrefs);
		set("CoolUtil", CoolUtil);
		set("StageData", StageData);
		set("PlayState", PlayState);
		set("FunkinLua", FunkinLua);
		set("HScript", HScript);

		// FNF-specific things
		set("MusicBeatState", backend.MusicBeatState);
		set("Paths", Paths);
		set("Conductor", Conductor);
		set("Song", Song);
		set("ClientPrefs", ClientPrefs);
		set("CoolUtil", CoolUtil);
		set("StageData", StageData);
		set("PlayState", PlayState);
		set("FunkinLua", FunkinLua);

		// objects
		set("Note", Note);
		set("HealthIcon", HealthIcon);
		set("Character", Character);
		set("NoteSplash", NoteSplash);
		set("BGSprite", BGSprite);
		set("StrumNote", StrumNote);
		set("Alphabet", Alphabet);
		set("AttachedSprite", AttachedSprite);
		set("AttachedText", AttachedText);

		set("GameOverSubstate", substates.game.GameOverSubstate);

		if ((FlxG.state is PlayState) && PlayState.instance != null)
		{
			final state:PlayState = PlayState.instance;

			set("game", state);
			set("global", state.variables);
			set("getInstance", getInstance);

			// why is ther hscriptglobals and variables when they achieve the same thign maybe kill off one or smth
			set('setGlobalFunc', (name:String, func:Dynamic) -> state.variables.set(name, func));
			set('callGlobalFunc', (name:String, ?args:Dynamic) ->
			{
				if (state.variables.exists(name))
					return state.variables.get(name)(args);
				else
					return null;
			});

			#if LUA_ALLOWED
			set('createGlobalCallback', function(name:String, func:Dynamic) {
				for (script in PlayState.instance.luaArray)
					if(script != null && script.lua != null && !script.closed)
						Lua_helper.add_callback(script.lua, name, func);
				FunkinLua.customFunctions.set(name, func);
			});
			#end
		}

		// todo rework this
		set("newShader", function(fragFile:String = null, vertFile:String = null) { // returns a FlxRuntimeShader but with file names lol
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

	public static inline function getInstance()
	{
		return PlayState.instance.isDead ? GameOverSubstate.instance : PlayState.instance;
	}
}
