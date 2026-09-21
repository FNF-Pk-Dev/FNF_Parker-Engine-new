package editors.blockcode;

import editors.blockcode.BlockTypes.BlockCodeEditorSettings;
import editors.blockcode.BlockTypes.ImportResult;
import flixel.group.FlxGroup;
import openfl.geom.Rectangle;

/**
 * The Lua side of the block-code editor substate: it shows the source the blocks generate, lets it
 * be typed and edited by hand on a phone or with a mouse, and hands the edited text back so the
 * substate can turn it into blocks again.
 *
 * Shape: a toolbar of actions (Apply / Revert / Copy / Snippet / Check / Lines / Close), a
 * full-height read-only-and-writable code view (line numbers in the gutter, a blinking caret on the
 * highlighted caret line, comments dimmed), and a footer with the character/line/warning counts plus
 * a preview of the import warnings. Scrolling is by wheel, by dragging the code area, or by touch;
 * no momentum, so a finger drag is the slow, precise way to move through 200 lines.
 *
 * Editing: there is no text cursor in this view - the engines below own the caret. Tapping the code
 * area opens the platform editor for the whole script, or, in "edit lines" mode, only for the tapped
 * line, which is far more workable on a phone. The platform editor is `BlockSoftKeyboard` (the real
 * IME) when the platform has one and the settings do not ask for the on-screen keyboard, and
 * `BlockVirtualKeyboard` in its `code` layout otherwise. Either way the view follows every keystroke
 * and the caret sits where the editing happens.
 *
 * Coordinates: everything is drawn in the camera's screen space (`scrollFactor == 0`) from this
 * panel's own origin, so `width`/`height` are the panel box and the caller places it by sizing it
 * that way - the panel does not offset its children. If the caller never assigns `cameras`, the
 * default camera is used for the whole panel (including the on-screen keyboard), and assigning a
 * camera afterwards moves every child with it.
 *
 * Integration: the substate owns the panel's lifetime. `open()` shows it with the current Lua and
 * the two callbacks, the Apply button calls `onApply(text)`, and `close()` hides it and calls
 * `onClosed()` once - whether it was the Close button, `close()` from the substate, or a state
 * switch that tore the panel down.
 */
class BlockCodePanel extends FlxGroup
{
	// --- Theme (same palette as the editor state and the on-screen keyboard) --------------------
	public static inline var COLOR_BG:Int = 0xFF1A1B26;
	public static inline var COLOR_CODE_BG:Int = 0xFF0F0F14;
	public static inline var COLOR_ACTIVE_LINE:Int = 0xFF16161E;
	public static inline var COLOR_GUTTER:Int = 0xFF16161E;
	public static inline var COLOR_TOOLBAR:Int = 0xFF16161E;
	public static inline var COLOR_FOOTER:Int = 0xFF16161E;
	public static inline var COLOR_SEPARATOR:Int = 0xFF414868;
	public static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_COMMENT:Int = 0xFF565F89;
	public static inline var COLOR_LINE_NUMBER:Int = 0xFF565F89;
	public static inline var COLOR_CARET:Int = 0xFFE0AF68;
	public static inline var COLOR_WARNING:Int = 0xFFE0AF68;
	public static inline var COLOR_BUTTON:Int = 0xFF2F3349;
	public static inline var COLOR_BUTTON_HOVER:Int = 0xFF3D59A1;
	public static inline var COLOR_BUTTON_ACTIVE:Int = 0xFF3D59A1;
	public static inline var COLOR_BUTTON_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_BUTTON_ACTIVE_TEXT:Int = 0xFFE0AF68;
	public static inline var COLOR_SCROLL_TRACK:Int = 0xFF16161E;
	public static inline var COLOR_SCROLL_THUMB:Int = 0xFF565F89;
	public static inline var COLOR_OVERLAY:Int = 0xCC0F0F14;

	// --- Metrics ---------------------------------------------------------------------------------

	/** Smallest interactive height in logical pixels: one finger. */
	public static inline var MIN_TOUCH_HEIGHT:Float = 44;

	/** Height of one drawn code row. */
	public static inline var ROW_HEIGHT:Float = 22;

	/** Size of the code font; `vcr.ttf` is (near) monospace, which is what the wrapping assumes. */
	public static inline var FONT_SIZE:Int = 16;

	public static inline var TOOLBAR_HEIGHT:Float = 50;
	public static inline var FOOTER_HEIGHT:Float = 52;
	public static inline var GUTTER_WIDTH:Float = 46;
	public static inline var CONTENT_PAD:Float = 6;
	public static inline var SCROLLBAR_WIDTH:Float = 8;
	public static inline var CARET_BLINK:Float = 0.5;

	/** How far a finger may travel before a press counts as a scroll instead of a tap. */
	public static inline var TAP_SLOP:Float = 8;

	/** What a tab expands to; the Lua generator indents with four spaces too. */
	public static inline var TAB_SPACES:String = '    ';

	/** Warnings previewed in the footer before the count alone has to do. */
	public static inline var MAX_WARNING_PREVIEW:Int = 2;

	/** How long a status message stays in the footer. */
	static inline var STATUS_TIME:Float = 3.5;

	// --- Geometry --------------------------------------------------------------------------------
	var _w:Float = 0;
	var _h:Float = 0;
	var _toolbarH:Float = 0;
	var _footerY:Float = 0;
	var _footerH:Float = 0;
	var _codeX:Float = 0;
	var _codeTop:Float = 0;
	var _codeW:Float = 0;
	var _codeH:Float = 0;
	var _charWidth:Float = 0;
	var _infoChars:Int = 40;
	var _warnChars:Int = 80;

	// --- Document --------------------------------------------------------------------------------
	var _text:String = '';
	var _original:String = '';
	var _lines:Array<String> = [];
	var _visual:Array<VisualRow> = [];
	var _lineCharStart:Array<Int> = [];
	var _lineStartIndex:Array<Int> = [];
	var _contentHeight:Float = 0;
	var _scrollY:Float = 0;
	var _maxScroll:Float = 0;
	var _warnings:Array<String> = [];

	// --- Caret / redraw flags ---------------------------------------------------------------------
	var _caretIndex:Int = 0;
	var _caretBlink:Float = 0;
	var _caretDirty:Bool = true;
	var _rowsDirty:Bool = true;

	// --- Panel state ------------------------------------------------------------------------------
	var _open:Bool = false;
	var _status:String = '';
	var _statusTimer:Float = 0;
	var _lineEditMode:Bool = false;
	var _editLine:Int = -1;
	var _ownNativeKeyboard:Bool = false;
	var _settings:BlockCodeEditorSettings = null;

	var _onApply:String->Void = null;
	var _onClosed:Void->Void = null;

	// --- Drawn objects ----------------------------------------------------------------------------
	var _bg:FlxSprite = null;
	var _codeBg:FlxSprite = null;
	var _activeLineBg:FlxSprite = null;
	var _gutter:FlxSprite = null;
	var _gutterSep:FlxSprite = null;
	var _caret:FlxSprite = null;
	var _scrollTrack:FlxSprite = null;
	var _scrollThumb:FlxSprite = null;
	var _toolbarBg:FlxSprite = null;
	var _footerBg:FlxSprite = null;

