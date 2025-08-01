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

using StringTools;

// 垃圾写法
class StartupState extends MusicBeatState
{
	public static var nextState:Class<FlxState> = states.TitleState;

	public function new()
	{
		super();
	}

	override function create()
	{
		FlxTransitionableState.skipNextTransIn = true;
		FlxTransitionableState.skipNextTransOut = true;
		MusicBeatState.switchState(Type.createInstance(nextState, []));
		super.create();
	}

}
