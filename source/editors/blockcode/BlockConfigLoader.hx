package editors.blockcode;

import editors.blockcode.BlockTypes;
import haxe.Json;
import haxe.io.Path;

/**
 * BlockConfigLoader — the external block programming interface of the block-code editor.
 *
 * Mods can add their own blocks without recompiling the engine: everything is read from
 * JSON and Lua files at runtime by `loadAll()`. Nothing in here ever throws — a broken
 * file only adds a line to `lastErrors()` and the remaining files are still loaded.
 *
 * ---------------------------------------------------------------------------
 * ## Search roots (missing folders are skipped silently)
 *
 * 1. Mods (`#if MODS_ALLOWED`). Priority order: the active mod, the global mods
 *    (`pack.json` -> `runsGlobally`), the remaining mod folders alphabetically, then the
 *    `mods/` folder itself as a pseudo mod:
 *
 *      <mod>/blockcode/blocks.json
 *      <mod>/blockcode/blocks.lua
 *      <mod>/blockcode/blocks/*.json   (also *.lua, and sub folders up to 3 levels deep)
 *      <mod>/data/blockcode/*.json     (fallback location for mods written in the wild)
 *      <mod>/data/blockcode/*.lua
 *
 * 2. Built-in / shared, read through `backend.Paths` so the level library rules still
 *    apply (`assets/shared/blockcode/…` and `assets/preload/blockcode/…`, i.e. the
 *    exported `assets/blockcode/…` folder on a packaged build).
 *
 * The first definition of a block type wins. A second definition of the same type is
 * skipped and reported in `lastErrors()`.
 *
 * ---------------------------------------------------------------------------
 * ## JSON schema
 *
 * ```json
 * {"categories":[{"name":"MyFX","color":"0xFFAA33FF","icon":"*","blocks":[
 *   {"type":"myFx.spawnRing","label":"spawn ring","description":"spawns a ring",
 *    "isReporter":false,"isHat":false,"lua":"spawnRing($1, $2)",
 *    "parameters":[{"name":"tag","type":"string","defaultValue":"ring"},
 *                  {"name":"size","type":"number","defaultValue":100}]}]}]}
 * ```
 *
 *   - `type` is the only required block field. `label` defaults to `type`.
 *   - `color` and `icon` may live on the category or on a single block. A block without a
 *     colour uses its category colour; a category without a colour gets a stable colour
 *     derived from a hash of its name.
 *   - `parameters` is a list of `{name, type, defaultValue, options, description}`.
 *     `type` is one of `string`, `number`, `bool`, `code`, `color`, `select` (aliases such
 *     as `boolean`/`int`/`float`/`lua`/`dropdown` are accepted). `options` only matters for
 *     `select`. Missing defaults fall back to `""`, `0`, `false` (or the first option).
 *   - `category` on a block files it under that category instead of the enclosing one.
 *   - `lua`, `hatLua`, `isReporter`, `isHat`, `description` are copied straight over.
 *   - Tolerated shortcuts: a root array of categories, a root array of blocks, a root
 *     object with a top level `blocks` array, or a single block object. Those blocks land
 *     in an implicit category named after the root `name`/`category`, else `"Blocks"`.
 *   - Unknown fields are ignored, and a category that ends up without a single usable block
 *     is dropped from the result so the palette shows no empty tab.
 *
 * ### Colours
 *
 * Accepted as a JSON number (`4289344511`) or as a string in any of these forms:
 * `"0xAARRGGBB"`, `"#RRGGBB"`, `"RRGGBB"`, `"AARRGGBB"`, `"#RGB"`, `"#ARGB"`, `"0x…"`,
 * `"$…"`. Six digit values are treated as opaque (`FF` alpha is added). Values without an
 * `#`, `0x` or `$` prefix that are not 6 or 8 hex digits are read as plain decimal integers.
 *
 * ---------------------------------------------------------------------------
 * ## Lua schema (parsed as TEXT — no Lua VM, so it works on HTML5 too)
 *
 * ```lua
 * registerCategory{ name = "MyFX", color = 0xFFAA33FF, icon = "*" }
 *
 * registerBlock{
 *   type = "myFx.spawnRing", label = "spawn ring", category = "MyFX",
 *   lua = "spawnRing($1)", isReporter = false,
 *   parameters = { { name = "tag", type = "string", defaultValue = "ring" } }
 * }
 *
 * -- positional form, type first
 * registerBlock("myFx.spawnRing", { label = "spawn ring", lua = "spawnRing($1)" })
 * registerBlock("myFx.playSound")            -- table optional
 * ```
 *
 * A block without an explicit `category` joins the last `registerCategory` of the file,
 * else `"External"`. A `registerCategory`/`registerBlock` table that carries no name/type
 * but a bare array is treated as a list of categories/blocks. Helper functions, `local`
 * assignments and any other statement are skipped; a call to an unknown function is
 * reported once by name.
 *
 * ### Supported Lua subset (this is the whole parser)
 *
 *   - `--` line comments and `--[[ ]]` / `--[=[ ]=]` (any `=` level) block comments.
 *   - Long strings `[[ ]]`, `[=[ ]=]`, `[==[ ]==]`, … including embedded newlines.
 *   - Single and double quoted strings with `\n \t \r \a \b \f \v \\ \" \' \z`,
 *     `\ddd` (up to 3 decimal digits), `\xHH` and `\u{XXXXX}` escapes; an unknown escape
 *     keeps the escaped character.
 *   - Decimal numbers (`1`, `2.5`, `1e3`) and hex numbers (`0xFFAA33FF`).
 *   - `true`, `false`, `nil` (and `null`). A bare word is read as text, so
 *     `type = number` and `type = "number"` behave the same.
 *   - Nested tables, `name = value` keys, `[expr] = value` keys, bare array values,
 *     `,` or `;` separators, trailing separators.
 *   - Multiple statements per line, and statements spread over several lines.
 *   - NOT supported: expressions (`1 + 2`, string concatenation, table lookups as values),
 *     function definitions, `return`, variables. Those statements are skipped and the
 *     file keeps loading whatever `registerBlock`/`registerCategory` calls it contains.
 *
 * ---------------------------------------------------------------------------
 * ## Runtime registration
 *
 * `registerRuntime()` adds a block coming from a live script binding. Runtime blocks are
 * kept for the rest of the session, re-registering the same `type` replaces it, and
 * `loadAll()` appends them after the file configs (so a hot reloaded script does not need
 * a reload of the editor). Registrations colliding with a built-in type, or with a type a
 * config file already defined, are skipped and reported; a `color` of `0` counts as "not
 * set" and is replaced by the colour derived from the category name.
 *
 * Malformed input is never fatal: everything that could not be understood shows up in
 * `lastErrors()` (non fatal notes are plain sentences, errors are prefixed with the file
 * and, when known, the line number). Messages produced by `registerRuntime()` are never
 * dropped by a later `loadAll()`, the file messages are replaced on every scan. Blocks and
 * categories carry `external = true` and `source` = the file (`"runtime"` for runtime
 * registrations) so the editor can tell them apart from the built-in library.
 */
class BlockConfigLoader
{
	// ------------------------------------------------------------------ constants
	static inline var JSON_NAME:String = 'blocks.json';
	static inline var LUA_NAME:String = 'blocks.lua';
	static inline var MAX_ERRORS:Int = 200;
	static inline var MAX_SCAN_DEPTH:Int = 3;
	static inline var FALLBACK_CATEGORY:String = 'External';
	static inline var IMPLICIT_CATEGORY:String = 'Blocks';

	/**
	 * Every block type of the built-in library, frozen from `editors/BlockCodeEditorState.hx`.
	 * Used to keep a mod from shadowing a built-in block. `builtInTypes()` unions this list
	 * with whatever a sibling `BlockLibrary` module exposes, when that module is compiled in.
	 */
	static var BUILT_IN_TYPES:Array<String> = [
		'onCreate',
		'onCreatePost',
		'onUpdate',
		'onUpdatePost',
		'onBeatHit',
		'onStepHit',
		'onDestroy',
		'onEvent',
		'if',
		'elseif',
		'else',
		'end',
		'wait',
		'debugPrint',
		'close',
		'add',
		'sub',
		'mul',
		'div',
		'eq',
		'gt',
		'lt',
		'and',
		'or',
		'not',
		'join',
		'keyJustPressed',
		'keyPressed',
		'curStep',
		'curBeat',
		'songPosition',
		'health',
		'getPixelColor',
		'setProperty',
		'getProperty',
		'makeLuaSprite',
		'makeAnimatedLuaSprite',
		'addLuaSprite',
		'scaleObject',
		'setObjectCamera',
		'playSound',
		'playMusic',
		'pauseSound',
		'stopSound',
		'doTweenX',
		'doTweenY',
		'doTweenAlpha',
		'doTweenZoom',
		'setHealth',
		'addHealth',
		'cameraShake',
		'cameraFlash',
		'cameraFade'
	];