	var _rowTexts:Array<FlxText> = [];
	var _gutterTexts:Array<FlxText> = [];
	var _footerInfo:FlxText = null;
	var _footerWarn:FlxText = null;

	var _buttons:Array<PanelButton> = [];
	var _linesButton:PanelButton = null;

	var _snippetSprites:Array<FlxSprite> = [];
	var _snippetButtons:Array<PanelButton> = [];
	var _snippetRect:Rectangle = null;
	var _snippetOpen:Bool = false;

	var _virtual:BlockVirtualKeyboard = null;

	// --- Pointer ----------------------------------------------------------------------------------
	var _ptrPoint:FlxPoint = null;
	var _ptrX:Float = 0;
	var _ptrY:Float = 0;
	var _ptrPressed:Bool = false;
	var _ptrJustPressed:Bool = false;
	var _ptrJustReleased:Bool = false;
	var _ptrFromTouch:Bool = false;
	var _activeTouchID:Int = -1;
	var _pressedButton:PanelButton = null;
	var _pressedSnippet:PanelButton = null;
	var _dragActive:Bool = false;
	var _dragMoved:Bool = false;
	var _dragStartY:Float = 0;
	var _dragStartScroll:Float = 0;

	public function new(width:Float, height:Float)
	{
		super();

		_w = (width > 0) ? width : ((FlxG.width > 0) ? FlxG.width : 1280);
		_h = (height > 0) ? height : ((FlxG.height > 0) ? FlxG.height : 720);

		_ptrPoint = FlxPoint.get();
		_lines = [''];
		_visual = [];
		_lineCharStart = [];
		_lineStartIndex = [];
		_warnings = [];

		computeLayout();
		_charWidth = measureCharWidth();

		buildBackground();
		buildRows();
		buildForeground();
		buildToolbar();
		buildFooter();
		buildSnippets();

		// A panel no caller gave a camera to still has to render somewhere sensible; assigning one
		// here propagates to every member added so far, and `add()` keeps new members in sync.
		if (FlxG.camera != null && (cameras == null || cameras.length == 0))
			cameras = [FlxG.camera];

		rebuildVisual();
		refreshFooter();
		positionCaret();

		visible = false;
		active = false;
	}

	// --- Public API -------------------------------------------------------------------------------

	/**
	 * Shows the panel with `text` in the code view.
	 *
	 * `onApply` is called with the current text by the Apply button; `onClosed` is called once when
	 * the panel goes away through `close()`. `text` also becomes the value the Revert button
	 * restores, so pass what the caller considers the current state of the script.
	 */
	public function open(text:String, onApply:String->Void, onClosed:Void->Void):Void
	{
		dismissKeyboards();

		_onApply = onApply;
		_onClosed = onClosed;
		_settings = null;
		_original = normalizeText(text);
		_text = _original;
		_warnings = [];
		_status = '';
		_statusTimer = 0;
		_editLine = -1;
		_pressedButton = null;
		_pressedSnippet = null;
		_dragActive = false;
		_dragMoved = false;
		_caretBlink = 0;
		_lineEditMode = BlockSoftKeyboard.isNativeAvailable();

		if (_linesButton != null)
			_linesButton.setActive(_lineEditMode);

		if (FlxG.camera != null && (cameras == null || cameras.length == 0))
			cameras = [FlxG.camera];

		_open = true;
		visible = true;
		active = true;

		hideSnippetList();
		rebuildVisual();
		_scrollY = 0;
		_caretIndex = _text.length;
		_caretDirty = true;
		refreshRows(true);
		refreshFooter();
		setStatus(_lineEditMode ? 'tap a line to edit it, drag to scroll' : 'tap the code to edit it, drag to scroll');
	}

	/**
	 * Hides the panel, dismisses the keyboard it opened and calls the `onClosed` callback of
	 * `open()` exactly once. Safe to call when the panel is already closed.
	 */
	public function close():Void
	{
		if (!_open)
			return;

		_open = false;
		dismissKeyboards();
		hideSnippetList();
		_pressedButton = null;
		_dragActive = false;
		visible = false;
		active = false;

		final notify:Void->Void = _onClosed;
		_onClosed = null;
		if (notify != null)
			notify();
	}

	/**
	 * Replaces the text in the view, e.g. when the blocks changed and the Lua was regenerated. Does
	 * not touch `onApply`, does not fire `onClosed`, and does not change what Revert restores.
	 */
	public function setText(t:String):Void
	{
		applyEditedText(t, -1);
	}

	/** The text as it stands right now, edits included. */
	public function getText():String
	{
		return _text;
	}

	public function isOpen():Bool
	{
		return _open;
	}

	/** Warnings of the last syntax check, empty when the script was clean or never checked. */
	public function getWarnings():Array<String>
	{
		return _warnings.copy();
	}

	override public function update(elapsed:Float):Void
	{
		if (!_open)
			return;

		super.update(elapsed);
		pollPointer();

		if (_snippetOpen)
		{
			if (FlxG.keys.justPressed.ESCAPE)
			{
				playSound('cancelMenu');
				hideSnippetList();
				resetPointer();
			}
			else
			{
				handleSnippetPointer();
			}
		}
		else if (keyboardOpen())
		{
			// The platform editor or the on-screen sheet owns the screen while it is up; the panel
			// only keeps painting the text that is being typed into it.
			resetPointer();
		}
		else
		{
			handleWheel();
			handlePointerInteraction();
			updateButtonStates();
		}

		if (_statusTimer > 0)
		{
			_statusTimer -= elapsed;
			if (_statusTimer <= 0)
			{
				_statusTimer = 0;
				refreshFooter();
			}
		}

		if (_rowsDirty)
			refreshRows();

		if (_caretDirty)
			positionCaret();

		_caretBlink += elapsed;
		if (_caret != null)
			_caret.visible = ((_caretBlink % (CARET_BLINK * 2)) < CARET_BLINK);

		updateScrollbar();
	}

	override public function destroy():Void
	{
		if (_ownNativeKeyboard)
		{
			_ownNativeKeyboard = false;
			BlockSoftKeyboard.close();
		}

		_buttons = null;
		_snippetButtons = null;
		_rowTexts = null;
		_gutterTexts = null;
		_visual = null;
		_warnings = null;
		_onApply = null;
		_onClosed = null;
		_virtual = null;
		_ptrPoint = FlxDestroyUtil.put(_ptrPoint);

		super.destroy();
	}

	// --- Layout -----------------------------------------------------------------------------------

