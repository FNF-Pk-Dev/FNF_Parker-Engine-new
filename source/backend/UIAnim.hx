package backend;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;

/**
 * Shared tween helpers for the game's menus, substates and HUD.
 *
 * Every helper is a no-op while `ClientPrefs.uiAnimations` is off, so the whole
 * animation pass can be disabled with a single setting. `source/import.hx`
 * already imports `backend.*`, so states can just call `UIAnim.xxx()`.
 */
class UIAnim
{
	/** How far an `Alphabet` slides in horizontally, in pixels. */
	public static inline var ALPHABET_TRAVEL:Float = 160;

	/** Longest stagger delay `staggeredDelay` may produce, in seconds. */
	public static inline var MAX_STAGGER:Float = 1.2;

	/** Slack used to decide whether a sprite already sits at its tween target. */
	static inline var REST_EPSILON:Float = 1;

	/** Scale an element returns to after `beatBump` pushed it out. */
	static inline var BUMP_REST:Float = 1;

	/** Scale an element starts from in `popIn`. */
	static inline var POP_FROM:Float = 0.8;

	/**
	 * Name of the field `popText` stashes a text's resting x in. Kept on the sprite itself so it is
	 * reclaimed with the sprite rather than accumulating in a static map.
	 */
	static inline var REST_X_FIELD:String = 'uiAnimRestX';

	public static function enabled():Bool
	{
		return ClientPrefs.uiAnimations;
	}

	/**
	 * Points `Conductor.songPosition` at the menu track, which is what
	 * `MusicBeatState.update()` turns into `curStep`/`curBeat`.
	 *
	 * Outside `PlayState` nothing advances the conductor, so menu states never
	 * reach `stepHit()`/`beatHit()` at all. Call this first thing in `update()`.
	 * It only writes while a track is playing, so a finished song cannot pin the
	 * position to a stale value.
	 */
	public static function syncConductor():Void
	{
		final music:FlxSound = FlxG.sound != null ? FlxG.sound.music : null;
		if (music == null || !music.playing)
			return;

		Conductor.songPosition = music.time;
	}

	/**
	 * Staggers an entrance: element `i` starts `i * stagger` seconds in, capped so a long list does
	 * not keep the last item waiting for seconds.
	 */
	static function staggeredDelay(i:Int, stagger:Float):Float
	{
		return Math.min(i * stagger, MAX_STAGGER);
	}

	/**
	 * Slides each sprite in horizontally, one after another.
	 *
	 * `fromX` may be a fixed x or a function of the element's index (e.g. to fly
	 * alternating items in from opposite sides). A sprite already resting at its
	 * target only gets the fade, which keeps the tween from fighting the
	 * `Alphabet` menu-item lerp for x.
	 *
	 * `restAlpha` gives the alpha each item should settle on (default 1). Menu lists whose
	 * unselected rows sit dimmed pass a function so the fade lands directly on that dim value,
	 * which is why no separate "re-apply the selection once the entrance is over" step is needed.
	 */
	public static function flyInX<T:FlxSprite>(items:Array<T>, fromX:Int->Float, stagger:Float = 0.08, duration:Float = 0.6, ?ease:EaseFunction,
			?restAlpha:Int->Float):Void
	{
		if (!enabled() || items == null)
			return;

		if (ease == null)
			ease = FlxEase.elasticOut;

		for (i in 0...items.length)
		{
			final spr:FlxSprite = items[i];
			if (spr == null)
				continue;

			final delay:Float = staggeredDelay(i, stagger);
			final targetX:Float = spr.x;
			final startX:Float = fromX(i);
			final alpha:Float = restAlpha != null ? restAlpha(i) : 1;

			spr.alpha = 0;
			FlxTween.tween(spr, {alpha: alpha}, duration, {ease: FlxEase.quadOut, startDelay: delay});

			if (Math.abs(startX - targetX) > REST_EPSILON)
			{
				spr.x = startX;
				FlxTween.tween(spr, {x: targetX}, duration, {ease: ease, startDelay: delay});
			}
		}
	}

