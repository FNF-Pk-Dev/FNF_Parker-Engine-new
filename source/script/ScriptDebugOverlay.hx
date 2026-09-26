package script;

import crowplexus.iris.Iris;
import flixel.FlxState;

/**
 * On-screen error/debug text for scripts running in scripted states.
 *
 * PlayState prints everything its scripts report through `PlayState.addTextToDebug` (the
 * `luaDebugGroup`), but the states that replace it — `LuaSState`, `LScriptSState` and
 * `OScriptState` — have no PlayState at all, so their scripts' messages used to reach
 * `trace`/`FlxG.log` only, and anything going through Iris or PlayState crashed instead of printing.
 * `report()` is the shared entry point for those three: while a song runs the message still goes to
 * PlayState, otherwise it prints on the overlay of the state running the script.
 *
 * The overlay draws through its own `FlxCamera`, appended last to `FlxG.cameras.list`. Cameras are
 * composited in list order, so being last is what makes the overlay top-most: above the state's own
 * sprites, its substates, transition sprites and every camera a mod script adds. `keepOnTop()`
 * re-appends the camera whenever something lands above it (one comparison per frame, and a no-op
 * while nothing does) instead of trusting a single point in time, because `LuaSState` (camHUD),
 * `addPadCamera()` and mod scripts all add cameras whenever they please.
 *
 * Messages reported while no overlay exists yet — a script error in `LScriptSState`'s or
 * `LuaSState`'s constructor, where `FlxG.state` is still the outgoing state — are queued and
 * flushed by `attach()`, which each scripted state calls from its own `create()`.
 */
class ScriptDebugOverlay extends FlxTypedGroup<DebugScriptText>
{
	/** Lines kept on screen, the same cap PlayState puts on its debug text. */
	public static inline final MAX_LINES:Int = 34;

	/** Vertical step between two lines, matches PlayState's debug text. */
	static inline final LINE_HEIGHT:Float = 20;

	/** Overlay of the scripted state on screen, `null` while there is none. */
	public static var instance(default, null):ScriptDebugOverlay = null;

	/** Messages reported while there was no overlay, oldest first, flushed by `attach()`. */
	static var pending:Array<ScriptDebugMessage> = [];

	/** State this overlay and its camera belong to. */
	public var owner(default, null):FlxState;

	var cam:FlxCamera;

	public function new(owner:FlxState)
	{
		super();

		this.owner = owner;

		cam = new FlxCamera();
		cam.bgColor.alpha = 0;
		// Not a default draw target, so only this group renders through it (PlayState points camOther
		// at its debug text the same way), and adding it last leaves it above the cameras already
		// in the list.
		FlxG.cameras.add(cam, false);

		cameras = [cam];
		owner.add(this);
	}

	/**
	 * Makes `owner` the state `report()` prints on, creating its overlay the first time. Scripted
	 * states call this from `create()`; whatever was reported before that is flushed here.
	 */
	public static function attach(owner:FlxState):ScriptDebugOverlay
	{
		#if DISABLE_LOGS
		return null;
		#else
		if (instance != null && instance.owner == owner)
			return instance;

		// The state that owned the previous overlay is on its way out, don't let its camera linger.
		if (instance != null)
			instance.dispose();

		instance = new ScriptDebugOverlay(owner);
		instance.flush();

		return instance;
		#end
	}

	/**
	 * Prints `text` the way `PlayState.addTextToDebug` does: PlayState keeps owning the debug text
	 * while a song runs, otherwise the message goes to the overlay of the scripted state on screen.
	 */
	public static function report(text:String, color:FlxColor = FlxColor.WHITE):Void
	{
		#if !DISABLE_LOGS
		final playState:PlayState = PlayState.instance;
		if (playState != null)
		{
			playState.addTextToDebug(text, color);
			return;
		}

		if (instance != null)
		{
			instance.addLine(text, color);
			return;
		}

		// Nothing to print on yet, hold the message for the overlay that attaches next and keep it
		// in the log in the meantime.
		queue(text, color);
		FlxG.log.error(text);
		#end
	}

