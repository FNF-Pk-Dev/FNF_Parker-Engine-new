package script;

#if LUA_ALLOWED
import llua.Convert;
import llua.Lua;
import llua.LuaL;
import llua.State;
#end
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.graphics.FlxGraphic;
import flixel.system.FlxAssets.FlxShader;
import flixel.addons.display.FlxRuntimeShader;
import openfl.Lib;
import openfl.display.BlendMode;
import openfl.filters.ShaderFilter;
import openfl.system.Capabilities;
import hxvlc.flixel.FlxVideo;
import hxvlc.flixel.FlxVideoSprite;
import hxvlc.util.Handle;
import haxe.Json;
#if sys
import sys.FileSystem;
import sys.io.File;
import Sys;
#end

/**
 * `.lscript` runtime: this class owns the whole Luau side of an LScript by itself, on `llua.Lua`
 * / `llua.LuaL` / `llua.Convert` (the same plumbing `psych.script.FunkinLua` drives Lua with).
 * It does not use `lscript.LScript` or any of its helpers any more, and it never installs a
 * metatable on `_G`; see `installBridge()` and `call()` for what that rules out.
 *
 * How a script sees Haxe:
 *
 * - the constructor creates one Luau state, runs the Lua bridge (`PRELUDE`) and binds every global
 *   a script may touch; the script body is only run by `execute()`.
 * - primitives stay primitives, engine functions become Lua functions, every other Haxe value
 *   (classes included) becomes a proxy table (`pushProxy()`): reading a field, writing one and
 *   calling a method go back to Haxe through `luaIndex()`, `luaSetProp()` and `luaInvoke()`.
 *   Nothing is reflected onto the script's `parent` any more, so scripts read engine state through
 *   `this` / `game` / the globals `setParent()` and the state hand them.
 * - every callback the engine dispatches is looked up as a plain global (`call()`), and an
 *   undefined one is simply absent - skipping it is a no-op instead of an unprotected globals
 *   lookup that took the process down.
 */
class FunkinLScript extends GlobalScript
{
	#if LUA_ALLOWED
	/** Runtime this script's `State` belongs to, kept for `close()` and for debugging. */
	public var lua(default, null):State;

	/** Name the engine matches the script by (see `GlobalScript.scriptMatchesTag()`). */
	public var scriptName(default, null):String;

	/** Group a script can put sprites in, the `foreground` global. */
	public var foreground:FlxTypedGroup<FlxBasic>;

	/** Variables every script is given, filled by `PlayState.setDefaultLScripts()`. */
	public static final defaultVars:Map<String, Dynamic> = new Map<String, Dynamic>();

	/**
	 * Every callback the engine can dispatch to a script: the vocabulary of `PlayState.callOnScripts()`
	 * (`callOnLuas()` / `callOnHScripts()` / `callOnLScripts()` / `callOnPScripts()` call sites) plus the
	 * ones `LScriptSState` dispatches itself.
	 *
	 * A script is not expected to define all of them: dispatch reads the name as a plain global and an
	 * absent one is skipped (see `call()`). A new engine callback has to be added here, otherwise `call()`
	 * reports it on screen instead of dispatching it.
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

	// ------------------------------------------------------------------ bridge

	/** Kind of a bridge descriptor: the engine has no value to hand over (see `describe()`). */
	static inline final KIND_NONE:Int = 0;

	/** Kind of a bridge descriptor: a plain value, pushed as `descriptor[1]`. */
	static inline final KIND_VALUE:Int = 1;

	/** Kind of a bridge descriptor: something callable. */
	static inline final KIND_FUNCTION:Int = 2;

	/** Kind of a bridge descriptor: a Haxe value the script gets as a proxy (see `pushProxy()`). */
	static inline final KIND_REF:Int = 3;

	/** Field of a proxy table holding the id of the Haxe value behind it. */
	static inline final REF_FIELD:String = '__lscript_ref';

	/** Global holding the proxy metatable, installed by `PRELUDE`. */
	static inline final PROXY:String = '__lscript_proxy';

	/** Global holding the `function(name)` factory behind `bind()`, installed by `PRELUDE`. */
	static inline final BIND_HELPER:String = '__lscript_bind';

