package editors.blockcode;

import openfl.display.Stage;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFieldType;
import openfl.text.TextFormat;
import openfl.ui.Keyboard;

/**
 * Text entry for the block-code editor, usable on top of a running PlayState.
 *
 * The engine has no other helper for this, so the module borrows OpenFL's input handling:
 * a real `openfl.text.TextField` is attached straight to `FlxG.stage` and focused. Focusing an
 * OpenFL TextField is enough to raise the native keyboard - `TextField.__startTextInput()` runs
 * on `FocusEvent.FOCUS_IN` and flips `stage.window.textInputEnabled` plus `setTextInputRect()`
 * (see `openfl/text/TextField.hx` and `openfl/display/Stage.hx`), which is exactly what makes the
 * Android/iOS IME appear over the game. Keep that in mind before deleting the focus block below.
 *
 * The field's own glyphs are invisible by default (`fieldAlpha = 0`) because the editor canvas
 * draws the text itself in Flixel space, but the object has to stay `visible` and attached for
 * the OS to keep the IME, the caret and the selection alive.
 *
 * Coordinate handling: the field lives in stage pixels while the caller thinks in Flixel
 * (game) pixels, so `targetRect` is converted through the game canvas' own transform. That keeps
 * the field on the on-screen text box even when the window is resized or letterboxed by
 * `backend.ScaleModeRezie` (mobile, or a resized desktop window).
 *
 * Usage:
 * ```haxe
 * BlockSoftKeyboard.targetRect = new Rectangle(boxX, boxY, boxW, boxH); // Flixel coordinates
 * BlockSoftKeyboard.open(currentValue, false, function(text:String) {
 *     box.value = text;
 * }, function() {
 *     // field dismissed: commit UI changes here
 * });
 * ```
 */
class BlockSoftKeyboard
{
	/**
	 * Area the field should cover, in Flixel (game) coordinates. When left `null` a band across
	 * the upper part of the screen is used, which stays clear of the note field and of the area
	 * a soft keyboard usually covers.
	 */
	public static var targetRect:Rectangle = null;

	/**
	 * Alpha of the input field. `0` keeps it invisible so only the in-game text and the system
	 * IME/caret are seen; raise it for platforms or debug builds that want the raw field shown.
	 */
	public static var fieldAlpha:Float = 0;

	/** Frames to ignore the focus check for after `open()`, see `checkFocus()`. */
	static inline var FOCUS_GRACE_FRAMES:Int = 2;

	static var _field:TextField = null;
	static var _isOpen:Bool = false;
	static var _multiline:Bool = false;
	static var _cachedText:String = "";
	static var _graceFrames:Int = 0;

	static var _textCallback:String->Void = null;
	static var _closeCallback:Void->Void = null;

	static var _changeListener:Event->Void = null;
	static var _keyListener:KeyboardEvent->Void = null;
	static var _frameListener:Void->Void = null;
	static var _switchListener:Void->Void = null;

	/** Resolved once: `Paths.fontName()` registers the font file on every call. */
	static var _fontName:String = null;

	/** True while a field is attached and text is being collected. */
	public static function isOpen():Bool
	{
		return _isOpen;
	}

	/**
	 * True when the platform provides a system keyboard we can raise (Android / iOS). Desktop
	 * uses the hardware keyboard and HTML5 gets the browser's own hidden input element, so both
	 * report `false` and the editor should offer its on-screen keyboard instead when it needs to.
	 */
	public static function isNativeAvailable():Bool
	{
		#if (android || ios)
		return true;
		#else
		return false;
		#end
	}

	/** Current text, also after the field has been closed. */
	public static function text():String
	{
		final tf = _field;
		if (tf != null)
			return tf.text;
		return _cachedText;
	}

