package script.hscript;

import StringTools;
import backend.ClientPrefs;
import backend.Highscore;
import backend.Paths;
import backend.game.StageData;
import backend.game.WeekData;
import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.input.keyboard.FlxKey;
import flixel.system.FlxAssets.FlxShader;
import flixel.system.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.ui.FlxBar;
import flixel.math.FlxMath;
import openfl.display.BlendMode;
import flixel.util.FlxTimer;
import hxvlc.flixel.FlxVideoSprite;
import hxvlc.flixel.FlxVideo;
import hxvlc.util.Handle;
import haxe.Json;
import obj.Boyfriend;
import obj.Character;
import obj.Note;
import obj.NoteSplash;
import obj.StrumNote;
import openfl.Lib;
import openfl.filters.ShaderFilter;
import openfl.system.Capabilities;
import script.hscript.HScript.ScriptReturn;
import flixel.addons.display.FlxRuntimeShader;
import backend.songs.Conductor;
import backend.songs.Section;
import backend.songs.Song;
import states.game.PlayState;
import psych.obj.PsychVideoSprite;
import modcharting.ModchartFuncs;
import backend.CoolUtil;
#if LUA_ALLOWED
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;

import psych.script.FunkinLua;
#end
import script.hscript.HScript;
import script.FunkinHScript;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

class HScriptUtil
{
	public static final extns:Array<String> = ["hx", "hscript", "hsc", "hxs"];

	public static function getBasicScript():HScript
	{
		var script = new HScript();

		// Main Class
		script.set("Main", Main);

		// Haxe Classes
		script.set("Std", Std);
		script.set("Type", Type);
		script.set("Reflect", Reflect);
		script.set("Math", Math);
		script.set("StringTools", StringTools);
		script.set("Json", {parse: Json.parse, stringify: Json.stringify});

		#if sys
		script.set("FileSystem", FileSystem);
		script.set("File", File);
		script.set("Sys", Sys);
		#end

		#if LUA_ALLOWED

	       for(i in Lua_helper.callbacks.keys()) //adds lua callbacks basic
               script.set(i, Lua_helper.callbacks.get(i));
	       script.set("Lua", Lua);
	       script.set("LuaL", LuaL);
	       #end

		return script;
	}

	public static function setUpFlixelScript(script:HScript)
	{
		if (script == null)
			return;

		// OpenFL
		script.set("Lib", Lib);
		script.set("Capabilities", Capabilities);
		script.set("ShaderFitler", ShaderFilter);
		script.set('BlendMode',{
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
		});

		// Basic Stuff
		//script.set("this", this);
		script.set("state", FlxG.state);
		script.set("camera", FlxG.camera);
		script.set("FlxG", FlxG);

		script.set("add", function(obj:FlxBasic)
		{
			FlxG.state.add(obj);
		});
		
		script.set("addBehindGF", function(obj:flixel.FlxObject)
		{
			PlayState.instance.addBehindGF(obj);
		});
		
		script.set("addBehindBF", function(obj:flixel.FlxObject)
		{
			PlayState.instance.addBehindBF(obj);
		});
		
		script.set("addBehindDad", function(obj:flixel.FlxObject)
		{
			PlayState.instance.addBehindDad(obj);
		});

		script.set("insert", function(postion:Int, obj:FlxBasic)
		{
			FlxG.state.insert(postion, obj);
		});

		script.set("remove", function(obj:FlxBasic)
		{
			FlxG.state.remove(obj);
		});

		script.set("FlxBasic", FlxBasic);
		script.set("FlxObject", FlxObject);

		// Sprites
		script.set("FlxSprite", FlxSprite);
		script.set("FlxGraphic", FlxGraphic);
		
		// Bar
		script.set("FlxBar", FlxBar);
		script.set("LEFT_TO_RIGHT", LEFT_TO_RIGHT);
		script.set("RIGHT_TO_LEFT", RIGHT_TO_LEFT);
		script.set("TOP_TO_BOTTOM", TOP_TO_BOTTOM);
		script.set("BOTTOM_TO_TOP", BOTTOM_TO_TOP);
		script.set("HORIZONTAL_INSIDE_OUT", HORIZONTAL_INSIDE_OUT);
		script.set("HORIZONTAL_OUTSIDE_IN", HORIZONTAL_OUTSIDE_IN);
		script.set("VERTICAL_INSIDE_OUT", VERTICAL_INSIDE_OUT);
		script.set("VERTICAL_OUTSIDE_IN", VERTICAL_OUTSIDE_IN);
		
		// Video
		script.set("FlxVideo", FlxVideo);
		script.set("FlxVideoSprite", FlxVideoSprite);
		script.set("PsychVideoSprite", PsychVideoSprite);
		script.set("ParkerVideoSprite", PsychVideoSprite);
		script.set("Handle", Handle);

		// Tweens
		script.set("FlxTween", FlxTween);
		script.set("FlxEase", FlxEase);

		// Timer
		script.set("FlxTimer", FlxTimer);

		// FlxText
		script.set("FlxText", FlxText);
		script.set("FlxTextFormat", FlxTextFormat);
		script.set("FlxTextFormatMarkerPair", FlxTextFormatMarkerPair);
		script.set("FlxTextAlign", {
			CENTER: flixel.text.FlxText.FlxTextAlign.CENTER,
			JUSTIFY: flixel.text.FlxText.FlxTextAlign.JUSTIFY,
			LEFT: flixel.text.FlxText.FlxTextAlign.LEFT,
			RIGHT: flixel.text.FlxText.FlxTextAlign.RIGHT
		});
		script.set("FlxTextBorderStyle", FlxTextBorderStyle);

		// Shaders
		script.set("FlxShader", FlxShader);
		script.set("FlxRuntimeShader", FlxRuntimeShader);

		// Color Functions
		script.set("FlxColor", CustomFlxColor);
		
		script.set("fromRGB", function(Red:Int, Green:Int, Blue:Int, Alpha:Int = 255)
		{
			return FlxColor.fromRGB(Red, Green, Blue, Alpha);
		});

		script.set("colorFromString", function(str:String)
		{
			return FlxColor.fromString(str);
		});

		// Sounds
		script.set("FlxSound", FlxSound);
		
		// RunLuaCodes
		#if LUA_ALLOWED
		script.set("runLuaCode", function(str:String)
		{
		    for (script in PlayState.instance.luaArray)
			script.executeLua(str);
		});
		#end
		
		script.set("FlxAxes", {
			X: flixel.util.FlxAxes.X,
			Y: flixel.util.FlxAxes.Y,
			XY: flixel.util.FlxAxes.XY
		});

		script.set("FlxTypedGroup", flixel.group.FlxGroup.FlxTypedGroup);
	}

