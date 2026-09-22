package editors.blockcode;

import editors.blockcode.BlockTypes.BlockCodeEditorSettings;
import editors.blockcode.BlockTypes.ImportResult;
import flixel.FlxBasic;
import flixel.group.FlxGroup;
import openfl.geom.Rectangle;

/**
 * The Lua side of the block-code editor substate: it shows the source the blocks generate and lets
 * it be typed by hand, on a phone or with a physical keyboard.
 *
 * Shape: a modal card (`BlockLayout.panelSize()`) centred in the viewport, over a dimmed backdrop.
 * Top to bottom: a header bar with the file name, a live "N lines | N chars" readout and the action
 * buttons (Apply / Revert / Copy / Snippet / Check / Lines / Close, wrapped into as many rows as the
 * width needs); a code view with a right-aligned line-number gutter, wrapped lines, syntax colour and
 * a blinking caret; a structure outline column on the right (hats and step/event guards, tap to jump)
 * that disappears when `BlockLayout.compact`; and a footer with the character count, the import
 * warning count and a preview of the first warnings. Scrolling is by wheel, by dragging the code
 * area, by dragging the scrollbar (at least 10px wide) or by tapping an outline row; every jump is
 * eased, so the view never teleports.
 *
 * Editing: there is no text cursor owned by this class - the engines below own the caret. Tapping
 * the code area opens the platform editor for the whole script, or, in "edit lines" mode, only for
 * the tapped line, which is by far the most workable thing to do with a thumb on a phone. The
 * platform editor is `BlockSoftKeyboard` (the real IME on mobile, the focused native field - i.e. the
 * hardware keyboard - on desktop) when the platform has one and the settings do not ask for the
 * on-screen keyboard, and `BlockVirtualKeyboard` in its `code` layout otherwise. Either way the panel
 * tracks every keystroke, keeps the caret on the changed column and scrolls the edit into view, and
 * in line mode a clearly marked highlight shows which line is being edited.
 *
 * Syntax colours: the token palette lives next to the theme colours below (`COLOR_TOKEN_*`) and is
 * deliberately public, because `BlockCodePreview` paints the same code and both views have to agree.
 *
 * Coordinates: everything is drawn in the camera's screen space (`scrollFactor == 0`). The card is
 * clamped to `BlockLayout.panelSize()` and centred in the viewport - `width`/`height` are only the
 * fallback box for when the viewport cannot be read yet; the panel always lays itself out from the
 * live `BlockLayout` metrics and re-lays out by itself when they change (rotation, window resize, a
 * different screen).
 *
 * Integration: the substate owns the panel's lifetime. `open()` shows it with the current Lua and the
 * two callbacks, the Apply button calls `onApply(text)`, and `close()` hides it and calls
 * `onClosed()` once - whether it was the Close button, `close()` from the substate, or a state switch
 * that tore the panel down.
 */
class BlockCodePanel extends FlxGroup
{
	// --- Theme (the palette every block-editor surface shares) ------------------------------------
	public static inline var COLOR_BG:Int = 0xFF1A1B26;
	public static inline var COLOR_CODE_BG:Int = 0xFF0F0F14;
	public static inline var COLOR_ACTIVE_LINE:Int = 0xFF16161E;
	public static inline var COLOR_GUTTER:Int = 0xFF16161E;
	public static inline var COLOR_TOOLBAR:Int = 0xFF16161E;
	public static inline var COLOR_FOOTER:Int = 0xFF16161E;
	public static inline var COLOR_SEPARATOR:Int = 0xFF414868;
	public static inline var COLOR_ACCENT:Int = 0xFF3D59A1;
	public static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_COMMENT:Int = 0xFF565F89;
	public static inline var COLOR_LINE_NUMBER:Int = 0xFF565F89;
	public static inline var COLOR_CARET:Int = 0xFFE0AF68;
	public static inline var COLOR_WARNING:Int = 0xFFE0AF68;
	public static inline var COLOR_ERROR:Int = 0xFFF7768E;
	public static inline var COLOR_OK:Int = 0xFF9ECE6A;
	public static inline var COLOR_BUTTON:Int = 0xFF2F3349;
	public static inline var COLOR_BUTTON_HOVER:Int = 0xFF3D59A1;
	public static inline var COLOR_BUTTON_ACTIVE:Int = 0xFF3D59A1;
	public static inline var COLOR_BUTTON_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_BUTTON_ACTIVE_TEXT:Int = 0xFFE0AF68;
	public static inline var COLOR_SCROLL_TRACK:Int = 0xFF16161E;
	public static inline var COLOR_SCROLL_THUMB:Int = 0xFF565F89;
	public static inline var COLOR_OVERLAY:Int = 0xCC0F0F14;

	/**
	 * Token colours of the code view. `BlockCodePreview` shows the same script and paints the same
	 * token classes with exactly these values, and both tokenizers key on the same keyword list and
	 * the same "identifier directly followed by `(` is a call" rule, so a line reads the same in the
	 * docked preview and in this editor.
	 */
	public static inline var COLOR_TOKEN_TEXT:Int = COLOR_TEXT;

	public static inline var COLOR_TOKEN_COMMENT:Int = COLOR_COMMENT;
	public static inline var COLOR_TOKEN_KEYWORD:Int = 0xFFBB9AF7;
	public static inline var COLOR_TOKEN_STRING:Int = COLOR_OK;
	public static inline var COLOR_TOKEN_NUMBER:Int = 0xFFFF9E64;
	public static inline var COLOR_TOKEN_BUILTIN:Int = 0xFF7AA2F7;

	// --- Behaviour --------------------------------------------------------------------------------

	/** Half a blink cycle of the caret, in seconds. */
	public static inline var CARET_BLINK:Float = 0.5;

	/** What a tab expands to; the Lua generator indents with four spaces too. */
	public static inline var TAB_SPACES:String = '    ';

	/** Warnings previewed in the footer before the count alone has to do. */
	public static inline var MAX_WARNING_PREVIEW:Int = 2;

	/** Warnings kept in memory: the importer stops at its own limit, this is the backstop. */
	public static inline var MAX_WARNINGS:Int = 200;

	/** How long a status message stays in the footer. */
	static inline var STATUS_TIME:Float = 3.5;

	/** How fast a jump-to-line eases towards its target (per second, exponential-ish). */
	static inline var SCROLL_EASE:Float = 15;

	/** A jump this close to its target snaps instead of easing forever. */
	static inline var SCROLL_SNAP:Float = 0.75;

	/** Finger travel that turns a press into a scroll instead of a tap, times `BlockLayout.scale`. */
	static inline var TAP_SLOP:Float = 8;

	static inline var MIN_PANEL_W:Float = 240;
	static inline var MIN_PANEL_H:Float = 160;
	static inline var MIN_CODE_H:Float = 40;
	static inline var MIN_CODE_W:Float = 80;

	/** Snippet rows never shrink below this, however short the card is. */
	static inline var MIN_SNIPPET_ROW:Float = 28;

	/** Cap on outline entries: a pathological script must not fill the structure map forever. */
	static inline var MAX_OUTLINE:Int = 400;

	// --- Derived metrics --------------------------------------------------------------------------
	var _requestedW:Float = 0;
	var _requestedH:Float = 0;
	var _viewportW:Float = 0;
	var _viewportH:Float = 0;
	var _scale:Float = 1;
	var _pad:Float = 12;
	var _pw:Float = 0;
	var _ph:Float = 0;
	var _ox:Float = 0;
	var _oy:Float = 0;

	var _layoutW:Float = -1;
	var _layoutH:Float = -1;
	var _layoutScale:Float = -1;

	var _codeFont:Int = 15;
	var _lineH:Float = 20;
	var _charW:Float = 9;
	var _smallCharW:Float = 8;

	var _headerH:Float = 0;
	var _headerTitleH:Float = 0;
	var _buttonH:Float = 0;
	var _buttonGap:Float = 4;
	var _buttonLabels:Array<String> = [];
	var _buttonPlan:Array<Array<Int>> = [];

	var _footerY:Float = 0;
	var _footerH:Float = 0;

	var _gutterW:Float = 40;
	var _codeX:Float = 0;
	var _codeTop:Float = 0;
	var _codeW:Float = 100;
	var _codeH:Float = 100;
	var _sbW:Float = 10;

	var _outlineW:Float = 0;
	var _outlineX:Float = 0;
	var _outlineTop:Float = 0;
	var _outlineH:Float = 0;
	var _outlineRowH:Float = 30;
	var _outlineScroll:Float = 0;
	var _outlineMax:Float = 0;
	var _outlineDirty:Bool = true;

	var _infoChars:Int = 40;
	var _warnChars:Int = 80;
	var _readoutChars:Int = 24;

	// --- Document ---------------------------------------------------------------------------------
	var _text:String = '';
	var _original:String = '';
	var _lines:Array<String> = [];
	var _visual:Array<VisualRow> = [];
	var _lineCharStart:Array<Int> = [];
	var _lineStartIndex:Array<Int> = [];
	var _lineTokens:Array<Array<CodeToken>> = [];
	var _outline:Array<OutlineEntry> = [];
	var _contentHeight:Float = 0;
	var _scrollY:Float = 0;
	var _scrollTarget:Float = -1;
	var _maxScroll:Float = 0;
	var _warnings:Array<String> = [];
	var _warnLines:Array<Int> = [];

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
	var _owned:Array<FlxBasic> = [];

