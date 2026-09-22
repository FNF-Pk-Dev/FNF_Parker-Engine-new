package modchart;

/**
 * Tracking state for sprites whose transform is a *composition* of layers.
 *
 * The modifier stack produces the modchart layer. The song, scripts, `FlxTween`, dance animations
 * and `setProperty` produce every other layer. Before ModManager existed everything wrote `x`/`y`
 * directly, so the stock application step (`strum.x = pos.x` every frame) silently erased whatever
 * a running `FlxTween` had just written - which is why tweening an arrow stopped working as soon as
 * the modchart was enabled.
 *
 * The fix is to remember what the modchart wrote last frame and how much *other* motion happened in
 * between, and to carry that motion forward:
 *
 * ```
 * external += obj.x - modAppliedX;      // the FlxTween (or anything else) moved it since our write
 * obj.x = pos.x + external;             // modchart layer + external layer
 * modAppliedX = obj.x;
 * ```
 *
 * `ModManager.applyPosition()`, `applyScale()` and `applyAngle()` are the only functions allowed to
 * write those properties for a composed sprite: they are what keeps `modApplied*` in sync, so a
 * modifier must never assign `x`, `y`, `scale` or `angle` on a `Note`/`StrumNote` itself.
 *
 * Position and angle are composed additively, scale multiplicatively (`modExternalScale*` is a
 * ratio, default `1`), which is what makes a tween of `x`, `y`, `scale.x`, `scale.y` or `angle`
 * survive next to a modchart.
 *
 * Implemented by `obj.Note` and `obj.StrumNote`. A sprite that does not implement it (for example a
 * plain `FlxSprite` passed in by a script) simply keeps the old absolute behaviour.
 */
interface ModchartComposed
{
	/** Value the modchart wrote to `x` last frame, `Math.NaN` before the first write. */
	public var modAppliedX:Float;

	/** Value the modchart wrote to `y` last frame, `Math.NaN` before the first write. */
	public var modAppliedY:Float;

	/** Accumulated `x` motion from everything that is not the modchart. */
	public var modExternalX:Float;

	/** Accumulated `y` motion from everything that is not the modchart. */
	public var modExternalY:Float;

	/** Value the modchart wrote to `scale.x` last frame, `Math.NaN` before the first write. */
	public var modAppliedScaleX:Float;

	/** Value the modchart wrote to `scale.y` last frame, `Math.NaN` before the first write. */
	public var modAppliedScaleY:Float;

	/** Accumulated external scale *factor* for `x` (a ratio, `1` when nothing else scaled it). */
	public var modExternalScaleX:Float;

	/** Accumulated external scale *factor* for `y` (a ratio, `1` when nothing else scaled it). */
	public var modExternalScaleY:Float;

	/** Value the modchart wrote to `angle` last frame, `Math.NaN` before the first write. */
	public var modAppliedAngle:Float;

	/** Accumulated external rotation in degrees. */
	public var modExternalAngle:Float;

	/** Set by the appliers on every frame the modchart wrote to this object. */
	public var modchartTouched:Bool;
}