	/**
	 * Lua side of the bridge, run before anything is bound.
	 *
	 * Proxies read and write through `__lscript_index()` / `__lscript_setprop()` and call through
	 * `__lscript_invoke()`, which are the Haxe functions of the same name in this class. A callable
	 * field is handed out as a closure that drops the object of an `obj:method(...)` call before
	 * calling back, so both call styles work, and the value a call returns is decoded by the same
	 * rules as any other descriptor: `{1, value}` is a value, `{2, ...}` a function, `{3, id}` a
	 * proxy of its own.
	 */
	static final PRELUDE:String = '
-- Proxy tables stand in for the Haxe values a script reaches (`__lscript_ref` is the id of one).
__lscript_proxy = {
	__index = function(t, key)
		local ref = rawget(t, "__lscript_ref")
		local r = __lscript_index(ref, key)
		if r == nil or r[1] == 0 then
			return nil
		end
		if r[1] == 1 then
			return r[2]
		end
		if r[1] == 3 then
			return __lscript_wrap(r[2])
		end
		-- A function field: call it back by name so the engine converts the result itself.
		return function(...)
			local args = {...}
			local first = args[1]
			if type(first) == "table" and rawget(first, "__lscript_ref") == ref then
				table.remove(args, 1)
			end
			return __lscript_decode(__lscript_invoke(ref, key, args))
		end
	end,
	__newindex = function(t, key, value)
		__lscript_setprop(rawget(t, "__lscript_ref"), key, value)
	end,
	__len = function(t)
		return __lscript_len(rawget(t, "__lscript_ref"))
	end,
	__tostring = function(t)
		return __lscript_tostring(rawget(t, "__lscript_ref"))
	end,
}

-- One table per Haxe value, so two reads of the same field stay equal for the script. Weak, so a
-- proxy the script no longer holds does not keep itself alive.
__lscript_wrapped = setmetatable({}, {__mode = "v"})

function __lscript_wrap(ref)
	local t = __lscript_wrapped[ref]
	if t == nil then
		t = setmetatable({__lscript_ref = ref}, __lscript_proxy)
		__lscript_wrapped[ref] = t
	end
	return t
end

function __lscript_decode(r)
	if r == nil or r[1] == 0 then
		return nil
	end
	if r[1] == 1 then
		return r[2]
	end
	if r[1] == 3 then
		return __lscript_wrap(r[2])
	end
	return r[2]
end

-- Engine functions are wrapped on this side too, so what they return is converted by the engine.
function __lscript_bind(name)
	return function(...)
		return __lscript_decode(__lscript_call(name, {...}))
	end
end
';

	/** Haxe functions the script calls by name, see `bind()`. */
	var bindings:Map<String, Dynamic> = new Map<String, Dynamic>();

	/** Haxe values behind the proxy tables the script holds, keyed by the id those tables carry. */
	var refs:Map<Int, Dynamic> = new Map<Int, Dynamic>();

	/** Ids already handed out, so a value the script sees twice stays one proxy (`registerRef()`). */
	var refIds:haxe.ds.ObjectMap<Dynamic, Int> = new haxe.ds.ObjectMap<Dynamic, Int>();

	var nextRef:Int = 0;
	var filePath:Null<String>;
	var closed:Bool = false;
	var executed:Bool = false;

	/**
	 * Whether script code is running right now. Closing a Luau state while a call is still on the
	 * stack inside it would take the VM down, so a script that stops itself is closed afterwards
	 * (see `stop()` and `call()`).
	 */
	var running:Bool = false;

	/**
	 * Sets up the script's arena: a Luau state, the Lua bridge and every global a script may touch.
	 * `executeScript` runs the body right after that (the default is to leave it to `execute()`, so
	 * callers can rebind globals through `setParent()` first).
	 */
	public function new(fileName:String, ?executeScript:Bool = false)
	{
		filePath = fileName;
		scriptName = 'FunkinLScript' + fileName;
		foreground = new FlxTypedGroup<FlxBasic>();

		if (createState())
		{
			installBridge();
			setupEnvironment();

			for (variable => arg in defaultVars)
				set(variable, arg);
		}

		if (executeScript)
			execute();
	}

	/** Creates this script's Luau state, reporting a failure instead of throwing one. */
	function createState():Bool
	{
		try
		{
			lua = LuaL.newstate();
			if (lua == null)
			{
				scriptMessage('$scriptName: could not create a Luau state', FlxColor.RED);
				return false;
			}

			LuaL.openlibs(lua);
			return true;
		}
		catch (e:Dynamic)
		{
			scriptMessage('$scriptName: could not create a Luau state: ' + Std.string(e), FlxColor.RED);
			lua = null;
			return false;
		}
	}

