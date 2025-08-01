package;

import flixel.graphics.FlxGraphic;
import flixel.FlxG;
import flixel.FlxGame;
import flixel.FlxState;
import openfl.Assets;
import openfl.Lib;
import openfl.display.BitmapData;
import openfl.display.FPS;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import lime.app.Application;

#if desktop
import backend.Discord.DiscordClient;
#end

//crash handler stuff
#if CRASH_HANDLER
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
#end
import haxe.Json;
import haxe.io.Bytes;
import haxe.zip.Uncompress;
import haxe.crypto.Md5;

using StringTools;

class Main extends Sprite
{
	var game = {
		width: 1280,
		height: 720,
		initState: StartupState,
		zoom: -1.0, // game state bounds
		framerate: 60, // default framerate
		skipSplash: true,
		#if android
		startFullscreen: true // if the game should start at fullscreen mode
		#elseif desktop
		startFullscreen: false
		#end
	};

	public static var fpsVar:FPS;

	public var scripts:FunkinHScript;

	// You can pretty much ignore everything from here on - your code should go in your states.

	public static function main():Void
	{
		#if cpp
                cpp.NativeGc.enable(true);
                cpp.NativeGc.run(true);
                cpp.NativeGc.enterGCFreeZone();
                #end
     
		Lib.current.addChild(new Main());
	}

	public function new()
	{
		#if mobile
		#if android
		StorageUtil.requestPermissions();
		#end
		Sys.setCwd(StorageUtil.getStorageDirectory());
		#end

		super();

		if (stage != null)
		{
			init();
		}
		else
		{
			addEventListener(Event.ADDED_TO_STAGE, init);
		}
	}

	private function init(?E:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
		{
			removeEventListener(Event.ADDED_TO_STAGE, init);
		}

		setupGame();
	}

	private function setupGame():Void
	{
		// #if (openfl <= "9.2.0")
		// var stageWidth:Int = Lib.current.stage.stageWidth;
		// var stageHeight:Int = Lib.current.stage.stageHeight;

		// if (game.zoom == -1.0)
		// {
		// 	var ratioX:Float = stageWidth / game.width;
		// 	var ratioY:Float = stageHeight / game.height;
		// 	game.zoom = Math.min(ratioX, ratioY);
		// 	game.width = Math.ceil(stageWidth / game.zoom);
		// 	game.height = Math.ceil(stageHeight / game.zoom);
		// }
		// #end 
		//what old

		ClientPrefs.loadDefaultKeys();
		addChild(new FNFGame(game.width, game.height, #if (mobile && MODS_ALLOWED) !CopyState.checkExistingFiles() ? CopyState : #end game.initState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen));

		fpsVar = new FPS(10, 3, 0xFFFFFF);
		#if !mobile
		addChild(fpsVar);
		#else
		FlxG.game.addChild(fpsVar);
		#end
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		if(fpsVar != null) {
			fpsVar.visible = ClientPrefs.showFPS;
		}

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		#if android
		FlxG.android.preventDefaultKeys = [BACK];
		#end
		
		#if CRASH_HANDLER
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
		#end

		#if desktop
		if (!DiscordClient.isInitialized) {
			DiscordClient.initialize();
			Application.current.window.onClose.add(function() {
				DiscordClient.shutdown();
			});
		}
		#end

		for (extn in HScriptUtil.extns)
		{
			var path:String = Paths.modFolders('global.$extn');
			
			if (FileSystem.exists(path))
<<<<<<< HEAD
			initIris(Paths.getContent(path), 'GLOBAL');
=======
			initIris(File.getContent(path), 'GLOBAL');
>>>>>>> c97f37f672a5792d4329f81e4d405bc1b37536e1
		}
		
	}

	function initIris(filePath:String, ?name:String)
	{
		var script:HScript = new HScript(filePath, name);
		if (script.parsingException != null)
		{
			script.stop();
			return null;
		}
		onAddScript(script);
		script.call('onCreate');
		return script;
	}


    public static function useUnpackedData(data:Bytes) {
        trace("Using unpacked data in memory, length: " + data.length);
    }
	

	private function onEnterFrame(e:Event):Void 
	{

		if (scripts != null)
			scripts.executeAllFunc("onUpdatePost", [e]);
	}
	
	function onAddScript(script:HScript) {
		script.set("this", Main);
		script.set("fnfgame", game);
	}

	// Code was entirely made by sqirra-rng for their fnf engine named "Izzy Engine", big props to them!!!
	// very cool person for real they don't get enough credit for their work
	#if CRASH_HANDLER
	function onCrash(e:UncaughtErrorEvent):Void
	{
		var errMsg:String = "";
		var path:String;
		var callStack:Array<StackItem> = CallStack.exceptionStack(true);
		var dateNow:String = Date.now().toString();

		dateNow = dateNow.replace(" ", "_");
		dateNow = dateNow.replace(":", "'");

		path = "./crash/" + "PkEngine_" + dateNow + ".txt";

		for (stackItem in callStack)
		{
			switch (stackItem)
			{
				case FilePos(s, file, line, column):
					errMsg += file + " (line " + line + ")\n";
				default:
					Sys.println(stackItem);
			}
		}

		errMsg += "\nUncaught Error: (" + e.error + "\nPlease report this error to the GitHub page: https://github.com/ShadowMario/FNF-PsychEngine\n\n> Crash Handler written by: sqirra-rng";

		if (!FileSystem.exists("./crash/"))
			FileSystem.createDirectory("./crash/");

		File.saveContent(path, errMsg + "\n");

		Sys.println(errMsg);
		Sys.println("Crash dump saved in " + Path.normalize(path));

		CoolUtil.showPopUp(errMsg, "Error!");
    #if desktop
		DiscordClient.shutdown();
	 #end
		Sys.exit(1);
	}
	#end
}