	/** Splits `_w` x `_h` into toolbar, code view and footer, never leaving the code view at zero. */
	function computeLayout():Void
	{
		_toolbarH = Math.min(TOOLBAR_HEIGHT, Math.max(MIN_TOUCH_HEIGHT + 4, _h * 0.2));
		_footerH = Math.min(FOOTER_HEIGHT, Math.max(34, _h * 0.18));
		_footerY = _h - _footerH;
		_codeTop = _toolbarH;
		_codeH = Math.max(40, _footerY - _codeTop);
		_codeX = GUTTER_WIDTH + CONTENT_PAD;
		_codeW = Math.max(60, _w - _codeX - SCROLLBAR_WIDTH - CONTENT_PAD);
	}

	function buildBackground():Void
	{
		_bg = makeRect(0, 0, _w, _h, COLOR_BG);
		_codeBg = makeRect(0, _codeTop, _w, _codeH, COLOR_CODE_BG);
		_activeLineBg = makeRect(_codeX, _codeTop, _codeW, _codeH, COLOR_ACTIVE_LINE);
		_gutter = makeRect(0, _codeTop, GUTTER_WIDTH, _codeH, COLOR_GUTTER);
		_gutterSep = makeRect(GUTTER_WIDTH, _codeTop, 1, _codeH, COLOR_SEPARATOR);
	}

	/** One reusable `FlxText` per visible row plus one, so scrolling never allocates. */
	function buildRows():Void
	{
		_rowTexts = [];
		_gutterTexts = [];

		var count:Int = Std.int(Math.ceil(_codeH / ROW_HEIGHT)) + 1;
		if (count < 1)
			count = 1;

		for (i in 0...count)
		{
			var row:FlxText = new FlxText(_codeX, _codeTop, _codeW, '', FONT_SIZE);
			applyFont(row, FONT_SIZE, COLOR_TEXT, LEFT);
			row.wordWrap = false;
			row.scrollFactor.set(0, 0);
			add(row);
			_rowTexts.push(row);

			var number:FlxText = new FlxText(0, _codeTop, GUTTER_WIDTH - CONTENT_PAD - 2, '', FONT_SIZE);
			applyFont(number, FONT_SIZE, COLOR_LINE_NUMBER, RIGHT);
			number.wordWrap = false;
			number.scrollFactor.set(0, 0);
			add(number);
			_gutterTexts.push(number);
		}
	}

	function buildForeground():Void
	{
		_caret = makeRect(_codeX, _codeTop, 2, ROW_HEIGHT - 6, COLOR_CARET);
		_scrollTrack = makeRect(_w - SCROLLBAR_WIDTH, _codeTop, SCROLLBAR_WIDTH, _codeH, COLOR_SCROLL_TRACK);
		_scrollThumb = makeRect(_w - SCROLLBAR_WIDTH, _codeTop, SCROLLBAR_WIDTH, _codeH, COLOR_SCROLL_THUMB);
		_scrollTrack.visible = false;
		_scrollThumb.visible = false;
	}

	function buildToolbar():Void
	{
		_toolbarBg = makeRect(0, 0, _w, _toolbarH, COLOR_TOOLBAR);
		makeRect(0, _toolbarH - 1, _w, 1, COLOR_SEPARATOR);

		var specs:Array<ButtonSpec> = [
			{label: 'Apply', action: applyEdits},
			{label: 'Revert', action: revertEdits},
			{label: 'Copy', action: copyToClipboard},
			{label: 'Snippet', action: showSnippetList},
			{label: 'Check', action: runSyntaxCheck},
			{label: 'Lines', action: toggleLineMode},
			{label: 'Close', action: close}
		];

		var count:Int = specs.length;
		var gap:Float = 4;
		var buttonW:Float = (_w - CONTENT_PAD * 2 - gap * (count - 1)) / count;
		if (buttonW < 44)
		{
			gap = 2;
			buttonW = Math.max(24, (_w - CONTENT_PAD * 2 - gap * (count - 1)) / count);
		}

		var buttonH:Float = Math.max(MIN_TOUCH_HEIGHT, Math.min(MIN_TOUCH_HEIGHT + 6, _toolbarH - 6));
		var buttonY:Float = Math.max(1, (_toolbarH - buttonH) * 0.5);
		var x:Float = CONTENT_PAD;

		for (spec in specs)
		{
			var button:PanelButton = new PanelButton(x, buttonY, buttonW, buttonH, spec.label, spec.action);
			add(button);
			_buttons.push(button);
			if (spec.label == 'Lines')
				_linesButton = button;
			x += buttonW + gap;
		}

		if (_linesButton != null)
			_linesButton.setActive(_lineEditMode);
	}

	function buildFooter():Void
	{
		_footerBg = makeRect(0, _footerY, _w, _footerH, COLOR_FOOTER);
		makeRect(0, _footerY, _w, 1, COLOR_SEPARATOR);

		_footerInfo = new FlxText(CONTENT_PAD, _footerY + 4, _w - CONTENT_PAD * 2, '', 14);
		applyFont(_footerInfo, 14, COLOR_TEXT, LEFT);
		_footerInfo.wordWrap = false;
		_footerInfo.scrollFactor.set(0, 0);
		add(_footerInfo);

		_footerWarn = new FlxText(CONTENT_PAD, _footerY + 24, _w - CONTENT_PAD * 2, '', 13);
		applyFont(_footerWarn, 13, COLOR_COMMENT, LEFT);
		_footerWarn.wordWrap = true;
		_footerWarn.scrollFactor.set(0, 0);
		add(_footerWarn);

		_infoChars = Std.int(Math.max(12, (_w - CONTENT_PAD * 2) / charWidthFor(14)));
		_warnChars = Std.int(Math.max(12, 2 * (_w - CONTENT_PAD * 2) / charWidthFor(13)));
	}

	/** The snippet list: built once, hidden until the Snippet button asks for it. */
	function buildSnippets():Void
	{
		var list:Array<SnippetSpec> = snippetList();
		var popupW:Float = Math.min(_w - 16, 420);
		var rowH:Float = MIN_TOUCH_HEIGHT;
		var titleH:Float = 26;
		var pad:Float = CONTENT_PAD;
		var rows:Int = list.length + 1;
		var popupH:Float = titleH + rows * rowH + pad * 2;

		if (popupH > _codeH - 8)
		{
			// A short panel cannot hold seven 44px rows: shrink them (still finger-sized) rather
			// than push the list out of the panel, which is what an unbounded sheet would do.
			rowH = Math.max(30, (_codeH - 8 - titleH - pad * 2) / rows);
			popupH = titleH + rows * rowH + pad * 2;
		}

		var popupX:Float = (_w - popupW) * 0.5;
		var popupY:Float = _codeTop + Math.max(2, (_codeH - popupH) * 0.5);
		_snippetRect = new Rectangle(popupX, popupY, popupW, popupH);

		var backdrop:FlxSprite = makeRect(0, _codeTop, _w, _codeH, COLOR_OVERLAY);
		var popup:FlxSprite = makeRect(popupX, popupY, popupW, popupH, COLOR_BG);

		var title:FlxText = new FlxText(popupX + pad, popupY + pad, popupW - pad * 2, 'Insert snippet', 16);
		applyFont(title, 16, COLOR_TEXT, LEFT);
		title.wordWrap = false;
		title.scrollFactor.set(0, 0);
		add(title);

		_snippetButtons = [];
		var y:Float = popupY + pad + titleH;

		for (spec in list)
		{
			var button:PanelButton = new PanelButton(popupX + pad, y, popupW - pad * 2, Math.max(28, rowH - 2), spec.label, makeSnippetAction(spec.code));
			add(button);
			_snippetButtons.push(button);
			y += rowH;
		}

		var cancel:PanelButton = new PanelButton(popupX + pad, y, popupW - pad * 2, Math.max(28, rowH - 2), 'Cancel', hideSnippetList);
		add(cancel);
		_snippetButtons.push(cancel);

		_snippetSprites = [backdrop, popup, title];
		setSnippetVisible(false);
	}