	/** Static members of a sibling built-in library module that may list its categories. */
	static var LIBRARY_FIELDS:Array<String> = [
		'categories',
		'defaultCategories',
		'baseCategories',
		'builtInCategories',
		'BASE_CATEGORIES',
		'DEFAULT_CATEGORIES',
		'getCategories',
		'getDefaultCategories'
	];

	// ------------------------------------------------------------------ state
	static var errors:Array<String> = [];
	static var reported:Map<String, Bool> = new Map();
	static var runtimeErrors:Array<String> = [];
	static var runtimeReported:Map<String, Bool> = new Map();
	static var runtimeOrder:Array<String> = [];
	static var runtimeCategories:Map<String, BlockCategory> = new Map();
	static var builtInCache:Map<String, Bool> = null;
	static var resolvingBuiltIns:Bool = false;

	// ------------------------------------------------------------------ public API

	/**
	 * Scans every config file, merges them by category, and appends the runtime
	 * registrations. Never throws; read `lastErrors()` for anything that was skipped.
	 */
	public static function loadAll():Array<BlockCategory>
	{
		errors = [];
		reported = new Map();

		var acc:CategoryAccumulator = new CategoryAccumulator();
		try
		{
			scanAllInto(acc);
		}
		catch (e:Dynamic)
		{
			pushError('block config scan failed: ' + Std.string(e));
		}
		try
		{
			mergeRuntimeInto(acc);
		}
		catch (e:Dynamic)
		{
			pushError('runtime block merge failed: ' + Std.string(e));
		}
		return acc.result();
	}

	/**
	 * Parses one JSON document (the schema is documented at the top of this file).
	 * Resets `lastErrors()`; returns the categories that could be built.
	 */
	public static function parseJson(text:String, source:String):Array<BlockCategory>
	{
		errors = [];
		reported = new Map();
		return parseJsonInternal(text, source);
	}

	/**
	 * Parses one Lua config document with the built-in tolerant parser (no Lua VM).
	 * Resets `lastErrors()`; returns the categories that could be built.
	 */
	public static function parseLua(text:String, source:String):Array<BlockCategory>
	{
		errors = [];
		reported = new Map();
		return parseLuaInternal(text, source);
	}

	/**
	 * Registers a block at runtime, e.g. from a script binding. The block's category is
	 * `categoryName`, else `b.category`, else `"External"`. Re-registering the same type
	 * replaces the previous runtime block. Nothing is returned: the block shows up in the
	 * next `loadAll()` result (and in the current one if it is re-read).
	 *
	 * Diagnostics of this call stay in `lastErrors()` for the rest of the session, so a
	 * rejected registration is still visible after the editor reloads its palette.
	 */
	public static function registerRuntime(b:BlockData, ?categoryName:String):Void
	{
		if (b == null)
		{
			pushRuntimeError('runtime: a null block registration was ignored');
			return;
		}

		var type:String = tblString(b, 'type');
		if (type == null || type.trim().length == 0)
		{
			pushRuntimeError('runtime: a block registration without a "type" was ignored');
			return;
		}
		type = type.trim();
		if (isBuiltInType(type))
		{
			pushRuntimeError('runtime: block type "' + type + '" is reserved by a built-in block and was ignored');
			return;
		}

		var category:String = categoryName;
		if (category == null || category.trim().length == 0)
			category = tblString(b, 'category');
		if (category == null || category.trim().length == 0)
			category = FALLBACK_CATEGORY;
		category = category.trim();

		var declared:Null<Int> = parseColor(tblGet(b, 'color'));
		var useDeclared:Bool = declared != null && declared != 0;
		var color:Int = useDeclared ? declared : deriveColor(category);

		var block:BlockData = buildBlock(b, category, color, 'runtime', 0);
		if (block == null)
			return;
		if (!useDeclared)
			block.color = color;

		// a re-registered type must not stay behind in its previous category
		for (name in runtimeOrder)
		{
			var old:BlockCategory = runtimeCategories.get(name);
			if (old == null)
				continue;
			for (i in 0...old.blocks.length)
			{
				if (old.blocks[i].type == type)
				{
					old.blocks.splice(i, 1);
					break;
				}
			}
		}

		var target:BlockCategory = runtimeCategories.get(category);
		if (target == null)
		{
			target = {
				name: category,
				color: color,
				icon: '*',
				blocks: [],
				external: true
			};
			runtimeCategories.set(category, target);
			runtimeOrder.push(category);
		}
		if (useDeclared)
			target.color = declared;
		target.blocks.push(block);
	}

	/**
	 * A listing of every scanned config file with its size and modification time, plus the
	 * runtime registration count. Compare two signatures to know whether the external
	 * blocks changed. Never throws.
	 */
	public static function configSignature():String
	{
		var parts:Array<String> = [];
		var files:Array<String> = collectConfigFiles(true, false);
		for (file in files)
		{
			parts.push(file + '|' + fileStamp(file));
		}
		var runtimeCount:Int = 0;
		for (name in runtimeOrder)
		{
			var category:BlockCategory = runtimeCategories.get(name);
			if (category != null)
				runtimeCount += category.blocks.length;
		}
		parts.push('runtime|' + runtimeCount);
		return parts.join('\n');
	}

	/**
	 * A copy of everything reported since the last `loadAll()` / `parseJson()` / `parseLua()`,
	 * followed by the runtime registration messages of this session (they are never dropped,
	 * so a registration a script did minutes ago is still visible).
	 */
	public static function lastErrors():Array<String>
	{
		var all:Array<String> = errors.copy();
		for (message in runtimeErrors)
			all.push(message);
		return all;
	}

	// ------------------------------------------------------------------ scanning

	static function scanAllInto(acc:CategoryAccumulator):Void
	{
		var files:Array<String> = collectConfigFiles(false, true);
		for (file in files)
		{
			var text:Null<String> = readText(file);
			if (text == null)
			{
				pushError(file + ': could not read block config file');
				continue;
			}
			try
			{
				mergeInto(acc, parseFile(file, text));
			}
			catch (e:Dynamic)
			{
				pushError(file + ': block config was skipped (' + Std.string(e) + ')');
			}
		}
	}

	static function parseFile(file:String, text:String):Array<BlockCategory>
	{
		return Path.extension(file).toLowerCase() == 'lua' ? parseLuaInternal(text, file) : parseJsonInternal(text, file);
	}

	static function mergeInto(acc:CategoryAccumulator, categories:Array<BlockCategory>):Void
	{
		if (categories == null)
			return;
		for (category in categories)
		{
			acc.ensure(category.name, category.color, category.icon, true);
			for (block in category.blocks)
			{
				if (!acc.add(block))
					pushError(at(block.source, 0, 'duplicate block type "' + block.type + '"; the later definition was skipped'));
			}
		}
	}

	static function mergeRuntimeInto(acc:CategoryAccumulator):Void
	{
		for (name in runtimeOrder)
		{
			var category:BlockCategory = runtimeCategories.get(name);
			if (category == null)
				continue;
			acc.ensure(category.name, category.color, category.icon, true);
			for (block in category.blocks)
			{
				if (!acc.add(block))
					pushError('runtime: block type "' + block.type + '" was skipped, another block already uses that type');
			}
		}
	}

	/**
	 * Every config file, in priority order (first definition wins) unless `sortPaths` is set,
	 * in which case the result is sorted so it is stable for `configSignature()`.
	 */
	static function collectConfigFiles(sortPaths:Bool, reportErrors:Bool):Array<String>
	{
		var files:Array<String> = [];
		var seen:Map<String, Bool> = new Map();

		#if MODS_ALLOWED
		var mods:Array<String> = [];
		addModName(mods, Paths.currentModDirectory);
		try
		{
			for (name in Paths.getGlobalMods())
				addModName(mods, name);
		}
		catch (e:Dynamic)
		{
			if (reportErrors)
				pushError('mods: could not read the global mod list (' + Std.string(e) + ')');
		}
		var folders:Array<String> = [];
		try
		{
			folders = Paths.getModDirectories();
		}
		catch (e:Dynamic)
		{
			if (reportErrors)
				pushError('mods: could not list the mod folders (' + Std.string(e) + ')');
		}
		folders.sort(function(a:String, b:String):Int return a < b ? -1 : (a > b ? 1 : 0));
		for (name in folders)
			addModName(mods, name);
		addModName(mods, '');
		for (name in mods)
			collectModFiles(name, files, seen);
		#end

		for (root in builtInRoots())
			collectDirFiles(root, files, seen, 0);

		if (sortPaths)
		{
			var sorted:Array<String> = files.copy();
			sorted.sort(function(a:String, b:String):Int return a < b ? -1 : (a > b ? 1 : 0));
			return sorted;
		}
		return files;
	}

