package editors.blockcode;

import editors.blockcode.Block.InputField;
import editors.blockcode.BlockTypes.BlockCodeEditorSettings;
import editors.blockcode.BlockTypes.BlockData;
import editors.blockcode.BlockTypes.BlockParameter;
import editors.blockcode.BlockTypes.BlockProject;
import editors.blockcode.BlockTypes.ParamType;
import editors.blockcode.BlockTypes.TimelineEntry;
import editors.blockcode.BlockTypes.TimelineMarker;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.util.FlxSave;
import haxe.Json;

using StringTools;

/**
 * Block trees to plain data and back, plus the editor cache and the editor settings
 * kept in a `FlxSave`.
 *
 * The node format is the one `editors.BlockCodeEditorState` wrote, so caches and
 * projects made by the old editor still load:
 *
 * ```json
 * { "type": "makeLuaSprite", "x": 40, "y": 80, "inputs": [ { "index": 0, "value": "bg" } ], "next": null }
 * ```
 *
 * A cached tree is plain data a user can hand edit or that a mod's config can shorten,
 * so every reader falls back to a default instead of throwing, and a node whose type is
 * unknown is repaired into a grey placeholder rather than dropped.
 */
class BlockSerializer
{
	/** FlxSave the editor document and settings live in. */
	static inline var CACHE_NAME:String = 'blockcodeEditor';

	/** FlxSave folder; the legacy editor used the same one, which is what makes migration possible. */
	static inline var CACHE_PATH:String = 'parker-engine';

	/** Binding `BlockCodeEditorState` cached its blocks in; read only to migrate it once. */
	static inline var LEGACY_CACHE_NAME:String = 'blockEditorCache';

	/** How deep reporter arguments may nest before the readers give up on the data. */
	static inline var MAX_NESTING:Int = 256;

	/** How many blocks a chain walk accepts before it assumes the links are broken. */
	static inline var MAX_CHAIN_LENGTH:Int = 4096;

	static inline var UNKNOWN_COLOR:Int = 0xFF888888;
	static inline var UNKNOWN_CATEGORY:String = 'Lua';
	static inline var UNKNOWN_DESCRIPTION:String = 'Unknown block type';

	static inline var MIN_ZOOM:Float = 0.25;
	static inline var MAX_ZOOM:Float = 4;

	static var _cache:FlxSave;
	static var _legacyCache:FlxSave;

	// --- Block trees ---

	/** Plain data of the chain starting at `root`, or null when there is no root. */
	public static function serializeStack(root:Block):Dynamic
	{
		return serializeChain(root, 0);
	}

	/**
	 * Walks the chain iteratively (a deep chain must not run into the call stack) and
	 * serializes every block's arguments, reporting blocks included.
	 */
	static function serializeChain(root:Block, depth:Int):Dynamic
	{
		if (root == null || depth > MAX_NESTING)
			return null;

		var head:BlockNode = null;
		var tail:BlockNode = null;
		var current:Block = root;
		var walked:Int = 0;

		while (current != null && walked++ < MAX_CHAIN_LENGTH)
		{
			var node:BlockNode = {
				type: (current.blockData == null) ? '' : current.blockData.type,
				x: current.x,
				y: current.y,
				inputs: serializeInputs(current, depth + 1),
				next: null
			};

			if (tail == null)
				head = node;
			else
				tail.next = node;

			tail = node;
			current = current.nextBlock;
		}

		return head;
	}

	/** One `{ index, value }` entry per input, the value being a primitive or a nested node. */
	static function serializeInputs(block:Block, depth:Int):Array<Dynamic>
	{
		var inputs:Array<Dynamic> = [];
		if (block.inputFields == null || depth > MAX_NESTING)
			return inputs;

		for (index in 0...block.inputFields.length)
		{
			var input:InputField = block.inputFields[index];
			if (input == null)
				continue;

			var value:Dynamic = input.value;
			if (input.attachedBlock != null)
				value = serializeChain(input.attachedBlock, depth);

			inputs.push({index: index, value: value});
		}

		return inputs;
	}