	var _backdrop:FlxSprite = null;
	var _border:FlxSprite = null;
	var _bg:FlxSprite = null;
	var _codeBg:FlxSprite = null;
	var _gutter:FlxSprite = null;
	var _gutterSep:FlxSprite = null;
	var _highlightBg:FlxSprite = null;
	var _highlightBar:FlxSprite = null;
	var _caret:FlxSprite = null;
	var _scrollTrack:FlxSprite = null;
	var _scrollThumb:FlxSprite = null;
	var _outlineBg:FlxSprite = null;
	var _outlineSep:FlxSprite = null;
	var _outlineSelBg:FlxSprite = null;
	var _outlineSelBar:FlxSprite = null;
	var _headerBg:FlxSprite = null;
	var _headerSep:FlxSprite = null;
	var _footerBg:FlxSprite = null;
	var _footerSep:FlxSprite = null;

	var _gutterTexts:Array<FlxText> = [];
	var _rowSegs:Array<FlxText> = [];
	var _rowSegCursor:Int = 0;
	var _outlineRows:Array<FlxText> = [];

	var _fileNameText:FlxText = null;
	var _readoutText:FlxText = null;
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
	var _dragKind:Int = DRAG_NONE;
	var _dragMoved:Bool = false;
	var _dragStartY:Float = 0;
	var _dragStartScroll:Float = 0;
	var _dragStartOutline:Float = 0;
	var _pressedOutline:Int = -1;

	static inline var DRAG_NONE:Int = 0;
	static inline var DRAG_CODE:Int = 1;
	static inline var DRAG_OUTLINE:Int = 2;
	static inline var DRAG_BAR:Int = 3;

	public function new(width:Float, height:Float)
	{
		super();

		_requestedW = (width > 0) ? width : BlockLayout.BASE_WIDTH;
		_requestedH = (height > 0) ? height : BlockLayout.BASE_HEIGHT;

		_ptrPoint = FlxPoint.get();
		_text = '';
		_original = '';
		_lines = [''];
		_visual = [];
		_lineCharStart = [];
		_lineStartIndex = [];
		_lineTokens = [];
		_outline = [];
		_warnings = [];
		_warnLines = [];
		_buttonLabels = BUTTON_LABELS.copy();

		rebuildChrome();

		// A panel no caller gave a camera to still has to render somewhere sensible; assigning one
		// here propagates to every member added so far, and `add()` keeps new members in sync.
		if (FlxG.camera != null && (cameras == null || cameras.length == 0))
			cameras = [FlxG.camera];

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
		_warnLines = [];
		_status = '';
		_statusTimer = 0;
		_editLine = -1;
		_pressedButton = null;
		_pressedSnippet = null;
		_pressedOutline = -1;
		_dragKind = DRAG_NONE;
		_dragMoved = false;
		_scrollTarget = -1;
		_outlineScroll = 0;
		_caretBlink = 0;
		_lineEditMode = BlockSoftKeyboard.isNativeAvailable();

		syncLayout();

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
		_outlineDirty = true;
		refreshRows(true);
		refreshOutline();
		refreshCounts();
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
		_pressedOutline = -1;
		_dragKind = DRAG_NONE;
		_scrollTarget = -1;
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

	/** Scrolls `line` (0-based) into view with the same easing the outline rows use. */
	public function scrollToLine(line:Int):Void
	{
		if (_lines.length == 0)
			return;

		final index:Int = Std.int(FlxMath.bound(line, 0, _lines.length - 1));
		final firstRow:Int = (index < _lineStartIndex.length) ? _lineStartIndex[index] : 0;
		final top:Float = firstRow * _lineH - _lineH * (BlockLayout.portrait ? 1.5 : 2.5);

		scrollToRow(top);
	}

	/** Selects `line` and scrolls both the code view and the outline column to it. */
	public function revealLine(line:Int, scroll:Bool = true):Void
	{
		if (_lines.length == 0)
			return;

		final index:Int = Std.int(FlxMath.bound(line, 0, _lines.length - 1));
		final start:Int = (index < _lineCharStart.length) ? _lineCharStart[index] : 0;
		_caretIndex = start;
		_caretDirty = true;
		_rowsDirty = true;
		_outlineDirty = true;

		if (scroll)
			scrollToLine(index);

		scrollOutlineTo(index);
	}

	/** True while the per-line editing mode is on (the "Lines" button shows the same state). */
	public function isLineEditMode():Bool
	{
		return _lineEditMode;
	}

	/** Switches between tapping-to-edit-a-line (phones) and tapping-to-edit-everything (keyboards). */
	public function setLineEditMode(value:Bool):Void
	{
		if (_lineEditMode == value)
			return;

		_lineEditMode = value;

		if (_linesButton != null)
			_linesButton.setActive(_lineEditMode);

		setStatus(_lineEditMode ? 'tap a line to edit that line' : 'tap the code to edit the whole script');
	}

	override public function update(elapsed:Float):Void
	{
		if (!_open)
			return;

		super.update(elapsed);
		syncLayout();
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
				refreshCounts();
			}
		}

		updateScrollEase(elapsed);

		if (_rowsDirty)
			refreshRows();

		if (_caretDirty)
			positionCaret();

		if (_outlineDirty)
			refreshOutline();

		_caretBlink += elapsed;
		if (_caret != null)
			_caret.visible = _open && ((_caretBlink % (CARET_BLINK * 2)) < CARET_BLINK);

