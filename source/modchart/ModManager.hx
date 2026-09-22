// @author Nebula_Zorua
package modchart;

import flixel.tweens.FlxEase;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.FlxSprite;
import flixel.FlxG;
import math.Vector3;
import modchart.Modifier.ModifierType;
import modchart.modifiers.*;
import modchart.events.*;

// Weird amalgamation of Schmovin' modifier system, Andromeda modifier system and my own new shit -neb

/**
	Schmovin'/Andromeda style modifier manager. It owns the modifier stack (`register`, `modArray`,
	`activeMods`), the timeline (`EventTimeline`) and the transform that stack produces for notes and
	receptors (`getPos`, `updateObject`).

	## The modchart layers on top of everything else

	The modifier stack produces only *one* of the layers that move a sprite. A `FlxTween`, a
	`setProperty('someStrum.x', ...)` from a script, a dance animation or the stock application step
	(`strum.x = pos.x` every frame) write `x`, `y`, `scale` and `angle` as well. Writing the
	modchart's absolute value every frame erased those writes, which is why a running `FlxTween` on
	an arrow stopped working as soon as this manager was enabled.

	`applyPosition()`, `applyScale()` and `applyAngle()` are the fix, and they are the ONLY functions
	allowed to write those properties on a composed sprite (see `ModchartComposed`). They remember
	what the modchart wrote last frame, take the difference between that and the sprite's current
	value as *external* motion, and write `modchart layer + external layer`:

	```haxe
	external += obj.x - modAppliedX; // a FlxTween (or anything else) moved it since our write
	obj.x = pos.x + external;        // modchart layer + external layer
	modAppliedX = obj.x;
	```

	Position and angle compose additively, scale composes multiplicatively (`modExternalScale*` is a
	ratio that defaults to `1`). The per-sprite tracking state is declared by the `ModchartComposed`
	interface - implemented by `obj.Note` and `obj.StrumNote` - so it travels with the sprite through
	pooling, `destroy()` and state changes; a sprite that does not implement it (a plain `FlxSprite`
	handed in by a script) keeps the old absolute behaviour.

	`syncComposition()` adopts a sprite's current transform as the new baseline (call it after a
	teleport or a fresh placement), `resetComposition()` does the same for one sprite or for every
	sprite this manager has written to (song start, song restart, destroy), and
	`composeExternals = false` switches composition off entirely: the appliers then write the
	modifier stack's transform absolutely, just like before composition existed, which is the escape
	hatch for a script that wants to own the transform itself. The absolute write still refreshes the
	baseline, so a script can turn composition back on at any time without the sprite jumping.
**/
class ModManager
{
	/**
		When `true` (the default) the appliers carry the motion of everything that is not the modchart
		forward instead of overwriting it. Scripts that want to own `x`/`y`/`scale`/`angle` themselves
		can set it to `false` to get the old absolute writes back.
	**/
	public var composeExternals:Bool = true;

	/** The tracked list is only swept once it grows past this many entries (see `sweepComposed`). */
	private static inline var COMPOSED_MIN_SWEEP:Int = 256;

	/** Every sprite the appliers have written to, duplicates included; `resetComposition(null)` walks it. */
	private var composedObjects:Array<FlxSprite> = [];

	/** Set of sprites already kept by the sweep in progress, so duplicates can be dropped. Empty outside a sweep. */
	private var composedScratch:Map<FlxSprite, Bool> = new Map();

	/** Current size `composedObjects` may reach before the appliers sweep it. */
	private var composedSweepAt:Int = COMPOSED_MIN_SWEEP;

	public function registerDefaultModifiers()
	{
		var quickRegs:Array<Any> = [
			FlipModifier,
			ReverseModifier,
			InvertModifier,
			DrunkModifier,
			BeatModifier,
			AlphaModifier,
			ScaleModifier,
			ConfusionModifier,
			OpponentModifier,
			TransformModifier,
			InfinitePathModifier,
			PerspectiveModifier
		];
		for (mod in quickRegs)
			quickRegister(Type.createInstance(mod, [this]));

		quickRegister(new RotateModifier(this));
		quickRegister(new RotateModifier(this, 'center', new Vector3((FlxG.width / 2) - (Note.swagWidth / 2), (FlxG.height / 2) - Note.swagWidth / 2)));
		quickRegister(new LocalRotateModifier(this, 'local'));
		quickRegister(new SubModifier("noteSpawnTime", this));
		setValue("noteSpawnTime", 1250);
	}

