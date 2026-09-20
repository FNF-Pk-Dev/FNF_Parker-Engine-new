package states;

#if desktop
import sys.thread.Thread;
#end
import flixel.util.FlxColor;
import flixel.util.FlxGradient;
import lime.app.Promise;
import lime.app.Future;
import flixel.FlxG;
import flixel.FlxState;
import flixel.FlxSprite;
import flixel.util.FlxTimer;
import flixel.math.FlxMath;
import flixel.FlxCamera;
import flixel.text.FlxText;
import haxe.Json;
import openfl.utils.Assets;
import lime.utils.Assets as LimeAssets;
import lime.utils.AssetLibrary;
import lime.utils.AssetManifest;
import haxe.io.Path;
import openfl.Assets;
import obj.PowerPuffGirl;

typedef LoadingRunData =
{
	loadingrunx:Float,
	loadingruny:Float,
	loadingRunSprite:String,
	loadingrunfps:Int,
	loadingrunloop:Bool,
	scaleloadingrun:Float,
	loadingrunaddbyprefix:String,
	loadingRunvisible:Bool,
	backgroundSprite:String,
	backgroundvisible:Bool,
	loadbarvisible:Bool,
	fadeTime:Float,
	?usePowerPuffGirls:Bool
}

class LoadingState extends MusicBeatState
{
	inline static var MIN_TIME = 1.0;

	public static var preloadedInst:String = null;
	public static var preloadedVoices:String = null;

	var funkay:FlxSprite;

	public var loadingRun:FlxSprite;

	var loadingRunJSON:LoadingRunData;
	var camOther:FlxCamera;
	var target:FlxState;
	var stopMusic = false;
	var directory:String;
	var callbacks:MultiCallback;
	var targetShit:Float = 0;

	// PowerPuff Girls loading
	var ppgLoading:PowerPuffGirl;
	var gradientBg:FlxSprite;
	var cloudSprites:Array<FlxSprite> = [];
	var cloudSpeeds:Array<Float> = [];
	var loadingTextBg:FlxSprite;
	var loadingText:FlxText;
	var usePowerPuffGirls:Bool = true;
	var ppgIntroDone:Bool = false;
	var ppgIdlePlaying:Bool = false;
	var ppgPendingOutro:Bool = false;
	var flyOutStarted:Bool = false;

	function new(target:FlxState, stopMusic:Bool, directory:String)
	{
		super();
		this.target = target;
		this.stopMusic = stopMusic;
		this.directory = directory;
	}

	var loadBar:FlxSprite;

	override function create()
	{
		CoolUtil.precacheImage("ui/diaTrans");

		loadingRunJSON = Json.parse(Paths.getTextFromFile('images/loading/loading.json'));

		// Check if PowerPuff Girls mode is enabled (default true)
		usePowerPuffGirls = loadingRunJSON.usePowerPuffGirls != null ? loadingRunJSON.usePowerPuffGirls : true;

		camOther = new FlxCamera();
		camOther.bgColor.alpha = 0;
		FlxG.cameras.add(camOther, false);
		CustomFadeTransition.nextCamera = camOther;

		if (usePowerPuffGirls)
		{
			createPowerPuffGirlsLoading();
		}
		else
		{
			createClassicLoading();
		}

		#if android
		addTouchPad("NONE", "A");
		#end

		initSongsManifest().onComplete(function(lib)
		{
			callbacks = new MultiCallback(onLoad);
			var introComplete = callbacks.add("introComplete");

			checkLibrary("shared");
			if (directory != null && directory.length > 0 && directory != 'shared')
			{
				checkLibrary(directory);
			}

			FlxG.camera.fade(FlxG.camera.bgColor, 0.2, true);

			new FlxTimer().start(0.3, function(_)
			{
				introComplete();
			});
		});
	}

