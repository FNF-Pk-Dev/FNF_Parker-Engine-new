package android.backend;

#if android
import flixel.FlxG;
#end

/**
 * Handles Android back button press for Android 13+ (API 33+) predictive back gestures.
 * 
 * IMPORTANT: On Android 13+, predictive back gestures don't generate key events.
 * This class uses reflection/JNI to register an OnBackInvokedCallback with the Android Activity.
 */
class AndroidBackHandler
{
	#if android
	private static var onBackCallback:Void->Bool = null;
	private static var initialized:Bool = false;
	#end

	/**
	 * Initialize back press handling for Android 13+
	 * @param callback Return true to show pause menu, false to exit app
	 */
	public static function init(callback:Void->Bool):Void
	{
		#if android
		onBackCallback = callback;
		
		if (!initialized)
		{
			initialized = true;
			setupNativeBackHandler();
		}
		#end
	}

	#if android
	private static function setupNativeBackHandler():Void
	{
		try
		{
			// Try to register the back callback with the Android Activity using reflection
			var activityClass:Dynamic = Type.resolveClass("org.haxe.lime.GameActivity");
			if (activityClass != null)
			{
				var registerMethod = Reflect.field(activityClass, "registerBackCallback");
				if (registerMethod != null)
				{
					Reflect.callMethod(activityClass, registerMethod, []);
					trace("AndroidBackHandler: Native back callback registered via reflection");
				}
			}
		}
		catch (e:Dynamic)
		{
			trace("AndroidBackHandler: Reflection method not available - " + e);
			trace("AndroidBackHandler: Falling back to KEY events only");
		}
	}

	/**
	 * Called from native code when back is pressed via predictive back gesture
	 * Returns true if back press was consumed (pause menu shown), false to exit
	 */
	public static function handleBackPress():Bool
	{
		trace("AndroidBackHandler: handleBackPress called");
		
		if (onBackCallback != null)
		{
			var consume = onBackCallback();
			trace("AndroidBackHandler: Callback returned " + consume);
			return consume;
		}
		
		// Default behavior: consume back press (show pause menu if in PlayState)
		if (FlxG.state != null && Std.is(FlxG.state, states.game.PlayState))
		{
			var playState:states.game.PlayState = cast FlxG.state;
			if (!playState.paused && !playState.endingSong)
			{
				playState.openSubState(new substates.PauseSubState(
					playState.boyfriend.getScreenPosition().x,
					playState.boyfriend.getScreenPosition().y
				));
				return true;
			}
		}
		
		// Not in PlayState, allow back to exit
		return false;
	}
	#end
}
