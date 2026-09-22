package editors.blockcode;

import flixel.group.FlxGroup;
import flixel.input.touch.FlxTouch;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

/**
 * Bottom-sheet on-screen keyboard, drawn entirely with `FlxSprite`s, for phones and tablets (and
 * for anyone who prefers it over the native IME) while the block-code editor substate sits on top
 * of a running `PlayState`.
 *
 * The keyboard owns a plain `String` buffer and knows nothing about blocks, Lua or `PlayState`: the
 * caller decides when it opens, with which text and which layout, and gets every press reported
 * through `onKey` so it can mirror the buffer or react to `enter` / `close` without polling. The
 * buffer is the single source of truth and is always readable with `getText()`.
 *
 * Shape, top to bottom: a preview strip (the text being typed, scrolled so the caret stays visible,
 * the character count and a Hide button), a layout switcher row (`ABC` / `123` / `#+=` / `code` /
 * `CLR`), the character rows of the active layout and finally the function row (`abc`/`ABC` shift,
 * plus `TAB` in the code layout, space, delete and enter). Every key is a rounded rectangle with a
 * 1px outline, it fills with the accent colour while it is held and shrinks slightly, and the gap
 * between two keys is at least 16% of a key height so a thumb cannot land between them. Four
 * layouts: `letters` (QWERTY), `numbers`, `symbols` and `code`, which carries every Lua character
 * people actually type - `( ) [ ] { } = " ' . , : ; < > + - * / % # ~ $ _` plus the four-space TAB.
 *
 * Sizing comes from `BlockLayout`: key height `max(touchSize(), 44)` (a little taller upright), key
 * fonts from `BlockLayout.font('body')` for single characters and `font('small')` for words, padding
 * from `BlockLayout.spacing()`. The sheet is capped at `min(BlockLayout.height * 0.45, 460 *
 * BlockLayout.scale)` so the workspace above it stays visible. When the rows would not fit that
 * cap they are reflowed with more keys per row - a wrapped row is never clipped - and portrait
 * screens start from fewer, fatter keys (a thumb keyboard) while landscape keeps wide rows. Only a
 * viewport too short for one finger per row lets the sheet grow past the cap, and it never covers
 * more than 70% of the view.
 *
 * Pointers are read from `FlxG.touches` first - only the first touch drives the keyboard, while any
 * finger is down the synthesized mouse is ignored - and from `FlxG.mouse` as the desktop fallback.
 * A key lights up when the finger lands on it and fires when the finger lifts off the same key, so
 * dragging off cancels a press; the delete key is the exception, it fires at once and repeats while
 * it is held. While closed the group is invisible, inactive and its `update` returns before touching
 * anything, so a tap meant for the editor is never intercepted.
 *
 * No external assets: flat theme colors and `Paths.font("vcr.ttf")`.
 */
class BlockVirtualKeyboard extends FlxGroup
{
	// Theme - the same palette the block-code editor state uses.
	public static inline var COLOR_SHEET:Int = 0xFF1A1B26;
	public static inline var COLOR_KEY:Int = 0xFF2F3349;
	public static inline var COLOR_KEY_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_ACCENT:Int = 0xFF3D59A1;
	public static inline var COLOR_PREVIEW:Int = 0xFF0F0F14;
	public static inline var COLOR_BORDER:Int = 0xFF414868;
	public static inline var COLOR_HINT:Int = 0xFF565F89;
	public static inline var COLOR_DANGER:Int = 0xFFF7768E;

	/** Layout names `setLayout` accepts. */
	public static inline var LAYOUT_LETTERS:String = 'letters';

	public static inline var LAYOUT_NUMBERS:String = 'numbers';
	public static inline var LAYOUT_SYMBOLS:String = 'symbols';
	public static inline var LAYOUT_CODE:String = 'code';

	/** Smallest sheet height in logical pixels. */
	public static inline var MIN_HEIGHT:Float = 220;

	/** Sheet height as a fraction of `FlxG.height`, used when the sheet has not been laid out yet. */
	public static inline var HEIGHT_RATIO:Float = 0.4;

	/** Smallest key height in logical pixels - one finger. */
	public static inline var MIN_KEY_HEIGHT:Float = 44;

	/** What the TAB key inserts. */
	public static inline var TAB_SPACES:String = '    ';

	// Key actions. Ints so they can be used as switch patterns.
	static inline var ACT_CHAR:Int = 1;
	static inline var ACT_SPACE:Int = 2;
	static inline var ACT_BACKSPACE:Int = 3;
	static inline var ACT_ENTER:Int = 4;
	static inline var ACT_SHIFT:Int = 5;
	static inline var ACT_TAB:Int = 6;
	static inline var ACT_CLEAR:Int = 7;
	static inline var ACT_CLOSE:Int = 8;
	static inline var ACT_LAYOUT:Int = 9;

	/** Longest and shortest key row: ten keys read like a phone keyboard, four is still usable. */
	static inline var MAX_COLUMNS:Int = 10;

	static inline var MIN_COLUMNS:Int = 4;

	/** How long the delete key has to be held before it starts repeating, and how fast it then goes. */
	static inline var REPEAT_DELAY:Float = 0.42;

	static inline var REPEAT_INTERVAL:Float = 0.085;
	static inline var REPEAT_MIN_INTERVAL:Float = 0.04;