	private var state:PlayState;

	public var receptors:Array<Array<StrumNote>> = []; // for modifiers to be able to access receptors directly if they need to
	public var timeline:EventTimeline = new EventTimeline();

	public var notemodRegister:Map<String, Modifier> = [];
	public var miscmodRegister:Map<String, Modifier> = [];

	@:deprecated("Unused in place of notemodRegister and miscModRegister")
	public var registerByType:Map<ModifierType, Map<String, Modifier>> = [NOTE_MOD => [], MISC_MOD => []];

	public var register:Map<String, Modifier> = [];

	public var modArray:Array<Modifier> = [];

	public var activeMods:Array<Array<String>> = [[], []]; // by player

	inline public function quickRegister(mod:Modifier)
		registerMod(mod.getName(), mod);

	public function registerMod(modName:String, mod:Modifier, ?registerSubmods = true)
	{
		register.set(modName, mod);
		// registerByType.get(mod.getModType()).set(modName, mod);
		switch (mod.getModType())
		{
			case NOTE_MOD:
				notemodRegister.set(modName, mod);
			case MISC_MOD:
				miscmodRegister.set(modName, mod);
		}
		timeline.addMod(modName);
		modArray.push(mod);

		if (registerSubmods)
		{
			for (name in mod.submods.keys())
			{
				var submod = mod.submods.get(name);
				quickRegister(submod);
			}
		}

		setValue(modName, 0); // so if it should execute it gets added Automagically
		modArray.sort((a, b) -> Std.int(a.getOrder() - b.getOrder()));
		// TODO: sort by mod.getOrder()
	}

	inline public function get(modName:String)
		return register.get(modName);

	inline public function getPercent(modName:String, player:Int)
		return register.get(modName).getPercent(player);

	inline public function getValue(modName:String, player:Int)
		return register.get(modName).getValue(player);

	inline public function setPercent(modName:String, val:Float, player:Int = -1)
		setValue(modName, val / 100, player);

	public function setValue(modName:String, val:Float, player:Int = -1)
	{
		if (player == -1)
		{
			for (pN in 0...2)
				setValue(modName, val, pN);
		}
		else
		{
			var daMod = register.get(modName);
			var mod = daMod.parent == null ? daMod : daMod.parent;
			var name = mod.getName();
			// optimization shit!! :)
			// thanks 4mbr0s3 for giving an alternative way to do all of this cus andromeda has smth similar in Flexy but like
			// this is a better way to do it
			// (ofc its not EXACTLY what 4mbr0s3 did but.. y'know, it's close to it)

			// a submod turning off must not turn its parent off while another submod - or the parent's own
			// value - is still running, so both are checked before anything is removed below

			if (activeMods[player] == null)
				activeMods[player] = [];

			register.get(modName).setValue(val, player);

			if (!activeMods[player].contains(name) && mod.shouldExecute(player, val))
			{
				if (daMod.getName() != name)
					activeMods[player].push(daMod.getName());
				activeMods[player].push(name);
			}
			else if (!mod.shouldExecute(player, val))
			{
				// there is prob a better way to do this
				// i just dont know it
				var modParent = daMod.parent;
				if (modParent == null)
				{
					for (subName => subMod in daMod.submods)
					{
						modParent = daMod; // because if this gets called at all, there's atleast 1 submod!!
						break;
					}
				}
				if (daMod != modParent)
					activeMods[player].remove(daMod.getName());
				if (modParent != null)
				{
					// the parent may still be running on its own value, or through one of its other submods,
					// in which case it stays active and nothing else is removed
					var parentStillRuns:Bool = modParent.shouldExecute(player, modParent.getValue(player));
					if (!parentStillRuns)
					{
						for (subName => subMod in modParent.submods)
						{
							if (subMod.shouldExecute(player, subMod.getValue(player)))
							{
								parentStillRuns = true;
								break;
							}
						}
					}
					if (!parentStillRuns)
						activeMods[player].remove(modParent.getName());
				}
				else
					activeMods[player].remove(daMod.getName());
			}

			// sorting is the expensive part, so it happens once, after activeMods has settled
			activeMods[player].sort((a, b) -> Std.int(register.get(a).getOrder() - register.get(b).getOrder()));
		}
	}

