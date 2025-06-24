package script;

#if LUA_ALLOWED
import flixel.util.FlxSignal.FlxTypedSignal;
import haxe.io.Path;
import llua.Lua;
import lscript.CustomConvert;
import lscript.LScript;
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
import openfl.filters.ShaderFilter;
import openfl.system.Capabilities;
import openfl.Lib;
import flixel.addons.display.FlxRuntimeShader;
import flixel.util.FlxTimer;
import hxvlc.flixel.FlxVideoSprite;
import hxvlc.flixel.FlxVideo;
import hxvlc.util.Handle;
import haxe.Json;
#if sys
import sys.FileSystem;
import sys.io.File;
import Sys;
#end

class FunkinLScript {
    #if LUA_ALLOWED
    public static var Function_Stop:Dynamic = 1;
	public static var Function_Continue:Dynamic = 0;
	public static var Function_Halt:Dynamic = 2;
    public var lua:LScript;
    public var scriptName(default, null):String;
    private var filePath:Null<String>;
    private var closed:Bool = false;

    public function new(script:String, unsafe:Bool = false) {
        var code:String;
        filePath = FileSystem.exists(script) ? script : null;
        scriptName = 'FunkinLScript' + script;

        // Load script content
        if (filePath != null) {
            try {
                code = File.getContent(filePath);
            } catch (e:Dynamic) {
                PlayState.instance.addTextToDebug('Failed to read script file at ${filePath}: ${e}',FlxColor.RED);
                code = script; // Fallback to raw input
                filePath = null;
                scriptName = 'FunkinLScript';
            }
        } else {
            code = script; // Treat input as raw Lua code
        }

        // Apply FlxColor workarounds
        code = applyColorWorkarounds(code);

        // Initialize Lua
        lua = new LScript(code, unsafe);
        setupLuaEnvironment();
        setupErrorHandlers();
    }

    private function applyColorWorkarounds(code:String):String {
        var workarounds:Map<String, String> = [
            "FlxColor:fromRGB(" => "FlxColor:new():setRGB(",
            "FlxColor.fromRGB(" => "FlxColor:new():setRGB(",
            "FlxColor:fromRGBFloat(" => "FlxColor:new():setRGBFloat(",
            "FlxColor.fromRGBFloat(" => "FlxColor:new():setRGBFloat(",
            "FlxColor:fromHSV(" => "FlxColor:new():setHSV(",
            "FlxColor.fromHSV(" => "FlxColor:new():setHSV(",
            "FlxColor:fromHSB(" => "FlxColor:new():setHSB(",
            "FlxColor.fromHSB(" => "FlxColor:new():setHSB(",
            "FlxColor:fromCMYK(" => "FlxColor:new():setCMYK(",
            "FlxColor.fromCMYK(" => "FlxColor:new():setCMYK("
        ];
        for (from => to in workarounds) {
            code = StringTools.replace(code, from, to);
        }
        return code;
    }