	/** `vcr.ttf` is monospaced: the width of one character as a fraction of the font size. */
	static inline var CHAR_RATIO:Float = 0.66;

	/** The sheet never covers more of the view than this, however much the rows want. */
	static inline var SHEET_CEILING_RATIO:Float = 0.7;

	/** How far the body of a held key shrinks for feedback. */
	static inline var PRESSED_SCALE:Float = 0.94;

	/** Sample used to measure one character of the preview font. */
	static inline var CELL_SAMPLE:String = '0000000000';

	/** Fired after every key press with the key name: `A`..`Z`, `0`..`9`, `space`, `backspace`, `enter`, `tab`, `shift`, `clear` or `close`. */
	public var onKey:String->Void = null;

	/** Fired by the close/hide key after `onKey('close')`, right before the sheet closes itself. */
	public var onClose:Void->Void = null;

	var _cam:FlxCamera;
	var _open:Bool = false;
	var _text:String = '';
	var _multiline:Bool = false;
	var _layout:String = LAYOUT_LETTERS;
	var _shift:Bool = false;

	var _keys:Array<KeyboardKey> = null;
	var _sheet:FlxSprite = null;
	var _accent:FlxSprite = null;
	var _previewBg:FlxSprite = null;
	var _previewFrame:FlxSprite = null;
	var _preview:FlxText = null;
	var _count:FlxText = null;
	var _caret:FlxSprite = null;

	var _sheetH:Float = 0;
	var _builtViewW:Float = -1;
	var _builtViewH:Float = -1;
	var _builtScale:Float = -1;
	var _builtPortrait:Bool = false;
	var _layoutDirty:Bool = true;
	var _cellW:Float = 0;
	var _previewTextX:Float = 0;
	var _previewFieldW:Float = 0;
	var _caretBlink:Float = 0;

	var _ptrPoint:FlxPoint = null;
	var _ptrX:Float = 0;
	var _ptrY:Float = 0;
	var _ptrPressed:Bool = false;
	var _ptrJustPressed:Bool = false;
	var _activeTouchID:Int = -1;
	var _holdKey:Int = -1;
	var _holdFired:Bool = false;
	var _holdTime:Float = 0;
	var _holdNext:Float = REPEAT_DELAY;
	var _holdInterval:Float = REPEAT_INTERVAL;

	public function new(cam:FlxCamera)
	{
		super();

		_cam = (cam != null) ? cam : FlxG.camera;
		_keys = [];
		_ptrPoint = FlxPoint.get();
		if (_cam != null)
			cameras = [_cam];

		visible = false;
		active = false;
	}

	/**
	 * Opens the sheet on `initial`, replacing the buffer, and shows it. `multiline` decides whether
	 * the enter key inserts a newline or only reports itself.
	 */
	public function open(initial:String, multiline:Bool):Void
	{
		BlockLayout.ensure();

		_text = (initial != null) ? initial : '';
		_multiline = multiline;
		_shift = false;
		releaseHold();
		_activeTouchID = -1;
		_ptrPressed = false;
		_ptrJustPressed = false;
		_caretBlink = 0;
		_open = true;
		visible = true;
		active = true;
		_layoutDirty = true;

		rebuildIfNeeded();
		refreshKeyVisuals();
		refreshPreview();
	}

	/**
	 * Hides the sheet and stops it from updating. The buffer, the layout and the shift state are
	 * kept, so reopening continues where this left off. Does not fire `onClose`.
	 */
	public function close():Void
	{
		_open = false;
		releaseHold();
		_activeTouchID = -1;
		_ptrPressed = false;
		_ptrJustPressed = false;
		visible = false;
		active = false;
	}

	public function isOpen():Bool
	{
		return _open;
	}

	/** Replaces the buffer, e.g. when the caller edited the value itself. */
	public function setText(t:String):Void
	{
		_text = (t != null) ? t : '';
		refreshPreview();
	}

	public function getText():String
	{
		return _text;
	}

	/**
	 * Switches to `"letters"`, `"numbers"`, `"symbols"` or `"code"` (the switcher button labels
	 * `ABC` / `123` / `#+=` are accepted too). Unknown names are ignored.
	 */
	public function setLayout(name:String):Void
	{
		var canonical:String = canonicalLayout(name);
		if (canonical == null || canonical == _layout)
			return;

		_layout = canonical;
		_layoutDirty = true;
		if (_open)
		{
			rebuildIfNeeded();
			refreshKeyVisuals();
		}
	}

	/** Height of the sheet in the camera's screen space, 0 while it has never been laid out. */
	public function getSheetHeight():Float
	{
		if (_sheetH > 0)
			return _sheetH;

		var base:Float = (FlxG.height > 0) ? FlxG.height : MIN_HEIGHT;
		return Math.max(MIN_HEIGHT, base * HEIGHT_RATIO);
	}

	override public function update(elapsed:Float):Void
	{
		if (!_open)
			return;

		BlockLayout.ensure();

		super.update(elapsed);

		rebuildIfNeeded();
		pollPointer();
		handlePointer(elapsed);
		// A press may have switched the layout, which rebuilds every key.
		rebuildIfNeeded();
		refreshKeyVisuals();
		updateCaret(elapsed);
	}

	override public function draw():Void
	{
		if (!_open)
			return;

		super.draw();
	}

