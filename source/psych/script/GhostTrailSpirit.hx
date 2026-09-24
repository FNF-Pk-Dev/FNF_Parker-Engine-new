package psych.script;

import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.util.FlxColor;

/**
 * A single snapshotted copy of the sprite a `GhostTrailSpirit` trails.
 *
 * A ghost never runs its own update/animation code: the trail freezes the target's frame,
 * transform and offsets onto it on spawn and only fades it out afterwards, so the ghost keeps
 * showing the exact pose the target was in when it was spawned.
 */
private class TrailGhost extends FlxSprite
{
	/** Seconds this ghost has been alive, drives the alpha falloff. */
	public var age:Float = 0;

	public function new()
	{
		super();
		// Ghosts are still pictures, they must not update an animation of their own
		active = false;
		exists = false;
	}
}

/**
 * Ghost trail spirit of the "Engine Custom ES" dialect (`makeTrailSpirit`).
 *
 * Every `stepInterval` seconds a frozen copy of `target` is spawned at the target's position and
 * then fades from `startAlpha` to nothing over `life` seconds. While a ghost lives it can drift
 * on its own: `followTarget` makes it chase the target at `dirSpeed` px/s, otherwise it moves
 * along the unit direction (`dirX`, `dirY`) at that speed. Dead ghosts stay in the group and are
 * recycled by the next spawn.
 */
class GhostTrailSpirit extends FlxGroup
{
	/** Never spawn faster than 240/s, a script may set a zero delay. */
	static inline var MIN_STEP_INTERVAL:Float = 1 / 240;

	/** A hitched frame must not spawn thousands of ghosts at once. */
	static inline var MAX_SPAWNS_PER_FRAME:Int = 16;

	public var target:FlxSprite;

	/** `trailAlpha` - alpha a ghost starts with and fades out from. */
	public var startAlpha:Float = 0.6;

	/** `trailLife` - seconds a ghost lives before it disappears. */
	public var life:Float = 1;

	/** `trailDelay` - seconds between two spawns. */
	public var stepInterval:Float = 0.1;

	/** `trailSpeed` - px/s a ghost drifts (or chases the target) with. */
	public var dirSpeed:Float = 0;

	/** `trailDirection` - unit direction the ghosts drift in. */
	public var dirX:Float = 0;

	public var dirY:Float = 0;

	/** `trailDirection(tag, 'follow')` - ghosts chase the target instead of drifting. */
	public var followTarget:Bool = false;

	/** Tint of every ghost, white leaves them looking like the target. */
	public var ghostColor:FlxColor = FlxColor.WHITE;

	/** Stopped trails stop spawning, the ghosts already alive still fade out. */
	public var activeTrail:Bool = true;

	var stepTimer:Float = 0;
	var ghosts:Array<TrailGhost> = [];

	public function new(target:FlxSprite)
	{
		super();
		this.target = target;
	}

	public function setTarget(sprite:FlxSprite):Void
	{
		target = sprite;
	}

	/** `follow` chases the target, compass names drift, anything else stands still. */
	public function parseDirection(direction:String):Void
	{
		followTarget = false;
		dirX = 0;
		dirY = 0;

		if (direction == null)
			return;

		switch (direction.toLowerCase().trim().replace('-', '').replace('_', ''))
		{
			case 'follow' | 'target':
				followTarget = true;
			case 'up':
				dirY = -1;
			case 'down':
				dirY = 1;
			case 'left':
				dirX = -1;
			case 'right':
				dirX = 1;
			case 'upleft' | 'leftup':
				dirX = -1;
				dirY = -1;
			case 'upright' | 'rightup':
				dirX = 1;
				dirY = -1;
			case 'downleft' | 'leftdown':
				dirX = -1;
				dirY = 1;
			case 'downright' | 'rightdown':
				dirX = 1;
				dirY = 1;
			default: // 'none'/'static' and anything unknown leave the ghosts where they are
		}

		if (!followTarget)
		{
			var length:Float = Math.sqrt(dirX * dirX + dirY * dirY);
			if (length > 0)
			{
				dirX /= length;
				dirY /= length;
			}
		}
	}

