package hscript;

import StringTools;
import ClientPrefs;
import Highscore;
import Paths;
import StageData;
import WeekData;
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
import flixel.math.FlxMath;
import openfl.display.BlendMode;
import flixel.util.FlxTimer;
import hxvlc.flixel.FlxVideoSprite;
import hxvlc.flixel.FlxVideo;
import hxvlc.util.Handle;
import haxe.Json;
import Boyfriend;
import Character;
import Note;
import NoteSplash;
import StrumNote;
import openfl.Lib;
import openfl.filters.ShaderFilter;
import openfl.system.Capabilities;
import hscript.Script.ScriptReturn;
import flixel.addons.display.FlxRuntimeShader;
import Conductor;
import Section;
import Song;
import PlayState;
import modcharting.ModchartFuncs;
import CoolUtil;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

class ScriptUtil
{
	public static final extns:Array<String> = ["hx", "hscript", "hsc", "hxs"];

	public static function getBasicScript():Script
	{
		var script = new Script();

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

		return script;
	}

	public static function setUpFlixelScript(script:Script)
	{
		if (script == null)
			return;

		// OpenFL
		script.set("BlendMode", CustomBlendMode);
		script.set("Lib", Lib);
		script.set("Capabilities", Capabilities);
		script.set("ShaderFitler", ShaderFilter);

		// Basic Stuff
		script.set("state", FlxG.state);
		script.set("camera", FlxG.camera);
		script.set("FlxG", FlxG);

		script.set("add", function(obj:FlxBasic)
		{
			FlxG.state.add(obj);
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
		
		// Video
		script.set("FlxVideo", FlxVideo);
		script.set("FlxVideoSprite", FlxVideoSprite);
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
	}

	public static function setUpFNFScript(script:Script)
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
		script.set("StrumNote", StrumNote);
		script.set("NoteSplash", NoteSplash);
		script.set("Character", Character);
		script.set("Boyfriend", Boyfriend);
	}
	
	public static function setUpModChatScript(script:Script){
	
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
class CustomBlendMode
{

    public static function fromString(value:String){
        return switch (value)
		{
			case "add": BlendMode.ADD;
			case "alpha": BlendMode.ALPHA;
			case "darken": BlendMode.DARKEN;
			case "difference": BlendMode.DIFFERENCE;
			case "erase": BlendMode.ERASE;
			case "hardlight": BlendMode.HARDLIGHT;
			case "invert": BlendMode.INVERT;
			case "layer": BlendMode.LAYER;
			case "lighten": BlendMode.LIGHTEN;
			case "multiply": BlendMode.MULTIPLY;
			case "normal": BlendMode.NORMAL;
			case "overlay": BlendMode.OVERLAY;
			case "screen": BlendMode.SCREEN;
			case "shader": BlendMode.SHADER;
			case "subtract": BlendMode.SUBTRACT;
			default: null;
		}
    }
    public static final ADD:String = BlendMode.ADD;
    public static final ALPHA:String = BlendMode.ALPHA;
    public static final DARKEN:String = BlendMode.DARKEN;
    public static final DIFFERENCE:String = BlendMode.DIFFERENCE;
    public static final ERASE:String = BlendMode.ERASE;
    public static final HARDLIGHT:String = BlendMode.HARDLIGHT;
    public static final INVERT:String = BlendMode.INVERT;
    public static final LAYER:String = BlendMode.LAYER;
    public static final LIGHTEN:String = BlendMode.LIGHTEN;
    public static final MULTIPLY:String = BlendMode.MULTIPLY;
    public static final NORMAL:String = BlendMode.NORMAL;
    public static final OVERLAY:String = BlendMode.OVERLAY;
    public static final SCREEN:String = BlendMode.SCREEN;
    public static final SHADER:String = BlendMode.SHADER;
    public static final SUBTRACT:String = BlendMode.ASUBTRACT;
}