	/**
	 * Rebuilds the chain (and the reporter arguments attached to it) from `serializeStack`
	 * data: every block is created with `BlockLibrary.get(type)` and added to `container`,
	 * the links are wired, the chain is laid out and its root is returned.
	 *
	 * Returns null when `data` holds nothing usable.
	 */
	public static function deserializeStack(data:Dynamic, container:FlxTypedGroup<Block>):Null<Block>
	{
		var root:Block = buildNode(data, null, container, 0);
		if (root == null)
			return null;

		var current:Block = root;
		var nextData:Dynamic = readField(data, 'next');
		var walked:Int = 0;

		while (nextData != null && walked++ < MAX_CHAIN_LENGTH)
		{
			var following:Block = buildNode(nextData, null, container, 0);
			if (following == null)
				break;

			current.nextBlock = following;
			following.prevBlock = current;
			following.isSnapped = true;
			current = following;
			nextData = readField(nextData, 'next');
		}

		normalizeStack(root, 0);
		return root;
	}

	static function buildNode(data:Dynamic, parentInput:InputField, container:FlxTypedGroup<Block>, depth:Int):Null<Block>
	{
		if (depth > MAX_NESTING || !isObject(data))
			return null;

		var type:String = readString(readField(data, 'type'), '');
		if (type.length == 0)
			return null;

		var inputs:Array<Dynamic> = readArray(readField(data, 'inputs'));

		var definition:BlockData = BlockLibrary.get(type);
		if (definition == null)
			definition = unknownData(type, inputs == null ? 0 : inputs.length);

		var block:Block = new Block(readFloat(readField(data, 'x'), 0), readFloat(readField(data, 'y'), 0), definition);
		if (container != null)
			container.add(block);

		if (parentInput != null)
		{
			parentInput.attachedBlock = block;
			block.parentInput = parentInput;
			block.x = parentInput.bg.x;
			block.y = parentInput.bg.y;
		}

		if (inputs != null)
		{
			for (entry in inputs)
			{
				if (!isObject(entry))
					continue;

				var index:Int = readInt(readField(entry, 'index'), -1);
				if (index < 0 || index >= block.inputFields.length)
					continue;

				var input:InputField = block.inputFields[index];
				if (input == null)
					continue;

				var value:Dynamic = readField(entry, 'value');
				if (isPrimitive(value))
					setInputValue(input, value);
				else if (isObject(value))
					buildNode(value, input, container, depth + 1);
			}
		}

		block.recalculateSize();
		return block;
	}

	/** A restored primitive: assigning the value refreshes the field's display and the block size. */
	static function setInputValue(input:InputField, value:Dynamic):Void
	{
		input.value = value;
	}

	/** The catalogue knows nothing about this type: keep the node as a grey placeholder block. */
	static function unknownData(type:String, inputCount:Int):BlockData
	{
		var definition:BlockData = {
			type: type,
			label: type,
			color: UNKNOWN_COLOR,
			category: UNKNOWN_CATEGORY,
			lua: "$1",
			description: UNKNOWN_DESCRIPTION
		};

		if (inputCount > 0)
			definition.parameters = unknownParameters(inputCount);

		return definition;
	}

	/** Placeholder parameters: without them the node's saved arguments could not be restored. */
	static function unknownParameters(count:Int):Array<BlockParameter>
	{
		var parameters:Array<BlockParameter> = [];
		for (index in 0...count)
		{
			parameters.push({
				name: 'arg' + (index + 1),
				type: ParamType.STRING,
				defaultValue: '',
				description: UNKNOWN_DESCRIPTION
			});
		}
		return parameters;
	}

	// --- Layout ---

	/**
	 * Glues a chain back together: every block sits on top of the one above it and reports
	 * itself as snapped, and every attached reporter sits on the input that holds it.
	 */
	static function normalizeStack(root:Block, depth:Int):Void
	{
		if (root == null || depth > MAX_NESTING)
			return;

		var current:Block = root;
		var walked:Int = 0;
		while (current != null && walked++ < MAX_CHAIN_LENGTH)
		{
			positionAttached(current, depth);

			var following:Block = current.nextBlock;
			if (following == null)
				break;

			following.x = current.x;
			following.y = current.y + current.height;
			following.isSnapped = true;
			current = following;
		}
	}

	static function positionAttached(block:Block, depth:Int):Void
	{
		if (block.inputFields == null)
			return;

		for (input in block.inputFields)
		{
			if (input == null || input.attachedBlock == null)
				continue;

			var attached:Block = input.attachedBlock;
			if (input.bg != null)
			{
				attached.x = input.bg.x;
				attached.y = input.bg.y + (input.height - attached.height) / 2;
			}

			normalizeStack(attached, depth + 1);
		}
	}

	// --- Documents ---