	/** `#RRGGBB` / `RRGGBB` / `0xAARRGGBB`, anything unreadable is plain white. */
	public function parseColorHex(color:String):FlxColor
	{
		if (color == null || color.length < 1)
			return FlxColor.WHITE;

		color = color.trim();
		if (!color.startsWith('0x') && !color.startsWith('0X'))
			color = '0xff' + color.replace('#', '');

		var parsed:Null<Int> = Std.parseInt(color);
		return parsed == null ? FlxColor.WHITE : parsed;
	}

	/** Kills every ghost of the trail. */
	public function clearGhosts():Void
	{
		if (ghosts == null)
			return; // already destroyed

		stepTimer = 0;
		for (ghost in ghosts)
			ghost.kill();
	}

	override public function update(elapsed:Float):Void
	{
		if (members == null)
			return; // destroyed while the state still holds the group

		if (activeTrail && target != null && target.exists && target.visible)
		{
			var interval:Float = stepInterval > 0 ? stepInterval : MIN_STEP_INTERVAL;
			stepTimer += elapsed;

			var spawned:Int = 0;
			while (stepTimer >= interval && spawned < MAX_SPAWNS_PER_FRAME)
			{
				stepTimer -= interval;
				spawnGhost();
				spawned++;
			}

			if (stepTimer > interval) // the per frame cap was hit, drop the backlog
				stepTimer = 0;
		}

		updateGhosts(elapsed);
		super.update(elapsed);
	}

	/** Recycles a dead ghost or makes a new one, then snaps it onto the target's current pose. */
	function spawnGhost():Void
	{
		if (target == null || target.frames == null)
			return;

		var ghost:TrailGhost = null;
		for (candidate in ghosts)
		{
			if (!candidate.alive)
			{
				ghost = candidate;
				break;
			}
		}

		if (ghost == null)
		{
			ghost = new TrailGhost();
			ghosts.push(ghost);
			add(ghost);
		}

		ghost.age = 0;
		ghost.alpha = startAlpha;

		// Repointing frames resets the frame index, so the pose has to be copied after it
		if (ghost.frames != target.frames)
			ghost.frames = target.frames;
		ghost.frame = target.frame;
		ghost.resetSizeFromFrame();

		// Same position and offset as the target keeps the ghost drawn exactly over it
		ghost.x = target.x;
		ghost.y = target.y;
		ghost.offset.copyFrom(target.offset);
		ghost.origin.copyFrom(target.origin);
		ghost.scale.copyFrom(target.scale);
		ghost.scrollFactor.copyFrom(target.scrollFactor);
		ghost.angle = target.angle;
		ghost.flipX = target.flipX;
		ghost.flipY = target.flipY;
		ghost.antialiasing = target.antialiasing;
		ghost.blend = target.blend;

		if (ghost.color != ghostColor)
			ghost.color = ghostColor;

		ghost.revive();
	}

	function updateGhosts(elapsed:Float):Void
	{
		// A zero lifetime would leave the alpha falloff undefined, so it fades in one frame
		var ghostLife:Float = life > 0 ? life : MIN_STEP_INTERVAL;

		for (ghost in ghosts)
		{
			if (!ghost.exists)
				continue;

			ghost.age += elapsed;
			if (ghost.age >= ghostLife)
			{
				ghost.kill();
				continue;
			}

			ghost.alpha = startAlpha * (1 - ghost.age / ghostLife);
			moveGhost(ghost, elapsed);
		}
	}

	function moveGhost(ghost:TrailGhost, elapsed:Float):Void
	{
		if (dirSpeed == 0)
			return;

		if (followTarget && target != null && target.exists)
		{
			var dx:Float = target.x - ghost.x;
			var dy:Float = target.y - ghost.y;
			var distance:Float = Math.sqrt(dx * dx + dy * dy);
			if (distance <= 0.0001)
				return;

			var step:Float = Math.min(dirSpeed * elapsed, distance); // never overshoot the target
			ghost.x += dx / distance * step;
			ghost.y += dy / distance * step;
			return;
		}

		ghost.x += dirX * dirSpeed * elapsed;
		ghost.y += dirY * dirSpeed * elapsed;
	}

	override public function destroy():Void
	{
		clearGhosts();
		ghosts = null;
		target = null;

		super.destroy();
	}
}