    private function setupLuaEnvironment():Void {
        lua.parent = this;

        // Core Flixel classes
        setVars([
            ["FlxG", FlxG],
            ["FlxSprite", FlxSprite],
            ["FlxGraphic", FlxGraphic],
            ["FlxBasic", FlxBasic],
            ["FlxObject", FlxObject],
            // Video and media
            ["FlxVideo", FlxVideo],
            ["FlxVideoSprite", FlxVideoSprite],
            ["PsychVideoSprite", PsychVideoSprite],
            ["ParkerVideoSprite", PsychVideoSprite],
            ["Handle", Handle],
            // Animation and effects
            ["FlxTween", FlxTween],
            ["FlxEase", FlxEase],
            ["FlxTimer", FlxTimer],
            // UI and text
            ["FlxText", FlxText],
            ["FlxTextFormat", FlxTextFormat],
            // Shaders and graphics
            ["FlxShader", FlxShader],
            ["FlxRuntimeShader", FlxRuntimeShader],
            ["ShaderFilter", ShaderFilter],
            // Sound
            ["FlxSound", FlxSound],
            // Axes enum
            ["FlxAxes", { X: flixel.util.FlxAxes.X, Y: flixel.util.FlxAxes.Y, XY: flixel.util.FlxAxes.XY }],
            // OpenFL utilities
            ["Lib", Lib],
            ["Capabilities", Capabilities],
            // Blend modes
            ["BlendMode", {
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
            }],
            // Standard Haxe utilities
            ["Std", Std],
            ["Type", Type],
            ["Reflect", Reflect],
            ["Math", Math],
            ["StringTools", StringTools],
            ["Json", { parse: Json.parse, stringify: Json.stringify }],
            // Game-specific classes
            ["PlayState", PlayState],
            ["game", PlayState.instance],
            ["Paths", Paths],
            ["ClientPrefs", ClientPrefs],
            ["Note", Note],
            ["StrumNote", StrumNote],
            ["NoteSplash", NoteSplash],
            ["Character", Character],
            ["Boyfriend", Boyfriend],
            ["Section", Section],
            ["Conductor", Conductor],
            ["WeekData", WeekData],
            ["Highscore", Highscore],
            ["StageData", StageData],
            ["Song", Song]
        ]);

        #if sys
        // System utilities
        setVars([
            ["FileSystem", FileSystem],
            ["File", File],
            ["Sys", Sys]
        ]);
        #end
    }

    private function setVars(vars:Array<Array<Dynamic>>):Void {
        for (v in vars) {
            lua.setVar(v[0], v[1]);
        }
    }

    private function setupErrorHandlers():Void {
        var location = filePath != null ? filePath : "inline script";
        lua.parseError = (err:String) -> {
            PlayState.instance.addTextToDebug('Failed to parse script at ${location}: ${err}', FlxColor.RED);
        };
        lua.functionError = (func:String, err:String) -> {
            PlayState.instance.addTextToDebug('Failed to call function "${func}" at ${location}: ${err}', FlxColor.RED);
        };
        lua.tracePrefix = scriptName;
        lua.print = (line:Int, s:String) -> {
            PlayState.instance.addTextToDebug('${scriptName}:${line}: ${s}', FlxColor.WHITE);
        };
    }

    public function execute():Void {
        if (closed) return;
        lua.execute();
        call("onCreate", []);
    }

    public function get(name:String):Dynamic {
        if (closed) return null;
        return lua.getVar(name);
    }

    public function set(name:String, value:Dynamic):Void {
        if (closed) return;
        lua.setVar(name, value);
    }

    public function setClass(value:Class<Dynamic>):Void {
        if (closed) return;
        var className = Type.getClassName(value).split('.').pop();
        lua.setVar(className, value);
    }

    public function call(method:String, ?args:Array<Dynamic>):Dynamic {
        if (closed) return Function_Continue;
        var result = lua.callFunc(method, args ?? []);
        return result != null ? result : Function_Continue;
    }

    public function setParent(parent:Dynamic):Void {
        if (closed) return;
        lua.parent = parent;
    }

    public function stop():Void {
        if (closed) return;
        closed = true;
        Lua.close(lua.luaState);
        lua = null;
    }
    #else
    public var scriptName(default, null):String;

    public function new(script:String, unsafe:Bool = false) {
        scriptName = Path.withoutDirectory(script);
        PlayState.instance.addTextToDebug("LUA support is disabled. Script functionality is limited.", FlxColor.YELLOW);
    }

    public function execute():Void {}
    public function get(name:String):Dynamic return null;
    public function set(name:String, value:Dynamic):Void {}
    public function setClass(value:Class<Dynamic>):Void {}
    public function call(method:String, ?args:Array<Dynamic>):Dynamic return Function_Continue;
    public function setParent(parent:Dynamic):Void {}
    public function stop():Void {}
    #end
}