	public function new(state:PlayState)
	{
		var modchart = ClientPrefs.getGameplaySetting('modchart', false);
		if (modchart)
			this.state = state;
		else
			this.state = null;
	}

	public function update(elapsed:Float)
	{
		for (mod in modArray)
		{
			if (mod.active && mod.doesUpdate())
				mod.update(elapsed);
		}
	}

	public function updateTimeline(curStep:Float)
		timeline.update(curStep);

	public function getBaseX(direction:Int, player:Int):Float
	{
		var x:Float = (FlxG.width / 2) - Note.swagWidth - 54 + Note.swagWidth * direction;
		switch (player)
		{
			case 0:
				x += FlxG.width / 2 - Note.swagWidth * 2 - 100;
			case 1:
				x -= FlxG.width / 2 - Note.swagWidth * 2 - 100;
		}

		x -= 56;

		return x;
	}

	public function updateObject(beat:Float, obj:FlxSprite, pos:Vector3, player:Int)
	{
		for (name in activeMods[player])
		{
			var mod:Modifier = notemodRegister.get(name);
			if (mod == null)
				continue;
			if (!obj.active)
				continue;
			if ((obj is Note))
			{
				var o:Note = cast obj;
				mod.updateNote(beat, o, pos, player);
			}
			else if ((obj is StrumNote))
			{
				var o:StrumNote = cast obj;
				mod.updateReceptor(beat, o, pos, player);
			}
		}
		if ((obj is Note))
			obj.updateHitbox();

		obj.centerOrigin();
		obj.centerOffsets();
		if ((obj is Note))
		{
			var cum:Note = cast obj;
			cum.offset.x += cum.typeOffsetX;
			cum.offset.y += cum.typeOffsetY;
		}
	}

	public inline function getVisPos(songPos:Float = 0, strumTime:Float = 0, songSpeed:Float = 1)
	{
		return -(0.45 * (songPos - strumTime) * songSpeed);
	}

	public function getPos(time:Float, diff:Float, tDiff:Float, beat:Float, data:Int, player:Int, obj:FlxSprite, ?exclusions:Array<String>,
			?pos:Vector3):Vector3
	{
		if (exclusions == null)
			exclusions = []; // since [] cant be a default value for.. some reason?? "its not constant!!" kys haxe
		if (pos == null)
			pos = new Vector3();

		if (!obj.active)
			return pos;

		pos.x = getBaseX(data, player);
		pos.y = 50 + diff;
		pos.z = 0;
		for (name in activeMods[player])
		{
			if (exclusions.contains(name))
				continue; // because some modifiers may want the path without reverse, for example. (which is actually more common than you'd think!)
			var mod:Modifier = notemodRegister.get(name);
			if (mod == null)
				continue;
			if (!obj.active)
				continue;
			pos = mod.getPos(time, diff, tDiff, beat, pos, data, player, obj);
		}
		return pos;
	}

	// ------------------------------------------------------------------------------------------------
	// Transform appliers - the only functions allowed to write x/y/scale/angle of a composed sprite.
	// ------------------------------------------------------------------------------------------------