	/** Same as `flyInX` but on the y axis, sliding items up or down into place. */
	public static function flyInY<T:FlxSprite>(items:Array<T>, fromY:Int->Float, stagger:Float = 0.08, duration:Float = 0.6, ?ease:EaseFunction,
			?restAlpha:Int->Float):Void
	{
		if (!enabled() || items == null)
			return;

		if (ease == null)
			ease = FlxEase.elasticOut;

		for (i in 0...items.length)
		{
			final spr:FlxSprite = items[i];
			if (spr == null)
				continue;

			final delay:Float = staggeredDelay(i, stagger);
			final targetY:Float = spr.y;
			final startY:Float = fromY(i);
			final alpha:Float = restAlpha != null ? restAlpha(i) : 1;

			spr.alpha = 0;
			FlxTween.tween(spr, {alpha: alpha}, duration, {ease: FlxEase.quadOut, startDelay: delay});

			if (Math.abs(startY - targetY) > REST_EPSILON)
			{
				spr.y = startY;
				FlxTween.tween(spr, {y: targetY}, duration, {ease: ease, startDelay: delay});
			}
		}
	}

	/**
	 * Pops a sprite in from `POP_FROM` scale while fading it up.
	 *
	 * Note that `Alphabet` does not scale through its `scale` property: its raw
	 * `scaleX`/`scaleY` are plain fields the hitbox never reads. Those are scaled
	 * directly instead, and the letters' own transform is never touched.
	 */
	public static function popIn(spr:FlxSprite, delay:Float = 0, duration:Float = 0.35, ?ease:EaseFunction):Void
	{
		if (!enabled() || spr == null)
			return;

		if (ease == null)
			ease = FlxEase.backOut;

		spr.alpha = 0;
		FlxTween.tween(spr, {alpha: 1}, duration, {ease: FlxEase.quadOut, startDelay: delay});

		final alphaSpr:Alphabet = Std.isOfType(spr, Alphabet) ? cast spr : null;
		if (alphaSpr != null)
		{
			alphaSpr.scaleX = POP_FROM;
			alphaSpr.scaleY = POP_FROM;
			FlxTween.tween(alphaSpr, {scaleX: 1, scaleY: 1}, duration, {ease: ease, startDelay: delay});
			return;
		}

		scaleSprite(spr, POP_FROM);
		FlxTween.tween(spr.scale, {x: BUMP_REST, y: BUMP_REST}, duration, {ease: ease, startDelay: delay});
	}

	/**
	 * Fades and slides a `FlxText` into place. Uses plain `FlxSprite.alpha`, so it always works.
	 *
	 * Safe to call repeatedly on the same text (e.g. on every selection change): while a slide is
	 * running the real resting x is remembered on the sprite, so re-triggering mid-flight reuses it
	 * instead of re-anchoring to wherever the previous tween had got to (which would walk the text
	 * across the screen a little on every call). The memo is dropped again once the slide lands, so
	 * a text whose x is repositioned by its owner between calls still picks up the new position.
	 */
	public static function popText(text:FlxText, delay:Float = 0, duration:Float = 0.3):Void
	{
		if (!enabled() || text == null)
			return;

		var restX:Null<Float> = Reflect.field(text, REST_X_FIELD);
		if (restX == null)
		{
			restX = text.x;
			Reflect.setField(text, REST_X_FIELD, restX);
		}

		FlxTween.cancelTweensOf(text, ['x', 'alpha']);
		text.alpha = 0;
		text.x = restX - ALPHABET_TRAVEL * 0.25;

		FlxTween.tween(text, {alpha: 1}, duration, {ease: FlxEase.quadOut, startDelay: delay});
		FlxTween.tween(text, {x: restX}, duration, {
			ease: FlxEase.backOut,
			startDelay: delay,
			onComplete: function(twn:FlxTween)
			{
				Reflect.deleteField(text, REST_X_FIELD);
			}
		});
	}