	override public function destroy():Void
	{
		_keys = null;
		_ptrPoint = FlxDestroyUtil.put(_ptrPoint);
		super.destroy();
	}

	// --- Pointer input -------------------------------------------------------------------------

	function pollPointer():Void
	{
		_ptrPressed = false;
		_ptrJustPressed = false;

		if (pollTouch())
			return;

		if (_cam == null || FlxG.mouse == null)
			return;

		var pos:FlxPoint = FlxG.mouse.getScreenPosition(_cam, _ptrPoint);
		_ptrX = pos.x;
		_ptrY = pos.y;
		_ptrPressed = FlxG.mouse.pressed;
		_ptrJustPressed = FlxG.mouse.justPressed;
	}

	/**
	 * Reads the touch that owns the keyboard and claims the first new one. Returns true whenever the
	 * touch screen has anything to do with this frame, so the (synthesized) mouse never handles a
	 * finger a second time.
	 */
	function pollTouch():Bool
	{
		#if FLX_TOUCH
		if (FlxG.touches == null || FlxG.touches.list == null)
			return false;

		var list:Array<FlxTouch> = FlxG.touches.list;

		if (_activeTouchID >= 0)
		{
			for (touch in list)
			{
				if (touch == null || touch.touchPointID != _activeTouchID)
					continue;

				var pos:FlxPoint = touch.getScreenPosition(_cam, _ptrPoint);
				_ptrX = pos.x;
				_ptrY = pos.y;
				_ptrPressed = touch.pressed;

				if (!touch.pressed)
					_activeTouchID = -1;

				return true;
			}

			// The touch we were tracking is gone without a release: cancel, pointing nowhere.
			_activeTouchID = -1;
			_ptrX = -1;
			_ptrY = -1;
			return true;
		}

		for (touch in list)
		{
			if (touch == null || !touch.justPressed)
				continue;

			_activeTouchID = touch.touchPointID;
			var pos:FlxPoint = touch.getScreenPosition(_cam, _ptrPoint);
			_ptrX = pos.x;
			_ptrY = pos.y;
			_ptrPressed = true;
			_ptrJustPressed = true;
			return true;
		}

		// A finger is on the screen but it is not ours: the sheet still owns the pointer.
		return list.length > 0;
		#end

		return false;
	}

	/**
	 * Turns the pointer into key presses. A key fires when the finger lifts off the same key it went
	 * down on (dragging off cancels it); the delete key fires on press so that it can repeat.
	 */
	function handlePointer(elapsed:Float):Void
	{
		if (_holdKey >= 0)
		{
			handleHeldKey(elapsed);
			return;
		}

		if (!_ptrJustPressed)
			return;

		var index:Int = keyIndexAt(_ptrX, _ptrY);
		if (index < 0 || index >= _keys.length)
			return;

		_holdKey = index;
		_holdFired = false;
		_holdTime = 0;
		_holdNext = REPEAT_DELAY;
		_holdInterval = REPEAT_INTERVAL;

		if (_keys[index].spec.action == ACT_BACKSPACE)
		{
			_holdFired = true;
			activateKey(index);
		}
	}

	function handleHeldKey(elapsed:Float):Void
	{
		var index:Int = _holdKey;

		if (!_ptrPressed)
		{
			var landed:Int = keyIndexAt(_ptrX, _ptrY);
			var fired:Bool = _holdFired;
			releaseHold();

			if (_open && landed == index && !fired)
				activateKey(index);

			return;
		}

		if (keyIndexAt(_ptrX, _ptrY) != index)
		{
			releaseHold();
			return;
		}

		if (!_holdFired || index >= _keys.length)
			return;

		_holdTime += elapsed;
		if (_holdTime < _holdNext)
			return;

		_holdTime = 0;
		_holdInterval = Math.max(REPEAT_MIN_INTERVAL, _holdInterval * 0.85);
		_holdNext = _holdInterval;
		activateKey(index);
	}

	/** Forgets the held key without firing anything. */
	function releaseHold():Void
	{
		_holdKey = -1;
		_holdFired = false;
		_holdTime = 0;
		_holdNext = REPEAT_DELAY;
		_holdInterval = REPEAT_INTERVAL;
	}

	function keyIndexAt(x:Float, y:Float):Int
	{
		for (i in 0..._keys.length)
		{
			var key:KeyboardKey = _keys[i];
			if (key == null)
				continue;

			if (x >= key.xPos && x <= key.xPos + key.width && y >= key.yPos && y <= key.yPos + key.height)
				return i;
		}

		return -1;
	}