	/** Snapshots the live workspace into a cacheable document. */
	public static function project(globals:Array<Block>, timeline:Array<{marker:TimelineMarker, root:Block}>, settings:BlockCodeEditorSettings):BlockProject
	{
		var stacks:Array<Dynamic> = [];
		if (globals != null)
		{
			for (block in globals)
			{
				var stack:Dynamic = serializeStack(block);
				if (stack != null)
					stacks.push(stack);
			}
		}

		var entries:Array<TimelineEntry> = [];
		if (timeline != null)
		{
			for (entry in timeline)
			{
				if (entry == null)
					continue;

				var marker:TimelineMarker = cloneMarker(entry.marker);
				if (marker == null)
					continue;

				entries.push({marker: marker, stack: serializeStack(entry.root)});
			}
		}

		return {
			version: BlockTypes.PROJECT_VERSION,
			stacks: stacks,
			timeline: entries,
			settings: (settings == null) ? BlockTypes.defaultSettings() : cloneSettings(settings)
		};
	}

	/**
	 * Rebuilds a whole document into `container`: the global stacks keep the order they
	 * were saved in, and every timeline marker comes back with the stack that was on it
	 * (`root` is null for a marker that had none).
	 */
	public static function restoreStacks(p:BlockProject,
			container:FlxTypedGroup<Block>):{globals:Array<Block>, timeline:Array<{marker:TimelineMarker, root:Block}>}
	{
		var globals:Array<Block> = [];
		var timeline:Array<{marker:TimelineMarker, root:Block}> = [];

		if (p == null)
			return {globals: globals, timeline: timeline};

		if (p.stacks != null)
		{
			for (stack in p.stacks)
			{
				var root:Block = deserializeStack(stack, container);
				if (root != null)
					globals.push(root);
			}
		}

		if (p.timeline != null)
		{
			for (entry in p.timeline)
			{
				if (entry == null)
					continue;

				var marker:TimelineMarker = cloneMarker(entry.marker);
				if (marker == null)
					continue;

				timeline.push({marker: marker, root: deserializeStack(entry.stack, container)});
			}
		}

		return {globals: globals, timeline: timeline};
	}

	// --- Cache ---

	/** Writes the document and its settings to the FlxSave; a failed write never throws. */
	public static function save(project:BlockProject):Void
	{
		var stored:FlxSave = cache();
		if (stored == null || project == null)
			return;

		var data:Dynamic = stored.data;
		if (data == null)
			return;

		data.project = plainProject(project);
		data.settings = settingsToData(project.settings);
		data.migrated = true;
		flush(stored);
	}

	/** The cached document, or null when nothing was cached yet. */
	public static function load():Null<BlockProject>
	{
		var stored:FlxSave = cache();
		if (stored == null)
			return null;

		var data:Dynamic = stored.data;
		var raw:Dynamic = readField(data, 'project');
		if (raw != null)
		{
			var parsed:Null<BlockProject> = parseProject(raw);
			if (parsed != null)
			{
				parsed.settings = loadSettings();
				return parsed;
			}
		}

		if (readBool(readField(data, 'migrated'), false))
			return null;

		return migrateLegacy(stored);
	}

	/** Forgets the cached document (the settings survive, and the legacy cache is not read again). */
	public static function clear():Void
	{
		var stored:FlxSave = cache();
		if (stored == null)
			return;

		var data:Dynamic = stored.data;
		if (data == null)
			return;

		data.project = null;
		data.migrated = true;
		flush(stored);
	}

	/** Editor settings, with every field falling back to `BlockTypes.defaultSettings()`. */
	public static function loadSettings():BlockCodeEditorSettings
	{
		var stored:FlxSave = cache();
		if (stored == null)
			return BlockTypes.defaultSettings();

		var data:Dynamic = stored.data;
		var raw:Dynamic = readField(data, 'settings');
		if (raw == null)
			raw = readField(readField(data, 'project'), 'settings');

		return parseSettings(raw);
	}

	public static function saveSettings(s:BlockCodeEditorSettings):Void
	{
		var stored:FlxSave = cache();
		if (stored == null)
			return;

		var data:Dynamic = stored.data;
		if (data == null)
			return;

		data.settings = settingsToData(s);
		flush(stored);
	}

	// --- Project files ---

	/** Pretty printed document, ready to be written to a `.json` file. */
	public static function exportJson(project:BlockProject):String
	{
		var source:BlockProject = (project == null) ? emptyProject() : project;
		return Json.stringify(plainProject(source), null, '\t');
	}

