package psych.script;

#if LUA_ALLOWED
import llua.Convert;
import llua.Lua;
import llua.LuaL;
import llua.State;

/**
 * Live proxy tables for the Haxe values a FunkinLua script is handed.
 *
 * `Convert.toLua()` turns a class instance into a one-off table of its fields and converts the
 * values inside it non-recursively, so an object field comes out as `nil`: a script reading
 * `camGame` off the state it got as `this` finds nothing there (see `FunkinLua.setProxy()`).
 *
 * A proxy table holds only the id of the Haxe value instead, and every read, write and call goes
 * back to the live object through `luaIndex()`, `luaSetProp()` and `luaInvoke()`.
 *
 * This is the same bridge `script/FunkinLScript.hx` uses for the values it pushes, which is where a
 * `.lscript` gets its `this` from - a `.lua` should not get a copy of the state where the other one
 * gets the state itself.
 */
class LuaProxy
{
	/** Kind of a bridge descriptor: nothing, a value the script gets as is, a function, a proxy. */
	static inline final KIND_NONE:Int = 0;

	static inline final KIND_VALUE:Int = 1;
	static inline final KIND_FUNCTION:Int = 2;
	static inline final KIND_REF:Int = 3;

	/** Field of a proxy table holding the id of the Haxe value behind it. */
	static inline final REF_FIELD:String = '__pklua_ref';

	/** Global holding the proxy metatable, installed by `PRELUDE`. */
	static inline final PROXY:String = '__pklua_proxy';

	/**
	 * Lua side of the bridge, run before any of the engine functions are bound.
	 *
	 * Proxies read and write through `__pklua_index()` / `__pklua_setprop()` and call through
	 * `__pklua_invoke()`, the Haxe functions of the same name in this class. A callable field is
	 * handed out as a closure that drops the object of an `obj:method(...)` call before calling
	 * back, so both call styles work, and the value a call returns is decoded by the same rules as
	 * any other descriptor: `{1, value}` is a value, `{2, ...}` a function, `{3, id}` a proxy.
	 */
	static final PRELUDE:String = '
-- Proxy tables stand in for the Haxe values a script reaches (`__pklua_ref` is the id of one).
__pklua_proxy = {
	__index = function(t, key)
		local ref = rawget(t, "__pklua_ref")
		local r = __pklua_index(ref, key)
		if r == nil or r[1] == 0 then
			return nil
		end
		if r[1] == 1 then
			return r[2]
		end
		if r[1] == 3 then
			return __pklua_wrap(r[2])
		end
		-- A function field: call it back by name so the engine converts the result itself.
		return function(...)
			local args = {...}
			local first = args[1]
			if type(first) == "table" and rawget(first, "__pklua_ref") == ref then
				table.remove(args, 1)
			end
			return __pklua_decode(__pklua_invoke(ref, key, args))
		end
	end,
	__newindex = function(t, key, value)
		-- The engine object refused the write (no such field): keep it as a script variable.
		if __pklua_setprop(rawget(t, "__pklua_ref"), key, value) ~= true then
			rawset(t, key, value)
		end
	end,
	__len = function(t)
		return __pklua_len(rawget(t, "__pklua_ref"))
	end,
	__tostring = function(t)
		return __pklua_tostring(rawget(t, "__pklua_ref"))
	end,
}

-- One table per Haxe value, so two reads of the same field stay equal for the script. Weak, so a
-- proxy the script no longer holds does not keep itself alive.
__pklua_wrapped = setmetatable({}, {__mode = "v"})

function __pklua_wrap(ref)
	local t = __pklua_wrapped[ref]
	if t == nil then
		t = setmetatable({__pklua_ref = ref}, __pklua_proxy)
		__pklua_wrapped[ref] = t
	end
	return t
end

function __pklua_decode(r)
	if r == nil or r[1] == 0 then
		return nil
	end
	if r[1] == 1 then
		return r[2]
	end
	if r[1] == 3 then
		return __pklua_wrap(r[2])
	end
	return r[2]
end
';

	/** Reports a bridge failure; FunkinLua sends these to its own `luaTrace()`. */
	var report:String->FlxColor->Void;

	var lua:State;

	/** Haxe values behind the proxy tables the script holds, keyed by the id those tables carry. */
	var refs:Map<Int, Dynamic> = new Map<Int, Dynamic>();

	/** Ids already handed out, so a value the script sees twice stays one proxy (`registerRef()`). */
	var refIds:haxe.ds.ObjectMap<Dynamic, Int> = new haxe.ds.ObjectMap<Dynamic, Int>();

	var nextRef:Int = 0;

	public function new(lua:State, report:String->FlxColor->Void)
	{
		this.lua = lua;
		this.report = report;
		install();
	}

	/**
	 * Puts the Lua side of the bridge in place (`PRELUDE`) and the Haxe ends of it in the globals.
	 * A bridge that does not come up leaves the proxy tables inert rather than failing the script.
	 */
	function install():Void
	{
		if (!runChunk('lua proxy bridge', PRELUDE))
			return;

		bindBridgeFunction('__pklua_index', luaIndex);
		bindBridgeFunction('__pklua_invoke', luaInvoke);
		bindBridgeFunction('__pklua_setprop', luaSetProp);
		bindBridgeFunction('__pklua_len', luaLen);
		bindBridgeFunction('__pklua_tostring', luaToString);
	}

