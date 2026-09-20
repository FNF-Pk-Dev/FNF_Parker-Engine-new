package backend;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxGradient;

/**
 * PowerPuff Girls themed transition effect
 * Features the three girls flying across the screen
 * Faithful to the original CSS animation style
 */
class PowerPuffTransition extends MusicBeatSubstate
{
	public static var finishCallback:Void->Void;
	public static var nextCamera:FlxCamera;

	var isTransIn:Bool = false;
	var gradientBg:FlxSprite;
	var powerPuffGirls:FlxGroup;
	var bubbles:PowerPuffGirl;
	var blossom:PowerPuffGirl;
	var buttercup:PowerPuffGirl;
	var transitionComplete:Bool = false;

	public function new(isTransIn:Bool)
	{
		this.isTransIn = isTransIn;
		super();

		// Scale matching original CSS proportions
		var scale:Float = 0.4;
		var centerY:Float = FlxG.height / 2 - 50;

		// Create gradient background matching original CSS:
		// background: linear-gradient(to top, #134e89, #05131d);
		gradientBg = FlxGradient.createGradientFlxSprite(FlxG.width, FlxG.height, [0xFF05131D, 0xFF134E89], 1, 90);
		gradientBg.scrollFactor.set();
		gradientBg.alpha = 0;
		add(gradientBg);

		// Create PowerPuff Girls group
		powerPuffGirls = new FlxGroup();
		add(powerPuffGirls);

		if (isTransIn)
		{
			// Trans In: Girls fly from right to left and exit (revealing new state)
			bubbles = new PowerPuffGirl(FlxG.width + 100, centerY, PowerPuffGirl.BUBBLES, scale);
			blossom = new PowerPuffGirl(FlxG.width + 200, centerY - 20, PowerPuffGirl.BLOSSOM, scale);
			buttercup = new PowerPuffGirl(FlxG.width + 150, centerY + 15, PowerPuffGirl.BUTTERCUP, scale);

			powerPuffGirls.add(bubbles);
			powerPuffGirls.add(blossom);
			powerPuffGirls.add(buttercup);

			// Fade in background
			FlxTween.tween(gradientBg, {alpha: 0.9}, 0.2);

			// Fly across screen from right to left
			FlxTween.tween(bubbles, {x: -250}, 0.8, {
				ease: FlxEase.sineIn,
				startDelay: 0.0
			});

			FlxTween.tween(blossom, {x: -200}, 0.8, {
				ease: FlxEase.sineIn,
				startDelay: 0.1
			});

			FlxTween.tween(buttercup, {x: -180}, 0.8, {
				ease: FlxEase.sineIn,
				startDelay: 0.2,
				onComplete: function(_)
				{
					// Fade out and close
					FlxTween.tween(gradientBg, {alpha: 0}, 0.2, {
						onComplete: function(_)
						{
							close();
						}
					});
				}
			});
		}
		else
		{
			// Trans Out: Girls fly from left to right across screen (covering old state)
			bubbles = new PowerPuffGirl(-250, centerY, PowerPuffGirl.BUBBLES, scale);
			blossom = new PowerPuffGirl(-300, centerY - 20, PowerPuffGirl.BLOSSOM, scale);
			buttercup = new PowerPuffGirl(-280, centerY + 15, PowerPuffGirl.BUTTERCUP, scale);

			powerPuffGirls.add(bubbles);
			powerPuffGirls.add(blossom);
			powerPuffGirls.add(buttercup);

			// Fade in background
			FlxTween.tween(gradientBg, {alpha: 1}, 0.15);

			// Fly across screen from left to right
			FlxTween.tween(bubbles, {x: FlxG.width + 250}, 1.0, {
				ease: FlxEase.sineIn,
				startDelay: 0.0
			});

			FlxTween.tween(blossom, {x: FlxG.width + 200}, 1.0, {
				ease: FlxEase.sineIn,
				startDelay: 0.1
			});

			FlxTween.tween(buttercup, {x: FlxG.width + 180}, 1.0, {
				ease: FlxEase.sineIn,
				startDelay: 0.2,
				onComplete: function(_)
				{
					transitionComplete = true;
					if (finishCallback != null)
					{
						finishCallback();
					}
				}
			});
		}

		if (nextCamera != null)
		{
			gradientBg.cameras = [nextCamera];
			bubbles.cameras = [nextCamera];
			blossom.cameras = [nextCamera];
			buttercup.cameras = [nextCamera];
		}
		nextCamera = null;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
	}
}