	/**
	 * Reads a document back, or null when the text is not a project (broken JSON, an
	 * unrelated file). The bare array the legacy editor exported is accepted as well and
	 * becomes the global stacks.
	 */
	public static function importJson(text:String):Null<BlockProject>
	{
		if (text == null)
			return null;

		var trimmed:String = text.trim();
		if (trimmed.length == 0)
			return null;

		var parsed:Dynamic = null;
		try
		{
			parsed = Json.parse(trimmed);
		}
		catch (e:Dynamic)
		{
			return null;
		}

		if (parsed == null)
			return null;

		var legacy:Array<Dynamic> = readArray(parsed);
		if (legacy != null)
		{
			var stacks:Array<Dynamic> = [];
			for (stack in legacy)
			{
				if (isObject(stack))
					stacks.push(stack);
			}

			if (stacks.length == 0)
				return null;

			var imported:BlockProject = emptyProject();
			imported.stacks = stacks;
			return imported;
		}

		return parseProject(parsed);
	}

	static function emptyProject():BlockProject
	{
		return {
			version: BlockTypes.PROJECT_VERSION,
			stacks: [],
			timeline: [],
			settings: BlockTypes.defaultSettings()
		};
	}

	/** A document reduced to plain data: primitives, arrays and objects only. */
	static function plainProject(project:BlockProject):Dynamic
	{
		var stacks:Array<Dynamic> = [];
		if (project.stacks != null)
		{
			for (stack in project.stacks)
			{
				if (isObject(stack))
					stacks.push(stack);
			}
		}

		var timeline:Array<Dynamic> = [];
		if (project.timeline != null)
		{
			for (entry in project.timeline)
			{
				if (entry == null)
					continue;

				var marker:Dynamic = markerToData(entry.marker);
				if (marker == null)
					continue;

				timeline.push({marker: marker, stack: isObject(entry.stack) ? entry.stack : null});
			}
		}

		return {
			version: projectVersion(project.version),
			stacks: stacks,
			timeline: timeline,
			settings: settingsToData(project.settings)
		};
	}

	static function parseProject(raw:Dynamic):Null<BlockProject>
	{
		if (!isObject(raw))
			return null;

		var stacksData:Dynamic = readField(raw, 'stacks');
		var timelineData:Dynamic = readField(raw, 'timeline');
		var settingsData:Dynamic = readField(raw, 'settings');
		if (stacksData == null && timelineData == null && settingsData == null && readField(raw, 'version') == null)
			return null;

		var stacks:Array<Dynamic> = [];
		var stackList:Array<Dynamic> = readArray(stacksData);
		if (stackList != null)
		{
			for (stack in stackList)
			{
				if (isObject(stack))
					stacks.push(stack);
			}
		}

		var timeline:Array<TimelineEntry> = [];
		var entryList:Array<Dynamic> = readArray(timelineData);
		if (entryList != null)
		{
			for (entry in entryList)
			{
				if (!isObject(entry))
					continue;

				var marker:TimelineMarker = parseMarker(readField(entry, 'marker'));
				if (marker == null)
					continue;

				var stack:Dynamic = readField(entry, 'stack');
				timeline.push({marker: marker, stack: isObject(stack) ? stack : null});
			}
		}

		return {
			version: projectVersion(readField(raw, 'version')),
			stacks: stacks,
			timeline: timeline,
			settings: parseSettings(settingsData)
		};
	}

	static function projectVersion(raw:Dynamic):Int
	{
		var version:Int = readInt(raw, BlockTypes.PROJECT_VERSION);
		return version < 1 ? BlockTypes.PROJECT_VERSION : version;
	}

	// --- Markers and settings ---

	static function parseMarker(raw:Dynamic):Null<TimelineMarker>
	{
		if (!isObject(raw))
			return null;

		var step:Int = readInt(readField(raw, 'step'), 0);
		if (step < 0)
			step = 0;

		var id:String = readString(readField(raw, 'id'), '');
		if (id.length == 0)
			id = 'marker_' + step;

		var marker:TimelineMarker = {
			id: id,
			step: step,
			time: Math.max(0, readFloat(readField(raw, 'time'), 0)),
			name: readString(readField(raw, 'name'), '')
		};

		var eventName:String = readString(readField(raw, 'eventName'), '');
		if (eventName.length > 0)
			marker.eventName = eventName;

		var color:Dynamic = readField(raw, 'color');
		if (color != null)
			marker.color = readInt(color, 0);

		var locked:Dynamic = readField(raw, 'locked');
		if (locked != null)
			marker.locked = readBool(locked, false);

		return marker;
	}

