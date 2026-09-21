package editors.blockcode;

/**
 * Shared data contract for the block-code editor (substate edition).
 *
 * Every module in `editors.blockcode` codes against these typedefs, so the
 * substate, the canvas, the serializer, the Lua generator/importer and the
 * external config loader can be developed independently.
 *
 * DO NOT change the field names or the signatures documented here without
 * updating every consumer.
 */
/** Value kinds a block parameter can hold. Also drives which inline editor the canvas opens. */
enum abstract ParamType(String) from String to String
{
	/** Single line text, inline box. */
	var STRING = "string";

	/** Number, inline box with numeric filtering. */
	var NUMBER = "number";

	/** true / false, inline box. */
	var BOOL = "bool";

	/** Raw Lua code, multiline panel + soft keyboard. */
	var CODE = "code";

	/** Hex color (RRGGBB / AARRGGBB), inline box. */
	var COLOR = "color";

	/** One of `options`, cycles on tap. */
	var SELECT = "select";
}

typedef BlockParameter =
{
	var name:String;
	var type:ParamType;
	var defaultValue:Dynamic;

	/** Allowed values when `type == SELECT`. */
	@:optional var options:Array<String>;

	@:optional var description:String;
}

typedef BlockData =
{
	/** Unique id, e.g. "makeLuaSprite" or an external "myMod.spawnRing". */
	var type:String;

	/** Text drawn on the block. */
	var label:String;

	var color:Int;

	/** Category name this block is listed under. */
	var category:String;

	@:optional var parameters:Array<BlockParameter>;

	/** Reporter (returns a value) instead of a stack block. */
	@:optional var isReporter:Bool;

	@:optional var description:String;

	/** Hat block: starts a `function` in the generated script. */
	@:optional var isHat:Bool;

	/** Literal Lua emitted for hat blocks, e.g. `function onCreate()`. */
	@:optional var hatLua:String;

	/**
	 * Codegen template for statement/expression blocks that have no hardcoded
	 * generator case. `$1`, `$2`... are replaced by the (already quoted/raw)
	 * arguments in order; `${name}` is replaced by the argument of the
	 * parameter called `name`. Example: `setProperty('health', $1)`.
	 */
	@:optional var lua:String;

	/** True when the block came from an external JSON/Lua config, not from BlockLibrary defaults. */
	@:optional var external:Bool;

	/** File (`mods/.../blocks.json`, `.../blocks.lua`) the block was read from. */
	@:optional var source:String;
}

typedef BlockCategory =
{
	var name:String;
	var color:Int;

	/** Single character/glyph shown on the toolbar button. */
	var icon:String;

	var blocks:Array<BlockData>;
	@:optional var external:Bool;
}

/** A time position on the song timeline: the script attached to it runs when the song reaches it. */
typedef TimelineMarker =
{
	var id:String;

	/** Absolute step in the song (0-based, `Conductor` step grid). */
	var step:Int;

	/** Cached milliseconds matching `step`, for drawing before the song data is ready. */
	var time:Float;

	/** Display name (free text). */
	var name:String;

	/**
	 * Optional chart event name. When set, the attached stack also runs on
	 * `onEvent`/matching chart event instead of only on the step guard.
	 */
	@:optional var eventName:String;

	@:optional var color:Int;

	/** Markers imported from a file/cache are locked (still draggable unless `locked`). */
	@:optional var locked:Bool;
}

/** One timeline entry: a marker plus the root of the block stack placed on it. */
typedef TimelineEntry =
{
	var marker:TimelineMarker;

	/** Serialized block tree (`BlockSerializer.serializeStack` output), null when empty. */
	var stack:Dynamic;
}

typedef BlockCodeEditorSettings =
{
	/** File name without extension used when saving. */
	var scriptName:String;

	/** Directory (relative to the game dir or absolute) the script is written to. */
	var savePath:String;

	/** 'song' = current song script, 'global' = mods/<mod>/scripts, 'custom' = `customExecPath`. */
	var execMode:String;

	var customExecPath:String;

	/** Hot-reload the script in the running PlayState after every save. */
	var autoReload:Bool;

	/** Show the in-game touch keyboard even when a native IME is available. */
	var forceVirtualKeyboard:Bool;

	var zoom:Float;
}

/** Full editor document (what gets cached and what an import produces). */
typedef BlockProject =
{
	var version:Int;

	/** Serialized root stacks of the "global" workspace (hat scripts and free blocks). */
	var stacks:Array<Dynamic>;

	var timeline:Array<TimelineEntry>;
	var settings:BlockCodeEditorSettings;
}

/** Result of converting Lua source back into blocks. */
typedef ImportResult =
{
	var stacks:Array<Dynamic>;
	var timeline:Array<TimelineEntry>;
	var settings:BlockCodeEditorSettings;

	/** Human readable notes about anything that could not be represented as blocks. */
	var warnings:Array<String>;
}

class BlockTypes
{
	public static inline var PROJECT_VERSION:Int = 1;
	public static inline var DEFAULT_SCRIPT_NAME:String = "blockcode";

	public static function defaultSettings():BlockCodeEditorSettings
	{
		return {
			scriptName: DEFAULT_SCRIPT_NAME,
			savePath: "mods/blockcode/scripts",
			execMode: "song",
			customExecPath: "",
			autoReload: true,
			forceVirtualKeyboard: false,
			zoom: 1
		};
	}
}
