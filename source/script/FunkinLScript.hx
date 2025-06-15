package script;

#if LUA_ALLOWED
import lscript.LScript;
import llua.Lua;
import llua.LuaL;
import llua.State;
import llua.Convert;
#end
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
import flixel.addons.display.FlxRuntimeShader;
import openfl.Lib;
import openfl.filters.ShaderFilter;
import openfl.system.Capabilities;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

class FunkinLScript
{
    #if LUA_ALLOWED
    public var Ls:LScript;
    #end
    
    public var scriptName:String = '';
    public static var Function_Stop:Dynamic = 1;
	public static var Function_Continue:Dynamic = 0;
    public function new(script:String) {
		
		Ls = new LScript(File.getContent(script));
		
		scriptName = script;
		Ls.parent = this;
		Ls.setVar("FlxG", flixel.FlxG);
		Ls.setVar("FlxSprite", flixel.FlxSprite);
	        Ls.setVar("FlxGraphic", FlxGraphic);
	        Ls.setVar("FlxBasic", FlxBasic);
		Ls.setVar("FlxObject", FlxObject);
	        Ls.setVar("FlxVideo", FlxVideo);
		Ls.setVar("FlxVideoSprite", FlxVideoSprite);
		Ls.setVar("PsychVideoSprite", PsychVideoSprite);
		Ls.setVar("ParkerVideoSprite", PsychVideoSprite);
		Ls.setVar("Handle", Handle);
		Ls.setVar("FlxTween", FlxTween);
		Ls.setVar("FlxEase", FlxEase);
		Ls.setVar("FlxTimer", FlxTimer);
		Ls.setVar("FlxText", FlxText);
		Ls.setVar("FlxTextFormat", FlxTextFormat);
	        Ls.setVar("FlxShader", FlxShader);
		Ls.setVar("FlxRuntimeShader", FlxRuntimeShader);
	        Ls.setVar("FlxSound", FlxSound);
	        Ls.setVar("FlxAxes", {
			X: flixel.util.FlxAxes.X,
			Y: flixel.util.FlxAxes.Y,
			XY: flixel.util.FlxAxes.XY
		});
	        Ls.setVar("Lib", Lib);
		Ls.setVar("Capabilities", Capabilities);
		Ls.setVar("ShaderFitler", ShaderFilter);
		Ls.setVar('BlendMode',{
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
	        Ls.setVar("Std", Std);
		Ls.setVar("Type", Type);
		Ls.setVar("Reflect", Reflect);
		Ls.setVar("Math", Math);
		Ls.setVar("StringTools", StringTools);
		Ls.setVar("Json", {parse: Json.parse, stringify: Json.stringify});
		Ls.setVar("PlayState", PlayState);
		Ls.setVar("game", PlayState.instance);
	        Ls.setVar("Paths", Paths);
	        Ls.setVar("ClientPrefs", ClientPrefs);
	        Ls.setVar("Note", Note);
		Ls.setVar("StrumNote", StrumNote);
		Ls.setVar("NoteSplash", NoteSplash);
		Ls.setVar("Character", Character);
		Ls.setVar("Boyfriend", Boyfriend);
	        Ls.setVar("Section", Section);
	        Ls.setVar("Conductor", Conductor);
	        Ls.setVar("WeekData", WeekData);
		Ls.setVar("Highscore", Highscore);
		Ls.setVar("StageData", StageData);
	        Ls.setVar("Song", Song);
	        #if sys
		Ls.setVar("FileSystem", FileSystem);
		Ls.setVar("File", File);
		Ls.setVar("Sys", Sys);
		#end
		Ls.execute();
		Ls.callFunc("onCreate");
	}
	public function call(func:String, ?args:Array<Dynamic>):Dynamic {
        var ret:Dynamic = Function_Continue;

        var result = Ls.callFunc(func, args);
		ret = (result != null && result.returnValue != null) ? result.returnValue : Function_Continue;

	    return ret;
	}
    public function set(variable:String, data:Dynamic) {
        Ls.setVar(variable, data);
    }
    public function stop() {
        if(Ls != null) {
            Ls.stop();
        }
    }

}