	function activateKey(index:Int):Void
	{
		if (index < 0 || index >= _keys.length)
			return;

		var key:KeyboardKey = _keys[index];
		if (key == null)
			return;

		var spec:KeySpec = key.spec;

		switch (spec.action)
		{
			case ACT_CHAR:
				var character:String = effectiveChar(spec.value);
				insertText(character);
				playClick('scrollMenu', 0.35);
				fireKey(character);
			case ACT_SPACE:
				insertText(' ');
				playClick('scrollMenu', 0.35);
				fireKey('space');
			case ACT_TAB:
				insertText(TAB_SPACES);
				playClick('scrollMenu', 0.35);
				fireKey('tab');
			case ACT_BACKSPACE:
				if (_text.length > 0)
					_text = _text.substr(0, _text.length - 1);
				refreshPreview();
				playClick('scrollMenu', 0.35);
				fireKey('backspace');
			case ACT_ENTER:
				if (_multiline)
					insertText('\n');
				playClick('confirmMenu', 0.4);
				fireKey('enter');
			case ACT_SHIFT:
				_shift = !_shift;
				playClick('scrollMenu', 0.35);
				fireKey('shift');
			case ACT_CLEAR:
				_text = '';
				refreshPreview();
				playClick('cancelMenu', 0.35);
				fireKey('clear');
			case ACT_CLOSE:
				playClick('cancelMenu', 0.4);
				if (onClose != null)
					onClose();
				close();
			case ACT_LAYOUT:
				playClick('scrollMenu', 0.35);
				setLayout(spec.value);
		}
	}

	function insertText(value:String):Void
	{
		_text += value;
		refreshPreview();
	}

	/** Turns a key's character into what it inserts right now: letters follow the shift state. */
	function effectiveChar(value:String):String
	{
		if (value == null || value.length != 1)
			return value;

		var code:Int = value.charCodeAt(0);
		if (code >= 97 && code <= 122)
			return _shift ? value.toUpperCase() : value;

		return value;
	}

	function fireKey(name:String):Void
	{
		if (onKey != null)
			onKey(name);
	}

	function playClick(key:String, volume:Float):Void
	{
		if (FlxG.sound == null)
			return;

		try
		{
			FlxG.sound.play(Paths.sound(key), volume);
		}
		catch (e:Dynamic)
		{
			// A missing click sound must never break a key press.
		}
	}

	// --- Drawing -------------------------------------------------------------------------------

	function refreshKeyVisuals():Void
	{
		for (i in 0..._keys.length)
		{
			var key:KeyboardKey = _keys[i];
			if (key == null)
				continue;

			var spec:KeySpec = key.spec;
			var label:String = (spec.action == ACT_CHAR) ? effectiveChar(spec.value) : keyLabel(spec);
			if (key.label.text != label)
			{
				key.label.text = label;
				key.label.updateHitbox();
			}

			key.label.y = key.yPos + (key.height - key.label.height) * 0.5;
			key.label.color = (spec.tint != 0) ? spec.tint : COLOR_KEY_TEXT;

			var held:Bool = (i == _holdKey);
			var active:Bool = (spec.action == ACT_SHIFT && _shift) || (spec.action == ACT_LAYOUT && spec.value == _layout);
			key.bg.color = (held || active) ? COLOR_ACCENT : COLOR_KEY;
			key.frame.color = (held || active) ? COLOR_KEY_TEXT : COLOR_BORDER;

			var shrink:Float = held ? PRESSED_SCALE : 1;
			key.bg.scale.set(shrink, shrink);
			key.frame.scale.set(shrink, shrink);
		}
	}

	/**
	 * Draws the text being typed: the last line of the buffer, scrolled so the caret (the end of the
	 * text, the keyboard only ever appends) stays visible, plus the line and character count.
	 */
	function refreshPreview():Void
	{
		if (_preview == null)
			return;

		var parts:Array<String> = _text.split('\n');
		var line:Int = parts.length;
		var source:String = parts[parts.length - 1];

		if (_count != null)
			_count.text = _multiline ? ('L' + line + ' ' + _text.length) : Std.string(_text.length);

		var cell:Float = (_cellW > 0) ? _cellW : BlockLayout.font('body') * CHAR_RATIO;
		var maxChars:Int = Std.int(_previewFieldW / cell);
		if (maxChars < 4)
			maxChars = 4;

		var shown:String = source;
		if (shown.length > maxChars)
			shown = '...' + shown.substr(shown.length - (maxChars - 3));

		if (shown.length == 0)
		{
			_preview.text = _multiline ? 'type Lua here' : 'type here';
			_preview.color = COLOR_HINT;
		}
		else
		{
			_preview.text = shown;
			_preview.color = COLOR_KEY_TEXT;
		}

		if (_caret != null)
			_caret.x = _previewTextX + Math.min(shown.length * cell, _previewFieldW);
	}

	function updateCaret(elapsed:Float):Void
	{
		if (_caret == null)
			return;

		_caretBlink += elapsed;
		if (_caretBlink > 10)
			_caretBlink -= 10;

		_caret.visible = (_text.length > 0) && ((_caretBlink % 1) < 0.6);
	}

	// --- Layout --------------------------------------------------------------------------------

	function rebuildIfNeeded():Void
	{
		var viewW:Float = viewWidth();
		var viewH:Float = viewHeight();

		if (!_layoutDirty && _keys.length > 0 && Math.abs(viewW - _builtViewW) < 0.5 && Math.abs(viewH - _builtViewH) < 0.5
			&& _builtScale == BlockLayout.scale && _builtPortrait == BlockLayout.portrait)
			return;

		rebuildLayout(viewW, viewH);
	}

