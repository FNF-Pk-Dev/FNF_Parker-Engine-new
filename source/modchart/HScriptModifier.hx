// @author Riconuts
package modchart;

import script.FunkinHScript;
import script.hscript.HScript;
import modchart.Modifier;
import math.Vector3;

/**
	Registers a modifier whose behaviour is written in HScript (`modifiers/<name>.hscript`, see
	`HScriptModifier.fromName`, or a source string through `HScriptModifier.fromString`).

	## What the script sees

	`this` inside the script *is* this modifier, so `this.modMgr` (the `ModManager`), `this.parent`
	(the modifier this one is a submod of) and the modifier's own accessors - `this.getValue(player)`,
	`this.getPercent(player)`, `this.setValue(value, player)`, `this.setPercent(percent, player)`,
	`this.getSubmodValue(name, player)`, `this.getSubmodPercent(name, player)` - are reachable from it.
	The `ModifierType` and `ModifierOrder` values are script globals: `NOTE_MOD`, `MISC_MOD`, `FIRST`,
	`PRE_REVERSE`, `REVERSE`, `POST_REVERSE`, `DEFAULT`, `LAST`.

	A script only has to implement the callbacks it cares about; every other one falls back to
	`Modifier`: `getModType`, `ignorePos`, `ignoreUpdateReceptor`, `ignoreUpdateNote`, `doesUpdate`,
	`shouldExecute`, `getOrder`, `getName`, `getValue`, `getPercent`, `setValue`, `setPercent`,
	`getSubmods`, `getSubmodPercent`, `getSubmodValue`, `updateReceptor`, `updateNote` and
	`update(elapsed)`. `onCreate` / `onCreatePost` run once, right after the script body.

	A modifier stays inactive until its percent is not `0` (or `shouldExecute` says otherwise), and
	`updateReceptor` / `updateNote` are only dispatched to a modifier that reports `NOTE_MOD` from
	`getModType` - a script that moves arrows has to do both.

	## Composition: what a modifier may and may not write

	The modifier stack is only one of the layers that move an arrow: a `FlxTween` (`noteTweenX`,
	`FlxTween.tween(strum, {x: ...})`), `setProperty` and the dance animations move it too. Position
	and angle compose additively, scale composes multiplicatively, and the appliers
	(`ModManager.applyPosition()`, `applyScale()`, `applyAngle()`) remember what *they* wrote so that
	everything else survives next to the modchart. `modchart.ModchartComposed` is the frozen contract.
	Two rules follow for a script modifier:

	- **Add to the `pos` vector, never assign the sprite's transform.** While `updateReceptor` /
	  `updateNote` run, the position vector `ModManager.getPos()` handed in is exposed as `this.pos`,
	  so `this.pos.x += 20` is how a modifier moves an arrow - and that is exactly what composes with
	  a tween. This is also how the built-in modifiers work: they take `pos` and add to it.
	- **Never write `note.x`, `note.y`, `note.scale` or `note.angle` directly** (nor through the
	  sprite's `scale` point). The appliers own those properties. A write behind their back is measured
	  as *external* motion and kept, so the modifier and the tween keep pushing the sprite every frame
	  and it drifts instead of composing.

	If a script really has to own the transform absolutely - a teleport, a custom path, a value that
	must not compose with anything - it has two options:

	- keep writing through `this.pos` (preferred): the arrow still lands exactly where the modifier
	  puts it, and a `FlxTween` running next to it keeps working;
	- set `this.modMgr.composeExternals = false` for the duration and back to `true` afterwards. That
	  restores the pre-composition absolute behaviour, where the applier overwrites `x` / `y` / `scale`
	  / `angle` from `pos` every frame - which also erases any running `FlxTween` again, i.e. exactly
	  the bug this layer exists to fix - so only use it for a short, deliberate interval. The appliers
	  keep their baseline fresh while the switch is off, so turning composition back on does not make
	  the sprite jump.

	Anything that moves a sprite outside a modifier or a tween (a hand-written teleport, a
	`setProperty`, a restart) should tell the composition about it:
	`this.modMgr.syncComposition(obj)` adopts that sprite's current transform as the new baseline, so
	the composition does not drag it back to where it was, while `this.modMgr.resetComposition()`
	drops everything that was accumulated - for one sprite, or for every sprite the appliers have
	written to, which is what a song restart wants.
**/
class HScriptModifier extends Modifier
{
	public var script:HScript;
	public var scripts:FunkinHScript;
	public var name:String = "unknown";

