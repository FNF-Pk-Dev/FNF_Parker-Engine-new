package android.hitboxskin;

import flixel.FlxG;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import android.flixel.FlxButton;
import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.geom.Matrix;

/**
 * A zone with 4 hint's (A hitbox).
 * It's really easy to customize the layout.
 *
 * @author Mihai Alexandru (M.A. Jigsaw)
 */
class Gradient extends FlxSpriteGroup
{
	final offsetFir:Int = (ClientPrefs.hitboxPT ? Std.int(FlxG.height / 4) * 3 : 0);
	final offsetSec:Int = (ClientPrefs.hitboxPT ? 0 : Std.int(FlxG.height / 4));

	public var hints(default, null):Array<FlxButton>;

	/**
	 * Create the zone.
	 * 
	 * @param ammo The ammount of hints you want to create.
	 * @param perHintWidth The width that the hints will use.
	 * @param perHintHeight The height that the hints will use.
	 * @param colors The color per hint.
	 */
	public function new(ammo:UInt, perHintWidth:Int, perHintHeight:Int, colors:Array<FlxColor>):Void
	{
		super();

		hints = new Array<FlxButton>();

		if (colors == null || (colors != null && colors.length < ammo))
			colors = [0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF];

		for (i in 0...ammo)
			add(hints[i] = createHint(i * perHintWidth, (ClientPrefs.hitboxLocation == "Space") ? offsetSec : 0, perHintWidth,
				(ClientPrefs.hitboxLocation == "Space") ? Std.int(FlxG.height / ammo) * 3 : perHintHeight, colors[i]));

		if (ClientPrefs.hitboxLocation == "Space")
			add(hints[4] = createHint(0, offsetFir, FlxG.width, Std.int(FlxG.height / 4), 0xFFFFFF00));

		scrollFactor.set();
	}

	/**
	 * Clean up memory.
	 */
	override public function destroy():Void
	{
		super.destroy();

		for (i in 0...hints.length)
			hints[i] = FlxDestroyUtil.destroy(hints[i]);

		hints.splice(0, hints.length);
	}

	private function createHint(X:Float, Y:Float, Width:Int, Height:Int, Color:Int = 0xFFFFFF):FlxButton
	{
		final guh2:Float = 0.00001;
		final guh:Float = ClientPrefs.hitboxalpha >= 0.9 ? ClientPrefs.hitboxalpha - 0.2 : ClientPrefs.hitboxalpha;
		var hint:FlxButton = new FlxButton(X, Y);
		hint.loadGraphic(createHintGraphic(Width, Height, Color));
		hint.solid = false;
		hint.multiTouch = true;
		hint.immovable = true;
		hint.moves = false;
		hint.antialiasing = ClientPrefs.globalAntialiasing;
		hint.scrollFactor.set();
		hint.alpha = guh2;
			hint.onDown.callback = function()
			{
				if (hint.alpha != guh)
					hint.alpha = guh;
			}
			hint.onUp.callback = function()
			{
				if (hint.alpha != guh2)
					hint.alpha = guh2;
			}
			hint.onOut.callback = function()
			{
				if (hint.alpha != guh2)
					hint.alpha = guh2;
			}
		#if FLX_DEBUG
		hint.ignoreDrawDebug = true;
		#end
		return hint;
	}

	private function createHintGraphic(Width:Int, Height:Int, Color:Int = 0xFFFFFF):BitmapData
	{
		var guh:Float = ClientPrefs.hitboxalpha;
		if (guh >= 0.9)
			guh = ClientPrefs.hitboxalpha - 0.07;
		var shape:Shape = new Shape();
		shape.graphics.beginFill(Color);
			var matrix:Matrix = new Matrix();
			matrix.createGradientBox(Width, Height, 0, 0, 0);

			shape.graphics.beginGradientFill(RADIAL, [Color, Color], [0, guh], [60, 255], matrix, PAD, RGB, 0);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.endFill();
		var bitmap:BitmapData = new BitmapData(Width, Height, true, 0);
		bitmap.draw(shape, true);
		return bitmap;
	}
}
