package backend;

import flixel.util.FlxSave;
import flixel.FlxG;
import flixel.FlxCamera;
import haxe.io.Path;

#if sys
import sys.io.File;
import sys.FileSystem;
#else
import openfl.utils.Assets;
#end

using StringTools;

/**
 * Collection of utility functions used throughout the engine.
 * Provides math helpers, file operations, and formatting utilities.
 */
class CoolUtil {
    // Difficulty settings
    public static var defaultDifficulties:Array<String> = ['Easy', 'Normal', 'Hard'];
    public static var defaultDifficulty:String = 'Normal';
    public static var difficulties:Array<String> = [];
    
    // Characters not allowed in formatted strings
    public static final formatNotAllowedChars:Array<String> = ["~", "%", "&", ";", ":", '/', '"', "'", "<", ">", "?", "#", " ", "!"];
    
    /**
     * Scale a value from one range to another
     */
    inline public static function scale(x:Float, l1:Float, h1:Float, l2:Float, h2:Float):Float {
        return ((x - l1) * (h2 - l2) / (h1 - l1) + l2);
    }
    
    /**
     * Clamp a value between min and max
     */
    inline public static function clamp(n:Float, l:Float, h:Float):Float {
        return Math.max(l, Math.min(h, n));
    }
    
    /**
     * Rotate a point around the origin
     */
    public static function rotate(x:Float, y:Float, angle:Float, ?point:FlxPoint):FlxPoint {
        final p = point == null ? FlxPoint.weak() : point;
        final cos = Math.cos(angle);
        final sin = Math.sin(angle);
        p.set((x * cos) - (y * sin), (x * sin) + (y * cos));
        return p;
    }
    
    /**
     * Quantize a float value to a snap grid
     */
    inline public static function quantize(f:Float, snap:Float):Float {
        return Math.fround(f * snap) / snap;
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

	   /**
	    * Generate an array of integers from min to max (exclusive)
	    */
	   public static function numberArray(max:Int, ?min:Int = 0):Array<Int> {
	       return [for (i in min...max) i];
	   }
	   
	   /**
	    * Precache a sound asset
	    */
	   inline public static function precacheSound(sound:String, ?library:String):Void {
	       Paths.sound(sound, library);
	   }
	   
	   /**
	    * Precache a music asset
	    */
	   inline public static function precacheMusic(sound:String, ?library:String):Void {
	       Paths.music(sound, library);
	   }
	   
	   /**
	    * Precache an image asset
	    */
	   inline public static function precacheImage(name:String, ?library:String):Void {
	       Paths.image(name, library);
	   }
	   
	   /**
	    * Open a URL in the default browser
	    */
	   public static function browserLoad(site:String):Void {
	       #if linux
	       Sys.command('/usr/bin/xdg-open', [site]);
	       #else
	       FlxG.openURL(site);
	       #end
	   }
	   
	   /**
	    * Format a string for use as a key binding identifier
	    */
	   public static function formatBindString(str:String):String {
	       var finalStr = str;
	       for (notAllowed in formatNotAllowedChars) {
	           finalStr = StringTools.replace(finalStr, notAllowed, "");
	       }
	       return finalStr.toLowerCase();
	   }
	   
	   /**
	    * Find files with specific extensions in a directory
	    * @param path Directory to search
	    * @param extns Array of file extensions to look for
	    * @param filePath If true, returns full paths; otherwise just filenames
	    * @param deepSearch If true, recursively searches subdirectories
	    */
	   public static function findFilesInPath(path:String, extns:Array<String>, filePath:Bool = false, deepSearch:Bool = true):Array<String> {
	       var files:Array<String> = [];
	       
	       #if sys
	       if (!FileSystem.exists(path)) return files;
	       
	       for (file in FileSystem.readDirectory(path)) {
	           final fullPath = haxe.io.Path.join([path, file]);
	           
	           if (!FileSystem.isDirectory(fullPath)) {
	               for (extn in extns) {
	                   if (file.endsWith(extn)) {
	                       files.push(filePath ? fullPath : file);
	                       break;
	                   }
	               }
	           } else if (deepSearch) {
	               for (f in findFilesInPath(fullPath, extns, filePath, deepSearch)) {
	                   files.push(f);
	               }
	           }
	       }
	       #end
	       
	       return files;
	   }
	   
	   /**
	    * Extract filename without extension from a path
	    */
	   public static inline function getFileStringFromPath(file:String):String {
	       return Path.withoutDirectory(Path.withoutExtension(file));
	   }
	   
	   /**
	    * Get the save path for Flixel 5 compatibility
	    */
	   public static function getSavePath(folder:String = 'ShadowMario'):String {
	       @:privateAccess
	       return #if (flixel < "5.0.0")
	           folder
	       #else
	           FlxG.stage.application.meta.get('company') + '/' + FlxSave.validate(FlxG.stage.application.meta.get('file'))
	       #end;
	   }
	   
	   /**
	    * Parse a color from a string value
	    */
	   inline public static function colorFromString(color:String):FlxColor {
	       final hideChars = ~/[\t\n\r]/;
	       var colorStr = hideChars.split(color).join('').trim();
	       if (colorStr.startsWith('0x')) colorStr = colorStr.substring(colorStr.length - 6);
	       
	       var colorNum:Null<FlxColor> = FlxColor.fromString(colorStr);
	       if (colorNum == null) colorNum = FlxColor.fromString('#$colorStr');
	       return colorNum != null ? colorNum : FlxColor.WHITE;
	   }
	   
	   /**
	    * Show a popup dialog
	    */
	   public static function showPopUp(message:String, title:String):Void {
	       #if android
	       android.Tools.showAlertDialog(title, message, {name: "OK", func: null}, null);
	       #else
	       FlxG.stage.window.alert(message, title);
	       #end
	   }
}
