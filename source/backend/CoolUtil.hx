package backend;

import flixel.util.FlxSave;
import flixel.FlxG;
import flixel.FlxCamera;
import openfl.utils.Assets;
import haxe.display.Display.Package;
import haxe.io.Path;
import lime.utils.Assets as LimeAssets;
import lime.utils.AssetLibrary;
import lime.utils.AssetManifest;
import flixel.system.FlxSound;
#if sys
import sys.io.File;
import sys.FileSystem;
#else
import openfl.utils.Assets;
#end

using StringTools;

class CoolUtil
{
	public static var defaultDifficulties:Array<String> = [
		'Easy',
		'Normal',
		'Hard'
	];
	public static var defaultDifficulty:String = 'Normal'; //The chart that has no suffix and starting difficulty on Freeplay/Story Mode

	public static var difficulties:Array<String> = [];

	inline public static function scale(x:Float, l1:Float, h1:Float, l2:Float, h2:Float):Float
		return ((x - l1) * (h2 - l2) / (h1 - l1) + l2);

	inline public static function clamp(n:Float, l:Float, h:Float)
	{
		if (n > h)
			n = h;
		if (n < l)
			n = l;

		return n;
	}

	public static function rotate(x:Float, y:Float, angle:Float, ?point:FlxPoint):FlxPoint
	{
		var p = point == null ? FlxPoint.weak() : point;
		p.set((x * Math.cos(angle)) - (y * Math.sin(angle)), (x * Math.sin(angle)) + (y * Math.cos(angle)));
		return p;
	}

	inline public static function quantize(f:Float, snap:Float){
		// changed so this actually works lol
		var m:Float = Math.fround(f * snap);
		trace(snap);
		return (m / snap);
	}
	
	public static function getDifficultyFilePath(num:Null<Int> = null)
	{
		if(num == null) num = PlayState.storyDifficulty;

		var fileSuffix:String = difficulties[num];
		if(fileSuffix != defaultDifficulty)
		{
			fileSuffix = '-' + fileSuffix;
		}
		else
		{
			fileSuffix = '';
		}
		return Paths.formatToSongPath(fileSuffix);
	}

	public static function difficultyString():String
	{
		return difficulties[PlayState.storyDifficulty].toUpperCase();
	}

	inline public static function boundTo(value:Float, min:Float, max:Float):Float {
		return Math.max(min, Math.min(max, value));
	}

	public static function coolTextFile(path:String):Array<String>
	{
		var daList:Array<String> = [];
		#if sys
		if(FileSystem.exists(path)) daList = File.getContent(path).trim().split('\n');
		#else
		if(Assets.exists(path)) daList = Assets.getText(path).trim().split('\n');
		#end

		for (i in 0...daList.length)
		{
			daList[i] = daList[i].trim();
		}

		return daList;
	}
	public static function listFromString(string:String):Array<String>
	{
		var daList:Array<String> = [];
		daList = string.trim().split('\n');

		for (i in 0...daList.length)
		{
			daList[i] = daList[i].trim();
		}

		return daList;
	}
	public static function dominantColor(sprite:flixel.FlxSprite):Int{
		var countByColor:Map<Int, Int> = [];
		for(col in 0...sprite.frameWidth){
			for(row in 0...sprite.frameHeight){
			  var colorOfThisPixel:Int = sprite.pixels.getPixel32(col, row);
			  if(colorOfThisPixel != 0){
				  if(countByColor.exists(colorOfThisPixel)){
				    countByColor[colorOfThisPixel] =  countByColor[colorOfThisPixel] + 1;
				  }else if(countByColor[colorOfThisPixel] != 13520687 - (2*13520687)){
					 countByColor[colorOfThisPixel] = 1;
				  }
			  }
			}
		 }
		var maxCount = 0;
		var maxKey:Int = 0;//after the loop this will store the max color
		countByColor[flixel.util.FlxColor.BLACK] = 0;
			for(key in countByColor.keys()){
			if(countByColor[key] >= maxCount){
				maxCount = countByColor[key];
				maxKey = key;
			}
		}
		return maxKey;
	}

	public static function numberArray(max:Int, ?min = 0):Array<Int>
	{
		var dumbArray:Array<Int> = [];
		for (i in min...max)
		{
			dumbArray.push(i);
		}
		return dumbArray;
	}

	//uhhhh does this even work at all? i'm starting to doubt
	public static function precacheSound(sound:String, ?library:String = null):Void {
		Paths.sound(sound, library);
	}

	public static function precacheMusic(sound:String, ?library:String = null):Void {
		Paths.music(sound, library);
	}

	public static function precacheImage(name:String, ?library:String = null):Void {
		Paths.image(name, library);
	}

	// public static function insertFlxCamera(idx:Int, cam:FlxCamera, defDraw:Bool):FlxCamera {
	// 	var cameras = [
	// 		for (i in FlxG.cameras.list)
	// 			{
	// 				cam: i,
	// 				defaultDraw: FlxG.cameras.list.defaults.contains(i)
	// 			}
	// 	];

	// 	for(i in cameras) FlxG.cameras.remove(i.cam, false);

	// 	cameras.insert(idx, {cam: cam, defaultDraw: defDraw});

	// 	for (i in cameras) FlxG.cameras.add(i.cam, i.defaultDraw);

	// 	return cam;
	// }

	public static function browserLoad(site:String) {
		#if linux
		Sys.command('/usr/bin/xdg-open', [site]);
		#else
		FlxG.openURL(site);
		#end
	}

	public static final formatNotAllowedChars:Array<String> = ["~", "%", "&", ";", ":", '/', '"', "'", "<", ">", "?", "#", " ", "!"];

	public static function formatBindString(str:String):String
	{
		var finalStr = str;

		for (notAllowed in formatNotAllowedChars)
		{
			finalStr = StringTools.replace(finalStr, notAllowed, "");
		}

		return finalStr.toLowerCase();
	}

	public static function findFilesInPath(path:String, extns:Array<String>, ?filePath:Bool = false, ?deepSearch:Bool = true):Array<String>
	{
		var files:Array<String> = [];

		if (FileSystem.exists(path))
		{
			for (file in FileSystem.readDirectory(path))
			{
				var path = haxe.io.Path.join([path, file]);
				if (!FileSystem.isDirectory(path))
				{
					for (extn in extns)
					{
						if (file.endsWith(extn))
						{
							if (filePath)
								files.push(path);
							else
								files.push(file);
						}
					}
				}
				else if (deepSearch) // ! YAY !!!! -lunar
				{
					var pathsFiles:Array<String> = findFilesInPath(path, extns);

					for (_ in pathsFiles)
						files.push(_);
				}
			}
		}
		return files;
	}
	
	public static inline function getFileStringFromPath(file:String):String
	{
		return Path.withoutDirectory(Path.withoutExtension(file));
	}

	/** Quick Function to Fix Save Files for Flixel 5
		if you are making a mod, you are gonna wanna change "ShadowMario" to something else
		so Base Psych saves won't conflict with yours
		@BeastlyGabi
	**/
	public static function getSavePath(folder:String = 'ShadowMario'):String {
		@:privateAccess
		return #if (flixel < "5.0.0") folder #else FlxG.stage.application.meta.get('company')
			+ '/'
			+ FlxSave.validate(FlxG.stage.application.meta.get('file')) #end;
	}
	public static function showPopUp(message:String, title:String):Void
	{
		#if android
		android.Tools.showAlertDialog(title, message, {name: "OK", func: null}, null);
		#else
		FlxG.stage.window.alert(message, title);
		#end
	}
}
