package modchart;

import flixel.math.FlxAngle;
import modchart.*;
import modchart.events.CallbackEvent;

/**
	Applies the built-in preset modchart of a song.

	## Composition

	A preset is nothing more than a batch of `setValue` / `setPercent` / `queueEase` / `queueSet`
	calls on the modifier stack, so it lives in the modchart layer of the composition described by
	`modchart.ModchartComposed`: its position and angle add to whatever else moves an arrow (a
	`FlxTween`, a `setProperty`, a dance animation) and its scale multiplies with theirs. That is what
	lets a preset run next to a tween instead of overwriting it every frame - as long as the preset
	itself keeps moving arrows through the modifier stack (`transformX`, `transformY`, `drunk`,
	`confusion`, ...) and never assigns `strum.x` / `note.y` / `scale` / `angle` directly, since
	`ModManager.applyPosition()`, `applyScale()` and `applyAngle()` own those properties.

	A preset that teleports arrows still has to tell the composition about the jump, and so does a
	preset being (re)loaded: `loadModchart()` resets the composition baseline before it sets anything,
	so position / scale / angle accumulated by an earlier chart, an earlier attempt at the same song
	or a resolution change is not carried into the new one. `Modcharts.isModcharted()` only reports
	whether the system is on, so it needs no such reset.
**/
class Modcharts
{
	static function numericForInterval(start, end, interval, func)
	{
		var index = start;
		while (index < end)
		{
			func(index);
			index += interval;
		}
	}

	static var songs = ["fresh"];

	public static function isModcharted(songName:String)
	{
		if (songs.contains(songName.toLowerCase()))
			return true;

		// add other conditionals if needed

		// return true; // turns modchart system on for all songs, only use for like.. debugging
		return false;
	}

	public static function loadModchart(modManager:ModManager, songName:String)
	{
		// the preset is applied on top of what the engine, a tween or a script already put on the
		// arrows, so drop the composition baseline first and start from a clean slate
		if (modManager != null)
			modManager.resetComposition();

		if (ClientPrefs.middleScroll)
		{
			modManager.setValue("opponentSwap", 0.5);
			modManager.setValue("alpha", 1, 1);
		}
		trace('${songName} modchart loaded!');
	}
}