	static function markerToData(marker:TimelineMarker):Dynamic
	{
		if (marker == null)
			return null;

		var data:Dynamic = {
			id: readString(marker.id, ''),
			step: readInt(marker.step, 0),
			time: readFloat(marker.time, 0),
			name: readString(marker.name, '')
		};

		var eventName:String = readString(Reflect.field(marker, 'eventName'), '');
		if (eventName.length > 0)
			data.eventName = eventName;

		if (Reflect.hasField(marker, 'color'))
			data.color = readInt(Reflect.field(marker, 'color'), 0);

		if (Reflect.hasField(marker, 'locked'))
			data.locked = readBool(Reflect.field(marker, 'locked'), false);

		return data;
	}

	/** A marker as a snapshot, so the cached copy does not follow the live one. */
	static function cloneMarker(marker:TimelineMarker):Null<TimelineMarker>
	{
		return parseMarker(markerToData(marker));
	}

	static function parseSettings(raw:Dynamic):BlockCodeEditorSettings
	{
		var defaults:BlockCodeEditorSettings = BlockTypes.defaultSettings();
		if (!isObject(raw))
			return defaults;

		return {
			scriptName: readString(readField(raw, 'scriptName'), defaults.scriptName),
			savePath: readString(readField(raw, 'savePath'), defaults.savePath),
			execMode: normalizeExecMode(readString(readField(raw, 'execMode'), defaults.execMode)),
			customExecPath: readString(readField(raw, 'customExecPath'), defaults.customExecPath),
			autoReload: readBool(readField(raw, 'autoReload'), defaults.autoReload),
			forceVirtualKeyboard: readBool(readField(raw, 'forceVirtualKeyboard'), defaults.forceVirtualKeyboard),
			zoom: clampZoom(readFloat(readField(raw, 'zoom'), defaults.zoom))
		};
	}

	static function settingsToData(s:BlockCodeEditorSettings):Dynamic
	{
		var defaults:BlockCodeEditorSettings = BlockTypes.defaultSettings();
		var settings:BlockCodeEditorSettings = (s == null) ? defaults : s;

		return {
			scriptName: readString(settings.scriptName, defaults.scriptName),
			savePath: readString(settings.savePath, defaults.savePath),
			execMode: normalizeExecMode(settings.execMode),
			customExecPath: readString(settings.customExecPath, ''),
			autoReload: readBool(settings.autoReload, defaults.autoReload),
			forceVirtualKeyboard: readBool(settings.forceVirtualKeyboard, defaults.forceVirtualKeyboard),
			zoom: clampZoom(settings.zoom)
		};
	}

	/** A settings snapshot, so the cached copy does not follow the live one. */
	static function cloneSettings(s:BlockCodeEditorSettings):BlockCodeEditorSettings
	{
		return parseSettings(settingsToData(s));
	}

	static function normalizeExecMode(mode:String):String
	{
		switch (mode)
		{
			case 'song', 'global', 'custom':
				return mode;
			default:
				return BlockTypes.defaultSettings().execMode;
		}
	}