	// --- Pointer ----------------------------------------------------------------------------------

	/** First touch drives the panel, mouse second - same order the on-screen keyboard uses. */
	function pollPointer():Void
	{
		_ptrX = 0;
		_ptrY = 0;
		_ptrPressed = false;
		_ptrJustPressed = false;
		_ptrJustReleased = false;
		_ptrFromTouch = false;

		if (pollTouch())
			return;

		if (FlxG.mouse == null)
			return;

		final position:FlxPoint = FlxG.mouse.getScreenPosition(panelCamera(), _ptrPoint);
		_ptrX = position.x;
		_ptrY = position.y;
		_ptrPressed = FlxG.mouse.pressed;
		_ptrJustPressed = FlxG.mouse.justPressed;
		_ptrJustReleased = FlxG.mouse.justReleased;
	}

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

				final position:FlxPoint = touch.getScreenPosition(panelCamera(), _ptrPoint);
				_ptrX = position.x;
				_ptrY = position.y;
				_ptrPressed = touch.pressed;
				_ptrJustReleased = touch.justReleased;
				_ptrFromTouch = true;
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
			final position:FlxPoint = touch.getScreenPosition(panelCamera(), _ptrPoint);
			_ptrX = position.x;
			_ptrY = position.y;
			_ptrPressed = true;
			_ptrJustPressed = true;
			_ptrFromTouch = true;
			return true;
		}
		#end

		return false;
	}

	function handleWheel():Void
	{
		if (FlxG.mouse == null)
			return;

		final wheel:Int = FlxG.mouse.wheel;
		if (wheel == 0 || !insideCodeArea(_ptrX, _ptrY))
			return;

		scrollBy(-wheel * ROW_HEIGHT * 2);
	}

	function handlePointerInteraction():Void
	{
		if (_ptrJustPressed)
		{
			_pressedButton = buttonAt(_ptrX, _ptrY);

			if (_pressedButton == null && insideCodeArea(_ptrX, _ptrY))
			{
				_dragActive = true;
				_dragMoved = false;
				_dragStartY = _ptrY;
				_dragStartScroll = _scrollY;
			}
		}

		if (_dragActive && _ptrPressed)
		{
			if (Math.abs(_ptrY - _dragStartY) > TAP_SLOP)
				_dragMoved = true;

			if (_dragMoved)
				setScroll(_dragStartScroll - (_ptrY - _dragStartY));
		}

		if (!_ptrJustReleased)
			return;

		final clicked:PanelButton = _pressedButton;
		_pressedButton = null;

		if (clicked != null && buttonAt(_ptrX, _ptrY) == clicked && clicked.onClick != null)
		{
			playSound('confirmMenu');
			clicked.onClick();
		}

		if (_dragActive)
		{
			_dragActive = false;
			// A release that never really moved is a tap: that is what opens the editor.
			if (!_dragMoved && insideCodeArea(_ptrX, _ptrY))
				openEditorForTap(_ptrY);
		}
	}

	function updateButtonStates():Void
	{
		for (button in _buttons)
		{
			if (button == null)
				continue;

			final hover:Bool = (_pressedButton == button) || (!_ptrFromTouch && button.containsPoint(_ptrX, _ptrY));
			button.setHover(hover);
		}
	}

	function handleSnippetPointer():Void
	{
		for (button in _snippetButtons)
		{
			if (button == null)
				continue;

			final hover:Bool = (_pressedSnippet == button) || (!_ptrFromTouch && button.containsPoint(_ptrX, _ptrY));
			button.setHover(hover);
		}

		if (_ptrJustPressed)
			_pressedSnippet = snippetButtonAt(_ptrX, _ptrY);

		if (!_ptrJustReleased)
			return;

		final clicked:PanelButton = _pressedSnippet;
		_pressedSnippet = null;

		if (clicked != null && snippetButtonAt(_ptrX, _ptrY) == clicked && clicked.onClick != null)
		{
			playSound('confirmMenu');
			clicked.onClick();
		}
		else if (clicked == null && _snippetRect != null && !_snippetRect.contains(_ptrX, _ptrY))
		{
			hideSnippetList();
		}
	}

	function resetPointer():Void
	{
		_pressedButton = null;
		_pressedSnippet = null;
		_dragActive = false;
		_dragMoved = false;
	}

	function buttonAt(x:Float, y:Float):PanelButton
	{
		for (button in _buttons)
		{
			if (button != null && button.containsPoint(x, y))
				return button;
		}

		return null;
	}

	function snippetButtonAt(x:Float, y:Float):PanelButton
	{
		for (button in _snippetButtons)
		{
			if (button != null && button.containsPoint(x, y))
				return button;
		}

		return null;
	}

	function insideCodeArea(x:Float, y:Float):Bool
	{
		return x >= 0 && x <= _codeX + _codeW + CONTENT_PAD && y >= _codeTop && y <= _codeTop + _codeH;
	}

	// --- Scrolling and caret ----------------------------------------------------------------------

	function setScroll(value:Float):Void
	{
		final clamped:Float = FlxMath.bound(value, 0, _maxScroll);
		if (clamped == _scrollY)
			return;

		_scrollY = clamped;
		_rowsDirty = true;
		_caretDirty = true;
	}

	function scrollBy(delta:Float):Void
	{
		setScroll(_scrollY + delta);
	}

	function clampScroll():Void
	{
		_maxScroll = Math.max(0, _contentHeight - _codeH);
		_scrollY = FlxMath.bound(_scrollY, 0, _maxScroll);
	}

	/** Scrolls so the caret row sits inside the view, with a couple of rows of context. */
	function ensureCaretVisible():Void
	{
		if (!_open)
			return;

		final index:Int = caretVisualIndex();
		final top:Float = index * ROW_HEIGHT;
		final bottom:Float = top + ROW_HEIGHT;
		final margin:Float = ROW_HEIGHT * 2;

		if (top - margin < _scrollY)
			setScroll(top - margin);
		else if (bottom + margin > _scrollY + _codeH)
			setScroll(bottom + margin - _codeH);
	}

	/** Visual row the caret is on, clamped into range even while the document has one empty row. */
	function caretVisualIndex():Int
	{
		if (_visual.length == 0)
			return 0;

		final line:Int = caretLine();
		var firstRow:Int = (line < _lineStartIndex.length) ? _lineStartIndex[line] : 0;
		var lastRow:Int = (line + 1 < _lineStartIndex.length) ? _lineStartIndex[line + 1] - 1 : _visual.length - 1;

		if (firstRow < 0)
			firstRow = 0;
		if (lastRow >= _visual.length)
			lastRow = _visual.length - 1;
		if (lastRow < firstRow)
			lastRow = firstRow;

		final column:Int = caretColumn();
		var row:Int = firstRow;

		for (i in firstRow...lastRow + 1)
		{
			row = i;
			final data:VisualRow = _visual[i];
			if (column < data.startCol + data.text.length)
				break;
		}

		return row;
	}

	/** Column of the caret inside its visual row, counted in the wrapped text of that row. */
	function caretColumnInRow(rowIndex:Int):Int
	{
		if (_visual.length == 0)
			return 0;

		final index:Int = Std.int(FlxMath.bound(rowIndex, 0, _visual.length - 1));
		final data:VisualRow = _visual[index];
		final offset:Int = caretColumn() - data.startCol;

		if (offset < 0)
			return 0;
		if (offset > data.text.length)
			return data.text.length;

		return offset;
	}

	/** Logical line the caret is on. */
	function caretLine():Int
	{
		var line:Int = 0;

		for (i in 0..._lineCharStart.length)
		{
			if (_caretIndex >= _lineCharStart[i])
				line = i;
			else
				break;
		}

		return line;
	}

	/** Column of the caret inside its logical line. */
	function caretColumn():Int
	{
		final line:Int = caretLine();
		if (line >= _lineCharStart.length)
			return 0;

		final offset:Int = _caretIndex - _lineCharStart[line];
		return (offset < 0) ? 0 : offset;
	}

	/** Character offset just past the last character of `lineIndex`. */
	function lineEndOffset(lineIndex:Int):Int
	{
		if (lineIndex < 0 || lineIndex >= _lines.length)
			return _text.length;

		final start:Int = (lineIndex < _lineCharStart.length) ? _lineCharStart[lineIndex] : 0;
		return start + _lines[lineIndex].length;
	}

	function positionCaret():Void
	{
		_caretDirty = false;

		if (_caret == null)
			return;

		final index:Int = caretVisualIndex();
		final line:Int = (_visual.length > 0) ? _visual[index].line : 0;

		_caret.x = _codeX + caretColumnInRow(index) * charWidth();
		_caret.y = _codeTop + index * ROW_HEIGHT - _scrollY + 3;

		if (_activeLineBg == null)
			return;

		final firstRow:Int = (line < _lineStartIndex.length) ? _lineStartIndex[line] : 0;
		final lastRow:Int = (line + 1 < _lineStartIndex.length) ? _lineStartIndex[line + 1] - 1 : _visual.length - 1;

		var top:Float = _codeTop + firstRow * ROW_HEIGHT - _scrollY;
		var bottom:Float = _codeTop + (lastRow + 1) * ROW_HEIGHT - _scrollY;

		if (top < _codeTop)
			top = _codeTop;
		if (bottom > _codeTop + _codeH)
			bottom = _codeTop + _codeH;

		if (bottom - top <= 1)
		{
			_activeLineBg.visible = false;
			return;
		}

		_activeLineBg.visible = true;
		_activeLineBg.y = top;
		_activeLineBg.scale.y = (bottom - top) / Math.max(1, _codeH);
	}

	function updateScrollbar():Void
	{
		if (_scrollTrack == null || _scrollThumb == null)
			return;

		final needed:Bool = _maxScroll > 0.5;
		_scrollTrack.visible = needed;
		_scrollThumb.visible = needed;

		if (!needed)
			return;

		var thumbH:Float = _codeH * (_codeH / Math.max(1, _contentHeight));
		if (thumbH < 24)
			thumbH = 24;
		if (thumbH > _codeH)
			thumbH = _codeH;

		_scrollThumb.scale.y = thumbH / Math.max(1, _codeH);
		_scrollThumb.y = _codeTop + (_scrollY / _maxScroll) * (_codeH - thumbH);
	}

	// --- Text layout -------------------------------------------------------------------------------

	/** Recomputes the visual rows, the line lookup tables and the content height from `_text`. */
	function rebuildVisual():Void
	{
		_lines = _text.split('\n');
		_lineCharStart = [];
		_lineStartIndex = [];
		_visual = [];

		final limit:Int = maxCharsPerRow();
		var charOffset:Int = 0;

		for (i in 0..._lines.length)
		{
			_lineCharStart.push(charOffset);
			_lineStartIndex.push(_visual.length);
			charOffset += _lines[i].length + 1;

			final chunks:Array<WrapChunk> = wrapLine(expandTabs(_lines[i]), limit);
			for (j in 0...chunks.length)
			{
				_visual.push({
					line: i,
					text: chunks[j].text,
					first: j == 0,
					startCol: chunks[j].start
				});
			}
		}

		if (_visual.length == 0)
			_visual.push({
				line: 0,
				text: '',
				first: true,
				startCol: 0
			});

		_contentHeight = _visual.length * ROW_HEIGHT;
		_rowsDirty = true;
		_caretDirty = true;
		clampScroll();
	}

	/** Greedy word wrap: prefers the last space of a row, falls back to a hard cut for long tokens. */
	function wrapLine(line:String, maxChars:Int):Array<WrapChunk>
	{
		final chunks:Array<WrapChunk> = [];
		if (maxChars < 4)
			maxChars = 4;

		if (line.length <= maxChars)
		{
			chunks.push({text: line, start: 0});
			return chunks;
		}

		var index:Int = 0;
		final length:Int = line.length;

		while (index < length)
		{
			final remaining:Int = length - index;
			if (remaining <= maxChars)
			{
				chunks.push({text: line.substr(index, remaining), start: index});
				break;
			}

			final limit:Int = index + maxChars;
			var breakAt:Int = -1;
			var scan:Int = limit - 1;

			while (scan > index)
			{
				if (line.charAt(scan) == ' ')
				{
					breakAt = scan;
					break;
				}
				scan--;
			}

			if (breakAt > index + Std.int(maxChars * 0.6))
			{
				chunks.push({text: line.substring(index, breakAt), start: index});
				index = breakAt + 1;
			}
			else
			{
				chunks.push({text: line.substr(index, maxChars), start: index});
				index = limit;
			}
		}

		if (chunks.length == 0)
			chunks.push({text: '', start: 0});

		return chunks;
	}

	function maxCharsPerRow():Int
	{
		final usable:Float = Math.max(20, _codeW - 8);
		var count:Int = Std.int(usable / charWidth());
		if (count < 8)
			count = 8;

		return count;
	}

	/** One monospace character in `vcr.ttf`, measured once; `vcr.ttf` is what the wrap depends on. */
	function measureCharWidth():Float
	{
		try
		{
			var probe:FlxText = new FlxText(0, 0, 1000, '', FONT_SIZE);
			applyFont(probe, FONT_SIZE, FlxColor.WHITE, LEFT);
			probe.text = 'MMMMMMMMMM';

			var measured:Float = 0;
			if (probe.textField != null)
				measured = probe.textField.textWidth / 10;

			probe.destroy();

			if (measured > 0.5)
				return measured;
		}
		catch (e:Dynamic)
		{
			// No font (very early boot, headless build): fall through to the estimate.
		}

		return charWidthFor(FONT_SIZE);
	}

	/** Repaints the visible rows for the current scroll position; only what changed is written. */
	function refreshRows(force:Bool = false):Void
	{
		if (!force && !_rowsDirty)
			return;

		_rowsDirty = false;
		clampScroll();

		final first:Int = Std.int(_scrollY / ROW_HEIGHT);
		final offset:Float = _scrollY - first * ROW_HEIGHT;

		for (i in 0..._rowTexts.length)
		{
			final row:FlxText = _rowTexts[i];
			final number:FlxText = _gutterTexts[i];
			final index:Int = first + i;

			if (index >= _visual.length)
			{
				row.visible = false;
				number.visible = false;
				continue;
			}

			final data:VisualRow = _visual[index];
			final y:Float = _codeTop + i * ROW_HEIGHT - offset;

			if (row.y != y)
				row.y = y;
			if (number.y != y)
				number.y = y;

			row.visible = true;
			number.visible = true;

			if (row.text != data.text)
				row.text = data.text;

			final color:FlxColor = isCommentLine(data.text) ? COLOR_COMMENT : COLOR_TEXT;
			if (row.color != color)
				row.color = color;

			final label:String = data.first ? Std.string(data.line + 1) : '';
			if (number.text != label)
				number.text = label;
		}

		positionCaret();
	}

	/** Line comments stay legible but recede, which is what makes a long script scannable. */
	static function isCommentLine(text:String):Bool
	{
		return text.trim().startsWith('--');
	}

	// --- Editing -----------------------------------------------------------------------------------

	/** Opens the platform editor for the whole script, or for the tapped line in line mode. */
	function openEditorForTap(y:Float):Void
	{
		if (!_lineEditMode)
		{
			beginEdit(-1);
			return;
		}

		if (_visual.length == 0)
		{
			beginEdit(0);
			return;
		}

		var index:Int = Std.int((y - _codeTop + _scrollY) / ROW_HEIGHT);
		index = Std.int(FlxMath.bound(index, 0, _visual.length - 1));
		beginEdit(_visual[index].line);
	}

	/**
	 * Hands `lineIndex` (or the whole document for a negative value) to the right editor.
	 *
	 * The platform IME is used when the device has one and the settings do not force the on-screen
	 * keyboard; otherwise the on-screen keyboard opens in its `code` layout.
	 */
	function beginEdit(lineIndex:Int):Void
	{
		if (!_open)
			return;

		final line:Int = (lineIndex >= 0 && lineIndex < _lines.length) ? lineIndex : -1;
		_editLine = line;

		if (line >= 0)
		{
			_caretIndex = lineEndOffset(line);
			_caretDirty = true;
			ensureCaretVisible();
		}

		final seed:String = (line >= 0) ? _lines[line] : _text;
		final multiline:Bool = (line < 0);

		if (shouldUseNativeKeyboard())
		{
			// The field has to sit over the code view, not over the whole game, or the IME covers
			// the text the user is editing.
			BlockSoftKeyboard.targetRect = new Rectangle(_codeX, _codeTop, _codeW, _codeH);
			_ownNativeKeyboard = true;
			BlockSoftKeyboard.open(seed, multiline, onNativeText, onNativeClose);
			setStatus(editStatusText(line));
			return;
		}

		final keyboard:BlockVirtualKeyboard = ensureVirtualKeyboard();
		if (keyboard == null)
		{
			setStatus('no keyboard available');
			return;
		}

		keyboard.setLayout(BlockVirtualKeyboard.LAYOUT_CODE);
		keyboard.onKey = onVirtualKey;
		keyboard.onClose = onVirtualClose;
		keyboard.open(seed, multiline);
		setStatus(editStatusText(line));
	}

	function editStatusText(line:Int):String
	{
		if (line < 0)
			return 'editing the whole script';

		return 'editing line ' + (line + 1) + ' of ' + _lines.length;
	}

	function onNativeText(value:String):Void
	{
		if (!_ownNativeKeyboard)
			return;

		if (_editLine >= 0)
			replaceLine(_editLine, stripNewlines(value));
		else
			applyEditedText(value, -1);
	}

	function onNativeClose():Void
	{
		_ownNativeKeyboard = false;
		_editLine = -1;
	}

	function onVirtualKey(name:String):Void
	{
		final keyboard:BlockVirtualKeyboard = _virtual;
		if (keyboard == null)
			return;

		if (_editLine >= 0)
			replaceLine(_editLine, keyboard.getText());
		else
			applyEditedText(keyboard.getText(), -1);
	}

	function onVirtualClose():Void
	{
		final keyboard:BlockVirtualKeyboard = _virtual;
		if (keyboard != null)
		{
			if (_editLine >= 0)
				replaceLine(_editLine, keyboard.getText());
			else
				applyEditedText(keyboard.getText(), -1);
		}

		_editLine = -1;
	}

	/** Creates the on-screen keyboard on first use, on whichever camera the panel lives on. */
	function ensureVirtualKeyboard():BlockVirtualKeyboard
	{
		if (_virtual != null)
			return _virtual;

		try
		{
			_virtual = new BlockVirtualKeyboard(panelCamera());
		}
		catch (e:Dynamic)
		{
			_virtual = null;
		}

		if (_virtual == null)
			return null;

		_virtual.onKey = onVirtualKey;
		_virtual.onClose = onVirtualClose;
		add(_virtual);
		return _virtual;
	}

	function shouldUseNativeKeyboard():Bool
	{
		if (!BlockSoftKeyboard.isNativeAvailable())
			return false;

		return !editorSettings().forceVirtualKeyboard;
	}

	/** Editor settings, read once per `open()` so a change in the options is picked up. */
	function editorSettings():BlockCodeEditorSettings
	{
		if (_settings != null)
			return _settings;

		try
		{
			_settings = BlockSerializer.loadSettings();
		}
		catch (e:Dynamic)
		{
			_settings = null;
		}

		if (_settings == null)
			_settings = BlockTypes.defaultSettings();

		return _settings;
	}

	/** True while an editor this panel opened owns the screen. */
	function keyboardOpen():Bool
	{
		if (_ownNativeKeyboard && BlockSoftKeyboard.isOpen())
			return true;

		return (_virtual != null && _virtual.isOpen());
	}

	/** Closes only the editors this panel opened, never a field some other module is using. */
	function dismissKeyboards():Void
	{
		if (_ownNativeKeyboard)
		{
			_ownNativeKeyboard = false;
			BlockSoftKeyboard.close();
		}

		if (_virtual != null && _virtual.isOpen())
			_virtual.close();

		_editLine = -1;
	}

	/** Swaps the whole document, keeping the caret where the caller asked (negative = at the end). */
	function applyEditedText(value:String, caretIndex:Int):Void
	{
		_text = normalizeText(value);
		rebuildVisual();
		_caretIndex = (caretIndex >= 0 && caretIndex <= _text.length) ? caretIndex : _text.length;
		_warnings = [];
		_rowsDirty = true;
		_caretDirty = true;
		refreshFooter();
		ensureCaretVisible();
	}

	/** Splices a single edited line back into the document, which is the phone editing mode. */
	function replaceLine(lineIndex:Int, value:String):Void
	{
		if (lineIndex < 0 || lineIndex >= _lines.length)
			return;

		_lines[lineIndex] = (value != null) ? value : '';
		_text = _lines.join('\n');
		rebuildVisual();

		_caretIndex = (lineIndex < _lineCharStart.length) ? _lineCharStart[lineIndex] + _lines[lineIndex].length : _text.length;
		_warnings = [];
		_rowsDirty = true;
		_caretDirty = true;
		refreshFooter();
		ensureCaretVisible();
	}

	// --- Actions ----------------------------------------------------------------------------------

	function applyEdits():Void
	{
		final callback:String->Void = _onApply;
		if (callback == null)
		{
			setStatus('apply is unavailable');
			return;
		}

		setStatus('sent ' + _lines.length + ' lines to the blocks');
		callback(_text);
	}

	function revertEdits():Void
	{
		if (_text == _original)
		{
			setStatus('nothing to revert');
			return;
		}

		applyEditedText(_original, -1);
		setScroll(0);
		setStatus('reverted to the text open() was given');
	}

	function copyToClipboard():Void
	{
		try
		{
			openfl.system.System.setClipboard(_text);
			setStatus('copied ' + _text.length + ' characters');
		}
		catch (e:Dynamic)
		{
			setStatus('clipboard is not available here');
		}
	}

	/** Runs the Lua importer without applying anything, so the warnings count in the footer is live. */
	function runSyntaxCheck():Void
	{
		var result:ImportResult = null;

		try
		{
			result = BlockLuaImporter.importCode(_text);
		}
		catch (e:Dynamic)
		{
			result = null;
		}

		if (result == null || result.warnings == null)
			_warnings = (result == null) ? ['the importer could not read this script'] : [];
		else
			_warnings = result.warnings.copy();

		refreshFooter();
		setStatus(_warnings.length == 0 ? 'syntax check: no warnings' : 'syntax check: ' + _warnings.length + ' warning(s)');
	}

	function toggleLineMode():Void
	{
		_lineEditMode = !_lineEditMode;

		if (_linesButton != null)
			_linesButton.setActive(_lineEditMode);

		setStatus(_lineEditMode ? 'tap a line to edit that line' : 'tap the code to edit the whole script');
	}

	function showSnippetList():Void
	{
		if (_snippetOpen)
		{
			hideSnippetList();
			return;
		}

		setSnippetVisible(true);
		setStatus('snippet goes in at the caret');
	}

	function hideSnippetList():Void
	{
		setSnippetVisible(false);
	}

	function setSnippetVisible(value:Bool):Void
	{
		for (sprite in _snippetSprites)
		{
			if (sprite != null)
				sprite.visible = value;
		}

		for (button in _snippetButtons)
		{
			if (button != null)
				button.visible = value;
		}

		_snippetOpen = value;
		_pressedSnippet = null;
	}

	function makeSnippetAction(code:String):Void->Void
	{
		return function():Void
		{
			insertSnippet(code);
		};
	}

	/** Inserts `code` at the caret, on its own lines, and leaves the caret just behind it. */
	function insertSnippet(code:String):Void
	{
		if (code == null || code.length == 0)
			return;

		final index:Int = Std.int(FlxMath.bound(_caretIndex, 0, _text.length));
		var before:String = _text.substr(0, index);
		var after:String = _text.substr(index);

		if (before.length > 0 && !before.endsWith('\n'))
			before += '\n';
		if (after.length > 0 && !after.startsWith('\n'))
			after = '\n' + after;

		applyEditedText(before + code + after, before.length + code.length);
		setStatus('snippet inserted');
	}

	/** The snippets the Snippet button offers, spelled the way the generator and the importer write them. */
	static function snippetList():Array<SnippetSpec>
	{
		return [
			{
				label: 'onStepHit',
				code: 'function onStepHit()\n    if curStep == 16 then\n        -- your code\n    end\nend'
			},
			{
				label: 'onBeatHit',
				code: 'function onBeatHit()\n    if curBeat == 4 then\n        -- your code\n    end\nend'
			},
			{
				label: 'makeLuaSprite',
				code: "makeLuaSprite('mySprite', 'image', 0, 0)\naddLuaSprite('mySprite', false)"
			},
			{
				label: 'doTweenX',
				code: "doTweenX('myTween', 'mySprite', 100, 1, 'linear')"
			},
			{
				label: 'setProperty',
				code: "setProperty('mySprite.alpha', 1)"
			},
			{
				label: 'runTimer',
				code: "runTimer('myTimer', 1, 1)"
			}
		];
	}

	// --- Footer and status --------------------------------------------------------------------------

	function setStatus(message:String):Void
	{
		_status = (message != null) ? message : '';
		_statusTimer = (_status.length == 0) ? 0 : STATUS_TIME;
		refreshFooter();
	}

	function refreshFooter():Void
	{
		if (_footerInfo == null || _footerWarn == null)
			return;

		var info:String = _text.length + ' chars  |  ' + _lines.length + ' lines  |  ' + _warnings.length + ' warnings';
		if (_statusTimer > 0 && _status.length > 0)
			info += '  |  ' + _status;
		_footerInfo.text = clampText(info, _infoChars);

		var preview:String = 'no import warnings';
		if (_warnings.length > 0)
		{
			final parts:Array<String> = [];
			final limit:Int = Std.int(Math.min(_warnings.length, MAX_WARNING_PREVIEW));
			for (i in 0...limit)
				parts.push(_warnings[i]);
			preview = 'warnings (' + _warnings.length + '): ' + parts.join('  /  ');
		}

		_footerWarn.text = clampText(preview, _warnChars);
		_footerWarn.color = (_warnings.length > 0) ? COLOR_WARNING : COLOR_COMMENT;
	}

	function clampText(value:String, maxChars:Int):String
	{
		if (value == null)
			return '';

		if (maxChars < 8)
			maxChars = 8;

		if (value.length <= maxChars)
			return value;

		return value.substr(0, maxChars - 3) + '...';
	}

	// --- Helpers ------------------------------------------------------------------------------------

	/** Rectangle sprite in the camera's screen space, origin at the top-left so scaling stays put. */
	function makeRect(x:Float, y:Float, w:Float, h:Float, color:Int):FlxSprite
	{
		final sprite:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(Math.max(1, Math.ceil(w))), Std.int(Math.max(1, Math.ceil(h))), color);
		sprite.scrollFactor.set(0, 0);
		sprite.origin.set(0, 0);
		sprite.offset.set(0, 0);
		add(sprite);
		return sprite;
	}

	function charWidth():Float
	{
		return (_charWidth > 0) ? _charWidth : charWidthFor(FONT_SIZE);
	}

	/** Character width of `vcr.ttf` at `size`, scaled from the measurement taken at `FONT_SIZE`. */
	function charWidthFor(size:Int):Float
	{
		if (_charWidth > 0)
			return _charWidth * size / FONT_SIZE;

		return Math.max(4, size * 0.6);
	}

	/** `Paths.font` with the platform failures contained: a missing font must not break the panel. */
	function applyFont(text:FlxText, size:Int, color:FlxColor, align:FlxTextAlign):Void
	{
		var name:String = 'vcr.ttf';

		try
		{
			final resolved:String = Paths.font('vcr.ttf');
			if (resolved != null && resolved.length > 0)
				name = resolved;
		}
		catch (e:Dynamic)
		{
			name = 'vcr.ttf';
		}

		text.setFormat(name, size, color, align);
	}

	/** The camera this panel draws on; `null` means "whatever the default camera is". */
	function panelCamera():FlxCamera
	{
		if (cameras != null && cameras.length > 0)
			return cameras[0];

		return FlxG.camera;
	}

	function playSound(key:String):Void
	{
		if (FlxG.sound == null)
			return;

		try
		{
			FlxG.sound.play(Paths.sound(key), 0.4);
		}
		catch (e:Dynamic)
		{
			// A missing click sound must never break a button.
		}
	}

	static function expandTabs(line:String):String
	{
		return (line == null) ? '' : line.replace('\t', TAB_SPACES);
	}

	/** One line ending convention for everything the panel stores and measures. */
	static function normalizeText(value:String):String
	{
		if (value == null)
			return '';

		return value.replace('\r\n', '\n').replace('\r', '\n');
	}

	/** Single line value for the line editor, which must not splice a newline into one line. */
	static function stripNewlines(value:String):String
	{
		if (value == null)
			return '';

		return normalizeText(value).replace('\n', '');
	}
}

