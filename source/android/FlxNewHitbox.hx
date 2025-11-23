package android;

import flixel.graphics.FlxGraphic;
import flixel.addons.ui.FlxButtonPlus;
import flixel.FlxSprite;
import flixel.FlxG;
import flixel.graphics.frames.FlxTileFrames;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxPoint;
import flixel.system.FlxAssets;
import flixel.util.FlxDestroyUtil;
import android.flixel.FlxButton;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame;
import flixel.ui.FlxVirtualPad;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import openfl.display.Shape;
import openfl.display.BitmapData;
import flixel.util.FlxColor;

class FlxNewHitbox extends FlxSpriteGroup
{
    public var hitbox:FlxSpriteGroup;

    var sizex:Int = 320;

    var screensizey:Int = 720;

    public var buttonLeft:FlxButton;
    public var buttonDown:FlxButton;
    public var buttonUp:FlxButton;
    public var buttonRight:FlxButton;
    public var buttonSpace:FlxButton;
    
    public function new()
    {
        super();

        /*if (widghtScreen == null)
            widghtScreen = FlxG.width;*/

        final offsetFir:Int = (ClientPrefs.hitboxPT ? Std.int(FlxG.height / 4) * 3 : 0);
		final offsetSec:Int = (ClientPrefs.hitboxPT ? 0 : Std.int(FlxG.height / 4));
		
        //add graphic
        hitbox = new FlxSpriteGroup();
        hitbox.scrollFactor.set();
        	if (ClientPrefs.hitboxLocation != 'Space'){
                hitbox.add(add(buttonLeft = createhitbox(0, 0xFF00FF)));
                hitbox.add(add(buttonDown = createhitbox(Std.int(FlxG.width / 4), 0x00FFFF)));
                hitbox.add(add(buttonUp = createhitbox(Std.int(FlxG.width / 4) * 2, 0x00FF00)));
                hitbox.add(add(buttonRight = createhitbox(Std.int(FlxG.width / 4) * 3, 0xFF0000)));
            }else{
                hitbox.add(add(buttonLeft = createhitbox(0, 0xFF00FF, offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3)));
                hitbox.add(add(buttonDown = createhitbox(Std.int(FlxG.width / 4), 0x00FFFF, offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3)));
                hitbox.add(add(buttonUp = createhitbox(Std.int(FlxG.width / 4) * 2, 0x00FF00, offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3)));
                hitbox.add(add(buttonRight = createhitbox(Std.int(FlxG.width / 4) * 3, 0xFF0000, offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3)));
                hitbox.add(add(buttonSpace = createhitbox(0, 0xFFFFFF00, offsetFir, FlxG.width, Std.int(FlxG.height / 4))));
       }
    }
    
    private function createHintGraphic(Width:Int, Height:Int, Color:Int = 0xFFFFFF):BitmapData
	{
		var shape:Shape = new Shape();

			shape.graphics.beginFill(Color);
			shape.graphics.lineStyle(3, Color, 1);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.lineStyle(0, 0, 0);
			shape.graphics.drawRect(3, 3, Width - 6, Height - 6);
			shape.graphics.endFill();
			shape.graphics.beginGradientFill(RADIAL, [Color, FlxColor.TRANSPARENT], [0.6, 0], [0, 255], null, null, null, 0.5);
			shape.graphics.drawRect(3, 3, Width - 6, Height - 6);
			shape.graphics.endFill();

		var bitmap:BitmapData = new BitmapData(Width, Height, true, 0);
		bitmap.draw(shape);
		return bitmap;
	}

    public function createhitbox(X:Float, color:Int, Y:Float = 0, width:Float = 0, height:Float = 0) {
        var button = new FlxButton(X, Y);
        if (width == 0) {
        	width = FlxG.width / 4;
        }
        if (height == 0) {
        	height = FlxG.height;
        }
        button.loadGraphic(createHintGraphic(Std.int(width), Std.int(height), color));
        button.scrollFactor.set();
        button.alpha = 0;
        
        button.onDown.callback = button.onOver.callback = function()
		{
			if (button.alpha != ClientPrefs.hitboxalpha)
				button.alpha = ClientPrefs.hitboxalpha;
		}
		button.onUp.callback = button.onOut.callback = function()
		{
			if (button.alpha != 0.00001)
				button.alpha = 0.00001;
		}
        return button;
    }

    override public function destroy():Void
        {
            super.destroy();
    
            buttonLeft = null;
            buttonDown = null;
            buttonUp = null;
            buttonRight = null;
        }
}