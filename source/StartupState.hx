package;

import backend.MusicBeatState;
import backend.CustomTilesTransition;

import flixel.FlxG;
import flixel.FlxState;
import flixel.FlxSprite;
import flixel.tweens.*;
import flixel.addons.transition.FlxTransitionableState;
import flixel.input.keyboard.FlxKey;

#if sys
import Sys.time as getTime;
#else
import haxe.Timer.stamp as getTime;
#end

#if desktop
import backend.Discord.DiscordClient;
import lime.app.Application;
#end

using StringTools;

// Loads the title screen, alongside some other stuff.

class StartupState extends MusicBeatState
{
	public static var muteKeys:Array<FlxKey> = [FlxKey.ZERO];
	public static var volumeDownKeys:Array<FlxKey> = [FlxKey.NUMPADMINUS, FlxKey.MINUS];
	public static var volumeUpKeys:Array<FlxKey> = [FlxKey.NUMPADPLUS, FlxKey.PLUS];
	public static var fullscreenKeys:Array<FlxKey> = [FlxKey.F11];

	public static var nextState:Class<FlxState> = funkin.states.TitleState;

	public function new()
	{
		super();
	}

	private static var loaded = false;
	public static function load():Void
	{
		if (loaded)
			return;
		loaded = true;

		ClientPrefs.initialize();
		ClientPrefs.load();

		FlxG.sound.volume = ClientPrefs.masterVolume;
		FlxG.sound.volumeHandler = (vol:Float)->{
			ClientPrefs.masterVolume = vol;
			Main.volumeChangedEvent.dispatch(vol);
		}

		FlxG.fixedTimestep = false;
		FlxG.keys.preventDefaultKeys = [TAB];

		#if (windows || linux) // No idea if this also applies to any other targets
		FlxG.stage.addEventListener(
			openfl.events.KeyboardEvent.KEY_DOWN, 
			(e)->{
				// Prevent Flixel from listening to key inputs when switching fullscreen mode
				if (e.keyCode == FlxKey.ENTER && e.altKey)
					e.stopImmediatePropagation();

				// Also add F11 to switch fullscreen mode
				if (fullscreenKeys.contains(e.keyCode)){
					FlxG.fullscreen = !FlxG.fullscreen;
					e.stopImmediatePropagation();
				}
			}, 
			false, 
			100
		);

		FlxG.stage.addEventListener(
			openfl.events.FullScreenEvent.FULL_SCREEN, 
			(e) -> FlxG.save.data.fullscreen = e.fullScreen
		);
		#end


		Paths.getAllStrings();
		
		funkin.data.Highscore.load();
		
		#if discord_rpc
		Application.current.onExit.add((exitCode)->{
			DiscordClient.shutdown();
		});
		#end

		FlxTransitionableState.defaultTransIn = FadeTransitionSubstate;
		FlxTransitionableState.defaultTransOut = FadeTransitionSubstate;
	}

	private var step:Int = 0;
	private var loadingTime:Float = getTime();


	inline private function doLoading()
	{
		load();
		final stateLoad:Dynamic = Reflect.getProperty(nextState, "load");
		if (stateLoad != null) Reflect.callMethod(null, stateLoad, []);

		loadingTime = getTime() - loadingTime;
	}

	var fadeTwn:FlxTween = null;
	override function update(elapsed:Float)
	{
		switch (step){
			case 0:
				#if !MULTICORE_LOADING
				doLoading();
				step = 10;

				#else
				if (loadingMutex == null){
					loadingMutex = new Mutex();
					Thread.create(() -> {
						loadingMutex.acquire();
						doLoading();
						loadingMutex.release();
					});
				}
				else if (loadingMutex.tryAcquire()){
					// is this necessary or at least favorable
					loadingMutex.release();
					loadingMutex = null;

					step = 10;
				}
				//else warning.angle += elapsed * 25;
				#end
				
			case 10:
				trace('loading lasted $loadingTime');

				#if !tgt
				step = 50;
				#else

				#if debug
				final waitTime:Float = 0.0;
				#else
				final waitTime:Float = (nextState == funkin.states.PlayState || nextState == funkin.states.editors.ChartingState) ? 0.0 : Math.max(0.0, 1.6 - loadingTime);
				#end

				step = 30;

				fadeTwn = FlxTween.tween(warning, {alpha: 0}, 1.0, {
					ease: FlxEase.expoIn,
					startDelay: waitTime,
					onStart: (twn)->{step = 40;},
					onComplete: (twn)->{step = 50;}
				});
				
			case 30:
				if (FlxG.keys.justPressed.ANY || FlxG.mouse.justPressed){
					fadeTwn.startDelay = 0;
					step = 40;
				}
			case 40:
				if (FlxG.keys.justPressed.ANY || FlxG.mouse.justPressed){
					fadeTwn.percent = (1.0 + fadeTwn.percent) * 0.5;
				}
				#end

			case 50:
				#if DO_AUTO_UPDATE
				if (Main.outOfDate)
					MusicBeatState.switchState(new UpdaterState(Main.recentRelease)); // UPDATE!!
				else
				#end
				{
					MusicBeatState.switchState(Type.createInstance(nextState, []));
				}
				step = 100000;
		}

		super.update(elapsed);
	}
}
