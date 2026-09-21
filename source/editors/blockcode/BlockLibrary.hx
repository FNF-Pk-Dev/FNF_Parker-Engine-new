package editors.blockcode;

import editors.blockcode.BlockTypes.BlockCategory;
import editors.blockcode.BlockTypes.BlockData;
import editors.blockcode.BlockTypes.ParamType;

/**
 * Single source of truth for the block catalogue of the block-code editor.
 *
 * The nine default categories mirror `editors.BlockCodeEditorState.initCategories()`
 * one to one (same names, colours, icons, types, labels, descriptions, parameters
 * and reporter flags), plus the hat metadata the Lua generator needs, the `Lua`
 * category of free-form code blocks and the two Control blocks the generator
 * special-cases.
 *
 * External mod blocks are merged on top of the defaults by `ensureLoaded()` and
 * `reload()` through `BlockConfigLoader.loadAll()`. Blocks/categories that come
 * from a config keep their `external` flag so the sidebar can mark them.
 */
class BlockLibrary
{
	/** Every category in toolbar order. Never null: the defaults are built while the class loads. */
	public static var categories(default, null):Array<BlockCategory> = buildDefaultCategories();

	/** Category used when a block is registered without one. */
	static inline var FALLBACK_CATEGORY:String = "Custom";

	/** True once the external configs have been merged into `categories`. */
	static var _loaded:Bool = false;

	/** Builds the defaults once, then merges the external configs on top of them. */
	public static function ensureLoaded():Void
	{
		if (_loaded)
			return;

		_loaded = true;
		mergeExternalConfigs();
	}

	/** Rebuilds the defaults and re-merges the external configs. Safe to call at runtime, e.g. after a mod reload. */
	public static function reload():Void
	{
		_loaded = true;
		categories = buildDefaultCategories();
		mergeExternalConfigs();
	}

	/** The block with this type, or null when nothing defines it. */
	public static function get(type:String):Null<BlockData>
	{
		ensureLoaded();
		if (type == null)
			return null;

		for (cat in categories)
		{
			for (block in cat.blocks)
			{
				if (block.type == type)
					return block;
			}
		}

		return null;
	}

	/** True when the block opens a Lua `function` block (the Event blocks). */
	public static function isHat(type:String):Bool
	{
		var data:BlockData = get(type);
		return data != null && data.isHat == true;
	}

	/** Every registered block, in category order. */
	public static function allBlocks():Array<BlockData>
	{
		ensureLoaded();

		var all:Array<BlockData> = [];
		for (cat in categories)
		{
			for (block in cat.blocks)
			{
				all.push(block);
			}
		}

		return all;
	}

	/** Appends a category, or merges it into the existing category with the same name. */
	public static function registerCategory(cat:BlockCategory):Void
	{
		ensureLoaded();
		if (cat == null)
			return;

		var existing:BlockCategory = findCategory(cat.name);
		if (existing == null)
		{
			categories.push(cat);
			return;
		}

		// Same name: keep the built-in colour and icon, only merge the blocks in.
		if (cat.external == true)
			existing.external = true;

		if (cat.blocks == null)
			return;

		for (block in cat.blocks.copy())
		{
			registerBlock(block, existing.name);
		}
	}

	/** Adds a block and files it under `categoryName` (its own category when omitted), creating the category when missing. */
	public static function registerBlock(data:BlockData, ?categoryName:String):Void
	{
		ensureLoaded();
		if (data == null)
			return;

		var catName:String = categoryName;
		if (catName == null || catName.length == 0)
			catName = data.category;
		if (catName == null || catName.length == 0)
			catName = FALLBACK_CATEGORY;

		// A type has to stay unique, so re-registering one replaces the previous definition.
		removeBlockType(data.type);
		data.category = catName;

		var cat:BlockCategory = findCategory(catName);
		if (cat == null)
		{
			cat = {
				name: catName,
				color: data.color,
				icon: defaultIcon(catName),
				blocks: [],
				external: data.external == true
			};
			categories.push(cat);
		}

		cat.blocks.push(data);
	}

