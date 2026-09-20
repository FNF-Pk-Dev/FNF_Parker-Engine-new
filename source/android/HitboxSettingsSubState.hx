package android;

#if desktop
import backend.Discord.DiscordClient;
#end
import backend.player.Controls;
import options.BaseOptionsMenu;
import options.Option;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.transition.FlxTransitionableState;
import flixel.graphics.FlxGraphic;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.input.keyboard.FlxKey;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSave;
import flixel.util.FlxTimer;
import openfl.text.TextField;
import lime.utils.Assets;
import haxe.Json;
import openfl.Lib;

using StringTools;

class HitboxSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'Hitbox Settings';
		rpcTitle = 'Hitbox Settings Menu'; // hi, you can ask what is that, i will answer it's all what you needed lol.

		var option:Option = new Option('Hitbox Mode:', "Choose your Hitbox Style!", 'hitboxmode', 'string', 'New', ['Classic', 'New', 'Gradient', 'Old']);
		addOption(option);

		var option:Option = new Option('NewHitbox Mode:', "Choose your NewHitbox Space and None!", 'hitboxLocation', 'string', 'None', ['None', 'Space']);
		addOption(option);

		var option:Option = new Option('Space NewHitbox Mode:', "Choose your Space NewHitbox Up and Down!", 'hitboxPT', 'bool', false);
		addOption(option);

		var option:Option = new Option('Hitbox Opacity', // mariomaster was here again
			'Changes opacity', 'hitboxalpha', 'float', 0.2);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);

		var option:Option = new Option('VirtualPad Opacity', // Ajwwk
			'Changes VirtualPad opacity', 'virtualPadAlpha', 'float', 0.2);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);

		super();
	}
	/*
		override function update(elapsed:Float)
		{
			super.update(elapsed);
				#if android
			if (FlxG.android.justReleased.BACK)
			{
				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
				MusicBeatState.switchState(new options.OptionsState());
		}
			#end
			}
	 */ // why this exists?!?¡
}