	public static function setUpFNFScript(script:HScript)
	{
		if (script == null)
			return;

		// Save Data
		script.set("ClientPrefs", ClientPrefs);
		script.set("WeekData", WeekData);
		script.set("Highscore", Highscore);
		script.set("StageData", StageData);

		// Assets
		script.set("Paths", Paths);

		// Song
		script.set("Song", Song);
		script.set("Section", Section);
		script.set("Conductor", Conductor);

		// Objects
		script.set("Note", Note);
		script.set("BGSprite", BGSprite);
		script.set("BackgroundDancer", backend.game.stages.BackgroundDancer);
		script.set("StrumNote", StrumNote);
		script.set("NoteSplash", NoteSplash);
		script.set("Character", Character);
		script.set("Boyfriend", Boyfriend);
	}
	
	public static function setUpModChatScript(script:HScript){
	
	    if (script == null)
			return;
			
		// ModChat
    	script.set('ModchartEditorState', modcharting.ModchartEditorState);
    	script.set('ModchartEvent', modcharting.ModchartEvent);
    	script.set('ModchartEventManager', modcharting.ModchartEventManager);
    	script.set('ModchartFile', modcharting.ModchartFile);
    	script.set('mod', modcharting.ModchartFuncs);
    	script.set('ModchartMusicBeatState', modcharting.ModchartMusicBeatState);
    	script.set('ModchartUtil', modcharting.ModchartUtil);
    	for (i in ['Modifier'])
    	script.set(i, modcharting.Modifier);
    	
    	script.set('ModifierSubValue', modcharting.Modifier.ModifierSubValue);
    	script.set('ModTable', modcharting.ModTable);
    	script.set('NoteMovement', modcharting.NoteMovement);
    	script.set('NotePositionData', modcharting.NotePositionData);
    	script.set('Playfield', modcharting.Playfield);
    	script.set('PlayfieldRenderer', modcharting.PlayfieldRenderer);
    	script.set('SimpleQuaternion', modcharting.SimpleQuaternion);
    	script.set('SustainStrip', modcharting.SustainStrip);
	}

	public static inline function findScriptsInDir(path:String, ?deepSearch:Bool = true):Array<String>
	{
		return CoolUtil.findFilesInPath(path, ["hx", "hscript", "hsc", "hxs"], true);
	}
	
	public static inline function findEncodedScriptsInDir(path:String, ?deepSearch:Bool = true):Array<String>
	{
		return CoolUtil.findFilesInPath(path, ["hxenc", "hscriptenc", "hscenc", "hxsenc"], true);
	}