	/** Slows down and reverses a scale drift, forever. Meant for idle attractors. */
	public static function breathe(spr:FlxSprite, amount:Float = 0.06, period:Float = 1.6):FlxTween
	{
		if (!enabled() || spr == null || Std.isOfType(spr, FlxSpriteGroup))
			return null;

		FlxTween.cancelTweensOf(spr.scale);
		scaleSprite(spr, 1 - amount);
		return FlxTween.tween(spr.scale, {x: 1 + amount, y: 1 + amount}, period, {ease: FlxEase.sineInOut, type: PINGPONG});
	}

	/**
	 * Punches a sprite out for one beat and lets it settle back.
	 *
	 * Only safe on sprites nothing else rewrites each frame; the health bar
	 * icons are owned by `PlayState`, so they are driven by their own decay curve
	 * instead (see `PlayState.update`).
	 */
	public static function beatBump(spr:FlxSprite, scaleTo:Float = 1.08, duration:Float = 0.25):Void
	{
		if (!enabled() || spr == null || Std.isOfType(spr, FlxSpriteGroup))
			return;

		FlxTween.cancelTweensOf(spr.scale);
		scaleSprite(spr, scaleTo);
		FlxTween.tween(spr.scale, {x: BUMP_REST, y: BUMP_REST}, duration, {ease: FlxEase.quadOut});
	}

	/**
	 * Eases a menu item between its idle and its selected transform.
	 *
	 * `Alphabet` menu items position themselves by `targetY` in their own
	 * `update()`, so they lean on `changeX` (plus a scale pop) instead of an x
	 * tween that their own `update()` would overwrite every frame.
	 */
	public static function selectItem(spr:FlxSprite, selected:Bool, offset:Float = 30, duration:Float = 0.15, ?scaleTo:Float):Void
	{
		if (spr == null)
			return;

		final targetAlpha:Float = selected ? 1 : 0.6;

		if (!enabled())
		{
			spr.alpha = targetAlpha;
			return;
		}

		final alphaSpr:Alphabet = Std.isOfType(spr, Alphabet) ? cast spr : null;
		if (alphaSpr != null)
		{
			FlxTween.tween(alphaSpr, {alpha: targetAlpha}, duration, {ease: FlxEase.quadOut});
			alphaSpr.changeX = selected;

			if (scaleTo != null)
			{
				alphaSpr.scaleX = scaleTo;
				alphaSpr.scaleY = scaleTo;
				FlxTween.tween(alphaSpr, {scaleX: 1, scaleY: 1}, duration * 2, {ease: FlxEase.backOut});
			}
			return;
		}

		FlxTween.tween(spr, {alpha: targetAlpha}, duration, {ease: FlxEase.quadOut});

		if (scaleTo == null || Std.isOfType(spr, FlxSpriteGroup))
			return;

		final restX:Float = spr.x + (selected ? offset : -offset);
		FlxTween.cancelTweensOf(spr.scale);
		FlxTween.tween(spr.scale, {x: scaleTo, y: scaleTo}, duration * 0.6, {
			ease: FlxEase.quadOut,
			onComplete: function(twn:FlxTween)
			{
				spr.x = restX;
				FlxTween.tween(spr.scale, {x: BUMP_REST, y: BUMP_REST}, duration * 2, {ease: FlxEase.backOut});
			}
		});
	}

	/** `FlxMath.lerp` towards `target`, framerate-independently and clamped at 1. */
	public static function approach(current:Float, target:Float, elapsed:Float, speed:Float):Float
	{
		return FlxMath.lerp(current, target, CoolUtil.boundTo(elapsed * speed, 0, 1));
	}

	/** Scales a plain sprite; a no-op on groups, whose `scale` the base class owns. */
	static function scaleSprite(spr:FlxSprite, value:Float):Void
	{
		if (Std.isOfType(spr, FlxSpriteGroup))
			return;

		spr.scale.set(value, value);
	}
}