	/** Category names in toolbar order. */
	public static function categoryNames():Array<String>
	{
		ensureLoaded();

		var names:Array<String> = [];
		for (cat in categories)
		{
			names.push(cat.name);
		}

		return names;
	}

	static function findCategory(name:String):BlockCategory
	{
		if (name == null)
			return null;

		for (cat in categories)
		{
			if (cat.name == name)
				return cat;
		}

		return null;
	}

	static function removeBlockType(type:String):Void
	{
		if (type == null)
			return;

		for (cat in categories)
		{
			var i:Int = cat.blocks.length - 1;
			while (i >= 0)
			{
				if (cat.blocks[i].type == type)
					cat.blocks.splice(i, 1);
				i--;
			}
		}
	}

	/** Toolbar glyph for a category created at runtime: its first letter. */
	static function defaultIcon(name:String):String
	{
		if (name == null || name.length == 0)
			return "?";

		return name.charAt(0).toUpperCase();
	}

	/**
	 * Merges `BlockConfigLoader.loadAll()` into the catalogue. A list of
	 * categories and a flat list of blocks are both accepted, so a config can
	 * either add a whole category or drop single blocks into existing ones.
	 */
	static function mergeExternalConfigs():Void
	{
		try
		{
			var loaded:Dynamic = BlockConfigLoader.loadAll();
			if (loaded == null)
				return;

			if (!Std.isOfType(loaded, Array))
			{
				trace("BlockLibrary: external block config was not a list, ignoring it.");
				return;
			}

			for (entry in (cast loaded : Array<Dynamic>))
			{
				if (entry == null)
					continue;

				var blocks:Dynamic = Reflect.field(entry, "blocks");
				if (blocks != null && Std.isOfType(blocks, Array))
					registerCategory(cast entry);
				else
					registerBlock(cast entry);
			}
		}
		catch (e:Dynamic)
		{
			trace("BlockLibrary: could not merge external block configs: " + Std.string(e));
		}
	}