	/**
		The shared position vector of the arrow the manager is updating right now, exposed to the
		script as `this.pos` while `updateReceptor` / `updateNote` run.

		A modifier **adds** to it (`this.pos.x += 20`, `this.pos.y -= 10`, ...). It must not assign
		`x`, `y`, `scale` or `angle` on the `Note` / `StrumNote` itself: `ModManager.applyPosition()`,
		`applyScale()` and `applyAngle()` own those properties and remember what they wrote, so a write
		behind their back makes the modifier and a running `FlxTween` fight over the sprite.

		Mutating this vector is what reaches the appliers - assigning a whole new `Vector3` to it does
		not, because the manager keeps and reads back the instance it handed in.
	**/
	public var pos:Vector3;

	public function new(modMgr:ModManager, ?parent:Modifier, script:HScript)
	{
		scripts = new FunkinHScript();

		this.script = script;
		this.modMgr = modMgr;
		this.parent = parent;

		if (this.script != null)
			scripts.scripts.push(this.script);

		super(this.modMgr, this.parent);

		modchart();
	}

	/**
		Called once the backing script exists: binds `this`, `modMgr` and `parent` inside it and runs
		its `onCreate` / `onCreatePost`.

		The value accessors are deliberately *not* installed as script globals: `this` already is this
		modifier (so `this.getValue(player)` and friends reach the overrides below), and a global
		`getValue` would both shadow a `getValue` the script defines itself and make the `getValue`
		override call that very global back into itself.
	**/
	function modchart()
	{
		if (script == null)
			return;

		script.set("this", this);
		script.set("modMgr", this.modMgr);
		script.set("parent", this.parent);

		script.executeFunc("onCreate");

		script.executeFunc("onCreatePost");
	}

	@:noCompletion
	private static final _scriptEnums:Map<String, Dynamic> = [
		"NOTE_MOD" => NOTE_MOD,
		"MISC_MOD" => MISC_MOD,
		"FIRST" => FIRST,
		"PRE_REVERSE" => PRE_REVERSE,
		"REVERSE" => REVERSE,
		"POST_REVERSE" => POST_REVERSE,
		"DEFAULT" => DEFAULT,
		"LAST" => LAST
	];

	public static function fromString(modMgr:ModManager, ?parent:Modifier, scriptSource:String):HScriptModifier
	{
		return new HScriptModifier(modMgr, parent, new HScript(scriptSource, "HScriptModifier", _scriptEnums));
	}