	static function clampZoom(zoom:Float):Float
	{
		if (!Math.isFinite(zoom))
			return BlockTypes.defaultSettings().zoom;

		return Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, zoom));
	}

	// --- Saves ---

	/**
	 * The `blockcodeEditor` save, or null when the platform has no usable storage.
	 * The FlxSave is bound once and kept: the editor reads it on every open.
	 */
	static function cache():Null<FlxSave>
	{
		if (_cache == null)
		{
			try
			{
				var bound:FlxSave = new FlxSave();
				bound.bind(CACHE_NAME, CACHE_PATH);
				_cache = bound;
			}
			catch (e:Dynamic)
			{
				return null;
			}
		}

		return (_cache.data == null) ? null : _cache;
	}

	/** `BlockCodeEditorState`'s save; bound only while there is something to migrate. */
	static function legacyCache():Null<FlxSave>
	{
		if (_legacyCache == null)
		{
			try
			{
				var bound:FlxSave = new FlxSave();
				bound.bind(LEGACY_CACHE_NAME, CACHE_PATH);
				_legacyCache = bound;
			}
			catch (e:Dynamic)
			{
				return null;
			}
		}

		return (_legacyCache.data == null) ? null : _legacyCache;
	}

	/**
	 * Copies the stacks `BlockCodeEditorState` left behind into the current cache, once.
	 * The old save is left untouched, so the legacy editor keeps working.
	 */
	static function migrateLegacy(stored:FlxSave):Null<BlockProject>
	{
		var legacy:FlxSave = legacyCache();
		if (legacy == null)
			return null;

		var blocks:Array<Dynamic> = readArray(readField(legacy.data, 'blocks'));
		if (blocks == null || blocks.length == 0)
			return null;

		var stacks:Array<Dynamic> = [];
		for (block in blocks)
		{
			if (isObject(block))
				stacks.push(block);
		}

		if (stacks.length == 0)
			return null;

		var migrated:BlockProject = emptyProject();
		migrated.stacks = stacks;

		var data:Dynamic = stored.data;
		if (data != null)
		{
			data.project = plainProject(migrated);
			data.migrated = true;
			flush(stored);
		}

		return migrated;
	}

	static function flush(stored:FlxSave):Void
	{
		try
		{
			stored.flush();
		}
		catch (e:Dynamic)
		{
			// out of storage or a platform that refuses to write: the in-memory cache is kept
		}
	}

	// --- Value readers ---

	static function isPrimitive(value:Dynamic):Bool
	{
		return Std.isOfType(value, String) || Std.isOfType(value, Bool) || Std.isOfType(value, Int) || Std.isOfType(value, Float);
	}

	/** True for the objects and arrays a serialized node is built from. */
	static function isObject(value:Dynamic):Bool
	{
		return value != null && !isPrimitive(value) && !Std.isOfType(value, Array);
	}

	static function readField(data:Dynamic, name:String):Dynamic
	{
		if (!isObject(data))
			return null;

		return Reflect.field(data, name);
	}

	static function readArray(value:Dynamic):Array<Dynamic>
	{
		if (value == null || !Std.isOfType(value, Array))
			return null;

		var list:Array<Dynamic> = cast value;
		return list;
	}

	static function readString(value:Dynamic, def:String):String
	{
		if (value == null)
			return def;

		if (Std.isOfType(value, String))
		{
			var text:String = value;
			return text;
		}

		return isPrimitive(value) ? Std.string(value) : def;
	}

	static function readFloat(value:Dynamic, def:Float):Float
	{
		if (Std.isOfType(value, Bool))
		{
			var flag:Bool = value;
			return flag ? 1 : 0;
		}

		if (Std.isOfType(value, Int))
		{
			var number:Int = value;
			return number * 1.0;
		}

		if (Std.isOfType(value, Float))
		{
			var number:Float = value;
			return Math.isFinite(number) ? number : def;
		}

		if (Std.isOfType(value, String))
		{
			var text:String = value;
			var parsed:Float = Std.parseFloat(text.trim());
			return Math.isFinite(parsed) ? parsed : def;
		}

		return def;
	}

	static function readInt(value:Dynamic, def:Int):Int
	{
		if (Std.isOfType(value, Bool))
		{
			var flag:Bool = value;
			return flag ? 1 : 0;
		}

		if (Std.isOfType(value, Int))
		{
			var number:Int = value;
			return number;
		}

		if (Std.isOfType(value, Float))
		{
			var number:Float = value;
			return Math.isFinite(number) ? Std.int(number) : def;
		}

		if (Std.isOfType(value, String))
		{
			var text:String = value;
			var parsed:Null<Int> = Std.parseInt(text.trim());
			return parsed == null ? def : parsed;
		}

		return def;
	}

	static function readBool(value:Dynamic, def:Bool):Bool
	{
		if (Std.isOfType(value, Bool))
		{
			var flag:Bool = value;
			return flag;
		}

		if (Std.isOfType(value, Int))
		{
			var number:Int = value;
			return number != 0;
		}

		if (Std.isOfType(value, Float))
		{
			var number:Float = value;
			return number != 0;
		}

		if (Std.isOfType(value, String))
		{
			var text:String = value;
			var flag:String = text.trim().toLowerCase();
			if (flag == 'true' || flag == '1' || flag == 'yes')
				return true;
			if (flag == 'false' || flag == '0' || flag == 'no')
				return false;
		}

		return def;
	}
}

/** Serialized node: the shape `serializeStack` writes and `deserializeStack` reads. */
private typedef BlockNode =
{
	var type:String;
	var x:Float;
	var y:Float;
	var inputs:Array<Dynamic>;
	var next:Dynamic;
}