	public static inline function hasPause(arr:Array<Dynamic>):Bool
	{
		return arr.contains(ScriptReturn.PUASE);
	}
}
/*
class HScriptState extends MusicBeatState
{
	var file:String = '';
	var stateScript:HScript;
	public var scripts:FunkinHScript;

	public function new(fileName:String, ?additionalVars:Map<String, Any>)
	{
		//super(false); // false because the whole point of this state is its scripted lol
		
		var hx:Null<String> = null;
        var endexts:Array<String> = [
			".hscript",
			".hsc",
			".hx",
			".hxs"
		];
		
		stateScript = new HScript();
		scripts = new FunkinHScript();

		for (filePath in Paths.modFolders("states/"))
		{
			var name = filePath + fileName + endexts;

			if (!FileSystem.exists(name))
				continue;
			
			if (FileSystem.exists(name))
			{
				hx = File.getContent(name);
				break;
			}

			if (scripts.getScriptByTag(name) == null)
				scripts.addScript(name).executeString(hx);
			else
			{
				scripts.getScriptByTag(fileName).error("Duplacite Script Error!", '$fileName: Duplicate Script');
				//Sys.exit(0);
			}
			break;
		    }

		stateScript.executeFunc("onLoad");
	}

	override function create()
	{
		// UPDATE: realised I should be using the "on" prefix just so if a script needs to call an internal function it doesnt cause issues
		// (Also need to figure out how to give the super to the classes incase that's needed in the on[function] funcs though honestly thats what the post functions are for)
		// I'd love to modify HScript to add override specifically for troll engine hscript
		// THSCript...

		// onCreate is used when the script is created so lol
		if (stateScript.executeFunc("onCreate", []) == FunkinLua.Function_Stop) // idk why you'd return stop on create on a hscriptstate but.. sure
			return;

		super.create();
		stateScript.executeFunc("onCreatePost");
	}

	override function update(e)
	{
		if (stateScript.executeFunc("onUpdate", [e]) == FunkinLua.Function_Stop)
			return;

		super.update(e);

		stateScript.executeFunc("onUpdatePost", [e]);
	}

	override function beatHit()
	{
		stateScript.executeFunc("onBeatHit");
		super.beatHit();
	}

	override function stepHit()
	{
		stateScript.executeFunc("onStepHit");
		super.stepHit();
	}

	override function destroy()
	{
		if (stateScript.executeFunc("onDestroy", []) == FunkinLua.Function_Stop)
			return;

		super.destroy();

		stateScript.executeFunc("onDestroyPost", []);
	}
}

/*
class HScriptSubstate extends MusicBeatSubstate
{
	public var scripts:ScriptGroup;
	var script:Script;

	public function new(ScriptName:String, ?additionalVars:Map<String, Any>)
	{
		super();
		
		scripts = new ScriptGroup();

		var fileName = 'substates/$ScriptName.$ScriptUtil.extns';


		for (filePath in [#if MODS_ALLOWED Paths.modFolders(fileName) #end Paths.getPreloadPath(fileName)])
		{
			if (!FileSystem.exists(filePath)) continue;

			// some shortcuts
            for (scriptName => hx in scriptData)
    		{
    			if (scripts.getScriptByTag(scriptName) == null)
    				scripts.addScript(scriptName).executeString(hx);
    			else
    			{
    				scripts.getScriptByTag(scriptName).error("Duplacite Script Error!", '$scriptName: Duplicate Script');
    			}
    		}

			scripts.onAddScript.push(filePath);
			script.scriptName = ScriptName;
			break;
		}

		if (script == null){
			trace('Script file "$ScriptName" not found!');
			return close();
		}

		script.call("onLoad");
	}

	override function update(e:Float)
	{
		if (script.call("update", [e]) == FunkinLua.Function_Stop)
			return; 
		
		super.update(e);
		script.executeFunc("updatePost", [e]);
	}

	override function close(){
		if (script != null)
			script.executeFunc("onClose");
		
		return super.close();
	}

	override function destroy()
	{
		if (script != null){
			script.executeFunc("onDestroy");
			script.stop();
		}
		script = null;

		return super.destroy();
	}
}*/
class CustomFlxColor
{
	// These aren't part of FlxColor but i thought they could be useful
	// honestly we should replace source/flixel/FlxColor.hx or w/e with one with these funcs
	public static function toRGBArray(color:FlxColor)
		return [color.red, color.green, color.blue];

	public static function lerp(from:FlxColor, to:FlxColor, ratio:Float) // FlxColor.interpolate() exists -_-
		return FlxColor.fromRGBFloat(flixel.math.FlxMath.lerp(from.redFloat, to.redFloat, ratio), flixel.math.FlxMath.lerp(from.greenFloat, to.greenFloat, ratio),
			flixel.math.FlxMath.lerp(from.blueFloat, to.blueFloat, ratio), flixel.math.FlxMath.lerp(from.alphaFloat, to.alphaFloat, ratio));

	////
	public static function get_red(color:FlxColor)
		return color.red;

	public static function get_green(color:FlxColor)
		return color.green;