	static function builtInRoots():Array<String>
	{
		var roots:Array<String> = [];
		roots.push(Paths.getPreloadPath('shared/blockcode'));
		roots.push(Paths.getLibraryPath('shared/blockcode'));
		roots.push(Paths.getPreloadPath('blockcode'));
		roots.push(Paths.getPreloadPath('preload/blockcode'));
		return roots;
	}

	static function addModName(list:Array<String>, name:String):Void
	{
		if (name == null)
			return;
		if (name.length == 0)
		{
			// the mods folder itself, used as a pseudo mod
			if (!list.contains(''))
				list.push('');
			return;
		}
		if (!list.contains(name))
			list.push(name);
	}

	static function collectModFiles(mod:String, out:Array<String>, seen:Map<String, Bool>):Void
	{
		var prefix:String = mod.length == 0 ? '' : mod + '/';
		addFileIfPresent(out, seen, Paths.mods(prefix + 'blockcode/' + JSON_NAME));
		addFileIfPresent(out, seen, Paths.mods(prefix + 'blockcode/' + LUA_NAME));
		collectDirFiles(Paths.mods(prefix + 'blockcode/blocks'), out, seen, 0);
		collectDirFiles(Paths.mods(prefix + 'data/blockcode'), out, seen, 0);
	}

	static function addFileIfPresent(out:Array<String>, seen:Map<String, Bool>, path:String):Void
	{
		if (path == null)
			return;
		var exists:Bool = false;
		try
		{
			exists = Paths.exists(path);
		}
		catch (e:Dynamic)
		{
			exists = false;
		}
		if (exists)
			pushFile(out, seen, path);
	}

	static function pushFile(out:Array<String>, seen:Map<String, Bool>, path:String):Void
	{
		var key:String = path.toLowerCase();
		if (seen.exists(key))
			return;
		seen.set(key, true);
		out.push(path);
	}

	/** Collects `*.json` / `*.lua` files of a folder, descending at most `MAX_SCAN_DEPTH` levels. */
	static function collectDirFiles(dir:String, out:Array<String>, seen:Map<String, Bool>, depth:Int):Void
	{
		if (dir == null || dir.length == 0)
			return;
		if (!dirExists(dir))
			return;

		var entries:Array<String> = null;
		try
		{
			entries = Paths.readDirectory(dir);
		}
		catch (e:Dynamic)
		{
			pushError(dir + ': could not list folder (' + Std.string(e) + ')');
			return;
		}
		if (entries == null)
			return;

		for (entry in entries)
		{
			if (entry == null)
				continue;
			var clean:String = stripLibraryPrefix(entry);
			var name:String = Path.withoutDirectory(clean);
			var full:String = clean.startsWith(dir) ? clean : Path.join([dir, name]);
			if (isConfigName(name))
			{
				pushFile(out, seen, full);
				continue;
			}
			#if sys
			if (depth < MAX_SCAN_DEPTH)
			{
				var isFolder:Bool = false;
				try
				{
					isFolder = FileSystem.exists(full) && FileSystem.isDirectory(full);
				}
				catch (e:Dynamic)
				{
					isFolder = false;
				}
				if (isFolder)
					collectDirFiles(full, out, seen, depth + 1);
			}
			#end
		}
	}

	static function isConfigName(name:String):Bool
	{
		if (name == null)
			return false;
		var ext:String = Path.extension(name).toLowerCase();
		return ext == 'json' || ext == 'lua';
	}

	/** Turns `shared:assets/shared/x.json` into `assets/shared/x.json`, leaves paths alone. */
	static function stripLibraryPrefix(path:String):String
	{
		if (path == null)
			return path;
		var colon:Int = path.indexOf(':');
		// a colon at index 0 or 1 is a library id at best and a Windows drive letter at worst
		if (colon <= 1)
			return path;
		var library:String = path.substr(0, colon);
		if (library.contains('/') || library.contains('\\'))
			return path;
		return path.substr(colon + 1);
	}

	static function dirExists(dir:String):Bool
	{
		try
		{
			if (Paths.exists(dir))
				return true;
		}
		catch (e:Dynamic)
		{
		}

		#if !sys
		// on HTML5 a folder is not an asset, so look for contained assets instead
		try
		{
			var prefix:String = dir + '/';
			for (asset in lime.utils.Assets.list())
			{
				if (asset != null && asset.startsWith(prefix))
					return true;
			}
		}
		catch (e:Dynamic)
		{
		}
		#end
		return false;
	}

	/** Reads a config file through `Paths`, with a library prefixed retry on non-sys targets. */
	static function readText(path:String):Null<String>
	{
		try
		{
			var text:Null<String> = Paths.getContent(path);
			if (text != null)
				return text;
		}
		catch (e:Dynamic)
		{
		}

		#if !sys
		try
		{
			var library:String = libraryOf(path);
			if (library != null)
			{
				var text:Null<String> = openfl.utils.Assets.getText(library + ':' + path);
				if (text != null)
					return text;
			}
		}
		catch (e:Dynamic)
		{
		}
		#end
		return null;
	}

	static function libraryOf(path:String):Null<String>
	{
		if (path == null)
			return null;
		var parts:Array<String> = path.split('/');
		if (parts.length < 2 || parts[0] != 'assets')
			return null;
		if (parts[1].length == 0 || parts[1] == 'preload')
			return null;
		return parts[1];
	}

	#if sys
	static function fileStamp(path:String):String
	{
		try
		{
			var stat:sys.FileStat = FileSystem.stat(path);
			var modified:String = stat.mtime == null ? '?' : Std.string(stat.mtime.getTime());
			return Std.string(stat.size) + '|' + modified;
		}
		catch (e:Dynamic)
		{
			return '?|?';
		}
	}
	#else
	static function fileStamp(path:String):String
	{
		var text:Null<String> = readText(path);
		if (text == null)
			return '?|?';
		return Std.string(text.length) + '|' + Std.string(fnv1a(text));
	}
	#end

	// ------------------------------------------------------------------ JSON configs

	static function parseJsonInternal(text:String, source:String):Array<BlockCategory>
	{
		var acc:CategoryAccumulator = new CategoryAccumulator();
		if (text == null || text.trim().length == 0)
			return acc.result();

		var root:Dynamic = null;
		try
		{
			root = Json.parse(text);
		}
		catch (e:Dynamic)
		{
			pushError(at(source, 0, 'invalid JSON (' + Std.string(e) + ')'));
			return acc.result();
		}
		if (root == null)
			return acc.result();

		if (Std.isOfType(root, Array))
		{
			for (entry in (cast root : Array<Dynamic>))
				addJsonEntry(acc, entry, source, IMPLICIT_CATEGORY);
			return acc.result();
		}
		if (!isTable(root))
		{
			pushError(at(source, 0, 'root of a JSON block config must be an object or an array'));
			return acc.result();
		}

		var categories:Dynamic = tblGet(root, 'categories');
		if (categories != null)
		{
			if (Std.isOfType(categories, Array))
			{
				for (entry in (cast categories : Array<Dynamic>))
					addJsonEntry(acc, entry, source, IMPLICIT_CATEGORY);
			}
			else
			{
				pushError(at(source, 0, '"categories" must be an array'));
			}
		}

		var blocks:Dynamic = tblGet(root, 'blocks');
		if (Std.isOfType(blocks, Array))
		{
			var name:String = tblString(root, 'name');
			if (name == null || name.trim().length == 0)
				name = tblString(root, 'category');
			if (name == null || name.trim().length == 0)
				name = IMPLICIT_CATEGORY;
			name = name.trim();
			for (entry in (cast blocks : Array<Dynamic>))
				addBlockEntry(acc, entry, source, name, null);
		}

		if (categories == null && !Std.isOfType(blocks, Array) && tblString(root, 'type') != null)
		{
			addBlockEntry(acc, root, source, IMPLICIT_CATEGORY, null);
		}
		return acc.result();
	}