/** One drawn row: the wrapped text of `line`, and where in that line the row starts. */
private typedef VisualRow =
{
	var line:Int;
	var text:String;
	var first:Bool;
	var startCol:Int;
}

/** One chunk of a wrapped logical line, with its offset inside the source line. */
private typedef WrapChunk =
{
	var text:String;
	var start:Int;
}

/** A toolbar or snippet button: a rectangle, a label and a callback. */
private typedef ButtonSpec =
{
	var label:String;
	var action:Void->Void;
}

/** One entry of the snippet list. */
private typedef SnippetSpec =
{
	var label:String;
	var code:String;
}

/**
 * Flat sprite button for the panel's toolbar and snippet list. It is its own `FlxGroup` so a button
 * is one member of the panel, and it forwards `visible` to its children - a `FlxGroup`'s own
 * `visible` is not consulted while drawing its members, so hiding the group alone would leave the
 * button on screen.
 */
private class PanelButton extends FlxGroup
{
	public var label:String = '';
	public var onClick:Void->Void = null;
	public var x:Float = 0;
	public var y:Float = 0;
	public var width:Float = 0;
	public var height:Float = 0;

	var _active:Bool = false;
	var _hover:Bool = false;
	var _bg:FlxSprite = null;
	var _text:FlxText = null;