		updateScrollbar();
	}

	override public function destroy():Void
	{
		if (_ownNativeKeyboard)
		{
			_ownNativeKeyboard = false;
			BlockSoftKeyboard.close();
		}

		destroyChrome();

		_onApply = null;
		_onClosed = null;
		_virtual = null;
		_visual = null;
		_warnings = null;
		_warnLines = null;
		_outline = null;
		_lineTokens = null;
		_ptrPoint = FlxDestroyUtil.put(_ptrPoint);

		super.destroy();
	}

	// --- Layout -----------------------------------------------------------------------------------

	/** Re-lays the panel out when `BlockLayout` reports a new viewport: rotation, resize, new screen. */
	function syncLayout():Void
	{
		BlockLayout.ensure();

		if (BlockLayout.width == _layoutW && BlockLayout.height == _layoutH && BlockLayout.scale == _layoutScale)
			return;

		rebuildChrome();
	}

	/** Throws the card away and builds it again for the current metrics. The document is kept. */
	function rebuildChrome():Void
	{
		destroyChrome();
		applyMetrics();
		buildChrome();
		rebuildVisual();
		rebuildOutline();
		refreshCounts();
		refreshOutline();
		refreshRows(true);
		positionCaret();
	}

	/**
	 * Turns the viewport into every number the card is drawn from. Everything comes from
	 * `BlockLayout`, so a 1280x720 window, a landscape phone, an upright phone and a tablet all get
	 * sensible room; nothing here is a constant that assumes a desktop window.
	 */
	function applyMetrics():Void
	{
		BlockLayout.ensure();

		_viewportW = (BlockLayout.width > 0) ? BlockLayout.width : _requestedW;
		_viewportH = (BlockLayout.height > 0) ? BlockLayout.height : _requestedH;

		_scale = BlockLayout.scale;
		_pad = Math.max(BlockLayout.inset(), 12 * _scale);

		final box = BlockLayout.panelSize(_viewportW, _viewportH);
		_pw = Math.max(MIN_PANEL_W, Math.min(box.w, _viewportW));
		_ph = Math.max(MIN_PANEL_H, Math.min(box.h, _viewportH));
		_ox = Math.floor((_viewportW - _pw) * 0.5);
		_oy = Math.floor((_viewportH - _ph) * 0.5);

		_codeFont = BlockLayout.font('body');
		_lineH = Math.max(10, Math.round(_codeFont * 1.35));
		measureCharWidth();
		_smallCharW = Math.max(4, _charW * BlockLayout.font('small') / _codeFont);

		// Every button is at least one finger tall, whatever the shared button height works out to.
		_buttonH = Math.max(BlockLayout.buttonHeight(), BlockLayout.touchSize());
		_buttonGap = BlockLayout.spacing('tight');
		_headerTitleH = Math.round(BlockLayout.font('title') * 1.35);
		_buttonPlan = planButtons();
		_headerH = Math.round(_pad * 0.5 + _headerTitleH + BlockLayout.topBarHeight(_buttonPlan.length));

		final infoH:Float = Math.round(BlockLayout.font('small') * 1.35);
		final warnH:Float = Math.round(BlockLayout.font('tiny') * 1.35);
		_footerH = Math.round(Math.max(BlockLayout.statusHeight() + infoH * 0.5, _pad * 0.5 + infoH + warnH + _pad * 0.7));
		_footerY = _ph - _footerH;

		final digits:Int = Std.string(Math.max(1, _lines.length)).length;
		_gutterW = Math.min(Math.max(digits * _charW + _pad, 3 * _charW), _pw * 0.22);
		_sbW = Math.max(10, 12 * _scale);
		_outlineW = BlockLayout.compact ? 0 : FlxMath.bound(_pw * 0.22, 140 * _scale, 250 * _scale);
		_outlineX = _pw - _outlineW;
		_outlineRowH = Math.max(BlockLayout.touchSize(), Math.round(BlockLayout.font('small') * 1.6));

		final gap:Float = Math.max(4, _pad * 0.45);
		_codeX = _gutterW + gap;
		_codeTop = _headerH + gap * 0.6;
		_codeW = Math.max(MIN_CODE_W, _outlineX - _codeX - _sbW - gap * 0.6);
		_codeH = Math.max(MIN_CODE_H, _footerY - gap * 0.6 - _codeTop);

		_outlineTop = _codeTop;
		_outlineH = _codeH;

		_layoutW = BlockLayout.width;
		_layoutH = BlockLayout.height;
		_layoutScale = BlockLayout.scale;
	}

	/**
	 * Distributes the buttons over as many rows as the card width needs; each row is stretched to
	 * fill the width exactly, so no two buttons touch and none is wider than its share.
	 */
	function planButtons():Array<Array<Int>>
	{
		final avail:Float = Math.max(60, _pw - _pad * 2);
		final plan:Array<Array<Int>> = [];
		var row:Array<Int> = [];
		var used:Float = 0;

		for (i in 0..._buttonLabels.length)
		{
			final width:Float = BlockLayout.buttonWidth(_buttonLabels[i]);
			final needed:Float = (row.length == 0) ? width : used + _buttonGap + width;

			if (row.length > 0 && needed > avail)
			{
				plan.push(row);
				row = [i];
				used = width;
			}
			else
			{
				row.push(i);
				used = needed;
			}
		}

		if (row.length > 0)
			plan.push(row);
		if (plan.length == 0)
			plan.push([0]);

		return plan;
	}

	/** Builds every sprite of the card in drawing order; the header and footer come last so they clip. */
	function buildChrome():Void
	{
		_backdrop = makeRect(0, 0, _viewportW, _viewportH, COLOR_OVERLAY);
		_border = makeRect(-1, -1, _pw + 2, _ph + 2, COLOR_SEPARATOR);
		_bg = makeRect(0, 0, _pw, _ph, COLOR_BG);

		buildCodeSurface();
		buildOutlineChrome();
		buildHeader();
		buildFooter();
		buildSnippets();

		if (_linesButton != null)
			_linesButton.setActive(_lineEditMode);
	}

	/** Code background, gutter and the pooled rows that paint the source. */
	function buildCodeSurface():Void
	{
		final bandRight:Float = _pw - _outlineW;

		// The band runs from the header down to the footer, past the two padding gaps, so a row that
		// is only half scrolled in is clipped by the header/footer bars and not by a lighter strip.
		final bandTop:Float = _headerH;
		final bandH:Float = Math.max(1, _footerY - bandTop);

		_codeBg = makeRect(0, bandTop, bandRight, bandH, COLOR_CODE_BG);
		_gutter = makeRect(0, bandTop, _gutterW, bandH, COLOR_GUTTER);
		_gutterSep = makeRect(_gutterW, bandTop, Math.max(1, _scale), bandH, COLOR_SEPARATOR);

		_highlightBg = makeRect(_gutterW + 1, _codeTop, bandRight - _gutterW - 1, 1, COLOR_ACTIVE_LINE);
		_highlightBar = makeRect(_gutterW + 1, _codeTop, Math.max(2, 2.5 * _scale), 1, COLOR_ACCENT);
		_highlightBg.visible = false;
		_highlightBar.visible = false;

		_gutterTexts = [];
		var slots:Int = Std.int(Math.ceil(_codeH / _lineH)) + 2;
		if (slots < 1)
			slots = 1;

		for (i in 0...slots)
			_gutterTexts.push(makeText(0, _codeTop, _gutterW - _pad * 0.4, '', _codeFont, COLOR_LINE_NUMBER, RIGHT));

		_rowSegs = [];
		_rowSegCursor = 0;

		_caret = makeRect(_codeX, _codeTop, Math.max(2, 2.5 * _scale), Math.max(6, _lineH - 6), COLOR_CARET);
		_scrollTrack = makeRect(_codeX + _codeW, _codeTop, _sbW, _codeH, COLOR_SCROLL_TRACK);
		_scrollThumb = makeRect(_codeX + _codeW, _codeTop, _sbW, 1, COLOR_SCROLL_THUMB);
		_scrollTrack.visible = false;
		_scrollThumb.visible = false;
	}

	/** The structure map column: background, selection marker and one text row per visible entry. */
	function buildOutlineChrome():Void
	{
		// Same full-height band as the code surface, so the card has one continuous middle.
		final bandTop:Float = _headerH;
		final bandH:Float = Math.max(1, _footerY - bandTop);

		_outlineBg = makeRect(_outlineX, bandTop, Math.max(1, _outlineW), bandH, COLOR_TOOLBAR);
		_outlineSep = makeRect(_outlineX, bandTop, Math.max(1, _scale), bandH, COLOR_SEPARATOR);
		_outlineSelBg = makeRect(_outlineX, _outlineTop, Math.max(1, _outlineW), 1, COLOR_BUTTON);
		_outlineSelBar = makeRect(_outlineX, _outlineTop, Math.max(2, 3 * _scale), 1, COLOR_ACCENT);
		_outlineRows = [];

		final visible:Bool = _outlineW > 0;
		_outlineBg.visible = visible;
		_outlineSep.visible = visible;
		_outlineSelBg.visible = visible;
		_outlineSelBar.visible = visible;

		if (!visible)
			return;

		var slots:Int = Std.int(Math.ceil(_outlineH / _outlineRowH)) + 1;
		if (slots < 1)
			slots = 1;

		final font:Int = BlockLayout.font('small');
		final textW:Float = Math.max(20, _outlineW - _pad * 0.6);

		for (i in 0...slots)
			_outlineRows.push(makeText(_outlineX + _pad * 0.4, _outlineTop + i * _outlineRowH, textW, '', font, COLOR_COMMENT, LEFT));
	}

	/** Header bar: file name, live count readout and the action buttons, one or more rows of them. */
	function buildHeader():Void
	{
		_headerBg = makeRect(0, 0, _pw, _headerH, COLOR_TOOLBAR);
		_headerSep = makeRect(0, _headerH - Math.max(1, _scale), _pw, Math.max(1, _scale), COLOR_SEPARATOR);

		final titleFont:Int = BlockLayout.font('title');
		final readoutFont:Int = BlockLayout.font('small');
		final rowW:Float = Math.max(80, _pw - _pad * 2);
		final gap:Float = BlockLayout.spacing('normal');
		final nameW:Float = Math.round(rowW * (BlockLayout.compact ? 0.5 : 0.62));
		final titleY:Float = Math.max(2, _pad * 0.4);

		_fileNameText = makeText(_pad, titleY, nameW, fileLabel(), titleFont, COLOR_TEXT, LEFT);
		_readoutText = makeText(_pad + nameW + gap, titleY + (BlockLayout.font('title') - readoutFont) * 0.4, rowW - nameW - gap, '', readoutFont,
			COLOR_COMMENT, RIGHT);
		_readoutChars = charsThatFit(rowW - nameW - gap, _smallCharW);

		var y:Float = titleY + _headerTitleH + BlockLayout.spacing('tight');
		final actions:Array<Void->Void> = buttonActions();

		for (row in _buttonPlan)
		{
			var natural:Float = -_buttonGap;
			for (index in row)
				natural += BlockLayout.buttonWidth(_buttonLabels[index]) + _buttonGap;

			final share:Float = Math.max(1, (_pw - _pad * 2 - _buttonGap * Math.max(0, row.length - 1)) / Math.max(1, natural));
			var x:Float = _pad;

			for (i in 0...row.length)
			{
				final index:Int = row[i];
				var w:Float = Math.floor(BlockLayout.buttonWidth(_buttonLabels[index]) * share);
				if (i == row.length - 1)
					w = Math.max(w, _pw - _pad - x);

				// However narrow the card gets, a button never runs past its right edge.
				w = Math.min(w, Math.max(24, _pw - _pad - x));

				final action:Void->Void = (index < actions.length) ? actions[index] : null;
				final button:PanelButton = new PanelButton(x, y, w, _buttonH, _buttonLabels[index], action, _ox, _oy);
				own(button);
				_buttons.push(button);
				if (_buttonLabels[index] == 'Lines')
					_linesButton = button;

				x += w + _buttonGap;
			}

			y += _buttonH + _buttonGap;
		}
	}

	/** Footer bar: character count, import warning count, the preview and the transient status. */
	function buildFooter():Void
	{
		_footerBg = makeRect(0, _footerY, _pw, _footerH, COLOR_FOOTER);
		_footerSep = makeRect(0, _footerY, _pw, Math.max(1, _scale), COLOR_SEPARATOR);

		final infoFont:Int = BlockLayout.font('small');
		final warnFont:Int = BlockLayout.font('tiny');
		final rowW:Float = Math.max(40, _pw - _pad * 2);
		final infoY:Float = _footerY + Math.max(2, _pad * 0.35);

		_footerInfo = makeText(_pad, infoY, rowW, '', infoFont, COLOR_TEXT, LEFT);
		_footerWarn = makeText(_pad, infoY + Math.round(infoFont * 1.4), rowW, '', warnFont, COLOR_COMMENT, LEFT);

		_infoChars = charsThatFit(rowW, Math.max(4, _charW * infoFont / _codeFont));
		_warnChars = charsThatFit(rowW, Math.max(4, _charW * warnFont / _codeFont));
	}

	/** The snippet list: built once per layout, hidden until the Snippet button asks for it. */
	function buildSnippets():Void
	{
		final list:Array<SnippetSpec> = snippetList();
		final pad:Float = Math.max(6, _pad * 0.5);
		final titleH:Float = Math.round(BlockLayout.font('title') * 1.35);
		final rows:Int = list.length + 1;

		var popupW:Float = Math.min(_pw - _pad, Math.max(240, _pw * 0.7));
		var rowH:Float = Math.max(MIN_SNIPPET_ROW, BlockLayout.touchSize());
		var popupH:Float = titleH + rows * rowH + pad * 2;

		if (popupH > _codeH - 4)
		{
			// A short card cannot hold seven finger-sized rows: shrink them (still tappable) rather
			// than push the list out of the panel, which is what an unbounded sheet would do.
			rowH = Math.max(MIN_SNIPPET_ROW, (_codeH - 4 - titleH - pad * 2) / rows);
			popupH = titleH + rows * rowH + pad * 2;
		}

		if (popupH > _ph - 4)
		{
			popupH = Math.max(60, _ph - 4);
			rowH = Math.max(MIN_SNIPPET_ROW * 0.7, (popupH - titleH - pad * 2) / rows);
		}

		final popupX:Float = Math.floor((_pw - popupW) * 0.5);
		final popupY:Float = Math.floor(_codeTop + Math.max(0, (_codeH - popupH) * 0.5));
		_snippetRect = new Rectangle(sx(popupX), sy(popupY), popupW, popupH);

		final backdrop:FlxSprite = makeRect(0, 0, _pw, _ph, COLOR_OVERLAY);
		final popup:FlxSprite = makeRect(popupX, popupY, popupW, popupH, COLOR_BG);
		final title:FlxText = makeText(popupX + pad, popupY + pad, popupW - pad * 2, 'Insert snippet', BlockLayout.font('title'), COLOR_TEXT, LEFT);

		_snippetButtons = [];
		var y:Float = popupY + pad + titleH;

		for (spec in list)
		{
			final button:PanelButton = new PanelButton(popupX + pad, y, popupW - pad * 2, rowH - Math.max(2, rowH * 0.08), spec.label,
				makeSnippetAction(spec.code), _ox, _oy);
			own(button);
			_snippetButtons.push(button);
			y += rowH;
		}

		final cancel:PanelButton = new PanelButton(popupX + pad, y, popupW - pad * 2, rowH - Math.max(2, rowH * 0.08), 'Cancel', hideSnippetList, _ox, _oy);
		own(cancel);
		_snippetButtons.push(cancel);

		_snippetSprites = [backdrop, popup, title];
		setSnippetVisible(false);
	}

	/** Order of `BUTTON_LABELS`: the header lays the buttons out by index, so the two must line up. */
	function buttonActions():Array<Void->Void>
	{
		return [
			applyEdits,
			revertEdits,
			copyToClipboard,
			showSnippetList,
			runSyntaxCheck,
			toggleLineMode,
			close
		];
	}

	/** Destroys every sprite of the card; the document, the callbacks and the keyboard stay. */
	function destroyChrome():Void
	{
		for (item in _owned)
		{
			if (item == null)
				continue;

			remove(item, true);
			item.destroy();
		}

		_owned = [];
		_gutterTexts = [];
		_rowSegs = [];
		_rowSegCursor = 0;
		_outlineRows = [];
		_buttons = [];
		_snippetButtons = [];
		_snippetSprites = [];
		_linesButton = null;

		_backdrop = null;
		_border = null;
		_bg = null;
		_codeBg = null;
		_gutter = null;
		_gutterSep = null;
		_highlightBg = null;
		_highlightBar = null;
		_caret = null;
		_scrollTrack = null;
		_scrollThumb = null;
		_outlineBg = null;
		_outlineSep = null;
		_outlineSelBg = null;
		_outlineSelBar = null;
		_headerBg = null;
		_headerSep = null;
		_footerBg = null;
		_footerSep = null;
		_fileNameText = null;
		_readoutText = null;
		_footerInfo = null;
		_footerWarn = null;
		_snippetRect = null;
		_snippetOpen = false;
		_pressedButton = null;
		_pressedSnippet = null;
		_pressedOutline = -1;
		_dragKind = DRAG_NONE;
		_dragMoved = false;
	}

	// --- Small helpers ----------------------------------------------------------------------------

	/** Adds a sprite to the panel and remembers it as ours, so a relayout can destroy it again. */
	function own(item:FlxBasic):Void
	{
		_owned.push(item);
		add(item);
	}

	/** Rectangle sprite in the camera's screen space, placed from the card origin, origin top-left. */
	function makeRect(x:Float, y:Float, w:Float, h:Float, color:Int):FlxSprite
	{
		final sprite:FlxSprite = new FlxSprite(sx(x), sy(y)).makeGraphic(Std.int(Math.max(1, Math.ceil(w))), Std.int(Math.max(1, Math.ceil(h))), color);
		sprite.scrollFactor.set(0, 0);
		sprite.origin.set(0, 0);
		sprite.offset.set(0, 0);
		own(sprite);
		return sprite;
	}

	/** Text sprite in the camera's screen space, placed from the card origin, never word wrapped. */
	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, color:Int, align:FlxTextAlign):FlxText
	{
		final field:FlxText = new FlxText(sx(x), sy(y), Math.max(8, w), text, size);
		applyFont(field, size, color, align);
		field.wordWrap = false;
		field.scrollFactor.set(0, 0);
		own(field);
		return field;
	}

	function sx(x:Float):Float
	{
		return _ox + x;
	}

	function sy(y:Float):Float
	{
		return _oy + y;
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

	/** One monospace character of the code font, measured once per layout; the wrap depends on it. */
	function measureCharWidth():Void
	{
		_charW = Math.max(4, _codeFont * 0.6);

		try
		{
			var probe:FlxText = new FlxText(0, 0, 2000, '', _codeFont);
			applyFont(probe, _codeFont, FlxColor.WHITE, LEFT);
			probe.text = 'MMMMMMMMMM';

			var measured:Float = 0;
			if (probe.textField != null)
				measured = probe.textField.textWidth / 10;

			probe.destroy();

			if (measured > 0.5)
				_charW = measured;
		}
		catch (e:Dynamic)
		{
			// No font (very early boot, headless build): the estimate set above has to do.
		}
	}

	function charWidth():Float
	{
		return (_charW > 0) ? _charW : Math.max(4, _codeFont * 0.6);
	}

	/** How many characters of a font this wide fit into `width`, with a legible floor. */
	static function charsThatFit(width:Float, charWidth:Float):Int
	{
		if (charWidth <= 0)
			return 24;

		return Std.int(Math.max(8, Math.floor(width / charWidth)));
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

	// --- Pointer ----------------------------------------------------------------------------------

	/** First touch drives the panel, mouse second - same order the on-screen keyboard uses. */
	function pollPointer():Void
	{
		_ptrX = -1;
		_ptrY = -1;
		_ptrPressed = false;
		_ptrJustPressed = false;
		_ptrJustReleased = false;
		_ptrFromTouch = false;

		if (pollTouch())
			return;

		if (FlxG.mouse == null)
			return;

		final position:FlxPoint = FlxG.mouse.getScreenPosition(panelCamera(), _ptrPoint);
		_ptrX = position.x - _ox;
		_ptrY = position.y - _oy;
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
				_ptrX = position.x - _ox;
				_ptrY = position.y - _oy;
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
			_ptrX = position.x - _ox;
			_ptrY = position.y - _oy;
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
		if (wheel == 0)
			return;

		if (insideOutline(_ptrX, _ptrY))
		{
			setOutlineScroll(_outlineScroll - wheel * _outlineRowH * 2);
			return;
		}

		if (insideCodeBand(_ptrX, _ptrY))
		{
			cancelScrollEase();
			scrollBy(-wheel * _lineH * 2);
		}
	}

	function handlePointerInteraction():Void
	{
		if (_ptrJustPressed)
		{
			_pressedButton = buttonAt(_ptrX, _ptrY);
			_pressedOutline = -1;

			if (_pressedButton == null)
			{
				if (insideScrollbar(_ptrX, _ptrY) && _maxScroll > 0)
				{
					// A scrollbar drag is not a tap: it starts moving the view right away.
					_dragKind = DRAG_BAR;
					_dragMoved = true;
					scrollFromThumb(_ptrY);
				}
				else if (insideOutline(_ptrX, _ptrY))
				{
					_dragKind = DRAG_OUTLINE;
					_dragMoved = false;
					_dragStartY = _ptrY;
					_dragStartOutline = _outlineScroll;
					_pressedOutline = outlineAt(_ptrX, _ptrY);
				}
				else if (insideCodeBand(_ptrX, _ptrY))
				{
					_dragKind = DRAG_CODE;
					_dragMoved = false;
					_dragStartY = _ptrY;
					_dragStartScroll = _scrollY;
				}
			}
		}

		if (_ptrPressed && _dragKind != DRAG_NONE)
		{
			final moved:Float = _ptrY - _dragStartY;
			if (Math.abs(moved) > tapSlop())
				_dragMoved = true;

			if (_dragMoved)
			{
				if (_dragKind == DRAG_CODE)
				{
					cancelScrollEase();
					setScroll(_dragStartScroll - moved);
				}
				else if (_dragKind == DRAG_OUTLINE)
				{
					setOutlineScroll(_dragStartOutline - moved);
				}
				else if (_dragKind == DRAG_BAR)
				{
					scrollFromThumb(_ptrY);
				}
			}
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

		// A release that never really moved is a tap: that is what opens the editor or a jump.
		if (_dragKind == DRAG_CODE && !_dragMoved && insideCodeBand(_ptrX, _ptrY))
			openEditorForTap(_ptrY);

		if (_dragKind == DRAG_OUTLINE && !_dragMoved && _pressedOutline >= 0 && _pressedOutline == outlineAt(_ptrX, _ptrY))
			jumpToOutline(_pressedOutline);

		_dragKind = DRAG_NONE;
		_pressedOutline = -1;
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
		else if (clicked == null && _snippetRect != null && !_snippetRect.contains(_ptrX + _ox, _ptrY + _oy))
		{
			hideSnippetList();
		}
	}

	function resetPointer():Void
	{
		_pressedButton = null;
		_pressedSnippet = null;
		_pressedOutline = -1;
		_dragKind = DRAG_NONE;
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

	/** Row of the outline under a point, or -1: the column belongs to the card, not to the camera. */
	function outlineAt(x:Float, y:Float):Int
	{
		if (!insideOutline(x, y))
			return -1;

		final index:Int = Std.int((y - _outlineTop + _outlineScroll) / _outlineRowH);
		if (index < 0 || index >= _outline.length)
			return -1;

		return index;
	}

	function insideCodeBand(x:Float, y:Float):Bool
	{
		final right:Float = _codeX + _codeW + _sbW;

		return x >= 0 && x <= right && y >= _codeTop && y <= _codeTop + _codeH;
	}

	function insideScrollbar(x:Float, y:Float):Bool
	{
		final left:Float = _codeX + _codeW;

		return x >= left && x <= left + _sbW && y >= _codeTop && y <= _codeTop + _codeH;
	}

	function insideOutline(x:Float, y:Float):Bool
	{
		if (_outlineW <= 0)
			return false;

		return x >= _outlineX && x <= _pw && y >= _outlineTop && y <= _outlineTop + _outlineH;
	}

	/** How far a finger may travel before a press counts as a scroll instead of a tap. */
	function tapSlop():Float
	{
		return Math.max(TAP_SLOP, TAP_SLOP * BlockLayout.scale);
	}

	// --- Scrolling --------------------------------------------------------------------------------

	function setScroll(value:Float):Void
	{
		final clamped:Float = FlxMath.bound(value, 0, _maxScroll);
		if (clamped == _scrollY)
			return;

		_scrollY = clamped;
		_rowsDirty = true;
		_caretDirty = true;
		_outlineDirty = true;
	}

	function scrollBy(delta:Float):Void
	{
		setScroll(_scrollY + delta);
	}

	/** Jumps are eased, so a tap on an outline row or a warning scrolls instead of teleporting. */
	function scrollToRow(row:Float):Void
	{
		_scrollTarget = FlxMath.bound(row, 0, _maxScroll);
	}

	function updateScrollEase(elapsed:Float):Void
	{
		if (_scrollTarget < 0)
			return;

		final target:Float = FlxMath.bound(_scrollTarget, 0, _maxScroll);

		if (Math.abs(target - _scrollY) < SCROLL_SNAP)
		{
			_scrollTarget = -1;
			setScroll(target);
			return;
		}

		setScroll(_scrollY + (target - _scrollY) * Math.min(1, elapsed * SCROLL_EASE));
	}

	function cancelScrollEase():Void
	{
		_scrollTarget = -1;
	}

	function clampScroll():Void
	{
		_maxScroll = Math.max(0, _contentHeight - _codeH);
		_scrollY = FlxMath.bound(_scrollY, 0, _maxScroll);
		_scrollTarget = FlxMath.bound(_scrollTarget, -1, _maxScroll);
	}

	/** Scrolls so the caret row sits inside the view, with a couple of rows of context. */
	function ensureCaretVisible():Void
	{
		if (!_open)
			return;

		final index:Int = caretVisualIndex();
		final top:Float = index * _lineH;
		final bottom:Float = top + _lineH;
		final margin:Float = _lineH * 2;

		if (top - margin < _scrollY)
			setScroll(top - margin);
		else if (bottom + margin > _scrollY + _codeH)
			setScroll(bottom + margin - _codeH);
	}

	function setOutlineScroll(value:Float):Void
	{
		final clamped:Float = FlxMath.bound(value, 0, _outlineMax);
		if (clamped == _outlineScroll)
			return;

		_outlineScroll = clamped;
		_outlineDirty = true;
	}

	/** Scrolls the structure map so `line`'s section is in view. */
	function scrollOutlineTo(line:Int):Void
	{
		if (_outlineW <= 0 || _outline.length == 0)
			return;

		var index:Int = 0;
		for (i in 0..._outline.length)
		{
			if (_outline[i].line <= line)
				index = i;
			else
				break;
		}

		final top:Float = index * _outlineRowH;
		if (top < _outlineScroll)
			setOutlineScroll(top);
		else if (top + _outlineRowH > _outlineScroll + _outlineH)
			setOutlineScroll(top + _outlineRowH - _outlineH);
	}

	function thumbHeight():Float
	{
		final wanted:Float = _codeH * (_codeH / Math.max(1, _contentHeight));
		return FlxMath.bound(wanted, Math.min(24, _codeH), _codeH);
	}

	function scrollFromThumb(y:Float):Void
	{
		final thumb:Float = thumbHeight();
		final track:Float = Math.max(1, _codeH - thumb);
		final ratio:Float = FlxMath.bound((y - _codeTop - thumb * 0.5) / track, 0, 1);

		cancelScrollEase();
		setScroll(ratio * _maxScroll);
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

		final thumb:Float = thumbHeight();
		final ratio:Float = (_maxScroll > 0) ? FlxMath.bound(_scrollY / _maxScroll, 0, 1) : 0;

		_scrollThumb.scale.y = thumb;
		_scrollThumb.y = sy(_codeTop + ratio * (_codeH - thumb));
	}

	// --- Caret ------------------------------------------------------------------------------------

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

		final column:Int = expandedCaretColumn();
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
		final offset:Int = expandedCaretColumn() - data.startCol;

		if (offset < 0)
			return 0;
		if (offset > data.text.length)
			return data.text.length;

		return offset;
	}

	/** Caret column in the tab-expanded line, which is what the visual rows are cut from. */
	function expandedCaretColumn():Int
	{
		final line:Int = caretLine();
		if (line < 0 || line >= _lines.length)
			return 0;

		final start:Int = (line < _lineCharStart.length) ? _lineCharStart[line] : 0;
		var offset:Int = _caretIndex - start;

		if (offset < 0)
			offset = 0;
		if (offset > _lines[line].length)
			offset = _lines[line].length;

		return expandTabs(_lines[line].substr(0, offset)).length;
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

	/** Character offset just past the last character of `lineIndex`. */
	function lineEndOffset(lineIndex:Int):Int
	{
		if (lineIndex < 0 || lineIndex >= _lines.length)
			return _text.length;

		final start:Int = (lineIndex < _lineCharStart.length) ? _lineCharStart[lineIndex] : 0;
		return start + _lines[lineIndex].length;
	}

	/** Puts the caret where the text says it is and highlights the line it belongs to. */
	function positionCaret():Void
	{
		_caretDirty = false;

		if (_caret == null || _visual == null || _visual.length == 0)
			return;

		final index:Int = Std.int(FlxMath.bound(caretVisualIndex(), 0, _visual.length - 1));
		final data:VisualRow = _visual[index];

		_caret.x = sx(_codeX + caretColumnInRow(index) * charWidth());
		_caret.y = sy(_codeTop + index * _lineH - _scrollY + 3);

		final line:Int = data.line;
		final edit:Bool = (_editLine >= 0 && _editLine == line);

		var firstRow:Int = (line < _lineStartIndex.length) ? _lineStartIndex[line] : 0;
		var lastRow:Int = (line + 1 < _lineStartIndex.length) ? _lineStartIndex[line + 1] - 1 : _visual.length - 1;

		if (firstRow < 0)
			firstRow = 0;
		if (lastRow >= _visual.length)
			lastRow = _visual.length - 1;
		if (lastRow < firstRow)
			lastRow = firstRow;

		var top:Float = _codeTop + firstRow * _lineH - _scrollY;
		var bottom:Float = _codeTop + (lastRow + 1) * _lineH - _scrollY;

		top = FlxMath.bound(top, _codeTop, _codeTop + _codeH);
		bottom = FlxMath.bound(bottom, _codeTop, _codeTop + _codeH);

		if (_highlightBg == null || _highlightBar == null || bottom - top <= 1)
		{
			if (_highlightBg != null)
				_highlightBg.visible = false;
			if (_highlightBar != null)
				_highlightBar.visible = false;
		}
		else
		{
			final height:Float = bottom - top;

			_highlightBg.visible = true;
			_highlightBg.y = sy(top);
			_highlightBg.scale.y = height;

			// The line being edited through the keyboard gets an accent edge, so "which line am I
			// typing into" is never a guess on a phone.
			_highlightBar.visible = edit;
			if (edit)
			{
				_highlightBar.y = sy(top);
				_highlightBar.scale.y = height;
			}
		}
	}

	// --- Text layout -------------------------------------------------------------------------------

	/** Recomputes the visual rows, the line lookup tables and the content height from `_text`. */
	function rebuildVisual():Void
	{
		_text = normalizeText(_text);
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
		{
			_visual.push({
				line: 0,
				text: '',
				first: true,
				startCol: 0
			});
		}

		tokenizeDocument();
		_contentHeight = _visual.length * _lineH;
		_rowsDirty = true;
		_caretDirty = true;
		_outlineDirty = true;
		clampScroll();
	}

	/**
	 * The structure map: the top-level `function onX` hats and the step / event guards inside them,
	 * which is what a script is actually navigated by. Only depth 0 and 1 lines are listed.
	 */
	function rebuildOutline():Void
	{
		_outline = [];
		_outlineDirty = true;

		if (_outlineW <= 0 || _lines == null)
			return;

		for (i in 0..._lines.length)
		{
			if (_outline.length >= MAX_OUTLINE)
				break;

			final raw:String = _lines[i];
			final text:String = (raw != null) ? raw.trim() : '';

			if (text.length == 0)
				continue;

			final indent:Int = indentLevel(raw);

			if (indent == 0 && text.startsWith('function '))
			{
				_outline.push({
					label: functionName(text, 9),
					depth: 0,
					line: i
				});
				continue;
			}

			if (indent == 0 && text.startsWith('local function '))
			{
				_outline.push({
					label: 'local ' + functionName(text, 15),
					depth: 0,
					line: i
				});
				continue;
			}

			if (indent == 0)
				continue;

			if (!text.startsWith('if ') && !text.startsWith('elseif '))
				continue;

			final guard:String = guardLabel(text);
			if (guard != null)
			{
				_outline.push({
					label: guard,
					depth: 1,
					line: i
				});
			}
		}
	}

	/** Name of the function a `function name(` line declares, without the arguments. */
	static function functionName(text:String, offset:Int):String
	{
		if (offset >= text.length)
			return 'function';

		final rest:String = text.substr(offset);
		final bracket:Int = rest.indexOf('(');
		final name:String = ((bracket == -1) ? rest : rest.substring(0, bracket)).trim();

		return (name.length == 0) ? 'function' : name;
	}

	/** "step 16" / "event 'name'" for a guard line, or null when it guards something else. */
	static function guardLabel(text:String):String
	{
		if (RE_STEP_GUARD.match(text))
			return 'step ' + RE_STEP_GUARD.matched(1);

		if (RE_EVENT_GUARD.match(text))
			return "event '" + RE_EVENT_GUARD.matched(1) + "'";

		return null;
	}

	/** How many four-space indents a line carries; the generator writes one indent per level. */
	static function indentLevel(line:String):Int
	{
		if (line == null)
			return 0;

		var spaces:Int = 0;
		while (spaces < line.length && line.charAt(spaces) == ' ')
			spaces++;

		return Std.int(spaces / 4);
	}

	/** Index of the outline entry the caret (or the edited line) sits in, -1 when there is none. */
	function currentOutlineIndex():Int
	{
		if (_outline == null || _outline.length == 0)
			return -1;

		final line:Int = (_editLine >= 0) ? _editLine : caretLine();
		var found:Int = -1;

		for (i in 0..._outline.length)
		{
			if (_outline[i].line > line)
				break;
			found = i;
		}

		return found;
	}

	/** Taps an outline row: the code view scrolls to it and the caret lands on its line. */
	function jumpToOutline(index:Int):Void
	{
		if (index < 0 || index >= _outline.length)
			return;

		final entry:OutlineEntry = _outline[index];
		revealLine(entry.line, true);
		setStatus(entry.label + '  -  line ' + (entry.line + 1));
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
		final usable:Float = Math.max(20, _codeW - 4);
		var count:Int = Std.int(usable / charWidth());
		if (count < 8)
			count = 8;

		return count;
	}

	/** Repaints the visible rows for the current scroll position; only what changed is written. */
	function refreshRows(force:Bool = false):Void
	{
		if (!force && !_rowsDirty)
			return;

		_rowsDirty = false;
		clampScroll();

		if (_gutterTexts == null || _gutterTexts.length == 0 || _visual == null)
			return;

		final first:Int = Std.int(_scrollY / _lineH);
		final offset:Float = _scrollY - first * _lineH;
		_rowSegCursor = 0;

		for (i in 0..._gutterTexts.length)
		{
			final number:FlxText = _gutterTexts[i];
			final index:Int = first + i;

			if (number == null)
				continue;

			if (index < 0 || index >= _visual.length)
			{
				number.visible = false;
				continue;
			}

			final data:VisualRow = _visual[index];
			final y:Float = _codeTop + i * _lineH - offset;

			number.visible = true;
			number.y = sy(y);
			number.text = data.first ? Std.string(data.line + 1) : '';
			number.color = ((_warnLines != null) && _warnLines.contains(data.line)) ? COLOR_WARNING : COLOR_LINE_NUMBER;

			emitRowSegments(data, y);
		}

		for (i in _rowSegCursor..._rowSegs.length)
		{
			final seg:FlxText = _rowSegs[i];
			if (seg != null)
				seg.visible = false;
		}

		positionCaret();
	}

	/** Paints one visual row as the colour spans of its source line, clipped to the wrapped part. */
	function emitRowSegments(data:VisualRow, y:Float):Void
	{
		final tokens:Array<CodeToken> = (data.line < _lineTokens.length) ? _lineTokens[data.line] : null;
		final start:Int = data.startCol;
		final end:Int = data.startCol + data.text.length;

		if (tokens == null || tokens.length == 0)
		{
			emitSegment(data.text, COLOR_TOKEN_TEXT, _codeX, y);
			return;
		}

		var pos:Int = start;

		for (token in tokens)
		{
			if (token.start >= end)
				break;
			if (token.start + token.len <= start)
				continue;

			final from:Int = (token.start < start) ? start : token.start;
			final to:Int = (token.start + token.len > end) ? end : token.start + token.len;

			if (from > pos)
				emitSegment(sliceRow(data, pos, from), COLOR_TOKEN_TEXT, _codeX + (pos - start) * charWidth(), y);

			emitSegment(sliceRow(data, from, to), token.color, _codeX + (from - start) * charWidth(), y);
			pos = to;
		}

		if (pos < end)
			emitSegment(sliceRow(data, pos, end), COLOR_TOKEN_TEXT, _codeX + (pos - start) * charWidth(), y);
	}

	/** `a`..`b` in the columns of the visual row's own text. */
	static function sliceRow(data:VisualRow, a:Int, b:Int):String
	{
		final from:Int = a - data.startCol;
		final to:Int = b - data.startCol;

		if (from >= to || from < 0 || to > data.text.length)
			return '';

		return data.text.substring(from, to);
	}

	/** Takes a text sprite from the row pool (creating one when the pool is too small) and fills it. */
	function emitSegment(text:String, color:Int, x:Float, y:Float):Void
	{
		if (text == null || text.length == 0)
			return;

		var seg:FlxText = null;

		if (_rowSegCursor < _rowSegs.length)
		{
			seg = _rowSegs[_rowSegCursor];
		}
		else
		{
			seg = makeText(_codeX, _codeTop, Math.max(20, _codeW + _pad), '', _codeFont, COLOR_TOKEN_TEXT, LEFT);
			_rowSegs.push(seg);
		}

		_rowSegCursor++;

		if (seg == null)
			return;

		if (seg.text != text)
			seg.text = text;
		if (seg.color != color)
			seg.color = color;

		seg.x = sx(x);
		seg.y = sy(y);
		seg.visible = true;
	}

	/** Repaints the structure map column for the current scroll and caret. */
	function refreshOutline():Void
	{
		_outlineDirty = false;

		if (_outlineRows == null)
			return;

		if (_outlineW <= 0 || _outlineRows.length == 0)
		{
			for (row in _outlineRows)
			{
				if (row != null)
					row.visible = false;
			}

			if (_outlineSelBg != null)
				_outlineSelBg.visible = false;
			if (_outlineSelBar != null)
				_outlineSelBar.visible = false;

			return;
		}

		_outlineMax = Math.max(0, _outline.length * _outlineRowH - _outlineH);
		_outlineScroll = FlxMath.bound(_outlineScroll, 0, _outlineMax);

		final selected:Int = currentOutlineIndex();
		final first:Int = Std.int(_outlineScroll / _outlineRowH);
		final offset:Float = _outlineScroll - first * _outlineRowH;
		final font:Int = BlockLayout.font('small');
		final textTop:Float = (_outlineRowH - font * 1.35) * 0.5;

		for (i in 0..._outlineRows.length)
		{
			final row:FlxText = _outlineRows[i];
			if (row == null)
				continue;

			final index:Int = first + i;

			if (index < 0 || index >= _outline.length)
			{
				row.visible = false;
				continue;
			}

			final entry:OutlineEntry = _outline[index];
			final indent:Float = entry.depth * Math.max(6, _smallCharW * 2);
			final label:String = clampText(entry.label, charsThatFit(_outlineW - _pad * 0.8 - indent, _smallCharW));

			row.visible = true;
			if (row.text != label)
				row.text = label;

			row.x = sx(_outlineX + _pad * 0.4 + indent);
			row.y = sy(_outlineTop + i * _outlineRowH - offset + textTop);

			var color:Int = COLOR_COMMENT;
			if (entry.depth == 0)
				color = COLOR_TOKEN_BUILTIN;
			if (index == selected)
				color = COLOR_TEXT;
			if (row.color != color)
				row.color = color;
		}

		if (_outlineSelBg == null || _outlineSelBar == null)
			return;

		if (selected < 0)
		{
			_outlineSelBg.visible = false;
			_outlineSelBar.visible = false;
			return;
		}

		final top:Float = selected * _outlineRowH - _outlineScroll;

		if (top + _outlineRowH <= 0 || top >= _outlineH)
		{
			_outlineSelBg.visible = false;
			_outlineSelBar.visible = false;
			return;
		}

		final clamped:Float = FlxMath.bound(top, 0, Math.max(0, _outlineH - _outlineRowH));
		final height:Float = Math.min(_outlineRowH, Math.max(1, _outlineH - clamped));

		_outlineSelBg.visible = true;
		_outlineSelBg.y = sy(_outlineTop + clamped);
		_outlineSelBg.scale.y = height;

		_outlineSelBar.visible = true;
		_outlineSelBar.y = _outlineSelBg.y;
		_outlineSelBar.scale.y = height;
	}

	// --- Syntax colouring -------------------------------------------------------------------------

	/**
	 * Splits every line into contiguous colour spans covering it completely, so painting a row is
	 * just a matter of picking the spans that fall inside the wrapped part. Lua long comments and
	 * long strings carry over to the next line, which is why this runs over the whole document.
	 */
	function tokenizeDocument():Void
	{
		_lineTokens = [];
		var inLongComment:Bool = false;
		var inLongString:Bool = false;

		for (index in 0..._lines.length)
		{
			final line:String = expandTabs(_lines[index]);
			final parts:Array<CodeToken> = [];
			final length:Int = line.length;
			var pos:Int = 0;
			var plainStart:Int = 0;
			var plain:String = '';

			while (pos < length)
			{
				if (inLongComment || inLongString)
				{
					final color:Int = inLongComment ? COLOR_TOKEN_COMMENT : COLOR_TOKEN_STRING;
					final close:Int = line.indexOf(']]', pos);
					final end:Int = (close == -1) ? length : close + 2;

					flushPlain(parts, plain, plainStart);
					plain = '';
					pushToken(parts, pos, line.substring(pos, end), color);

					if (close == -1)
					{
						pos = length;
					}
					else
					{
						inLongComment = false;
						inLongString = false;
						pos = end;
					}
					continue;
				}

				final c:String = line.charAt(pos);
				final next:String = (pos + 1 < length) ? line.charAt(pos + 1) : '';

				if (c == '-' && next == '-')
				{
					flushPlain(parts, plain, plainStart);
					plain = '';
					final long:Bool = (pos + 3 < length && line.charAt(pos + 2) == '[' && line.charAt(pos + 3) == '[');

					if (!long)
					{
						pushToken(parts, pos, line.substr(pos), COLOR_TOKEN_COMMENT);
						pos = length;
						continue;
					}

					final close:Int = line.indexOf(']]', pos + 4);
					final end:Int = (close == -1) ? length : close + 2;
					pushToken(parts, pos, line.substring(pos, end), COLOR_TOKEN_COMMENT);

					if (close == -1)
					{
						inLongComment = true;
						pos = length;
					}
					else
					{
						pos = end;
					}
					continue;
				}

				if (c == '"' || c == "'")
				{
					flushPlain(parts, plain, plainStart);
					plain = '';
					final end:Int = scanString(line, pos);
					pushToken(parts, pos, line.substring(pos, end), COLOR_TOKEN_STRING);
					pos = end;
					continue;
				}

				if (c == '[' && next == '[')
				{
					flushPlain(parts, plain, plainStart);
					plain = '';
					final close:Int = line.indexOf(']]', pos + 2);
					final end:Int = (close == -1) ? length : close + 2;
					pushToken(parts, pos, line.substring(pos, end), COLOR_TOKEN_STRING);

					if (close == -1)
					{
						inLongString = true;
						pos = length;
					}
					else
					{
						pos = end;
					}
					continue;
				}

				if (isDigit(c) || (c == '.' && isDigit(next)))
				{
					flushPlain(parts, plain, plainStart);
					plain = '';
					final end:Int = scanNumber(line, pos);
					pushToken(parts, pos, line.substring(pos, end), COLOR_TOKEN_NUMBER);
					pos = end;
					continue;
				}

				if (isIdentStart(c))
				{
					var end:Int = pos + 1;
					while (end < length && isIdentChar(line.charAt(end)))
						end++;

					final word:String = line.substring(pos, end);
					final keyword:Bool = isKeyword(word);
					final call:Bool = !keyword && nextMeaningful(line, end) == '(';

					if (keyword || call)
					{
						flushPlain(parts, plain, plainStart);
						plain = '';
						pushToken(parts, pos, word, keyword ? COLOR_TOKEN_KEYWORD : COLOR_TOKEN_BUILTIN);
					}
					else
					{
						if (plain.length == 0)
							plainStart = pos;
						plain += word;
					}

					pos = end;
					continue;
				}

				if (plain.length == 0)
					plainStart = pos;
				plain += c;
				pos++;
			}

			flushPlain(parts, plain, plainStart);
			_lineTokens.push(parts);
		}
	}

	static function flushPlain(parts:Array<CodeToken>, text:String, start:Int):Void
	{
		pushToken(parts, start, text, COLOR_TOKEN_TEXT);
	}

	/** Appends a span, merging it into the previous one when they are the same colour and adjacent. */
	static function pushToken(parts:Array<CodeToken>, start:Int, text:String, color:Int):Void
	{
		if (text == null || text.length == 0)
			return;

		if (parts.length > 0)
		{
			final last:CodeToken = parts[parts.length - 1];

			if (last.color == color && last.start + last.len == start)
			{
				last.len += text.length;
				return;
			}
		}

		parts.push({
			start: start,
			len: text.length,
			color: color
		});
	}

	/** End of the string literal starting at `start`, escapes included; the line end when unclosed. */
	static function scanString(line:String, start:Int):Int
	{
		final quote:String = line.charAt(start);
		var i:Int = start + 1;

		while (i < line.length)
		{
			final c:String = line.charAt(i);

			if (c == '\\')
			{
				i += 2;
				continue;
			}

			if (c == quote)
				return i + 1;

			i++;
		}

		return line.length;
	}

	/** End of the number starting at `start`: decimals, `0x` hex and exponents. */
	static function scanNumber(line:String, start:Int):Int
	{
		final hex:Bool = (start + 1 < line.length
			&& line.charAt(start) == '0'
			&& (line.charAt(start + 1) == 'x' || line.charAt(start + 1) == 'X'));
		var i:Int = start + (hex ? 2 : 0);

		while (i < line.length)
		{
			final c:String = line.charAt(i);
			final next:String = (i + 1 < line.length) ? line.charAt(i + 1) : '';

			if (hex)
			{
				if (isDigit(c) || isHexLetter(c))
				{
					i++;
					continue;
				}
				break;
			}

			if (isDigit(c) || c == '_')
			{
				i++;
				continue;
			}

			// `1 .. 2` is string concatenation, not one number.
			if (c == '.' && next != '.')
			{
				i++;
				continue;
			}

			if ((c == 'e' || c == 'E')
				&& (isDigit(next) || ((next == '+' || next == '-') && i + 2 < line.length && isDigit(line.charAt(i + 2)))))
			{
				i += isDigit(next) ? 1 : 2;
				continue;
			}

			break;
		}

		return (i > start) ? i : start + 1;
	}

	/** First non-space character at or after `from`, or '' at the end of the line. */
	static function nextMeaningful(line:String, from:Int):String
	{
		var i:Int = from;

		while (i < line.length && (line.charAt(i) == ' ' || line.charAt(i) == '\t'))
			i++;

		return (i < line.length) ? line.charAt(i) : '';
	}

	static function isKeyword(word:String):Bool
	{
		return KEYWORDS.indexOf(word) != -1;
	}

	static function charCode(c:String):Int
	{
		return (c == null || c.length == 0) ? -1 : c.charCodeAt(0);
	}

	static function isDigit(c:String):Bool
	{
		final code:Int = charCode(c);
		return code >= 48 && code <= 57;
	}

	static function isHexLetter(c:String):Bool
	{
		final code:Int = charCode(c);
		return (code >= 97 && code <= 102) || (code >= 65 && code <= 70);
	}

	static function isIdentStart(c:String):Bool
	{
		final code:Int = charCode(c);
		return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95;
	}

	static function isIdentChar(c:String):Bool
	{
		return isIdentStart(c) || isDigit(c);
	}

	// --- Editing ----------------------------------------------------------------------------------

	/** Opens the platform editor for the whole script, or for the tapped line in line mode. */
	function openEditorForTap(y:Float):Void
	{
		if (!_lineEditMode)
		{
			beginEdit(-1);
			return;
		}

		if (_visual == null || _visual.length == 0)
		{
			beginEdit(0);
			return;
		}

		var index:Int = Std.int((y - _codeTop + _scrollY) / _lineH);
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
			_rowsDirty = true;
			ensureCaretVisible();
		}

		final seed:String = (line >= 0) ? _lines[line] : _text;
		final multiline:Bool = (line < 0);

		if (shouldUseNativeKeyboard())
		{
			// The field has to sit over the code view, not over the whole game, or the IME covers
			// the text the user is editing.
			BlockSoftKeyboard.targetRect = new Rectangle(sx(_codeX), sy(_codeTop), _codeW, _codeH);
			_ownNativeKeyboard = true;
			BlockSoftKeyboard.open(seed, multiline, onNativeText, onNativeClose);
			setStatus(editStatusText(line) + '  -  esc or a tap outside when done');
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

	/** Every keystroke of the platform editor, whole file: the view follows the typing and the caret. */
	function onNativeText(value:String):Void
	{
		if (!_ownNativeKeyboard)
			return;

		if (_editLine >= 0)
		{
			replaceLine(_editLine, stripNewlines(value));
			return;
		}

		applyEditedText(value, caretFromChange(_text, value));
		ensureCaretVisible();
	}

	function onNativeClose():Void
	{
		_ownNativeKeyboard = false;
		_editLine = -1;
		_caretDirty = true;
		_rowsDirty = true;
		refreshCounts();
	}

	function onVirtualKey(name:String):Void
	{
		final keyboard:BlockVirtualKeyboard = _virtual;
		if (keyboard == null)
			return;

		if (_editLine >= 0)
		{
			replaceLine(_editLine, keyboard.getText());
			return;
		}

		applyEditedText(keyboard.getText(), caretFromChange(_text, keyboard.getText()));
		ensureCaretVisible();
	}

	function onVirtualClose():Void
	{
		final keyboard:BlockVirtualKeyboard = _virtual;
		if (keyboard != null)
		{
			if (_editLine >= 0)
				replaceLine(_editLine, keyboard.getText());
			else
				applyEditedText(keyboard.getText(), caretFromChange(_text, keyboard.getText()));
		}

		_editLine = -1;
		_caretDirty = true;
		_rowsDirty = true;
		refreshCounts();
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

	/**
	 * Where the typing happens: the platform field when the device has an IME, and also when it has
	 * a hardware keyboard (desktop and web - the field is a focused text field either way), the
	 * on-screen sheet only when the device has neither or the settings ask for it.
	 */
	function shouldUseNativeKeyboard():Bool
	{
		if (editorSettings().forceVirtualKeyboard)
			return false;

		if (BlockSoftKeyboard.isNativeAvailable())
			return true;

		return !BlockLayout.isMobile();
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
		rebuildOutline();
		_caretIndex = (caretIndex >= 0 && caretIndex <= _text.length) ? caretIndex : _text.length;
		_warnings = [];
		_warnLines = [];
		_rowsDirty = true;
		_caretDirty = true;
		_outlineDirty = true;
		refreshCounts();
		ensureCaretVisible();
	}

	/** Splices a single edited line back into the document, which is the phone editing mode. */
	function replaceLine(lineIndex:Int, value:String):Void
	{
		if (lineIndex < 0 || lineIndex >= _lines.length)
			return;

		final clean:String = (value != null) ? value : '';
		if (_lines[lineIndex] == clean)
			return;

		_lines[lineIndex] = clean;
		_text = _lines.join('\n');
		rebuildVisual();
		rebuildOutline();

		_caretIndex = (lineIndex < _lineCharStart.length) ? _lineCharStart[lineIndex] + clean.length : _text.length;
		_warnings = [];
		_warnLines = [];
		_rowsDirty = true;
		_caretDirty = true;
		_outlineDirty = true;
		refreshCounts();
		ensureCaretVisible();
	}

	/**
	 * Caret offset inside `after`, derived from how `after` differs from `before`: the field's own
	 * caret is not readable through `BlockSoftKeyboard`, so the common prefix/suffix diff has to
	 * stand in. It is right for typing, deleting, pasting and replacing a selection, which is every
	 * edit the platform editor reports.
	 */
	static function caretFromChange(before:String, after:String):Int
	{
		if (before == null || after == null || before == after)
			return -1;

		final limit:Int = Std.int(Math.min(before.length, after.length));
		var prefix:Int = 0;

		while (prefix < limit && before.charAt(prefix) == after.charAt(prefix))
			prefix++;

		var suffix:Int = 0;
		final remBefore:Int = before.length - prefix;
		final remAfter:Int = after.length - prefix;

		while (suffix < remBefore
			&& suffix < remAfter
			&& before.charAt(before.length - 1 - suffix) == after.charAt(after.length - 1 - suffix))
			suffix++;

		return after.length - suffix;
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

		cancelScrollEase();
		_editLine = -1;
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

	/**
	 * Runs the Lua importer without applying anything, so the warning count in the footer is live,
	 * and jumps to the first line a warning is about.
	 */
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

		if (_warnings.length > MAX_WARNINGS)
			_warnings = _warnings.slice(0, MAX_WARNINGS);

		collectWarningLines();
		_rowsDirty = true;
		refreshCounts();

		if (_warnings.length == 0)
		{
			setStatus('syntax check: no warnings');
			return;
		}

		setStatus('syntax check: ' + _warnings.length + ' warning(s)');

		if (_warnLines.length > 0)
		{
			final first:Int = _warnLines[0];
			revealLine(first, true);
			setStatus('syntax check: ' + _warnings.length + ' warning(s)  -  first at line ' + (first + 1));
		}
	}

	/** Importer warnings are "Line N: ...", so the line a warning points at can be marked and found. */
	function collectWarningLines():Void
	{
		_warnLines = [];

		for (message in _warnings)
		{
			if (message == null || !RE_WARN_LINE.match(message))
				continue;

			final number:Null<Int> = Std.parseInt(RE_WARN_LINE.matched(1));
			if (number == null || number <= 0)
				continue;

			final zero:Int = number - 1;
			if (!_warnLines.contains(zero))
				_warnLines.push(zero);
		}

		_warnLines.sort(function(a:Int, b:Int):Int
		{
			return a - b;
		});
	}

	function toggleLineMode():Void
	{
		setLineEditMode(!_lineEditMode);
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
		refreshCounts();
	}

	/** Live counts in the header and the footer: characters, warnings, preview and status. */
	function refreshCounts():Void
	{
		if (_footerInfo == null || _footerWarn == null || _lines == null)
			return;

		var info:String = _text.length + ' chars  |  ' + _warnings.length + ' warnings';
		if (_statusTimer > 0 && _status.length > 0)
			info += '  |  ' + _status;

		_footerInfo.text = clampText(info, _infoChars);
		_footerInfo.color = (_warnings.length > 0) ? COLOR_WARNING : COLOR_TEXT;

		var preview:String = 'no import warnings (Check runs the importer)';
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

		if (_readoutText != null)
			_readoutText.text = clampText(_lines.length + ' lines  |  ' + _text.length + ' chars', _readoutChars);
	}

	/** What the Save panel would call this script, which is the file name the header shows. */
	function fileLabel():String
	{
		final settings:BlockCodeEditorSettings = editorSettings();
		var name:String = ((settings != null) && settings.scriptName != null) ? settings.scriptName : BlockTypes.DEFAULT_SCRIPT_NAME;

		if (name.length == 0)
			name = BlockTypes.DEFAULT_SCRIPT_NAME;
		if (!name.endsWith('.lua'))
			name += '.lua';

		return name;
	}

	static function clampText(value:String, maxChars:Int):String
	{
		if (value == null)
			return '';

		if (maxChars < 8)
			maxChars = 8;

		if (value.length <= maxChars)
			return value;

		return value.substr(0, maxChars - 3) + '...';
	}

	// --- Static tables ------------------------------------------------------------------------------

	/** Header buttons, in the order `buttonActions()` returns its callbacks. */
	static var BUTTON_LABELS:Array<String> = ['Apply', 'Revert', 'Copy', 'Snippet', 'Check', 'Lines', 'Close'];

	/**
	 * Lua keywords the generator emits, coloured as keywords. The list is `BlockCodePreview`'s, so a
	 * word is never purple in the docked preview and plain in this editor.
	 */
	static var KEYWORDS:Array<String> = [
		'function',
		'if',
		'then',
		'else',
		'elseif',
		'end',
		'while',
		'do',
		'break',
		'local',
		'return',
		'for',
		'in'
	];

	static var RE_STEP_GUARD:EReg = new EReg('curStep\\s*[=<>]+\\s*(-?[0-9]+)', '');

	static var RE_EVENT_GUARD:EReg = new EReg("^(?:if|elseif)\\s+(?:n|eventName|event|value1|value2)\\s*==\\s*'([^']*)'", '');

	static var RE_WARN_LINE:EReg = new EReg('^Line ([0-9]+):', '');
}

/** One drawn row: the wrapped text of `line`, and where in that line the row starts. */
private typedef VisualRow =
{
	var line:Int;
	var text:String;
	var first:Bool;

	/** Column in the tab-expanded line the row's text starts at. */
	var startCol:Int;
}

/** One chunk of a wrapped logical line, with its offset inside the source line. */
private typedef WrapChunk =
{
	var text:String;
	var start:Int;
}

/** One coloured span of a source line: `len` characters from `start`, in `color`. */
private typedef CodeToken =
{
	var start:Int;
	var len:Int;
	var color:Int;
}

/** One row of the structure map: a label, how deep it is and the line it starts at. */
private typedef OutlineEntry =
{
	var label:String;
	var depth:Int;
	var line:Int;
}

/** One entry of the snippet list. */
private typedef SnippetSpec =
{
	var label:String;
	var code:String;
}

/**
 * Flat sprite button for the panel's header and snippet list. It is its own `FlxGroup` so a button is
 * one member of the panel, and it forwards `visible` to its children - a `FlxGroup`'s own `visible` is
 * not consulted while drawing its members, so hiding the group alone would leave the button on
 * screen. `x`/`y`/`width`/`height` are the button's box in the panel's own coordinates, which is what
 * hit testing uses; the sprites it draws are offset by the card origin the panel passes in.
 */
private class PanelButton extends FlxGroup
{
	public var label:String = '';
	public var onClick:Void->Void = null;
	public var x:Float = 0;
	public var y:Float = 0;
	public var width:Float = 0;
	public var height:Float = 0;

	var _ox:Float = 0;
	var _oy:Float = 0;
	var _active:Bool = false;
	var _hover:Bool = false;
	var _bg:FlxSprite = null;
	var _text:FlxText = null;

	public function new(x:Float, y:Float, w:Float, h:Float, label:String, onClick:Void->Void = null, ox:Float = 0, oy:Float = 0)
	{
		super();

		this.x = x;
		this.y = y;
		this.width = Math.max(1, w);
		this.height = Math.max(1, h);
		this.label = (label != null) ? label : '';
		this.onClick = onClick;
		_ox = ox;
		_oy = oy;

		_bg = new FlxSprite(x + _ox, y + _oy).makeGraphic(Std.int(Math.ceil(this.width)), Std.int(Math.ceil(this.height)), BlockCodePanel.COLOR_BUTTON);
		_bg.scrollFactor.set(0, 0);
		add(_bg);

		final size:Int = fitFontSize(this.label, this.width, this.height);
		_text = new FlxText(x + _ox, y + _oy, this.width, this.label, size);
		_text.setFormat(resolveFont(), size, BlockCodePanel.COLOR_BUTTON_TEXT, CENTER);
		_text.wordWrap = false;
		_text.scrollFactor.set(0, 0);
		_text.updateHitbox();
		_text.y = y + _oy + (this.height - _text.height) * 0.5;
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
			_text.y = y + _oy + (height - _text.height) * 0.5;
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
		var size:Int = BlockLayout.font('small');
		final limit:Float = Math.max(10, w - Math.max(6, h * 0.2));

		if (label == null || label.length == 0)
			return size;

		var wanted:Int = Std.int(Math.min(size, Math.max(9, h * 0.45)));

		if (label.length * wanted * 0.62 > limit)
		{
			final shrunk:Int = Std.int(limit / (label.length * 0.62));
			wanted = (shrunk < 9) ? 9 : shrunk;
		}

		return wanted;
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