	static function addJsonEntry(acc:CategoryAccumulator, entry:Dynamic, source:String, implicitCategory:String):Void
	{
		if (entry == null)
			return;
		if (Std.isOfType(entry, Array))
		{
			for (sub in (cast entry : Array<Dynamic>))
				addJsonEntry(acc, sub, source, implicitCategory);
			return;
		}
		if (!isTable(entry))
		{
			pushError(at(source, 0, 'ignored an entry that is not an object'));
			return;
		}
		if (tblGet(entry, 'blocks') != null || tblString(entry, 'name') != null || tblString(entry, 'category') != null)
		{
			readCategory(acc, entry, source, 0, implicitCategory);
			return;
		}
		if (tblString(entry, 'type') != null)
		{
			addBlockEntry(acc, entry, source, implicitCategory, null);
			return;
		}
		pushError(at(source, 0, 'ignored an entry without a "name" or a "type"'));
	}

	// ------------------------------------------------------------------ Lua configs

	static function parseLuaInternal(text:String, source:String):Array<BlockCategory>
	{
		var acc:CategoryAccumulator = new CategoryAccumulator();
		if (text == null || text.trim().length == 0)
			return acc.result();

		var parser:LuaParser = new LuaParser(source, text);
		var commands:Array<LuaCommand> = parser.parseStatements();
		for (message in parser.takeErrors())
			pushError(message);

		var lastCategory:String = null;
		var handled:Int = 0;
		for (command in commands)
		{
			if (command.name == 'category')
			{
				var table:LuaTable = firstTableArg(command.args);
				if (table == null)
				{
					pushError(at(source, command.line, command.rawName + ' expects a table; ignored'));
					continue;
				}
				var name:String = readCategory(acc, table, source, command.line, null);
				if (name != null)
					lastCategory = name;
				handled++;
				continue;
			}
			if (command.name == 'block')
			{
				var type:String = firstTextArg(command.args);
				var table:LuaTable = firstTableArg(command.args);
				if (type == null && table == null)
				{
					pushError(at(source, command.line, command.rawName + ' expects a block table; ignored'));
					continue;
				}
				if (table == null)
					table = new LuaTable();
				if (type != null && type.length > 0)
					table.set('type', type);
				if (tblString(table, 'type') == null)
				{
					pushError(at(source, command.line, 'block without a "type" was skipped'));
					continue;
				}
				addBlockEntry(acc, table, source, lastCategory == null ? FALLBACK_CATEGORY : lastCategory, null);
				handled++;
				continue;
			}
		}

		if (handled == 0)
		{
			pushError(at(source, 0, 'no registerBlock/registerCategory call found; this Lua config was ignored'));
		}
		return acc.result();
	}

	static function firstTableArg(args:Array<Dynamic>):LuaTable
	{
		if (args == null)
			return null;
		for (arg in args)
		{
			if (Std.isOfType(arg, LuaTable))
				return cast arg;
		}
		return null;
	}

	static function firstTextArg(args:Array<Dynamic>):Null<String>
	{
		if (args == null)
			return null;
		for (arg in args)
		{
			var text:String = asText(arg);
			if (text != null && text.length > 0)
				return text;
		}
		return null;
	}

	// ------------------------------------------------------------------ categories and blocks

	/** Reads a category (JSON object or Lua table). Returns its name, or null when it had none. */
	static function readCategory(acc:CategoryAccumulator, raw:Dynamic, source:String, line:Int, implicitCategory:String):Null<String>
	{
		var name:String = tblString(raw, 'name');
		if (name == null || name.trim().length == 0)
			name = tblString(raw, 'category');
		if (name == null || name.trim().length == 0)
			name = implicitCategory;
		name = name == null ? null : name.trim();

		if (name == null || name.length == 0)
		{
			// tolerant: a bare list of categories
			var list:Array<Dynamic> = tblArray(tblGet(raw, 'categories'));
			if (list == null)
				list = tblArray(raw);
			if (list == null)
			{
				pushError(at(source, line, 'a category without a "name" was skipped'));
				return null;
			}
			var last:String = null;
			for (entry in list)
			{
				if (!isTable(entry) && !Std.isOfType(entry, LuaTable))
					continue;
				var inner:String = readCategory(acc, entry, source, line, null);
				if (inner != null)
					last = inner;
			}
			return last;
		}

		var declared:Null<Int> = parseColor(tblGet(raw, 'color'));
		var category:BlockCategory = acc.ensure(name, declared != null ? declared : deriveColor(name), tblString(raw, 'icon'), declared != null);

		var blocks:Dynamic = tblGet(raw, 'blocks');
		if (blocks == null)
			return name;
		var list:Array<Dynamic> = tblArray(blocks);
		if (list == null)
		{
			pushError(at(source, line, 'category "' + name + '" has a "blocks" field that is not a list'));
			return name;
		}
		for (entry in list)
			addBlockEntry(acc, entry, source, name, category.color);
		return name;
	}

	static function addBlockEntry(acc:CategoryAccumulator, raw:Dynamic, source:String, defaultCategory:String, defaultColor:Null<Int>):Void
	{
		if (raw == null)
			return;
		if (Std.isOfType(raw, Array))
		{
			for (entry in (cast raw : Array<Dynamic>))
				addBlockEntry(acc, entry, source, defaultCategory, defaultColor);
			return;
		}
		if (!isTable(raw) && !Std.isOfType(raw, LuaTable))
		{
			pushError(at(source, 0, 'ignored a block entry that is not a table'));
			return;
		}

		// a block without a colour takes the colour of its category (which may have been
		// declared by an earlier file of the same load pass), then of the enclosing one
		var category:String = blockCategory(raw, defaultCategory);
		var inherited:Null<Int> = acc.colorOf(category);
		if (inherited == null)
			inherited = defaultColor;
		if (inherited == null)
			inherited = deriveColor(category);

		var block:BlockData = buildBlock(raw, category, inherited, source, 0);
		if (block == null)
			return;

		acc.ensure(block.category, block.color, null, true);
		if (!acc.add(block))
		{
			pushError(at(source, 0, 'duplicate block type "' + block.type + '"; the later definition was skipped'));
		}
	}

	/** The category a block belongs to: its own `category` field, else the enclosing one. */
	static function blockCategory(raw:Dynamic, fallback:String):String
	{
		var category:String = tblString(raw, 'category');
		if (category == null || category.trim().length == 0)
			category = fallback;
		if (category == null || category.trim().length == 0)
			category = FALLBACK_CATEGORY;
		return category.trim();
	}

	/** Turns a JSON object or a Lua table into a validated `BlockData`, or null when unusable. */
	static function buildBlock(raw:Dynamic, category:String, defaultColor:Int, source:String, line:Int):Null<BlockData>
	{
		var type:String = tblString(raw, 'type');
		if (type == null || type.trim().length == 0)
		{
			pushError(at(source, line, 'block without a "type" was skipped'));
			return null;
		}
		type = type.trim();
		if (isBuiltInType(type))
		{
			pushError(at(source, line, 'block type "' + type + '" is reserved by a built-in block and was skipped'));
			return null;
		}

		if (category == null || category.length == 0)
			category = FALLBACK_CATEGORY;

		var declared:Null<Int> = parseColor(tblGet(raw, 'color'));
		var color:Int = declared != null ? declared : defaultColor;

		var label:String = tblString(raw, 'label');
		if (label == null || label.length == 0)
			label = type;

		var description:Null<String> = tblString(raw, 'description');
		var hatLua:Null<String> = tblString(raw, 'hatLua');
		var lua:Null<String> = tblString(raw, 'lua');

		var block:BlockData = {
			type: type,
			label: label,
			color: color,
			category: category,
			parameters: readParameters(tblGet(raw, 'parameters'), source, line),
			isReporter: tblBool(raw, 'isReporter') == true,
			isHat: tblBool(raw, 'isHat') == true,
			description: description,
			hatLua: hatLua,
			lua: lua,
			external: true,
			source: source
		};
		return block;
	}

	static function readParameters(raw:Dynamic, source:String, line:Int):Array<BlockParameter>
	{
		var list:Array<Dynamic> = tblArray(raw);
		if (list == null)
		{
			if (raw != null && !isTable(raw) && !Std.isOfType(raw, LuaTable))
				pushError(at(source, line, '"parameters" must be a list of parameter tables'));
			return [];
		}

		var out:Array<BlockParameter> = [];
		var index:Int = 0;
		for (entry in list)
		{
			index++;
			if (!isTable(entry) && !Std.isOfType(entry, LuaTable))
			{
				pushError(at(source, line, 'parameter #' + index + ' is not a table and was skipped'));
				continue;
			}
			var name:String = tblString(entry, 'name');
			if (name == null || name.trim().length == 0)
			{
				pushError(at(source, line, 'parameter #' + index + ' has no "name" and was skipped'));
				continue;
			}
			name = name.trim();

			var type:ParamType = readParamType(tblString(entry, 'type'), name, source, line);
			var options:Array<String> = readOptions(tblGet(entry, 'options'), name, source, line);
			var description:Null<String> = tblString(entry, 'description');

			var parameter:BlockParameter = {
				name: name,
				type: type,
				defaultValue: readDefault(entry, type, options)
			};
			if (options.length > 0)
				parameter.options = options;
			if (description != null && description.length > 0)
				parameter.description = description;
			out.push(parameter);
		}
		return out;
	}