	public static function fromName(modMgr:ModManager, ?parent:Modifier, scriptName:String):Null<HScriptModifier>
	{
		var fileName:String = 'modifiers/$scriptName.hscript';
		for (filePath in [#if MODS_ALLOWED Paths.modFolders(fileName), #end Paths.getPreloadPath(fileName)])
		{
			if (!FileSystem.exists(filePath))
				continue;

			var mod = new HScriptModifier(modMgr, parent, new HScript(File.getContent(filePath), 'HScriptModifier:$scriptName', _scriptEnums));
			mod.name = scriptName;
			return mod;
		}

		trace('Modifier script: $scriptName not found!');
		return null;
	}

	/**
		True when the script implements that callback (and false when there is no script at all, in
		which case every callback falls back to `Modifier`).
	**/
	inline function hasScriptFunc(funcName:String):Bool
		return script != null && script.exists(funcName);

	//// this is where a macro could have helped me, if i weren't so stupid.
	// lol i'll probably rewrite this to use a macro dont worry bb

	override public function getModType()
		return hasScriptFunc("getModType") ? script.executeFunc("getModType") : super.getModType();

	override public function ignorePos()
		return hasScriptFunc("ignorePos") ? script.executeFunc("ignorePos") : super.ignorePos();

	override public function ignoreUpdateReceptor()
		return hasScriptFunc("ignoreUpdateReceptor") ? script.executeFunc("ignoreUpdateReceptor") : super.ignoreUpdateReceptor();

	override public function ignoreUpdateNote()
		return hasScriptFunc("ignoreUpdateNote") ? script.executeFunc("ignoreUpdateNote") : super.ignoreUpdateNote();

	override public function doesUpdate()
		return hasScriptFunc("doesUpdate") ? script.executeFunc("doesUpdate") : super.doesUpdate();

	override public function shouldExecute(player:Int, value:Float):Bool
		return hasScriptFunc("shouldExecute") ? script.executeFunc("shouldExecute", [player, value]) : super.shouldExecute(player, value);

	override public function getOrder():Int
		return hasScriptFunc("getOrder") ? script.executeFunc("getOrder") : super.getOrder();

	override public function getName():String
		return hasScriptFunc("getName") ? script.executeFunc("getName") : name;

	// getValue/getPercent are read back by the manager, they are not meant to be written through
	override public function getValue(player:Int):Float
		return hasScriptFunc("getValue") ? script.executeFunc("getValue", [player]) : super.getValue(player);

	override public function getPercent(player:Int):Float
		return hasScriptFunc("getPercent") ? script.executeFunc("getPercent", [player]) : super.getPercent(player);

	override public function setValue(value:Float, player:Int = -1)
		return hasScriptFunc("setValue") ? script.executeFunc("setValue", [value, player]) : super.setValue(value, player);

	override public function setPercent(percent:Float, player:Int = -1)
		return hasScriptFunc("setPercent") ? script.executeFunc("setPercent", [percent, player]) : super.setPercent(percent, player);

	override public function getSubmodPercent(modName:String, player:Int)
		return hasScriptFunc("getSubmodPercent") ? script.executeFunc("getSubmodPercent", [modName, player]) : super.getSubmodPercent(modName, player);

	override public function getSubmodValue(modName:String, player:Int)
		return hasScriptFunc("getSubmodValue") ? script.executeFunc("getSubmodValue", [modName, player]) : super.getSubmodValue(modName, player);

	override public function getSubmods():Array<String>
		return hasScriptFunc("getSubmods") ? script.executeFunc("getSubmods") : super.getSubmods();

	/**
		Hands the shared position vector to the script as `this.pos` and lets it add to it. The vector
		is the one `ModManager.getPos()` produced, and the manager reads it back afterwards, so adding
		to `this.pos` moves the arrow through the modchart layer instead of overwriting the appliers.
	**/
	override public function updateReceptor(beat:Float, receptor:StrumNote, pos:Vector3, player:Int)
	{
		if (!hasScriptFunc("updateReceptor"))
		{
			super.updateReceptor(beat, receptor, pos, player);
			return;
		}

		this.pos = pos;
		script.executeFunc("updateReceptor", [beat, receptor, player]);
		this.pos = null;
	}

	override public function updateNote(beat:Float, note:Note, pos:Vector3, player:Int)
	{
		if (!hasScriptFunc("updateNote"))
		{
			super.updateNote(beat, note, pos, player);
			return;
		}

		this.pos = pos;
		script.executeFunc("updateNote", [beat, note, player]);
		this.pos = null;
	}

	override public function update(elapsed:Float)
	{
		if (!hasScriptFunc("update"))
		{
			super.update(elapsed);
			return;
		}

		script.executeFunc("update", [elapsed]);
	}

	// Schmovin' leftovers this fork's `Modifier` does not have: `getPos(diff, tDiff, beat, pos, data,
	// player, obj, field)`, `modifyVert(...)`, `getExtraInfo(...)` (its `RenderInfo` type does not
	// exist here) and `isRenderMod()`. `updateReceptor`/`updateNote` above are where a script can
	// still change the position of something, because `this.pos` is handed to it there.
}
