package openfl.display;

import haxe.Timer;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFormat;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import lime.system.System as LimeSystem;
#if gl_stats
import openfl.display._internal.stats.Context3DStats;
import openfl.display._internal.stats.DrawCallContext;
#end
#if flash
import openfl.Lib;
#end

#if openfl
import openfl.system.System;
#end

/**
	The FPS class provides an easy-to-use monitor to display
	the current frame rate of an OpenFL project
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end

class FPS extends TextField
{
	/**
		The current frame rate, expressed using frames-per-second
	**/
	public var currentFPS(default, null):Int;

	@:noCompletion private var cacheCount:Int;
	@:noCompletion private var currentTime:Float;
	@:noCompletion private var times:Array<Float>;
    @:noCompletion private var pkEngineVersion:String;
	public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000)
	{
		super();

		this.x = x;
		this.y = y;

		currentFPS = 0;
		selectable = false;
		mouseEnabled = false;
		#if android
                defaultTextFormat = new TextFormat('_sans', Std.int(14 * Math.min(openfl.Lib.current.stage.stageWidth / FlxG.width, openfl.Lib.current.stage.stageHeight / FlxG.height)), color);
                #else
		defaultTextFormat = new TextFormat("_sans", 14, color);
                #end
		autoSize = LEFT;
		multiline = true;
		text = "FPS: ";
		textColor = 0xFFFFFFFF;

		cacheCount = 0;
		currentTime = 0;
		times = [];

                pkEngineVersion = "v0.5.2";
        
		#if flash
		addEventListener(Event.ENTER_FRAME, function(e)
		{
			var time = Lib.getTimer();
			__enterFrame(time - currentTime);
		});
		#end
	}
	
    public static var currentColor = 0;	
	var skippedFrames = 0;

	var ColorArray:Array<Int> = [
		0x9400D3,
		0x4B0082,
		0x0000FF,
		0x00FF00,
		0xFFFF00,
		0xFF7F00,
		0xFF0000
		];
		
	// Event Handlers
	@:noCompletion
	private #if !flash override #end function __enterFrame(deltaTime:Float):Void
	{
	
	if (ClientPrefs.rainbowFPS)
		{
			if (skippedFrames >= 6)
			{
				if (currentColor >= ColorArray.length)
					currentColor = 0;
				textColor = ColorArray[currentColor];
				currentColor++;
				skippedFrames = 0;
			}
			else
			{
				skippedFrames++;
			}
		}
		else
		{
			textColor = 0xFFFFFFFF;
		}
		
		currentTime += deltaTime;
		times.push(currentTime);

		while (times[0] < currentTime - 1000)
		{
			times.shift();
		}

		var currentCount = times.length;
		currentFPS = Math.round((currentCount + cacheCount) / 2);
		if (currentFPS > ClientPrefs.framerate) currentFPS = ClientPrefs.framerate;

		if (currentCount != cacheCount /*&& visible*/)
		{
			text = "FPS: " + currentFPS;
			var memoryMegas:Float = 0;
			
			#if openfl
			memoryMegas = Math.abs(FlxMath.roundDecimal(System.totalMemory / 1000000, 1));
			text += "\nMemory: " + memoryMegas + " MB";
			text += "\nPk Engine: " + pkEngineVersion;
			#end
			var memoryMegas:Float = 0;
			
			if (memoryMegas > 3000 || currentFPS <= ClientPrefs.framerate / 2)
			{
				// textColor = 0xFFFF0000;
				text = "FPS: " + currentFPS;
				text += "\nMemory: " + memoryMegas + " MB";
				text += "\nPk Engine: " + pkEngineVersion;
			}

			#if (gl_stats && !disable_cffi && (!html5 || !canvas))
			text += "\ntotalDC: " + Context3DStats.totalDrawCalls();
			text += "\nstageDC: " + Context3DStats.contextDrawCalls(DrawCallContext.STAGE);
			text += "\nstage3DDC: " + Context3DStats.contextDrawCalls(DrawCallContext.STAGE3D);
			#end

			text += "\n";
		}

		cacheCount = currentCount;
	}
}
