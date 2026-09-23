package substates;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.util.FlxColor;
import flixel.addons.transition.FlxTransitionableState;

using StringTools;

class ResetScoreSubState extends MusicBeatSubstate
{
	inline static var BACKDROP_ALPHA:Float = 0.6;

	// Yes/No ease between their two states in `OPTION_TWEEN`, but the first call fades them in
	// with the rest of the entrance instead, `ENTRANCE_DELAY` later and a little slower.
	inline static var OPTION_TWEEN:Float = 0.15;
	inline static var ENTRANCE_DELAY:Float = 0.2;
	inline static var ENTRANCE_TWEEN:Float = 0.35;

	var bg:FlxSprite;
	var alphabetArray:Array<Alphabet> = [];
	var icon:HealthIcon;
	var onYes:Bool = false;
	var yesText:Alphabet;
	var noText:Alphabet;

	var song:String;
	var difficulty:Int;
	var week:Int;

	// Week -1 = Freeplay
	public function new(song:String, difficulty:Int, character:String, week:Int = -1)
	{
		this.song = song;
		this.difficulty = difficulty;
		this.week = week;

		super();

		var name:String = song;
		if (week > -1)
		{
			name = WeekData.weeksLoaded.get(WeekData.weeksList[week]).weekName;
		}
		name += ' (' + CoolUtil.difficulties[difficulty] + ')?';

		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.scrollFactor.set();
		add(bg);
		// The backdrop settles at its own translucency rather than at `popIn`'s full alpha,
		// so it gets its own fade.
		if (UIAnim.enabled())
		{
			bg.alpha = 0;
			FlxTween.tween(bg, {alpha: BACKDROP_ALPHA}, 0.4, {ease: FlxEase.quadOut});
		}
		else
		{
			bg.alpha = BACKDROP_ALPHA;
		}

		var tooLong:Float = (name.length > 18) ? 0.8 : 1; // Fucking Winter Horrorland
		var text:Alphabet = new Alphabet(0, 180, "Reset the score of", true);
		text.screenCenter(X);
		alphabetArray.push(text);
		add(text);
		var text:Alphabet = new Alphabet(0, text.y + 90, name, true);
		text.scaleX = tooLong;
		text.screenCenter(X);
		if (week == -1)
			text.x += 60 * tooLong;
		alphabetArray.push(text);
		add(text);
		if (week == -1)
		{
			icon = new HealthIcon(character);
			icon.setGraphicSize(Std.int(icon.width * tooLong));
			icon.updateHitbox();
			icon.setPosition(text.x - icon.width + (10 * tooLong), text.y - 30);
			add(icon);
		}

		yesText = new Alphabet(0, text.y + 150, 'Yes', true);
		yesText.screenCenter(X);
		yesText.x -= 200;
		add(yesText);
		noText = new Alphabet(0, text.y + 150, 'No', true);
		noText.screenCenter(X);
		noText.x += 200;
		add(noText);
		// `ENTRANCE_DELAY` lets the entrance own the Yes/No alpha instead of the state being
		// snapped on before the pair has even appeared.
		updateOptions(ENTRANCE_DELAY);

		// Entrance, in order: the prompt lines, then Yes/No, then the icon. Only sliding and
		// fading is used - `popIn` would tween away the `tooLong` clamp on the name and the
		// health icon's graphic size.
		var entrance:Array<FlxSprite> = [alphabetArray[0], alphabetArray[1], icon];
		UIAnim.flyInX(entrance, function(i) return entrance[Std.int(i)].x - 100, 0.15, 0.5);

		#if android
		addTouchPad("LEFT_RIGHT", "A_B");
		addPadCamera();
		#end
	}

	override function update(elapsed:Float)
	{
		if (controls.UI_LEFT_P || controls.UI_RIGHT_P)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'), 1);
			onYes = !onYes;
			updateOptions();
		}
		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 1);
			#if android
			FlxTransitionableState.skipNextTransOut = true;
			FlxG.resetState();
			#else
			close();
			#end
		}
		else if (controls.ACCEPT)
		{
			if (onYes)
			{
				if (week == -1)
				{
					Highscore.resetSong(song, difficulty);
				}
				else
				{
					Highscore.resetWeek(WeekData.weeksList[week], difficulty);
				}
			}
			FlxG.sound.play(Paths.sound('cancelMenu'), 1);
			#if android
			FlxTransitionableState.skipNextTransOut = true;
			FlxG.resetState();
			#else
			close();
			#end
		}
		super.update(elapsed);
	}

	/**
	 * `delay` is non-zero only for the opening call, where it hands the alpha over to a delayed
	 * fade so the option joins the entrance; every later toggle tweens straight to the new state.
	 */
	function updateOptions(delay:Float = 0)
	{
		var scales:Array<Float> = [0.75, 1];
		var alphas:Array<Float> = [0.6, 1.25];
		var confirmInt:Int = onYes ? 1 : 0;

		applyOptionState(yesText, alphas[confirmInt], scales[confirmInt], delay);
		applyOptionState(noText, alphas[1 - confirmInt], scales[1 - confirmInt], delay);

		if (week == -1 && icon != null && icon.animation != null && icon.animation.curAnim != null)
			icon.animation.curAnim.curFrame = confirmInt;
	}

	/** Eases one of the Yes/No prompts between its idle and its chosen transform. */
	function applyOptionState(spr:Alphabet, alpha:Float, scale:Float, delay:Float = 0):Void
	{
		if (spr == null)
			return;

		if (!UIAnim.enabled())
		{
			spr.alpha = alpha;
			spr.scaleX = scale;
			spr.scaleY = scale;
			return;
		}

		// An `Alphabet` only scales through `scaleX`/`scaleY`; `scale.set()` does nothing visible.
		FlxTween.cancelTweensOf(spr, ['scaleX', 'scaleY']);
		FlxTween.tween(spr, {scaleX: scale, scaleY: scale}, OPTION_TWEEN, {ease: FlxEase.quadOut, startDelay: delay});

		FlxTween.cancelTweensOf(spr, ['alpha']);
		if (delay > 0)
			spr.alpha = 0;
		FlxTween.tween(spr, {alpha: alpha}, delay > 0 ? ENTRANCE_TWEEN : OPTION_TWEEN, {ease: FlxEase.quadOut, startDelay: delay});
	}
}