	/**
		Writes the modchart layer's position (the `Vector3` produced by `getPos()`) onto `obj`, carrying
		everything that is not the modchart (a `FlxTween`, a `setProperty`, a dance animation) forward.
		This replaces the old `strum.x = pos.x; strum.y = pos.y;` application step.
	**/
	public function applyPosition(obj:FlxSprite, pos:Vector3):Void
	{
		if (obj == null)
			return;

		var c:ModchartComposed = composedOf(obj);
		if (c == null)
		{
			obj.x = pos.x;
			obj.y = pos.y;
			return;
		}

		if (!composeExternals)
		{
			// Escape hatch: the plain absolute write of old builds. The baseline is still refreshed and the
			// external layers dropped so a script can turn composition back on without the sprite jumping.
			obj.x = pos.x;
			obj.y = pos.y;
			c.modExternalX = 0;
			c.modExternalY = 0;
			c.modAppliedX = obj.x;
			c.modAppliedY = obj.y;
			c.modchartTouched = true;
			trackComposed(obj);
			return;
		}

		if (!Math.isNaN(c.modAppliedX))
		{
			c.modExternalX += obj.x - c.modAppliedX;
			c.modExternalY += obj.y - c.modAppliedY;
		}
		obj.x = pos.x + c.modExternalX;
		obj.y = pos.y + c.modExternalY;
		c.modAppliedX = obj.x;
		c.modAppliedY = obj.y;
		c.modchartTouched = true;
		trackComposed(obj);
	}

	/**
		Writes the modchart layer's scale onto `obj`. External scaling is remembered as a *ratio*, so a
		`FlxTween` on `scale.x`/`scale.y` (or a sustain note's `resizeByRatio`) survives next to it.
	**/
	public function applyScale(obj:FlxSprite, scaleX:Float, scaleY:Float):Void
	{
		if (obj == null)
			return;

		var c:ModchartComposed = composedOf(obj);
		if (c == null)
		{
			obj.scale.set(scaleX, scaleY);
			return;
		}

		if (!composeExternals)
		{
			obj.scale.set(scaleX, scaleY);
			c.modExternalScaleX = 1;
			c.modExternalScaleY = 1;
			c.modAppliedScaleX = obj.scale.x;
			c.modAppliedScaleY = obj.scale.y;
			c.modchartTouched = true;
			trackComposed(obj);
			return;
		}

		if (!Math.isNaN(c.modAppliedScaleX) && c.modAppliedScaleX > 0 && c.modAppliedScaleY > 0)
		{
			c.modExternalScaleX *= obj.scale.x / c.modAppliedScaleX;
			c.modExternalScaleY *= obj.scale.y / c.modAppliedScaleY;
		}
		obj.scale.set(scaleX * c.modExternalScaleX, scaleY * c.modExternalScaleY);
		c.modAppliedScaleX = obj.scale.x;
		c.modAppliedScaleY = obj.scale.y;
		c.modchartTouched = true;
		trackComposed(obj);
	}

	/** Writes the modchart layer's rotation (degrees) onto `obj`, on top of whatever else rotated it. **/
	public function applyAngle(obj:FlxSprite, degrees:Float):Void
	{
		if (obj == null)
			return;

		var c:ModchartComposed = composedOf(obj);
		if (c == null)
		{
			obj.angle = degrees;
			return;
		}

		if (!composeExternals)
		{
			obj.angle = degrees;
			c.modExternalAngle = 0;
			c.modAppliedAngle = obj.angle;
			c.modchartTouched = true;
			trackComposed(obj);
			return;
		}

		if (!Math.isNaN(c.modAppliedAngle))
			c.modExternalAngle += obj.angle - c.modAppliedAngle;

		obj.angle = degrees + c.modExternalAngle;
		c.modAppliedAngle = obj.angle;
		c.modchartTouched = true;
		trackComposed(obj);
	}

	/** Adopts `obj`'s current transform as the new baseline: the next write starts from where it is now. */
	public function syncComposition(obj:FlxSprite):Void
	{
		var c:ModchartComposed = composedOf(obj);
		if (c == null)
			return;

		clearComposition(c);
		trackComposed(obj);
	}

	/** Clears the tracking for one sprite, or for every sprite the appliers have written to when `obj` is null. */
	public function resetComposition(?obj:FlxSprite = null):Void
	{
		if (obj != null)
		{
			var c:ModchartComposed = composedOf(obj);
			if (c != null)
				clearComposition(c);
			composedObjects = composedObjects.filter(held -> held != obj);
			return;
		}

		for (held in composedObjects)
		{
			var c:ModchartComposed = composedOf(held);
			if (c != null)
				clearComposition(c);
		}
		composedObjects = [];
		composedScratch.clear();
	}

