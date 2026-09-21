package editors.blockcode;

import flixel.group.FlxGroup;

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
 * Shape: a sheet anchored to the bottom of `cam`'s view - a preview line of the current text, a
 * control row (the four layout switchers, clear, close) and the key rows of the active layout:
 * 6 to 10 keys per row depending on how wide the view is, and every key at least `MIN_KEY_HEIGHT`
 * logical pixels tall. The sheet is 40% of `FlxG.height` unless the rows need more room, and never
 * under 220px. Four layouts: `letters` (QWERTY), `numbers`, `symbols` and `code`, which carries the
 * punctuation and the four-space TAB key Lua wants.
 *
 * Everything lives in `cam`'s own screen space (`scrollFactor == 0`, group `cameras == [cam]`), so
 * the sheet stays glued to the bottom of that camera whatever the editor does to the scroll and
 * zoom behind it. Pointers are read from `FlxG.touches` first - only the first touch drives the
 * keyboard - and from `FlxG.mouse` as the desktop fallback. While closed the group is invisible,
 * inactive and its `update` returns before touching anything, so a tap meant for the editor is
 * never intercepted.
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

	/** Layout names `setLayout` accepts. */
	public static inline var LAYOUT_LETTERS:String = 'letters';

	public static inline var LAYOUT_NUMBERS:String = 'numbers';
	public static inline var LAYOUT_SYMBOLS:String = 'symbols';
	public static inline var LAYOUT_CODE:String = 'code';

	/** Smallest sheet height in logical pixels. */
	public static inline var MIN_HEIGHT:Float = 220;

	/** Sheet height as a fraction of `FlxG.height`, before the minimums are applied. */
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

	/** Fired after every key press with the key name: `A`..`Z`, `0`..`9`, `space`, `backspace`, `enter`, `tab`, `shift`, `clear` or `close`. */
	public var onKey:String->Void = null;

	/** Fired by the close key after `onKey('close')`, right before the sheet closes itself. */
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
	var _preview:FlxText = null;

	var _sheetH:Float = 0;
	var _builtViewW:Float = -1;
	var _builtViewH:Float = -1;
	var _layoutDirty:Bool = true;
	var _charWidth:Float = 0;

	var _ptrPoint:FlxPoint = null;
	var _ptrX:Float = 0;
	var _ptrY:Float = 0;
	var _ptrPressed:Bool = false;
	var _ptrJustPressed:Bool = false;
	var _ptrJustReleased:Bool = false;
	var _activeTouchID:Int = -1;
	var _pressedIndex:Int = -1;

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
		_text = (initial != null) ? initial : '';
		_multiline = multiline;
		_shift = false;
		_pressedIndex = -1;
		_activeTouchID = -1;
		_ptrPressed = false;
		_ptrJustPressed = false;
		_ptrJustReleased = false;
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
		_pressedIndex = -1;
		_activeTouchID = -1;
		_ptrPressed = false;
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
			rebuildIfNeeded();
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

		super.update(elapsed);

		rebuildIfNeeded();
		pollPointer();
		handlePointer();
		refreshKeyVisuals();
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
		_ptrJustReleased = false;
		_ptrX = 0;
		_ptrY = 0;

		if (pollTouch())
			return;

		if (FlxG.mouse == null)
			return;

		var pos = FlxG.mouse.getScreenPosition(_cam, _ptrPoint);
		_ptrX = pos.x;
		_ptrY = pos.y;
		_ptrPressed = FlxG.mouse.pressed;
		_ptrJustPressed = FlxG.mouse.justPressed;
		_ptrJustReleased = FlxG.mouse.justReleased;
	}

	/** Reads the touch that owns the keyboard, claiming the first new one. Returns false to fall back to the mouse. */
	function pollTouch():Bool
	{
		#if FLX_TOUCH
		if (FlxG.touches == null)
			return false;

		if (_activeTouchID >= 0)
		{
			for (touch in FlxG.touches.list)
			{
				if (touch == null || touch.touchPointID != _activeTouchID)
					continue;

				var pos = touch.getScreenPosition(_cam, _ptrPoint);
				_ptrX = pos.x;
				_ptrY = pos.y;
				_ptrPressed = touch.pressed;
				_ptrJustReleased = touch.justReleased;
				if (!_ptrPressed)
					_activeTouchID = -1;
				return true;
			}

			// The touch we were tracking is gone without a release.
			_activeTouchID = -1;
			return false;
		}

		for (touch in FlxG.touches.list)
		{
			if (touch == null || !touch.justPressed)
				continue;

			_activeTouchID = touch.touchPointID;
			var pos = touch.getScreenPosition(_cam, _ptrPoint);
			_ptrX = pos.x;
			_ptrY = pos.y;
			_ptrPressed = true;
			_ptrJustPressed = true;
			return true;
		}
		#end

		return false;
	}

	function handlePointer():Void
	{
		if (_ptrJustReleased)
			_pressedIndex = -1;

		if (_ptrJustPressed)
		{
			var index:Int = keyIndexAt(_ptrX, _ptrY);
			if (index >= 0)
			{
				_pressedIndex = index;
				activateKey(index);
			}
		}

		if (_pressedIndex >= 0 && (!_ptrPressed || keyIndexAt(_ptrX, _ptrY) != _pressedIndex))
			_pressedIndex = -1;
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

			var highlighted:Bool = (i == _pressedIndex);
			if (!highlighted)
				highlighted = (spec.action == ACT_SHIFT && _shift) || (spec.action == ACT_LAYOUT && spec.value == _layout);

			key.bg.color = highlighted ? COLOR_ACCENT : COLOR_KEY;
		}
	}

	function refreshPreview():Void
	{
		if (_preview == null)
			return;

		var flat:String = _text.split('\n').join(' ');
		_preview.text = flat;

		var field = _preview.textField;
		if (_charWidth <= 0 && field != null && flat.length > 0)
		{
			var measured:Float = field.textWidth;
			if (measured > 0)
				_charWidth = measured / flat.length;
		}

		var perChar:Float = (_charWidth > 0) ? _charWidth : 8;
		var maxChars:Int = Std.int(_preview.fieldWidth / perChar);
		if (maxChars < 5)
			maxChars = 5;

		if (flat.length > maxChars)
			_preview.text = '...' + flat.substr(flat.length - (maxChars - 3));
	}

	function rebuildIfNeeded():Void
	{
		var viewW:Float = viewWidth();
		var viewH:Float = viewHeight();

		if (!_layoutDirty && _keys.length > 0 && Math.abs(viewW - _builtViewW) < 0.5 && Math.abs(viewH - _builtViewH) < 0.5)
			return;

		rebuildLayout(viewW, viewH);
	}

	function rebuildLayout(viewW:Float, viewH:Float):Void
	{
		clearLayout();

		_builtViewW = viewW;
		_builtViewH = viewH;
		_layoutDirty = false;
		_sheetH = 0;
		_charWidth = 0;

		var rows:Array<Array<KeySpec>> = buildRows(_layout, columnsFor(viewW));
		var rowCount:Int = rows.length;
		if (rowCount <= 0)
			return;

		var pad:Float = Math.max(6, viewH * 0.012);
		var gap:Float = Math.max(4, viewW * 0.005);
		var previewH:Float = Math.max(28, Math.min(48, viewH * 0.05));
		var controlH:Float = Math.max(MIN_KEY_HEIGHT, Math.min(64, viewH * 0.062));
		var innerW:Float = viewW - pad * 2;
		if (innerW < 48)
			return;

		var baseHeight:Float = (FlxG.height > 0) ? FlxG.height : viewH;
		var needed:Float = pad * 2 + previewH + controlH + rowCount * MIN_KEY_HEIGHT + (rowCount + 1) * gap;
		var sheetH:Float = Math.max(MIN_HEIGHT, baseHeight * HEIGHT_RATIO);
		if (needed > sheetH)
			sheetH = needed;
		if (sheetH > viewH)
			sheetH = viewH;

		var sheetX:Float = 0;
		var sheetY:Float = Math.max(0, viewH - sheetH);
		_sheetH = sheetH;

		_sheet = makeRect(sheetX, sheetY, viewW, sheetH, COLOR_SHEET);
		_accent = makeRect(sheetX, sheetY, viewW, Math.max(2, viewH * 0.004), COLOR_ACCENT);

		var contentTop:Float = sheetY + pad;
		_previewBg = makeRect(sheetX + pad, contentTop, innerW, previewH, COLOR_PREVIEW);

		var previewSize:Int = Std.int(Math.max(12, Math.min(24, previewH * 0.62)));
		_preview = new FlxText(sheetX + pad + 6, contentTop, Math.max(1, innerW - 12), '', previewSize);
		_preview.setFormat(Paths.font('vcr.ttf'), previewSize, COLOR_KEY_TEXT, LEFT);
		_preview.wordWrap = false;
		_preview.scrollFactor.set(0, 0);
		_preview.updateHitbox();
		_preview.y = contentTop + Math.max(0, (previewH - _preview.height) * 0.5);
		add(_preview);

		var controlY:Float = contentTop + previewH + gap;
		buildRow(controlRow(), sheetX + pad, controlY, innerW, controlH, gap);

		var rowY:Float = controlY + controlH + gap;
		var rowH:Float = (sheetY + sheetH - pad - rowY) / rowCount - gap * (rowCount - 1) / rowCount;
		if (rowH < 1)
			rowH = 1;

		for (row in rows)
		{
			buildRow(row, sheetX + pad, rowY, innerW, rowH, gap);
			rowY += rowH + gap;
		}
	}

	function clearLayout():Void
	{
		for (key in _keys)
		{
			if (key == null)
				continue;

			remove(key.bg, true);
			remove(key.label, true);
			key.bg.destroy();
			key.label.destroy();
		}

		_keys = [];
		_pressedIndex = -1;

		if (_sheet != null)
		{
			remove(_sheet, true);
			_sheet.destroy();
			_sheet = null;
		}
		if (_accent != null)
		{
			remove(_accent, true);
			_accent.destroy();
			_accent = null;
		}
		if (_previewBg != null)
		{
			remove(_previewBg, true);
			_previewBg.destroy();
			_previewBg = null;
		}
		if (_preview != null)
		{
			remove(_preview, true);
			_preview.destroy();
			_preview = null;
		}
	}

	// --- Layout --------------------------------------------------------------------------------

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
				designed.push(charRow("[]{}<>/\\"));
				designed.push(charRow('^`~_|$&#'));
				designed.push(charRow("()\"'.,:;"));
			case LAYOUT_CODE:
				designed.push(charRow('()[]{}'));
				designed.push(charRow("=\"'.,:;"));
				designed.push(charRow('<>+-*/%'));
				designed.push([charKey('#'), charKey('~'), charKey("$"), charKey('_'), tabKey()]);
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
		rows.push(functionRow());
		return rows;
	}

	/** How many keys a row may hold on a view this wide: 10 normally, 6 on a very narrow one. */
	function columnsFor(viewW:Float):Int
	{
		var columns:Int = Std.int(viewW / 88);
		if (columns < 6)
			columns = 6;
		if (columns > 10)
			columns = 10;

		return columns;
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

	/** The layout switcher row: ABC / 123 / #+= / code, clear and close. */
	function controlRow():Array<KeySpec>
	{
		return [
			layoutKey(LAYOUT_LETTERS, 'ABC'),
			layoutKey(LAYOUT_NUMBERS, '123'),
			layoutKey(LAYOUT_SYMBOLS, '#+='),
			layoutKey(LAYOUT_CODE, 'code'),
			spec('CLR', ACT_CLEAR, '', 1),
			spec('X', ACT_CLOSE, '', 1)
		];
	}

	function functionRow():Array<KeySpec>
	{
		return [
			spec('shift', ACT_SHIFT, '', 1.4),
			spec('SPACE', ACT_SPACE, ' ', 3),
			spec('DEL', ACT_BACKSPACE, '', 1.4),
			spec('ENTER', ACT_ENTER, '', 1.4)
		];
	}

	static function spec(label:String, action:Int, value:String, flex:Float = 1):KeySpec
	{
		return {
			label: label,
			action: action,
			value: value,
			flex: flex
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

	static function tabKey():KeySpec
	{
		return spec('TAB', ACT_TAB, '', 1.5);
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
		var bg:FlxSprite = makeRect(x, y, w, h, FlxColor.WHITE);
		bg.color = COLOR_KEY;

		var size:Int = fitFontSize(item.label, w, Std.int(Math.max(10, Math.min(22, h * 0.34))));
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
			label: label,
			xPos: x,
			yPos: y,
			width: w,
			height: h
		});
	}

	function makeRect(x:Float, y:Float, w:Float, h:Float, color:Int):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(Math.max(1, Math.ceil(w))), Std.int(Math.max(1, Math.ceil(h))), color);
		sprite.scrollFactor.set(0, 0);
		add(sprite);
		return sprite;
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

	/** `vcr.ttf` is monospace, so the key width gives a usable estimate for a label that is too long. */
	function fitFontSize(label:String, keyW:Float, wanted:Int):Int
	{
		var size:Int = (wanted < 9) ? 9 : wanted;
		if (label == null || label.length == 0)
			return size;

		var limit:Float = keyW - 8;
		if (label.length * size * 0.62 > limit)
		{
			var shrunk:Int = Std.int(limit / (label.length * 0.62));
			size = (shrunk < 9) ? 9 : shrunk;
		}

		return size;
	}

	function keyLabel(item:KeySpec):String
	{
		if (item.action == ACT_SHIFT)
			return _shift ? 'SHIFT' : 'shift';

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

/** One drawn key: its rectangle, its label and where it sits in the camera's screen space. */
private typedef KeyboardKey =
{
	var spec:KeySpec;
	var bg:FlxSprite;
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
}