	/** Puts a Haxe function in the globals as itself, so Lua calls it directly. */
	function bindBridgeFunction(name:String, fn:Dynamic):Void
	{
		Convert.toLua(lua, fn);
		Lua.setglobal(lua, name);
	}

	/** Loads `code` and runs it, reporting a syntax or runtime error instead of throwing one. */
	function runChunk(chunkName:String, code:String):Bool
	{
		if (lua == null)
			return false;

		try
		{
			if (LuaL.luau_loadsource(lua, chunkName, code) != Lua.LUA_OK)
			{
				report('LuaProxy: could not parse the bridge: ' + takeError(), FlxColor.RED);
				return false;
			}

			if (Lua.pcall(lua, 0, 0, 0) != Lua.LUA_OK)
			{
				report('LuaProxy: could not run the bridge: ' + takeError(), FlxColor.RED);
				return false;
			}

			return true;
		}
		catch (e:Dynamic)
		{
			report('LuaProxy: could not set up the bridge: ' + Std.string(e), FlxColor.RED);
			return false;
		}
	}

	/** Reads and pops the error message the VM left on the stack. */
	function takeError():String
	{
		final message:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);
		return (message != null && message.length > 0) ? message.trim() : 'unknown error';
	}

	/** Pushes `value` as a proxy table of its own, leaving it on the stack. */
	public function push(value:Dynamic):Void
	{
		pushProxy(value);
	}

	/**
	 * Binds `value` as the global `name` of the script, as a live proxy table.
	 *
	 * Only what this call pushes is dropped on failure: `setGlobal()` may well run while another
	 * call is holding values on the same stack.
	 */
	public function setGlobal(name:String, value:Dynamic):Void
	{
		if (lua == null || name == null)
			return;

		final top:Int = Lua.gettop(lua);
		try
		{
			pushProxy(value);
			Lua.setglobal(lua, name);
		}
		catch (e:Dynamic)
		{
			Lua.settop(lua, top);
			report('LuaProxy: could not bind "$name": ' + Std.string(e), FlxColor.RED);
		}
	}

	/**
	 * Drops the Haxe values behind the proxies the script holds. The Lua state outliving them is
	 * what makes this worth calling: the ids are only meaningful while this object is alive.
	 */
	public function dispose():Void
	{
		refs.clear();
		refIds.clear();
		nextRef = 0;
	}

	// ------------------------------------------------------- Haxe -> Lua values

	/** Pushes a proxy table for `value`. See `FunkinLua.setProxy()`. */
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

	/**
	 * `unwrap()`s the argument list a script passed to a method.
	 *
	 * The Lua side always builds it as `{...}`, but a table with no entries reaches Haxe as `{}`
	 * rather than as an array (`Convert.toHaxeObj()` only makes an array out of a table that has
	 * items), so an empty one has to read as "no arguments" instead of being iterated as an array.
	 */
	function argList(args:Dynamic):Array<Dynamic>
	{
		final unwrapped:Array<Dynamic> = [];
		if (args == null || !Std.isOfType(args, Array))
			return unwrapped;

		for (arg in (cast args : Array<Dynamic>))
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

	/**
	 * Lua writes a field on the value behind `ref`: the proxy's `__newindex`.
	 *
	 * `false` means the engine object has no such field (hxcpp throws on those) and the script
	 * should keep the value itself - half of what a script assigns to an object it holds is its own
	 * bookkeeping, and there is no engine field to put that in.
	 */
	function luaSetProp(ref:Int, key:Dynamic, value:Dynamic):Bool
	{
		try
		{
			final target:Dynamic = refs.get(ref);
			final name:String = keyName(key);
			if (target == null || name == null)
				return false;

			final unwrapped:Dynamic = unwrap(value);

			if (isMap(target))
			{
				(cast target : haxe.Constraints.IMap<Dynamic, Dynamic>).set(name, unwrapped);
				return true;
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
					return true;
				}
			}

			Reflect.setProperty(target, name, unwrapped);
			return true;
		}
		catch (e:Dynamic)
		{
			// Where the value ends up is the script's business, this is not a failure worth a screen
			// full of red text on every `spr.customFlag = true`.
			return false;
		}
	}

	/** Lua calls something on the value behind `ref`: the proxy's method path and `Class:new()`. */
	function luaInvoke(ref:Int, key:Dynamic, ?args:Dynamic):Dynamic
	{
		try
		{
			final target:Dynamic = refs.get(ref);
			final name:String = keyName(key);
			if (target == null || name == null)
				return [KIND_NONE];

			final callArgs:Array<Dynamic> = argList(args);

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

	/** Reports a field a script asked for but the bridge could not reach, without failing the call. */
	function reportFailure(action:String, e:Dynamic):Void
	{
		report('LuaProxy: $action on a proxy value failed: ' + Std.string(e), FlxColor.RED);
	}
}
#end
