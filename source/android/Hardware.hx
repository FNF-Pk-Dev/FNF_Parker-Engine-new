package android;

import lime.system.JNI;

class Hardware
{
	/**
	 * Base Orientation of the phone.
	 */
	public static inline var ORIENTATION_UNSPECIFIED:Int = 0;

	public static inline var ORIENTATION_PORTRAIT:Int = 1;
	public static inline var ORIENTATION_LANDSCAPE:Int = 2;

	/**
	 * Makes the Phone vibrate, the time is in milliseconds btw.
	 *
	 * Goes through lime's own haptic backend (`org/haxe/lime/GameActivity.vibrate`), which lime ships
	 * in its Android template and which already handles the API-level differences (and returns
	 * quietly when the device has no vibrator). The previous implementation called
	 * `org/haxe/extension/Hardware` - a class no haxelib in this project provides - so every call was
	 * a JNI lookup failure, which is the error that appeared in the log as soon as the "Vibrations"
	 * setting was enabled on the phone.
	 */
	public static function vibrate(inputValue:Int):Void
	{
		#if (android || ios || web)
		// `period == 0` = one vibration lasting `duration` ms, the same shape the old call had.
		lime.ui.Haptic.vibrate(0, inputValue);
		#end
	}

	/**
	 * The Name of the function says all.
	 */
	public static function wakeUp():Void
	{
		var wakeUp_jni = JNI.createStaticMethod("org/haxe/extension/Hardware", "wakeUp", "()V");
		wakeUp_jni();
	}

	/**
	 * Sets the phone brightness, max is 1 and min is 0.
	 */
	public static function setBrightness(brightness:Float):Void
	{
		var setbrightness_set_brightness_jni = JNI.createStaticMethod("org/haxe/extension/Hardware", "setBrightness", "(F)V");
		setbrightness_set_brightness_jni(brightness);
	}

	/**
	 * The Name of the function says all.
	 */
	public static function setScreenOrientation(screenOrientation:Int):Void
	{
		var setRequestedOrientationNative = JNI.createStaticMethod("org/haxe/extension/Hardware", "setRequestedOrientation", "(I)V");
		setRequestedOrientationNative(screenOrientation);
	}

	/**
	 * Returns the full screen width.
	 */
	public static function getScreenWidth():Int
	{
		var get_screen_width_jni = JNI.createStaticMethod("org/haxe/extension/Hardware", "getScreenWidth", "()I");
		return get_screen_width_jni();
	}

	/**
	 * Returns the full screen height.
	 */
	public static function getScreenHeight():Int
	{
		var get_screen_height_jni = JNI.createStaticMethod("org/haxe/extension/Hardware", "getScreenHeight", "()I");
		return get_screen_height_jni();
	}
}
