package backend;

#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if !flash
import flixel.addons.display.FlxRuntimeShader;
#end
#if cpp
import cpp.vm.Gc;
#elseif hl
import hl.Gc;
#elseif neko
import neko.vm.Gc;
#end
import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFramesCollection;
import openfl.display.BitmapData;
import openfl.display3D.textures.RectangleTexture;
import openfl.system.System;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import lime.media.AudioBuffer;
import lime.media.vorbis.VorbisFile;
import lime.utils.Assets;
import haxe.Json;
import haxe.io.Bytes;
import openfl.media.Sound;

using StringTools;

class Paths
{
	inline public static var SOUND_EXT = #if web "mp3" #else "ogg" #end;
	inline public static var VIDEO_EXT = "mp4";

	#if MODS_ALLOWED
	public static var ignoreModFolders:Array<String> = [
		'characters',
		'custom_events',
		'custom_notetypes',
		'data',
		'songs',
		'music',
		'sounds',
		'shaders',
		'videos',
		'images',
		'stages',
		'states',
		'substates',
		'weeks',
		'fonts',
		'scripts',
		'achievements'
	];
	#end

	public static function excludeAsset(key:String):Void
	{
		if (!dumpExclusions.contains(key))
			dumpExclusions.push(key);
	}

	public static var dumpExclusions:Array<String> = [
		'assets/music/freakyMenu.$SOUND_EXT',
		'assets/shared/music/breakfast.$SOUND_EXT',
		'assets/shared/music/tea-time.$SOUND_EXT',
	];

	@:noCompletion private inline static function _gc(major:Bool):Void
	{
		#if (cpp || neko)
		Gc.run(major);
		#elseif hl
		Gc.major();
		#end
	}

	@:noCompletion public inline static function compress():Void
	{
		#if cpp
		Gc.compact();
		#elseif hl
		Gc.major();
		#elseif neko
		Gc.run(true);
		#end
	}

	public inline static function gc(major:Bool = false, repeat:Int = 1):Void
	{
		while (repeat-- > 0)
			_gc(major);
	}