	function createPowerPuffGirlsLoading():Void
	{
		gradientBg = FlxGradient.createGradientFlxSprite(FlxG.width, FlxG.height, [0xFF8CCBFF, 0xFF2B5E95], 1, 90);
		gradientBg.scrollFactor.set();
		gradientBg.cameras = [camOther];
		add(gradientBg);

		createClouds();

		ppgLoading = new PowerPuffGirl(0, 0);
		ppgLoading.cameras = [camOther];
		add(ppgLoading);

		ppgIntroDone = false;
		ppgIdlePlaying = false;
		ppgPendingOutro = false;

		ppgLoading.playIntro(function()
		{
			ppgIntroDone = true;
			if (ppgPendingOutro)
			{
				playPpgOutro();
			}
			else
			{
				ppgIdlePlaying = true;
				ppgLoading.playIdle();
			}
		});

		createLoadingText();
	}

	function createClassicLoading():Void
	{
		var bg:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		add(bg);
		funkay = new FlxSprite(0, 0).loadGraphic(Paths.image('loading/' + loadingRunJSON.backgroundSprite));
		funkay.setGraphicSize(FlxG.width, FlxG.height);
		funkay.updateHitbox();
		funkay.antialiasing = ClientPrefs.globalAntialiasing;
		add(funkay);
		funkay.visible = loadingRunJSON.backgroundvisible;
		funkay.scrollFactor.set();
		funkay.screenCenter();

		loadingRun = new FlxSprite();
		loadingRun.x = loadingRunJSON.loadingrunx;
		loadingRun.y = loadingRunJSON.loadingruny;
		loadingRun.frames = Paths.getSparrowAtlas('loading/' + loadingRunJSON.loadingRunSprite);
		loadingRun.animation.addByPrefix('idle', loadingRunJSON.loadingrunaddbyprefix, loadingRunJSON.loadingrunfps, loadingRunJSON.loadingrunloop);
		loadingRun.animation.play('idle');
		loadingRun.antialiasing = ClientPrefs.globalAntialiasing;
		loadingRun.updateHitbox();
		loadingRun.scale.x = loadingRunJSON.scaleloadingrun;
		loadingRun.scale.y = loadingRunJSON.scaleloadingrun;
		loadingRun.cameras = [camOther];
		loadingRun.visible = loadingRunJSON.loadingRunvisible;
		add(loadingRun);

		loadBar = new FlxSprite(0, FlxG.height - 20).makeGraphic(FlxG.width, 10, 0xffff16d2);
		loadBar.screenCenter(X);
		loadBar.antialiasing = ClientPrefs.globalAntialiasing;
		loadBar.visible = loadingRunJSON.loadbarvisible;
		add(loadBar);
	}

	function createClouds():Void
	{
		cloudSprites = [];
		cloudSpeeds = [];

		var cloudKeys = [
			"ui/ANI_loading_Atlas/comp_000",
			"ui/ANI_loading_Atlas/comp_001",
			"ui/ANI_loading_Atlas/comp_002",
			"ui/ANI_loading_Atlas/comp_003",
			"ui/ANI_loading_Atlas/comp_004",
			"ui/ANI_loading_Atlas/comp_005",
			"ui/ANI_loading_Atlas/comp_006",
			"ui/ANI_loading_Atlas/comp_007",
			"ui/ANI_loading_Atlas/comp_008",
			"ui/ANI_loading_Atlas/comp_009",
			"ui/ANI_loading_Atlas/comp_010"
		];

		var cloudCount:Int = 10;
		for (i in 0...cloudCount)
		{
			var key = cloudKeys[FlxG.random.int(0, cloudKeys.length - 1)];
			var cloud = new FlxSprite();
			cloud.loadGraphic(Paths.image(key));
			cloud.antialiasing = ClientPrefs.globalAntialiasing;
			cloud.scrollFactor.set();
			var scale = FlxG.random.float(0.8, 1.35);
			cloud.scale.set(scale, scale);
			cloud.updateHitbox();
			cloud.x = FlxG.random.float(-cloud.width, FlxG.width);
			cloud.y = FlxG.random.float(0, FlxG.height + 50);
			cloud.alpha = FlxG.random.float(0.6, 1);
			cloud.cameras = [camOther];
			add(cloud);
			cloudSprites.push(cloud);
			cloudSpeeds.push(FlxG.random.float(12, 32));
		}
	}

