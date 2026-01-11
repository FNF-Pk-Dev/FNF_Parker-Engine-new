package;

import flixel.graphics.FlxGraphic;
import flixel.FlxG;
import flixel.FlxGame;
import flixel.FlxState;
import openfl.Assets;
import openfl.Lib;
import openfl.display.BitmapData;
import backend.obj.FPSCounter;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import lime.app.Application;
#if desktop
import backend.Discord.DiscordClient;
#end
#if android
import openfl.events.KeyboardEvent;
#end
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
	public static var backPressed:Bool = false;

	var game = {
		width: 1280,
		height: 720,
		initState: StartupState,
		zoom: -1.0,
		framerate: 60,
		skipSplash: true,
		#if android
		startFullscreen: true
		#elseif desktop
		startFullscreen: false
		#end
	};

	public static var fpsVar:FPSCounter;
	public static var scaleMode:ScaleModeRezie;
	public var scripts:FunkinHScript;

	public static function main():Void
	{
		Lib.current.addChild(new Main());
		#if cpp
		cpp.NativeGc.enable(true);
		cpp.NativeGc.run(true);
		cpp.NativeGc.enterGCFreeZone();
		#end
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
			init();
		else
			addEventListener(Event.ADDED_TO_STAGE, init);
	}

	private function init(?E:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
			removeEventListener(Event.ADDED_TO_STAGE, init);

		setupGame();
	}

	public static function setScaleMode(scale:String){
		switch(scale){
			default:
				Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
			case 'EXACT_FIT':
				Lib.current.stage.scaleMode = StageScaleMode.EXACT_FIT;
			case 'NO_BORDER':
				Lib.current.stage.scaleMode = StageScaleMode.NO_BORDER;
			case 'SHOW_ALL':
				Lib.current.stage.scaleMode = StageScaleMode.SHOW_ALL;
		}
	}

	private function setupGame():Void
	{
		ClientPrefs.loadDefaultKeys();
		addChild(new FNFGame(game.width, game.height, #if (mobile && MODS_ALLOWED) !CopyState.checkExistingFiles() ? CopyState : #end game.initState,
			#if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen));

		addEventListener(Event.ENTER_FRAME, onEnterFrame);

		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		#if !mobile
		addChild(fpsVar);
		#else
		FlxG.game.addChild(fpsVar);
		#end
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		if (fpsVar != null)
			fpsVar.visible = ClientPrefs.showFPS;

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		#if CRASH_HANDLER
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
		#end

		#if desktop
		if (!DiscordClient.isInitialized)
		{
			DiscordClient.initialize();
			Application.current.window.onClose.add(function()
			{
				DiscordClient.shutdown();
			});
		}
		#end

		FlxG.signals.gameResized.add(onResize);
		FlxG.scaleMode = new ScaleModeRezie();
		FlxG.signals.preStateSwitch.add((cast FlxG.scaleMode : ScaleModeRezie).resetSize);

		for (extn in HScriptUtil.extns)
		{
			var path:String = Paths.modFolders('global.$extn');

			if (FileSystem.exists(path))
				initIris(Paths.getContent(path), 'GLOBAL');
		}
	}

	static function onResize(w,h) 
	{
		final scale:Float = Math.max(1,Math.min(w / FlxG.width, h / FlxG.height));
		if (fpsVar != null) {
			fpsVar.scaleX = fpsVar.scaleY = scale;
		}

		@:privateAccess if (FlxG.cameras != null) for (i in FlxG.cameras.list) if (i != null && i._filters != null) resetSpriteCache(i.flashSprite);
		if (FlxG.game != null) resetSpriteCache(FlxG.game);
		
	}

	public static function resetSpriteCache(sprite:Sprite):Void
	{
		@:privateAccess 
		{
			sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
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

	private function onEnterFrame(e:Event):Void
	{
		#if android
		if (backPressed && FlxG.state != null && FlxG.state.visible)
		{
			backPressed = false;
			
			if (Std.is(FlxG.state, states.game.PlayState))
			{
				var playState:states.game.PlayState = cast FlxG.state;
				if (!playState.paused && !playState.endingSong)
				{
					playState.openSubState(new substates.PauseSubState(
						playState.boyfriend.getScreenPosition().x,
						playState.boyfriend.getScreenPosition().y
					));
				}
			}
			else if (Std.is(FlxG.state, states.TitleState))
				finish();
		}
		#end

		if (scripts != null)
			scripts.executeAllFunc("onUpdatePost", [e]);
	}

	private function finish():Void
	{
		Sys.exit(0);
	}

	function onAddScript(script:HScript)
	{
		script.set("this", Main);
		script.set("fnfgame", game);
	}

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

		errMsg += "\nUncaught Error: ("
			+ e.error
			+ "\nPlease report this error to the GitHub page: https://github.com/ShadowMario/FNF-PsychEngine\n\n> Crash Handler written by: sqirra-rng";

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