	public function new(x:Float, y:Float, w:Float, h:Float, label:String, onClick:Void->Void = null)
	{
		super();

		this.x = x;
		this.y = y;
		this.width = Math.max(1, w);
		this.height = Math.max(1, h);
		this.label = (label != null) ? label : '';
		this.onClick = onClick;

		_bg = new FlxSprite(x, y).makeGraphic(Std.int(Math.ceil(this.width)), Std.int(Math.ceil(this.height)), BlockCodePanel.COLOR_BUTTON);
		_bg.scrollFactor.set(0, 0);
		add(_bg);

		final size:Int = fitFontSize(this.label, this.width, this.height);
		_text = new FlxText(x, y, this.width, this.label, size);
		_text.setFormat(resolveFont(), size, BlockCodePanel.COLOR_BUTTON_TEXT, CENTER);
		_text.wordWrap = false;
		_text.scrollFactor.set(0, 0);
		_text.updateHitbox();
		_text.y = y + (this.height - _text.height) * 0.5;
		add(_text);

		applyColors();
	}

	public function setLabel(value:String):Void
	{
		label = (value != null) ? value : '';

		if (_text != null && _text.text != label)
		{
			_text.text = label;
			_text.updateHitbox();
			_text.y = y + (height - _text.height) * 0.5;
		}
	}

