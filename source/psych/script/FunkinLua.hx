package psych.script;

import openfl.display.BitmapData;
#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
import llua.LuaRequire;
import llua.*;
#end
import animateatlas.AtlasFrameMaker;
import flixel.FlxG;
import flixel.addons.effects.FlxTrail;
import flixel.input.keyboard.FlxKey;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.text.FlxText;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxPoint;
import flixel.system.FlxSound;
import flixel.util.FlxTimer;
import flixel.FlxSprite;
// import flxgif.FlxGifSprite;
import flixel.FlxCamera;
import flixel.util.FlxColor;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxState;
import openfl.Lib;
import openfl.display.BlendMode;
import openfl.filters.BitmapFilter;
import openfl.utils.Assets;
import flixel.math.FlxMath;
import flixel.util.FlxSave;
import flixel.addons.transition.FlxTransitionableState;
import flixel.system.FlxAssets.FlxShader;
import Type.ValueType;
import haxe.Constraints;
#if (!flash && sys)
import flixel.addons.display.FlxRuntimeShader;
#end
#if sys
import sys.FileSystem;
import sys.io.File;
#end
import backend.player.Controls;
import psych.cutscenes.DialogueBoxPsych;
import backend.MusicBeatState;
#if hscript
import hscript.Parser;
import hscript.Interp;
import hscript.Expr;
#end
import modchart.*;
#if desktop
import backend.Discord;
#end
#if android
import android.Hardware;
import android.FlxNewHitbox;
import android.FlxVirtualPad;
#end

using StringTools;

typedef LuaTweenOptions =
{
	type:FlxTweenType,
	startDelay:Float,
	onUpdate:Null<String>,
	onStart:Null<String>,
	onComplete:Null<String>,
	loopDelay:Float,
	ease:EaseFunction
}

class FunkinLua extends GlobalScript
{
	public static var Function_StopLua:Dynamic = "##PSYCHLUA_FUNCTIONSTOPLUA";

	static final instanceStr:Dynamic = "##PSYCHLUA_STRINGTOOBJ";

	// public var errorHandler:String->Void;
	#if LUA_ALLOWED
	public var lua:State = null;
	#end
	public var camTarget:FlxCamera;
	public var scriptName:String = '';
	public var scriptHxLuaCode:Dynamic = '';
	public var closed:Bool = false;

	// -- "Engine Custom ES" dialect support -----------------------------------
	// Menu scripts (see LuaSState) have no PlayState.instance to store their objects in,
	// so they keep their own registries here. `menuMode` is set by LuaSState.
	public var menuMode(default, null):Bool = false;
	public var menuOwner:FlxState = null;
	public var menuSprites:Map<String, ModchartSprite> = new Map<String, ModchartSprite>();
	public var menuTexts:Map<String, ModchartText> = new Map<String, ModchartText>();
	public var menuTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	public var menuTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	public var menuSounds:Map<String, FlxSound> = new Map<String, FlxSound>();

	/** Insertion index used by add() so sprites added "behind" keep their creation order. */
	public var menuBackIndex:Int = 0;

	/** Step of the last onEventSet dispatch, used by the ES stepEvent() helper. */
	public var lastEventSetStep:Int = 0;

	/** Lua variables of menu scripts, they have no variables map of their own. */
	public static var menuVariables:Map<String, Dynamic> = new Map<String, Dynamic>();

	/** Every menu script still alive, so the static helpers below can find their registries. */
	public static var menuScripts:Array<FunkinLua> = [];

	/** State owning the menu scripts, set by LuaSState. */
	public static var currentMenuState:FlxState = null;

	// Last resort registries for the static helpers when no menu script is alive.
	static var looseSprites:Map<String, ModchartSprite> = new Map<String, ModchartSprite>();
	static var looseTexts:Map<String, ModchartText> = new Map<String, ModchartText>();
	static var looseTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	static var looseTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	static var looseSounds:Map<String, FlxSound> = new Map<String, FlxSound>();

	public static var customFunctions:Map<String, Dynamic> = new Map<String, Dynamic>();

	public static var callbacks:Map<String, Dynamic> = new Map<String, Dynamic>();

	#if hscript
	public static var hscript:HScripts = null;
	#end