	/**
	 * Opens the field with `initial` text.
	 *
	 * `onText` is called on every edit and again on commit; `onClose` is called exactly once when
	 * the field goes away, whichever path closed it.
	 */
	public static function open(initial:String, multiline:Bool, onText:String->Void, onClose:Void->Void):Void
	{
		// Re-opening must never leave the previous field attached; its owner gets its onClose.
		close();

		_multiline = multiline;
		_cachedText = multiline ? (initial != null ? initial : "") : stripNewlines(initial);
		_textCallback = onText;
		_closeCallback = onClose;
		_graceFrames = FOCUS_GRACE_FRAMES;

		final stage = FlxG.stage;
		if (stage == null)
		{
			// Nothing to attach to (headless build, very early boot): report the failure instead
			// of pretending the keyboard is up.
			_textCallback = null;
			_closeCallback = null;
			if (onClose != null)
				onClose();
			return;
		}

		final tf = new TextField();
		_field = tf;
		_isOpen = true;

		tf.type = TextFieldType.INPUT;
		tf.multiline = multiline;
		tf.wordWrap = multiline;
		tf.selectable = true;
		tf.autoSize = TextFieldAutoSize.NONE;
		tf.mouseEnabled = true; // tapping the field itself must not blur it again
		tf.background = false;
		tf.border = false;
		// Both of these matter: `visible = false` would drop the IME and the caret, and the OS
		// only keeps a soft keyboard up while the focused object is rendered.
		tf.visible = true;
		tf.alpha = fieldAlpha;
		tf.needsSoftKeyboard = isNativeAvailable();
		tf.defaultTextFormat = new TextFormat(fontName(), multiline ? 20 : 24, 0xFFFFFF);
		tf.text = _cachedText;

		applyRect(stage);

		_changeListener = function(e:Event):Void
		{
			handleChange();
		};

		_keyListener = function(e:KeyboardEvent):Void
		{
			handleKey(e);
		};

		_frameListener = function():Void
		{
			checkFocus();
		};

		tf.addEventListener(Event.CHANGE, _changeListener);
		tf.addEventListener(KeyboardEvent.KEY_DOWN, _keyListener);

		stage.addChild(tf);

		// Focusing the field dispatches FOCUS_IN, and `TextField.this_onFocusIn` calls
		// `__startTextInput()`: input is enabled and the field bounds are handed to
		// `window.setTextInputRect()`, which is what raises/positions the Android and iOS IME.
		// Do not "simplify" this into the requestSoftKeyboard() call below - that one only
		// supplements it.
		stage.focus = tf;

		#if (android || ios)
		// Ask explicitly as well: some IMEs only honour the request and ignore a plain focus.
		try
		{
			tf.requestSoftKeyboard();
		}
		catch (e:Dynamic)
		{
			// Device without a soft keyboard: hardware/on-screen keys still work.
		}
		#end

		// A state change would otherwise strand a focused (invisible) input field on the stage,
		// keeping the IME up forever. Teardown there is silent - the owner is being switched out.
		_switchListener = function():Void
		{
			destroy();
		};
		FlxG.signals.preStateSwitch.add(_switchListener);

		FlxG.signals.preUpdate.add(_frameListener);
	}

	/** Pushes a programmatic change into the live field (caret moved to the end, no callbacks). */
	public static function update(text:String):Void
	{
		_cachedText = text != null ? text : "";

		final tf = _field;
		if (tf == null || tf.text == _cachedText)
			return;

		tf.text = _cachedText; // assigning `text` deliberately does not dispatch CHANGE
		tf.setSelection(_cachedText.length, _cachedText.length);
	}

	/** Dismisses the field, dropping focus (and with it the IME) and calling the close callback once. */
	public static function close():Void
	{
		if (!_isOpen)
			return;

		final notify = _closeCallback;

		detach();
		_textCallback = null;
		_closeCallback = null;
		_isOpen = false;
		_multiline = false;
		_graceFrames = 0;

		if (notify != null)
			notify();
	}

	/**
	 * Hard teardown for state/editor cleanup: detaches everything and forgets the callbacks
	 * **without** invoking the close callback, because the owner is assumed to be going away too
	 * and may already be unsafe to call into. Use `close()` for a normal dismissal.
	 */
	public static function destroy():Void
	{
		detach();
		_textCallback = null;
		_closeCallback = null;
		_cachedText = "";
		_isOpen = false;
		_multiline = false;
		_graceFrames = 0;
	}

	static function handleChange():Void
	{
		final tf = _field;
		if (tf == null)
			return;

		final cleaned:String = _multiline ? tf.text : stripNewlines(tf.text);
		if (cleaned != tf.text)
		{
			// A native IME's Enter/Done can arrive as text input instead of as a key event, and
			// OpenFL inserts that "\n" even into a single line field. Strip it and treat it as the
			// commit the user asked for instead of letting a line break into the value.
			tf.text = cleaned;
			commitAndClose();
			return;
		}

		_cachedText = cleaned;
		pushText(_cachedText);
	}

	static function handleKey(event:KeyboardEvent):Void
	{
		final tf = _field;
		if (tf == null)
			return;

		final code:Int = event.keyCode;

		if (code == Keyboard.ESCAPE)
		{
			close();
			return;
		}

		if (code != Keyboard.ENTER && code != Keyboard.NUMPAD_ENTER)
			return;

		if (!_multiline)
		{
			commitAndClose();
			return;
		}

		// OpenFL's own TextField editor inserts the newline from `window.onKeyDown`, and lime runs
		// that handler *after* this listener. Cancelling the default keeps the newline at exactly
		// one; BACKSPACE, arrows, delete and every other editing key are untouched here, so the
		// built-in editor keeps handling them.
		event.preventDefault();

		tf.replaceSelectedText("\n");
		// `replaceSelectedText()` does not dispatch CHANGE itself (the built-in editor does it
		// around the call), so the edit is announced here.
		tf.dispatchEvent(new Event(Event.CHANGE, true));
	}