	/** Draws the button in the accent colour: the "Lines" mode and the pressed state use it. */
	public function setActive(value:Bool):Void
	{
		if (_active == value)
			return;

		_active = value;
		applyColors();
	}

	public function setHover(value:Bool):Void
	{
		if (_hover == value)
			return;

		_hover = value;
		applyColors();
	}

	public function containsPoint(px:Float, py:Float):Bool
	{
		return px >= x && px <= x + width && py >= y && py <= y + height;
	}

	override function set_visible(value:Bool):Bool
	{
		if (_bg != null)
			_bg.visible = value;
		if (_text != null)
			_text.visible = value;

		return super.set_visible(value);
	}

	override public function destroy():Void
	{
		_bg = null;
		_text = null;
		onClick = null;
		super.destroy();
	}

	function applyColors():Void
	{
		if (_bg == null || _text == null)
			return;

		var color:Int = BlockCodePanel.COLOR_BUTTON;
		if (_hover)
			color = BlockCodePanel.COLOR_BUTTON_HOVER;
		else if (_active)
			color = BlockCodePanel.COLOR_BUTTON_ACTIVE;

		_bg.color = color;
		_text.color = (_active && !_hover) ? BlockCodePanel.COLOR_BUTTON_ACTIVE_TEXT : BlockCodePanel.COLOR_BUTTON_TEXT;
	}

	/** Shrinks the label until it fits the button, down to a floor that is still legible. */
	static function fitFontSize(label:String, w:Float, h:Float):Int
	{
		var size:Int = Std.int(Math.min(16, Math.max(11, h * 0.34)));

		if (label == null || label.length == 0)
			return size;

		var limit:Float = w - 10;
		if (limit < 10)
			limit = 10;

		if (label.length * size * 0.62 > limit)
		{
			var shrunk:Int = Std.int(limit / (label.length * 0.62));
			size = (shrunk < 9) ? 9 : shrunk;
		}

		return size;
	}

	static function resolveFont():String
	{
		try
		{
			final resolved:String = Paths.font('vcr.ttf');
			if (resolved != null && resolved.length > 0)
				return resolved;
		}
		catch (e:Dynamic)
		{
			// Fall through to the plain name.
		}

		return 'vcr.ttf';
	}
}
