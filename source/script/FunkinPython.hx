package script;

using StringTools;

#if PYTHON_ALLOWED
import flixel.util.FlxSignal.FlxTypedSignal;
import haxe.io.Path;
import pyscript.PScript;
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

class FunkinPython extends FlxBasic
{
    #if PYTHON_ALLOWED

    public var PyScript:PScript;
    public var scriptName(default, null):String;
    private var filePath:Null<String>;
    private var closed:Bool = false;

    public var foreground : FlxTypedGroup<FlxBasic>;

    public static final defaultVars:Map<String, Dynamic> = new Map<String, Dynamic>();

    public function new(script:String) {
        super();
        
        var code:String;
        filePath = script;
        scriptName = script;

        // Read Python script file
        if (sys.FileSystem.exists(filePath)) {
            code = sys.io.File.getContent(filePath);
        } else {
            code = script; // Treat as inline code
        }

        // Apply FlxColor workarounds for Python syntax
        code = applyColorWorkarounds(code);

        // Initialize PyScript PyScript.interpreter
        PyScript = new PScript(code);
        setupPythonEnvironment();

        for (variable => arg in defaultVars)
            set(variable, arg);

        setupErrorHandlers();
        
    }

    private function applyColorWorkarounds(code:String):String {
        var workarounds:Map<String, String> = [
            "FlxColor.fromRGB(" => "FlxColor().setRGB(",
            "FlxColor.fromRGBFloat(" => "FlxColor().setRGBFloat(",
            "FlxColor.fromHSV(" => "FlxColor().setHSV(",
            "FlxColor.fromHSB(" => "FlxColor().setHSB(",
            "FlxColor.fromCMYK(" => "FlxColor().setCMYK("
        ];
        for (from => to in workarounds) {
            code = StringTools.replace(code, from, to);
        }
        return code;
    }

    private function setupPythonEnvironment():Void 
    {
        foreground = new FlxTypedGroup<FlxBasic>();

        // Core Flixel classes
        setVars([
            ["Function_Stop", GlobalScript.Function_Stop],
            ["Function_Continue", GlobalScript.Function_Continue],
            ["Function_Halt", GlobalScript.Function_Halt],
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
            ["FlxAxes", { "X": flixel.util.FlxAxes.X, "Y": flixel.util.FlxAxes.Y, "XY": flixel.util.FlxAxes.XY }],
            // OpenFL utilities
            ["Lib", Lib],
            ["Capabilities", Capabilities],
            // Blend modes
            ["BlendMode", {
                "SUBTRACT": BlendMode.SUBTRACT,
                "ADD": BlendMode.ADD,
                "MULTIPLY": BlendMode.MULTIPLY,
                "ALPHA": BlendMode.ALPHA,
                "DARKEN": BlendMode.DARKEN,
                "DIFFERENCE": BlendMode.DIFFERENCE,
                "INVERT": BlendMode.INVERT,
                "HARDLIGHT": BlendMode.HARDLIGHT,
                "LIGHTEN": BlendMode.LIGHTEN,
                "OVERLAY": BlendMode.OVERLAY,
                "SHADER": BlendMode.SHADER,
                "SCREEN": BlendMode.SCREEN
            }],
            // Standard Haxe utilities
            ["Std", Std],
            ["Type", Type],
            ["Reflect", Reflect],
            ["Math", Math],
            ["StringTools", StringTools],
            ["Json", { "parse": Json.parse, "stringify": Json.stringify }],
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

        if ((FlxG.state is PlayState) && PlayState.instance != null)
        {
            final state:PlayState = PlayState.instance;

            setVars([
                ["modManager", state.modManager],
                ["global", state.variables],
                ["setGlobalFunc", function(name:String, func:Dynamic) { state.variables.set(name, func); }],
                ["callGlobalFunc", function(name:String, ?args:Dynamic) {
                    if (state.variables.exists(name))
                        return state.variables.get(name)(args);
                    else
                        return null;
                }]
            ]);

            // setVars([
            //     ["createGlobalCallback", function(name:String, func:Dynamic) {
            //         for (script in PlayState.instance.luaArray)
            //             if(script != null && script.lua != null && !script.closed)
            //                 Lua_helper.add_callback(script.lua, name, func);
            //         psych.script.FunkinLua.customFunctions.set(name, func);
            //     }]
            // ]);
        }

        setVars([
            ["FlxCamera", flixel.FlxCamera],
            ["FlxSpriteGroup", flixel.group.FlxSpriteGroup],
            ["FlxTypedGroup", flixel.group.FlxTypedGroup],
        ]);

        set("add", FlxG.state.add);
        set("remove", FlxG.state.remove);
        set("insert", FlxG.state.insert);
        set("members", FlxG.state.members);
        set('foreground', foreground);

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
            PyScript.setVar(v[0], v[1]);
        }
    }

    private function setupErrorHandlers():Void {
        var location = filePath != null ? filePath : "inline script";
        
        // Set up error handling for PyScript
        PyScript.onError = function(err:String) {
            PlayState.instance.addTextToDebug('Failed to execute script at ${location}: ${err}', FlxColor.RED);
        };
        
        PyScript.onPrint = function(line:Int, s:String) {
            PlayState.instance.addTextToDebug('${scriptName}:${line}: ${s}', FlxColor.WHITE);
        };
    }

    public function execute():Void {
        if (closed) return;
        PyScript.execute();
        call("onCreate", []);
    }

    public function get(name:String):Dynamic {
        if (closed) return null;
        return PyScript.getVar(name);
    }

    public function set(name:String, value:Dynamic):Void {
        if (closed) return;
        PyScript.setVar(name, value);
    }

    public function setClass(value:Class<Dynamic>):Void {
        if (closed) return;
        var className = Type.getClassName(value).split('.').pop();
        PyScript.setVar(className, value);
    }

    public function call(method:String, ?args:Array<Dynamic>):Dynamic {
        if (closed) return GlobalScript.Function_Continue;
        var result = PyScript.callFunc(method, args != null ? args : []);
        return result != null ? result : GlobalScript.Function_Continue;
    }

    public function setParent(parent:Dynamic):Void {
        if (closed) return;
        PyScript.parent = parent;
    }

    public function stop():Void {
        if (closed) return;
        closed = true;
        PyScript.interpreter = null;
    }
    
    #else
    public var scriptName(default, null):String;

    public function new(script:String) {
        super();
        scriptName = Path.withoutDirectory(script);
        PlayState.instance.addTextToDebug("PYTHON support is disabled. Script functionality is limited.", FlxColor.YELLOW);
    }

    public function execute():Void {}
    public function get(name:String):Dynamic return null;
    public function set(name:String, value:Dynamic):Void {}
    public function setClass(value:Class<Dynamic>):Void {}
    public function call(method:String, ?args:Array<Dynamic>):Dynamic return GlobalScript.Function_Continue;
    public function setParent(parent:Dynamic):Void {}
    public function stop():Void {}
    #end
}