	/**
		Null when the sprite does not implement `ModchartComposed`. The cast is unchecked: every sprite
		given to the appliers goes through here or not at all.
	**/
	static function composedOf(obj:FlxSprite):ModchartComposed
	{
		if (obj == null || !Std.isOfType(obj, ModchartComposed))
			return null;
		return cast obj;
	}

	/** Adds `obj` to the tracked list, sweeping dead and duplicated entries when it gets too long. */
	private function trackComposed(obj:FlxSprite):Void
	{
		composedObjects.push(obj);
		if (composedObjects.length > composedSweepAt)
			sweepComposed();
	}

	/**
		Keeps the live, unique sprites in `composedObjects`, which matters because notes are created
		constantly. A sprite is dead once it was killed or destroyed, and those are dropped: they are
		never handed to an applier again. The threshold grows with the number of sprites that survive,
		so a busy song sweeps once per few hundred applier calls instead of once per frame.
	**/
	private function sweepComposed():Void
	{
		var kept:Array<FlxSprite> = [];
		for (obj in composedObjects)
		{
			if (obj == null || (!obj.exists && !obj.alive))
				continue;
			if (composedScratch.exists(obj))
				continue;
			composedScratch.set(obj, true);
			kept.push(obj);
		}
		composedScratch.clear();
		composedObjects = kept;
		composedSweepAt = kept.length * 2;
		if (composedSweepAt < COMPOSED_MIN_SWEEP)
			composedSweepAt = COMPOSED_MIN_SWEEP;
	}

	/** Forgets what the modchart wrote, so the next applier call starts from the sprite's current transform. */
	static function clearComposition(c:ModchartComposed):Void
	{
		c.modAppliedX = Math.NaN;
		c.modAppliedY = Math.NaN;
		c.modExternalX = 0;
		c.modExternalY = 0;
		c.modAppliedScaleX = Math.NaN;
		c.modAppliedScaleY = Math.NaN;
		c.modExternalScaleX = 1;
		c.modExternalScaleY = 1;
		c.modAppliedAngle = Math.NaN;
		c.modExternalAngle = 0;
		c.modchartTouched = false;
	}

	public function queueEaseP(step:Float, endStep:Float, modName:String, percent:Float, style:String = 'linear', player:Int = -1, ?startVal:Float)
		queueEase(step, endStep, modName, percent / 100, style, player, startVal / 100);

	public function queueSetP(step:Float, modName:String, percent:Float, player:Int = -1)
		queueSet(step, modName, percent / 100, player);

	public function queueEase(step:Float, endStep:Float, modName:String, target:Float, style:String = 'linear', player:Int = -1, ?startVal:Float)
	{
		if (player == -1)
		{
			queueEase(step, endStep, modName, target, style, 0);
			queueEase(step, endStep, modName, target, style, 1);
		}
		else
		{
			var easeFunc = FlxEase.linear;

			try
			{
				var newEase = Reflect.getProperty(FlxEase, style);
				if (newEase != null)
					easeFunc = newEase;
			}

			timeline.addEvent(new EaseEvent(step, endStep, modName, target, easeFunc, player, this));
		}
	}

	public function queueSet(step:Float, modName:String, target:Float, player:Int = -1)
	{
		if (player == -1)
		{
			queueSet(step, modName, target, 0);
			queueSet(step, modName, target, 1);
		}
		else
			timeline.addEvent(new SetEvent(step, modName, target, player, this));
	}

	public function queueFunc(step:Float, endStep:Float, callback:(CallbackEvent, Float) -> Void)
	{
		timeline.addEvent(new StepCallbackEvent(step, endStep, callback, this));
	}

	public function queueFuncOnce(step:Float, callback:(CallbackEvent, Float) -> Void)
		timeline.addEvent(new CallbackEvent(step, callback, this));

	public function randomFloat(minVal:Float, maxVal:Float):Float
	{ // WHO LET DEWOTT CODE AGAIN
		return FlxG.random.float(minVal, maxVal);
	}
}