	function rebuildLayout(viewW:Float, viewH:Float):Void
	{
		clearLayout();

		_builtViewW = viewW;
		_builtViewH = viewH;
		_builtScale = BlockLayout.scale;
		_builtPortrait = BlockLayout.portrait;
		_layoutDirty = false;
		_sheetH = 0;
		_cellW = 0;

		var pad:Float = Math.max(6, BlockLayout.spacing('tight') * 1.5);
		var floorKey:Float = Math.max(BlockLayout.touchSize(), MIN_KEY_HEIGHT);
		var idealKey:Float = floorKey * (BlockLayout.portrait ? 1.12 : 1);
		var gap:Float = FlxMath.bound(idealKey * 0.16, 4, BlockLayout.spacing('loose'));
		var innerW:Float = Math.max(64, viewW - pad * 2);

		// The Hide button is inset into the strip, so the strip has to be slightly taller than a finger.
		var previewH:Float = Math.max(BlockLayout.touchSize() + 4, 34 * BlockLayout.scale);
		var switchH:Float = Math.max(BlockLayout.touchSize(), 40 * BlockLayout.scale);
		var hideW:Float = Math.max(BlockLayout.touchSize() * 1.3, 58 * BlockLayout.scale);
		var overhead:Float = pad * 2 + previewH + gap + switchH + gap;

		// Rows: portrait aims for fewer, fatter keys, landscape for the wide rows the layouts are
		// designed with. A row that does not fit is reflowed, never clipped.
		var limit:Int = columnLimit(innerW, gap);
		var columns:Int = softColumns(innerW, gap, limit);
		var rows:Array<Array<KeySpec>> = buildRows(_layout, columns);
		var cap:Float = sheetCap(viewH);

		var guard:Int = 0;
		while (rows.length > 0 && columns < limit && contentHeight(overhead, rows.length, idealKey, gap) > cap && guard < 12)
		{
			guard++;
			columns++;
			rows = buildRows(_layout, columns);
		}

		if (rows.length <= 0)
			return;

		var rowCount:Int = rows.length;
		var rowH:Float = idealKey;
		if (contentHeight(overhead, rowCount, rowH, gap) > cap)
		{
			rowH = (cap - overhead - (rowCount - 1) * gap) / rowCount;
			if (rowH < floorKey)
				rowH = floorKey; // One finger per key beats the cap; the workspace still keeps a third.
			if (rowH > idealKey)
				rowH = idealKey;
		}

		var sheetH:Float = contentHeight(overhead, rowCount, rowH, gap);
		var ceiling:Float = viewH * SHEET_CEILING_RATIO;
		if (sheetH > ceiling)
		{
			rowH = Math.max(16, (ceiling - overhead - (rowCount - 1) * gap) / rowCount);
			sheetH = Math.min(ceiling, contentHeight(overhead, rowCount, rowH, gap));
			if (sheetH > viewH)
				sheetH = viewH;
		}

		if (sheetH < 1)
			sheetH = 1;

		var sheetY:Float = Math.max(0, viewH - sheetH);
		_sheetH = sheetH;

		var contentW:Float = rowContentWidth(innerW, columns, gap);
		var rowX:Float = Math.max(pad, (viewW - contentW) * 0.5);
		var y:Float = sheetY + pad;

		_sheet = makeRect(0, sheetY, viewW, sheetH, COLOR_SHEET);
		var ruleH:Float = Math.max(2, 3 * BlockLayout.scale);
		_accent = makeRect(0, sheetY, viewW, ruleH, COLOR_ACCENT);
		makeRect(0, sheetY + ruleH, viewW, 1, COLOR_BORDER);

		buildPreviewStrip(rowX, y, contentW, previewH, hideW, gap);
		y += previewH + gap;

		var switchW:Float = Math.min(contentW, 560 * BlockLayout.scale);
		buildRow(switcherRow(), Math.max(pad, (viewW - switchW) * 0.5), y, switchW, switchH, gap);
		y += switchH + gap;

		for (row in rows)
		{
			buildRow(row, rowX, y, contentW, rowH, gap);
			y += rowH + gap;
		}

		refreshKeyVisuals();
		refreshPreview();
	}

	/** Preview strip: the text (and caret), the character count and the Hide button. */
	function buildPreviewStrip(x:Float, y:Float, w:Float, h:Float, hideW:Float, gap:Float):Void
	{
		var radius:Float = Math.min(h * 0.28, 10 * BlockLayout.scale);
		_previewBg = makeRoundRect(x, y, w, h, radius, COLOR_PREVIEW);
		_previewFrame = makeRoundFrame(x, y, w, h, radius, COLOR_BORDER);

		var countW:Float = (_multiline ? 96 : 62) * BlockLayout.scale;
		var countX:Float = x + w - hideW - 2 - gap - countW;
		_count = new FlxText(countX, y, Math.max(1, countW), '', BlockLayout.font('small'));
		_count.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('small'), COLOR_KEY_TEXT, RIGHT);
		_count.wordWrap = false;
		_count.scrollFactor.set(0, 0);
		_count.updateHitbox();
		_count.y = y + (h - _count.height) * 0.5;
		add(_count);

		addKey(spec('HIDE', ACT_CLOSE, '', 1), x + w - hideW - 2, y + 2, hideW, Math.max(1, h - 4));

		var inner:Float = Math.max(3, BlockLayout.spacing('tight'));
		_previewTextX = x + inner + 2;
		_previewFieldW = Math.max(24, countX - gap - _previewTextX);