	static function readParamType(raw:String, name:String, source:String, line:Int):ParamType
	{
		switch (raw == null ? '' : raw.trim().toLowerCase())
		{
			case 'string', 'text', 'str', '':
				return ParamType.STRING;
			case 'number', 'num', 'int', 'integer', 'float', 'double':
				return ParamType.NUMBER;
			case 'bool', 'boolean', 'flag':
				return ParamType.BOOL;
			case 'code', 'lua', 'script':
				return ParamType.CODE;
			case 'color', 'colour', 'hex':
				return ParamType.COLOR;
			case 'select', 'enum', 'choice', 'dropdown', 'options':
				return ParamType.SELECT;
			default:
				pushError(at(source, line, 'parameter "' + name + '" has the unknown type "' + raw + '"; string is used instead'));
				return ParamType.STRING;
		}
	}

	static function readOptions(raw:Dynamic, name:String, source:String, line:Int):Array<String>
	{
		var out:Array<String> = [];
		var list:Array<Dynamic> = tblArray(raw);
		if (list == null)
		{
			if (raw != null)
				pushError(at(source, line, 'the "options" of parameter "' + name + '" must be a list'));
			return out;
		}
		for (entry in list)
		{
			var text:String = asText(entry);
			if (text != null)
				out.push(text);
		}
		return out;
	}

	static function readDefault(raw:Dynamic, type:ParamType, options:Array<String>):Dynamic
	{
		var declared:Dynamic = tblGet(raw, 'defaultValue');
		switch (cast(type, String))
		{
			case 'number':
				var number:Null<Float> = tblNumber(raw, 'defaultValue');
				return number == null ? 0 : number;
			case 'bool':
				var flag:Null<Bool> = tblBool(raw, 'defaultValue');
				return flag == null ? false : flag;
			case 'color':
				if (declared == null)
					return '';
				if (Std.isOfType(declared, String))
					return (cast declared : String).trim();
				var color:Null<Int> = parseColor(declared);
				return color == null ? '' : toHexColor(color);
			default:
				var text:String = asText(declared);
				if (text != null)
					return text;
				if (type == ParamType.SELECT && options.length > 0)
					return options[0];
				return '';
		}
	}

	static function toHexColor(value:Int):String
	{
		var alpha:Int = (value >> 24) & 0xFF;
		return alpha == 0xFF ? StringTools.hex(value & 0xFFFFFF, 6) : StringTools.hex(value, 8);
	}

	// ------------------------------------------------------------------ built-in types

	static function isBuiltInType(type:String):Bool
	{
		if (type == null)
			return false;
		var map:Map<String, Bool> = builtInTypes();
		return map.exists(type);
	}

	static function builtInTypes():Map<String, Bool>
	{
		if (builtInCache != null)
			return builtInCache;

		var map:Map<String, Bool> = new Map();
		for (type in BUILT_IN_TYPES)
			map.set(type, true);

		// best effort: honour the block list of the built-in library module when it is
		// compiled in, so an external block can never shadow a built-in one.
		if (!resolvingBuiltIns)
		{
			resolvingBuiltIns = true;
			try
			{
				var library:Class<Dynamic> = Type.resolveClass('editors.blockcode.BlockLibrary');
				if (library != null)
				{
					for (field in LIBRARY_FIELDS)
					{
						var value:Dynamic = null;
						try
						{
							value = Reflect.field(library, field);
						}
						catch (e:Dynamic)
						{
							continue;
						}
						if (value != null && Reflect.isFunction(value))
						{
							value = try Reflect.callMethod(library, value, []) catch (e:Dynamic) null;
						}
						if (!Std.isOfType(value, Array))
							continue;
						for (category in (cast value : Array<Dynamic>))
							collectLibraryTypes(category, map);
					}
				}
			}
			catch (e:Dynamic)
			{
			}
			resolvingBuiltIns = false;
		}

		builtInCache = map;
		return builtInCache;
	}

	static function collectLibraryTypes(category:Dynamic, map:Map<String, Bool>):Void
	{
		var list:Array<Dynamic> = tblArray(tblGet(category, 'blocks'));
		if (list == null)
			return;
		for (block in list)
		{
			var type:String = tblString(block, 'type');
			if (type != null && type.length > 0)
				map.set(type, true);
		}
	}

	// ------------------------------------------------------------------ value helpers

	/** Reads a field of a JSON object or of a Lua table. */
	static function tblGet(value:Dynamic, key:String):Dynamic
	{
		if (value == null || key == null)
			return null;
		if (Std.isOfType(value, LuaTable))
			return (cast value : LuaTable).fields.get(key);
		if (isTable(value))
			return Reflect.field(value, key);
		return null;
	}

	static function tblString(value:Dynamic, key:String):Null<String>
	{
		return asText(tblGet(value, key));
	}

	static function tblBool(value:Dynamic, key:String):Null<Bool>
	{
		var raw:Dynamic = tblGet(value, key);
		if (raw == null)
			return null;
		if (Std.isOfType(raw, Bool))
			return (cast raw : Bool);
		if (Std.isOfType(raw, String))
		{
			switch ((cast raw : String).trim().toLowerCase())
			{
				case 'true', 'yes', 'on', '1':
					return true;
				case 'false', 'no', 'off', '0':
					return false;
				default:
					return null;
			}
		}
		switch (Type.typeof(raw))
		{
			case TInt, TFloat:
				var number:Float = raw;
				return number != 0;
			default:
				return null;
		}
	}

	static function tblNumber(value:Dynamic, key:String):Null<Float>
	{
		var raw:Dynamic = tblGet(value, key);
		if (raw == null)
			return null;
		if (Std.isOfType(raw, String))
		{
			var text:String = (cast raw : String).trim();
			if (text.length == 0)
				return null;
			if (text.startsWith('0x') || text.startsWith('0X'))
			{
				var color:Null<Int> = parseColorString(text);
				return color == null ? null : color * 1.0;
			}
			var parsed:Float = Std.parseFloat(text);
			return Math.isNaN(parsed) ? null : parsed;
		}
		switch (Type.typeof(raw))
		{
			case TInt, TFloat:
				return raw;
			default:
				return null;
		}
	}

	static function tblArray(raw:Dynamic):Null<Array<Dynamic>>
	{
		if (raw == null)
			return null;
		if (Std.isOfType(raw, Array))
			return (cast raw : Array<Dynamic>);
		if (Std.isOfType(raw, LuaTable))
			return (cast raw : LuaTable).array.copy();
		return null;
	}

	static function asText(raw:Dynamic):Null<String>
	{
		if (raw == null)
			return null;
		if (Std.isOfType(raw, String))
			return (cast raw : String);
		if (Std.isOfType(raw, Bool))
			return (cast raw : Bool) ? 'true' : 'false';
		switch (Type.typeof(raw))
		{
			case TInt, TFloat:
				return Std.string(raw);
			default:
				return null;
		}
	}

	/** True for a JSON object (an anonymous structure), false for arrays, strings and numbers. */
	static function isTable(value:Dynamic):Bool
	{
		if (value == null || Std.isOfType(value, Array) || Std.isOfType(value, String))
			return false;
		return switch (Type.typeof(value))
		{
			case TObject, TClass(_): true;
			default: false;
		}
	}

	// ------------------------------------------------------------------ colours

	static function parseColor(value:Dynamic):Null<Int>
	{
		if (value == null || Std.isOfType(value, Bool))
			return null;
		if (Std.isOfType(value, String))
			return parseColorString(cast value);
		switch (Type.typeof(value))
		{
			case TInt:
				return (cast value : Int);
			case TFloat:
				return floatBits((cast value : Float));
			default:
				return null;
		}
	}

