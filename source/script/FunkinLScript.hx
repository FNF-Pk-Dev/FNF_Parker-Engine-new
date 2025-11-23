package script;

#if (LUA_ALLOWED || lscript)
import flixel.util.FlxSignal.FlxTypedSignal;
import haxe.io.Path;
import llua.Lua;
import lscript.CustomConvert;
import lscript.LScript;
import llua.*;
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

class FunkinLScript extends GlobalScript {
    #if (LUA_ALLOWED || lscript)

    public var lua:LScript;
    public var scriptName(default, null):String;
    private var filePath:Null<String>;
    private var closed:Bool = false;

    public var foreground : FlxTypedGroup<FlxBasic>;

    public static final defaultVars:Map<String, Dynamic> = new Map<String, Dynamic>();

    public function new(script:String, unsafe:Bool = false) {
        var code:String;
        filePath = script;
        scriptName = 'FunkinLScript' + script;

        // Apply FlxColor workarounds
        //code = applyColorWorkarounds();

        // Initialize Lua
        lua = new LScript(Paths.getContent(filePath), unsafe);
        setupLuaEnvironment();

        for (variable => arg in defaultVars)
			set(variable, arg);

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

    private function setupLuaEnvironment():Void 
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
            ["Song", Song],
            ["import", function(className:String) {  //原来构思script不能用呵呵
                var classSplit:Array<String> = className.split(".");
                var daClassName = classSplit[classSplit.length-1]; // last one

                if (daClassName == '*'){
                    var daClass = Type.resolveClass(className);

                    while(classSplit.length > 0 && daClass==null){
                        daClassName = classSplit.pop();
                        daClass = Type.resolveClass(classSplit.join("."));
                        if(daClass!=null) break;
                    }
                    if(daClass!=null){
                        for(field in Reflect.fields(daClass))
                            set(field, Reflect.field(daClass, field));
                    }else{
                        PlayState.instance.addTextToDebug('Could not import class $className', FlxColor.RED);
                        FlxG.log.error('Could not import class $className');
                    }
                }else{
                    lua.setVar(daClassName, Type.resolveClass(className));
                }
            }]
        ]);

        if ((FlxG.state is PlayState) && PlayState.instance != null)
		{
			final state:PlayState = PlayState.instance;

			setVars([
                ["modManager", state.modManager], //lol ModChart
				["global", state.variables],
				["setGlobalFunc", (name:String, func:Dynamic) -> state.variables.set(name, func)],
				["callGlobalFunc", function(name:String, ?args:Dynamic)
				{
				if (state.variables.exists(name))
					return state.variables.get(name)(args);
				else
					return null;
			}]
        ]);

			setVars([
				["createGlobalCallback", function(name:String, func:Dynamic) {
					for (script in PlayState.instance.luaArray)
						if(script != null && script.lua != null && !script.closed)
							Lua_helper.add_callback(script.lua, name, func);
					psych.script.FunkinLua.customFunctions.set(name, func);
				}]
			]);
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
        if (closed) return GlobalScript.Function_Continue;
        var result = lua.callFunc(method, args != null ? args : []);
        return result != null ? result : GlobalScript.Function_Continue;
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
    public function call(method:String, ?args:Array<Dynamic>):Dynamic return GlobalScript.Function_Continue;
    public function setParent(parent:Dynamic):Void {}
    public function stop():Void {}
    #end
}
