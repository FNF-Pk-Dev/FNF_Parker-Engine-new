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
import flixel.FlxState;
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
import flixel.addons.display.FlxRuntimeShader;
import backend.songs.Conductor;
import backend.songs.Section;
import backend.songs.Song;
import states.game.PlayState;
import psych.obj.PsychVideoSprite;
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
#if android
import android.FlxVirtualPad;
#end

class HScriptUtil extends HScript
{
	public static final extns:Array<String> = ["hx", "hscript", "hsc", "hxs"];

	override function setDefaultVars()
	{
		_script.preset();
		super.setDefaultVars();

		// Main Class
		set("Main", Main);

		// Haxe Classes
		set("Std", Std);
		set("Type", Type);
		set("Reflect", Reflect);
		set("Math", Math);
		set("StringTools", StringTools);
		set("Json", {parse: Json.parse, stringify: Json.stringify});

		#if sys
		set("FileSystem", FileSystem);
		set("File", File);
		set("Sys", Sys);
		#end

		// OpenFL
		set("Lib", Lib);
		set("Capabilities", Capabilities);
		set("ShaderFitler", ShaderFilter);
		set('BlendMode',{
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
		//set("this", this);
		set("state", FlxG.state);
		set("camera", FlxG.camera);
		set("FlxG", FlxG);

		set("newShader", Paths.getShader);

		set("add", function(obj:FlxBasic)
		{
			FlxG.state.add(obj);
		});
		
		set("addBehindGF", function(obj:flixel.FlxObject)
		{
			PlayState.instance.addBehindGF(obj);
		});
		
		set("addBehindBF", function(obj:flixel.FlxObject)
		{
			PlayState.instance.addBehindBF(obj);
		});
		
		set("addBehindDad", function(obj:flixel.FlxObject)
		{
			PlayState.instance.addBehindDad(obj);
		});

		set("insert", function(postion:Int, obj:FlxBasic)
		{
			FlxG.state.insert(postion, obj);
		});

		set("remove", function(obj:FlxBasic)
		{
			FlxG.state.remove(obj);
		});

		set("FlxBasic", FlxBasic);
		set("FlxObject", FlxObject);

		// Sprites
		set("FlxSprite", FlxSprite);
		set("FlxGraphic", FlxGraphic);
		
		// Bar
		set("FlxBar", FlxBar);
		set("LEFT_TO_RIGHT", LEFT_TO_RIGHT);
		set("RIGHT_TO_LEFT", RIGHT_TO_LEFT);
		set("TOP_TO_BOTTOM", TOP_TO_BOTTOM);
		set("BOTTOM_TO_TOP", BOTTOM_TO_TOP);
		set("HORIZONTAL_INSIDE_OUT", HORIZONTAL_INSIDE_OUT);
		set("HORIZONTAL_OUTSIDE_IN", HORIZONTAL_OUTSIDE_IN);
		set("VERTICAL_INSIDE_OUT", VERTICAL_INSIDE_OUT);
		set("VERTICAL_OUTSIDE_IN", VERTICAL_OUTSIDE_IN);
		
		// Video
		set("FlxVideo", FlxVideo);
		set("FlxVideoSprite", FlxVideoSprite);
		set("PsychVideoSprite", PsychVideoSprite);
		set("ParkerVideoSprite", PsychVideoSprite);
		set("Handle", Handle);

		// Tweens
		set("FlxTween", FlxTween);
		set("FlxEase", FlxEase);

		// Timer
		set("FlxTimer", FlxTimer);

		// FlxText
		set("FlxText", FlxText);
		set("FlxTextFormat", FlxTextFormat);
		set("FlxTextFormatMarkerPair", FlxTextFormatMarkerPair);
		set("FlxTextAlign", {
			CENTER: flixel.text.FlxText.FlxTextAlign.CENTER,
			JUSTIFY: flixel.text.FlxText.FlxTextAlign.JUSTIFY,
			LEFT: flixel.text.FlxText.FlxTextAlign.LEFT,
			RIGHT: flixel.text.FlxText.FlxTextAlign.RIGHT
		});
		set("FlxTextBorderStyle", FlxTextBorderStyle);

		// Shaders
		set("FlxShader", FlxShader);
		set("FlxRuntimeShader", FlxRuntimeShader);

		// Modchart
		set("ModManager", modchart.ModManager);
		set("Modifier", modchart.Modifier);
		//set("HScriptModifier", modchart.HScriptModifier);
		set("SubModifier", modchart.SubModifier);
		set("NoteModifier", modchart.NoteModifier);
		set("EventTimeline", modchart.EventTimeline);
		set("StepCallbackEvent", modchart.events.StepCallbackEvent);
		set("CallbackEvent", modchart.events.CallbackEvent);
		set("ModEvent", modchart.events.ModEvent);
		set("EaseEvent", modchart.events.EaseEvent);
		set("SetEvent", modchart.events.SetEvent);
		
		// Color Functions
		set("FlxColor", CustomFlxColor);
		
		set("fromRGB", function(Red:Int, Green:Int, Blue:Int, Alpha:Int = 255)
		{
			return FlxColor.fromRGB(Red, Green, Blue, Alpha);
		});

		set("colorFromString", function(str:String)
		{
			return FlxColor.fromString(str);
		});

		// Sounds
		set("FlxSound", FlxSound);
		
		// RunLuaCodes
		#if LUA_ALLOWED
		set("runLuaCode", function(str:String)
		{
		    for (script in PlayState.instance.luaArray)
			script.executeLua(str);
		});
		#end
		
		set("FlxAxes", {
			X: flixel.util.FlxAxes.X,
			Y: flixel.util.FlxAxes.Y,
			XY: flixel.util.FlxAxes.XY
		});

		set("FlxTypedGroup", flixel.group.FlxGroup.FlxTypedGroup);

		// Save Data
		set("ClientPrefs", ClientPrefs);
		set("WeekData", WeekData);
		set("Highscore", Highscore);
		set("StageData", StageData);

		// Assets
		set("Paths", Paths);

		// Song
		set("Song", Song);
		set("Section", Section);
		set("Conductor", Conductor);

		// Objects
		set("Note", Note);
		set("BGSprite", BGSprite);
		set("BackgroundDancer", backend.game.stages.BackgroundDancer);
		set("StrumNote", StrumNote);
		set("NoteSplash", NoteSplash);
		set("Character", Character);
		set("Boyfriend", Boyfriend);


	   }

	   /**
	    * Find all HScript files in a directory
	    * @param path Directory path to search
	    * @param deepSearch Whether to search recursively
	    * @return Array of script file paths
	    */
	   public static inline function findScriptsInDir(path:String, ?deepSearch:Bool = true):Array<String> {
	       return CoolUtil.findFilesInPath(path, extns, deepSearch);
	   }
	   
	   /**
	    * Find all encoded HScript files in a directory
	    * @param path Directory path to search
	    * @param deepSearch Whether to search recursively
	    * @return Array of encoded script file paths
	    */
	   public static inline function findEncodedScriptsInDir(path:String, ?deepSearch:Bool = true):Array<String> {
	       return CoolUtil.findFilesInPath(path, ["hxenc", "hscriptenc", "hscenc", "hxsenc"], deepSearch);
	   }
}

/**
	* Placeholder class for scripted states.
	* Actual implementation is in OScriptState.
	*/
class HScriptState extends MusicBeatState {
	   // This class serves as a placeholder for the scripted state system.
	   // The actual scripted state functionality is handled by OScriptState.
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