	public function new(script:String, ?menuMode:Bool = false, ?owner:FlxState = null)
	{
		this.menuMode = menuMode;
		this.menuOwner = owner;

		#if LUA_ALLOWED
		lua = LuaL.newstate();
		LuaL.openlibs(lua);
		Lua_helper.register_hxtrace(lua);
		Lua.init_callbacks(lua);

		// trace('Lua version: ' + Lua.version());
		// trace("LuaJIT version: " + Lua.versionJIT());

		// LuaL.dostring(lua, CLENSE);

		try
		{
			var code:String = Paths.getContent(script);
			var status:Int = LuaL.luau_loadsource(lua, script, code);
			if (status != Lua.LUA_OK)
			{
				var resultStr:String = Lua.tostring(lua, -1);
				Lua.pop(lua, 1);
				trace('Error on lua script! ' + resultStr);
				#if (windows || android)
				CoolUtil.showPopUp(resultStr, 'Error on lua script!');
				#else
				luaTrace('Error loading lua script: "$script"\n' + resultStr, true, false, FlxColor.RED);
				#end
				Lua.close(lua);
				lua = null;
				return;
			}

			// NOTE: Script is loaded but NOT executed yet!
			// We need to register all functions first before executing the script.
		}
		catch (e:Dynamic)
		{
			trace(e);
			if (lua != null)
			{
				Lua.close(lua);
				lua = null;
			}
			return;
		}
		scriptName = script;

		// Initialize require() function BEFORE executing script
		LuaRequire.init(lua, ["./", "mods/", "scripts/", "data/"]);

		if (menuMode)
		{
			// Forget about the scripts of menu states that are already gone
			menuScripts = menuScripts.filter(menuScript -> !menuScript.closed);
			menuScripts.push(this);
			// Claim the "currently running script" slot so the static helpers below can
			// find this script's registries while its own onCreate() runs
			lastCalledScript = this;
		}

		initHaxeModule();

		trace('lua file loaded succesfully:' + script);

		// Lua shit
		set('Function_StopLua', Function_StopLua);
		set('Function_Stop', GlobalScript.Function_Stop);
		set('Function_Continue', GlobalScript.Function_Continue);
		set('luaDebugMode', false);
		set('luaDeprecatedWarnings', true);
		set('inChartEditor', false);

		// Some values only exist while a song is running (menu scripts don't have a PlayState)
		var inPlayState:Bool = PlayState.instance != null && !menuMode;
		var hasSong:Bool = PlayState.SONG != null;

		// Song/Week shit
		set('curBpm', Conductor.bpm);
		set('bpm', hasSong ? PlayState.SONG.bpm : 0);
		set('scrollSpeed', hasSong ? PlayState.SONG.speed : 1);
		set('crochet', Conductor.crochet);
		set('stepCrochet', Conductor.stepCrochet);
		set('songLength', (FlxG.sound.music != null) ? FlxG.sound.music.length : 0);
		set('songName', hasSong ? PlayState.SONG.song : '');
		set('songPath', hasSong ? Paths.formatToSongPath(PlayState.SONG.song) : '');
		set('startedCountdown', false);
		set('curStage', hasSong ? PlayState.SONG.stage : '');

		set('isStoryMode', PlayState.isStoryMode);
		set('difficulty', PlayState.storyDifficulty);

		var difficultyName:String = CoolUtil.defaultDifficulty;
		if (PlayState.storyDifficulty > -1 && PlayState.storyDifficulty < CoolUtil.difficulties.length)
			difficultyName = CoolUtil.difficulties[PlayState.storyDifficulty];
		set('difficultyName', difficultyName);
		set('difficultyPath', Paths.formatToSongPath(difficultyName));
		set('weekRaw', PlayState.storyWeek);
		set('week', (PlayState.storyWeek > -1
			&& PlayState.storyWeek < WeekData.weeksList.length) ? WeekData.weeksList[PlayState.storyWeek] : '');
		set('seenCutscene', PlayState.seenCutscene);

		// Camera poo
		set('cameraX', 0);
		set('cameraY', 0);

		// Screen stuff
		set('screenWidth', FlxG.width);
		set('screenHeight', FlxG.height);

		// PlayState cringe ass nae nae bullcrap
		set('curBeat', 0);
		set('curStep', 0);
		set('curDecBeat', 0);
		set('curDecStep', 0);

		set('score', 0);
		set('misses', 0);
		set('hits', 0);

		set('rating', 0);
		set('ratingName', '');
		set('ratingFC', '');
		set('version', MainMenuState.psychEngineVersion.trim());

		set('inGameOver', false);
		set('mustHitSection', false);
		set('altAnim', false);
		set('gfSection', false);

		// Gameplay settings
		set('healthGainMult', inPlayState ? PlayState.instance.healthGain : 1);
		set('healthLossMult', inPlayState ? PlayState.instance.healthLoss : 1);
		set('playbackRate', inPlayState ? PlayState.instance.playbackRate : 1);
		set('instakillOnMiss', inPlayState ? PlayState.instance.instakillOnMiss : false);
		set('botPlay', inPlayState ? PlayState.instance.cpuControlled : false);
		set('practice', inPlayState ? PlayState.instance.practiceMode : false);

		for (i in 0...4)
		{
			set('defaultPlayerStrumX' + i, 0);
			set('defaultPlayerStrumY' + i, 0);
			set('defaultOpponentStrumX' + i, 0);
			set('defaultOpponentStrumY' + i, 0);
		}

		// Default character positions woooo
		set('defaultBoyfriendX', inPlayState ? PlayState.instance.BF_X : 0);
		set('defaultBoyfriendY', inPlayState ? PlayState.instance.BF_Y : 0);
		set('defaultOpponentX', inPlayState ? PlayState.instance.DAD_X : 0);
		set('defaultOpponentY', inPlayState ? PlayState.instance.DAD_Y : 0);
		set('defaultGirlfriendX', inPlayState ? PlayState.instance.GF_X : 0);
		set('defaultGirlfriendY', inPlayState ? PlayState.instance.GF_Y : 0);

		// Character shit
		set('boyfriendName', hasSong ? PlayState.SONG.player1 : '');
		set('dadName', hasSong ? PlayState.SONG.player2 : '');
		set('gfName', hasSong ? PlayState.SONG.gfVersion : '');

		// Some settings, no jokes
		set('downscroll', ClientPrefs.downScroll);
		set('middlescroll', ClientPrefs.middleScroll);
		set('framerate', ClientPrefs.framerate);
		set('ghostTapping', ClientPrefs.ghostTapping);
		set('hideHud', ClientPrefs.hideHud);
		set('timeBarType', ClientPrefs.timeBarType);
		set('scoreZoom', ClientPrefs.scoreZoom);
		set('cameraZoomOnBeat', ClientPrefs.camZooms);
		set('flashingLights', ClientPrefs.flashing);
		set('noteOffset', ClientPrefs.noteOffset);
		set('healthBarAlpha', ClientPrefs.healthBarAlpha);
		set('noResetButton', ClientPrefs.noReset);
		set('lowQuality', ClientPrefs.lowQuality);
		set('shadersEnabled', ClientPrefs.shaders);
		set('scriptName', scriptName);
		set('currentModDirectory', Paths.currentModDirectory);

		#if windows
		set('buildTarget', 'windows');
		#elseif linux
		set('buildTarget', 'linux');
		#elseif mac
		set('buildTarget', 'mac');
		#elseif html5
		set('buildTarget', 'browser');
		#elseif android
		set('buildTarget', 'android');
		#else
		set('buildTarget', 'unknown');
		#end

		// custom substate
		set("openCustomSubstate", function(name:String, pauseGame:Bool = false)
		{
			if (pauseGame)
			{
				PlayState.instance.persistentUpdate = false;
				PlayState.instance.persistentDraw = true;
				PlayState.instance.paused = true;
				if (FlxG.sound.music != null)
				{
					FlxG.sound.music.pause();
					PlayState.instance.vocals.pause();
				}
			}

			PlayState.instance.openSubState(new CustomSubstate(name));
		});

		set("closeCustomSubstate", function()
		{
			if (CustomSubstate.instance != null)
			{
				PlayState.instance.closeSubState();
				CustomSubstate.instance = null;
				return true;
			}
			return false;
		});

		// shader shit
		set("initLuaShader", function(name:String)
		{
			if (!ClientPrefs.shaders)
				return false;

			#if (!flash && MODS_ALLOWED && sys)
			return initLuaShader(name);
			#else
			luaTrace("initLuaShader: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
			return false;
		});

		set("setSpriteShader", function(obj:String, shader:String)
		{
			if (!ClientPrefs.shaders)
				return false;

			#if (!flash && MODS_ALLOWED && sys)
			if (menuMode || PlayState.instance == null)
			{
				luaTrace('setSpriteShader: Runtime shaders are only available while a song is playing!', false, false, FlxColor.RED);
				return false;
			}

			if (!PlayState.instance.runtimeShaders.exists(shader) && !initLuaShader(shader))
			{
				luaTrace('setSpriteShader: Shader $shader is missing!', false, false, FlxColor.RED);
				return false;
			}

			var killMe:Array<String> = obj.split('.');
			var leObj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				leObj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (leObj != null)
			{
				var arr:Array<String> = PlayState.instance.runtimeShaders.get(shader);
				leObj.shader = new FlxRuntimeShader(arr[0], arr[1]);
				return true;
			}
			#else
			luaTrace("setSpriteShader: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
			return false;
		});
		set("removeSpriteShader", function(obj:String)
		{
			var killMe:Array<String> = obj.split('.');
			var leObj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				leObj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (leObj != null)
			{
				leObj.shader = null;
				return true;
			}
			return false;
		});

		set("getShaderBool", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				return null;
			}
			return shader.getBool(prop);
			#else
			luaTrace("getShaderBool: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});
		set("getShaderBoolArray", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				return null;
			}
			return shader.getBoolArray(prop);
			#else
			luaTrace("getShaderBoolArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});
		set("getShaderInt", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				return null;
			}
			return shader.getInt(prop);
			#else
			luaTrace("getShaderInt: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});
		set("getShaderIntArray", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				return null;
			}
			return shader.getIntArray(prop);
			#else
			luaTrace("getShaderIntArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});
		set("getShaderFloat", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				return null;
			}
			return shader.getFloat(prop);
			#else
			luaTrace("getShaderFloat: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});
		set("getShaderFloatArray", function(obj:String, prop:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
			{
				return null;
			}
			return shader.getFloatArray(prop);
			#else
			luaTrace("getShaderFloatArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			return null;
			#end
		});

		set("setShaderBool", function(obj:String, prop:String, value:Bool)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setBool(prop, value);
			#else
			luaTrace("setShaderBool: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});
		set("setShaderBoolArray", function(obj:String, prop:String, values:Dynamic)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setBoolArray(prop, values);
			#else
			luaTrace("setShaderBoolArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});
		set("setShaderInt", function(obj:String, prop:String, value:Int)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setInt(prop, value);
			#else
			luaTrace("setShaderInt: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});
		set("setShaderIntArray", function(obj:String, prop:String, values:Dynamic)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setIntArray(prop, values);
			#else
			luaTrace("setShaderIntArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});
		set("setShaderFloat", function(obj:String, prop:String, value:Float)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setFloat(prop, value);
			#else
			luaTrace("setShaderFloat: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});
		set("setShaderFloatArray", function(obj:String, prop:String, values:Dynamic)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			shader.setFloatArray(prop, values);
			#else
			luaTrace("setShaderFloatArray: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});

		set("setShaderSampler2D", function(obj:String, prop:String, bitmapdataPath:String)
		{
			#if (!flash && MODS_ALLOWED && sys)
			var shader:FlxRuntimeShader = getShader(obj);
			if (shader == null)
				return;

			// trace('bitmapdatapath: $bitmapdataPath');
			var value = Paths.image(bitmapdataPath);
			if (value != null && value.bitmap != null)
			{
				// trace('Found bitmapdata. Width: ${value.bitmap.width} Height: ${value.bitmap.height}');
				shader.setSampler2D(prop, value.bitmap);
			}
			#else
			luaTrace("setSampler2D: Platform unsupported for Runtime Shaders!", false, false, FlxColor.RED);
			#end
		});

		//
		set("getRunningScripts", function()
		{
			var runningScripts:Array<String> = [];
			for (idx in 0...PlayState.instance.luaArray.length)
				runningScripts.push(PlayState.instance.luaArray[idx].scriptName);

			return runningScripts;
		});

		set("callOnLuas", function(?funcName:String, ?args:Array<Dynamic>, ignoreStops = false, ignoreSelf = true, ?exclusions:Array<String>)
		{
			if (funcName == null)
			{
				#if (linc_luajit >= "0.0.6")
				LuaL.error(lua, "bad argument #1 to 'callOnLuas' (string expected, got nil)");
				#end
				return;
			}
			if (args == null)
				args = [];

			if (exclusions == null)
				exclusions = [];

			Lua.getglobal(lua, 'scriptName');
			var daScriptName = Lua.tostring(lua, -1);
			Lua.pop(lua, 1);
			if (ignoreSelf && !exclusions.contains(daScriptName))
				exclusions.push(daScriptName);

			if (menuMode || PlayState.instance == null)
			{
				// Menu scripts have no PlayState to broadcast through
				if (!exclusions.contains(daScriptName))
					call(funcName, args);
				return;
			}
			PlayState.instance.callOnLuas(funcName, args, ignoreStops, exclusions);
		});

		set("callScript", function(?luaFile:String, ?funcName:String, ?args:Array<Dynamic>)
		{
			if (luaFile == null)
			{
				#if (linc_luajit >= "0.0.6")
				LuaL.error(lua, "bad argument #1 to 'callScript' (string expected, got nil)");
				#end
				return;
			}
			if (funcName == null)
			{
				#if (linc_luajit >= "0.0.6")
				LuaL.error(lua, "bad argument #2 to 'callScript' (string expected, got nil)");
				#end
				return;
			}
			if (args == null)
			{
				args = [];
			}
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = SUtil.getPath() + Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end
			if (doPush)
			{
				for (luaInstance in PlayState.instance.luaArray)
				{
					if (luaInstance.scriptName == cervix)
					{
						luaInstance.call(funcName, args);

						return;
					}
				}
			}
		});

		set("getGlobalFromScript", function(?luaFile:String, ?global:String)
		{ // returns the global from a script
			if (luaFile == null)
			{
				#if (linc_luajit >= "0.0.6")
				LuaL.error(lua, "bad argument #1 to 'getGlobalFromScript' (string expected, got nil)");
				#end
				return;
			}
			if (global == null)
			{
				#if (linc_luajit >= "0.0.6")
				LuaL.error(lua, "bad argument #2 to 'getGlobalFromScript' (string expected, got nil)");
				#end
				return;
			}
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = SUtil.getPath() + Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end
			if (doPush)
			{
				for (luaInstance in PlayState.instance.luaArray)
				{
					if (luaInstance.scriptName == cervix)
					{
						Lua.getglobal(luaInstance.lua, global);
						if (Lua.isnumber(luaInstance.lua, -1))
						{
							Lua.pushnumber(lua, Lua.tonumber(luaInstance.lua, -1));
						}
						else if (Lua.isstring(luaInstance.lua, -1))
						{
							Lua.pushstring(lua, Lua.tostring(luaInstance.lua, -1));
						}
						else if (Lua.isboolean(luaInstance.lua, -1))
						{
							Lua.pushboolean(lua, Lua.toboolean(luaInstance.lua, -1));
						}
						else
						{
							Lua.pushnil(lua);
						}
						// TODO: table

						Lua.pop(luaInstance.lua, 1); // remove the global

						return;
					}
				}
			}
		});
		set("setGlobalFromScript", function(luaFile:String, global:String, val:Dynamic)
		{ // returns the global from a script
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = SUtil.getPath() + Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end
			if (doPush)
			{
				for (luaInstance in PlayState.instance.luaArray)
				{
					if (luaInstance.scriptName == cervix)
					{
						luaInstance.set(global, val);
					}
				}
			}
		});
		/*set("getGlobals", function(luaFile:String){ // returns a copy of the specified file's globals
			var cervix = luaFile + ".lua";
			if(luaFile.endsWith(".lua"))cervix=luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if(FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if(FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else {
				cervix = SUtil.getPath() + Paths.getPreloadPath(cervix);
				if(FileSystem.exists(cervix)) {
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if(Assets.exists(cervix)) {
				doPush = true;
			}
			#end
			if(doPush)
			{
				for (luaInstance in PlayState.instance.luaArray)
				{
					if(luaInstance.scriptName == cervix)
					{
						Lua.newtable(lua);
						var tableIdx = Lua.gettop(lua);

						Lua.pushvalue(luaInstance.lua, Lua.LUA_GLOBALSINDEX);
						while(Lua.next(luaInstance.lua, -2) != 0) {
							// key = -2
							// value = -1

							var pop:Int = 0;

							// Manual conversion
							// first we convert the key
							if(Lua.isnumber(luaInstance.lua,-2)){
								Lua.pushnumber(lua, Lua.tonumber(luaInstance.lua, -2));
								pop++;
							}else if(Lua.isstring(luaInstance.lua,-2)){
								Lua.pushstring(lua, Lua.tostring(luaInstance.lua, -2));
								pop++;
							}else if(Lua.isboolean(luaInstance.lua,-2)){
								Lua.pushboolean(lua, Lua.toboolean(luaInstance.lua, -2));
								pop++;
							}
							// TODO: table


							// then the value
							if(Lua.isnumber(luaInstance.lua,-1)){
								Lua.pushnumber(lua, Lua.tonumber(luaInstance.lua, -1));
								pop++;
							}else if(Lua.isstring(luaInstance.lua,-1)){
								Lua.pushstring(lua, Lua.tostring(luaInstance.lua, -1));
								pop++;
							}else if(Lua.isboolean(luaInstance.lua,-1)){
								Lua.pushboolean(lua, Lua.toboolean(luaInstance.lua, -1));
								pop++;
							}
							// TODO: table

							if(pop==2)Lua.rawset(lua, tableIdx); // then set it
							Lua.pop(luaInstance.lua, 1); // for the loop
						}
						Lua.pop(luaInstance.lua,1); // end the loop entirely
						Lua.pushvalue(lua, tableIdx); // push the table onto the stack so it gets returned

						return;
					}

				}
			}
		});*/
		set("isRunning", function(luaFile:String)
		{
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = SUtil.getPath() + Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end

			if (doPush)
			{
				for (luaInstance in PlayState.instance.luaArray)
				{
					if (luaInstance.scriptName == cervix)
						return true;
				}
			}
			return false;
		});

		set("addLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false)
		{ // would be dope asf.
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = SUtil.getPath() + Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end

			if (doPush)
			{
				if (!ignoreAlreadyRunning)
				{
					for (luaInstance in PlayState.instance.luaArray)
					{
						if (luaInstance.scriptName == cervix)
						{
							luaTrace('addLuaScript: The script "' + cervix + '" is already running!');
							return;
						}
					}
				}
				PlayState.instance.luaArray.push(new FunkinLua(cervix));
				return;
			}
			luaTrace("addLuaScript: Script doesn't exist!", false, false, FlxColor.RED);
		});
		set("removeLuaScript", function(luaFile:String, ?ignoreAlreadyRunning:Bool = false)
		{ // would be dope asf.
			var cervix = luaFile + ".lua";
			if (luaFile.endsWith(".lua"))
				cervix = luaFile;
			var doPush = false;
			#if MODS_ALLOWED
			if (FileSystem.exists(Paths.modFolders(cervix)))
			{
				cervix = Paths.modFolders(cervix);
				doPush = true;
			}
			else if (FileSystem.exists(cervix))
			{
				doPush = true;
			}
			else
			{
				cervix = SUtil.getPath() + Paths.getPreloadPath(cervix);
				if (FileSystem.exists(cervix))
				{
					doPush = true;
				}
			}
			#else
			cervix = Paths.getPreloadPath(cervix);
			if (Assets.exists(cervix))
			{
				doPush = true;
			}
			#end

			if (doPush)
			{
				if (!ignoreAlreadyRunning)
				{
					for (luaInstance in PlayState.instance.luaArray)
					{
						if (luaInstance.scriptName == cervix)
						{
							// luaTrace('The script "' + cervix + '" is already running!');

							PlayState.instance.luaArray.remove(luaInstance);
							return;
						}
					}
				}
				return;
			}
			luaTrace("removeLuaScript: Script doesn't exist!", false, false, FlxColor.RED);
		});

		set("runHaxeCode", function(codeToRun:String)
		{
			var retVal:Dynamic = null;

			#if hscript
			initHaxeModule();
			try
			{
				retVal = hscript.execute(codeToRun);
			}
			catch (e:Dynamic)
			{
				luaTrace(scriptName + ":" + lastCalledFunction + " - " + e, false, false, FlxColor.RED);
			}
			#else
			luaTrace("runHaxeCode: HScript isn't supported on this platform!", false, false, FlxColor.RED);
			#end

			if (retVal != null && !isOfTypes(retVal, [Bool, Int, Float, String, Array]))
				retVal = null;
			return retVal;
		});

		set("addHaxeLibrary", function(libName:String, ?libPackage:String = '')
		{
			#if hscript
			initHaxeModule();
			try
			{
				var str:String = '';
				if (libPackage.length > 0)
					str = libPackage + '.';

				hscript.variables.set(libName, Type.resolveClass(str + libName));
			}
			catch (e:Dynamic)
			{
				luaTrace(scriptName + ":" + lastCalledFunction + " - " + e, false, false, FlxColor.RED);
			}
			#end
		});

		set("loadSong", function(?name:String = null, ?difficultyNum:Int = -1)
		{
			if (name == null || name.length < 1)
				name = PlayState.SONG.song;
			if (difficultyNum == -1)
				difficultyNum = PlayState.storyDifficulty;

			var poop = Highscore.formatSong(name, difficultyNum);
			PlayState.SONG = Song.loadFromJson(poop, name);
			PlayState.storyDifficulty = difficultyNum;
			PlayState.instance.persistentUpdate = false;
			LoadingState.loadAndSwitchState(new PlayState());

			FlxG.sound.music.pause();
			FlxG.sound.music.volume = 0;
			if (PlayState.instance.vocals != null)
			{
				PlayState.instance.vocals.pause();
				PlayState.instance.vocals.volume = 0;
			}
		});

		set("loadGraphic", function(variable:String, image:String, ?gridX:Int = 0, ?gridY:Int = 0)
		{
			var killMe:Array<String> = variable.split('.');
			var spr:FlxSprite = getObjectDirectly(killMe[0]);
			var animated = gridX != 0 || gridY != 0;

			if (killMe.length > 1)
			{
				spr = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (spr != null && image != null && image.length > 0)
			{
				spr.loadGraphic(Paths.image(image), animated, gridX, gridY);
			}
		});
		set("loadFrames", function(variable:String, image:String, spriteType:String = "sparrow")
		{
			var killMe:Array<String> = variable.split('.');
			var spr:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				spr = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (spr != null && image != null && image.length > 0)
			{
				loadFrames(spr, image, spriteType);
			}
		});

		set("getProperty", function(variable:String)
		{
			var result:Dynamic = null;
			var killMe:Array<String> = variable.split('.');
			if (killMe.length > 1)
				result = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			else
				result = getVarInArray(getInstance(), variable);

			return result;
		});
		set("setProperty", function(variable:String, value:Dynamic)
		{
			var killMe:Array<String> = variable.split('.');
			if (killMe.length > 1)
			{
				setVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1], value);
				return true;
			}
			setVarInArray(getInstance(), variable, value);
			return true;
		});
		set("getPropertyFromGroup", function(obj:String, index:Int, variable:Dynamic)
		{
			var shitMyPants:Array<String> = obj.split('.');
			var realObject:Dynamic = Reflect.getProperty(getInstance(), obj);
			if (shitMyPants.length > 1)
				realObject = getPropertyLoopThingWhatever(shitMyPants, true, false);

			if (Std.isOfType(realObject, FlxTypedGroup))
			{
				var result:Dynamic = getGroupStuff(realObject.members[index], variable);
				return result;
			}

			var leArray:Dynamic = realObject[index];
			if (leArray != null)
			{
				var result:Dynamic = null;
				if (Type.typeof(variable) == ValueType.TInt)
					result = leArray[variable];
				else
					result = getGroupStuff(leArray, variable);

				return result;
			}
			luaTrace("getPropertyFromGroup: Object #" + index + " from group: " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return null;
		});
		set("setPropertyFromGroup", function(obj:String, index:Int, variable:Dynamic, value:Dynamic)
		{
			var shitMyPants:Array<String> = obj.split('.');
			var realObject:Dynamic = Reflect.getProperty(getInstance(), obj);
			if (shitMyPants.length > 1)
				realObject = getPropertyLoopThingWhatever(shitMyPants, true, false);

			if (Std.isOfType(realObject, FlxTypedGroup))
			{
				setGroupStuff(realObject.members[index], variable, value);
				return;
			}

			var leArray:Dynamic = realObject[index];
			if (leArray != null)
			{
				if (Type.typeof(variable) == ValueType.TInt)
				{
					leArray[variable] = value;
					return;
				}
				setGroupStuff(leArray, variable, value);
			}
		});
		set("removeFromGroup", function(obj:String, index:Int, dontDestroy:Bool = false)
		{
			if (Std.isOfType(Reflect.getProperty(getInstance(), obj), FlxTypedGroup))
			{
				var sex = Reflect.getProperty(getInstance(), obj).members[index];
				if (!dontDestroy)
					sex.kill();
				Reflect.getProperty(getInstance(), obj).remove(sex, true);
				if (!dontDestroy)
					sex.destroy();
				return;
			}
			Reflect.getProperty(getInstance(), obj).remove(Reflect.getProperty(getInstance(), obj)[index]);
		});

		set("getPropertyFromClass", function(classVar:String, variable:String)
		{
			@:privateAccess
			var killMe:Array<String> = variable.split('.');
			if (killMe.length > 1)
			{
				var coverMeInPiss:Dynamic = getVarInArray(Type.resolveClass(classVar), killMe[0]);
				for (i in 1...killMe.length - 1)
				{
					coverMeInPiss = getVarInArray(coverMeInPiss, killMe[i]);
				}
				return getVarInArray(coverMeInPiss, killMe[killMe.length - 1]);
			}
			return getVarInArray(Type.resolveClass(classVar), variable);
		});
		set("setPropertyFromClass", function(classVar:String, variable:String, value:Dynamic)
		{
			@:privateAccess
			var killMe:Array<String> = variable.split('.');
			if (killMe.length > 1)
			{
				var coverMeInPiss:Dynamic = getVarInArray(Type.resolveClass(classVar), killMe[0]);
				for (i in 1...killMe.length - 1)
				{
					coverMeInPiss = getVarInArray(coverMeInPiss, killMe[i]);
				}
				setVarInArray(coverMeInPiss, killMe[killMe.length - 1], value);
				return true;
			}
			setVarInArray(Type.resolveClass(classVar), variable, value);
			return true;
		});

		set("callMethod", function(funcToRun:String, ?args:Array<Dynamic> = null)
		{
			return callMethodFromObject(PlayState.instance, funcToRun, parseInstances(args));
		});
		set("callMethodFromClass", function(className:String, funcToRun:String, ?args:Array<Dynamic> = null)
		{
			return callMethodFromObject(Type.resolveClass(className), funcToRun, parseInstances(args));
		});

		set("createInstance", function(variableToSave:String, className:String, ?args:Array<Dynamic> = null)
		{
			variableToSave = variableToSave.trim().replace('.', '');
			if (!getVariablesMap().exists(variableToSave))
			{
				if (args == null)
					args = [];
				var myType:Dynamic = Type.resolveClass(className);

				if (myType == null)
				{
					luaTrace('createInstance: Variable $variableToSave is already being used and cannot be replaced!', false, false, FlxColor.RED);
					return false;
				}

				var obj:Dynamic;
				try
				{
					obj = Type.createInstance(myType, args);
				}
				catch (e:Dynamic)
				{
					luaTrace('createInstance: Failed to create $variableToSave, error: ' + Std.string(e), false, false, FlxColor.RED);
					return false;
				}
				if (obj != null)
					getVariablesMap().set(variableToSave, obj);
				else
					luaTrace('createInstance: Failed to create $variableToSave, arguments are possibly wrong.', false, false, FlxColor.RED);

				return (obj != null);
			}
			else
				luaTrace('createInstance: Variable $variableToSave is already being used and cannot be replaced!', false, false, FlxColor.RED);
			return false;
		});
		set("addInstance", function(objectName:String, ?inFront:Bool = false)
		{
			if (getVariablesMap().exists(objectName))
			{
				var obj:Dynamic = getVariablesMap().get(objectName);

				if (menuMode || PlayState.instance == null)
				{
					var state:FlxState = getTargetState();
					if (state != null)
						state.add(obj);
					return;
				}

				if (inFront)
					getTargetInstance().add(obj);
				else
				{
					if (!PlayState.instance.isDead)
						PlayState.instance.insert(PlayState.instance.members.indexOf(getLowestCharacterGroup()), obj);
					else
						GameOverSubstate.instance.insert(GameOverSubstate.instance.members.indexOf(GameOverSubstate.instance.boyfriend), obj);
				}
			}
			else
				luaTrace('addInstance: Can\'t add what doesn\'t exist~ ($objectName)', false, false, FlxColor.RED);
		});
		set("instanceArg", function(instanceName:String, ?className:String = null)
		{
			var retStr:String = '$instanceStr::$instanceName';
			if (className != null)
				retStr += '::$className';
			return retStr;
		});

		// shitass stuff for epic coders like me B)  *image of obama giving himself a medal*
		set("getObjectOrder", function(obj:String)
		{
			var killMe:Array<String> = obj.split('.');
			var leObj:FlxBasic = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				leObj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (leObj != null)
			{
				return getInstance().members.indexOf(leObj);
			}
			luaTrace("getObjectOrder: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return -1;
		});
		set("setObjectOrder", function(obj:String, position:Int)
		{
			var killMe:Array<String> = obj.split('.');
			var leObj:FlxBasic = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				leObj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (leObj != null)
			{
				getInstance().remove(leObj, true);
				getInstance().insert(position, leObj);
				return;
			}
			luaTrace("setObjectOrder: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
		});

		// gay ass tweens
		set("startTween", function(tag:String, vars:String, values:Any = null, duration:Float, options:Any = null)
		{
			var penisExam:Dynamic = tweenPrepare(tag, vars);
			if (penisExam != null)
			{
				if (values != null)
				{
					var myOptions:LuaTweenOptions = getLuaTween(options);
					if (tag != null)
					{
						var variables = MusicBeatState.getVariables();
						tag = 'tween_' + formatVariable(tag);
						variables.set(tag, FlxTween.tween(penisExam, values, duration, {
							type: myOptions.type,
							ease: myOptions.ease,
							startDelay: myOptions.startDelay,
							loopDelay: myOptions.loopDelay,

							onUpdate: function(twn:FlxTween)
							{
								if (myOptions.onUpdate != null)
									dispatchCall(myOptions.onUpdate, [tag, vars]);
							},
							onStart: function(twn:FlxTween)
							{
								if (myOptions.onStart != null)
									dispatchCall(myOptions.onStart, [tag, vars]);
							},
							onComplete: function(twn:FlxTween)
							{
								if (twn.type == FlxTweenType.ONESHOT || twn.type == FlxTweenType.BACKWARD)
									variables.remove(tag);
								if (myOptions.onComplete != null)
									dispatchCall(myOptions.onComplete, [tag, vars]);
							}
						}));
					}
					else
						FlxTween.tween(penisExam, values, duration, {
							type: myOptions.type,
							ease: myOptions.ease,
							startDelay: myOptions.startDelay,
							loopDelay: myOptions.loopDelay
						});
				}
				else
					luaTrace('startTween: No values on 2nd argument!', false, false, FlxColor.RED);
			}
			else
				luaTrace('startTween: Couldnt find object: ' + vars, false, false, FlxColor.RED);
		});

		set("doTweenX", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				getTweenMap().set(tag, FlxTween.tween(penisExam, {x: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
			else
			{
				luaTrace('doTweenX: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		set("doTweenY", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				getTweenMap().set(tag, FlxTween.tween(penisExam, {y: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
			else
			{
				luaTrace('doTweenY: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		set("doTweenAngle", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				getTweenMap().set(tag, FlxTween.tween(penisExam, {angle: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
			else
			{
				luaTrace('doTweenAngle: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		set("doTweenAlpha", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				getTweenMap().set(tag, FlxTween.tween(penisExam, {alpha: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
			else
			{
				luaTrace('doTweenAlpha: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		set("doTweenZoom", function(tag:String, vars:String, value:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				getTweenMap().set(tag, FlxTween.tween(penisExam, {zoom: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
			else
			{
				luaTrace('doTweenZoom: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});
		set("doTweenNum", function(tag:String, value1:Dynamic, value2:Dynamic, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, null);
			if (penisExam != null)
			{
				getTweenMap().set(tag, FlxTween.num(value1, value2, duration, {
					ease: getFlxEaseByString(ease),
					onUpdate: function(num:FlxTween)
					{
						getTweenMap().remove(tag);
						dispatchCall('onTweenUpdateNum', [tag, num]);
					}
				}));
			}
			else
			{
				luaTrace('doTweenNum: Couldnt find object: ' + tag, false, false, FlxColor.RED);
			}
		});
		set("doTweenColor", function(tag:String, vars:String, targetColor:String, duration:Float, ease:String)
		{
			var penisExam:Dynamic = tweenShit(tag, vars);
			if (penisExam != null)
			{
				var color:Int = Std.parseInt(targetColor);
				if (!targetColor.startsWith('0x'))
					color = Std.parseInt('0xff' + targetColor);

				var curColor:FlxColor = penisExam.color;
				curColor.alphaFloat = penisExam.alpha;
				getTweenMap().set(tag, FlxTween.color(penisExam, duration, curColor, color, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						getTweenMap().remove(tag);
						dispatchCall('onTweenCompleted', [tag]);
					}
				}));
			}
			else
			{
				luaTrace('doTweenColor: Couldnt find object: ' + vars, false, false, FlxColor.RED);
			}
		});

		// Tween shit, but for strums
		set("noteTweenX", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
		{
			if (menuMode || PlayState.instance == null)
			{
				luaTrace('noteTween: Strums only exist while a song is playing!', false, false, FlxColor.RED);
				return;
			}

			cancelTween(tag);
			if (note < 0)
				note = 0;
			var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

			if (testicle != null)
			{
				getTweenMap().set(tag, FlxTween.tween(testicle, {x: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
		});
		set("noteTweenY", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
		{
			if (menuMode || PlayState.instance == null)
			{
				luaTrace('noteTween: Strums only exist while a song is playing!', false, false, FlxColor.RED);
				return;
			}

			cancelTween(tag);
			if (note < 0)
				note = 0;
			var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

			if (testicle != null)
			{
				getTweenMap().set(tag, FlxTween.tween(testicle, {y: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
		});
		set("noteTweenAngle", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
		{
			if (menuMode || PlayState.instance == null)
			{
				luaTrace('noteTween: Strums only exist while a song is playing!', false, false, FlxColor.RED);
				return;
			}

			cancelTween(tag);
			if (note < 0)
				note = 0;
			var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

			if (testicle != null)
			{
				getTweenMap().set(tag, FlxTween.tween(testicle, {angle: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
		});
		set("noteTweenDirection", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
		{
			if (menuMode || PlayState.instance == null)
			{
				luaTrace('noteTween: Strums only exist while a song is playing!', false, false, FlxColor.RED);
				return;
			}

			cancelTween(tag);
			if (note < 0)
				note = 0;
			var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

			if (testicle != null)
			{
				getTweenMap().set(tag, FlxTween.tween(testicle, {direction: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
		});
		set("mouseClicked", function(button:String)
		{
			var boobs = FlxG.mouse.justPressed;
			switch (button)
			{
				case 'middle':
					boobs = FlxG.mouse.justPressedMiddle;
				case 'right':
					boobs = FlxG.mouse.justPressedRight;
			}

			return boobs;
		});
		set("mousePressed", function(button:String)
		{
			var boobs = FlxG.mouse.pressed;
			switch (button)
			{
				case 'middle':
					boobs = FlxG.mouse.pressedMiddle;
				case 'right':
					boobs = FlxG.mouse.pressedRight;
			}
			return boobs;
		});
		set("mouseReleased", function(button:String)
		{
			var boobs = FlxG.mouse.justReleased;
			switch (button)
			{
				case 'middle':
					boobs = FlxG.mouse.justReleasedMiddle;
				case 'right':
					boobs = FlxG.mouse.justReleasedRight;
			}
			return boobs;
		});
		set("noteTweenAngle", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
		{
			if (menuMode || PlayState.instance == null)
			{
				luaTrace('noteTween: Strums only exist while a song is playing!', false, false, FlxColor.RED);
				return;
			}

			cancelTween(tag);
			if (note < 0)
				note = 0;
			var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

			if (testicle != null)
			{
				getTweenMap().set(tag, FlxTween.tween(testicle, {angle: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
		});
		set("noteTweenAlpha", function(tag:String, note:Int, value:Dynamic, duration:Float, ease:String)
		{
			if (menuMode || PlayState.instance == null)
			{
				luaTrace('noteTween: Strums only exist while a song is playing!', false, false, FlxColor.RED);
				return;
			}

			cancelTween(tag);
			if (note < 0)
				note = 0;
			var testicle:StrumNote = PlayState.instance.strumLineNotes.members[note % PlayState.instance.strumLineNotes.length];

			if (testicle != null)
			{
				getTweenMap().set(tag, FlxTween.tween(testicle, {alpha: value}, duration, {
					ease: getFlxEaseByString(ease),
					onComplete: function(twn:FlxTween)
					{
						dispatchCall('onTweenCompleted', [tag]);
						getTweenMap().remove(tag);
					}
				}));
			}
		});

		set("cancelTween", function(tag:String)
		{
			cancelTween(tag);
		});

		set("runTimer", function(tag:String, time:Float = 1, loops:Int = 1)
		{
			cancelTimer(tag);
			getTimerMap().set(tag, new FlxTimer().start(time, function(tmr:FlxTimer)
			{
				if (tmr.finished)
				{
					getTimerMap().remove(tag);
				}
				dispatchCall('onTimerCompleted', [tag, tmr.loops, tmr.loopsLeft]);
				// trace('Timer Completed: ' + tag);
			}, loops));
		});
		set("cancelTimer", function(tag:String)
		{
			cancelTimer(tag);
		});

		/*set("getPropertyAdvanced", function(varsStr:String) {
				var variables:Array<String> = varsStr.replace(' ', '').split(',');
				var leClass:Class<Dynamic> = Type.resolveClass(variables[0]);
				if(variables.length > 2) {
					var curProp:Dynamic = Reflect.getProperty(leClass, variables[1]);
					if(variables.length > 3) {
						for (i in 2...variables.length-1) {
							curProp = Reflect.getProperty(curProp, variables[i]);
						}
					}
					return Reflect.getProperty(curProp, variables[variables.length-1]);
				} else if(variables.length == 2) {
					return Reflect.getProperty(leClass, variables[variables.length-1]);
				}
				return null;
			});
			set("setPropertyAdvanced", function(varsStr:String, value:Dynamic) {
				var variables:Array<String> = varsStr.replace(' ', '').split(',');
				var leClass:Class<Dynamic> = Type.resolveClass(variables[0]);
				if(variables.length > 2) {
					var curProp:Dynamic = Reflect.getProperty(leClass, variables[1]);
					if(variables.length > 3) {
						for (i in 2...variables.length-1) {
							curProp = Reflect.getProperty(curProp, variables[i]);
						}
					}
					return Reflect.setProperty(curProp, variables[variables.length-1], value);
				} else if(variables.length == 2) {
					return Reflect.setProperty(leClass, variables[variables.length-1], value);
				}
		});*/

		// stupid bietch ass functions
		set("addScore", function(value:Int = 0)
		{
			PlayState.instance.songScore += value;
			PlayState.instance.RecalculateRating();
		});
		set("addMisses", function(value:Int = 0)
		{
			PlayState.instance.songMisses += value;
			PlayState.instance.RecalculateRating();
		});
		set("addHits", function(value:Int = 0)
		{
			PlayState.instance.songHits += value;
			PlayState.instance.RecalculateRating();
		});
		set("setScore", function(value:Int = 0)
		{
			PlayState.instance.songScore = value;
			PlayState.instance.RecalculateRating();
		});
		set("setMisses", function(value:Int = 0)
		{
			PlayState.instance.songMisses = value;
			PlayState.instance.RecalculateRating();
		});
		set("setHits", function(value:Int = 0)
		{
			PlayState.instance.songHits = value;
			PlayState.instance.RecalculateRating();
		});
		set("getScore", function()
		{
			return PlayState.instance.songScore;
		});
		set("getMisses", function()
		{
			return PlayState.instance.songMisses;
		});
		set("getHits", function()
		{
			return PlayState.instance.songHits;
		});

		set("setHealth", function(value:Float = 0)
		{
			PlayState.instance.health = value;
		});
		set("addHealth", function(value:Float = 0)
		{
			PlayState.instance.health += value;
		});
		set("getHealth", function()
		{
			return PlayState.instance.health;
		});

		set("getColorFromHex", function(color:String)
		{
			if (!color.startsWith('0x'))
				color = '0xff' + color;
			return Std.parseInt(color);
		});

		set("keyboardJustPressed", function(name:String)
		{
			return Reflect.getProperty(FlxG.keys.justPressed, name);
		});
		set("keyboardPressed", function(name:String)
		{
			return Reflect.getProperty(FlxG.keys.pressed, name);
		});
		set("keyboardReleased", function(name:String)
		{
			return Reflect.getProperty(FlxG.keys.justReleased, name);
		});

		set("anyGamepadJustPressed", function(name:String)
		{
			return FlxG.gamepads.anyJustPressed(name);
		});
		set("anyGamepadPressed", function(name:String)
		{
			return FlxG.gamepads.anyPressed(name);
		});
		set("anyGamepadReleased", function(name:String)
		{
			return FlxG.gamepads.anyJustReleased(name);
		});

		set("gamepadAnalogX", function(id:Int, ?leftStick:Bool = true)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
			{
				return 0.0;
			}
			return controller.getXAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		set("gamepadAnalogY", function(id:Int, ?leftStick:Bool = true)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
			{
				return 0.0;
			}
			return controller.getYAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		set("gamepadJustPressed", function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
			{
				return false;
			}
			return Reflect.getProperty(controller.justPressed, name) == true;
		});
		set("gamepadPressed", function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
			{
				return false;
			}
			return Reflect.getProperty(controller.pressed, name) == true;
		});
		set("gamepadReleased", function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
			{
				return false;
			}
			return Reflect.getProperty(controller.justReleased, name) == true;
		});

		set("keyJustPressed", function(name:String)
		{
			var key:Bool = false;
			switch (name)
			{
				case 'left':
					key = getControlSafe('NOTE_LEFT_P');
				case 'down':
					key = getControlSafe('NOTE_DOWN_P');
				case 'up':
					key = getControlSafe('NOTE_UP_P');
				case 'right':
					key = getControlSafe('NOTE_RIGHT_P');
				case 'accept':
					key = getControlSafe('ACCEPT');
				case 'back':
					key = getControlSafe('BACK');
				case 'pause':
					key = getControlSafe('PAUSE');
				case 'reset':
					key = getControlSafe('RESET');
				case 'space':
					/*
						if (ClientPrefs.hitboxLocation == 'Space'){key = FlxG.keys.justPressed.SPACE || PlayState.instance.getControl('SPACE_P');}else{key = FlxG.keys.justPressed.SPACE;}; */ // an extra key for convinience
					key = (PlayState.instance.getControl('SPACE_P') || FlxG.keys.justPressed.SPACE);
			}
			return key;
		});
		set("keyPressed", function(name:String)
		{
			var key:Bool = false;
			switch (name)
			{
				case 'left':
					key = getControlSafe('NOTE_LEFT');
				case 'down':
					key = getControlSafe('NOTE_DOWN');
				case 'up':
					key = getControlSafe('NOTE_UP');
				case 'right':
					key = getControlSafe('NOTE_RIGHT');
				case 'space':
					/*
						if (ClientPrefs.hitboxLocation == 'Space'){key = FlxG.keys.pressed.SPACE || PlayState.instance.getControl('SPACE');}else{key = FlxG.keys.pressed.SPACE;}; */ key = (PlayState.instance.getControl('SPACE')
						|| FlxG.keys.pressed.SPACE);
					// an extra key for convinience
			}
			return key;
		});
		set("keyReleased", function(name:String)
		{
			var key:Bool = false;
			switch (name)
			{
				case 'left':
					key = getControlSafe('NOTE_LEFT_R');
				case 'down':
					key = getControlSafe('NOTE_DOWN_R');
				case 'up':
					key = getControlSafe('NOTE_UP_R');
				case 'right':
					key = getControlSafe('NOTE_RIGHT_R');
				/*case 'space':
					if (ClientPrefs.hitboxLocation == 'Space'){key = FlxG.keys.justReleased.SPACE || PlayState.instance.getControl('SPACE_R');}else{key = FlxG.keys.justReleased.SPACE;}; */
				case 'space':
					key = (PlayState.instance.getControl('SPACE_R') || FlxG.keys.justReleased.SPACE); ///an extra key for convinience
			}
			return key;
		});
		set("addCharacterToList", function(name:String, type:String)
		{
			var charType:Int = 0;
			switch (type.toLowerCase())
			{
				case 'dad':
					charType = 1;
				case 'gf' | 'girlfriend':
					charType = 2;
			}
			PlayState.instance.addCharacterToList(name, charType);
		});
		set("precacheImage", function(name:String, ?library:String, ?allowGPU:Bool = true)
		{
			Paths.image(name, library, allowGPU);
		});
		set("precacheSound", function(name:String)
		{
			CoolUtil.precacheSound(name);
		});
		set("precacheMusic", function(name:String)
		{
			CoolUtil.precacheMusic(name);
		});
		set("triggerEvent", function(name:String, arg1:Dynamic, arg2:Dynamic)
		{
			var value1:String = arg1;
			var value2:String = arg2;
			if (menuMode || PlayState.instance == null)
			{
				// Song events don't exist outside of PlayState
				luaTrace('triggerEvent: Events are only available while a song is playing! ($name)');
				return false;
			}
			PlayState.instance.triggerEventNote(name, value1, value2);
			// trace('Triggered event: ' + name + ', ' + value1 + ', ' + value2);
			return true;
		});

		set("startCountdown", function()
		{
			PlayState.instance.startCountdown();
			return true;
		});
		/*
			#if android
			set("addVirtualPad", function(Dpad:String, Full:String) {
				addVirtualPad(Dpad, Full);
				return true;
			});
			#end
		 */

		set("setPercent", function(modName:String, val:Float, player:Int = -1)
		{
			PlayState.instance.modManager.setPercent(modName, val, player);
		});

		set("addBlankMod", function(modName:String, defaultVal:Float = 0, player:Int = -1)
		{
			PlayState.instance.modManager.quickRegister(new SubModifier(modName, PlayState.instance.modManager));
			PlayState.instance.modManager.setValue(modName, defaultVal);
		});

		set("setValue", function(modName:String, val:Float, player:Int = -1)
		{
			PlayState.instance.modManager.setValue(modName, val, player);
		});

		set("getPercent", function(modName:String, player:Int)
		{
			return PlayState.instance.modManager.getPercent(modName, player);
		});

		set("getValue", function(modName:String, player:Int)
		{
			return PlayState.instance.modManager.getValue(modName, player);
		});

		set("queueSet", function(step:Float, modName:String, target:Float, player:Int = -1)
		{
			PlayState.instance.modManager.queueSet(step, modName, target, player);
		});

		set("queueSetP", function(step:Float, modName:String, perc:Float, player:Int = -1)
		{
			PlayState.instance.modManager.queueSetP(step, modName, perc, player);
		});

		set("queueEase",
			function(step:Float, endStep:Float, modName:String, percent:Float, style:String = 'linear', player:Int = -1,
					?startVal:Float) // lua is autistic and can only accept 5 args
			{
				PlayState.instance.modManager.queueEase(step, endStep, modName, percent, style, player, startVal);
			});

		set("queueEaseP",
			function(step:Float, endStep:Float, modName:String, percent:Float, style:String = 'linear', player:Int = -1,
					?startVal:Float) // lua is autistic and can only accept 5 args
			{
				PlayState.instance.modManager.queueEaseP(step, endStep, modName, percent, style, player, startVal);
			});

		set("endSong", function()
		{
			PlayState.instance.KillNotes();
			PlayState.instance.endSong();
			return true;
		});
		set("restartSong", function(?skipTransition:Bool = false)
		{
			PlayState.instance.persistentUpdate = false;
			PauseSubState.restartSong(skipTransition);
			return true;
		});
		set("exitSong", function(?skipTransition:Bool = false)
		{
			if (skipTransition)
			{
				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
			}

			PlayState.cancelMusicFadeTween();
			CustomFadeTransition.nextCamera = PlayState.instance.camOther;
			if (FlxTransitionableState.skipNextTransIn)
				CustomFadeTransition.nextCamera = null;

			if (PlayState.isStoryMode)
				MusicBeatState.switchState(new StoryMenuState());
			else
				MusicBeatState.switchState(new FreeplayState());

			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			PlayState.changedDifficulty = false;
			PlayState.chartingMode = false;
			PlayState.instance.transitioning = true;
			WeekData.loadTheFirstEnabledMod();
			return true;
		});
		set("getSongPosition", function()
		{
			return Conductor.songPosition;
		});

		set("getCharacterX", function(type:String)
		{
			switch (type.toLowerCase())
			{
				case 'dad' | 'opponent':
					return PlayState.instance.dadGroup.x;
				case 'gf' | 'girlfriend':
					return PlayState.instance.gfGroup.x;
				default:
					return PlayState.instance.boyfriendGroup.x;
			}
		});
		set("setCharacterX", function(type:String, value:Float)
		{
			switch (type.toLowerCase())
			{
				case 'dad' | 'opponent':
					PlayState.instance.dadGroup.x = value;
				case 'gf' | 'girlfriend':
					PlayState.instance.gfGroup.x = value;
				default:
					PlayState.instance.boyfriendGroup.x = value;
			}
		});
		set("getCharacterY", function(type:String)
		{
			switch (type.toLowerCase())
			{
				case 'dad' | 'opponent':
					return PlayState.instance.dadGroup.y;
				case 'gf' | 'girlfriend':
					return PlayState.instance.gfGroup.y;
				default:
					return PlayState.instance.boyfriendGroup.y;
			}
		});
		set("setCharacterY", function(type:String, value:Float)
		{
			switch (type.toLowerCase())
			{
				case 'dad' | 'opponent':
					PlayState.instance.dadGroup.y = value;
				case 'gf' | 'girlfriend':
					PlayState.instance.gfGroup.y = value;
				default:
					PlayState.instance.boyfriendGroup.y = value;
			}
		});
		set("cameraSetTarget", function(target:String)
		{
			var isDad:Bool = false;
			if (target == 'dad')
			{
				isDad = true;
			}
			PlayState.instance.moveCamera(isDad);
			return isDad;
		});
		set("cameraShake", function(camera:String, intensity:Float, duration:Float)
		{
			cameraFromString(camera).shake(intensity, duration);
		});

		set("cameraFlash", function(camera:String, color:String, duration:Float, forced:Bool)
		{
			var colorNum:Int = Std.parseInt(color);
			if (!color.startsWith('0x'))
				colorNum = Std.parseInt('0xff' + color);
			cameraFromString(camera).flash(colorNum, duration, null, forced);
		});
		set("cameraFade", function(camera:String, color:String, duration:Float, forced:Bool)
		{
			var colorNum:Int = Std.parseInt(color);
			if (!color.startsWith('0x'))
				colorNum = Std.parseInt('0xff' + color);
			cameraFromString(camera).fade(colorNum, duration, false, null, forced);
		});
		set("setRatingPercent", function(value:Float)
		{
			PlayState.instance.ratingPercent = value;
		});
		set("setRatingName", function(value:String)
		{
			PlayState.instance.ratingName = value;
		});
		set("setRatingFC", function(value:String)
		{
			PlayState.instance.ratingFC = value;
		});
		set("getMouseX", function(camera:String)
		{
			var cam:FlxCamera = cameraFromString(camera);
			return FlxG.mouse.getScreenPosition(cam).x;
		});
		set("getMouseY", function(camera:String)
		{
			var cam:FlxCamera = cameraFromString(camera);
			return FlxG.mouse.getScreenPosition(cam).y;
		});

		set("getMidpointX", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getMidpoint().x;

			return 0;
		});
		set("getMidpointY", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getMidpoint().y;

			return 0;
		});
		set("getGraphicMidpointX", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getGraphicMidpoint().x;

			return 0;
		});
		set("getGraphicMidpointY", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getGraphicMidpoint().y;

			return 0;
		});
		set("getScreenPositionX", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getScreenPosition().x;

			return 0;
		});
		set("getScreenPositionY", function(variable:String)
		{
			var killMe:Array<String> = variable.split('.');
			var obj:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				obj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}
			if (obj != null)
				return obj.getScreenPosition().y;

			return 0;
		});
		set("characterDance", function(character:String)
		{
			switch (character.toLowerCase())
			{
				case 'dad':
					PlayState.instance.dad.dance();
				case 'gf' | 'girlfriend':
					if (PlayState.instance.gf != null)
						PlayState.instance.gf.dance();
				default:
					PlayState.instance.boyfriend.dance();
			}
		});

		set("makeLuaSprite", function(tag:String, image:String, x:Float, y:Float, ?sfX:Null<Float>, ?sfY:Null<Float>, ?p7:Dynamic)
		{
			tag = tag.replace('.', '');
			resetSpriteTag(tag);
			var leSprite:ModchartSprite = new ModchartSprite(x, y);
			if (image != null && image.length > 0)
			{
				// ES dialect: makeLuaSprite also loads the Sparrow atlas when one sits next to the image
				if (Paths.fileExists('images/' + image + '.xml', TEXT))
					leSprite.frames = Paths.getSparrowAtlas(image);
				else
					leSprite.loadGraphic(Paths.image(image));
			}
			// ES dialect: extra makeLuaSprite args are the scroll factor; menu cameras are
			// scrolled half a screen, so (1, 1) sprites land center-origin like ES does
			if (menuMode && (sfX != null || sfY != null))
				leSprite.scrollFactor.set(sfX != null ? sfX : 1, sfY != null ? sfY : 1);
			leSprite.antialiasing = ClientPrefs.globalAntialiasing;
			getSpriteMap().set(tag, leSprite);
			leSprite.active = true;
		});
		/*
			set("makeLuaGifSprite", function(tag:String, gif:String, x:Float, y:Float) {
				tag = tag.replace('.', '');
				resetSpriteTag(tag);
				var leSprite:ModcharGiftSprite = new ModcharGiftSprite(x, y);
				if(gif != null && gif.length > 0)
				{
					leSprite.loadGif((gif));
				}
				leSprite.antialiasing = ClientPrefs.globalAntialiasing;
				getSpriteMap().set(tag, leSprite);
				leSprite.active = true;
			});
		 */
		set("makeAnimatedLuaSprite", function(tag:String, image:String, x:Float, y:Float, ?spriteType:String = "sparrow")
		{
			tag = tag.replace('.', '');
			resetSpriteTag(tag);
			var leSprite:ModchartSprite = new ModchartSprite(x, y);

			loadFrames(leSprite, image, spriteType);
			leSprite.antialiasing = ClientPrefs.globalAntialiasing;
			getSpriteMap().set(tag, leSprite);
		});

		set("makeGraphic", function(obj:String, width:Int, height:Int, color:String)
		{
			var colorNum:Int = Std.parseInt(color);
			if (!color.startsWith('0x'))
				colorNum = Std.parseInt('0xff' + color);

			var spr:FlxSprite = getLuaObjectSafe(obj, false);
			if (spr != null)
			{
				getLuaObjectSafe(obj, false).makeGraphic(width, height, colorNum);
				return;
			}

			var object:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (object != null)
			{
				object.makeGraphic(width, height, colorNum);
			}
		});
		set("addAnimationByPrefix", function(obj:String, name:String, prefix:String, framerate:Int = 24, loop:Bool = true)
		{
			if (getLuaObjectSafe(obj, false) != null)
			{
				var cock:FlxSprite = getLuaObjectSafe(obj, false);
				cock.animation.addByPrefix(name, prefix, framerate, loop);
				if (cock.animation.curAnim == null)
				{
					cock.animation.play(name, true);
				}
				return;
			}

			var cock:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (cock != null)
			{
				cock.animation.addByPrefix(name, prefix, framerate, loop);
				if (cock.animation.curAnim == null)
				{
					cock.animation.play(name, true);
				}
			}
		});

		set("addAnimation", function(obj:String, name:String, frames:Array<Int>, framerate:Int = 24, loop:Bool = true)
		{
			if (getLuaObjectSafe(obj, false) != null)
			{
				var cock:FlxSprite = getLuaObjectSafe(obj, false);
				cock.animation.add(name, frames, framerate, loop);
				if (cock.animation.curAnim == null)
				{
					cock.animation.play(name, true);
				}
				return;
			}

			var cock:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (cock != null)
			{
				cock.animation.add(name, frames, framerate, loop);
				if (cock.animation.curAnim == null)
				{
					cock.animation.play(name, true);
				}
			}
		});

		set("addAnimationByIndices", function(obj:String, name:String, prefix:String, indices:String, framerate:Int = 24)
		{
			return addAnimByIndices(obj, name, prefix, indices, framerate, false);
		});
		set("addAnimationByIndicesLoop", function(obj:String, name:String, prefix:String, indices:String, framerate:Int = 24)
		{
			return addAnimByIndices(obj, name, prefix, indices, framerate, true);
		});

		set("playAnim", function(obj:String, name:String, forced:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0)
		{
			if (getLuaObjectSafe(obj, false) != null)
			{
				var luaObj:FlxSprite = getLuaObjectSafe(obj, false);
				if (luaObj.animation.getByName(name) != null)
				{
					if (Std.isOfType(luaObj, Character))
					{
						// ES dialect: characters created with makeChar() keep their anim offsets
						var char:Character = cast luaObj;
						char.playAnim(name, forced, reverse, startFrame);
					}
					else
						luaObj.animation.play(name, forced, reverse, startFrame);

					if (Std.isOfType(luaObj, ModchartSprite))
					{
						// convert luaObj to ModchartSprite
						var obj:Dynamic = luaObj;
						var luaObj:ModchartSprite = obj;

						var daOffset = luaObj.animOffsets.get(name);
						if (luaObj.animOffsets.exists(name))
						{
							luaObj.offset.set(daOffset[0], daOffset[1]);
						}
					}
				}
				return true;
			}

			var spr:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (spr != null)
			{
				if (spr.animation.getByName(name) != null)
				{
					if (Std.isOfType(spr, Character))
					{
						// convert spr to Character
						var obj:Dynamic = spr;
						var spr:Character = obj;
						spr.playAnim(name, forced, reverse, startFrame);
					}
					else
						spr.animation.play(name, forced, reverse, startFrame);
				}
				return true;
			}
			return false;
		});
		set("addOffset", function(obj:String, anim:String, x:Float, y:Float)
		{
			if (getSpriteMap().exists(obj))
			{
				getSpriteMap().get(obj).animOffsets.set(anim, [x, y]);
				return true;
			}

			var char:Character = Reflect.getProperty(getInstance(), obj);
			if (char != null)
			{
				char.addOffset(anim, x, y);
				return true;
			}
			return false;
		});
		set("setVar", function(varName:String, value:Dynamic)
		{
			getVariablesMap().set(varName, value);
			return value;
		});
		set("getVar", function(varName:String)
		{
			var vars:Map<String, Dynamic> = getVariablesMap();
			if (vars.exists(varName))
				return vars.get(varName);
			return null;
		});

		set("setScrollFactor", function(obj:String, scrollX:Float, scrollY:Float)
		{
			if (getLuaObjectSafe(obj, false) != null)
			{
				getLuaObjectSafe(obj, false).scrollFactor.set(scrollX, scrollY);
				return;
			}

			var object:FlxObject = Reflect.getProperty(getInstance(), obj);
			if (object != null)
			{
				object.scrollFactor.set(scrollX, scrollY);
			}
		});
		set("addLuaSprite", function(tag:String, front:Bool = false)
		{
			if (getSpriteMap().exists(tag))
			{
				var shit:ModchartSprite = getSpriteMap().get(tag);
				if (!shit.wasAdded)
				{
					if (menuMode || PlayState.instance == null)
					{
						// ES menu states: plain append, creation order = draw order
						getTargetState().add(shit);
					}
					else if (front)
					{
						getInstance().add(shit);
					}
					else
					{
						if (PlayState.instance.isDead)
						{
							GameOverSubstate.instance.insert(GameOverSubstate.instance.members.indexOf(GameOverSubstate.instance.boyfriend), shit);
						}
						else
						{
							var position:Int = PlayState.instance.members.indexOf(PlayState.instance.gfGroup);
							if (PlayState.instance.members.indexOf(PlayState.instance.boyfriendGroup) < position)
							{
								position = PlayState.instance.members.indexOf(PlayState.instance.boyfriendGroup);
							}
							else if (PlayState.instance.members.indexOf(PlayState.instance.dadGroup) < position)
							{
								position = PlayState.instance.members.indexOf(PlayState.instance.dadGroup);
							}
							PlayState.instance.insert(position, shit);
						}
					}
					shit.wasAdded = true;
					// trace('added a thing: ' + tag);
				}
			}
		});
		set("setGraphicSize", function(obj:String, x:Int, y:Int = 0, updateHitbox:Bool = true)
		{
			if (getLuaObjectSafe(obj) != null)
			{
				var shit:FlxSprite = getLuaObjectSafe(obj);
				shit.setGraphicSize(x, y);
				if (updateHitbox)
					shit.updateHitbox();
				return;
			}

			var killMe:Array<String> = obj.split('.');
			var poop:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				poop = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (poop != null)
			{
				poop.setGraphicSize(x, y);
				if (updateHitbox)
					poop.updateHitbox();
				return;
			}
			luaTrace('setGraphicSize: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});
		set("scaleObject", function(obj:String, x:Float, y:Float, updateHitbox:Bool = true)
		{
			if (getLuaObjectSafe(obj) != null)
			{
				var shit:FlxSprite = getLuaObjectSafe(obj);
				shit.scale.set(x, y);
				if (updateHitbox)
					shit.updateHitbox();
				return;
			}

			var killMe:Array<String> = obj.split('.');
			var poop:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				poop = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (poop != null)
			{
				poop.scale.set(x, y);
				if (updateHitbox)
					poop.updateHitbox();
				return;
			}
			luaTrace('scaleObject: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});
		set("updateHitbox", function(obj:String)
		{
			if (getLuaObjectSafe(obj) != null)
			{
				var shit:FlxSprite = getLuaObjectSafe(obj);
				shit.updateHitbox();
				return;
			}

			var poop:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (poop != null)
			{
				poop.updateHitbox();
				return;
			}
			luaTrace('updateHitbox: Couldnt find object: ' + obj, false, false, FlxColor.RED);
		});
		set("updateHitboxFromGroup", function(group:String, index:Int)
		{
			if (Std.isOfType(Reflect.getProperty(getInstance(), group), FlxTypedGroup))
			{
				Reflect.getProperty(getInstance(), group).members[index].updateHitbox();
				return;
			}
			Reflect.getProperty(getInstance(), group)[index].updateHitbox();
		});

		set("removeLuaSprite", function(tag:String, destroy:Bool = true)
		{
			if (!getSpriteMap().exists(tag))
			{
				return;
			}

			var pee:ModchartSprite = getSpriteMap().get(tag);
			if (destroy)
			{
				pee.kill();
			}

			if (pee.wasAdded)
			{
				getInstance().remove(pee, true);
				pee.wasAdded = false;
			}

			if (destroy)
			{
				pee.destroy();
				getSpriteMap().remove(tag);
			}
		});

		set("luaSpriteExists", function(tag:String)
		{
			return getSpriteMap().exists(tag);
		});
		set("luaTextExists", function(tag:String)
		{
			return getTextMap().exists(tag);
		});
		set("luaSoundExists", function(tag:String)
		{
			return getSoundMap().exists(tag);
		});

		set("setHealthBarColors", function(leftHex:String, rightHex:String, ?rightHex2:String)
		{
			// ES dialect: setHealthBarColors(barTag, leftHex, rightHex)
			if (rightHex2 != null)
			{
				ESCompat.setHealthBarColors(this, leftHex, rightHex, rightHex2);
				return;
			}

			if (PlayState.instance == null || menuMode)
				return;

			var left:FlxColor = Std.parseInt(leftHex);
			if (!leftHex.startsWith('0x'))
				left = Std.parseInt('0xff' + leftHex);
			var right:FlxColor = Std.parseInt(rightHex);
			if (!rightHex.startsWith('0x'))
				right = Std.parseInt('0xff' + rightHex);

			PlayState.instance.healthBar.createFilledBar(left, right);
			PlayState.instance.healthBar.updateBar();
		});
		set("setTimeBarColors", function(leftHex:String, rightHex:String)
		{
			var left:FlxColor = Std.parseInt(leftHex);
			if (!leftHex.startsWith('0x'))
				left = Std.parseInt('0xff' + leftHex);
			var right:FlxColor = Std.parseInt(rightHex);
			if (!rightHex.startsWith('0x'))
				right = Std.parseInt('0xff' + rightHex);

			PlayState.instance.timeBar.createFilledBar(right, left);
			PlayState.instance.timeBar.updateBar();
		});

		set("setObjectCamera", function(obj:String, camera:String = '')
		{
			/*if(getSpriteMap().exists(obj)) {
					getSpriteMap().get(obj).cameras = [cameraFromString(camera)];
					return true;
				}
				else if(getTextMap().exists(obj)) {
					getTextMap().get(obj).cameras = [cameraFromString(camera)];
					return true;
			}*/
			var real = getLuaObjectSafe(obj);
			if (real != null)
			{
				// cameras is a pure get/set property in flixel 5.x, so it cannot be
				// assigned through a Dynamic-typed reference
				if (!Std.isOfType(real, FlxBasic))
					return false;
				(cast real : FlxBasic).cameras = [cameraFromString(camera)];
				return true;
			}

			var killMe:Array<String> = obj.split('.');
			var object:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				object = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (object != null)
			{
				object.cameras = [cameraFromString(camera)];
				return true;
			}
			luaTrace("setObjectCamera: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		set("setBlendMode", function(obj:String, blend:String = '')
		{
			var real = getLuaObjectSafe(obj);
			if (real != null)
			{
				real.blend = blendModeFromString(blend);
				return true;
			}

			var killMe:Array<String> = obj.split('.');
			var spr:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				spr = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (spr != null)
			{
				spr.blend = blendModeFromString(blend);
				return true;
			}
			luaTrace("setBlendMode: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		set("screenCenter", function(obj:String, pos:String = 'xy')
		{
			var spr:FlxSprite = getLuaObjectSafe(obj);

			if (spr == null)
			{
				var killMe:Array<String> = obj.split('.');
				spr = getObjectDirectly(killMe[0]);
				if (killMe.length > 1)
				{
					spr = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
				}
			}

			if (spr != null)
			{
				switch (pos.trim().toLowerCase())
				{
					case 'x':
						spr.screenCenter(X);
						return;
					case 'y':
						spr.screenCenter(Y);
						return;
					default:
						spr.screenCenter(XY);
						return;
				}
			}
			luaTrace("screenCenter: Object " + obj + " doesn't exist!", false, false, FlxColor.RED);
		});
		set("objectsOverlap", function(obj1:String, obj2:String)
		{
			var namesArray:Array<String> = [obj1, obj2];
			var objectsArray:Array<FlxSprite> = [];
			for (i in 0...namesArray.length)
			{
				var real = getLuaObjectSafe(namesArray[i]);
				if (real != null)
				{
					objectsArray.push(real);
				}
				else
				{
					objectsArray.push(Reflect.getProperty(getInstance(), namesArray[i]));
				}
			}

			if (!objectsArray.contains(null) && FlxG.overlap(objectsArray[0], objectsArray[1]))
			{
				return true;
			}
			return false;
		});
		set("getPixelColor", function(obj:String, x:Int, y:Int)
		{
			var killMe:Array<String> = obj.split('.');
			var spr:FlxSprite = getObjectDirectly(killMe[0]);
			if (killMe.length > 1)
			{
				spr = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
			}

			if (spr != null)
			{
				if (spr.framePixels != null)
					spr.framePixels.getPixel32(x, y);
				return spr.pixels.getPixel32(x, y);
			}
			return 0;
		});
		set("getRandomInt", function(min:Int, max:Int = FlxMath.MAX_VALUE_INT, exclude:String = '')
		{
			var excludeArray:Array<String> = exclude.split(',');
			var toExclude:Array<Int> = [];
			for (i in 0...excludeArray.length)
			{
				toExclude.push(Std.parseInt(excludeArray[i].trim()));
			}
			return FlxG.random.int(min, max, toExclude);
		});
		set("getRandomFloat", function(min:Float, max:Float = 1, exclude:String = '')
		{
			var excludeArray:Array<String> = exclude.split(',');
			var toExclude:Array<Float> = [];
			for (i in 0...excludeArray.length)
			{
				toExclude.push(Std.parseFloat(excludeArray[i].trim()));
			}
			return FlxG.random.float(min, max, toExclude);
		});
		set("getRandomBool", function(chance:Float = 50)
		{
			return FlxG.random.bool(chance);
		});
		set("startDialogue", function(dialogueFile:String, music:String = null)
		{
			var path:String;
			#if MODS_ALLOWED
			path = Paths.modsJson(Paths.formatToSongPath(PlayState.SONG.song) + '/' + dialogueFile);
			if (!FileSystem.exists(path))
			#end
			path = SUtil.getPath() + Paths.json(Paths.formatToSongPath(PlayState.SONG.song) + '/' + dialogueFile);

			luaTrace('startDialogue: Trying to load dialogue: ' + path);

			#if MODS_ALLOWED
			if (FileSystem.exists(path))
			#else
			if (Assets.exists(path))
			#end
			{
				var shit:DialogueFile = DialogueBoxPsych.parseDialogue(path);
				if (shit.dialogue.length > 0)
				{
					PlayState.instance.startDialogue(shit, music);
					luaTrace('startDialogue: Successfully loaded dialogue', false, false, FlxColor.GREEN);
					return true;
				}
				else
				{
					luaTrace('startDialogue: Your dialogue file is badly formatted!', false, false, FlxColor.RED);
				}
			}
		else
		{
			luaTrace('startDialogue: Dialogue file not found', false, false, FlxColor.RED);
			if (PlayState.instance.endingSong)
			{
				PlayState.instance.endSong();
			}
			else
			{
				PlayState.instance.startCountdown();
			}
		}
			return false;
		});
		set("startVideo", function(videoFile:String, ?forMidSong:Bool = false)
		{
			#if VIDEOS_ALLOWED
			if (FileSystem.exists(Paths.video(videoFile)))
			{
				PlayState.instance.startVideo(videoFile, forMidSong);
				if (forMidSong)
				{
					PlayState.instance.inCutscene = false;
					@:privateAccess PlayState.instance.canPause = true;
				}
				return true;
			}
			else
			{
				luaTrace('startVideo: Video file not found: ' + videoFile, false, false, FlxColor.RED);
			}
			return false;
			#else
			if (PlayState.instance.endingSong)
			{
				PlayState.instance.endSong();
			}
			else
			{
				PlayState.instance.startCountdown();
			}
			return true;
			#end
		});

		set("makeLuaVideoSprite", function(tag:String, ?path:String = null, ?x:Float = 0, ?y:Float = 0, ?destroyOnUse = true)
		{
			if (menuMode || PlayState.instance == null)
			{
				luaTrace('makeLuaVideoSprite: Videos are only available while a song is playing!', false, false, FlxColor.RED);
				return;
			}

			tag = tag.replace('.', '');
			resetVideoSpriteTag(tag);
			var leSprite:ModchartVideoSprite = new ModchartVideoSprite(destroyOnUse);
			leSprite.addCallback('onFormat', () ->
			{
				leSprite.x = x;
				leSprite.y = y;
				dispatchCall('onVideoFormat', [tag]);
			});
			leSprite.addCallback('onStart', () ->
			{
				dispatchCall('onVideoStart', [tag]);
			});
			leSprite.addCallback('onEnd', () ->
			{
				dispatchCall('onVideoFinished', [tag]);
			});
			if (path != null && path.length > 0)
			{
				leSprite.load(Paths.video(path));
			}
			PlayState.instance.modchartVideo.set(tag, leSprite);
			leSprite.active = true;
		});

		set("playVideo", function(tag:String)
		{
			if (PlayState.instance.getLuaVideoObject(tag) != null)
			{
				PlayState.instance.getLuaVideoObject(tag).play();
				return;
			}
		});

		// I dare not use this function. I seldom use it.
		set("stopVideo", function(tag:String)
		{
			if (PlayState.instance.getLuaVideoObject(tag) != null)
			{
				PlayState.instance.getLuaVideoObject(tag).stop();
				return;
			}
		});

		set("EndVideo", function(tag:String)
		{
			if (PlayState.instance.getLuaVideoObject(tag) != null)
			{
				PlayState.instance.getLuaVideoObject(tag).destroy();
				return;
			}
		});

		set("resumeVideo", function(tag:String)
		{
			if (PlayState.instance.getLuaVideoObject(tag) != null)
			{
				PlayState.instance.getLuaVideoObject(tag).resume();
				return;
			}
		});
		set("pauseVideo", function(tag:String)
		{
			if (PlayState.instance.getLuaVideoObject(tag) != null)
			{
				PlayState.instance.getLuaVideoObject(tag).pause();
				return;
			}
		});

		set("playMusic", function(sound:String, volume:Float = 1, loop:Bool = false)
		{
			FlxG.sound.playMusic(Paths.music(sound), volume, loop);
		});
		set("playSound", function(sound:String, volume:Float = 1, ?tag:String = null)
		{
			if (tag != null && tag.length > 0)
			{
				tag = tag.replace('.', '');
				if (getSoundMap().exists(tag))
				{
					getSoundMap().get(tag).stop();
				}
				getSoundMap().set(tag, FlxG.sound.play(Paths.sound(sound), volume, false, function()
				{
					getSoundMap().remove(tag);
					dispatchCall('onSoundFinished', [tag]);
				}));
				return;
			}
			FlxG.sound.play(Paths.sound(sound), volume);
		});
		set("stopSound", function(tag:String)
		{
			if (tag != null && tag.length > 1 && getSoundMap().exists(tag))
			{
				getSoundMap().get(tag).stop();
				getSoundMap().remove(tag);
			}
		});
		set("pauseSound", function(tag:String)
		{
			if (tag != null && tag.length > 1 && getSoundMap().exists(tag))
			{
				getSoundMap().get(tag).pause();
			}
		});
		set("resumeSound", function(tag:String)
		{
			if (tag != null && tag.length > 1 && getSoundMap().exists(tag))
			{
				getSoundMap().get(tag).play();
			}
		});
		set("soundFadeIn", function(tag:String, duration:Float, fromValue:Float = 0, toValue:Float = 1)
		{
			if (tag == null || tag.length < 1)
			{
				FlxG.sound.music.fadeIn(duration, fromValue, toValue);
			}
			else if (getSoundMap().exists(tag))
			{
				getSoundMap().get(tag).fadeIn(duration, fromValue, toValue);
			}
		});
		set("soundFadeOut", function(tag:String, duration:Float, toValue:Float = 0)
		{
			if (tag == null || tag.length < 1)
			{
				FlxG.sound.music.fadeOut(duration, toValue);
			}
			else if (getSoundMap().exists(tag))
			{
				getSoundMap().get(tag).fadeOut(duration, toValue);
			}
		});
		set("soundFadeCancel", function(tag:String)
		{
			if (tag == null || tag.length < 1)
			{
				if (FlxG.sound.music.fadeTween != null)
				{
					FlxG.sound.music.fadeTween.cancel();
				}
			}
			else if (getSoundMap().exists(tag))
			{
				var theSound:FlxSound = getSoundMap().get(tag);
				if (theSound.fadeTween != null)
				{
					theSound.fadeTween.cancel();
					getSoundMap().remove(tag);
				}
			}
		});
		set("getSoundVolume", function(tag:String)
		{
			if (tag == null || tag.length < 1)
			{
				if (FlxG.sound.music != null)
				{
					return FlxG.sound.music.volume;
				}
			}
			else if (getSoundMap().exists(tag))
			{
				return getSoundMap().get(tag).volume;
			}
			return 0;
		});
		set("setSoundVolume", function(tag:String, value:Float)
		{
			if (tag == null || tag.length < 1)
			{
				if (FlxG.sound.music != null)
				{
					FlxG.sound.music.volume = value;
				}
			}
			else if (getSoundMap().exists(tag))
			{
				getSoundMap().get(tag).volume = value;
			}
		});
		set("getSoundTime", function(tag:String)
		{
			if (tag != null && tag.length > 0 && getSoundMap().exists(tag))
			{
				return getSoundMap().get(tag).time;
			}
			return 0;
		});
		set("setSoundTime", function(tag:String, value:Float)
		{
			if (tag != null && tag.length > 0 && getSoundMap().exists(tag))
			{
				var theSound:FlxSound = getSoundMap().get(tag);
				if (theSound != null)
				{
					var wasResumed:Bool = theSound.playing;
					theSound.pause();
					theSound.time = value;
					if (wasResumed)
						theSound.play();
				}
			}
		});

		set("debugPrint", function(text1:Dynamic = '', text2:Dynamic = '', text3:Dynamic = '', text4:Dynamic = '', text5:Dynamic = '')
		{
			if (text1 == null)
				text1 = '';
			if (text2 == null)
				text2 = '';
			if (text3 == null)
				text3 = '';
			if (text4 == null)
				text4 = '';
			if (text5 == null)
				text5 = '';
			luaTrace('' + text1 + text2 + text3 + text4 + text5, true, false);
		});

		set("close", function()
		{
			closed = true;
			return closed;
		});

		set("changePresence", function(details:String, state:Null<String>, ?smallImageKey:String, ?hasStartTimestamp:Bool, ?endTimestamp:Float)
		{
			#if desktop
			DiscordClient.changePresence(details, state, smallImageKey, hasStartTimestamp, endTimestamp);
			#end
		});

		set("vibration", function(milliseconds:Int)
		{
			#if android
			Hardware.vibrate(milliseconds);
			#end
		});

		// LUA TEXTS
		set("makeLuaText", function(tag:String, text:String, width:Int, x:Float, y:Float)
		{
			tag = tag.replace('.', '');
			resetTextTag(tag);
			var leText:ModchartText = new ModchartText(x, y, text, width);
			getTextMap().set(tag, leText);
		});

		set("setTextString", function(tag:String, text:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.text = text;
				return true;
			}
			luaTrace("setTextString: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		set("setTextSize", function(tag:String, size:Int)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.size = size;
				return true;
			}
			luaTrace("setTextSize: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		set("setTextWidth", function(tag:String, width:Float)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.fieldWidth = width;
				return true;
			}
			luaTrace("setTextWidth: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		set("setTextBorder", function(tag:String, size:Dynamic, color:Dynamic)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				// Engine Custom ES calls this as setTextBorder(tag, color, size) while Psych uses
				// (tag, size, color): a String in the size slot can only be a color, so swap them
				if (Std.isOfType(size, String) && !Std.isOfType(color, String))
				{
					var swap:Dynamic = size;
					size = color;
					color = swap;
				}

				var colorStr:String = Std.string(color);
				var colorNum:Int = Std.parseInt(colorStr);
				if (!colorStr.startsWith('0x'))
					colorNum = Std.parseInt('0xff' + colorStr);

				obj.borderSize = Std.parseFloat(Std.string(size));
				obj.borderColor = colorNum;
				return true;
			}
			luaTrace("setTextBorder: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		set("setTextColor", function(tag:String, color:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				var colorNum:Int = Std.parseInt(color);
				if (!color.startsWith('0x'))
					colorNum = Std.parseInt('0xff' + color);

				obj.color = colorNum;
				return true;
			}
			luaTrace("setTextColor: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		set("setTextFont", function(tag:String, newFont:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.font = Paths.fontName(newFont);
				return true;
			}
			luaTrace("setTextFont: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		set("setTextItalic", function(tag:String, italic:Bool)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.italic = italic;
				return true;
			}
			luaTrace("setTextItalic: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});
		set("setTextAlignment", function(tag:String, alignment:String = 'left')
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				obj.alignment = LEFT;
				switch (alignment.trim().toLowerCase())
				{
					case 'right':
						obj.alignment = RIGHT;
					case 'center':
						obj.alignment = CENTER;
				}
				return true;
			}
			luaTrace("setTextAlignment: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return false;
		});

		set("getTextString", function(tag:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null && obj.text != null)
			{
				return obj.text;
			}
			luaTrace("getTextString: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return null;
		});
		set("getTextSize", function(tag:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				return obj.size;
			}
			luaTrace("getTextSize: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return -1;
		});
		set("getTextFont", function(tag:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				return obj.font;
			}
			luaTrace("getTextFont: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return null;
		});
		set("getTextWidth", function(tag:String)
		{
			var obj:FlxText = getTextObject(tag);
			if (obj != null)
			{
				return obj.fieldWidth;
			}
			luaTrace("getTextWidth: Object " + tag + " doesn't exist!", false, false, FlxColor.RED);
			return 0;
		});

		set("addLuaText", function(tag:String)
		{
			if (getTextMap().exists(tag))
			{
				var shit:ModchartText = getTextMap().get(tag);
				if (!shit.wasAdded)
				{
					getInstance().add(shit);
					shit.wasAdded = true;
					// trace('added a thing: ' + tag);
				}
			}
		});
		set("removeLuaText", function(tag:String, destroy:Bool = true)
		{
			if (!getTextMap().exists(tag))
			{
				return;
			}

			var pee:ModchartText = getTextMap().get(tag);
			if (destroy)
			{
				pee.kill();
			}

			if (pee.wasAdded)
			{
				getInstance().remove(pee, true);
				pee.wasAdded = false;
			}

			if (destroy)
			{
				pee.destroy();
				getTextMap().remove(tag);
			}
		});

		set("initSaveData", function(name:String, ?folder:String = 'psychenginemods')
		{
			if (!PlayState.instance.modchartSaves.exists(name))
			{
				var save:FlxSave = new FlxSave();
				// folder goes unused for flixel 5 users. @BeastlyGhost
				save.bind(name, CoolUtil.getSavePath(folder));
				PlayState.instance.modchartSaves.set(name, save);
				return;
			}
			luaTrace('initSaveData: Save file already initialized: ' + name);
		});
		set("flushSaveData", function(name:String)
		{
			if (PlayState.instance.modchartSaves.exists(name))
			{
				PlayState.instance.modchartSaves.get(name).flush();
				return;
			}
			luaTrace('flushSaveData: Save file not initialized: ' + name, false, false, FlxColor.RED);
		});
		set("getDataFromSave", function(name:String, field:String, ?defaultValue:Dynamic = null)
		{
			if (PlayState.instance.modchartSaves.exists(name))
			{
				var retVal:Dynamic = Reflect.field(PlayState.instance.modchartSaves.get(name).data, field);
				return retVal;
			}
			luaTrace('getDataFromSave: Save file not initialized: ' + name, false, false, FlxColor.RED);
			return defaultValue;
		});
		set("setDataFromSave", function(name:String, field:String, value:Dynamic)
		{
			if (PlayState.instance.modchartSaves.exists(name))
			{
				Reflect.setField(PlayState.instance.modchartSaves.get(name).data, field, value);
				return;
			}
			luaTrace('setDataFromSave: Save file not initialized: ' + name, false, false, FlxColor.RED);
		});

		set("checkFileExists", function(filename:String, ?absolute:Bool = false)
		{
			#if MODS_ALLOWED
			if (absolute)
			{
				return FileSystem.exists(filename);
			}

			var path:String = Paths.modFolders(filename);
			if (FileSystem.exists(path))
			{
				return true;
			}
			return FileSystem.exists(Paths.getPath('assets/$filename', TEXT));
			#else
			if (absolute)
			{
				return Assets.exists(filename);
			}
			return Assets.exists(Paths.getPath('assets/$filename', TEXT));
			#end
		});
		set("saveFile", function(path:String, content:String, ?absolute:Bool = false)
		{
			try
			{
				if (!absolute)
					File.saveContent(Paths.mods(path), content);
				else
					File.saveContent(path, content);

				return true;
			}
			catch (e:Dynamic)
			{
				luaTrace("saveFile: Error trying to save " + path + ": " + e, false, false, FlxColor.RED);
			}
			return false;
		});
		set("deleteFile", function(path:String, ?ignoreModFolders:Bool = false)
		{
			try
			{
				#if MODS_ALLOWED
				if (!ignoreModFolders)
				{
					var lePath:String = Paths.modFolders(path);
					if (FileSystem.exists(lePath))
					{
						FileSystem.deleteFile(lePath);
						return true;
					}
				}
				#end

				var lePath:String = Paths.getPath(path, TEXT);
				if (Assets.exists(lePath))
				{
					FileSystem.deleteFile(lePath);
					return true;
				}
			}
			catch (e:Dynamic)
			{
				luaTrace("deleteFile: Error trying to delete " + path + ": " + e, false, false, FlxColor.RED);
			}
			return false;
		});
		set("getTextFromFile", function(path:String, ?ignoreModFolders:Bool = false)
		{
			return Paths.getTextFromFile(path, ignoreModFolders);
		});

		// DEPRECATED, DONT MESS WITH THESE SHITS, ITS JUST THERE FOR BACKWARD COMPATIBILITY
		set("objectPlayAnimation", function(obj:String, name:String, forced:Bool = false, ?startFrame:Int = 0)
		{
			luaTrace("objectPlayAnimation is deprecated! Use playAnim instead", false, true);
			if (getLuaObjectSafe(obj, false) != null)
			{
				getLuaObjectSafe(obj, false).animation.play(name, forced, false, startFrame);
				return true;
			}

			var spr:FlxSprite = Reflect.getProperty(getInstance(), obj);
			if (spr != null)
			{
				spr.animation.play(name, forced, false, startFrame);
				return true;
			}
			return false;
		});
		set("characterPlayAnim", function(character:String, anim:String, ?forced:Bool = false)
		{
			luaTrace("characterPlayAnim is deprecated! Use playAnim instead", false, true);
			switch (character.toLowerCase())
			{
				case 'dad':
					if (PlayState.instance.dad.animOffsets.exists(anim))
						PlayState.instance.dad.playAnim(anim, forced);
				case 'gf' | 'girlfriend':
					if (PlayState.instance.gf != null && PlayState.instance.gf.animOffsets.exists(anim))
						PlayState.instance.gf.playAnim(anim, forced);
				default:
					if (PlayState.instance.boyfriend.animOffsets.exists(anim))
						PlayState.instance.boyfriend.playAnim(anim, forced);
			}
		});
		set("luaSpriteMakeGraphic", function(tag:String, width:Int, height:Int, color:String)
		{
			luaTrace("luaSpriteMakeGraphic is deprecated! Use makeGraphic instead", false, true);
			if (getSpriteMap().exists(tag))
			{
				var colorNum:Int = Std.parseInt(color);
				if (!color.startsWith('0x'))
					colorNum = Std.parseInt('0xff' + color);

				getSpriteMap().get(tag).makeGraphic(width, height, colorNum);
			}
		});
		set("luaSpriteAddAnimationByPrefix", function(tag:String, name:String, prefix:String, framerate:Int = 24, loop:Bool = true)
		{
			luaTrace("luaSpriteAddAnimationByPrefix is deprecated! Use addAnimationByPrefix instead", false, true);
			if (getSpriteMap().exists(tag))
			{
				var cock:ModchartSprite = getSpriteMap().get(tag);
				cock.animation.addByPrefix(name, prefix, framerate, loop);
				if (cock.animation.curAnim == null)
				{
					cock.animation.play(name, true);
				}
			}
		});
		set("luaSpriteAddAnimationByIndices", function(tag:String, name:String, prefix:String, indices:String, framerate:Int = 24)
		{
			luaTrace("luaSpriteAddAnimationByIndices is deprecated! Use addAnimationByIndices instead", false, true);
			if (getSpriteMap().exists(tag))
			{
				var strIndices:Array<String> = indices.trim().split(',');
				var die:Array<Int> = [];
				for (i in 0...strIndices.length)
				{
					die.push(Std.parseInt(strIndices[i]));
				}
				var pussy:ModchartSprite = getSpriteMap().get(tag);
				pussy.animation.addByIndices(name, prefix, die, '', framerate, false);
				if (pussy.animation.curAnim == null)
				{
					pussy.animation.play(name, true);
				}
			}
		});
		set("luaSpritePlayAnimation", function(tag:String, name:String, forced:Bool = false)
		{
			luaTrace("luaSpritePlayAnimation is deprecated! Use playAnim instead", false, true);
			if (getSpriteMap().exists(tag))
			{
				getSpriteMap().get(tag).animation.play(name, forced);
			}
		});
		set("setLuaSpriteCamera", function(tag:String, camera:String = '')
		{
			luaTrace("setLuaSpriteCamera is deprecated! Use setObjectCamera instead", false, true);
			if (getSpriteMap().exists(tag))
			{
				getSpriteMap().get(tag).cameras = [cameraFromString(camera)];
				return true;
			}
			luaTrace("Lua sprite with tag: " + tag + " doesn't exist!");
			return false;
		});
		set("setLuaSpriteScrollFactor", function(tag:String, scrollX:Float, scrollY:Float)
		{
			luaTrace("setLuaSpriteScrollFactor is deprecated! Use setScrollFactor instead", false, true);
			if (getSpriteMap().exists(tag))
			{
				getSpriteMap().get(tag).scrollFactor.set(scrollX, scrollY);
				return true;
			}
			return false;
		});
		set("scaleLuaSprite", function(tag:String, x:Float, y:Float)
		{
			luaTrace("scaleLuaSprite is deprecated! Use scaleObject instead", false, true);
			if (getSpriteMap().exists(tag))
			{
				var shit:ModchartSprite = getSpriteMap().get(tag);
				shit.scale.set(x, y);
				shit.updateHitbox();
				return true;
			}
			return false;
		});
		set("getPropertyLuaSprite", function(tag:String, variable:String)
		{
			luaTrace("getPropertyLuaSprite is deprecated! Use getProperty instead", false, true);
			if (getSpriteMap().exists(tag))
			{
				var killMe:Array<String> = variable.split('.');
				if (killMe.length > 1)
				{
					var coverMeInPiss:Dynamic = Reflect.getProperty(getSpriteMap().get(tag), killMe[0]);
					for (i in 1...killMe.length - 1)
					{
						coverMeInPiss = Reflect.getProperty(coverMeInPiss, killMe[i]);
					}
					return Reflect.getProperty(coverMeInPiss, killMe[killMe.length - 1]);
				}
				return Reflect.getProperty(getSpriteMap().get(tag), variable);
			}
			return null;
		});
		set("setPropertyLuaSprite", function(tag:String, variable:String, value:Dynamic)
		{
			luaTrace("setPropertyLuaSprite is deprecated! Use setProperty instead", false, true);
			if (getSpriteMap().exists(tag))
			{
				var killMe:Array<String> = variable.split('.');
				if (killMe.length > 1)
				{
					var coverMeInPiss:Dynamic = Reflect.getProperty(getSpriteMap().get(tag), killMe[0]);
					for (i in 1...killMe.length - 1)
					{
						coverMeInPiss = Reflect.getProperty(coverMeInPiss, killMe[i]);
					}
					Reflect.setProperty(coverMeInPiss, killMe[killMe.length - 1], value);
					return true;
				}
				Reflect.setProperty(getSpriteMap().get(tag), variable, value);
				return true;
			}
			luaTrace("setPropertyLuaSprite: Lua sprite with tag: " + tag + " doesn't exist!");
			return false;
		});
		set("musicFadeIn", function(duration:Float, fromValue:Float = 0, toValue:Float = 1)
		{
			FlxG.sound.music.fadeIn(duration, fromValue, toValue);
			luaTrace('musicFadeIn is deprecated! Use soundFadeIn instead.', false, true);
		});
		set("musicFadeOut", function(duration:Float, toValue:Float = 0)
		{
			FlxG.sound.music.fadeOut(duration, toValue);
			luaTrace('musicFadeOut is deprecated! Use soundFadeOut instead.', false, true);
		});

		// Other stuff
		set("stringStartsWith", function(str:String, start:String)
		{
			return str.startsWith(start);
		});
		set("stringEndsWith", function(str:String, end:String)
		{
			return str.endsWith(end);
		});
		set("stringSplit", function(str:String, split:String)
		{
			return str.split(split);
		});
		set("stringTrim", function(str:String)
		{
			return str.trim();
		});

		set("directoryFileList", function(folder:String)
		{
			var list:Array<String> = [];
			#if sys
			if (FileSystem.exists(folder))
			{
				for (folder in FileSystem.readDirectory(folder))
				{
					if (!list.contains(folder))
					{
						list.push(folder);
					}
				}
			}
			#end
			return list;
		});

		// Require functions
		set("addRequirePath", function(path:String)
		{
			#if LUA_ALLOWED
			LuaRequire.addPath(lua, path);
			#end
		});

		set("clearRequireCache", function(?modname:String)
		{
			#if LUA_ALLOWED
			LuaRequire.clearCache(lua, modname);
			#end
		});

		// Engine Custom ES dialect: register the extra functions the ES engine provides
		ESCompat.register(this);

		for (name => func in customFunctions)
		{
			if (func != null)
				set(name, func);
			// Lua_helper.add_callback(lua, name, func);
		}

		if (Lua_helper.callbacks != null)
		{
			for (i => value in Lua_helper.callbacks)
			{ // 直接遍历键值对
				Convert.toLua(lua, value);
				Lua.setglobal(lua, i);
			}
		}

		// Engine Custom ES has no setObjectCamera; ES scripts probe for it with
		// `if setObjectCamera then`, so it must be nil in menu states.
		// Done after the Lua_helper.callbacks re-application above, which would otherwise
		// restore the base setObjectCamera registration.
		if (menuMode)
		{
			Lua.pushnil(lua);
			Lua.setglobal(lua, 'setObjectCamera');

			// camFollowPos/camFollow move the menu camera so the content point (x, y) lands
			// on the screen center (the menu camera rests scrolled half a screen, i.e. the
			// content origin (0, 0) starts centered). FreeplayState.lua uses this to slide
			// the Min1/Min4 previews when the song selection changes.
			set("camFollowPos", function(x:Float = 0, y:Float = 0)
			{
				FlxG.camera.scroll.set(x - FlxG.width / 2, y - FlxG.height / 2);
			});
			set("camFollow", function(x:Float = 0, y:Float = 0)
			{
				FlxG.camera.scroll.set(x - FlxG.width / 2, y - FlxG.height / 2);
			});
		}

		// NOW execute the loaded script after all functions are registered
		trace('Executing lua script: ' + scriptName);
		var runStatus:Int = Lua.pcall(lua, 0, 0, 0);
		if (runStatus != Lua.LUA_OK)
		{
			var err:String = Lua.tostring(lua, -1);
			Lua.pop(lua, 1);
			trace('Error running lua script! ' + err);
			#if (windows || android)
			CoolUtil.showPopUp(err, 'Error running lua script!');
			#else
			luaTrace('Error running lua script: "$scriptName"\n' + err, true, false, FlxColor.RED);
			#end
			Lua.close(lua);
			lua = null;
			return;
		}

		// Menu-state scripts get their onCreate from LuaSState.create() instead, so it runs
		// after the ES camera layout (scrolled camGame + raw camHUD) is in place and only once
		if (!menuMode)
			call('onCreate', []);
		#end
	}

	public static function isOfTypes(value:Any, types:Array<Dynamic>)
	{
		for (type in types)
		{
			if (Std.isOfType(value, type))
				return true;
		}
		return false;
	}

	// ------------------------------------------------------------------------
	// "Engine Custom ES" compatibility helpers
	// ------------------------------------------------------------------------

	/** Registry holding this script's Lua sprites. */
	public function spriteMap():Map<String, ModchartSprite>
	{
		var playState:PlayState = PlayState.instance;
		return (menuMode || playState == null) ? menuSprites : playState.modchartSprites;
	}

	/** Registry holding this script's Lua texts. */
	public function textMap():Map<String, ModchartText>
	{
		var playState:PlayState = PlayState.instance;
		return (menuMode || playState == null) ? menuTexts : playState.modchartTexts;
	}

	/** Registry holding this script's tweens. */
	public function tweenMap():Map<String, FlxTween>
	{
		var playState:PlayState = PlayState.instance;
		return (menuMode || playState == null) ? menuTweens : playState.modchartTweens;
	}

	/** Registry holding this script's timers. */
	public function timerMap():Map<String, FlxTimer>
	{
		var playState:PlayState = PlayState.instance;
		return (menuMode || playState == null) ? menuTimers : playState.modchartTimers;
	}

	/** Registry holding this script's sounds. */
	public function soundMap():Map<String, FlxSound>
	{
		var playState:PlayState = PlayState.instance;
		return (menuMode || playState == null) ? menuSounds : playState.modchartSounds;
	}

	/** State this script adds its objects to. */
	public function getTargetState():FlxState
	{
		if (menuMode)
			return menuOwner != null ? menuOwner : FlxG.state;
		if (PlayState.instance != null)
			return PlayState.instance.isDead ? GameOverSubstate.instance : PlayState.instance;
		return FlxG.state;
	}

	/**
	 * Broadcasts a script callback. Gameplay scripts broadcast to every Lua script like
	 * `PlayState.callOnLuas` does, menu scripts only call themselves.
	 */
	public function dispatchCall(event:String, args:Array<Dynamic>):Void
	{
		var playState:PlayState = PlayState.instance;
		if (!menuMode && playState != null)
		{
			playState.callOnLuas(event, args);
			return;
		}
		call(event, args);
	}

	/** True while the Lua code currently executing belongs to a menu script. */
	public static function inMenuContext():Bool
	{
		if (lastCalledScript != null && lastCalledScript.menuMode)
			return true;
		return PlayState.instance == null;
	}

	/** The menu script the static helpers below should use, if any. */
	public static function getMenuScript():FunkinLua
	{
		var script = lastCalledScript;
		if (script != null && script.menuMode && !script.closed)
			return script;

		for (i in 0...menuScripts.length)
		{
			// Prefer the most recently created script (scripts of menu states
			// that were skipped by switchState() never get stopped)
			var script = menuScripts[menuScripts.length - 1 - i];
			if (script.menuMode && !script.closed)
				return script;
		}
		return null;
	}

	public static function getSpriteMap():Map<String, ModchartSprite>
	{
		var playState:PlayState = PlayState.instance;
		if (!inMenuContext() && playState != null)
			return playState.modchartSprites;

		var script = getMenuScript();
		return script != null ? script.menuSprites : looseSprites;
	}

	public static function getTextMap():Map<String, ModchartText>
	{
		var playState:PlayState = PlayState.instance;
		if (!inMenuContext() && playState != null)
			return playState.modchartTexts;

		var script = getMenuScript();
		return script != null ? script.menuTexts : looseTexts;
	}

	public static function getTweenMap():Map<String, FlxTween>
	{
		var playState:PlayState = PlayState.instance;
		if (!inMenuContext() && playState != null)
			return playState.modchartTweens;

		var script = getMenuScript();
		return script != null ? script.menuTweens : looseTweens;
	}

	public static function getTimerMap():Map<String, FlxTimer>
	{
		var playState:PlayState = PlayState.instance;
		if (!inMenuContext() && playState != null)
			return playState.modchartTimers;

		var script = getMenuScript();
		return script != null ? script.menuTimers : looseTimers;
	}

	public static function getSoundMap():Map<String, FlxSound>
	{
		var playState:PlayState = PlayState.instance;
		if (!inMenuContext() && playState != null)
			return playState.modchartSounds;

		var script = getMenuScript();
		return script != null ? script.menuSounds : looseSounds;
	}

	public static function getVariablesMap():Map<String, Dynamic>
	{
		var playState:PlayState = PlayState.instance;
		if (!inMenuContext() && playState != null)
			return playState.variables;
		return menuVariables;
	}

	/** Lua objects of ES scripts that aren't Lua sprites/texts (characters, videos, backdrops...). */
	public static function setESObject(tag:String, obj:Dynamic):Void
	{
		var playState:PlayState = PlayState.instance;
		if (inMenuContext() || playState == null)
			menuVariables.set(tag, obj);
		else
			playState.variables.set(tag, obj);
	}

	/** Look up any Lua object, in gameplay as well as in menu states. */
	public static function getLuaObjectSafe(obj:String, ?text:Bool = true, ?video:Bool = true):Dynamic
	{
		var playState:PlayState = PlayState.instance;
		if (playState != null && !inMenuContext())
			return playState.getLuaObject(obj, text, video);

		if (getSpriteMap().exists(obj))
			return getSpriteMap().get(obj);
		if (text && getTextMap().exists(obj))
			return getTextMap().get(obj);
		if (menuVariables.exists(obj))
		{
			var variable:Dynamic = menuVariables.get(obj);
			if (Std.isOfType(variable, FlxSprite))
				return cast variable;
		}

		var cam:FlxCamera = menuCameraObject(obj);
		if (cam != null)
			return cam;
		return null;
	}

	/** Menu states have camGame (scrolled) plus a raw camHUD for ES scripts. */
	public static function menuCameraObject(name:String):FlxCamera
	{
		if (PlayState.instance != null && !inMenuContext())
			return null;

		switch (name.toLowerCase())
		{
			case 'camhud' | 'hud':
				var luaState:LuaSState = Std.downcast(currentMenuState, LuaSState);
				if (luaState != null && luaState.camHUD != null)
					return luaState.camHUD;
				return FlxG.camera;
			case 'camgame' | 'camother' | 'camvideo' | 'camera':
				return FlxG.camera;
		}
		return null;
	}

	/** `PlayState.getControl` that also works while no song is running. */
	public static function getControlSafe(key:String):Bool
	{
		var playState:PlayState = PlayState.instance;
		if (playState != null && !(lastCalledScript != null && lastCalledScript.menuMode))
			return playState.getControl(key);

		var player1 = backend.player.PlayerSettings.player1;
		if (player1 == null || player1.controls == null)
			return false;

		return Reflect.getProperty(player1.controls, key) == true;
	}

	#if hscript
	public function initHaxeModule()
	{
		if (hscript == null)
		{
			trace('initializing haxe interp for: $scriptName');
			hscript = new HScripts(); // TO DO: Fix issue with 2 scripts not being able to use the same variable names
		}
	}
	#end

	public static function setVarInArray(instance:Dynamic, variable:String, value:Dynamic):Any
	{
		var shit:Array<String> = variable.split('[');
		if (shit.length > 1)
		{
			var blah:Dynamic = null;
			if (getVariablesMap().exists(shit[0]))
			{
				var retVal:Dynamic = getVariablesMap().get(shit[0]);
				if (retVal != null)
					blah = retVal;
			}
			else
				blah = Reflect.getProperty(instance, shit[0]);

			for (i in 1...shit.length)
			{
				var leNum:Dynamic = shit[i].substr(0, shit[i].length - 1);
				if (i >= shit.length - 1) // Last array
					blah[leNum] = value;
				else // Anything else
					blah = blah[leNum];
			}
			return blah;
		}
		/*if(Std.isOfType(instance, Map))
				instance.set(variable,value);
			else */

		if (getVariablesMap().exists(variable))
		{
			getVariablesMap().set(variable, value);
			return true;
		}

		Reflect.setProperty(instance, variable, value);
		return true;
	}

	public static function getVarInArray(instance:Dynamic, variable:String):Any
	{
		var shit:Array<String> = variable.split('[');
		if (shit.length > 1)
		{
			var blah:Dynamic = null;
			if (getVariablesMap().exists(shit[0]))
			{
				var retVal:Dynamic = getVariablesMap().get(shit[0]);
				if (retVal != null)
					blah = retVal;
			}
			else
				blah = Reflect.getProperty(instance, shit[0]);

			for (i in 1...shit.length)
			{
				var leNum:Dynamic = shit[i].substr(0, shit[i].length - 1);
				blah = blah[leNum];
			}
			return blah;
		}

		if (getVariablesMap().exists(variable))
		{
			var retVal:Dynamic = getVariablesMap().get(variable);
			if (retVal != null)
				return retVal;
		}

		return Reflect.getProperty(instance, variable);
	}

	static function getTextObject(name:String):FlxText
	{
		var texts:Map<String, ModchartText> = getTextMap();
		if (texts.exists(name))
			return texts.get(name);

		return Reflect.getProperty(getInstance(), name);
	}

	public static function callMethodFromObject(classObj:Dynamic, funcStr:String, args:Array<Dynamic> = null)
	{
		if (args == null)
			args = [];

		var split:Array<String> = funcStr.split('.');
		var funcToRun:Function = null;
		var obj:Dynamic = classObj;
		// trace('start: ' + obj);
		if (obj == null)
		{
			trace('Error: classObj is null');
			return null;
		}

		for (i in 0...split.length)
		{
			obj = getVarInArray(obj, split[i].trim());
			if (obj == null)
			{
				trace('Error: Property not found: ' + split[i]);
				return null;
			}
			// trace(obj, split[i]);
		}

		funcToRun = cast obj;
		// trace('end: $obj');
		if (funcToRun == null)
		{
			trace('Error: Function not found: ' + funcStr);
			return null;
		}
		return Reflect.callMethod(obj, funcToRun, args);
	}

	static function parseInstances(args:Array<Dynamic>)
	{
		for (i in 0...args.length)
		{
			var myArg:String = cast args[i];
			if (myArg != null && myArg.length > instanceStr.length)
			{
				var index:Int = myArg.indexOf('::');
				if (index > -1)
				{
					myArg = myArg.substring(index + 2);
					// trace('Op1: $myArg');
					var lastIndex:Int = myArg.lastIndexOf('::');

					var split:Array<String> = myArg.split('.');
					args[i] = (lastIndex > -1) ? Type.resolveClass(myArg.substring(0, lastIndex)) : PlayState.instance;
					if (args[i] == null)
					{
						trace('Error: Class not found: ' + myArg.substring(0, lastIndex));
						continue;
					}
					for (j in 0...split.length)
					{
						// trace('Op2: ${Type.getClass(args[i])}, ${split[j]}');
						args[i] = getVarInArray(args[i], split[j].trim());
						if (args[i] == null)
						{
							trace('Error: Property not found: ' + split[j]);
							break;
						}
						// trace('Op3: ${args[i] != null ? Type.getClass(args[i]) : null}');
					}
				}
			}
		}
		return args;
	}

	#if (!flash && sys)
	public function getShader(obj:String):FlxRuntimeShader
	{
		var killMe:Array<String> = obj.split('.');
		var leObj:FlxSprite = getObjectDirectly(killMe[0]);
		if (killMe.length > 1)
		{
			leObj = getVarInArray(getPropertyLoopThingWhatever(killMe), killMe[killMe.length - 1]);
		}

		if (leObj != null)
		{
			var shader:Dynamic = leObj.shader;
			var shader:FlxRuntimeShader = shader;
			return shader;
		}

		// ES dialect: shaders are created with makeShader() and used through their own tag
		return ESCompat.getShader(this, obj);
	}
	#end

	function initLuaShader(name:String)
	{
		if (!ClientPrefs.shaders)
			return false;

		#if (!flash && sys)
		if (PlayState.instance == null)
		{
			luaTrace('initLuaShader: Runtime shaders are only available while a song is playing!', false, false, FlxColor.RED);
			return false;
		}

		if (PlayState.instance.runtimeShaders.exists(name))
		{
			luaTrace('Shader $name was already initialized!');
			return true;
		}

		var foldersToCheck:Array<String> = [SUtil.getPath() + Paths.getPreloadPath('shaders/')];

		if (Paths.currentModDirectory != null && Paths.currentModDirectory.length > 0)
			foldersToCheck.insert(0, Paths.mods(Paths.currentModDirectory + '/shaders/'));

		for (mod in Paths.getGlobalMods())
			foldersToCheck.insert(0, Paths.mods(mod + '/shaders/'));

		for (folder in foldersToCheck)
		{
			if (FileSystem.exists(folder))
			{
				var frag:String = folder + name + '.frag';
				var vert:String = folder + name + '.vert';
				var found:Bool = false;
				if (FileSystem.exists(frag))
				{
					frag = File.getContent(frag);
					found = true;
				}
				else
					frag = null;

				if (FileSystem.exists(vert))
				{
					vert = File.getContent(vert);
					found = true;
				}
				else
					vert = null;

				if (found)
				{
					PlayState.instance.runtimeShaders.set(name, [frag, vert]);
					// trace('Found shader $name!');
					return true;
				}
			}
		}
		luaTrace('Missing shader $name .frag AND .vert files!', false, false, FlxColor.RED);
		#else
		luaTrace('This platform doesn\'t support Runtime Shaders!', false, false, FlxColor.RED);
		#end
		return false;
	}

	function getTargetInstance()
	{
		if (menuMode || PlayState.instance == null)
			return getTargetState();
		return PlayState.instance.isDead ? GameOverSubstate.instance : PlayState.instance;
	}

	function getLowestCharacterGroup():FlxSpriteGroup
	{
		var group:FlxSpriteGroup = PlayState.instance.gfGroup;
		var pos:Int = PlayState.instance.members.indexOf(group);

		var newPos:Int = PlayState.instance.members.indexOf(PlayState.instance.boyfriendGroup);
		if (newPos < pos)
		{
			group = PlayState.instance.boyfriendGroup;
			pos = newPos;
		}

		newPos = PlayState.instance.members.indexOf(PlayState.instance.dadGroup);
		if (newPos < pos)
		{
			group = PlayState.instance.dadGroup;
			pos = newPos;
		}
		return group;
	}

	function getGroupStuff(leArray:Dynamic, variable:String)
	{
		var killMe:Array<String> = variable.split('.');
		if (killMe.length > 1)
		{
			var coverMeInPiss:Dynamic = Reflect.getProperty(leArray, killMe[0]);
			for (i in 1...killMe.length - 1)
			{
				coverMeInPiss = Reflect.getProperty(coverMeInPiss, killMe[i]);
			}
			switch (Type.typeof(coverMeInPiss))
			{
				case ValueType.TClass(haxe.ds.StringMap) | ValueType.TClass(haxe.ds.ObjectMap) | ValueType.TClass(haxe.ds.IntMap) | ValueType.TClass(haxe.ds.EnumValueMap):
					return coverMeInPiss.get(killMe[killMe.length - 1]);
				default:
					return Reflect.getProperty(coverMeInPiss, killMe[killMe.length - 1]);
			};
		}
		switch (Type.typeof(leArray))
		{
			case ValueType.TClass(haxe.ds.StringMap) | ValueType.TClass(haxe.ds.ObjectMap) | ValueType.TClass(haxe.ds.IntMap) | ValueType.TClass(haxe.ds.EnumValueMap):
				return leArray.get(variable);
			default:
				return Reflect.getProperty(leArray, variable);
		};
	}

	function loadFrames(spr:FlxSprite, image:String, spriteType:String)
	{
		switch (spriteType.toLowerCase().trim())
		{
			case "texture" | "textureatlas" | "tex":
				spr.frames = AtlasFrameMaker.construct(image);

			case "texture_noaa" | "textureatlas_noaa" | "tex_noaa":
				spr.frames = AtlasFrameMaker.construct(image, null, true);

			case "packer" | "packeratlas" | "pac":
				spr.frames = Paths.getPackerAtlas(image);

			default:
				spr.frames = Paths.getSparrowAtlas(image);
		}
	}

	function setGroupStuff(leArray:Dynamic, variable:String, value:Dynamic)
	{
		var killMe:Array<String> = variable.split('.');
		if (killMe.length > 1)
		{
			var coverMeInPiss:Dynamic = Reflect.getProperty(leArray, killMe[0]);
			for (i in 1...killMe.length - 1)
			{
				coverMeInPiss = Reflect.getProperty(coverMeInPiss, killMe[i]);
			}
			Reflect.setProperty(coverMeInPiss, killMe[killMe.length - 1], value);
			return;
		}
		Reflect.setProperty(leArray, variable, value);
	}

	function resetTextTag(tag:String)
	{
		if (!getTextMap().exists(tag))
		{
			return;
		}

		var pee:ModchartText = getTextMap().get(tag);
		pee.kill();
		if (pee.wasAdded)
		{
			var state:FlxState = getTargetState();
			if (state != null)
				state.remove(pee, true);
		}
		pee.destroy();
		getTextMap().remove(tag);
	}

	function resetSpriteTag(tag:String)
	{
		if (!getSpriteMap().exists(tag))
		{
			return;
		}

		var pee:ModchartSprite = getSpriteMap().get(tag);

		pee.kill();
		if (pee.wasAdded)
		{
			var state:FlxState = getTargetState();
			if (state != null)
				state.remove(pee, true);
		}
		pee.destroy();

		getSpriteMap().remove(tag);
	}

	function resetVideoSpriteTag(tag:String)
	{
		if (!PlayState.instance.modchartVideo.exists(tag))
		{
			return;
		}

		var pee:ModchartVideoSprite = PlayState.instance.modchartVideo.get(tag);

		if (pee.destroyOnUse)
		{
			PlayState.instance.remove(pee, true);
		}
		pee.destroy();

		PlayState.instance.modchartVideo.remove(tag);
	}

	function cancelTween(tag:String)
	{
		if (getTweenMap().exists(tag))
		{
			getTweenMap().get(tag).cancel();
			getTweenMap().get(tag).destroy();
			getTweenMap().remove(tag);
		}

		if (tag == null || !Std.isOfType(FlxG.state, MusicBeatState))
			return;

		// startTween keeps its tween in the state's variables under a 'tween_' key instead of the tween map
		var variables:Map<String, Dynamic> = MusicBeatState.getVariables();
		var tweenKey:String = 'tween_' + formatVariable(tag);
		var stored:Dynamic = variables.get(tweenKey);
		if (Std.isOfType(stored, FlxTween))
		{
			var tween:FlxTween = cast stored;
			tween.cancel();
			tween.destroy();
			variables.remove(tweenKey);
		}
	}

	function tweenShit(tag:String, vars:String)
	{
		cancelTween(tag);
		var variables:Array<String> = vars.split('.');
		var sexyProp:Dynamic = getObjectDirectly(variables[0]);
		if (variables.length > 1)
		{
			sexyProp = getVarInArray(getPropertyLoopThingWhatever(variables), variables[variables.length - 1]);
		}
		return sexyProp;
	}

	function cancelTimer(tag:String)
	{
		if (getTimerMap().exists(tag))
		{
			var theTimer:FlxTimer = getTimerMap().get(tag);
			theTimer.cancel();
			theTimer.destroy();
			getTimerMap().remove(tag);
		}
	}

	public static function getTypeByString(?type:String = '')
	{
		switch (type.toLowerCase().trim())
		{
			case 'backward':
				return FlxTweenType.BACKWARD;
			case 'looping' | 'loop':
				return FlxTweenType.LOOPING;
			case 'persist':
				return FlxTweenType.PERSIST;
			case 'pingpong':
				return FlxTweenType.PINGPONG;
		}
		return FlxTweenType.ONESHOT;
	}

	// Better optimized than using some getProperty shit or idk
	public static function getFlxEaseByString(?ease:String = '')
	{
		if (ease == null)
			return FlxEase.linear;

		switch (ease.toLowerCase().trim())
		{
			case 'backin':
				return FlxEase.backIn;
			case 'backinout':
				return FlxEase.backInOut;
			case 'backout':
				return FlxEase.backOut;
			case 'bouncein':
				return FlxEase.bounceIn;
			case 'bounceinout':
				return FlxEase.bounceInOut;
			case 'bounceout':
				return FlxEase.bounceOut;
			case 'circin':
				return FlxEase.circIn;
			case 'circinout':
				return FlxEase.circInOut;
			case 'circout':
				return FlxEase.circOut;
			case 'cubein':
				return FlxEase.cubeIn;
			case 'cubeinout':
				return FlxEase.cubeInOut;
			case 'cubeout':
				return FlxEase.cubeOut;
			case 'elasticin':
				return FlxEase.elasticIn;
			case 'elasticinout':
				return FlxEase.elasticInOut;
			case 'elasticout':
				return FlxEase.elasticOut;
			case 'expoin':
				return FlxEase.expoIn;
			case 'expoinout':
				return FlxEase.expoInOut;
			case 'expoout':
				return FlxEase.expoOut;
			case 'quadin':
				return FlxEase.quadIn;
			case 'quadinout':
				return FlxEase.quadInOut;
			case 'quadout':
				return FlxEase.quadOut;
			case 'quartin':
				return FlxEase.quartIn;
			case 'quartinout':
				return FlxEase.quartInOut;
			case 'quartout':
				return FlxEase.quartOut;
			case 'quintin':
				return FlxEase.quintIn;
			case 'quintinout':
				return FlxEase.quintInOut;
			case 'quintout':
				return FlxEase.quintOut;
			case 'sinein':
				return FlxEase.sineIn;
			case 'sineinout':
				return FlxEase.sineInOut;
			case 'sineout':
				return FlxEase.sineOut;
			case 'smoothstepin':
				return FlxEase.smoothStepIn;
			case 'smoothstepinout':
				return FlxEase.smoothStepInOut;
			case 'smoothstepout':
				return FlxEase.smoothStepInOut;
			case 'smootherstepin':
				return FlxEase.smootherStepIn;
			case 'smootherstepinout':
				return FlxEase.smootherStepInOut;
			case 'smootherstepout':
				return FlxEase.smootherStepOut;
		}
		return FlxEase.linear;
	}

	public static function blendModeFromString(blend:String):BlendMode
	{
		switch (blend.toLowerCase().trim())
		{
			case 'add':
				return ADD;
			case 'alpha':
				return ALPHA;
			case 'darken':
				return DARKEN;
			case 'difference':
				return DIFFERENCE;
			case 'erase':
				return ERASE;
			case 'hardlight':
				return HARDLIGHT;
			case 'invert':
				return INVERT;
			case 'layer':
				return LAYER;
			case 'lighten':
				return LIGHTEN;
			case 'multiply':
				return MULTIPLY;
			case 'overlay':
				return OVERLAY;
			case 'screen':
				return SCREEN;
			case 'shader':
				return SHADER;
			case 'subtract':
				return SUBTRACT;
		}
		return NORMAL;
	}

	public static function cameraFromString(cam:String):FlxCamera
	{
		if (PlayState.instance == null || (lastCalledScript != null && lastCalledScript.menuMode))
		{
			// ES menu dialect: camHUD is a raw (unscrolled) camera, camGame is scrolled
			var luaState:LuaSState = Std.downcast(currentMenuState, LuaSState);
			if (luaState != null && luaState.camHUD != null)
			{
				switch (cam.toLowerCase())
				{
					case 'camhud' | 'hud' | 'camother' | 'other':
						return luaState.camHUD;
				}
			}
			return FlxG.camera;
		}

		switch (cam.toLowerCase())
		{
			case 'camhud' | 'hud':
				return PlayState.instance.camHUD;
			case 'camother' | 'other':
				return PlayState.instance.camOther;
			case 'camvideo' | 'video':
				return PlayState.instance.camVideo;
		}
		return PlayState.instance.camGame;
	}

	public function luaTrace(text:String, ignoreCheck:Bool = false, deprecated:Bool = false, color:FlxColor = FlxColor.WHITE)
	{
		#if LUA_ALLOWED
		if (ignoreCheck || getBool('luaDebugMode'))
		{
			if (deprecated && !getBool('luaDeprecatedWarnings'))
			{
				return;
			}
			if (PlayState.instance != null && !menuMode)
				PlayState.instance.addTextToDebug(text, color);
			trace(text);
		}
		#end
	}

	function getErrorMessage(status:Int):String
	{
		#if LUA_ALLOWED
		var v:String = Lua.tostring(lua, -1);
		Lua.pop(lua, 1);

		if (v != null)
			v = v.trim();
		if (v == null || v == "")
		{
			switch (status)
			{
				case Lua.LUA_ERRRUN:
					return "Runtime Error";
				case Lua.LUA_ERRMEM:
					return "Memory Allocation Error";
				case Lua.LUA_ERRERR:
					return "Critical Error";
			}
			return "Unknown Error";
		}

		return v;
		#end
		return null;
	}

	public var lastCalledFunction:String = '';

	public static var lastCalledScript:FunkinLua = null;

	public function call(func:String, args:Array<Dynamic>):Dynamic
	{
		if (closed)
			return GlobalScript.Function_Continue;

		lastCalledFunction = func;
		lastCalledScript = this;
		try
		{
			if (lua == null)
				return GlobalScript.Function_Continue;

			Lua.getglobal(lua, func);
			var type:Int = Lua.type(lua, -1);
			// The prebuilt Luau libraries and the vendored lua.h don't necessarily share the
			// same type-tag enum (recent Luau inserts LUA_TINTEGER after LUA_TNUMBER), which
			// makes Lua.LUA_TFUNCTION unreliable. Ask the linked VM for the type name instead.
			var typeName:String = Lua.typename(lua, type);

			if (typeName != 'function')
			{
				if (type > Lua.LUA_TNIL)
					luaTrace("ERROR (" + func + "): attempt to call a " + typeName + " value", false, false, FlxColor.RED);

				Lua.pop(lua, 1);
				return GlobalScript.Function_Continue;
			}

			for (arg in args)
				Convert.toLua(lua, arg);

			// ES dialect: onEventSet receives the current step, stepEvent() needs to know it
			if (func == 'onEventSet' && args.length > 0 && args[0] != null)
				lastEventSetStep = Std.int(cast args[0]);

			// ES dialect: per frame housekeeping (onPlayAnim emulation, camera rules)
			if (func == 'onUpdate')
				ESCompat.tick(this);

			var status:Int = Lua.pcall(lua, args.length, 1, 0);

			// Checks if it's not successful, then show a error.
			if (status != Lua.LUA_OK)
			{
				var error:String = getErrorMessage(status);
				luaTrace("ERROR (" + func + "): " + error, false, false, FlxColor.RED);
				return GlobalScript.Function_Continue;
			}

			// If successful, pass and then return the result.
			var result:Dynamic = cast Convert.fromLua(lua, -1);
			if (result == null)
				result = GlobalScript.Function_Continue;

			Lua.pop(lua, 1);
			if (closed)
				stop();
			return result;
		}
		catch (e:Dynamic)
		{
			trace(e);
			trace(haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
		}
		return GlobalScript.Function_Continue;
	}

	static function addAnimByIndices(obj:String, name:String, prefix:String, indices:String, framerate:Int = 24, loop:Bool = false)
	{
		var strIndices:Array<String> = indices.trim().split(',');
		var die:Array<Int> = [];
		for (i in 0...strIndices.length)
		{
			die.push(Std.parseInt(strIndices[i]));
		}

		if (getLuaObjectSafe(obj, false) != null)
		{
			var pussy:FlxSprite = getLuaObjectSafe(obj, false);
			pussy.animation.addByIndices(name, prefix, die, '', framerate, loop);
			if (pussy.animation.curAnim == null)
			{
				pussy.animation.play(name, true);
			}
			return true;
		}

		var pussy:FlxSprite = Reflect.getProperty(getInstance(), obj);
		if (pussy != null)
		{
			pussy.animation.addByIndices(name, prefix, die, '', framerate, loop);
			if (pussy.animation.curAnim == null)
			{
				pussy.animation.play(name, true);
			}
			return true;
		}
		return false;
	}

	public static function getPropertyLoopThingWhatever(killMe:Array<String>, ?checkForTextsToo:Bool = true, ?getProperty:Bool = true):Dynamic
	{
		var coverMeInPiss:Dynamic = getObjectDirectly(killMe[0], checkForTextsToo);
		var end = killMe.length;
		if (getProperty)
			end = killMe.length - 1;

		for (i in 1...end)
		{
			coverMeInPiss = getVarInArray(coverMeInPiss, killMe[i]);
		}
		return coverMeInPiss;
	}

	function formatVariable(tag:String)
		return tag.trim().replace(' ', '_').replace('.', '');

	function getLuaTween(options:Dynamic)
	{
		return {
			type: getTypeByString(options.type),
			startDelay: options.startDelay,
			onUpdate: options.onUpdate,
			onStart: options.onStart,
			onComplete: options.onComplete,
			loopDelay: options.loopDelay,
			ease: getFlxEaseByString(options.ease)
		};
	}

	function tweenPrepare(tag:String, vars:String)
	{
		if (tag != null)
			cancelTween(tag);
		var variables:Array<String> = vars.split('.');
		var sexyProp:Dynamic = getObjectDirectly(variables[0]);
		if (variables.length > 1)
			sexyProp = getVarInArray(getPropertyLoopThingWhatever(variables), variables[variables.length - 1]);
		return sexyProp;
	}

	public static function getObjectDirectly(objectName:String, ?checkForTextsToo:Bool = true):Dynamic
	{
		var coverMeInPiss:Dynamic = getLuaObjectSafe(objectName, checkForTextsToo);
		if (coverMeInPiss == null)
			coverMeInPiss = getVarInArray(getInstance(), objectName);

		return coverMeInPiss;
	}

	public function set(variable:String, data:Dynamic)
	{
		#if LUA_ALLOWED
		if (lua == null)
			return;

		if (Type.typeof(data) == TFunction)
		{
			Lua_helper.add_callback(lua, variable, data);
			// CRITICAL: Also store in global function table for Luau compatibility
			// This prevents "attempt to call a nil value" errors in scripts
			Convert.toLua(lua, data);
			Lua.setglobal(lua, variable);
			return;
		}

		Convert.toLua(lua, data);
		Lua.setglobal(lua, variable);
		#end
	}

	public function addLocalCallback(name:String, myFunction:Dynamic)
	{
		callbacks.set(name, myFunction);
		Lua_helper.add_callback(lua, name, null); // just so that it gets called
	}

	#if LUA_ALLOWED
	public function getBool(variable:String)
	{
		var result:String = null;
		Lua.getglobal(lua, variable);
		result = Convert.fromLua(lua, -1);
		Lua.pop(lua, 1);

		if (result == null)
		{
			return false;
		}
		return (result == 'true');
	}
	#end

	public function stop()
	{
		#if LUA_ALLOWED
		if (lua != null)
		{
			Lua.close(lua);
			lua = null;
		}
		#end

		if (menuMode)
		{
			ESCompat.cleanup(this);
			cancelMenuData();
			menuScripts.remove(this);
			if (menuScripts.length == 0)
				menuVariables.clear();
		}
		closed = true;
	}

	/** Destroys every tween/timer/sound a menu script created, used when its state dies. */
	public function cancelMenuData():Void
	{
		for (tag => tween in menuTweens)
		{
			tween.cancel();
			tween.destroy();
		}
		menuTweens.clear();

		for (tag => timer in menuTimers)
		{
			timer.cancel();
			timer.destroy();
		}
		menuTimers.clear();

		for (tag => sound in menuSounds)
		{
			sound.stop();
		}
		menuSounds.clear();

		menuBackIndex = 0;
	}

	public static function getInstance()
	{
		var playState:PlayState = PlayState.instance;
		if (playState != null && !inMenuContext())
			return playState.isDead ? GameOverSubstate.instance : playState;

		if (currentMenuState != null)
			return currentMenuState;
		return FlxG.state != null ? FlxG.state : playState;
	}

	public function executeLua(codeToRun:String):Dynamic
	{
		return scriptHxLuaCode = codeToRun;
	}
}

class ModchartSprite extends FlxSprite
{
	public var wasAdded:Bool = false;
	public var animOffsets:Map<String, Array<Float>> = new Map<String, Array<Float>>();

	// public var isInFront:Bool = false;

	public function new(?x:Float = 0, ?y:Float = 0)
	{
		super(x, y);
		antialiasing = ClientPrefs.globalAntialiasing;
	}
}

class ModchartVideoSprite extends PsychVideoSprite
{
	public function new(destroyOnUse = true)
	{
		super(destroyOnUse);
		antialiasing = ClientPrefs.globalAntialiasing;
	}
}

/*
	class ModcharGiftSprite extends FlxGifSprite
	{
	//public var wasAdded:Bool = false;
	//public var animOffsets:Map<String, Array<Float>> = new Map<String, Array<Float>>();
	//public var isInFront:Bool = false;

	public function new(?x:Float = 0, ?y:Float = 0)
	{
		super(x, y);
		antialiasing = ClientPrefs.globalAntialiasing;
	}
	}
 */
class LuaSState extends MusicBeatState
{
	public var lua:FunkinLua;

	// ES menu dialect camera: raw (unscrolled) HUD camera for setCam('camHUD') sprites
	public var camHUD:FlxCamera;

	public function new(fileName:String, globalss:Bool = false)
	{
		super(false);

		trace(fileName);
		FunkinLua.currentMenuState = this;
		if (globalss)
			startLuasOnFolder('states/' + fileName);
		else
		{
			startLuasOnFolder('states/' + fileName + '.lua');
		}

		if (lua == null)
			trace('LuaSState: Couldn\'t find state script "$fileName"!');

		callOnLuas("onLoad", []);
	}

	// TODO: use a macro to auto-generate code to variables.set all variables/methods of MusicBeatState

	public function callOnLuas(event:String, args:Array<Dynamic>, ignoreStops = true, exclusions:Array<String> = null,
			excludeValues:Array<Dynamic> = null):Dynamic
	{
		var returnVal = GlobalScript.Function_Continue;
		#if LUA_ALLOWED
		if (exclusions == null)
			exclusions = [];
		if (excludeValues == null)
			excludeValues = [];

		var myValue = lua.call(event, args);

		if (myValue != null && myValue != GlobalScript.Function_Continue)
		{
			returnVal = myValue;
		}
		#end
		return returnVal;
	}

	public function startLuasOnFolder(luaFile:String)
	{
		trace(luaFile);

		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if (FileSystem.exists(luaToLoad))
		{
			lua = new FunkinLua(luaToLoad, true, this);
			return true;
		}
		else
		{
			luaToLoad = Paths.getPreloadPath(luaFile);
			if (FileSystem.exists(luaToLoad))
			{
				lua = new FunkinLua(luaToLoad, true, this);
				return true;
			}
		}
		#elseif sys
		var luaToLoad:String = Paths.getPreloadPath(luaFile);
		if (OpenFlAssets.exists(luaToLoad))
		{
			lua = new FunkinLua(luaToLoad, true, this);
			return true;
		}
		#end

		trace('LuaSState: State script not found: $luaFile');
		return false;
	}

	public function setOnLuas(variable:String, arg:Dynamic)
	{
		#if LUA_ALLOWED
		lua.set(variable, arg);
		#end
	}

	#if android
	function stringToDPadMode(str:String):FlxDPadMode
	{
		// 获取所有枚举构造器
		var constructs = Type.getEnumConstructs(FlxDPadMode);

		// 检查字符串是否为有效构造器
		if (constructs.indexOf(str) == -1)
		{
			throw '无效的枚举值: $str';
		}

		// 创建枚举实例（无参数）
		return Type.createEnum(FlxDPadMode, str, []);
	}

	function stringToActionMode(str:String):FlxActionMode
	{
		// 获取所有枚举构造器
		var constructs = Type.getEnumConstructs(FlxActionMode);

		// 检查字符串是否为有效构造器
		if (constructs.indexOf(str) == -1)
		{
			throw '无效的枚举值: $str';
		}

		// 创建枚举实例（无参数）
		return Type.createEnum(FlxActionMode, str, []);
	}
	#end

	override function create()
	{
		// ES menu dialect camera layout: camGame scrolled half a screen so lua coords
		// are center-origin, plus a raw camHUD reachable through setCam('camHUD')
		FlxG.camera.scroll.set(-FlxG.width / 2, -FlxG.height / 2);
		camHUD = new FlxCamera();
		camHUD.bgColor = 0;
		FlxG.cameras.add(camHUD, false);

		// UPDATE: realised I should be using the "on" prefix just so if a script needs to call an internal function it doesnt cause issues
		// (Also need to figure out how to give the super to the classes incase that's needed in the on[function] funcs though honestly thats what the post functions are for)
		// I'd love to modify HScript to add override specifically for troll engine hscript
		// THSCript...

		// onCreate is used when the script is created so lol
		if (callOnLuas("onCreate", []) == GlobalScript.Function_Stop) // idk why you'd return stop on create on a hscriptstate but.. sure
			return;

		super.create();
		callOnLuas("onCreatePost", []);
	}

	override function update(e:Float)
	{
		if (callOnLuas("onUpdate", [e]) == GlobalScript.Function_Stop)
			return;

		// Engine Custom ES hook, only for custom menu states
		callOnLuas("onUpdateOptions", [e]);

		super.update(e);

		callOnLuas("onUpdatePost", [e]);
	}

	override function beatHit()
	{
		callOnLuas("onBeatHit", []);
		super.beatHit();
	}

	override function stepHit()
	{
		callOnLuas("onStepHit", []);
		// Engine Custom ES hook: stepEvent() callbacks are registered in onEventSet
		callOnLuas("onEventSet", [curStep]);
		super.stepHit();
	}

	override function destroy()
	{
		// Restore the shared default camera for the next (possibly built-in) state
		FlxG.camera.scroll.set(0, 0);
		if (camHUD != null)
		{
			FlxG.cameras.remove(camHUD);
			camHUD = null;
		}

		if (callOnLuas("onDestroy", []) != GlobalScript.Function_Stop)
			callOnLuas("onDestroyPost", []);

		if (lua != null)
		{
			// Also frees the script's sprites, tweens and timers
			lua.stop();
			lua = null;
		}

		if (FunkinLua.currentMenuState == this)
			FunkinLua.currentMenuState = null;

		super.destroy();
	}
}

class ModchartText extends FlxText
{
	public var wasAdded:Bool = false;

	public function new(x:Float, y:Float, text:String, width:Float)
	{
		super(x, y, width, text, 16);
		setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		// ES menu dialect: texts stay on camGame but with zero scroll factor, so they render
		// at their raw stored coordinates in normal member order (later sprites cover them)
		cameras = [PlayState.instance != null ? PlayState.instance.camHUD : FlxG.camera];
		scrollFactor.set();
		borderSize = 2;
	}
}

class DebugLuaText extends FlxText
{
	private var disableTime:Float = 6;

	public var parentGroup:FlxTypedGroup<DebugLuaText>;

	public function new(text:String, parentGroup:FlxTypedGroup<DebugLuaText>, color:FlxColor)
	{
		this.parentGroup = parentGroup;
		super(10, 10, 0, text, 16);
		setFormat(Paths.font("vcr.ttf"), 16, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scrollFactor.set();
		borderSize = 1;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		disableTime -= elapsed;
		if (disableTime < 0)
			disableTime = 0;
		if (disableTime < 1)
			alpha = disableTime;
	}
}

class CustomSubstate extends MusicBeatSubstate
{
	public static var name:String = 'unnamed';
	public static var instance:CustomSubstate;

	override function create()
	{
		instance = this;

		PlayState.instance.callOnLuas('onCustomSubstateCreate', [name]);
		super.create();
		PlayState.instance.callOnLuas('onCustomSubstateCreatePost', [name]);
	}

	public function new(name:String)
	{
		CustomSubstate.name = name;
		super();
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];
	}

	override function update(elapsed:Float)
	{
		PlayState.instance.callOnLuas('onCustomSubstateUpdate', [name, elapsed]);
		super.update(elapsed);
		PlayState.instance.callOnLuas('onCustomSubstateUpdatePost', [name, elapsed]);
	}

	override function destroy()
	{
		PlayState.instance.callOnLuas('onCustomSubstateDestroy', [name]);
		super.destroy();
	}
}

#if hscript
class HScripts
{
	public static var parser:Parser = new Parser();

	public var interp:Interp;
	public var parentLua:FunkinLua;

	public var variables(get, never):Map<String, Dynamic>;

	public function get_variables()
	{
		return interp.variables;
	}

	public function new()
	{
		interp = new Interp();
		interp.variables.set('FlxG', FlxG);
		interp.variables.set('FlxSprite', FlxSprite);
		interp.variables.set('FlxCamera', FlxCamera);
		interp.variables.set('FlxTimer', FlxTimer);
		interp.variables.set('FlxTween', FlxTween);
		interp.variables.set('FlxEase', FlxEase);
		interp.variables.set('PlayState', PlayState);
		interp.variables.set('LuaMenuState', LuaSState); // ES-Engine style custom menu states
		interp.variables.set('MusicBeatState', backend.MusicBeatState); // scripted state switching (keeps engine transitions)
		interp.variables.set('MusicBeatSubstate', backend.MusicBeatSubstate);
		interp.variables.set('game', PlayState.instance != null ? PlayState.instance : FlxG.state);
		interp.variables.set('Paths', Paths);
		interp.variables.set('Conductor', Conductor);
		interp.variables.set('ClientPrefs', ClientPrefs);
		interp.variables.set('Character', Character);
		interp.variables.set('Alphabet', Alphabet);
		interp.variables.set('CustomSubstate', CustomSubstate);
		#if (!flash && sys)
		interp.variables.set('FlxRuntimeShader', FlxRuntimeShader);
		#end
		interp.variables.set('ShaderFilter', openfl.filters.ShaderFilter);
		interp.variables.set('StringTools', StringTools);

		interp.variables.set('setVar', function(name:String, value:Dynamic)
		{
			FunkinLua.getVariablesMap().set(name, value);
		});
		interp.variables.set('getVar', function(name:String)
		{
			var result:Dynamic = null;
			var vars:Map<String, Dynamic> = FunkinLua.getVariablesMap();
			if (vars.exists(name))
				result = vars.get(name);
			return result;
		});
		interp.variables.set('removeVar', function(name:String)
		{
			var vars:Map<String, Dynamic> = FunkinLua.getVariablesMap();
			if (vars.exists(name))
			{
				vars.remove(name);
				return true;
			}
			return false;
		});

		#if LUA_ALLOWED
		interp.variables.set('createGlobalCallback', function(name:String, func:Dynamic)
		{
			for (script in PlayState.instance.luaArray)
				if (script != null && script.lua != null && !script.closed)
					Lua_helper.add_callback(script.lua, name, func);

			FunkinLua.customFunctions.set(name, func);
		});

		// this one was tested
		interp.variables.set('createCallback', function(name:String, func:Dynamic, ?funk:FunkinLua = null)
		{
			if (funk == null)
				funk = parentLua;

			if (parentLua != null)
				parentLua.addLocalCallback(name, func);
			else
				funk.luaTrace('createCallback ($name): 3rd argument is null', false, false, FlxColor.RED);
		});
		#end
	}

	public function execute(codeToRun:String):Dynamic
	{
		@:privateAccess
		HScripts.parser.line = 1;
		HScripts.parser.allowTypes = true;
		return interp.execute(HScripts.parser.parseString(codeToRun));
	}
}
#end