	/// haya I love you for the base cache dump I took to the max
	public static function clearUnusedMemory():Void
	{
		// clear non local assets in the tracked assets list
		for (key in currentTrackedAssets.keys())
		{
			// if it is not currently contained within the used local assets
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key))
			{
				// get rid of it
				var obj = currentTrackedAssets.get(key);
				@:privateAccess
				if (obj != null)
				{
					openfl.Assets.cache.removeBitmapData(key);
					FlxG.bitmap._cache.remove(key);
					currentTrackedAssets.remove(key);
					obj.persist = false;
					obj.destroyOnNoUse = true;
					obj.destroy();
				}
			}
		}
		// run the garbage collector for good measure lmfao
		compress();
		gc(true);
		System.gc();
	}

	// define the locally tracked assets
	public static var localTrackedAssets:Array<String> = [];

	public static function clearStoredMemory(?cleanUnused:Bool = false):Void
	{
		// clear anything not in the tracked assets list
		@:privateAccess
		for (key in FlxG.bitmap._cache.keys())
		{
			var obj = FlxG.bitmap._cache.get(key);
			if (obj != null && !currentTrackedAssets.exists(key))
			{
				openfl.Assets.cache.removeBitmapData(key);
				FlxG.bitmap._cache.remove(key);
				obj.destroy();
			}
		}

		// clear all sounds that are cached
		for (key in currentTrackedSounds.keys())
		{
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key) && key != null)
			{
				Assets.cache.clear(key);
				currentTrackedSounds.remove(key);
			}
		}
		// flags everything to be cleared out next unused memory clear
		compress();
		gc(true);
		localTrackedAssets = [];
		openfl.Assets.cache.clear("songs");
		CoolUtil.precacheImage("ui/diaTrans");
	}

	static public var currentModDirectory:String = '';
	static public var currentLevel:String;

	static public function setCurrentLevel(name:String)
	{
		currentLevel = name.toLowerCase();
	}

	public static function getPath(file:String, type:AssetType, ?library:Null<String> = null)
	{
		if (library != null)
			return getLibraryPath(file, library);

		if (currentLevel != null)
		{
			var levelPath:String = '';
			if (currentLevel != 'shared')
			{
				levelPath = getLibraryPathForce(file, currentLevel);
				if (OpenFlAssets.exists(levelPath, type))
					return levelPath;
			}

			levelPath = getLibraryPathForce(file, "shared");
			if (OpenFlAssets.exists(levelPath, type))
				return levelPath;
		}

		return getPreloadPath(file);
	}

	static public function getLibraryPath(file:String, library = "preload")
	{
		return if (library == "preload" || library == "default") getPreloadPath(file); else getLibraryPathForce(file, library);
	}

	inline static function getLibraryPathForce(file:String, library:String)
	{
		var returnPath = '$library:assets/$library/$file';
		return returnPath;
	}

	inline public static function getPreloadPath(file:String = '')
	{
		return 'assets/$file';
	}

	inline static public function file(file:String, type:AssetType = TEXT, ?library:String)
	{
		return getPath(file, type, library);
	}

	inline static public function txt(key:String, ?library:String)
	{
		return getPath('data/$key.txt', TEXT, library);
	}

	inline static public function xml(key:String, ?library:String)
	{
		return getPath('data/$key.xml', TEXT, library);
	}

	inline static public function json(key:String, ?library:String)
	{
		return getPath('data/$key.json', TEXT, library);
	}

	inline static public function shaderFragment(key:String, ?library:String)
	{
		return getPath('shaders/$key.frag', TEXT, library);
	}

	inline static public function shaderVertex(key:String, ?library:String)
	{
		return getPath('shaders/$key.vert', TEXT, library);
	}

	inline static public function lua(key:String, ?library:String)
	{
		return getPath('$key.lua', TEXT, library);
	}

	static public function video(key:String)
	{
		#if MODS_ALLOWED
		var file:String = modsVideo(key);
		if (FileSystem.exists(file))
		{
			return #if ASSET_MODS AssetFiles.materialize(file) #else file #end;
		}
		#end
		var path = SUtil.getPath() + 'assets/videos/$key.$VIDEO_EXT';
		return #if ASSET_MODS AssetFiles.materialize(path) #else path #end;
	}

	static public function sound(key:String, ?library:String):Sound
	{
		var sound:Sound = returnSound('sounds', key, library);
		return sound;
	}

	inline static public function soundRandom(key:String, min:Int, max:Int, ?library:String)
	{
		return sound(key + FlxG.random.int(min, max), library);
	}

	inline static public function music(key:String, ?library:String):Sound
	{
		var file:Sound = returnSound('music', key, library);
		return file;
	}

	// Loads the Voices. Crucial for generateSong
	static public function voices(song:String, ?difficulty:String = '', ?postfix:String = null):Any
	{
		var formattedDifficulty:String = formatToSongPath(difficulty);
		if (difficulty.contains(' '))
			difficulty = formattedDifficulty;
		#if html5
		return 'songs:assets/songs/${formatToSongPath(song)}/Voices.$SOUND_EXT';
		#else
		if (difficulty != null)
		{
			var songKey:String = '${formatToSongPath(song)}/Voices';
			if (postfix != null)
				songKey += '-' + postfix;
			songKey += '-$difficulty';
			if (FileSystem.exists(Paths.modFolders('songs/' + songKey + '.$SOUND_EXT'))
				|| FileSystem.exists('assets/songs/' + songKey + '.$SOUND_EXT'))
			{
				var voices = returnSound('songs', songKey);
				return voices;
			}
		}
		var songKey:String = '${formatToSongPath(song)}/Voices';
		if (postfix != null)
			songKey += '-' + postfix;
		var voices = returnSound('songs', songKey);
		return voices;
		#end
	}

	// Loads the instrumental. Crucial for generateSong
	static public function inst(song:String, ?difficulty:String = ''):Any
	{
		var formattedDifficulty:String = formatToSongPath(difficulty);
		if (difficulty.contains(' '))
			difficulty = formattedDifficulty;
		#if html5
		return 'songs:assets/songs/${formatToSongPath(song)}/Inst.$SOUND_EXT';
		#else
		if (difficulty != null)
		{
			var songKey:String = '${formatToSongPath(song)}/Inst-$difficulty';
			if (FileSystem.exists(Paths.modFolders('songs/' + songKey + '.$SOUND_EXT'))
				|| FileSystem.exists('assets/songs/' + songKey + '.$SOUND_EXT'))
			{
				var inst = returnSound('songs', songKey);
				return inst;
			}
		}
		var songKey:String = '${formatToSongPath(song)}/Inst';
		var inst = returnSound('songs', songKey);
		return inst;
		#end
	}

	/** Resolve each mod/library before choosing a format, preserving override priority. */
	static function imageCandidates(key:String, ?library:String):Array<String>
	{
		var bases:Array<String> = [];
		#if MODS_ALLOWED
		if (currentModDirectory != null && currentModDirectory.length > 0)
			bases.push(mods(currentModDirectory + '/images/' + key));
		for (mod in getGlobalMods())
			bases.push(mods(mod + '/images/' + key));
		bases.push(mods('images/' + key));
		#end
		if (library != null)
			bases.push(getLibraryPath('images/' + key, library));
		else
		{
			if (currentLevel != null)
			{
				if (currentLevel != 'shared')
					bases.push(getLibraryPathForce('images/' + key, currentLevel));
				bases.push(getLibraryPathForce('images/' + key, 'shared'));
			}
			bases.push(getPreloadPath('images/' + key));
		}
		return bases;
	}

	static function imageFileExists(path:String):Bool
	{
		#if sys
		if (FileSystem.exists(path))
			return true;
		#end
		return Assets.exists(path);
	}

	public static function loadBitmap(path:String):BitmapData
	{
		if (path.toLowerCase().endsWith('.ktx') || path.toLowerCase().endsWith('.astc'))
		{
			var bytes:Bytes = null;
			#if sys
			if (FileSystem.exists(path))
				bytes = File.getBytes(path);
			else
			#end
			bytes = Assets.getBytes(path);
			return ASTCBitmapData.fromBytes(bytes);
		}
		#if sys
		if (FileSystem.exists(path))
			return BitmapData.fromFile(path);
		#end
		return OpenFlAssets.getBitmapData(path);
	}

	static public function image(key:String, ?library:String = null, ?allowGPU:Bool = true):FlxGraphic
	{
		// Existing scripts still request extensionless PNG names.
		for (base in imageCandidates(key, library))
		{
			var extensions = allowGPU && ASTCBitmapData.supported() ? ['.astc.ktx', '.astc', '.png'] : ['.png', '.astc.ktx', '.astc'];
			var found = false;
			var errors:Array<String> = [];
			for (extension in extensions)
			{
				var file = base + extension;
				if (currentTrackedAssets.exists(file))
				{
					localTrackedAssets.push(file);
					return currentTrackedAssets.get(file);
				}
				if (!imageFileExists(file))
					continue;
				found = true;
				try
				{
					var bitmap = loadBitmap(file);
					if (bitmap != null)
						return cacheBitmap(file, bitmap, allowGPU);
					errors.push(file + ': decoder returned null');
				}
				catch (error:Dynamic)
				{
					errors.push(file + ': ' + Std.string(error));
				}
			}
			// Do not substitute another mod's image when this mod owns the asset.
			if (found)
				throw 'Cannot load image: ' + errors.join('\n');
		}
		return null;
	}

	static public function cacheBitmap(file:String, ?bitmap:BitmapData = null, ?allowGPU:Bool = true)
	{
		if (bitmap == null)
		{
			if (!imageFileExists(file))
				return null;
			bitmap = loadBitmap(file);
			if (bitmap == null)
				return null;
		}

		localTrackedAssets.push(file);
		if (allowGPU && ClientPrefs.cacheOnGPU && bitmap.image != null)
		{
			var texture:RectangleTexture = FlxG.stage.context3D.createRectangleTexture(bitmap.width, bitmap.height, BGRA, true);
			texture.uploadFromBitmapData(bitmap);
			bitmap.image.data = null;
			bitmap.dispose();
			bitmap.disposeImage();
			bitmap = BitmapData.fromTexture(texture);
		}
		var newGraphic:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, file);
		newGraphic.persist = true;
		newGraphic.destroyOnNoUse = false;
		currentTrackedAssets.set(file, newGraphic);
		return newGraphic;
	}

	/*
		inline static public function gif(key:String, ?library:String):FlxGraphic
		{
			// streamlined the assets process more
			var returnAsset:FlxGraphic = returnGraphic(key, library);
			return returnAsset;
		}
	 */
	static public function getTextFromFile(key:String, ?ignoreMods:Bool = false):String
	{
		#if MODS_ALLOWED
		if (!ignoreMods && FileSystem.exists(modFolders(key)))
			return File.getContent(modFolders(key));

		if (FileSystem.exists(SUtil.getPath() + getPreloadPath(key)))
			return File.getContent(SUtil.getPath() + getPreloadPath(key));

		if (currentLevel != null)
		{
			var levelPath:String = '';
			if (currentLevel != 'shared')
			{
				levelPath = SUtil.getPath() + getLibraryPathForce(key, currentLevel);
				if (FileSystem.exists(levelPath))
					return File.getContent(levelPath);
			}

			levelPath = SUtil.getPath() + getLibraryPathForce(key, 'shared');
			if (FileSystem.exists(levelPath))
				return File.getContent(levelPath);
		}
		#end
		return Assets.getText(getPath(key, TEXT));
	}

	static public function font(key:String)
	{
		#if MODS_ALLOWED
		var file:String = modsFont(key);
		if (FileSystem.exists(file))
		{
			return file;
		}

		// scripts usually pass the font name without its extension (setTextFont(tag, 'SBF')
		// for fonts/SBF.ttf), so try the usual font extensions before giving up
		if (!hasFontExtension(key))
		{
			for (ext in FONT_EXTENSIONS)
			{
				var withExtension:String = modsFont(key + ext);
				if (FileSystem.exists(withExtension))
					return withExtension;
			}
		}
		#end

		var defaultPath:String = #if ASSET_MODS 'assets/fonts/$key' #else SUtil.getPath() + 'assets/fonts/$key' #end;
		#if MODS_ALLOWED
		if (!FileSystem.exists(defaultPath) && !hasFontExtension(key))
		{
			for (ext in FONT_EXTENSIONS)
			{
				var withExtension:String = defaultPath + ext;
				if (FileSystem.exists(withExtension))
					return withExtension;
			}
		}
		#end
		return defaultPath;
	}

	static final FONT_EXTENSIONS:Array<String> = ['.ttf', '.otf'];
	static var registeredFontNames:Map<String, String> = [];

	static function hasFontExtension(key:String):Bool
	{
		var lower:String = key.toLowerCase();
		for (ext in FONT_EXTENSIONS)
		{
			if (lower.endsWith(ext))
				return true;
		}
		return false;
	}

	/**
	 * Resolves a font key into a font name that FlxText can actually use.
	 * Scripts pass either a family name or a font file (`'SBF'` / `'SBF.ttf'`), and openfl
	 * only knows fonts that have been loaded from their file, so the file is registered here.
	 */
	static public function fontName(key:String):String
	{
		if (key == null || key.length < 1)
			return key;

		var path:String = font(key);

		#if sys
		if (path != null && FileSystem.exists(path))
		{
			var cacheKey:String = FileSystem.fullPath(path);
			if (registeredFontNames.exists(cacheKey))
				return registeredFontNames.get(cacheKey);
			var loaded:openfl.text.Font = openfl.text.Font.fromFile(path);
			if (loaded != null && loaded.fontName != null)
			{
				// fromFile() only decodes the file. TextField cannot resolve the returned
				// family name until the Font instance is registered with OpenFL.
				openfl.text.Font.registerFont(loaded);
				registeredFontNames.set(cacheKey, loaded.fontName);
				return loaded.fontName;
			}
		}
		#end

		if (path != null && OpenFlAssets.exists(path, FONT))
		{
			var assetFont:openfl.text.Font = OpenFlAssets.getFont(path);
			if (assetFont != null && assetFont.fontName != null)
				return assetFont.fontName;
		}

		return key;
	}

	static public function fileExists(key:String, type:AssetType, ?ignoreMods:Bool = false, ?library:String)
	{
		if (type == IMAGE && key.startsWith('images/') && key.endsWith('.png') && !ignoreMods)
		{
			for (base in imageCandidates(key.substr(7, key.length - 11), library))
				for (extension in ['.png', '.astc.ktx', '.astc'])
					if (imageFileExists(base + extension))
						return true;
		}

		#if MODS_ALLOWED
		if (FileSystem.exists(mods(currentModDirectory + '/' + key)) || FileSystem.exists(mods(key)))
		{
			return true;
		}
		#end

		if (OpenFlAssets.exists(getPath(key, type)))
		{
			return true;
		}
		return false;
	}

	inline static public function getSparrowAtlas(key:String, ?library:String, ?allowGPU:Bool = true)
	{
		#if MODS_ALLOWED
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);
		var xmlExists:Bool = false;
		if (FileSystem.exists(modsXml(key)))
		{
			xmlExists = true;
		}

		return FlxAtlasFrames.fromSparrow((imageLoaded != null ? imageLoaded : image(key, library)),
			(xmlExists ? File.getContent(modsXml(key)) : file('images/$key.xml', library)));
		#else
		return FlxAtlasFrames.fromSparrow(image(key, library), file('images/$key.xml', library));
		#end
	}

	inline static public function getPackerAtlas(key:String, ?library:String, ?allowGPU:Bool = true)
	{
		#if MODS_ALLOWED
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);
		var txtExists:Bool = false;
		if (FileSystem.exists(modsTxt(key)))
		{
			txtExists = true;
		}

		return FlxAtlasFrames.fromSpriteSheetPacker((imageLoaded != null ? imageLoaded : image(key, library)),
			(txtExists ? File.getContent(modsTxt(key)) : file('images/$key.txt', library)));
		#else
		return FlxAtlasFrames.fromSpriteSheetPacker(image(key, library), file('images/$key.txt', library));
		#end
	}

	inline static public function getXMLAtlas(key:String, ?library:String, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		#if MODS_ALLOWED
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);
		var xmlExists:Bool = false;
		if (FileSystem.exists(modsXml(key)))
		{
			xmlExists = true;
		}

		return FlxAtlasFrames.fromTexturePackerXml((imageLoaded != null ? imageLoaded : image(key, library)),
			(xmlExists ? File.getContent(modsXml(key)) : file('images/$key.xml', library)));
		#else
		return FlxAtlasFrames.fromTexturePackerXml(image(key, library), file('images/$key.xml', library));
		#end
	}

	inline static public function getJSONAtlas(key:String, ?library:String, ?allowGPU:Bool = true)
	{
		#if MODS_ALLOWED
		var imageLoaded:FlxGraphic = image(key, library, allowGPU);
		var jsonExists:Bool = false;
		if (FileSystem.exists(modsJsons(key)))
		{
			jsonExists = true;
		}

		return FlxAtlasFrames.fromTexturePackerJson((imageLoaded != null ? imageLoaded : image(key, library)),
			(jsonExists ? File.getContent(modsJsons(key)) : file('images/$key.json', library)));
		#else
		return FlxAtlasFrames.fromTexturePackerJson(image(key, library), file('images/$key.json', library));
		#end
	}

	inline static public function exists(path:String, ?type:AssetType):Bool
	{
		#if sys
		return FileSystem.exists(path);
		#else
		return Assets.exists(path, type);
		#end
	}

	inline static public function getContent(path:String):Null<String>
	{
		#if sys
		return FileSystem.exists(path) ? File.getContent(path) : null;
		#else
		return Assets.exists(path) ? Assets.getText(path) : null;
		#end
	}

	inline static public function formatToSongPath(path:String)
	{
		var invalidChars = ~/[~&\\;:<>#]/;
		var hideChars = ~/[.,'"%?!]/;

		var path = invalidChars.split(path.replace(' ', '-')).join("-");
		return hideChars.split(path).join("").toLowerCase();
	}

	public static var currentTrackedAssets:Map<String, FlxGraphic> = [];
	public static var currentTrackedSounds:Map<String, Sound> = [];

	// Returns sounds which is useful for all the sfx
	public static function returnSound(path:String, key:String, ?library:String, stream:Bool = false)
	{
		var sound:Sound = null;
		var file:String = null;

		#if MODS_ALLOWED
		file = modsSounds(path, key);
		if (currentTrackedSounds.exists(file))
		{
			localTrackedAssets.push(file);
			return currentTrackedSounds.get(file);
		}
		else if (FileSystem.exists(file))
		{
			#if lime_vorbis
			if (stream)
				sound = Sound.fromAudioBuffer(AudioBuffer.fromVorbisFile(VorbisFile.fromFile(#if ASSET_MODS AssetFiles.materialize(file) #else file #end)));
			else
			#end
			try
			{
				final bytes:Bytes = File.getBytes(file);
				final header:Bytes = bytes.sub(0, Std.int(Math.min(4, bytes.length)));
				if (header.toString() != "OggS" && file != null)
				{
					throw 'The file "$file" is not a valid OGG file (missing OggS header). It may have been renamed from another format like MP3.';
				}

				sound = #if ASSET_MODS Sound.fromAudioBuffer(AudioBuffer.fromBytes(bytes)) #else Sound.fromFile(file) #end;
			}
			catch (e)
			{
				throw 'Cannot load sound file: $file\nMake sure it is a properly encoded .ogg file.\nError: $e';
			}
		}
		else
		#end
		{
			// I hate this so god damn much
			var gottenPath:String = getPath('$path/$key.$SOUND_EXT', SOUND, library);
			file = gottenPath.substring(gottenPath.indexOf(':') + 1, gottenPath.length);
			if (path == 'songs')
				gottenPath = 'songs:' + gottenPath;
			if (currentTrackedSounds.exists(file))
			{
				localTrackedAssets.push(file);
				return currentTrackedSounds.get(file);
			}
			else if (OpenFlAssets.exists(gottenPath, SOUND))
			{
				#if lime_vorbis
				if (stream)
					sound = OpenFlAssets.getMusic(gottenPath);
				else
				#end
				sound = OpenFlAssets.getSound(gottenPath);
			}
		}

		if (sound != null)
		{
			localTrackedAssets.push(file);
			currentTrackedSounds.set(file, sound);
			return sound;
		}

		return null;
	}

	#if MODS_ALLOWED
	inline static public function mods(key:String = '')
	{
		return #if ASSET_MODS 'assets/mods/' + key #else SUtil.getPath() + 'mods/' + key #end;
	}

	inline static public function modsFont(key:String)
	{
		return modFolders('fonts/' + key);
	}

	inline static public function modsJson(key:String)
	{
		return modFolders('data/' + key + '.json');
	}

	inline static public function modsVideo(key:String)
	{
		return modFolders('videos/' + key + '.' + VIDEO_EXT);
	}

	inline static public function modsSounds(path:String, key:String)
	{
		return modFolders(path + '/' + key + '.' + SOUND_EXT);
	}

	inline static public function modsImages(key:String)
	{
		return modFolders('images/' + key + '.png');
	}

	inline static public function modsXml(key:String)
	{
		return modFolders('images/' + key + '.xml');
	}

	inline static public function modsJsons(key:String)
	{
		return modFolders('images/' + key + '.json');
	}

	inline static public function modsTxt(key:String)
	{
		return modFolders('images/' + key + '.txt');
	}

	// Goes unused for now

	inline static public function modsShaderFragment(key:String, ?library:String)
	{
		return modFolders('shaders/' + key + '.frag');
	}

	inline static public function modsShaderVertex(key:String, ?library:String)
	{
		return modFolders('shaders/' + key + '.vert');
	}

	inline static public function modsAchievements(key:String)
	{
		return modFolders('achievements/' + key + '.json');
	}

	static function getShaderFragment(name:String):Null<String>
	{
		#if MODS_ALLOWED
		var path = Paths.modsShaderFragment(name);
		if (Paths.exists(path))
			return path;
		#end
		var path = Paths.shaderFragment(name);
		if (Paths.exists(path))
			return path;
		return null;
	}

	static function getShaderVertex(name:String):Null<String>
	{
		#if MODS_ALLOWED
		var path = Paths.modsShaderVertex(name);
		if (Paths.exists(path))
			return path;
		#end
		var path = Paths.shaderVertex(name);
		if (Paths.exists(path))
			return path;
		return null;
	}

	public static function getShader(fragFile:String = null, vertFile:String = null, ?version:Int):FlxRuntimeShader
	{
		try
		{
			var fragPath:Null<String> = fragFile == null ? null : getShaderFragment(fragFile);
			var vertPath:Null<String> = fragFile == null ? null : getShaderVertex(vertFile);

			return new FlxRuntimeShader(fragFile == null ? null : Paths.getContent(fragPath), vertFile == null ? null : Paths.getContent(vertPath), version);
		}
		catch (e:Dynamic)
		{
			trace("Shader compilation error:" + e.message);
		}

		return null;
	}

	static public function modFolders(key:String)
	{
		if (currentModDirectory != null && currentModDirectory.length > 0)
		{
			var fileToCheck:String = mods(currentModDirectory + '/' + key);
			if (FileSystem.exists(fileToCheck))
			{
				return fileToCheck;
			}
		}

		for (mod in getGlobalMods())
		{
			var fileToCheck:String = mods(mod + '/' + key);
			if (FileSystem.exists(fileToCheck))
				return fileToCheck;
		}
		return mods(key);
	}

	public static var globalMods:Array<String> = [];

	static public function getGlobalMods()
		return globalMods;

	static public function pushGlobalMods() // prob a better way to do this but idc
	{
		globalMods = [];
		var path:String = SUtil.getPath() + 'modsList.txt';
		#if ASSET_MODS
		// No external mod scan/copy runs in packaged mode. Seed the writable load-order file once.
		if (!FileSystem.exists(path))
		{
			var bundledList = getPreloadPath('modsList.txt');
			var folders = getModDirectories();
			folders.sort(Reflect.compare);
			File.saveContent(path, FileSystem.exists(bundledList) ? File.getContent(bundledList) : [for (folder in folders) folder + '|1'].join('\n'));
		}
		#end
		if (FileSystem.exists(path))
		{
			var list:Array<String> = CoolUtil.coolTextFile(path);
			for (i in list)
			{
				var dat = i.split("|");
				if (dat[1] == "1")
				{
					var folder = dat[0];
					var path = Paths.mods(folder + '/pack.json');
					if (FileSystem.exists(path))
					{
						try
						{
							var rawJson:String = File.getContent(path);
							if (rawJson != null && rawJson.length > 0)
							{
								var stuff:Dynamic = Json.parse(rawJson);
								var global:Bool = Reflect.getProperty(stuff, "runsGlobally");
								if (global)
									globalMods.push(dat[0]);
							}
						}
						catch (e:Dynamic)
						{
							trace(e);
						}
					}
				}
			}
		}
		return globalMods;
	}

	static public function getModDirectories():Array<String>
	{
		var list:Array<String> = [];
		var modsFolder:String = mods();
		if (FileSystem.exists(modsFolder))
		{
			for (folder in FileSystem.readDirectory(modsFolder))
			{
				var path = haxe.io.Path.join([modsFolder, folder]);
				if (sys.FileSystem.isDirectory(path) && !ignoreModFolders.contains(folder) && !list.contains(folder))
				{
					list.push(folder);
				}
			}
		}
		return list;
	}
	#end

	public static function readDirectory(directory:String):Array<String>
	{
		#if MODS_ALLOWED
		return FileSystem.readDirectory(directory);
		#else
		var dirs:Array<String> = [];
		for (dir in Assets.list().filter(folder -> folder.startsWith(directory)))
		{
			@:privateAccess
			for (library in lime.utils.Assets.libraries.keys())
			{
				if (library != 'default' && Assets.exists('$library:$dir') && (!dirs.contains('$library:$dir') || !dirs.contains(dir)))
					dirs.push('$library:$dir');
				else if (Assets.exists(dir) && !dirs.contains(dir))
					dirs.push(dir);
			}
		}
		return dirs;
		#end
	}

	inline static public function getAtlasFromData(key:String, data:DataType, ?noAntialiasing:Bool = false):FlxFramesCollection
	{
		switch (data)
		{
			case SPARROW:
				return getSparrowAtlas(key);
			case GENERICXML:
				return getXMLAtlas(key);
			case PACKER:
				return getPackerAtlas(key);
			case JSON:
				return getJSONAtlas(key);
			case TEXTURE:
				return animateatlas.AtlasFrameMaker.construct(key, null, noAntialiasing);
		}
	}
}