	static function parseColorString(raw:String):Null<Int>
	{
		if (raw == null)
			return null;
		var text:String = raw.trim();
		if (text.length == 0)
			return null;

		var prefixed:Bool = false;
		if (text.startsWith('#'))
		{
			text = text.substr(1);
			prefixed = true;
		}
		else if (text.startsWith('0x') || text.startsWith('0X'))
		{
			text = text.substr(2);
			prefixed = true;
		}
		else if (text.startsWith('$'))
		{
			text = text.substr(1);
			prefixed = true;
		}
		text = text.trim();
		if (text.length == 0)
			return null;

		if (isHexString(text))
		{
			if (prefixed && text.length == 3)
			{
				text = text.charAt(0) + text.charAt(0) + text.charAt(1) + text.charAt(1) + text.charAt(2) + text.charAt(2);
			}
			else if (prefixed && text.length == 4)
			{
				text = text.charAt(0)
					+ text.charAt(0)
					+ text.charAt(1)
					+ text.charAt(1)
					+ text.charAt(2)
					+ text.charAt(2)
					+ text.charAt(3)
					+ text.charAt(3);
			}
			if (text.length == 6)
				return 0xFF000000 | hexToBits(text);
			if (text.length == 8)
				return hexToBits(text);
			if (prefixed)
				return hexToBits(text);
		}

		var decimal:Null<Int> = Std.parseInt(text);
		if (decimal != null)
			return decimal;
		var float:Float = Std.parseFloat(text);
		return Math.isNaN(float) ? null : floatBits(float);
	}

	static function isHexString(text:String):Bool
	{
		if (text == null || text.length == 0)
			return false;
		for (i in 0...text.length)
		{
			if (hexDigit(text.charAt(i)) < 0)
				return false;
		}
		return true;
	}

	static function hexDigit(char:String):Int
	{
		if (char >= '0' && char <= '9')
			return char.charCodeAt(0) - 48;
		if (char >= 'a' && char <= 'f')
			return char.charCodeAt(0) - 87;
		if (char >= 'A' && char <= 'F')
			return char.charCodeAt(0) - 55;
		return -1;
	}

	static function hexToBits(text:String):Int
	{
		var value:Float = 0;
		for (i in 0...text.length)
		{
			var digit:Int = hexDigit(text.charAt(i));
			if (digit < 0)
				break;
			value = value * 16 + digit;
		}
		return floatBits(value);
	}

	/** Wraps an out of range JSON/Lua number into the 32 bit pattern of a colour. */
	static function floatBits(value:Float):Int
	{
		var wrapped:Float = value % 4294967296.0;
		if (wrapped < 0)
			wrapped += 4294967296.0;
		if (wrapped >= 2147483648.0)
			wrapped -= 4294967296.0;
		return Std.int(wrapped);
	}

	/** A stable colour for a category name that declared none. */
	static function deriveColor(name:String):Int
	{
		var key:String = name == null ? '' : name;
		var hash:Int = 0x811C9DC5;
		for (i in 0...key.length)
		{
			hash = hash ^ key.charCodeAt(i);
			hash = hash * 0x01000193;
		}
		var hue:Float = (hash & 0x7FFFFFFF) % 360;
		return hsvColor(hue, 0.55, 0.95);
	}

	static function hsvColor(hue:Float, saturation:Float, value:Float):Int
	{
		var chroma:Float = value * saturation;
		var sector:Float = (hue % 360) / 60;
		var second:Float = chroma * (1 - Math.abs((sector % 2) - 1));
		var red:Float = 0;
		var green:Float = 0;
		var blue:Float = 0;
		if (sector < 1)
		{
			red = chroma;
			green = second;
		}
		else if (sector < 2)
		{
			red = second;
			green = chroma;
		}
		else if (sector < 3)
		{
			green = chroma;
			blue = second;
		}
		else if (sector < 4)
		{
			green = second;
			blue = chroma;
		}
		else if (sector < 5)
		{
			red = second;
			blue = chroma;
		}
		else
		{
			red = chroma;
			blue = second;
		}
		var base:Float = value - chroma;
		return 0xFF000000 | (channel255(red + base) << 16) | (channel255(green + base) << 8) | channel255(blue + base);
	}

	static function channel255(value:Float):Int
	{
		var channel:Int = Std.int(value * 255 + 0.5);
		if (channel < 0)
			channel = 0;
		if (channel > 255)
			channel = 255;
		return channel;
	}

	static function fnv1a(text:String):Int
	{
		var hash:Int = 0x811C9DC5;
		for (i in 0...text.length)
		{
			hash = hash ^ text.charCodeAt(i);
			hash = hash * 0x01000193;
		}
		return hash;
	}

	// ------------------------------------------------------------------ diagnostics

	static function at(source:String, line:Int, message:String):String
	{
		var where:String = source == null || source.length == 0 ? 'blockcode' : source;
		if (line > 0)
			where += ':' + line;
		return where + ': ' + message;
	}

	static function pushError(message:String):Void
	{
		pushInto(errors, reported, message);
	}

	/** Runtime registration messages are kept until the end of the session. */
	static function pushRuntimeError(message:String):Void
	{
		pushInto(runtimeErrors, runtimeReported, message);
	}

	static function pushInto(list:Array<String>, seen:Map<String, Bool>, message:String):Void
	{
		if (message == null || message.length == 0)
			return;
		if (seen.exists(message))
			return;
		if (list.length >= MAX_ERRORS)
		{
			var overflow:String = '... further messages were suppressed';
			if (!seen.exists(overflow))
			{
				seen.set(overflow, true);
				list.push(overflow);
			}
			return;
		}
		seen.set(message, true);
		list.push(message);
	}
}

/** One `registerCategory` / `registerBlock` statement found in a Lua config file. */
private typedef LuaCommand =
{
	/** Normalized target: `category` or `block`. */
	var name:String;

	/** The callee as written, used for messages. */
	var rawName:String;

	var line:Int;

	/** Positional arguments: strings/numbers and at most one table. */
	var args:Array<Dynamic>;
}

private enum LuaTokenType
{
	TName;
	TNumber;
	TString;
	TLBrace;
	TRBrace;
	TLBracket;
	TRBracket;
	TLParen;
	TRParen;
	TComma;
	TSemi;
	TAssign;
	TDot;
	TColon;
	TOther;
	TEof;
}

private typedef LuaToken =
{
	var type:LuaTokenType;

	/** Raw text for names/numbers/other, decoded text for strings. */
	var value:String;

	/** Numeric value of a `TNumber` token. */
	var number:Float;

	var line:Int;
}

/** A Lua table literal: named/`[expr]` keys plus the bare array part, in insertion order. */
private class LuaTable
{
	public var fields:Map<String, Dynamic> = new Map();
	public var array:Array<Dynamic> = [];

	public function new()
	{
	}

	public function set(key:String, value:Dynamic):Void
	{
		fields.set(key, value);
	}
}

/**
 * Tolerant Lua *table literal* parser: it never executes anything, it only walks the text
 * and hands the `registerCategory` / `registerBlock` calls back as `LuaCommand`s. Anything
 * it cannot understand becomes a message in `takeErrors()` instead of a crash. The exact
 * accepted subset is documented at the top of `BlockConfigLoader`.
 */
private class LuaParser
{
	static inline var MAX_PARSER_ERRORS:Int = 100;

	public var source:String;

	var tokens:Array<LuaToken> = [];
	var errors:Array<String> = [];
	var pos:Int = 0;

	public function new(source:String, text:String)
	{
		this.source = source;
		tokenize(text == null ? '' : text);
	}

	public function takeErrors():Array<String>
	{
		return errors;
	}

	public function parseStatements():Array<LuaCommand>
	{
		var out:Array<LuaCommand> = [];
		while (pos < tokens.length)
		{
			var token:LuaToken = tokens[pos];
			if (token.type == TEof)
				break;

			if (token.type == TSemi)
			{
				pos++;
				continue;
			}

			if (token.type != TName)
			{
				skipStatement(token.line);
				continue;
			}

			var rawName:String = token.value;
			var line:Int = token.line;
			pos++;

			var args:Array<Dynamic> = parseCallArgs();
			var name:String = normalizeCallee(rawName);
			if (name == null)
			{
				if (args.length > 0)
					unknownCall(rawName)
				else
					skipStatement(line);
				skipSeparators();
				continue;
			}

			out.push({
				name: name,
				rawName: rawName,
				line: line,
				args: args
			});
			skipSeparators();
		}
		return out;
	}

	static function normalizeCallee(rawName:String):Null<String>
	{
		if (rawName == null)
			return null;
		var name:String = rawName.toLowerCase().replace('_', '').replace('-', '');
		if (name == 'registercategory' || name == 'registercategories' || name == 'addcategory')
			return 'category';
		if (name == 'registerblock' || name == 'registerblocks' || name == 'addblock')
			return 'block';
		return null;
	}