	public static function get_blue(color:FlxColor)
		return color.blue;

	public static function set_red(color:FlxColor, val)
	{
		color.red = val;
		return color;
	}

	public static function set_green(color:FlxColor, val)
	{
		color.green = val;
		return color;
	}

	public static function set_blue(color:FlxColor, val)
	{
		color.blue = val;
		return color;
	}

	public static function get_rgb(color:FlxColor)
		return color.rgb;

	public static function get_redFloat(color:FlxColor)
		return color.redFloat;

	public static function get_greenFloat(color:FlxColor)
		return color.greenFloat;

	public static function get_blueFloat(color:FlxColor)
		return color.blueFloat;

	public static function set_redFloat(color:FlxColor, val)
	{
		color.redFloat = val;
		return color;
	}

	public static function set_greenFloat(color:FlxColor, val)
	{
		color.greenFloat = val;
		return color;
	}

	public static function set_blueFloat(color:FlxColor, val)
	{
		color.blue = val;
		return color;
	}

	//
	public static function get_hue(color:FlxColor)
		return color.hue;

	public static function get_saturation(color:FlxColor)
		return color.saturation;

	public static function get_lightness(color:FlxColor)
		return color.lightness;

	public static function get_brightness(color:FlxColor)
		return color.brightness;

	public static function set_hue(color:FlxColor, val)
	{
		color.hue = val;
		return color;
	}

	public static function set_saturation(color:FlxColor, val)
	{
		color.saturation = val;
		return color;
	}

	public static function set_lightness(color:FlxColor, val)
	{
		color.lightness = val;
		return color;
	}

	public static function set_brightness(color:FlxColor, val)
	{
		color.brightness = val;
		return color;
	}

	//
	public static function get_cyan(color:FlxColor)
		return color.cyan;

	public static function get_magenta(color:FlxColor)
		return color.magenta;

	public static function get_yellow(color:FlxColor)
		return color.yellow;

	public static function get_black(color:FlxColor)
		return color.black;

	public static function set_cyan(color:FlxColor, val)
	{
		color.cyan = val;
		return color;
	}

	public static function set_magenta(color:FlxColor, val)
	{
		color.magenta = val;
		return color;
	}

	public static function set_yellow(color:FlxColor, val)
	{
		color.yellow = val;
		return color;
	}

	public static function set_black(color:FlxColor, val)
	{
		color.black = val;
		return color;
	}

	//
	public static function getAnalogousHarmony(color:FlxColor)
		return color.getAnalogousHarmony();

	public static function getComplementHarmony(color:FlxColor)
		return color.getComplementHarmony();

	public static function getSplitComplementHarmony(color:FlxColor)
		return color.getSplitComplementHarmony();

	public static function getTriadicHarmony(color:FlxColor)
		return color.getTriadicHarmony();

	public static function getDarkened(color:FlxColor)
		return color.getDarkened();

	public static function getInverted(color:FlxColor)
		return color.getInverted();

	public static function getLightened(color:FlxColor)
		return color.getLightened();

	public static function to24Bit(color:FlxColor)
		return color.to24Bit();

	public static function getColorInfo(color:FlxColor)
		return color.getColorInfo;

	public static function toHexString(color:FlxColor)
		return color.toHexString();

	public static function toWebString(color:FlxColor)
		return color.toWebString();

	//
	public static final fromCMYK = FlxColor.fromCMYK;
	public static final fromHSL = FlxColor.fromHSL;
	public static final fromHSB = FlxColor.fromHSB;
	public static final fromInt = FlxColor.fromInt;
	public static final fromRGBFloat = FlxColor.fromRGBFloat;
	public static final fromString = FlxColor.fromString;
	public static final fromRGB = FlxColor.fromRGB;

	public static final getHSBColorWheel = FlxColor.getHSBColorWheel;
	public static final interpolate = FlxColor.interpolate;
	public static final gradient = FlxColor.gradient;

	public static final TRANSPARENT:Int = FlxColor.TRANSPARENT;
	public static final BLACK:Int = FlxColor.BLACK;
	public static final WHITE:Int = FlxColor.WHITE;
	public static final GRAY:Int = FlxColor.GRAY;

	public static final GREEN:Int = FlxColor.GREEN;
	public static final LIME:Int = FlxColor.LIME;
	public static final YELLOW:Int = FlxColor.YELLOW;
	public static final ORANGE:Int = FlxColor.ORANGE;
	public static final RED:Int = FlxColor.RED;
	public static final PURPLE:Int = FlxColor.PURPLE;
	public static final BLUE:Int = FlxColor.BLUE;
	public static final BROWN:Int = FlxColor.BROWN;
	public static final PINK:Int = FlxColor.PINK;
	public static final MAGENTA:Int = FlxColor.MAGENTA;
	public static final CYAN:Int = FlxColor.CYAN;
}