	/**
	 * Runs every frame while the field is up. Focus loss is handled here instead of in a
	 * `FOCUS_OUT` listener on purpose: a tap anywhere in the game clears `stage.focus` in the same
	 * frame it lands, and reacting to that immediately would dismiss the keyboard right after it
	 * opened (the tap that opened the editor is still being processed at that point).
	 */
	static function checkFocus():Void
	{
		if (!_isOpen)
			return;

		final stage = FlxG.stage;
		if (stage == null)
		{
			close();
			return;
		}

		if (_graceFrames > 0)
		{
			_graceFrames--;
			return;
		}

		final tf = _field;
		if (tf == null || stage.focus != tf)
			close();
	}

	/** Hands the final value over once more and dismisses the field. */
	static function commitAndClose():Void
	{
		final tf = _field;
		_cachedText = tf != null ? tf.text : _cachedText;
		pushText(_cachedText);
		close();
	}

	static function pushText(value:String):Void
	{
		final callback = _textCallback;
		if (callback != null)
			callback(value);
	}

	/** Removes listeners, the signals and the field itself. Callbacks are left untouched. */
	static function detach():Void
	{
		if (_frameListener != null)
		{
			FlxG.signals.preUpdate.remove(_frameListener);
			_frameListener = null;
		}

		if (_switchListener != null)
		{
			FlxG.signals.preStateSwitch.remove(_switchListener);
			_switchListener = null;
		}

		final tf = _field;
		_field = null;

		if (tf == null)
			return;

		if (_changeListener != null)
		{
			tf.removeEventListener(Event.CHANGE, _changeListener);
			_changeListener = null;
		}

		if (_keyListener != null)
		{
			tf.removeEventListener(KeyboardEvent.KEY_DOWN, _keyListener);
			_keyListener = null;
		}

		// Clearing the focus turns `window.textInputEnabled` off (FOCUS_OUT ->
		// `TextField.__stopTextInput()`), which hides the soft keyboard again.
		final stage = FlxG.stage;
		if (stage != null && stage.focus == tf)
			stage.focus = null;

		if (tf.parent != null)
			tf.parent.removeChild(tf);
	}

	/** Sizes and places the field over `targetRect` (Flixel space), clamped to the screen. */
	static function applyRect(stage:Stage):Void
	{
		final tf = _field;
		if (tf == null || stage == null)
			return;

		final screen:Rectangle = toStageRect(targetRect != null ? targetRect : defaultRect());

		final screenWidth:Float = stage.stageWidth > 0 ? stage.stageWidth : FlxG.width;
		final screenHeight:Float = stage.stageHeight > 0 ? stage.stageHeight : FlxG.height;

		screen.x = Math.max(0, Math.min(screen.x, screenWidth - 1));
		screen.y = Math.max(0, Math.min(screen.y, screenHeight - 1));
		screen.width = Math.max(1, Math.min(screen.width, screenWidth - screen.x));
		screen.height = Math.max(1, Math.min(screen.height, screenHeight - screen.y));

		tf.x = screen.x;
		tf.y = screen.y;
		tf.width = screen.width;
		tf.height = screen.height;
	}

	/**
	 * Converts a Flixel-space rectangle into the stage pixels the TextField lives in. The game
	 * canvas is scaled and offset by the active scale mode, so the raw numbers only match on an
	 * unscaled window. Public so callers that only know stage coordinates can convert before
	 * assigning `targetRect`.
	 */
	public static function toStageRect(game:Rectangle):Rectangle
	{
		final flxGame = FlxG.game;
		if (flxGame == null)
			return game.clone();

		final matrix:Matrix = flxGame.transform.concatenatedMatrix;
		var scaleX:Float = Math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b);
		var scaleY:Float = Math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d);
		if (scaleX <= 0)
			scaleX = 1;
		if (scaleY <= 0)
			scaleY = 1;

		final origin:Point = matrix.transformPoint(new Point(game.x, game.y));
		return new Rectangle(origin.x, origin.y, game.width * scaleX, game.height * scaleY);
	}

	/**
	 * Fallback area for callers that did not place the editor's text box themselves: a band in
	 * the upper part of the screen, on top of the game and clear of the soft keyboard.
	 */
	static function defaultRect():Rectangle
	{
		final width:Float = FlxG.width > 0 ? FlxG.width : 1280;
		final height:Float = FlxG.height > 0 ? FlxG.height : 720;

		final rectWidth:Float = Math.max(200, width * 0.7);
		final rectHeight:Float = _multiline ? Math.max(90, height * 0.3) : Math.max(48, height * 0.08);

		return new Rectangle((width - rectWidth) * 0.5, Math.max(0, height * 0.2), rectWidth, rectHeight);
	}

	static function stripNewlines(value:String):String
	{
		if (value == null)
			return "";

		return value.replace("\r", "").replace("\n", "");
	}

	/**
	 * Font name for the field, resolved through `Paths` and cached: `Paths.fontName()` loads and
	 * registers the font file from disk, and the editor re-opens this field for every parameter it
	 * edits, so calling it per open would pile up font instances.
	 */
	static function fontName():String
	{
		if (_fontName == null)
		{
			final resolved:String = Paths.fontName("vcr.ttf");
			_fontName = resolved != null ? resolved : "vcr.ttf";
		}

		return _fontName;
	}
}