		var size:Int = BlockLayout.font('body');
		_preview = new FlxText(_previewTextX, y, _previewFieldW, '', size);
		_preview.setFormat(Paths.font('vcr.ttf'), size, COLOR_KEY_TEXT, LEFT);
		_preview.wordWrap = false;
		_preview.scrollFactor.set(0, 0);
		_preview.updateHitbox();
		_preview.y = y + (h - _preview.height) * 0.5;
		add(_preview);

		_cellW = measureCell(size);

		var caretH:Float = Math.max(6, h * 0.56);
		_caret = makeRect(_previewTextX, y + (h - caretH) * 0.5, Math.max(2, 2 * BlockLayout.scale), caretH, COLOR_ACCENT);
	}

	/** `vcr.ttf` is monospaced, so one measured sample gives the width of every character. */
	function measureCell(size:Int):Float
	{
		var probe:FlxText = new FlxText(0, 0, 0, CELL_SAMPLE, size);
		probe.setFormat(Paths.font('vcr.ttf'), size, COLOR_KEY_TEXT, LEFT);
		probe.wordWrap = false;

		var measured:Float = 0;
		if (probe.textField != null)
			measured = probe.textField.textWidth;

		probe.destroy();

		if (measured > 0)
			return measured / CELL_SAMPLE.length;

		return size * CHAR_RATIO;
	}

	function clearLayout():Void
	{
		for (key in _keys)
		{
			if (key == null)
				continue;

			dropSprite(key.bg);
			dropSprite(key.frame);
			dropSprite(key.label);
		}

		_keys = [];
		releaseHold();

		dropSprite(_sheet);
		dropSprite(_accent);
		dropSprite(_previewBg);
		dropSprite(_previewFrame);
		dropSprite(_preview);
		dropSprite(_count);
		dropSprite(_caret);

		_sheet = null;
		_accent = null;
		_previewBg = null;
		_previewFrame = null;
		_preview = null;
		_count = null;
		_caret = null;
	}

	function dropSprite(sprite:FlxSprite):Void
	{
		if (sprite == null)
			return;

		remove(sprite, true);
		sprite.destroy();
	}

	/** Builds the key rows of `layout`, reflowed so a row never holds more than `columns` keys. */
	function buildRows(layout:String, columns:Int):Array<Array<KeySpec>>
	{
		var designed:Array<Array<KeySpec>> = [];

		switch (layout)
		{
			case LAYOUT_NUMBERS:
				designed.push(charRow('1234567890'));
				designed.push(charRow('-/:;()$&@"'));
				designed.push(charRow(".,?!'#%*+="));
			case LAYOUT_SYMBOLS:
				designed.push(charRow('[]{}<>/\\'));
				designed.push(charRow('^`~_|$&#'));
				designed.push(charRow("()\"'.,:;"));
			case LAYOUT_CODE:
				// Every Lua character the layouts above leave out; the rows carry the four-space TAB.
				designed.push(charRow("()[]{}=\"'"));
				designed.push(charRow('.,:;<>+-'));
				designed.push(charRow("*/%#~$_"));
			default:
				designed.push(charRow('qwertyuiop'));
				designed.push(charRow('asdfghjkl'));
				designed.push(charRow('zxcvbnm'));
		}

		var rows:Array<Array<KeySpec>> = [];
		for (row in designed)
		{
			for (chunk in chunkRow(row, columns))
				rows.push(chunk);
		}

		// The function row is the one row that is never reflowed: shift / space / del / enter stay put.
		rows.push(functionRow(layout));
		return rows;
	}

	/** Splits an over-long row into evenly sized chunks, so a reflowed row never ends in a stray key. */
	static function chunkRow(row:Array<KeySpec>, columns:Int):Array<Array<KeySpec>>
	{
		var chunks:Array<Array<KeySpec>> = [];
		if (row == null || row.length <= columns)
		{
			chunks.push(row);
			return chunks;
		}

		var chunkCount:Int = Math.ceil(row.length / columns);
		var base:Int = Std.int(row.length / chunkCount);
		var longer:Int = row.length - base * chunkCount;

		var index:Int = 0;
		for (i in 0...chunkCount)
		{
			var size:Int = base + ((i < longer) ? 1 : 0);
			chunks.push(row.slice(index, index + size));
			index += size;
		}

		return chunks;
	}

	/** How many keys a row may hold on a view this wide before a key gets narrower than a finger. */
	function columnLimit(innerW:Float, gap:Float):Int
	{
		var minKeyW:Float = Math.max(38, BlockLayout.touchSize() * 0.9);
		var columns:Int = Std.int((innerW + gap) / (minKeyW + gap));

		return Std.int(FlxMath.bound(columns, MIN_COLUMNS, MAX_COLUMNS));
	}

	/**
	 * Keys per row the sheet aims for: upright screens want fewer, fatter keys - a thumb keyboard -
	 * while landscape keeps the wide rows the layouts are designed with.
	 */
	function softColumns(innerW:Float, gap:Float, limit:Int):Int
	{
		var target:Float = (BlockLayout.portrait ? 84 : 66) * BlockLayout.scale;
		var columns:Int = Std.int((innerW + gap) / (target + gap));

		return Std.int(FlxMath.bound(columns, MIN_COLUMNS, limit));
	}

	/** Widest a row may spread: a very wide view would otherwise stretch ten keys across the screen. */
	function rowContentWidth(innerW:Float, columns:Int, gap:Float):Float
	{
		var maxKeyW:Float = Math.max(120 * BlockLayout.scale, innerW / 12);
		var wanted:Float = columns * maxKeyW + (columns - 1) * gap;

		return Math.min(innerW, wanted);
	}

	static function contentHeight(overhead:Float, rowCount:Int, rowH:Float, gap:Float):Float
	{
		return overhead + rowCount * rowH + (rowCount - 1) * gap;
	}

	/** Where the sheet may reach, in this camera's screen space: the BlockLayout cap, unit-scaled. */
	function sheetCap(viewH:Float):Float
	{
		var unit:Float = (BlockLayout.height > 0) ? viewH / BlockLayout.height : 1;
		var cap:Float = Math.min(BlockLayout.height * 0.45, 460 * BlockLayout.scale) * unit;

		return Math.max(MIN_HEIGHT * unit, cap);
	}

	/** The layout switcher: the active layout is filled with the accent colour. */
	function switcherRow():Array<KeySpec>
	{
		return [
			layoutKey(LAYOUT_LETTERS, 'ABC'),
			layoutKey(LAYOUT_NUMBERS, '123'),
			layoutKey(LAYOUT_SYMBOLS, '#+='),
			layoutKey(LAYOUT_CODE, 'code'),
			spec('CLR', ACT_CLEAR, '', 1, COLOR_DANGER)
		];
	}

	/** The bottom row: shift reports its own state through its label, TAB only exists for Lua. */
	function functionRow(layout:String):Array<KeySpec>
	{
		var row:Array<KeySpec> = [spec('abc', ACT_SHIFT, '', 1.5)];

		if (layout == LAYOUT_CODE)
			row.push(spec('TAB', ACT_TAB, '', 1.3));

		row.push(spec('SPACE', ACT_SPACE, ' ', (layout == LAYOUT_CODE) ? 2.2 : 3));
		row.push(spec('DEL', ACT_BACKSPACE, '', 1.5));
		row.push(spec('ENTER', ACT_ENTER, '', 1.5));

		return row;
	}

	static function spec(label:String, action:Int, value:String, flex:Float = 1, tint:Int = 0):KeySpec
	{
		return {
			label: label,
			action: action,
			value: value,
			flex: flex,
			tint: tint
		};
	}

	static function charKey(character:String):KeySpec
	{
		return spec(character, ACT_CHAR, character, 1);
	}

	static function charRow(characters:String):Array<KeySpec>
	{
		var row:Array<KeySpec> = [];
		for (i in 0...characters.length)
			row.push(charKey(characters.charAt(i)));

		return row;
	}

	static function layoutKey(layout:String, label:String):KeySpec
	{
		return spec(label, ACT_LAYOUT, layout, 1);
	}

	/** Lays `specs` out over `w`, giving every key `flex` shares of it. */
	function buildRow(specs:Array<KeySpec>, x:Float, y:Float, w:Float, h:Float, gap:Float):Void
	{
		if (specs == null || specs.length == 0)
			return;

		var sumFlex:Float = 0;
		for (item in specs)
			sumFlex += Math.max(0.1, item.flex);
		if (sumFlex <= 0)
			sumFlex = specs.length;

		var unitW:Float = (w - gap * (specs.length - 1)) / sumFlex;
		if (unitW < 1)
			unitW = 1;

		var cursor:Float = x;
		for (item in specs)
		{
			var keyW:Float = unitW * Math.max(0.1, item.flex);
			addKey(item, cursor, y, keyW, h);
			cursor += keyW + gap;
		}
	}

	function addKey(item:KeySpec, x:Float, y:Float, w:Float, h:Float):Void
	{
		if (w < 2 || h < 2)
			return;

		var radius:Float = Math.min(w, h) * 0.22;
		var bg:FlxSprite = makeRoundRect(x, y, w, h, radius, COLOR_KEY);
		var frame:FlxSprite = makeRoundFrame(x, y, w, h, radius, COLOR_BORDER);

		var size:Int = keyFontSize(item, w, h);
		var label:FlxText = new FlxText(x, y, Math.max(1, w), item.label, size);
		label.setFormat(Paths.font('vcr.ttf'), size, COLOR_KEY_TEXT, CENTER);
		label.wordWrap = false;
		label.scrollFactor.set(0, 0);
		label.updateHitbox();
		label.y = y + (h - label.height) * 0.5;
		add(label);

		_keys.push({
			spec: item,
			bg: bg,
			frame: frame,
			label: label,
			xPos: x,
			yPos: y,
			width: w,
			height: h
		});
	}

	/** Single characters get the body font, words the small one, both shrunk until they fit the key. */
	function keyFontSize(item:KeySpec, keyW:Float, keyH:Float):Int
	{
		var role:String = (item.label != null && item.label.length <= 1) ? 'body' : 'small';
		var wanted:Int = Std.int(Math.round(BlockLayout.font(role) * 0.95));
		var size:Int = (wanted < 9) ? 9 : wanted;

		if (item.label != null && item.label.length > 0)
		{
			var limit:Float = Math.max(12, keyW - 10 * BlockLayout.scale);
			var fitted:Int = Std.int(limit / (item.label.length * CHAR_RATIO));
			if (fitted < size)
				size = fitted;
		}

		var byHeight:Int = Std.int((keyH - 8 * BlockLayout.scale) / 1.25);
		if (byHeight < size)
			size = byHeight;

		return (size < 9) ? 9 : size;
	}

	/** Flat sprite of `w` x `h`; the sheet, the accent rule and the caret. */
	function makeRect(x:Float, y:Float, w:Float, h:Float, color:Int):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(Math.max(1, Math.ceil(w))), Std.int(Math.max(1, Math.ceil(h))), color);
		sprite.scrollFactor.set(0, 0);
		add(sprite);
		return sprite;
	}

	/** Rounded corner fill. The bitmap is white, so `color` tints it exactly. */
	function makeRoundRect(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Int):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite(x, y);
		sprite.loadGraphic(roundedBitmap(Std.int(Math.max(1, Math.ceil(w))), Std.int(Math.max(1, Math.ceil(h))), radius, FlxColor.WHITE));
		sprite.color = color;
		sprite.scrollFactor.set(0, 0);
		sprite.origin.set(sprite.width * 0.5, sprite.height * 0.5);
		add(sprite);
		return sprite;
	}

	/** The 1px outline of the same rounded rectangle, on its own sprite so it can take its own tint. */
	function makeRoundFrame(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Int):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite(x, y);
		sprite.loadGraphic(roundedFrameBitmap(Std.int(Math.max(1, Math.ceil(w))), Std.int(Math.max(1, Math.ceil(h))), radius, FlxColor.WHITE));
		sprite.color = color;
		sprite.scrollFactor.set(0, 0);
		sprite.origin.set(sprite.width * 0.5, sprite.height * 0.5);
		add(sprite);
		return sprite;
	}

	/**
	 * A rounded rectangle built row by row - no vector graphics, no assets, the same result on every
	 * target. Every pixel is either opaque or transparent, so tinting the sprite keeps crisp edges.
	 */
	static function roundedBitmap(w:Int, h:Int, radius:Float, color:Int):BitmapData
	{
		var bitmap:BitmapData = new BitmapData(w, h, true, 0x00000000);
		var r:Float = Math.min(radius, Math.min(w, h) * 0.5);

		for (row in 0...h)
		{
			var inset:Int = cornerInset(row, h, r);
			var span:Int = w - inset * 2;
			if (span <= 0)
				continue;

			bitmap.fillRect(new Rectangle(inset, row, span, 1), color);
		}

		return bitmap;
	}

	/** The same silhouette hollowed out, leaving the 1px outline behind. */
	static function roundedFrameBitmap(w:Int, h:Int, radius:Float, color:Int):BitmapData
	{
		var bitmap:BitmapData = roundedBitmap(w, h, radius, color);
		var r:Float = Math.min(radius, Math.min(w, h) * 0.5);

		for (row in 1...(h - 1))
		{
			var inset:Int = cornerInset(row, h, r);
			var span:Int = w - inset * 2 - 2;
			if (span <= 0)
				continue;

			bitmap.fillRect(new Rectangle(inset + 1, row, span, 1), 0x00000000);
		}

		return bitmap;
	}

	/** Horizontal inset of a rounded corner at `row`, in whole pixels. */
	static function cornerInset(row:Int, h:Int, r:Float):Int
	{
		var dy:Float = 0;
		if (row < r)
			dy = r - row - 0.5;
		else if (row >= h - r)
			dy = row - (h - r) + 0.5;
		else
			return 0;

		var dx:Float = r - Math.sqrt(Math.max(0, r * r - dy * dy));
		return Std.int(Math.round(dx));
	}

	// --- Helpers -------------------------------------------------------------------------------

	function viewWidth():Float
	{
		var width:Float = (_cam != null && _cam.width > 0) ? _cam.width : FlxG.width;
		return Math.max(1, width / cameraZoom());
	}

	function viewHeight():Float
	{
		var height:Float = (_cam != null && _cam.height > 0) ? _cam.height : FlxG.height;
		return Math.max(1, height / cameraZoom());
	}

	function cameraZoom():Float
	{
		return (_cam != null && _cam.zoom > 0.0001) ? _cam.zoom : 1;
	}

	function keyLabel(item:KeySpec):String
	{
		if (item.action == ACT_SHIFT)
			return _shift ? 'ABC' : 'abc';

		return item.label;
	}

	static function canonicalLayout(name:String):String
	{
		if (name == null)
			return null;

		switch (name.toLowerCase())
		{
			case LAYOUT_LETTERS, 'abc':
				return LAYOUT_LETTERS;
			case LAYOUT_NUMBERS, '123':
				return LAYOUT_NUMBERS;
			case LAYOUT_SYMBOLS, '#+=', 'symbol':
				return LAYOUT_SYMBOLS;
			case LAYOUT_CODE:
				return LAYOUT_CODE;
			default:
				return null;
		}
	}
}

/** One drawn key: its rectangle, its body, its outline and where it sits in the camera's screen space. */
private typedef KeyboardKey =
{
	var spec:KeySpec;
	var bg:FlxSprite;
	var frame:FlxSprite;
	var label:FlxText;
	var xPos:Float;
	var yPos:Float;
	var width:Float;
	var height:Float;
}

/** What a key does when it is pressed, straight out of the layout tables. */
private typedef KeySpec =
{
	var label:String;
	var action:Int;
	var value:String;
	var flex:Float;

	/** Label colour override, 0 for the default key text colour. */
	var tint:Int;
}