	/**
	 * Puts the Lua side of the bridge in place (`PRELUDE`) and the Haxe ends of it in the globals.
	 *
	 * The bridge functions are bound to this script's instance, so they reach this script's `refs` /
	 * `bindings` without any global "current script" pointer - the reason the old runtime needed one
	 * was `lscript`'s C callbacks, which cannot know which script they belong to.
	 */
	function installBridge():Void
	{
		if (!runChunk('lscript bridge', PRELUDE))
			return;

		bindBridgeFunction('__lscript_index', luaIndex);
		bindBridgeFunction('__lscript_invoke', luaInvoke);
		bindBridgeFunction('__lscript_setprop', luaSetProp);
		bindBridgeFunction('__lscript_len', luaLen);
		bindBridgeFunction('__lscript_tostring', luaToString);
		bindBridgeFunction('__lscript_call', luaCall);
	}

	/** Puts a Haxe function in the globals as itself, so Lua calls it directly. */
	function bindBridgeFunction(name:String, fn:Dynamic):Void
	{
		Convert.toLua(lua, fn);
		Lua.setglobal(lua, name);
	}

	/**
	 * Loads `code` and runs it. Syntax errors, runtime errors and a Haxe exception that escaped a
	 * bound function are all reported through `scriptMessage()`: nothing an error path raises may
	 * reach the VM's own handling, which is what used to abort the process.
	 *
	 * A chunk that does not run leaves the state closed: the script has nothing to dispatch to then.
	 * A null or empty chunk never reaches the VM at all - it is one of the reported failures below.
	 */
	function runChunk(chunkName:String, code:String):Bool
	{
		if (lua == null)
			return false;

		// The native loader takes both strings as `const char*` and starts with `strlen()` on them
		// (`linc::luau::load_source`, and the same function again as CodeGen's fallback), so a null
		// or absent chunk has to be refused before it is handed over: on Android, where a script path
		// that resolves to nothing is normal, that used to be an instant process death rather than a
		// failure anything could report. `scriptMessage()` / `ScriptDebugOverlay` are the only
		// reporting used on the way out - no native dialog, which cannot be raised from here safely.
		if (code == null || code.length == 0)
		{
			scriptMessage('Failed to parse script at ${describePath(filePath)}: the script is empty', FlxColor.RED);
			closeState();
			return false;
		}

		// The name is what a Luau error message points at, and it goes to the native loader too, so it
		// falls back to the script's own path (or a readable stand-in) when a caller passes nothing.
		final name:String = (chunkName != null && chunkName.length > 0) ? chunkName : describePath(filePath);

		var success:Bool = false;
		var failure:Null<String> = null;

		running = true;
		try
		{
			if (LuaL.luau_loadsource(lua, name, code) != Lua.LUA_OK)
				failure = 'Failed to parse script at ${describePath(filePath)}: ${takeError()}';
			else if (Lua.pcall(lua, 0, 0, 0) != Lua.LUA_OK)
				failure = 'Failed to run script at ${describePath(filePath)}: ${takeError()}';
			else
				success = true;
		}
		catch (e:Dynamic)
		{
			failure = 'Failed to run script at ${describePath(filePath)}: ' + Std.string(e);
		}
		running = false;

		if (failure != null)
			scriptMessage(failure, FlxColor.RED);

		// The chunk may have stopped the script that owns this state (see `stop()`), in which case
		// closing it had to wait until here.
		if (!success || closed)
			closeState();

		return success;
	}

	/**
	 * Reads and pops the error message the VM left on the stack. A stack entry that is not a string
	 * (and so gives `Lua.tostring()` nothing) still has to produce a readable message: this text goes
	 * into the failure that gets reported.
	 */
	function takeError():String
	{
		if (lua == null)
			return 'unknown error';

		final message:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);