	/** Reads `{ ... }`, `( ... )` or a single bare string literal after a callee. */
	function parseCallArgs():Array<Dynamic>
	{
		var args:Array<Dynamic> = [];
		if (pos >= tokens.length)
			return args;

		var token:LuaToken = tokens[pos];
		if (token.type == TLBrace)
		{
			args.push(parseTable());
			return args;
		}

		if (token.type == TLParen)
		{
			pos++;
			while (pos < tokens.length)
			{
				var inner:LuaToken = tokens[pos];
				if (inner.type == TRParen)
				{
					pos++;
					break;
				}
				if (inner.type == TEof)
				{
					err(inner.line, 'unterminated "(" in a call');
					break;
				}
				if (inner.type == TComma || inner.type == TSemi)
				{
					pos++;
					continue;
				}
				args.push(parseValue());
			}
			return args;
		}

		if (token.type == TString)
		{
			// `registerBlock "myFx.play"` — a bare string is the only Lua call shorthand we accept
			args.push(parseValue());
			return args;
		}
		return args;
	}

	function parseTable():LuaTable
	{
		var table:LuaTable = new LuaTable();
		if (pos < tokens.length && tokens[pos].type == TLBrace)
			pos++;
		else
		{
			err(currentLine(), 'expected "{"');
			return table;
		}

		while (pos < tokens.length)
		{
			var token:LuaToken = tokens[pos];
			if (token.type == TRBrace)
			{
				pos++;
				return table;
			}
			if (token.type == TEof)
			{
				err(token.line, 'unterminated table, "}" is missing');
				return table;
			}
			if (token.type == TComma || token.type == TSemi)
			{
				pos++;
				continue;
			}

			if (token.type == TLBracket)
			{
				pos++;
				var key:Dynamic = parseValue();
				if (pos < tokens.length && tokens[pos].type == TRBracket)
					pos++;
				else
					err(token.line, 'expected "]" after a computed table key');
				if (pos < tokens.length && tokens[pos].type == TAssign)
					pos++;
				else
				{
					err(token.line, 'expected "=" after a computed table key');
					continue;
				}
				table.set(keyText(key), parseValue());
				continue;
			}

			if (token.type == TName && pos + 1 < tokens.length && tokens[pos + 1].type == TAssign)
			{
				var key:String = token.value;
				pos += 2;
				table.set(key, parseValue());
				continue;
			}

			table.array.push(parseValue());
		}
		return table;
	}

	function parseValue():Dynamic
	{
		if (pos >= tokens.length)
			return null;
		var token:LuaToken = tokens[pos];

		switch (token.type)
		{
			case TString:
				pos++;
				return token.value;
			case TNumber:
				pos++;
				return token.number;
			case TName:
				pos++;
				switch (token.value.toLowerCase())
				{
					case 'true': return true;
					case 'false': return false;
					case 'nil', 'null': return null;
					default: return token.value;
				}
			case TLBrace:
				return parseTable();
			case TOther:
				pos++;
				if (token.value == '-')
				{
					var value:Dynamic = parseValue();
					if (Std.isOfType(value, Float))
						return -(cast value : Float);
					if (Std.isOfType(value, Int))
						return -(cast value : Int);
					return null;
				}
				err(token.line, 'unexpected "' + token.value + '"');
				return null;
			case TLBracket, TRBracket, TLParen, TRParen, TRBrace, TComma, TSemi, TAssign, TDot, TColon:
				pos++;
				err(token.line, 'unexpected "' + token.value + '"');
				return null;
			case TEof:
				return null;
		}
	}

	/** Skips everything up to the end of the statement starting on `startLine`. */
	function skipStatement(startLine:Int):Void
	{
		var depth:Int = 0;
		while (pos < tokens.length)
		{
			var token:LuaToken = tokens[pos];
			if (token.type == TEof)
				return;
			if (token.type == TLBrace || token.type == TLParen || token.type == TLBracket)
				depth++;
			else if (token.type == TRBrace || token.type == TRParen || token.type == TRBracket)
				depth--;
			else if (depth <= 0)
			{
				if (token.type == TSemi)
				{
					pos++;
					return;
				}
				if (token.line > startLine)
					return;
			}
			pos++;
		}
	}

	function skipSeparators():Void
	{
		while (pos < tokens.length && (tokens[pos].type == TSemi || tokens[pos].type == TComma))
			pos++;
	}

	static function keyText(key:Dynamic):String
	{
		var text:String = asKey(key);
		return text == null ? 'nil' : text;
	}

	static function asKey(key:Dynamic):Null<String>
	{
		if (key == null)
			return null;
		if (Std.isOfType(key, String))
			return (cast key : String);
		if (Std.isOfType(key, Bool))
			return (cast key : Bool) ? 'true' : 'false';
		switch (Type.typeof(key))
		{
			case TInt, TFloat:
				return Std.string(key);
			default:
				return null;
		}
	}

	function currentLine():Int
	{
		if (pos < tokens.length)
			return tokens[pos].line;
		return tokens.length > 0 ? tokens[tokens.length - 1].line : 1;
	}

	function err(line:Int, message:String):Void
	{
		var where:String = source == null || source.length == 0 ? 'lua' : source;
		var text:String = where + ':' + line + ': ' + message;
		if (!errors.contains(text) && errors.length < MAX_PARSER_ERRORS)
			errors.push(text);
	}

	function unknownCall(rawName:String):Void
	{
		var where:String = source == null || source.length == 0 ? 'lua' : source;
		var text:String = where + ': ignored the unknown call "' + rawName + '"';
		if (!errors.contains(text) && errors.length < MAX_PARSER_ERRORS)
			errors.push(text);
	}

	// ------------------------------------------------------------------ tokenizer

	function tokenize(text:String):Void
	{
		var index:Int = 0;
		var line:Int = 1;
		var total:Int = text.length;

		while (index < total)
		{
			var char:String = text.charAt(index);

			if (char == '\n')
			{
				line++;
				index++;
				continue;
			}
			if (isWhitespace(char))
			{
				index++;
				continue;
			}

			if (char == '-' && index + 1 < total && text.charAt(index + 1) == '-')
			{
				index += 2;
				var comment:Null<{body:String, next:Int}> = readLongBracket(text, index);
				if (comment != null)
				{
					line += countNewlines(comment.body);
					index = comment.next;
				}
				else
				{
					while (index < total && text.charAt(index) != '\n')
						index++;
				}
				continue;
			}

			if (char == '[')
			{
				var long:Null<{body:String, next:Int}> = readLongBracket(text, index);
				if (long != null)
				{
					tokens.push({
						type: TString,
						value: long.body,
						number: 0,
						line: line
					});
					line += countNewlines(long.body);
					index = long.next;
					continue;
				}
			}

			if (char == '"' || char == '\'')
			{
				var quoted:Null<{value:String, next:Int, newlines:Int}> = readQuoted(text, index);
				if (quoted == null)
				{
					err(line, 'unterminated string literal');
					break;
				}
				tokens.push({
					type: TString,
					value: quoted.value,
					number: 0,
					line: line
				});
				line += quoted.newlines;
				index = quoted.next;
				continue;
			}

			if (isDigit(char) || (char == '.' && index + 1 < total && isDigit(text.charAt(index + 1))))
			{
				var end:Int = index;
				var hex:Bool = false;
				if (char == '0' && index + 1 < total && (text.charAt(index + 1) == 'x' || text.charAt(index + 1) == 'X'))
				{
					hex = true;
					end = index + 2;
					while (end < total && isHexDigit(text.charAt(end)))
						end++;
				}
				else
				{
					while (end < total && (isDigit(text.charAt(end)) || text.charAt(end) == '.'))
						end++;
					if (end < total && (text.charAt(end) == 'e' || text.charAt(end) == 'E'))
					{
						end++;
						if (end < total && (text.charAt(end) == '+' || text.charAt(end) == '-'))
							end++;
						while (end < total && isDigit(text.charAt(end)))
							end++;
					}
				}
				var raw:String = text.substring(index, end);
				var value:Float = hex ? hexValue(raw.substr(2)) : Std.parseFloat(raw);
				if (Math.isNaN(value))
				{
					err(line, 'could not read the number "' + raw + '"');
					value = 0;
				}
				tokens.push({
					type: TNumber,
					value: raw,
					number: value,
					line: line
				});
				index = end;
				continue;
			}

			if (isNameStart(char))
			{
				var end:Int = index;
				while (end < total && isNamePart(text.charAt(end)))
					end++;
				tokens.push({
					type: TName,
					value: text.substring(index, end),
					number: 0,
					line: line
				});
				index = end;
				continue;
			}

			var type:LuaTokenType = TOther;
			switch (char)
			{
				case '{':
					type = TLBrace;
				case '}':
					type = TRBrace;
				case '[':
					type = TLBracket;
				case ']':
					type = TRBracket;
				case '(':
					type = TLParen;
				case ')':
					type = TRParen;
				case ',':
					type = TComma;
				case ';':
					type = TSemi;
				case '=':
					type = TAssign;
				case '.':
					type = TDot;
				case ':':
					type = TColon;
				default:
					type = TOther;
			}
			tokens.push({
				type: type,
				value: char,
				number: 0,
				line: line
			});
			index++;
		}

		tokens.push({
			type: TEof,
			value: '',
			number: 0,
			line: line
		});
	}