	/**
	 * Points Iris' global log handlers at `report()`.
	 *
	 * `FunkinHScript.InitLogger()`, which every `HScript` constructor runs, sends Iris messages
	 * straight to `PlayState.addTextToDebug`: outside a song that null-references, so a failing
	 * script function crashed inside Iris' own `catch` instead of reporting anything. `OScriptState`
	 * installs these after building its script to keep the same message format without a PlayState;
	 * PlayState's scripts reinstall their own handlers when they are constructed again, and
	 * `report()` still defers to PlayState whenever there is one, so the two never fight.
	 */
	public static function hookScriptLog():Void
	{
		Iris.warn = function(x, ?pos)
		{
			log('WARN', x, pos, FlxColor.YELLOW);
		};

		Iris.error = function(x, ?pos)
		{
			log('ERROR', x, pos, FlxColor.RED);
		};

		Iris.print = function(x, ?pos)
		{
			log('TRACE', x, pos, FlxColor.WHITE);
		};
	}

	/** Formats an Iris message the way `FunkinHScript.InitLogger()` does, minus its PlayState. */
	static function log(level:String, x:Dynamic, ?pos:haxe.PosInfos, color:FlxColor = FlxColor.WHITE):Void
	{
		#if !DISABLE_LOGS
		final message:String = (pos == null || pos.fileName == null) ? '$level: $x' : '[${pos.fileName}]: $level: ${pos.lineNumber} -> $x';

		report(message, color);
		FlxG.log.error(message);
		#end
	}

	/** Adds a message to the queue, which never grows past what the overlay could show anyway. */
	static function queue(text:String, color:FlxColor):Void
	{
		pending.push({text: text, color: color});

		if (pending.length > MAX_LINES)
			pending.shift();
	}

	/** Prints one message, stacking the previous lines like `PlayState.addTextToDebug`. */
	function addLine(text:String, color:FlxColor):Void
	{
		forEachAlive(function(spr:DebugScriptText)
		{
			spr.y += LINE_HEIGHT;
		});

		if (members.length > MAX_LINES && members[MAX_LINES] != null)
		{
			// Spliced out so the dropped line leaves no null hole behind in `members`
			final oldest = members[MAX_LINES];
			oldest.destroy();
			remove(oldest, true);
		}

		insert(0, new DebugScriptText(text, color));
	}

	/** Empties the queued messages onto this overlay, oldest first so the newest ends up on top. */
	function flush():Void
	{
		var i:Int = pending.length;
		while (i-- > 0)
		{
			final message = pending[i];
			addLine(message.text, message.color);
		}

		pending = [];
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		keepOnTop();
	}

	/** Keeps the overlay camera the last entry of `FlxG.cameras.list`, which is the draw order. */
	function keepOnTop():Void
	{
		if (cam == null)
			return;

		final cameras = FlxG.cameras.list;
		// A state switch resets the whole list (FlxGame.switchState), and then there is nothing left
		// to reorder: this state and the overlay are being torn down anyway.
		if (cameras.length == 0 || !cameras.contains(cam) || cameras[cameras.length - 1] == cam)
			return;

		FlxG.cameras.remove(cam, false);
		FlxG.cameras.add(cam, false);
	}

	/** Drops the camera, called when the owner state is destroyed or another one takes it over. */
	public function dispose():Void
	{
		if (cam != null && FlxG.cameras.list.contains(cam))
			FlxG.cameras.remove(cam, true);

		cam = null;

		if (instance == this)
			instance = null;
	}

	override function destroy():Void
	{
		dispose();
		super.destroy();
	}
}

/** One line of `ScriptDebugOverlay`, the look-alike of PlayState's `DebugLuaText`. */
class DebugScriptText extends FlxText
{
	private var disableTime:Float = 6;

	public function new(text:String, color:FlxColor)
	{
		super(10, 10, 0, text, 16);
		setFormat(Paths.font("vcr.ttf"), 16, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scrollFactor.set();
		borderSize = 1;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		disableTime -= elapsed;
		if (disableTime < 0)
			disableTime = 0;
		if (disableTime < 1)
			alpha = disableTime;
	}
}

/** A message waiting for the next `ScriptDebugOverlay.attach()`. */
typedef ScriptDebugMessage =
{
	var text:String;
	var color:FlxColor;
}