		final trimmed:String = message != null ? message.trim() : '';
		return trimmed.length > 0 ? trimmed : 'unknown error';
	}

	/**
	 * `filePath` the way a report spells it. A script built without a usable path (the constructor's
	 * `fileName`, which is also what `Paths.getContent()` and the native loader are given) reads as a
	 * stand-in instead of as an empty string or `null` in the message.
	 */
	static inline function describePath(path:Null<String>):String
		return (path != null && path.length > 0) ? path : 'unknown script';

	/**
	 * Reads the script file the constructor was given. A path that was never usable is a reported
	 * failure like an unreadable file: handing it to the filesystem would be another native call with
	 * nothing in it.
	 */
	function readScript():Null<String>
	{
		if (filePath == null || filePath.length == 0)
		{
			scriptMessage('LScript: script not found: ${describePath(filePath)}', FlxColor.RED);
			return null;
		}

		try
		{
			final code:Null<String> = Paths.getContent(filePath);
			if (code == null)
				scriptMessage('LScript: script not found: ${describePath(filePath)}', FlxColor.RED);

			return code;
		}
		catch (e:Dynamic)
		{
			scriptMessage('Failed to read script at ${describePath(filePath)}: ' + Std.string(e), FlxColor.RED);
			return null;
		}
	}

	/** The state scripts act on: the ongoing song if there is one, otherwise the current state. */
	function getCurrentState():Dynamic
	{
		return PlayState.instance != null ? PlayState.instance : FlxG.state;
	}

	#if android
	/**
	 * Calls a method of the current state, used for states that have no `PlayState.instance`.
	 */
	function callCurrentState(name:String, ?args:Array<Dynamic>):Void
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

	// ------------------------------------------------------- Haxe -> Lua values

	/**
	 * Pushes `value` for the script to see: primitives as themselves, functions as a callable
	 * closure and everything else as a proxy table of its own (`pushProxy()`).
	 */
	function pushValue(value:Dynamic):Void
	{
		switch (Type.typeof(value))
		{
			case TNull:
				Lua.pushnil(lua);
			case TBool:
				Lua.pushboolean(lua, value);
			case TInt:
				Lua.pushinteger(lua, cast(value, Int));
			case TFloat:
				Lua.pushnumber(lua, value);
			case TClass(String):
				Lua.pushstring(lua, cast value);
			case TFunction:
				Convert.toLua(lua, value);
			default:
				pushProxy(value);
		}
	}

	/**
	 * Pushes a proxy table for `value`. The table holds nothing but the id of the value: every read,
	 * write and call on it goes back to Haxe (`luaIndex()`, `luaSetProp()`, `luaInvoke()`), so a
	 * script sees live engine objects instead of a copy made once at binding time.
	 */
	function pushProxy(value:Dynamic):Void
	{
		final ref:Int = registerRef(value);

		Lua.createtable(lua, 0, 0);
		Lua.pushinteger(lua, ref);
		Lua.setfield(lua, -2, REF_FIELD);
		Lua.getglobal(lua, PROXY);
		Lua.setmetatable(lua, -2);
	}

	/** Id of `value` in `refs`, reused for a value the script already got a proxy for. */
	function registerRef(value:Dynamic):Int
	{
		final known:Null<Int> = refIds.get(value);
		if (known != null)
			return known;

		final ref:Int = nextRef++;
		refIds.set(value, ref);
		refs.set(ref, value);
		return ref;
	}

	/**
	 * Describes a Haxe value the Lua side asked for, as `[kind, value]`. `null` becomes
	 * `[KIND_NONE]` rather than a nil return: the callback path turns a `null` result into `0`, which
	 * a script cannot tell from a number.
	 */
	function describe(value:Dynamic):Dynamic
	{
		switch (Type.typeof(value))
		{
			case TNull:
				return [KIND_NONE];
			case TBool | TInt | TFloat:
				return [KIND_VALUE, value];
			case TClass(String):
				return [KIND_VALUE, value];
			case TFunction:
				return [KIND_FUNCTION, value];
			default:
				return [KIND_REF, registerRef(value)];
		}
	}

	/** Resolves a value an argument carries: a proxy table arrives as the Haxe value it stands for. */
	function unwrap(value:Dynamic):Dynamic
	{
		if (value == null)
			return null;

		switch (Type.typeof(value))
		{
			case TObject:
				if (!Reflect.hasField(value, REF_FIELD))
					return value;

				final ref:Dynamic = Reflect.field(value, REF_FIELD);
				final id:Int = Std.int(cast ref);
				return refs.exists(id) ? refs.get(id) : value;
			case TClass(Array):
				final values:Array<Dynamic> = cast value;
				for (i in 0...values.length)
					values[i] = unwrap(values[i]);
				return values;
			default:
				return value;
		}
	}

	/** `unwrap()`s an argument list, `[]` when the script passed nothing. */
	function unwrapArgs(?args:Array<Dynamic>):Array<Dynamic>
	{
		final unwrapped:Array<Dynamic> = [];
		if (args == null)
			return unwrapped;

		for (arg in args)
			unwrapped.push(unwrap(arg));

		return unwrapped;
	}

	// ------------------------------------------------------- Lua -> Haxe bridge

	/** Lua reads a field off the value behind `ref`: the proxy's `__index`. */
	function luaIndex(ref:Int, key:Dynamic):Dynamic
	{
		try
		{
			final target:Dynamic = refs.get(ref);
			final name:String = keyName(key);
			if (target == null || name == null)
				return [KIND_NONE];

			if (isMap(target))
			{
				final map:haxe.Constraints.IMap<Dynamic, Dynamic> = cast target;
				return map.exists(name) ? describe(map.get(name)) : [KIND_NONE];
			}

			if (isClass(target))
			{
				if (name == 'new')
					return [KIND_FUNCTION];

				// Only a class' statics: looking a name up on a class otherwise makes hxcpp build a
				// throwaway instance of it just to read the field (see `Class_obj::__Field`).
				if (!Type.getClassFields(cast target).contains(name))
					return [KIND_NONE];
			}
			else if (isArray(target))
			{
				final index:Int = arrayIndex(name);
				if (index >= 0)
				{
					final values:Array<Dynamic> = cast target;
					return index < values.length ? describe(values[index]) : [KIND_NONE];
				}
			}

			return describe(Reflect.getProperty(target, name));
		}
		catch (e:Dynamic)
		{
			reportFailure('could not read "' + Std.string(key) + '"', e);
			return [KIND_NONE];
		}
	}

	/** Lua writes a field on the value behind `ref`: the proxy's `__newindex`. */
	function luaSetProp(ref:Int, key:Dynamic, value:Dynamic):Void
	{
		try
		{
			final target:Dynamic = refs.get(ref);
			final name:String = keyName(key);
			if (target == null || name == null)
				return;

			final unwrapped:Dynamic = unwrap(value);

			if (isMap(target))
			{
				(cast target : haxe.Constraints.IMap<Dynamic, Dynamic>).set(name, unwrapped);
				return;
			}

			if (isArray(target))
			{
				final index:Int = arrayIndex(name);
				if (index >= 0)
				{
					final values:Array<Dynamic> = cast target;
					if (index < values.length)
						values[index] = unwrapped;
					else
						values.push(unwrapped);
					return;
				}
			}

			Reflect.setProperty(target, name, unwrapped);
		}
		catch (e:Dynamic)
		{
			reportFailure('could not set "' + Std.string(key) + '"', e);
		}
	}

	/** Lua calls something on the value behind `ref`: the proxy's method path and `Class:new()`. */
	function luaInvoke(ref:Int, key:Dynamic, ?args:Array<Dynamic>):Dynamic
	{
		try
		{
			final target:Dynamic = refs.get(ref);
			final name:String = keyName(key);
			if (target == null || name == null)
				return [KIND_NONE];

			final callArgs:Array<Dynamic> = unwrapArgs(args);

			if (isClass(target) && name == 'new')
				return describe(Type.createInstance(cast target, callArgs));

			final fn:Dynamic = isMap(target) ? (cast target : haxe.Constraints.IMap<Dynamic, Dynamic>).get(name) : Reflect.getProperty(target, name);

			if (fn == null || !Reflect.isFunction(fn))
				return [KIND_NONE];

			// Member functions already carry their object (`HX_DEFINE_DYNAMIC_FUNC*`), so nothing
			// has to be passed as `this` here - that is what makes `obj.method(a)` work as well.
			return describe(Reflect.callMethod(null, fn, callArgs));
		}
		catch (e:Dynamic)
		{
			reportFailure('could not call "' + Std.string(key) + '"', e);
			return [KIND_NONE];
		}
	}

	/** Length of the value behind `ref`, for Lua's `#` (the proxy's `__len`). */
	function luaLen(ref:Int):Int
	{
		final target:Dynamic = refs.get(ref);
		return isArray(target) ? (cast target : Array<Dynamic>).length : 0;
	}

	/** `tostring()` of the value behind `ref` (the proxy's `__tostring`). */
	function luaToString(ref:Int):String
	{
		final target:Dynamic = refs.get(ref);
		return target == null ? 'nil' : Std.string(target);
	}

	/** Lua calls one of the script's engine functions by name, see `bind()`. */
	function luaCall(name:String, ?args:Array<Dynamic>):Dynamic
	{
		try
		{
			final fn:Dynamic = bindings.get(name);
			if (fn == null)
				return [KIND_NONE];

			return describe(Reflect.callMethod(null, fn, unwrapArgs(args)));
		}
		catch (e:Dynamic)
		{
			reportFailure('"' + name + '" failed', e);
			return [KIND_NONE];
		}
	}

	/** Lua keys reach Haxe as numbers for array indices and strings for fields; Haxe wants one name. */
	static function keyName(key:Dynamic):Null<String>
	{
		if (key == null)
			return null;

		final name:String = Std.string(key).trim();
		return name.length > 0 ? name : null;
	}

	/** Whether `name` addresses an array element, as a Haxe (0-based) index, `-1` when it does not. */
	static function arrayIndex(name:String):Int
	{
		final index:Null<Int> = Std.parseInt(name);
		return (index != null && index > 0) ? index - 1 : -1;
	}

	static inline function isArray(value:Dynamic):Bool
		return (value is Array);

	static inline function isMap(value:Dynamic):Bool
		return (value is haxe.Constraints.IMap);

	/** Whether `value` is a class rather than an instance of one. */
	static inline function isClass(value:Dynamic):Bool
		return (value is Class);

	// ------------------------------------------------------------------ engine API

	/**
	 * Runs the script body once, then fires `onCreate` - the order `PlayState` and `LScriptSState`
	 * rely on. A second call is a no-op: running the body again would redefine every function and
	 * replay its side effects.
	 */
	public function execute():Void
	{
		if (closed || executed)
			return;

		executed = true;

		if (lua == null)
			return;

		final code:Null<String> = readScript();
		if (code == null)
			return;

		// The chunk is named after the file, which is what a Luau error message points at then (it
		// used to be a bare "script").
		if (!runChunk(filePath != null ? filePath : 'script', code))
			return;

		call('onCreate', []);
	}

	/**
	 * Fires the script callback `method` with `args`.
	 *
	 * A callback the script did not define is simply not there: dispatch reads the name as a global and
	 * skips a nil/absent one. That lookup used to go through `lscript`'s `_G` metatable, whose `__index`
	 * reflected the name onto `script.parent` in an unprotected call - an error there ended the process
	 * with no crash log, which is what this runtime exists to not do.
	 *
	 * Errors raised *inside* the callback are reported on screen and turn into `Function_Continue`, and
	 * a paused script is never dispatched to at all.
	 */
	public function call(method:String, ?args:Array<Dynamic>):Dynamic
	{
		if (closed || lua == null)
			return GlobalScript.Function_Continue;

		if (!CALLBACKS.contains(method))
		{
			scriptMessage('$scriptName: "$method" is not a dispatchable callback, skipping it', FlxColor.RED);
			return GlobalScript.Function_Continue;
		}

		if (paused)
			return GlobalScript.Function_Continue;

		var result:Dynamic = GlobalScript.Function_Continue;
		var failure:Null<String> = null;

		running = true;
		try
		{
			Lua.getglobal(lua, method);
			if (isCallable(-1))
			{
				final callArgs:Array<Dynamic> = args != null ? args : [];
				for (arg in callArgs)
					pushValue(arg);

				final status:Int = Lua.pcall(lua, callArgs.length, 1, 0);
				if (status != Lua.LUA_OK)
				{
					failure = 'Failed to call function "$method" at ${describePath(filePath)}: ${takeError()}';
				}
				else
				{
					// A callback that returns nothing has to leave the engine's chain on "continue":
					// an absent result read as a number (or null) would look like a return value.
					final returned:Dynamic = isNil(-1) ? null : unwrap(Convert.fromLua(lua, -1));
					Lua.pop(lua, 1);

					if (returned != null)
						result = returned;
				}
			}
			else
			{
				Lua.pop(lua, 1);
			}
		}
		catch (e:Dynamic)
		{
			failure = 'Failed to call function "$method" at ${describePath(filePath)}: ' + Std.string(e);
		}
		running = false;

		if (failure != null)
			scriptMessage(failure, FlxColor.RED);

		// The callback may have stopped the script it belongs to (see `stop()`), which can only be
		// closed here, now that nothing is running inside it any more.
		if (closed)
			closeState();

		return result;
	}

	/** Whether the script has a callback/function called `name`. */
	public function hasFunction(name:String):Bool
	{
		if (closed || lua == null || name == null)
			return false;

		Lua.getglobal(lua, name);
		final present:Bool = isCallable(-1);
		Lua.pop(lua, 1);
		return present;
	}

	/**
	 * Value of the script global `name`, as Haxe sees it: a proxy comes back as the Haxe value behind
	 * it, and a Lua function as a `llua.LuaCallback` (see `Convert.fromLua()`).
	 */
	public function get(name:String):Dynamic
	{
		if (closed || lua == null || name == null)
			return null;

		Lua.getglobal(lua, name);
		final value:Dynamic = isNil(-1) ? null : unwrap(Convert.fromLua(lua, -1));
		Lua.pop(lua, 1);
		return value;
	}

	/**
	 * Binds `value` as the script global `name`.
	 *
	 * Functions go through `bind()`, so calling one from the script comes back through the bridge and
	 * the engine converts what it returns; everything else is pushed as a value or a proxy of its own.
	 * The external `set()` calls a scripted state makes after `setParent()` land here too.
	 */
	public function set(name:String, value:Dynamic):Void
	{
		if (closed || lua == null || name == null)
			return;

		if (Reflect.isFunction(value))
		{
			bind(name, value);
			return;
		}

		// Only what this call pushes is dropped on failure: `set()` may well run while another call
		// is holding values on the same stack (an engine function handing a global back from script
		// code), and clearing the whole stack there would break that call.
		final top:Int = Lua.gettop(lua);
		try
		{
			pushValue(value);
			Lua.setglobal(lua, name);
		}
		catch (e:Dynamic)
		{
			Lua.settop(lua, top);
			scriptMessage('$scriptName: could not set "$name": ' + Std.string(e), FlxColor.RED);
		}
	}

	/** Binds a class under its own name, the way `set()` does for any other value. */
	public function setClass(value:Class<Dynamic>):Void
	{
		if (closed || lua == null || value == null)
			return;

		set(Type.getClassName(value).split('.').pop(), value);
	}

	/**
	 * Makes the Haxe function `fn` callable from the script as the global `name`.
	 *
	 * The script gets a Lua wrapper that calls back into `luaCall()`, which is what keeps engine
	 * functions on the bridge: an error they raise is reported instead of unwinding into the VM, and
	 * a value they return is converted here rather than by the raw callback path.
	 *
	 * The name goes to `Lua.pushstring()` and `Lua.setglobal()`, which take it as a `const char*` and
	 * `strlen()` it, so a name-less bind is refused and reported here rather than handed over - `set()`
	 * already refuses a null name, this keeps the native boundary safe on its own.
	 */
	function bind(name:String, fn:Dynamic):Void
	{
		if (name == null || name.length == 0)
		{
			scriptMessage('$scriptName: could not bind a global without a name', FlxColor.RED);
			return;
		}

		bindings.set(name, fn);

		final top:Int = Lua.gettop(lua);
		try
		{
			Lua.getglobal(lua, BIND_HELPER);
			if (!isCallable(-1))
			{
				Lua.settop(lua, top);
				return;
			}

			Lua.pushstring(lua, name);
			if (Lua.pcall(lua, 1, 1, 0) != Lua.LUA_OK)
				scriptMessage('$scriptName: could not bind "$name": ${takeError()}', FlxColor.RED);
			else
				Lua.setglobal(lua, name);
		}
		catch (e:Dynamic)
		{
			Lua.settop(lua, top);
			scriptMessage('$scriptName: could not bind "$name": ' + Std.string(e), FlxColor.RED);
		}
	}

	/**
	 * Points the script at the state it runs on: `this` and `game` become `parent`, and so do the
	 * `add` / `remove` / `insert` / `members` globals that were bound to `FlxG.state` while the
	 * wrapper had no state yet (see `LScriptSState.loadScript()`).
	 *
	 * There is no `script.parent` behind it any more: a global a script assigns now stays in the
	 * script instead of landing on the state.
	 */
	public function setParent(parent:Dynamic):Void
	{
		if (closed || lua == null)
			return;

		final state:Dynamic = parent != null ? parent : getCurrentState();
		if (state == null)
			return;

		set('this', state);
		set('game', state);

		for (name in ['add', 'remove', 'insert', 'members'])
		{
			final value:Dynamic = Reflect.field(state, name);
			if (value != null)
				set(name, value);
		}
	}

	/**
	 * Retires the script: no callback reaches it any more and its Luau state is dropped.
	 *
	 * A script that stops itself from inside a callback is only marked: the state is closed by whoever
	 * is running it, once the call it is inside has returned (`closeState()`).
	 */
	public function stop():Void
	{
		if (closed)
			return;

		closed = true;
		executed = true;

		if (!running)
			closeState();
	}

	/** Closes the Luau state and forgets everything the script held, at most once. */
	function closeState():Void
	{
		if (lua != null)
		{
			Lua.close(lua);
			lua = null;
		}

		bindings.clear();
		refs.clear();
		refIds.clear();
	}

	/** Whether the stack entry at `index` is a function. */
	function isCallable(index:Int):Bool
	{
		// The prebuilt Luau libraries and the vendored lua.h don't necessarily share the same
		// type-tag enum, which makes `Lua.LUA_TFUNCTION` unreliable - ask the VM for the type name.
		return Lua.typename(lua, Lua.type(lua, index)) == 'function';
	}

	/** Whether the stack entry at `index` is nil (or absent). */
	function isNil(index:Int):Bool
	{
		final typeName:String = Lua.typename(lua, Lua.type(lua, index));
		return typeName == 'nil' || typeName == 'none';
	}

	// ------------------------------------------------------------------ environment

	/** Binds every global a script may touch, before its body runs. */
	function setupEnvironment():Void
	{
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
				function(className:String, ?varName:String)
				{
					importClass(className, varName);
				}
			],
			[
				"print",
				Reflect.makeVarArgs(function(args:Array<Dynamic>)
				{
					final parts:Array<String> = [];
					if (args != null)
						for (arg in args)
							parts.push(Std.string(arg));

					scriptMessage('$scriptName: ' + parts.join(' '), FlxColor.WHITE);
				})
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
				],
				[
					"createGlobalCallback",
					function(name:String, func:Dynamic)
					{
						// Every Lua script gets the function too, and it survives into the ones
						// created later through FunkinLua.customFunctions.
						for (script in PlayState.instance.luaArray)
							if (script != null && !script.closed)
								script.set(name, func);

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
	 * The `import` global: `import('flixel.FlxSprite')` binds a class under its own name,
	 * `import('flixel.FlxSprite', 'Spr')` under the given one, and `import('flixel.*')` every static
	 * field of the package's classes the name resolves to.
	 *
	 * (The old wrapper had a "safe"/"unsafe" pair here, where the safe one refused to import at all;
	 * this runtime has nothing to protect - an import is just another binding.)
	 */
	function importClass(className:String, ?varName:String):Void
	{
		if (className == null)
			return;

		final classSplit:Array<String> = className.split('.');
		final shortName:String = classSplit[classSplit.length - 1]; // last one

		if (shortName != '*')
		{
			final imported:Class<Dynamic> = Type.resolveClass(className);
			if (imported != null)
				set(varName != null ? varName : shortName, imported);
			else
				scriptMessage('Could not import class $className', FlxColor.RED);
			return;
		}

		// Wildcard: the longest prefix of the path that resolves to a class is the one imported. No
		// wildcard binding is given, the class is bound under `varName` instead (its statics are
		// already reachable through it).
		var imported:Class<Dynamic> = null;
		while (classSplit.length > 0 && imported == null)
		{
			classSplit.pop();
			imported = Type.resolveClass(classSplit.join("."));
		}

		if (imported == null)
		{
			scriptMessage('Could not import class $className', FlxColor.RED);
			return;
		}

		if (varName != null)
		{
			set(varName, imported);
			return;
		}

		for (field in Type.getClassFields(imported))
			set(field, Reflect.field(imported, field));
	}

	function setVars(vars:Array<Array<Dynamic>>):Void
	{
		for (v in vars)
			set(v[0], v[1]);
	}

	// ------------------------------------------------------------------ reporting

	/**
	 * Script messages normally go to PlayState's debug text, which only exists while a song
	 * is running — scripted states (see LScriptSState) have none, so print those on the shared
	 * on-screen overlay (ScriptDebugOverlay) instead of dropping them.
	 *
	 * Both of those only ever draw: nothing here reaches a platform dialog (`CoolUtil.showPopUp()` /
	 * `android.Tools.showAlertDialog`) the way the script-error paths used to, which cannot be raised
	 * from a script-loading call on Android. A message without text still prints as a readable line
	 * rather than being handed on as null.
	 */
	function scriptMessage(msg:String, color:FlxColor):Void
	{
		final line:String = (msg != null && msg.length > 0) ? msg : '$scriptName: an empty message was reported';

		final playState:PlayState = PlayState.instance;
		if (playState != null)
			playState.addTextToDebug(line, color);
		else
			ScriptDebugOverlay.report(line, color);
	}

	/**
	 * Reports a failure of a bridge call. These run inside script code, so they report and hand the
	 * script nothing instead of raising: whatever an engine function throws must not unwind the VM.
	 */
	function reportFailure(what:String, error:Dynamic):Void
	{
		scriptMessage('$scriptName: $what: ' + Std.string(error), FlxColor.RED);
	}

	#else
	public var scriptName(default, null):String;

	/** Kept on this side too: `PlayState.setDefaultLScripts()` writes to it without a LUA guard. */
	public static final defaultVars:Map<String, Dynamic> = new Map<String, Dynamic>();

	public function new(fileName:String, ?executeScript:Bool = false)
	{
		scriptName = fileName != null ? haxe.io.Path.withoutDirectory(fileName) : 'LScript';
		// PlayState may not exist (scripted states), ScriptDebugOverlay reports either way
		ScriptDebugOverlay.report("LUA support is disabled. Script functionality is limited.", FlxColor.YELLOW);
	}

	public function execute():Void
	{
	}

	public function hasFunction(name:String):Bool
		return false;

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