	function updateClouds(elapsed:Float):Void
	{
		if (cloudSprites == null || cloudSpeeds == null)
			return;

		for (i in 0...cloudSprites.length)
		{
			var cloud = cloudSprites[i];
			cloud.y -= cloudSpeeds[i] * elapsed;
			if (cloud.y + cloud.height < -20)
			{
				cloud.y = FlxG.height + FlxG.random.float(10, 120);
				cloud.x = FlxG.random.float(-cloud.width, FlxG.width);
				cloudSpeeds[i] = FlxG.random.float(12, 32);
			}
		}
	}

	function createLoadingText():Void
	{
		var barHeight:Int = 36;
		loadingTextBg = new FlxSprite(0, FlxG.height - barHeight).makeGraphic(FlxG.width, barHeight, FlxColor.BLACK);
		loadingTextBg.scrollFactor.set();
		loadingTextBg.cameras = [camOther];
		add(loadingTextBg);

		loadingText = new FlxText(0, loadingTextBg.y + 6, FlxG.width, getLoadingLabel(), 18);
		loadingText.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, CENTER);
		loadingText.scrollFactor.set();
		loadingText.cameras = [camOther];
		add(loadingText);
	}

	function getLoadingLabel():String
	{
		var names = ["BLOSSOM", "BUBBLES", "BUTTERCUP"];
		var pick = names[FlxG.random.int(0, names.length - 1)];
		return "LOADING " + pick;
	}

	function playPpgOutro():Void
	{
		if (flyOutStarted)
			return;
		flyOutStarted = true;
		ppgPendingOutro = false;
		ppgIdlePlaying = false;

		if (ppgLoading != null)
		{
			ppgLoading.playOutro(function()
			{
				MusicBeatState.switchState(target);
			});
		}
		else
		{
			MusicBeatState.switchState(target);
		}
	}

	function checkLoadSong(path:String)
	{
		if (!Assets.cache.hasSound(path))
		{
			var library = Assets.getLibrary("songs");
			final symbolPath = path.split(":").pop();
			var callback = callbacks.add("song:" + path);

			Assets.loadSound(path).onComplete(function(_)
			{
				trace('Loaded: ' + path);
				callback();
			}).onError(function(e)
			{
					trace('Failed to load: ' + path + ' - ' + e);
					callback();
			});
		}
	}

	function checkLibrary(library:String)
	{
		trace(Assets.hasLibrary(library));
		if (Assets.getLibrary(library) == null)
		{
			@:privateAccess
			if (!LimeAssets.libraryPaths.exists(library))
				throw "Missing library: " + library;

			var callback = callbacks.add("library:" + library);
			Assets.loadLibrary(library).onComplete(function(_)
			{
				callback();
			});
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (usePowerPuffGirls)
		{
			updateClouds(elapsed);
		}

		if (!usePowerPuffGirls && funkay != null)
		{
			funkay.setGraphicSize(Std.int(0.88 * FlxG.width + 0.9 * (funkay.width - 0.88 * FlxG.width)));
			funkay.updateHitbox();
			if (controls != null && controls.ACCEPT)
			{
				funkay.setGraphicSize(Std.int(funkay.width + 60));
				funkay.updateHitbox();
			}
		}

		if (callbacks != null)
		{
			targetShit = FlxMath.remapToRange(callbacks.numRemaining / callbacks.length, 1, 0, 0, 1);
			if (loadBar != null)
			{
				if (usePowerPuffGirls)
				{
					loadBar.scale.x += 0.2 * (targetShit - loadBar.scale.x);
				}
				else
				{
					loadBar.scale.x += 0.5 * (targetShit - loadBar.scale.x);
				}
			}
		}
	}

	function onLoad()
	{
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		if (usePowerPuffGirls && !flyOutStarted)
		{
			ppgPendingOutro = true;
			if (ppgIntroDone || ppgIdlePlaying)
			{
				playPpgOutro();
			}
		}
		else if (!usePowerPuffGirls)
		{
			MusicBeatState.switchState(target);
		}
	}

	static function getSongPath()
	{
		return Paths.inst(PlayState.SONG.song);
	}

	static function getVocalPath()
	{
		return Paths.voices(PlayState.SONG.song);
	}

	inline static public function loadAndSwitchState(target:FlxState, stopMusic = false)
	{
		MusicBeatState.switchState(getNextState(target, stopMusic));
	}

	static function getNextState(target:FlxState, stopMusic = false):FlxState
	{
		var directory:String = 'shared';
		var weekDir:String = StageData.forceNextDirectory;
		StageData.forceNextDirectory = null;

		if (weekDir != null && weekDir.length > 0 && weekDir != '')
			directory = weekDir;

		Paths.setCurrentLevel(directory);
		trace('Setting asset folder to ' + directory);

		var loaded:Bool = false;
		if (PlayState.SONG != null)
		{
			var instLoaded = isSoundLoaded(getSongPath());
			var voicesLoaded = !PlayState.SONG.needsVoices || isSoundLoaded(getVocalPath());
			var sharedLoaded = isLibraryLoaded("shared");
			var dirLoaded = isLibraryLoaded(directory);

			loaded = instLoaded && voicesLoaded && sharedLoaded && dirLoaded;

			trace('=== Cache Check ===');
			trace('Inst: ' + instLoaded + ' | Voices: ' + voicesLoaded);
			trace('Shared: ' + sharedLoaded + ' | Dir: ' + dirLoaded);
			trace('All loaded: ' + loaded);
		}

		if (!loaded)
		{
			trace('Not fully cached - showing loading screen');
			return new LoadingState(target, stopMusic, directory);
		}

		trace('Fully cached - skipping loading screen!');
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		return target;
	}

	static function isSoundLoaded(path:String):Bool
	{
		return Assets.cache.hasSound(path);
	}

	static function isLibraryLoaded(library:String):Bool
	{
		return Assets.getLibrary(library) != null;
	}

	override function destroy()
	{
		#if android
		if (_touchpad != null)
			removeTouchPad();
		#end

		super.destroy();

		callbacks = null;
	}

	static function initSongsManifest()
	{
		var id = "songs";
		var promise = new Promise<AssetLibrary>();

		var library = LimeAssets.getLibrary(id);

		if (library != null)
		{
			return Future.withValue(library);
		}

		var path = id;
		var rootPath = null;

		@:privateAccess
		var libraryPaths = LimeAssets.libraryPaths;
		if (libraryPaths.exists(id))
		{
			path = libraryPaths[id];
			rootPath = Path.directory(path);
		}
		else
		{
			if (StringTools.endsWith(path, ".bundle"))
			{
				rootPath = path;
				path += "/library.json";
			}
			else
			{
				rootPath = Path.directory(path);
			}
			@:privateAccess
			path = LimeAssets.__cacheBreak(path);
		}

		AssetManifest.loadFromFile(path, rootPath).onComplete(function(manifest)
		{
			if (manifest == null)
			{
				promise.error("Cannot parse asset manifest for library \"" + id + "\"");
				return;
			}

			var library = AssetLibrary.fromManifest(manifest);

			if (library == null)
			{
				promise.error("Cannot open library \"" + id + "\"");
			}
			else
			{
				@:privateAccess
				LimeAssets.libraries.set(id, library);
				library.onChange.add(LimeAssets.onChange.dispatch);
				promise.completeWith(Future.withValue(library));
			}
		}).onError(function(_)
		{
				promise.error("There is no asset library with an ID of \"" + id + "\"");
		});

		return promise.future;
	}
}

class MultiCallback
{
	public var callback:Void->Void;
	public var logId:String = null;
	public var length(default, null) = 0;
	public var numRemaining(default, null) = 0;

	var unfired = new Map<String, Void->Void>();
	var fired = new Array<String>();

	public function new(callback:Void->Void, logId:String = null)
	{
		this.callback = callback;
		this.logId = logId;
	}

	public function add(id = "untitled")
	{
		id = '$length:$id';
		length++;
		numRemaining++;
		var func:Void->Void = null;
		func = function()
		{
			if (unfired.exists(id))
			{
				unfired.remove(id);
				fired.push(id);
				numRemaining--;

				if (logId != null)
					log('fired $id, $numRemaining remaining');

				if (numRemaining == 0)
				{
					if (logId != null)
						log('all callbacks fired');
					callback();
				}
			}
			else
				log('already fired $id');
		}
		unfired[id] = func;
		return func;
	}

	inline function log(msg):Void
	{
		if (logId != null)
			trace('$logId: $msg');
	}

	public function getFired()
		return fired.copy();

	public function getUnfired()
		return [for (id in unfired.keys()) id];
}