	/** `[[ ... ]]`, `[=[ ... ]=]`, … Returns null when this is not a long bracket. */
	static function readLongBracket(text:String, index:Int):Null<{body:String, next:Int}>
	{
		if (index >= text.length || text.charAt(index) != '[')
			return null;
		var cursor:Int = index + 1;
		var level:Int = 0;
		while (cursor < text.length && text.charAt(cursor) == '=')
		{
			level++;
			cursor++;
		}
		if (cursor >= text.length || text.charAt(cursor) != '[')
			return null;
		cursor++;

		var closing:String = ']' + repeat('=', level) + ']';
		var end:Int = text.indexOf(closing, cursor);
		if (end < 0)
			return {body: text.substring(cursor), next: text.length};
		return {body: text.substring(cursor, end), next: end + closing.length};
	}

	static function readQuoted(text:String, index:Int):Null<{value:String, next:Int, newlines:Int}>
	{
		var quote:String = text.charAt(index);
		var buffer:StringBuf = new StringBuf();
		var cursor:Int = index + 1;
		var newlines:Int = 0;

		while (cursor < text.length)
		{
			var char:String = text.charAt(cursor);
			if (char == quote)
				return {value: buffer.toString(), next: cursor + 1, newlines: newlines};

			if (char != '\\')
			{
				if (char == '\n')
					newlines++;
				buffer.add(char);
				cursor++;
				continue;
			}

			cursor++;
			if (cursor >= text.length)
				break;
			var escape:String = text.charAt(cursor);
			switch (escape)
			{
				case 'n':
					buffer.add('\n');
					cursor++;
				case 't':
					buffer.add('\t');
					cursor++;
				case 'r':
					buffer.add('\r');
					cursor++;
				case 'a':
					buffer.add('\x07');
					cursor++;
				case 'b':
					buffer.add('\x08');
					cursor++;
				case 'f':
					buffer.add('\x0C');
					cursor++;
				case 'v':
					buffer.add('\x0B');
					cursor++;
				case '\n':
					buffer.add('\n');
					newlines++;
					cursor++;
				case 'x':
					cursor++;
					var hexDigits:String = '';
					while (hexDigits.length < 2 && cursor < text.length && isHexDigit(text.charAt(cursor)))
					{
						hexDigits += text.charAt(cursor);
						cursor++;
					}
					buffer.add(hexDigits.length == 0 ? 'x' : String.fromCharCode(Std.int(hexValue(hexDigits))));
				case 'u':
					if (cursor + 1 < text.length && text.charAt(cursor + 1) == '{')
					{
						var closing:Int = text.indexOf('}', cursor + 2);
						if (closing < 0)
						{
							buffer.add('u');
							cursor++;
						}
						else
						{
							var code:Int = Std.int(hexValue(text.substring(cursor + 2, closing)));
							buffer.add(codePoint(code));
							cursor = closing + 1;
						}
					}
					else
					{
						buffer.add('u');
						cursor++;
					}
				case 'z':
					cursor++;
					while (cursor < text.length && isWhitespaceOrNewline(text.charAt(cursor)))
					{
						if (text.charAt(cursor) == '\n')
							newlines++;
						cursor++;
					}
				default:
					if (isDigit(escape))
					{
						var digits:String = '';
						while (digits.length < 3 && cursor < text.length && isDigit(text.charAt(cursor)))
						{
							digits += text.charAt(cursor);
							cursor++;
						}
						var code:Null<Int> = Std.parseInt(digits);
						buffer.add(String.fromCharCode(code == null ? 0 : code));
					}
					else
					{
						buffer.add(escape);
						cursor++;
					}
			}
		}
		return null;
	}

	static function codePoint(code:Int):String
	{
		if (code < 0)
			return '';
		if (code <= 0xFFFF)
			return String.fromCharCode(code);
		var value:Int = code - 0x10000;
		return String.fromCharCode(0xD800 + (value >> 10)) + String.fromCharCode(0xDC00 + (value & 0x3FF));
	}

	static function hexValue(text:String):Float
	{
		var value:Float = 0;
		for (i in 0...text.length)
		{
			var digit:Int = hexDigit(text.charAt(i));
			if (digit < 0)
				break;
			value = value * 16 + digit;
		}
		return value;
	}

	static function countNewlines(text:String):Int
	{
		var count:Int = 0;
		for (i in 0...text.length)
		{
			if (text.charAt(i) == '\n')
				count++;
		}
		return count;
	}

	static function repeat(char:String, times:Int):String
	{
		var buffer:StringBuf = new StringBuf();
		for (i in 0...times)
			buffer.add(char);
		return buffer.toString();
	}

	static function isDigit(char:String):Bool
	{
		return char.length == 1 && char >= '0' && char <= '9';
	}

	static function isHexDigit(char:String):Bool
	{
		return hexDigit(char) >= 0;
	}

	static function hexDigit(char:String):Int
	{
		if (char.length != 1)
			return -1;
		if (char >= '0' && char <= '9')
			return char.charCodeAt(0) - 48;
		if (char >= 'a' && char <= 'f')
			return char.charCodeAt(0) - 87;
		if (char >= 'A' && char <= 'F')
			return char.charCodeAt(0) - 55;
		return -1;
	}

	static function isNameStart(char:String):Bool
	{
		if (char.length != 1)
			return false;
		if (char == '_')
			return true;
		return (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z');
	}

	static function isNamePart(char:String):Bool
	{
		return isNameStart(char) || isDigit(char);
	}

	static function isWhitespace(char:String):Bool
	{
		return char == ' ' || char == '\t' || char == '\r' || char == '\x0B' || char == '\x0C';
	}

	static function isWhitespaceOrNewline(char:String):Bool
	{
		return isWhitespace(char) || char == '\n';
	}
}

/**
 * Builds the merged category list of one load pass: categories in first-seen order, blocks
 * in first-seen order, and only the first block of a type is kept.
 */
private class CategoryAccumulator
{
	public var order:Array<String> = [];
	public var map:Map<String, BlockCategory> = new Map();

	var explicitColor:Map<String, Bool> = new Map();
	var seenTypes:Map<String, Bool> = new Map();

	public function new()
	{
	}

	public function ensure(name:String, color:Int, ?icon:String, colorIsExplicit:Bool = false):BlockCategory
	{
		var category:BlockCategory = map.get(name);
		if (category == null)
		{
			category = {
				name: name,
				color: color,
				icon: icon == null || icon.length == 0 ? '*' : icon,
				blocks: [],
				external: true
			};
			map.set(name, category);
			order.push(name);
			explicitColor.set(name, colorIsExplicit);
			return category;
		}

		if (colorIsExplicit && explicitColor.get(name) != true)
		{
			category.color = color;
			explicitColor.set(name, true);
		}
		if (icon != null && icon.length > 0)
			category.icon = icon;
		return category;
	}

	/** The colour declared for a category, or null when it is not known (yet). */
	public function colorOf(name:String):Null<Int>
	{
		if (name == null)
			return null;
		var category:BlockCategory = map.get(name);
		return category == null ? null : category.color;
	}

	/** Adds a block to its own category. Returns false when its type was already used. */
	public function add(block:BlockData):Bool
	{
		if (block == null || block.type == null || block.type.length == 0)
			return false;
		if (seenTypes.exists(block.type))
			return false;
		seenTypes.set(block.type, true);
		ensure(block.category, block.color, null, false).blocks.push(block);
		return true;
	}

	public function result():Array<BlockCategory>
	{
		var out:Array<BlockCategory> = [];
		for (name in order)
		{
			var category:BlockCategory = map.get(name);
			if (category != null && category.blocks.length > 0)
				out.push(category);
		}
		return out;
	}
}