	static function buildDefaultCategories():Array<BlockCategory>
	{
		return [
			{
				name: "Events",
				color: 0xFFFFBF00,
				icon: "⚡",
				blocks: [
					{
						type: "onCreate",
						label: "onCreate",
						color: 0xFFFFBF00,
						category: "Events",
						description: "Runs when the script starts.",
						isHat: true,
						hatLua: "function onCreate()"
					},
					{
						type: "onCreatePost",
						label: "onCreatePost",
						color: 0xFFFFBF00,
						category: "Events",
						description: "Runs after the game objects are created.",
						isHat: true,
						hatLua: "function onCreatePost()"
					},
					{
						type: "onUpdate",
						label: "onUpdate",
						color: 0xFFFFBF00,
						category: "Events",
						description: "Runs every frame.",
						isHat: true,
						hatLua: "function onUpdate(elapsed)"
					},
					{
						type: "onUpdatePost",
						label: "onUpdatePost",
						color: 0xFFFFBF00,
						category: "Events",
						description: "Runs every frame after game logic.",
						isHat: true,
						hatLua: "function onUpdatePost(elapsed)"
					},
					{
						type: "onBeatHit",
						label: "onBeatHit",
						color: 0xFFFFBF00,
						category: "Events",
						description: "Runs every beat of the song.",
						isHat: true,
						hatLua: "function onBeatHit()"
					},
					{
						type: "onStepHit",
						label: "onStepHit",
						color: 0xFFFFBF00,
						category: "Events",
						description: "Runs every step (1/4 beat) of the song.",
						isHat: true,
						hatLua: "function onStepHit()"
					},
					{
						type: "onDestroy",
						label: "onDestroy",
						color: 0xFFFFBF00,
						category: "Events",
						description: "Runs when the script is closed or game ends.",
						isHat: true,
						hatLua: "function onDestroy()"
					},
					{
						type: "onEvent",
						label: "onEvent",
						color: 0xFFFFBF00,
						category: "Events",
						description: "Runs when a chart event is triggered.",
						isHat: true,
						hatLua: "function onEvent(n, v1, v2)",
						parameters: [
							{
								name: "n",
								type: ParamType.STRING,
								defaultValue: "name"
							},
							{name: "v1", type: ParamType.STRING, defaultValue: "val1"},
							{name: "v2", type: ParamType.STRING, defaultValue: "val2"}
						]
					}
				]
			},
			{
				name: "Control",
				color: 0xFFFFAB19,
				icon: "🔄",
				blocks: [
					{
						type: "if",
						label: "if",
						color: 0xFFFFAB19,
						category: "Control",
						description: "Runs code inside if the condition is true.",
						parameters: [{name: "condition", type: ParamType.STRING, defaultValue: "true"}]
					},
					{
						type: "elseif",
						label: "else if",
						color: 0xFFFFAB19,
						category: "Control",
						description: "Runs if previous conditions failed and this one is true.",
						parameters: [
							{
								name: "condition",
								type: ParamType.STRING,
								defaultValue: "true"
							}
						]
					},
					{
						type: "else",
						label: "else",
						color: 0xFFFFAB19,
						category: "Control",
						description: "Runs if all previous conditions failed."
					},
					{
						type: "end",
						label: "end",
						color: 0xFFFFAB19,
						category: "Control",
						description: "Ends an if statement or function."
					},
					{
						type: "whileTrue",
						label: "repeat forever",
						color: 0xFFFFAB19,
						category: "Control",
						description: "Repeats the blocks under it on every frame until the loop is broken."
					},
					{
						type: "breakLoop",
						label: "break",
						color: 0xFFFFAB19,
						category: "Control",
						description: "Leaves the repeat forever loop right away.",
						lua: "break"
					},
					{
						type: "wait",
						label: "wait",
						color: 0xFFFFAB19,
						category: "Control",
						description: "Waits for a number of seconds.",
						parameters: [{name: "seconds", type: ParamType.NUMBER, defaultValue: 1.0}]
					},
					{
						type: "debugPrint",
						label: "debugPrint",
						color: 0xFFFFAB19,
						category: "Control",
						description: "Prints text to the debug console.",
						parameters: [
							{
								name: "text",
								type: ParamType.STRING,
								defaultValue: "hello"
							}
						]
					},
					{
						type: "close",
						label: "close script",
						color: 0xFFFFAB19,
						category: "Control",
						description: "Stops this script."
					}
				]
			},
			{
				name: "Operators",
				color: 0xFF59C059,
				icon: "➕",
				blocks: [
					{
						type: "add",
						label: "+",
						color: 0xFF59C059,
						category: "Operators",
						description: "Adds two numbers.",
						isReporter: true,
						parameters: [
							{name: "a", type: ParamType.NUMBER, defaultValue: 0},
							{name: "b", type: ParamType.NUMBER, defaultValue: 0}
						]
					},
					{
						type: "sub",
						label: "-",
						color: 0xFF59C059,
						category: "Operators",
						description: "Subtracts two numbers.",
						isReporter: true,
						parameters: [
							{name: "a", type: ParamType.NUMBER, defaultValue: 0},
							{name: "b", type: ParamType.NUMBER, defaultValue: 0}
						]
					},
					{
						type: "mul",
						label: "*",
						color: 0xFF59C059,
						category: "Operators",
						description: "Multiplies two numbers.",
						isReporter: true,
						parameters: [
							{name: "a", type: ParamType.NUMBER, defaultValue: 0},
							{name: "b", type: ParamType.NUMBER, defaultValue: 0}
						]
					},
					{
						type: "div",
						label: "/",
						color: 0xFF59C059,
						category: "Operators",
						description: "Divides two numbers.",
						isReporter: true,
						parameters: [
							{name: "a", type: ParamType.NUMBER, defaultValue: 0},
							{name: "b", type: ParamType.NUMBER, defaultValue: 0}
						]
					},
					{
						type: "eq",
						label: "=",
						color: 0xFF59C059,
						category: "Operators",
						description: "Checks if two values are equal.",
						isReporter: true,
						parameters: [
							{
								name: "a",
								type: ParamType.STRING,
								defaultValue: ""
							},
							{name: "b", type: ParamType.STRING, defaultValue: ""}
						]
					},
					{
						type: "gt",
						label: ">",
						color: 0xFF59C059,
						category: "Operators",
						description: "Checks if first number is greater than second.",
						isReporter: true,
						parameters: [
							{
								name: "a",
								type: ParamType.NUMBER,
								defaultValue: 0
							},
							{name: "b", type: ParamType.NUMBER, defaultValue: 0}
						]
					},
					{
						type: "lt",
						label: "<",
						color: 0xFF59C059,
						category: "Operators",
						description: "Checks if first number is less than second.",
						isReporter: true,
						parameters: [
							{
								name: "a",
								type: ParamType.NUMBER,
								defaultValue: 0
							},
							{name: "b", type: ParamType.NUMBER, defaultValue: 0}
						]
					},
					{
						type: "and",
						label: "and",
						color: 0xFF59C059,
						category: "Operators",
						description: "Returns true if both are true.",
						isReporter: true,
						parameters: [
							{
								name: "a",
								type: ParamType.STRING,
								defaultValue: "true"
							},
							{name: "b", type: ParamType.STRING, defaultValue: "true"}
						]
					},
					{
						type: "or",
						label: "or",
						color: 0xFF59C059,
						category: "Operators",
						description: "Returns true if at least one is true.",
						isReporter: true,
						parameters: [
							{
								name: "a",
								type: ParamType.STRING,
								defaultValue: "true"
							},
							{name: "b", type: ParamType.STRING, defaultValue: "true"}
						]
					},
					{
						type: "not",
						label: "not",
						color: 0xFF59C059,
						category: "Operators",
						description: "Inverts true/false.",
						isReporter: true,
						parameters: [{name: "a", type: ParamType.STRING, defaultValue: "true"}]
					},
					{
						type: "join",
						label: "join",
						color: 0xFF59C059,
						category: "Operators",
						description: "Joins two strings together.",
						isReporter: true,
						parameters: [
							{
								name: "a",
								type: ParamType.STRING,
								defaultValue: "hello"
							},
							{name: "b", type: ParamType.STRING, defaultValue: "world"}
						]
					}
				]
			},
			{
				name: "Sensing",
				color: 0xFF4CBFE6,
				icon: "🔍",
				blocks: [
					{
						type: "keyJustPressed",
						label: "keyJustPressed",
						color: 0xFF4CBFE6,
						category: "Sensing",
						description: "True if key was just pressed this frame.",
						isReporter: true,
						parameters: [
							{
								name: "key",
								type: ParamType.STRING,
								defaultValue: "space"
							}
						]
					},
					{
						type: "keyPressed",
						label: "keyPressed",
						color: 0xFF4CBFE6,
						category: "Sensing",
						description: "True if key is currently held down.",
						isReporter: true,
						parameters: [
							{
								name: "key",
								type: ParamType.STRING,
								defaultValue: "space"
							}
						]
					},
					{
						type: "curStep",
						label: "curStep",
						color: 0xFF4CBFE6,
						category: "Sensing",
						description: "Current step of the song.",
						isReporter: true
					},
					{
						type: "curBeat",
						label: "curBeat",
						color: 0xFF4CBFE6,
						category: "Sensing",
						description: "Current beat of the song.",
						isReporter: true
					},
					{
						type: "songPosition",
						label: "songPosition",
						color: 0xFF4CBFE6,
						category: "Sensing",
						description: "Current position in milliseconds.",
						isReporter: true
					},
					{
						type: "health",
						label: "health",
						color: 0xFF4CBFE6,
						category: "Sensing",
						description: "Current health (0-2).",
						isReporter: true
					},
					{
						type: "getPixelColor",
						label: "getPixelColor",
						color: 0xFF4CBFE6,
						category: "Sensing",
						description: "Gets color of a pixel on an object.",
						isReporter: true,
						parameters: [
							{
								name: "obj",
								type: ParamType.STRING,
								defaultValue: "boyfriend"
							},
							{name: "x", type: ParamType.NUMBER, defaultValue: 0},
							{name: "y", type: ParamType.NUMBER, defaultValue: 0}
						]
					}
				]
			},
			{
				name: "Looks",
				color: 0xFF9966FF,
				icon: "👁️",
				blocks: [
					{
						type: "setProperty",
						label: "setProperty",
						color: 0xFF9966FF,
						category: "Looks",
						description: "Sets a property of an object.",
						parameters: [
							{name: "tag", type: ParamType.STRING, defaultValue: "tag"},
							{name: "val", type: ParamType.STRING, defaultValue: "value"}
						]
					},
					{
						type: "getProperty",
						label: "getProperty",
						color: 0xFF9966FF,
						category: "Looks",
						description: "Gets a property of an object.",
						isReporter: true,
						parameters: [
							{
								name: "tag",
								type: ParamType.STRING,
								defaultValue: "tag"
							}
						]
					},
					{
						type: "makeLuaSprite",
						label: "makeLuaSprite",
						color: 0xFF9966FF,
						category: "Looks",
						description: "Creates a new sprite.",
						parameters: [
							{name: "tag", type: ParamType.STRING, defaultValue: "sprite"},
							{name: "image", type: ParamType.STRING, defaultValue: "image"},
							{name: "x", type: ParamType.NUMBER, defaultValue: 0},
							{name: "y", type: ParamType.NUMBER, defaultValue: 0}
						]
					},
					{
						type: "makeAnimatedLuaSprite",
						label: "makeAnimatedLuaSprite",
						color: 0xFF9966FF,
						category: "Looks",
						description: "Creates a new animated sprite.",
						parameters: [
							{
								name: "tag",
								type: ParamType.STRING,
								defaultValue: "sprite"
							},
							{name: "image", type: ParamType.STRING, defaultValue: "image"},
							{name: "x", type: ParamType.NUMBER, defaultValue: 0},
							{name: "y", type: ParamType.NUMBER, defaultValue: 0}
						]
					},
					{
						type: "addLuaSprite",
						label: "addLuaSprite",
						color: 0xFF9966FF,
						category: "Looks",
						description: "Adds the sprite to the scene.",
						parameters: [
							{name: "tag", type: ParamType.STRING, defaultValue: "sprite"},
							{name: "front", type: ParamType.STRING, defaultValue: "false"}
						]
					},
					{
						type: "scaleObject",
						label: "scaleObject",
						color: 0xFF9966FF,
						category: "Looks",
						description: "Scales an object.",
						parameters: [
							{name: "tag", type: ParamType.STRING, defaultValue: "tag"},
							{name: "x", type: ParamType.NUMBER, defaultValue: 1},
							{name: "y", type: ParamType.NUMBER, defaultValue: 1}
						]
					},
					{
						type: "setObjectCamera",
						label: "setObjectCamera",
						color: 0xFF9966FF,
						category: "Looks",
						description: "Sets which camera an object uses.",
						parameters: [
							{
								name: "tag",
								type: ParamType.STRING,
								defaultValue: "tag"
							},
							{name: "cam", type: ParamType.STRING, defaultValue: "hud"}
						]
					},
					{
						type: "screenCenter",
						label: "screenCenter",
						color: 0xFF9966FF,
						category: "Looks",
						description: "Centers an object on screen.",
						parameters: [{name: "tag", type: ParamType.STRING, defaultValue: "tag"}]
					}
				]
			},
			{
				name: "Sound",
				color: 0xFFCF63CF,
				icon: "🎵",
				blocks: [
					{
						type: "playSound",
						label: "playSound",
						color: 0xFFCF63CF,
						category: "Sound",
						description: "Plays a sound effect.",
						parameters: [
							{name: "sound", type: ParamType.STRING, defaultValue: "scrollMenu"},
							{name: "vol", type: ParamType.NUMBER, defaultValue: 1.0}
						]
					},
					{
						type: "playMusic",
						label: "playMusic",
						color: 0xFFCF63CF,
						category: "Sound",
						description: "Plays background music.",
						parameters: [
							{name: "sound", type: ParamType.STRING, defaultValue: "music"},
							{name: "vol", type: ParamType.NUMBER, defaultValue: 1.0},
							{name: "loop", type: ParamType.STRING, defaultValue: "true"}
						]
					},
					{
						type: "pauseSound",
						label: "pauseSound",
						color: 0xFFCF63CF,
						category: "Sound",
						description: "Pauses a sound.",
						parameters: [{name: "sound", type: ParamType.STRING, defaultValue: "sound"}]
					},
					{
						type: "stopSound",
						label: "stopSound",
						color: 0xFFCF63CF,
						category: "Sound",
						description: "Stops a sound.",
						parameters: [{name: "sound", type: ParamType.STRING, defaultValue: "sound"}]
					}
				]
			},
			{
				name: "Motion",
				color: 0xFF4C97FF,
				icon: "✨",
				blocks: [
					{
						type: "doTweenX",
						label: "doTweenX",
						color: 0xFF4C97FF,
						category: "Motion",
						description: "Tweens the X position.",
						parameters: [
							{name: "tag", type: ParamType.STRING, defaultValue: "tag"},
							{name: "obj", type: ParamType.STRING, defaultValue: "obj"},
							{name: "val", type: ParamType.NUMBER, defaultValue: 100},
							{name: "dur", type: ParamType.NUMBER, defaultValue: 1},
							{name: "ease", type: ParamType.STRING, defaultValue: "linear"}
						]
					},
					{
						type: "doTweenY",
						label: "doTweenY",
						color: 0xFF4C97FF,
						category: "Motion",
						description: "Tweens the Y position.",
						parameters: [
							{name: "tag", type: ParamType.STRING, defaultValue: "tag"},
							{name: "obj", type: ParamType.STRING, defaultValue: "obj"},
							{name: "val", type: ParamType.NUMBER, defaultValue: 100},
							{name: "dur", type: ParamType.NUMBER, defaultValue: 1},
							{name: "ease", type: ParamType.STRING, defaultValue: "linear"}
						]
					},
					{
						type: "doTweenAlpha",
						label: "doTweenAlpha",
						color: 0xFF4C97FF,
						category: "Motion",
						description: "Tweens the Alpha (opacity).",
						parameters: [
							{name: "tag", type: ParamType.STRING, defaultValue: "tag"},
							{name: "obj", type: ParamType.STRING, defaultValue: "obj"},
							{name: "val", type: ParamType.NUMBER, defaultValue: 1},
							{name: "dur", type: ParamType.NUMBER, defaultValue: 1},
							{name: "ease", type: ParamType.STRING, defaultValue: "linear"}
						]
					},
					{
						type: "doTweenZoom",
						label: "doTweenZoom",
						color: 0xFF4C97FF,
						category: "Motion",
						description: "Tweens the Camera Zoom.",
						parameters: [
							{name: "tag", type: ParamType.STRING, defaultValue: "tag"},
							{name: "cam", type: ParamType.STRING, defaultValue: "game"},
							{name: "val", type: ParamType.NUMBER, defaultValue: 1},
							{name: "dur", type: ParamType.NUMBER, defaultValue: 1},
							{name: "ease", type: ParamType.STRING, defaultValue: "linear"}
						]
					}
				]
			},
			{
				name: "Game",
				color: 0xFF59C059,
				icon: "🎮",
				blocks: [
					{
						type: "setHealth",
						label: "setHealth",
						color: 0xFF59C059,
						category: "Game",
						description: "Sets the player health.",
						parameters: [{name: "val", type: ParamType.NUMBER, defaultValue: 1.0}]
					},
					{
						type: "addHealth",
						label: "addHealth",
						color: 0xFF59C059,
						category: "Game",
						description: "Adds to the player health.",
						parameters: [{name: "val", type: ParamType.NUMBER, defaultValue: 0.1}]
					},
					{
						type: "cameraShake",
						label: "cameraShake",
						color: 0xFF59C059,
						category: "Game",
						description: "Shakes the camera.",
						parameters: [
							{name: "cam", type: ParamType.STRING, defaultValue: "game"},
							{name: "int", type: ParamType.NUMBER, defaultValue: 0.05},
							{name: "dur", type: ParamType.NUMBER, defaultValue: 0.5}
						]
					},
					{
						type: "cameraFlash",
						label: "cameraFlash",
						color: 0xFF59C059,
						category: "Game",
						description: "Flashes the camera with a color.",
						parameters: [
							{name: "cam", type: ParamType.STRING, defaultValue: "game"},
							{name: "col", type: ParamType.STRING, defaultValue: "FFFFFF"},
							{name: "dur", type: ParamType.NUMBER, defaultValue: 0.5}
						]
					},
					{
						type: "cameraFade",
						label: "cameraFade",
						color: 0xFF59C059,
						category: "Game",
						description: "Fades the camera to a color.",
						parameters: [
							{name: "cam", type: ParamType.STRING, defaultValue: "game"},
							{name: "col", type: ParamType.STRING, defaultValue: "000000"},
							{name: "dur", type: ParamType.NUMBER, defaultValue: 0.5}
						]
					}
				]
			},
			{
				name: "Lua",
				color: 0xFF9F6BFF,
				icon: "~",
				blocks: [
					{
						type: "runLuaCode",
						label: "run lua code",
						color: 0xFF9F6BFF,
						category: "Lua",
						description: "Runs the Lua code you type here at this point in the script.",
						lua: "$1",
						parameters: [
							{
								name: "code",
								type: ParamType.CODE,
								defaultValue: ""
							}
						]
					},
					{
						type: "luaExpression",
						label: "lua value",
						color: 0xFF9F6BFF,
						category: "Lua",
						description: "A Lua value you type yourself, to plug into another block.",
						isReporter: true,
						lua: "$1",
						parameters: [
							{
								name: "code",
								type: ParamType.CODE,
								defaultValue: ""
							}
						]
					},
					{
						type: "commentLine",
						label: "comment",
						color: 0xFF9F6BFF,
						category: "Lua",
						description: "A note for humans; the game ignores it while the song plays.",
						lua: "-- $1",
						parameters: [
							{
								name: "text",
								type: ParamType.STRING,
								defaultValue: "todo"
							}
						]
					},
					{
						type: "callFunction",
						label: "call",
						color: 0xFF9F6BFF,
						category: "Lua",
						description: "Calls a Lua function with the arguments you give.",
						lua: "$1($2)",
						parameters: [
							{
								name: "func",
								type: ParamType.STRING,
								defaultValue: "myFunction"
							},
							{name: "args", type: ParamType.STRING, defaultValue: ""}
						]
					},
					{
						type: "setVariable",
						label: "set variable",
						color: 0xFF9F6BFF,
						category: "Lua",
						description: "Stores a value in a Lua variable so you can use it later.",
						lua: "$1 = $2",
						parameters: [
							{
								name: "name",
								type: ParamType.STRING,
								defaultValue: "myVar"
							},
							{name: "value", type: ParamType.STRING, defaultValue: "0"}
						]
					},
					{
						type: "getVariable",
						label: "get variable",
						color: 0xFF9F6BFF,
						category: "Lua",
						description: "Reads the value you stored in a Lua variable.",
						isReporter: true,
						lua: "$1",
						parameters: [
							{
								name: "name",
								type: ParamType.STRING,
								defaultValue: "myVar"
							}
						]
					}
				]
			}
		];
	}
}
