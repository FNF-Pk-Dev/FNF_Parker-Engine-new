package editors.blockcode;

import flixel.group.FlxGroup;
import openfl.geom.Rectangle;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/** One `.lua` the browser lists, together with the metadata its row shows. */
private typedef ScriptEntry =
{
	/** Slash path exactly as `BlockFileIO.listScripts()` returned it. */
	var path:String;

	var name:String;

	/** Mod folder the file lives in, `''` for the shared `mods/` root. */
	var mod:String;

	/** True when the file sits in the current song's `data/<formatted song>/` folder. */
	var inSongFolder:Bool;

	/** Size on disk in bytes, `0` when it could not be read. */
	var size:Float;

	/** Epoch milliseconds of the last write, `0` when unknown. */
	var modified:Float;
};

/**
 * A themed press target: one solid `FlxSprite` plus a label, hit-tested against the
 * pointer. Kept as a small plain holder so the browser can reuse a fixed pool of them
 * for the filter chips, the footer actions and the delete confirmation.
 */
private class BrowserButton
{
	public var bg:FlxSprite;
	public var label:FlxText;
	public var x:Float = 0;
	public var y:Float = 0;
	public var w:Float = 0;
	public var h:Float = 0;

	/** Whether the button takes part in drawing and hit-testing right now. */
	public var shown:Bool = false;

	public var enabled:Bool = true;

	/** Destructive action: drawn in the danger colour. */
	public var danger:Bool = false;

	/** Primary action or active filter: drawn in the accent colour. */
	public var accent:Bool = false;

	public var held:Bool = false;

	/** Mouse (never touch) is over the button: drawn one step lighter. */
	public var hover:Bool = false;

	/** True when the button lives on the list camera, i.e. its rect is list-local. */
	public var listSpace:Bool = false;

	/** Colour the background graphic was last built with, so it is only rebuilt when it changes. */
	public var bgColor:Int = 0;

	public function new()
	{
	}

	public function contains(px:Float, py:Float):Bool
	{
		return shown && px >= x && px <= x + w && py >= y && py <= y + h;
	}
}

/**
 * One pooled list row: the row background plus the two lines of a script file - the name
 * with the body font, the shortened path and the size with the small font - and the cache
 * of which of the three looks (normal / hover / selected) the background currently has.
 */
private class BrowserRow
{
	public var bg:FlxSprite;
	public var name:FlxText;
	public var detail:FlxText;
	public var size:FlxText;

	/** 0 = normal, 1 = hover, 2 = selected or pressed. `-1` forces the first paint. */
	public var visual:Int = -1;

	public function new()
	{
	}
}

/**
 * File browser of the block-code editor: lists every `.lua` the engine could load, loads
 * one back into blocks and shows whether the external block definitions were picked up.
 *
 * It is built for the editor substate that sits on top of a running `PlayState`, so it is
 * self-contained: it owns its cameras (a full screen overlay, a small list viewport that
 * clips the scrolling rows, and one for the on-screen keyboard), adds them to
 * `FlxG.cameras` while it is open and takes them out again when it closes. Every child
 * sprite is positioned in the space of the camera that draws it, so the panel stays where
 * it is whatever the game behind it does with its own cameras.
 *
 * ```haxe
 * var browser = new BlockFileBrowser(760, 560);
 * browser.setSongFilter(songName);
 * add(browser);
 * browser.open(function(path:String) {
 *     importIntoBlocks(path);
 * }, function() {
 *     // dismissed: the browser is closed again
 * });
 * ```
 *
 * Layout comes entirely from `BlockLayout`, so the same panel reads well in a 1280x720
 * window, on a phone in landscape and on an upright phone or tablet:
 *
 * - the panel is `BlockLayout.panelSize()` clamped to the requested size, and every row,
 *   button and font is derived from `BlockLayout.touchSize()`, `font()` and `spacing()`;
 * - a sticky header (title, result count, filter chips, search field) never scrolls;
 * - rows are two lines tall - at least `touchSize() + 12` - with the file name on the
 *   first line and the shortened path plus the size on the second;
 * - the external block-config card is its own section with a one line summary, an
 *   expandable, scrollable detail area and the Reload button;
 * - an empty list explains where scripts are expected (`BlockFileIO.execTargetsFor`) and
 *   a search without hits offers a way back to the full list.
 *
 * Pointer input is touch first (`FlxG.touches`) and mouse second; the list scrolls by
 * touch drag, mouse wheel and a `BlockLayout`-sized scrollbar, and a long press on a row
 * opens the destructive "move to `.bak`" confirmation.
 */
class BlockFileBrowser extends FlxGroup
{
	// --- Theme -------------------------------------------------------------------------
	public static inline var COLOR_BG:Int = 0xFF16161E;
	public static inline var COLOR_ROW:Int = 0xFF1A1B26;
	public static inline var COLOR_HOVER:Int = 0xFF24283B;
	public static inline var COLOR_SELECTED:Int = 0xFF3D59A1;
	public static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_DIM:Int = 0xFF565F89;
	public static inline var COLOR_BOX:Int = 0xFF24283B;
	public static inline var COLOR_EDGE:Int = 0xFF414868;
	public static inline var COLOR_OK:Int = 0xFF9ECE6A;
	public static inline var COLOR_WARN:Int = 0xFFE0AF68;
	public static inline var COLOR_DANGER:Int = 0xFFF7768E;
	public static inline var COLOR_SCRIM:Int = 0xB3000000;

	// --- Constants ---------------------------------------------------------------------

	/** How long a press on a row lasts before the delete confirmation opens. */
	static inline var LONG_PRESS:Float = 0.55;

	/** How far a finger may travel before the gesture counts as a scroll instead of a tap. */
	static inline var DRAG_SLOP:Float = 8;

	static inline var WHEEL_STEP:Float = 52;

	/** Seconds a status message stays in the footer before the hint comes back. */
	static inline var MESSAGE_TIME:Float = 5;

	/** `vcr.ttf` is monospace, so the font size gives a usable estimate for clipping. */
	static inline var CHAR_W:Float = 0.62;

	/** Width of the coloured status stripe on the left edge of the block-config card. */
	static inline var CARD_EDGE_W:Float = 3;

	/** Smallest number of detail lines the config card can show at once. */
	static inline var CARD_MIN_LINES:Int = 1;

	/** Text lines the empty state can draw (a title plus these). */
	static inline var EMPTY_LINE_POOL:Int = 12;

	/** Text lines the config card can draw at once. */
	static inline var CARD_LINE_POOL:Int = 6;

	/** `vcr.ttf` has no U+00B7, so the summary uses the bullet the FPS counter already uses. */
	static inline var SEPARATOR:String = ' • ';

	/** Chips shown on top of the three fixed ones (this song / all mods / all). */
	static inline var MAX_MOD_CHIPS:Int = 3;

	// --- Callbacks ---------------------------------------------------------------------

	/** Called with the path the user picked, before the browser closes itself. */
	var _pick:String->Void = null;

	/** Called exactly once every time the browser goes from open to closed. */
	var _closed:Void->Void = null;

	// --- Cameras -----------------------------------------------------------------------
	var _overlay:FlxCamera;
	var _kbdCam:FlxCamera;

	/** Shared camera arrays: every child holds one of these, so swapping the camera in it moves everyone. */
	var _cams:Array<FlxCamera> = [];

	var _listCams:Array<FlxCamera> = [];
	var _kbdCams:Array<FlxCamera> = [];

	var _camerasAttached:Bool = false;
	var _isOpen:Bool = false;
	var _screenW:Float = 1280;
	var _screenH:Float = 720;

	/** Panel size the caller asked for; `layout()` clamps it to the screen. */
	var _requestedW:Float = 0;

	var _requestedH:Float = 0;

	// --- Metrics (all of them from BlockLayout, filled in by `measure()`) --------------
	var _pad:Float = 14;
	var _gap:Float = 8;
	var _gapTight:Float = 4;
	var _ctlH:Float = 38;
	var _rowH:Float = 58;
	var _rowGap:Float = 8;
	var _barW:Float = 12;
	var _chipH:Float = 46;
	var _lineH:Float = 17;
	var _hintH:Float = 18;
	var _fontBody:Int = 15;
	var _fontSmall:Int = 13;
	var _fontTitle:Int = 18;

	/** `BlockLayout.describe()` of the last styling pass, so fonts are only re-applied on a real resize. */
	var _styleStamp:String = '';

	/** Detail lines the config card body shows at once, and the number it currently uses. */
	var _cardVisibleLines:Int = 4;

	var _cardLinesUsed:Int = CARD_MIN_LINES;

	// --- Panel geometry ----------------------------------------------------------------
	var _panelX:Float = 0;
	var _panelY:Float = 0;
	var _panelW:Float = 0;
	var _panelH:Float = 0;
	var _innerX:Float = 0;
	var _innerW:Float = 0;
	var _titleY:Float = 0;
	var _titleH:Float = 0;
	var _chipY:Float = 0;
	var _chipRows:Int = 0;
	var _searchY:Float = 0;
	var _cardY:Float = 0;
	var _cardH:Float = 0;
	var _listX:Float = 0;
	var _listY:Float = 0;
	var _listW:Float = 0;
	var _listH:Float = 0;
	var _buttonsY:Float = 0;
	var _hintY:Float = 0;
	var _hintVisible:Bool = true;

	/** Widest text areas, derived once per layout pass. */
	var _titleW:Float = 100;

	var _countW:Float = 100;
	var _searchTextW:Float = 100;
	var _cardSummaryW:Float = 100;
	var _cardToggleW:Float = 100;

	// --- List geometry (list-local coordinates) ----------------------------------------
	var _rowW:Float = 100;
	var _rowTextX:Float = 8;
	var _rowTextW:Float = 100;
	var _rowPadY:Float = 8;
	var _sizeBoxW:Float = 64;
	var _barX:Float = 0;
	var _thumbY:Float = 0;
	var _thumbH:Float = 0;
	var _emptyX:Float = 8;
	var _emptyY:Float = 8;
	var _emptyW:Float = 100;
	var _emptyH:Float = 0;

	// --- Chrome ------------------------------------------------------------------------
	var _scrim:FlxSprite;
	var _panel:FlxSprite;
	var _edgeTop:FlxSprite;
	var _edgeBottom:FlxSprite;
	var _edgeLeft:FlxSprite;
	var _edgeRight:FlxSprite;
	var _headerEdge:FlxSprite;
	var _footerEdge:FlxSprite;
	var _cardBg:FlxSprite;
	var _cardBodyBg:FlxSprite;
	var _cardEdge:FlxSprite;

	var _titleText:FlxText;
	var _countText:FlxText;
	var _searchText:FlxText;
	var _searchHint:FlxText;
	var _hintText:FlxText;
	var _cardSummary:FlxText;

	/** One text per visible line of the block-config card body. */
	var _cardTexts:Array<FlxText> = [];

	var _cardBarBg:FlxSprite;
	var _cardBarThumb:FlxSprite;

	var _closeBtn:BrowserButton;
	var _searchBtn:BrowserButton;
	var _clearBtn:BrowserButton;
	var _cardToggle:BrowserButton;
	var _reloadBtn:BrowserButton;
	var _loadBtn:BrowserButton;
	var _deleteBtn:BrowserButton;
	var _cancelBtn:BrowserButton;
	var _yesBtn:BrowserButton;
	var _noBtn:BrowserButton;
	var _resetBtn:BrowserButton;

	/** Filter chips, grown on demand because the mod folders are only known at runtime. */
	var _chipButtons:Array<BrowserButton> = [];

	var _buttons:Array<BrowserButton> = [];

	// --- List (drawn by the list camera, so these are list-local coordinates) -----------
	var _rows:Array<BrowserRow> = [];
	var _emptyTitle:FlxText;
	var _emptyLines:Array<FlxText> = [];
	var _emptyContent:Array<String> = [];
	var _emptyColors:Array<Int> = [];
	var _scrollTrack:FlxSprite;
	var _scrollThumb:FlxSprite;

	var _confirmScrim:FlxSprite;
	var _confirmCard:FlxSprite;
	var _confirmEdge:FlxSprite;
	var _confirmTitle:FlxText;
	var _confirmName:FlxText;
	var _confirmBody:FlxText;
	var _confirmIndex:Int = -1;
	var _confirmCardX:Float = 0;
	var _confirmCardY:Float = 0;
	var _confirmCardW:Float = 0;
	var _confirmCardH:Float = 0;

	/** Name the confirmation promises, resolved once when the confirmation opens. */
	var _confirmBackup:String = '';

	var _vkb:BlockVirtualKeyboard;

	// --- Data --------------------------------------------------------------------------
	var _songName:String = '';
	var _all:Array<ScriptEntry> = [];
	var _filtered:Array<ScriptEntry> = [];
	var _filterKind:String = 'all';
	var _filterMod:String = '';
	var _search:String = '';

	/** Labels, kinds and mod names of the chips currently on screen. */
	var _chipLabels:Array<String> = [];

	var _chipKinds:Array<String> = [];
	var _chipMods:Array<String> = [];

	/** `kind|mod|search` of the last filtering, used to drop the selection when it changes. */
	var _filterKey:String = '';

	/** Labels of the last chip strip, so a strip that needs another row triggers a layout. */
	var _chipKey:String = '';

	var _selected:Int = -1;
	var _scroll:Float = 0;
	var _contentH:Float = 0;
	var _maxScroll:Float = 0;
	var _hoverRow:Int = -1;

	var _configFiles:Array<String> = [];
	var _configErrors:Array<String> = [];
	var _configRuntime:Int = 0;
	var _cardContent:Array<String> = [];
	var _cardColors:Array<Int> = [];
	var _cardEdgeColor:Int = 0;

	/** Whether the config card is unfolded, and whether the user decided that themselves. */
	var _cardOpen:Bool = false;

	var _cardUserToggled:Bool = false;

	/** First visible line of the config card body and its scroll range, in lines. */
	var _cardScroll:Float = 0;

	var _cardScrollMax:Float = 0;

	var _cardBodyVisible:Bool = false;
	var _cardBodyX:Float = 0;
	var _cardBodyY:Float = 0;
	var _cardBodyW:Float = 0;
	var _cardBodyH:Float = 0;
	var _cardTextX:Float = 0;
	var _cardTextW:Float = 100;
	var _cardBarW:Float = 10;

	var _message:String = '';
	var _messageError:Bool = false;
	var _messageTimer:Float = 0;

	// --- Pointer -----------------------------------------------------------------------
	var _pointer:FlxPoint;
	var _auxPoint:FlxPoint;
	var _ptrX:Float = 0;
	var _ptrY:Float = 0;
	var _ptrPressed:Bool = false;
	var _ptrJustPressed:Bool = false;
	var _ptrJustReleased:Bool = false;
	var _touchId:Int = -1;

	/** `''` / `'list'` / `'bar'` / `'card'`: what the current drag started on. */
	var _gesture:String = '';

	var _pressRow:Int = -1;
	var _pressTime:Float = 0;
	var _pressY:Float = 0;
	var _pressScroll:Float = 0;
	var _pressDragged:Bool = false;
	var _pressButton:BrowserButton = null;
	var _pressOutsideConfirm:Bool = false;
	var _barGrab:Float = 0;

	var _hoverButton:BrowserButton = null;

	var _editingSearch:Bool = false;
	var _nativeEditing:Bool = false;

	/**
	 * @param width  Width the panel should have in pixels; `BlockLayout.panelSize()` clamps it to the screen.
	 * @param height Height the panel should have in pixels; clamped the same way.
	 */
	public function new(width:Float, height:Float)
	{
		super();

		_requestedW = width;
		_requestedH = height;
		_pointer = FlxPoint.get();
		_auxPoint = FlxPoint.get();

		BlockLayout.ensure();
		measure();
		buildCameras();
		buildUI();
		layout();
	}

	// --- Public API --------------------------------------------------------------------

	/**
	 * Opens the browser on top of whatever runs behind it.
	 *
	 * `onPick` receives the path of the file the user loaded (a second tap on the row, or
	 * the LOAD button); it runs while the browser is still open, and the browser closes
	 * itself right after it returns. `onClosed` runs once when the browser is closed,
	 * whichever way that happened (load, cancel, close button), so the caller can hand its
	 * own input handling back. A callback that closes the browser itself gets no second
	 * close.
	 *
	 * Calling this while the browser is already open refreshes it and adopts the new
	 * callbacks.
	 */
	public function open(onPick:String->Void, onClosed:Void->Void):Void
	{
		_pick = onPick;
		_closed = onClosed;

		if (_isOpen)
		{
			refresh();
			return;
		}

		_isOpen = true;
		visible = true;
		active = true;

		layout();
		attachCameras();
		refresh();
		playSound('scrollMenu');
	}

	/**
	 * Closes the browser and fires `onClosed` once. Safe to call twice, and safe to call
	 * from `onPick` - the close is a no-op once the browser is gone.
	 */
	public function close():Void
	{
		if (!_isOpen)
			return;

		_isOpen = false;
		visible = false;
		active = false;

		dismissTextEditor();
		closeConfirm();
		_pressButton = null;
		_pressRow = -1;
		_gesture = '';
		_pressDragged = false;
		_pressOutsideConfirm = false;
		_selected = -1;
		_scroll = 0;
		_hoverRow = -1;

		if (_hoverButton != null)
		{
			_hoverButton.hover = false;
			refreshButton(_hoverButton);
			_hoverButton = null;
		}

		detachCameras();

		if (_closed != null)
		{
			var notify:Void->Void = _closed;
			_closed = null;
			notify();
		}
	}

	/**
	 * Song the "This song" chip narrows to and the song folder `BlockFileIO` scans. An
	 * empty or null name just leaves that chip out.
	 */
	public function setSongFilter(songName:String):Void
	{
		_songName = songName == null ? '' : songName.trim();
		if (_isOpen)
			refresh();
	}

	override public function update(elapsed:Float):Void
	{
		if (!_isOpen)
			return;

		super.update(elapsed);

		if (_messageTimer > 0)
		{
			_messageTimer -= elapsed;
			if (_messageTimer <= 0)
			{
				_messageTimer = 0;
				refreshFooterText();
			}
		}

		// A resize while the panel is up has to move the cameras with it, and the metrics
		// every control is measured in come from the same viewport.
		BlockLayout.ensure();
		if (BlockLayout.width != _screenW || BlockLayout.height != _screenH)
			layout();

		// A text editor owns the pointer while it is up, and the tap that dismisses the
		// field is deliberately swallowed instead of also selecting a row behind it.
		if (_editingSearch)
			return;

		pollPointer();
		updateHover();
		handlePointer(elapsed);
	}

	override public function destroy():Void
	{
		if (_nativeEditing)
		{
			_nativeEditing = false;
			BlockSoftKeyboard.destroy();
		}

		detachCameras();
		_vkb = null;
		_hoverButton = null;
		_pointer = FlxDestroyUtil.put(_pointer);
		_auxPoint = FlxDestroyUtil.put(_auxPoint);

		super.destroy();
	}

	// --- Construction ------------------------------------------------------------------

	function buildCameras():Void
	{
		_screenW = FlxG.width > 0 ? FlxG.width : 1280;
		_screenH = FlxG.height > 0 ? FlxG.height : 720;

		_overlay = makeOverlayCamera(_screenW, _screenH);
		_kbdCam = makeOverlayCamera(_screenW, _screenH);

		_cams = [_overlay];
		_listCams = [makeListCamera(0, 0, 1, 1)];
		_kbdCams = [_kbdCam];
	}

	function makeOverlayCamera(w:Float, h:Float):FlxCamera
	{
		var cam:FlxCamera = new FlxCamera(0, 0, Std.int(Math.max(1, w)), Std.int(Math.max(1, h)));
		cam.bgColor = 0x00000000;
		cam.scroll.set(0, 0);
		cam.zoom = 1;
		return cam;
	}

	function makeListCamera(x:Float, y:Float, w:Float, h:Float):FlxCamera
	{
		var cam:FlxCamera = new FlxCamera(Math.round(x), Math.round(y), Std.int(Math.max(1, w)), Std.int(Math.max(1, h)));
		cam.bgColor = 0x00000000;
		cam.scroll.set(0, 0);
		cam.zoom = 1;
		return cam;
	}

	/** Rebuilds the full screen cameras (and the keyboard that lives on one of them) after a resize. */
	function syncCameras():Bool
	{
		var w:Float = FlxG.width > 0 ? FlxG.width : _screenW;
		var h:Float = FlxG.height > 0 ? FlxG.height : _screenH;
		if (_overlay != null && w == _screenW && h == _screenH)
			return false;

		_screenW = w;
		_screenH = h;

		// A `FlxCamera` only works out its clip rect in its constructor, so resizing one in
		// place would leave it cropping the old area. Replace them instead.
		detachCameras();
		_overlay = makeOverlayCamera(w, h);
		_kbdCam = makeOverlayCamera(w, h);
		_cams[0] = _overlay;
		_kbdCams[0] = _kbdCam;
		_listCams[0] = makeListCamera(_listX, _listY, _listW, _listH);

		buildKeyboard();

		if (_isOpen)
			attachCameras();
		return true;
	}

	function attachCameras():Void
	{
		if (_camerasAttached)
			return;

		// `false` keeps them out of the default draw target list, so nothing that belongs to
		// the game's own cameras is drawn a second time on top of the editor.
		FlxG.cameras.add(_cams[0], false);
		FlxG.cameras.add(_listCams[0], false);
		FlxG.cameras.add(_kbdCams[0], false);
		_camerasAttached = true;
	}

	function detachCameras():Void
	{
		if (!_camerasAttached)
			return;

		_camerasAttached = false;
		for (cam in [_cams[0], _listCams[0], _kbdCams[0]])
		{
			if (cam != null)
				FlxG.cameras.remove(cam, false);
		}
	}

	function buildKeyboard():Void
	{
		if (_vkb != null)
		{
			remove(_vkb, true);
			_vkb.destroy();
			_vkb = null;
		}

		_vkb = new BlockVirtualKeyboard(_kbdCam);
		_vkb.cameras = _kbdCams;
		_vkb.onKey = onVirtualKey;
		_vkb.onClose = onVirtualKeyboardClosed;
		add(_vkb);
	}

	function buildUI():Void
	{
		_scrim = overlay(new FlxSprite());
		_panel = overlay(new FlxSprite());
		_edgeTop = overlay(new FlxSprite());
		_edgeBottom = overlay(new FlxSprite());
		_edgeLeft = overlay(new FlxSprite());
		_edgeRight = overlay(new FlxSprite());
		_headerEdge = overlay(new FlxSprite());
		_footerEdge = overlay(new FlxSprite());
		_cardBg = overlay(new FlxSprite());
		_cardBodyBg = overlay(new FlxSprite());
		_cardEdge = overlay(new FlxSprite());

		_titleText = overlay(makeText());
		_titleText.text = 'Load Lua Script';

		_countText = overlay(makeText());
		_countText.alignment = FlxTextAlign.RIGHT;

		_cardSummary = overlay(makeText());

		for (i in 0...CARD_LINE_POOL)
			_cardTexts.push(overlay(makeText()));

		_cardBarBg = overlay(new FlxSprite());
		_cardBarThumb = overlay(new FlxSprite());

		_closeBtn = makeButton(false, false);
		_searchBtn = makeButton(false, false);
		_searchText = overlay(makeText());
		_searchHint = overlay(makeText());
		_clearBtn = makeButton(false, false);
		_cardToggle = makeButton(false, false);
		_reloadBtn = makeButton(false, false);
		_hintText = overlay(makeText());

		_loadBtn = makeButton(false, true);
		_deleteBtn = makeButton(true, false);
		_cancelBtn = makeButton(false, false);
		_yesBtn = makeButton(true, false, true);
		_noBtn = makeButton(false, false, true);

		// The keyboard draws on its own camera, which is the last one added, so it is above
		// the panel whatever the member order is.
		buildKeyboard();

		// List contents, in draw order. The rows come first, then everything that has to
		// draw above them (scrollbar, empty state, reset button, confirmation).
		buildRows();
		_scrollTrack = listChild(new FlxSprite());
		_scrollThumb = listChild(new FlxSprite());

		_emptyTitle = listChild(makeText());
		for (i in 0...EMPTY_LINE_POOL)
			_emptyLines.push(listChild(makeText()));
		_resetBtn = makeButton(false, true, true);

		_confirmScrim = listChild(new FlxSprite());
		_confirmCard = listChild(new FlxSprite());
		_confirmEdge = listChild(new FlxSprite());
		_confirmTitle = listChild(makeText());
		_confirmTitle.alignment = FlxTextAlign.CENTER;
		_confirmName = listChild(makeText());
		_confirmName.alignment = FlxTextAlign.CENTER;
		_confirmBody = listChild(makeText());
		_confirmBody.alignment = FlxTextAlign.CENTER;

		applyStyles();
	}

	function buildRows():Void
	{
		// One slot per row the tallest possible panel can show, plus the row cut off at the
		// bottom. Built here so the scrollbar, the empty state and the confirmation are all
		// added after the rows and therefore draw above them.
		var slots:Int = Std.int(Math.ceil(_screenH / Math.max(1, _rowH + _rowGap))) + 2;
		if (slots < 2)
			slots = 2;

		for (i in 0...slots)
			addRow();
	}

	/** Grows the row pool by one slot, inserted below the scrollbar so the draw order holds. */
	function addRow():BrowserRow
	{
		var row:BrowserRow = new BrowserRow();
		row.bg = insertRowSprite(new FlxSprite());
		row.name = insertRowSprite(makeText());
		row.detail = insertRowSprite(makeText());
		row.size = insertRowSprite(makeText());
		row.size.alignment = FlxTextAlign.RIGHT;
		setRowVisible(row, false);
		_rows.push(row);
		return row;
	}

	/** Adds one more slot when the panel got taller (a window resize while the browser is up). */
	function ensureRowSlots():Void
	{
		var needed:Int = Std.int(Math.ceil(_listH / Math.max(1, _rowH + _rowGap))) + 2;
		while (_rows.length < needed)
			addRow();
	}

	function insertRowSprite<T:FlxSprite>(sprite:T):T
	{
		sprite.cameras = _listCams;
		sprite.scrollFactor.set(0, 0);

		var at:Int = _scrollTrack != null ? members.indexOf(_scrollTrack) : -1;
		if (at < 0)
			add(sprite);
		else
			insert(at, sprite);
		return sprite;
	}

	/** Creates a button, registers it for hit-testing and adds its two sprites to a camera. */
	function makeButton(danger:Bool, accent:Bool, onListCamera:Bool = false):BrowserButton
	{
		var btn:BrowserButton = new BrowserButton();
		btn.danger = danger;
		btn.accent = accent;
		btn.listSpace = onListCamera;
		btn.bg = onListCamera ? listChild(new FlxSprite()) : overlay(new FlxSprite());
		btn.label = onListCamera ? listChild(makeText()) : overlay(makeText());
		btn.label.alignment = FlxTextAlign.CENTER;
		_buttons.push(btn);
		return btn;
	}

	function overlay<T:FlxSprite>(sprite:T):T
	{
		sprite.cameras = _cams;
		sprite.scrollFactor.set(0, 0);
		add(sprite);
		return sprite;
	}

	function listChild<T:FlxSprite>(sprite:T):T
	{
		sprite.cameras = _listCams;
		sprite.scrollFactor.set(0, 0);
		add(sprite);
		return sprite;
	}

	function makeText():FlxText
	{
		var text:FlxText = new FlxText(0, 0, 0, '', 12);
		text.setFormat(Paths.font('vcr.ttf'), 12, COLOR_TEXT);
		return text;
	}

	function setStyle(text:FlxText, size:Int, color:Int):Void
	{
		if (text == null)
			return;

		text.setFormat(Paths.font('vcr.ttf'), size, color);
	}

	/**
	 * Re-applies every font of the panel. Sizes come from `BlockLayout.font()`, so a resize
	 * that changed `BlockLayout.scale` has to restyle everything; the stamp keeps this off
	 * the per-frame path.
	 */
	function applyStyles():Void
	{
		var stamp:String = BlockLayout.describe();
		if (stamp == _styleStamp)
			return;

		_styleStamp = stamp;

		setStyle(_titleText, _fontTitle, COLOR_TEXT);
		setStyle(_countText, _fontSmall, COLOR_DIM);
		setStyle(_searchText, _fontBody, COLOR_TEXT);
		setStyle(_searchHint, _fontBody, COLOR_DIM);
		setStyle(_hintText, _fontSmall, COLOR_DIM);
		setStyle(_cardSummary, _fontBody, COLOR_TEXT);

		for (text in _cardTexts)
			setStyle(text, _fontSmall, COLOR_DIM);

		setStyle(_emptyTitle, _fontBody, COLOR_TEXT);
		for (text in _emptyLines)
			setStyle(text, _fontSmall, COLOR_DIM);

		setStyle(_confirmTitle, _fontBody, COLOR_DANGER);
		setStyle(_confirmName, _fontBody, COLOR_TEXT);
		setStyle(_confirmBody, _fontSmall, COLOR_DIM);

		for (row in _rows)
		{
			setStyle(row.name, _fontBody, COLOR_TEXT);
			setStyle(row.detail, _fontSmall, COLOR_DIM);
			setStyle(row.size, _fontSmall, COLOR_DIM);
		}

		for (btn in _buttons)
			setStyle(btn.label, _fontBody, COLOR_TEXT);
	}

	// --- Layout ------------------------------------------------------------------------

	/** Fills every metric from `BlockLayout`, so nothing below works with a hardcoded size. */
	function measure():Void
	{
		_pad = Math.max(BlockLayout.inset(), BlockLayout.spacing('normal'));
		_gap = BlockLayout.spacing('normal');
		_gapTight = BlockLayout.spacing('tight');
		_ctlH = Math.max(BlockLayout.touchSize(), BlockLayout.buttonHeight());
		_rowGap = BlockLayout.spacing('normal');
		_barW = Math.max(10, 12 * BlockLayout.scale);

		_fontBody = BlockLayout.font('body');
		_fontSmall = BlockLayout.font('small');
		_fontTitle = BlockLayout.font('title');

		// Two text lines with breathing room between and around them, and never under one
		// finger-sized hit area (the task's floor is `touchSize() + 12`).
		var stacked:Float = _fontBody * 1.25 + _fontSmall * 1.25 + _gapTight * 2;
		_rowH = Math.max(BlockLayout.touchSize() + 14, Math.round(stacked + _gapTight * 2));
		_chipH = Math.max(BlockLayout.touchSize(), Math.round(_fontBody * 1.9));
		_lineH = Math.round(_fontSmall * 1.35);
		_hintH = Math.round(_fontSmall * 1.4);
		_cardVisibleLines = BlockLayout.compact ? 2 : (BlockLayout.narrow || BlockLayout.portrait ? 3 : 4);
	}

	function layout():Void
	{
		BlockLayout.ensure();
		measure();
		applyStyles();
		syncCameras();

		var size = BlockLayout.panelSize(_requestedW, _requestedH);
		_panelW = Math.round(size.w);
		_panelH = Math.round(size.h);
		_panelX = Math.round((_screenW - _panelW) / 2);
		_panelY = Math.round((_screenH - _panelH) / 2);
		_innerX = Math.round(_panelX + _pad);
		_innerW = Math.round(_panelW - _pad * 2);

		// The chip strip wraps depending on how wide its labels are, and the strip height
		// moves the list, so lay out twice whenever the wrap changed.
		for (pass in 0...3)
		{
			var rows:Int = _chipRows;
			layoutChrome();
			layoutChips();
			if (_chipRows == rows)
				break;
		}

		layoutCard();

		// The list camera has to be resized before anything is placed inside it.
		ensureListCamera();
		layoutList();

		refreshSearchText();
		refreshCount();
		refreshEmptyState();
		refreshRows();
		refreshScrollbar();
		refreshCardStatus();
		refreshCardBody();
		refreshCardScrollbar();
		refreshConfirm();
		refreshFooter();
		refreshFooterText();
	}

	/**
	 * Everything the panel draws directly on the overlay camera: the frame, the sticky
	 * header (title, count, chips, search field), the block-config card, the footer and the
	 * list rect the list camera is clipped to. The list content itself is placed by
	 * `layoutList()` and the `refresh*` methods.
	 */
	function layoutChrome():Void
	{
		_titleY = _panelY + _pad;
		_titleH = _ctlH;
		_chipY = _titleY + _titleH + _gap;

		var stripH:Float = chipsStripHeight();
		_searchY = _chipY + stripH;
		_cardY = _searchY + _ctlH + _gap;

		var cardCollapsedH:Float = _ctlH;
		var cardOpenH:Float = cardCollapsedH + _gapTight + _cardLinesUsed * _lineH + _gapTight * 2;
		var cardH:Float = _cardOpen ? cardOpenH : cardCollapsedH;

		_buttonsY = _panelY + _panelH - _pad - _ctlH;

		// From the bottom up: buttons, hint line, list. On a short panel the card body and
		// then the hint line give way before the list is squeezed below one row.
		var showHint:Bool = true;
		var listTop:Float = _cardY + cardH + _gap;
		var listH:Float = 0;

		for (attempt in 0...3)
		{
			listTop = _cardY + cardH + _gap;
			var bottom:Float = (showHint ? _buttonsY - _gapTight - _hintH : _buttonsY) - _gap;
			listH = bottom - listTop;

			if (listH >= _rowH)
				break;
			if (cardH > cardCollapsedH)
			{
				cardH = cardCollapsedH;
				continue;
			}
			if (showHint)
			{
				showHint = false;
				continue;
			}
			break;
		}

		if (listH < _rowH)
			listH = _rowH;

		_cardH = Math.round(cardH);
		_cardBodyVisible = _cardOpen && cardH > cardCollapsedH;
		_hintVisible = showHint;
		_hintY = _buttonsY - _gapTight - _hintH;
		_listX = _panelX;
		_listY = Math.round(listTop);
		_listW = _panelW;
		_listH = Math.round(listH);

		// Frame.
		paint(_scrim, 0, 0, _screenW, _screenH, COLOR_SCRIM);
		paint(_panel, _panelX, _panelY, _panelW, _panelH, COLOR_BG);
		paint(_edgeTop, _panelX, _panelY, _panelW, 1, COLOR_EDGE);
		paint(_edgeBottom, _panelX, _panelY + _panelH - 1, _panelW, 1, COLOR_EDGE);
		paint(_edgeLeft, _panelX, _panelY, 1, _panelH, COLOR_EDGE);
		paint(_edgeRight, _panelX + _panelW - 1, _panelY, 1, _panelH, COLOR_EDGE);
		paint(_headerEdge, _panelX, Math.round(_cardY - _gap * 0.5), _panelW, 1, COLOR_EDGE);
		paint(_footerEdge, _panelX, Math.round((showHint ? _hintY : _buttonsY) - _gap * 0.5), _panelW, 1, COLOR_EDGE);

		layoutHeader();
		layoutFooterButtons();
		placeText(_hintText, _innerX, _hintY, _innerW, FlxTextAlign.LEFT, _fontSmall);
		_hintText.visible = showHint;
	}

	/** Title row and search row, the two parts of the sticky header that never scroll. */
	function layoutHeader():Void
	{
		var closeW:Float = Math.round(Math.max(_ctlH, BlockLayout.touchSize()));
		var countY:Float = _titleY + Math.round((_titleH - _fontSmall * 1.25) / 2);
		var titleY:Float = _titleY + Math.round((_titleH - _fontTitle * 1.25) / 2);
		var searchY:Float = _searchY + Math.round((_ctlH - _fontBody * 1.25) / 2);

		paintButton(_closeBtn, _innerX + _innerW - closeW, _titleY + Math.round((_titleH - closeW) / 2), closeW, closeW);
		paintButtonLabel(_closeBtn, 'X');

		var titleAvail:Float = Math.max(40, _innerW - closeW - _gap * 2);
		_countW = Math.min(titleAvail * 0.55, Math.max(110, 170 * BlockLayout.scale));
		_titleW = Math.max(40, titleAvail - _countW - _gap);

		placeText(_titleText, _innerX, titleY, _titleW, FlxTextAlign.LEFT, _fontTitle);
		placeText(_countText, _innerX + titleAvail - _countW, countY, _countW, FlxTextAlign.RIGHT, _fontSmall);

		// Search field with the clear "X" sitting inside its right end, so the field can use
		// the full panel width; the text area keeps clear of the X either way.
		paintButton(_searchBtn, _innerX, _searchY, _innerW, _ctlH);
		paintButtonLabel(_searchBtn, '');

		// The X keeps the full finger-sized height while still sitting inside the field.
		var clearW:Float = Math.min(_ctlH, Math.max(BlockLayout.touchSize(), _ctlH - _gapTight * 2));
		_searchTextW = Math.max(30, _innerW - _gap * 2 - clearW - _gapTight);
		placeText(_searchText, _innerX + _gap, searchY, _searchTextW, FlxTextAlign.LEFT, _fontBody);
		placeText(_searchHint, _innerX + _gap, searchY, _searchTextW, FlxTextAlign.LEFT, _fontBody);

		paintButton(_clearBtn, _innerX + _innerW - clearW - _gapTight, _searchY + Math.round((_ctlH - clearW) / 2), clearW, clearW);
		paintButtonLabel(_clearBtn, 'X');
	}

	/** The filter chips wrap into as many rows as the labels need. */
	function layoutChips():Void
	{
		var drawn:Int = 0;
		for (i in 0..._chipButtons.length)
		{
			if (i < _chipLabels.length && _chipLabels[i].length > 0)
				drawn++;
		}

		if (drawn < 1)
		{
			_chipRows = 0;
			for (btn in _chipButtons)
			{
				btn.shown = false;
				refreshButton(btn);
			}
			return;
		}

		var limit:Float = _innerX + _innerW;
		var x:Float = _innerX;
		var row:Int = 0;

		for (i in 0..._chipButtons.length)
		{
			var btn:BrowserButton = _chipButtons[i];
			if (i >= _chipLabels.length || _chipLabels[i].length < 1)
			{
				btn.shown = false;
				refreshButton(btn);
				continue;
			}

			var w:Float = chipWidthFor(_chipLabels[i]);
			if (x > _innerX && x + w > limit)
			{
				row++;
				x = _innerX;
			}

			btn.accent = isActiveChip(i);
			paintButton(btn, x, _chipY + row * (_chipH + _gap), w, _chipH);
			paintButtonLabel(btn, _chipLabels[i]);
			x += w + _gap;
		}

		_chipRows = row + 1;
	}

	function chipsStripHeight():Float
	{
		if (_chipRows < 1)
			return 0;

		return _chipRows * _chipH + _chipRows * _gap;
	}

	function chipWidthFor(label:String):Float
	{
		var wanted:Float = label.length * _fontBody * CHAR_W + _pad * 2;
		var floor:Float = BlockLayout.touchSize() * 1.3;
		return Math.round(Math.max(floor, Math.min(wanted, _innerW)));
	}

	/** The block-config card: a summary row that is a tap target, plus the detail section. */
	function layoutCard():Void
	{
		if (_cardToggle == null)
			return;

		var reloadW:Float = Math.round(Math.max(Math.max(BlockLayout.buttonWidth('RELOAD'), _fontBody * CHAR_W * 6
			+ _pad * 2), BlockLayout.touchSize() * 1.3));
		_cardToggleW = Math.max(60, _innerW - reloadW - _gap * 2);
		_cardSummaryW = Math.max(40, _cardToggleW - _gap * 2 - CARD_EDGE_W);

		paint(_cardBg, _innerX, _cardY, _innerW, _cardH, COLOR_BOX);

		paintButton(_cardToggle, _innerX + CARD_EDGE_W, _cardY, _cardToggleW, _ctlH);
		paintButtonLabel(_cardToggle, '');

		paintButton(_reloadBtn, _innerX + _innerW - reloadW, _cardY, reloadW, _ctlH);
		paintButtonLabel(_reloadBtn, 'RELOAD');

		placeText(_cardSummary, _innerX + CARD_EDGE_W + _gap, _cardY + Math.round((_ctlH - _fontBody * 1.25) / 2), _cardSummaryW, FlxTextAlign.LEFT, _fontBody);

		if (!_cardBodyVisible)
		{
			_cardBodyBg.visible = false;
			_cardBarBg.visible = false;
			_cardBarThumb.visible = false;
			for (text in _cardTexts)
				text.visible = false;
			return;
		}

		_cardBodyX = _innerX;
		_cardBodyY = _cardY + _ctlH + _gapTight;
		_cardBodyW = _innerW;
		_cardBodyH = Math.max(_lineH, _cardH - _ctlH - _gapTight);
		_cardBarW = _barW;
		_cardTextX = _innerX + CARD_EDGE_W + _gap;
		_cardTextW = Math.max(40, _innerW - CARD_EDGE_W - _gap * 2 - _cardBarW - _gapTight);

		paint(_cardBodyBg, _cardBodyX, _cardBodyY, _cardBodyW, _cardBodyH, COLOR_ROW);

		for (text in _cardTexts)
			text.fieldWidth = _cardTextW;
	}

	/** Sizes and places the list-local content: rows are handled by `refreshRows()`. */
	function layoutList():Void
	{
		_rowW = Math.max(1, _listW - _barW - _gap);
		_rowTextX = _gap;
		_rowTextW = Math.max(20, _rowW - _rowTextX * 2);
		_sizeBoxW = Math.round(Math.max(56, _fontSmall * CHAR_W * 9));

		var stacked:Float = _fontBody * 1.25 + _fontSmall * 1.25;
		_rowPadY = Math.max(2, Math.round((_rowH - stacked) / 2));

		_barX = _listW - _barW;
		paint(_scrollTrack, _barX, 0, _barW, _listH, COLOR_BOX);
		_scrollTrack.visible = false;

		_emptyX = _pad;
		_emptyY = _pad;
		_emptyW = Math.max(40, _listW - _barW - _gap - _pad * 2);
	}

	/** The list lives on its own camera, whose clip rect has to match the list rect exactly. */
	function ensureListCamera():Void
	{
		var cam:FlxCamera = _listCams[0];
		if (cam != null && cam.x == Math.round(_listX) && cam.y == Math.round(_listY) && cam.width == Std.int(_listW) && cam.height == Std.int(_listH))
			return;

		var attached:Bool = _camerasAttached;
		detachCameras();
		_listCams[0] = makeListCamera(_listX, _listY, _listW, _listH);
		if (attached)
			attachCameras();
	}

	// --- Painting helpers --------------------------------------------------------------

	/**
	 * Sizes, positions and repaints a solid box. Every sprite passed here keeps the same
	 * colour for its whole life (only buttons and the config stripe change colour, and they
	 * track it themselves), so the graphic is rebuilt on the first call and when the size
	 * changed - not on every scroll frame.
	 */
	function paint(sprite:FlxSprite, x:Float, y:Float, w:Float, h:Float, color:Int):Void
	{
		var iw:Int = Std.int(Math.max(1, Math.round(w)));
		var ih:Int = Std.int(Math.max(1, Math.round(h)));
		if (sprite.graphic == null || sprite.width != iw || sprite.height != ih)
			sprite.makeGraphic(iw, ih, color);

		sprite.setPosition(Math.round(x), Math.round(y));
	}

	/** `paint()` for a box whose colour may change (the config card stripe); returns the cache. */
	function paintTint(sprite:FlxSprite, x:Float, y:Float, w:Float, h:Float, color:Int, current:Int):Int
	{
		var iw:Int = Std.int(Math.max(1, Math.round(w)));
		var ih:Int = Std.int(Math.max(1, Math.round(h)));
		if (sprite.graphic == null || sprite.width != iw || sprite.height != ih || current != color)
			sprite.makeGraphic(iw, ih, color);

		sprite.setPosition(Math.round(x), Math.round(y));
		return color;
	}

	/** Positions and styles one line of text; `align` is left alone when it is null. */
	function placeText(text:FlxText, x:Float, y:Float, width:Float, align:FlxTextAlign, size:Int):Void
	{
		if (text == null)
			return;

		text.x = Math.round(x);
		text.y = Math.round(y);
		if (text.fieldWidth != width)
			text.fieldWidth = width;
		if (align != null && text.alignment != align)
			text.alignment = align;
		if (text.size != size)
			text.size = size;
	}

	function paintButton(btn:BrowserButton, x:Float, y:Float, w:Float, h:Float):Void
	{
		btn.x = Math.round(x);
		btn.y = Math.round(y);
		btn.w = Math.round(w);
		btn.h = Math.round(h);

		// Painting a button is what puts it on screen; the `refresh*` methods that run after
		// the layout pass are the ones that can hide it again (thin X, DELETE, SHOW ALL).
		btn.shown = true;
		btn.bg.setPosition(btn.x, btn.y);
		btn.label.x = btn.x;
		btn.label.fieldWidth = btn.w;
		paintButtonLabel(btn, btn.label.text);
	}

	function paintButtonLabel(btn:BrowserButton, text:String):Void
	{
		btn.label.text = clipText(text, btn.w - 8, _fontBody, false);
		btn.label.y = Math.round(btn.y + (btn.h - btn.label.height) / 2);
		refreshButton(btn);
	}

	/** Applies hover/press feedback, the enabled state and the colour without touching geometry. */
	function refreshButton(btn:BrowserButton):Void
	{
		if (btn == null)
			return;

		btn.bg.visible = btn.shown;
		btn.label.visible = btn.shown && btn.label.text.length > 0;

		var color:Int = buttonColor(btn);
		var iw:Int = Std.int(Math.max(1, btn.w));
		var ih:Int = Std.int(Math.max(1, btn.h));
		if (btn.bg.graphic == null || btn.bg.width != iw || btn.bg.height != ih || btn.bgColor != color)
		{
			btn.bg.makeGraphic(iw, ih, color);
			btn.bgColor = color;
		}

		btn.bg.setPosition(btn.x, btn.y);
		btn.bg.alpha = btn.held ? 0.7 : (btn.enabled ? 1 : 0.55);
		btn.label.alpha = btn.enabled ? 1 : 0.5;
	}

	/** Hover lightens a plain button; the accent and danger looks stay themselves. */
	function buttonColor(btn:BrowserButton):Int
	{
		if (btn.danger)
			return COLOR_DANGER;
		if (btn.accent)
			return COLOR_SELECTED;
		return btn.hover ? COLOR_EDGE : COLOR_BOX;
	}

	// --- Data --------------------------------------------------------------------------

	/** Re-reads the disk and the block config, then rebuilds the visible list. */
	function refresh():Void
	{
		rescan();
		refreshConfigStatus();
		applyFilter();
	}

	function rescan():Void
	{
		_all = [];
		_selected = -1;
		_scroll = 0;
		_hoverRow = -1;

		var songFolder:String = _songName.length > 0 ? Paths.formatToSongPath(_songName) : '';
		var seen:Array<String> = [];

		for (path in BlockFileIO.listScripts(_songName))
		{
			if (path == null || path.length < 1 || seen.contains(path))
				continue;
			seen.push(path);
			_all.push(makeEntry(path, songFolder));
		}
	}

	static function makeEntry(path:String, songFolder:String):ScriptEntry
	{
		var parts:Array<String> = path.split('/');
		var entry:ScriptEntry = {
			path: path,
			name: parts.length > 0 ? parts[parts.length - 1] : path,
			mod: modOf(parts),
			inSongFolder: hasSongFolder(parts, songFolder),
			size: 0,
			modified: 0
		};

		#if sys
		try
		{
			if (FileSystem.exists(path) && !FileSystem.isDirectory(path))
			{
				var stat = FileSystem.stat(path);
				entry.size = stat.size;
				if (stat.mtime != null)
					entry.modified = stat.mtime.getTime();
			}
		}
		catch (e:Dynamic)
		{
			trace('BlockFileBrowser: could not read the file info of "$path": $e');
		}
		#end

		return entry;
	}

	/**
	 * The mod folder a script belongs to, or `''` when it sits in one of the shared folders
	 * directly under `mods/` (`scripts`, `blockcode`, `data`). Paths may carry an absolute
	 * storage prefix on Android, so the last `mods` segment is the one that counts.
	 */
	static function modOf(parts:Array<String>):String
	{
		var index:Int = -1;
		for (i in 0...parts.length)
		{
			if (parts[i] == 'mods')
				index = i;
		}

		// `mods/a.lua` has no mod folder either, only a stray file.
		if (index < 0 || index + 2 >= parts.length)
			return '';

		var folder:String = parts[index + 1];
		if (folder == 'scripts' || folder == 'blockcode' || folder == 'data')
			return '';
		return folder;
	}

	static function hasSongFolder(parts:Array<String>, songFolder:String):Bool
	{
		if (songFolder.length < 1)
			return false;

		var wanted:String = songFolder.toLowerCase();
		for (i in 0...(parts.length - 1))
		{
			if (parts[i].toLowerCase() == 'data' && parts[i + 1].toLowerCase() == wanted)
				return true;
		}
		return false;
	}

	// --- Block config card -------------------------------------------------------------

	function refreshConfigStatus():Void
	{
		BlockLibrary.ensureLoaded();

		_configFiles = [];
		_configRuntime = 0;

		var signature:String = BlockConfigLoader.configSignature();
		if (signature != null)
		{
			for (raw in signature.split('\n'))
			{
				var line:String = raw.trim();
				if (line.length < 1)
					continue;

				var bar:Int = line.indexOf('|');
				if (bar < 0)
				{
					_configFiles.push(line);
					continue;
				}

				var key:String = line.substring(0, bar);
				if (key == 'runtime')
				{
					var count:Null<Int> = Std.parseInt(line.substring(bar + 1));
					_configRuntime = count == null ? 0 : count;
					continue;
				}

				// Rebuilt as `path|size|mtime`, the shape `configPathOf`/`fileStampOf` read.
				_configFiles.push(key + '|' + line.substring(bar + 1));
			}
		}

		_configErrors = BlockConfigLoader.lastErrors();
		buildCardContent();

		var visible:Int = Std.int(Math.max(CARD_MIN_LINES, Math.min(_cardVisibleLines, _cardContent.length)));
		var relayout:Bool = visible != _cardLinesUsed;

		// A config that does not load unfolds the card on its own: that is exactly the moment
		// a mod author has to see the error list. Once they fold it themselves, that wins.
		var autoOpen:Bool = _configErrors.length > 0;
		if (!_cardUserToggled && _cardOpen != autoOpen)
		{
			_cardOpen = autoOpen;
			relayout = true;
		}

		_cardLinesUsed = visible;
		clampCardScroll();

		if (relayout)
		{
			layout();
			return;
		}

		refreshCardStatus();
		refreshCardBody();
		refreshCardScrollbar();
	}

	/** The detailed lines behind the summary: block counts, scanned files, problems. */
	function buildCardContent():Void
	{
		_cardContent = [];
		_cardColors = [];

		var categories:Int = 0;
		var blocks:Int = 0;
		if (BlockLibrary.categories != null)
		{
			for (cat in BlockLibrary.categories)
			{
				if (cat == null)
					continue;
				categories++;
				if (cat.blocks != null)
					blocks += cat.blocks.length;
			}
		}

		pushCard('Blocks: ' + blocks + ' in ' + categories + ' categories - runtime: ' + _configRuntime, COLOR_TEXT);

		if (_configFiles.length < 1)
		{
			pushCard('No external block config found yet.', COLOR_WARN);
			pushCard('  add <mod>/blockcode/blocks.json or blocks.lua', COLOR_DIM);
		}
		else
		{
			for (record in _configFiles)
				pushCard('  ' + displayPath(configPathOf(record)) + fileStampOf(record), COLOR_DIM);
		}

		if (_configErrors.length < 1)
			pushCard('Every scanned config file loaded without errors.', COLOR_OK);
		else
		{
			for (message in _configErrors)
				pushCard('! ' + message, COLOR_DANGER);
		}
	}

	function pushCard(text:String, color:Int):Void
	{
		if (_cardContent.length >= CARD_LINE_POOL * 4)
			return;

		_cardContent.push(text);
		_cardColors.push(color);
	}

	/** The one line a modder acts on, plus the status stripe on the card's left edge. */
	function refreshCardStatus():Void
	{
		if (_cardSummary == null)
			return;

		var files:Int = _configFiles.length;
		var errors:Int = _configErrors.length;
		var color:Int = errors > 0 ? COLOR_DANGER : (files > 0 ? COLOR_OK : COLOR_WARN);
		var plural:String = files == 1 ? '' : 's';
		var summary:String;

		if (errors > 0)
			summary = files + ' config file' + plural + ' scanned' + SEPARATOR + errors + ' error' + (errors == 1 ? '' : 's');
		else if (files > 0)
			summary = files + ' config file' + plural + ' scanned' + SEPARATOR + '0 errors  -  tap for details';
		else
			summary = 'No block config file found  -  tap to see where one goes';

		_cardSummary.text = clipText(summary, _cardSummaryW, _fontBody);
		_cardSummary.color = color;
		_cardEdgeColor = paintTint(_cardEdge, _innerX, _cardY, CARD_EDGE_W, _cardH, color, _cardEdgeColor);
	}

	function refreshCardBody():Void
	{
		if (_cardTexts.length < 1)
			return;

		if (!_cardBodyVisible)
		{
			for (text in _cardTexts)
				text.visible = false;
			return;
		}

		var first:Int = Std.int(_cardScroll);
		if (first < 0)
			first = 0;

		for (i in 0..._cardTexts.length)
		{
			var text:FlxText = _cardTexts[i];
			var index:Int = first + i;

			if (i >= _cardLinesUsed || index >= _cardContent.length)
			{
				text.visible = false;
				continue;
			}

			text.visible = true;
			text.color = _cardColors[index];
			text.text = clipText(_cardContent[index], _cardTextW, _fontSmall, false);
			text.x = Math.round(_cardTextX);
			text.y = Math.round(_cardBodyY + _gapTight + i * _lineH);
		}
	}

	function refreshCardScrollbar():Void
	{
		if (!_cardBodyVisible || _cardScrollMax <= 0 || _cardContent.length < 1)
		{
			_cardBarBg.visible = false;
			_cardBarThumb.visible = false;
			return;
		}

		var barX:Float = _innerX + _innerW - _cardBarW;
		paint(_cardBarBg, barX, _cardBodyY, _cardBarW, _cardBodyH, COLOR_BOX);
		_cardBarBg.visible = true;

		var visible:Float = Math.max(1, _cardLinesUsed);
		var thumbH:Float = _cardBodyH * (visible / _cardContent.length);
		thumbH = FlxMath.bound(thumbH, BlockLayout.touchSize() * 0.7, _cardBodyH);

		var range:Float = Math.max(0, _cardBodyH - thumbH);
		var pct:Float = _cardScrollMax > 0 ? FlxMath.bound(_cardScroll / _cardScrollMax, 0, 1) : 0;

		paint(_cardBarThumb, barX, _cardBodyY + pct * range, _cardBarW, thumbH, COLOR_EDGE);
		_cardBarThumb.visible = true;
	}

	function clampCardScroll():Void
	{
		_cardScrollMax = Math.max(0, _cardContent.length - _cardLinesUsed);
		_cardScroll = FlxMath.bound(_cardScroll, 0, _cardScrollMax);
	}

	function toggleCard():Void
	{
		_cardOpen = !_cardOpen;
		_cardUserToggled = true;
		playSound('scrollMenu');
		layout();
	}

	/** Path part of a `configSignature()` record, which is `path|size|mtime`. */
	static function configPathOf(record:String):String
	{
		var bar:Int = record.indexOf('|');
		return bar < 0 ? record : record.substring(0, bar);
	}

	/** Human readable size of a signature record, e.g. `  12.3 KB`. */
	static function fileStampOf(record:String):String
	{
		var parts:Array<String> = record.split('|');
		if (parts.length < 2)
			return '';

		var size:Null<Int> = Std.parseInt(parts[1]);
		return size == null ? '' : '  ' + formatSize(size);
	}

	// --- Filtering ---------------------------------------------------------------------

	function applyFilter():Void
	{
		rebuildChips();

		var key:String = _filterKind + '|' + _filterMod + '|' + _search;
		if (key != _filterKey)
		{
			// A different set of files on screen: a selection from before would point at the
			// wrong entry now.
			_filterKey = key;
			_selected = -1;
			_scroll = 0;
			_hoverRow = -1;
		}

		var needle:String = _search.trim().toLowerCase();
		_filtered = [];

		for (entry in _all)
		{
			if (!matchesFilter(entry))
				continue;
			if (needle.length > 0 && entry.path.toLowerCase().indexOf(needle) < 0)
				continue;
			_filtered.push(entry);
		}

		// Newest first, then by path so the order stays stable for equal timestamps.
		_filtered.sort(function(a:ScriptEntry, b:ScriptEntry):Int
		{
			if (a.modified != b.modified)
				return a.modified > b.modified ? -1 : 1;
			return a.path < b.path ? -1 : (a.path > b.path ? 1 : 0);
		});

		if (_selected >= _filtered.length)
			_selected = -1;

		// A chip strip that needs a different number of rows moves the list, so the whole
		// panel is laid out again - which also refreshes everything below.
		var chipKey:String = _chipLabels.join('|');
		if (chipKey != _chipKey)
		{
			_chipKey = chipKey;
			layout();
			return;
		}

		refreshEmptyState();
		refreshRows();
		refreshScrollbar();
		refreshConfirm();
		refreshCount();
		refreshFooter();
	}

	function matchesFilter(entry:ScriptEntry):Bool
	{
		switch (_filterKind)
		{
			case 'song':
				return entry.inSongFolder;
			case 'mod':
				return entry.mod == _filterMod;
			case 'mods':
				return entry.mod.length > 0;
			default:
				return true;
		}
	}

	/** Builds the chip labels out of the mod folders that actually contain scripts. */
	function rebuildChips():Void
	{
		var mods:Array<String> = [];
		var counts:Map<String, Int> = new Map();
		var modTotal:Int = 0;
		var songTotal:Int = 0;

		for (entry in _all)
		{
			if (entry.inSongFolder)
				songTotal++;

			if (entry.mod.length < 1)
				continue;

			modTotal++;
			if (!counts.exists(entry.mod))
			{
				counts.set(entry.mod, 0);
				mods.push(entry.mod);
			}
			counts.set(entry.mod, counts.get(entry.mod) + 1);
		}

		// The folders with the most scripts first: those are the ones worth a chip.
		mods.sort(function(a:String, b:String):Int
		{
			var ca:Int = counts.exists(a) ? counts.get(a) : 0;
			var cb:Int = counts.exists(b) ? counts.get(b) : 0;
			if (ca != cb)
				return ca > cb ? -1 : 1;
			return a < b ? -1 : (a > b ? 1 : 0);
		});

		var labels:Array<String> = [];
		var kinds:Array<String> = [];
		var modNames:Array<String> = [];

		labels.push(countLabel('All', _all.length));
		kinds.push('all');
		modNames.push('');

		if (_songName.length > 0)
		{
			labels.push(countLabel('This song', songTotal));
			kinds.push('song');
			modNames.push('');
		}

		if (modTotal > 0)
		{
			labels.push(countLabel('All mods', modTotal));
			kinds.push('mods');
			modNames.push('');
		}

		var cap:Int = BlockLayout.compact ? 2 : MAX_MOD_CHIPS;
		var added:Int = 0;
		for (mod in mods)
		{
			if (added >= cap)
				break;

			labels.push(countLabel(shortenName(mod, 12), counts.exists(mod) ? counts.get(mod) : 0));
			kinds.push('mod');
			modNames.push(mod);
			added++;
		}

		_chipLabels = labels;
		_chipKinds = kinds;
		_chipMods = modNames;

		// A filter whose chip is gone falls back to everything.
		if (_filterKind == 'song' && !kinds.contains('song'))
			_filterKind = 'all';
		if (_filterKind == 'mods' && !kinds.contains('mods'))
			_filterKind = 'all';
		if (_filterKind == 'mod' && !modNames.contains(_filterMod))
			_filterKind = 'all';

		ensureChipButtons(labels.length);

		for (i in 0..._chipButtons.length)
		{
			_chipButtons[i].accent = isActiveChip(i);
			refreshButton(_chipButtons[i]);
		}
	}

	function ensureChipButtons(count:Int):Void
	{
		while (_chipButtons.length < count)
		{
			var btn:BrowserButton = makeButton(false, false);
			btn.shown = false;
			_chipButtons.push(btn);
		}
	}

	static function countLabel(name:String, count:Int):String
	{
		return name + ' (' + count + ')';
	}

	static function shortenName(name:String, max:Int):String
	{
		if (name.length <= max)
			return name;

		return name.substr(0, Std.int(Math.max(1, max - 3))) + '...';
	}

	function isActiveChip(index:Int):Bool
	{
		if (index < 0 || index >= _chipKinds.length)
			return false;

		if (_chipKinds[index] != _filterKind)
			return false;
		if (_filterKind == 'mod')
			return _chipMods[index] == _filterMod;
		return true;
	}

	function selectChip(index:Int):Void
	{
		if (index < 0 || index >= _chipKinds.length || _chipKinds[index].length < 1)
			return;

		var kind:String = _chipKinds[index];
		var mod:String = _chipMods[index];
		if (kind == _filterKind && mod == _filterMod)
			return;

		_filterKind = kind;
		_filterMod = mod;
		playSound('scrollMenu');
		applyFilter();
	}

	function resetFilters():Void
	{
		_search = '';
		_filterKind = 'all';
		_filterMod = '';
		playSound('scrollMenu');
		refreshSearchText();
		applyFilter();
	}

	// --- Rows --------------------------------------------------------------------------

	function refreshRows():Void
	{
		ensureRowSlots();

		var count:Int = _filtered.length;
		var step:Float = Math.max(1, _rowH + _rowGap);
		var first:Int = Std.int(Math.floor(_scroll / step));
		if (first < 0)
			first = 0;

		var rowW:Int = Std.int(Math.max(1, _rowW));

		for (slot in 0..._rows.length)
		{
			var row:BrowserRow = _rows[slot];
			var index:Int = first + slot;

			if (index >= count)
			{
				setRowVisible(row, false);
				continue;
			}

			var entry:ScriptEntry = _filtered[index];
			var y:Float = index * step - _scroll;
			if (y > _listH || y + _rowH < 0)
			{
				setRowVisible(row, false);
				continue;
			}

			var visual:Int = rowVisual(index);

			if (row.bg.graphic == null || row.bg.width != rowW || row.bg.height != Std.int(_rowH) || row.visual != visual)
			{
				row.visual = visual;
				row.bg.makeGraphic(rowW, Std.int(_rowH), rowColor(visual));
			}

			var top:Float = Math.round(y);
			var nameY:Float = top + _rowPadY;
			var detailY:Float = nameY + Math.round(_fontBody * 1.25);

			if (row.name.fieldWidth != _rowTextW)
				row.name.fieldWidth = _rowTextW;
			if (row.size.fieldWidth != _sizeBoxW)
				row.size.fieldWidth = _sizeBoxW;

			setRowVisible(row, true);
			row.bg.setPosition(0, top);

			row.name.text = clipText(entry.name, _rowTextW, _fontBody, false);
			row.name.color = COLOR_TEXT;
			row.name.setPosition(_rowTextX, nameY);

			row.detail.text = clipText(shortPath(entry.path), _rowTextW - _sizeBoxW - _gap, _fontSmall, true);
			row.detail.color = visual == 2 ? COLOR_TEXT : COLOR_DIM;
			row.detail.setPosition(_rowTextX, detailY);

			row.size.text = sizeLabel(entry);
			row.size.color = visual == 2 ? COLOR_TEXT : COLOR_DIM;
			row.size.setPosition(_rowW - _sizeBoxW - _rowTextX, detailY);
		}
	}

	/** 0 = plain row, 1 = mouse hover, 2 = selected or being pressed. */
	function rowVisual(index:Int):Int
	{
		if (_gesture == 'list' && !_pressDragged && index == _pressRow)
			return 2;
		if (index == _selected)
			return 2;
		if (index == _hoverRow && !_ptrPressed)
			return 1;
		return 0;
	}

	static function rowColor(visual:Int):Int
	{
		switch (visual)
		{
			case 1:
				return COLOR_HOVER;
			case 2:
				return COLOR_SELECTED;
			default:
				return COLOR_ROW;
		}
	}

	static function setRowVisible(row:BrowserRow, shown:Bool):Void
	{
		row.bg.visible = shown;
		row.name.visible = shown;
		row.detail.visible = shown;
		row.size.visible = shown;
	}

	static function sizeLabel(entry:ScriptEntry):String
	{
		#if sys
		if (entry.size > 0)
			return formatSize(entry.size);
		#end
		return '';
	}

	/** `mods/<mod>/scripts/foo.lua` reads as `blockcode/scripts/foo.lua` in a row. */
	static function shortPath(path:String):String
	{
		var shown:String = displayPath(path);
		if (shown.startsWith('mods/'))
			return shown.substring(5);
		return shown;
	}

	// --- Scrolling ---------------------------------------------------------------------

	/** How tall the scrollable content is right now: the rows, or the empty state. */
	function contentHeight():Float
	{
		if (_filtered.length > 0)
			return _filtered.length * (_rowH + _rowGap) - _rowGap;

		return _emptyH;
	}

	function clampScroll():Void
	{
		_contentH = contentHeight();
		_maxScroll = Math.max(0, _contentH - _listH);
		_scroll = FlxMath.bound(_scroll, 0, _maxScroll);
	}

	function refreshScrollbar():Void
	{
		_contentH = contentHeight();

		if (_contentH <= _listH || _listH <= 0)
		{
			_scrollTrack.visible = false;
			_scrollThumb.visible = false;
			_thumbY = 0;
			_thumbH = 0;
			return;
		}

		paint(_scrollTrack, _barX, 0, _barW, _listH, COLOR_BOX);
		_scrollTrack.visible = true;

		var thumbH:Float = Math.max(BlockLayout.touchSize(), _listH * (_listH / _contentH));
		if (thumbH > _listH)
			thumbH = _listH;

		var range:Float = Math.max(0, _listH - thumbH);
		var pct:Float = _maxScroll > 0 ? FlxMath.bound(_scroll / _maxScroll, 0, 1) : 0;

		_thumbH = thumbH;
		_thumbY = pct * range;

		paint(_scrollThumb, _barX, _thumbY, _barW, _thumbH, COLOR_EDGE);
		_scrollThumb.visible = true;
	}

	function scrollTo(y:Float):Void
	{
		_scroll = y;
		clampScroll();
		refreshRows();

		// The empty state is what scrolls when there are no rows at all.
		if (_filtered.length < 1)
			refreshEmptyState();

		refreshScrollbar();
	}

	// --- Header texts ------------------------------------------------------------------

	function refreshCount():Void
	{
		var total:Int = _all.length;
		var shown:Int = _filtered.length;

		if (shown == total)
			_countText.text = clipText(total + ' script' + (total == 1 ? '' : 's'), _countW, _fontSmall);
		else
			_countText.text = clipText(shown + ' of ' + total + ' shown', _countW, _fontSmall);
	}

	function refreshFooter():Void
	{
		_loadBtn.shown = true;
		_cancelBtn.shown = true;
		_deleteBtn.shown = supportsDelete() && _selected >= 0 && _confirmIndex < 0;
		_loadBtn.enabled = _selected >= 0 && _selected < _filtered.length;

		refreshButton(_loadBtn);
		refreshButton(_cancelBtn);
		refreshButton(_deleteBtn);
	}

	/** LOAD on the far right, CANCEL next to it, DELETE on the far left so it stays away from LOAD. */
	function layoutFooterButtons():Void
	{
		var loadW:Float = footerWidth('LOAD');
		var cancelW:Float = footerWidth('CANCEL');
		var deleteW:Float = footerWidth('DELETE');

		var total:Float = loadW + cancelW + deleteW + _gap * 2;
		if (total > _innerW)
		{
			var shrink:Float = Math.max(0, _innerW - _gap * 2) / Math.max(1, loadW + cancelW + deleteW);
			loadW = Math.max(BlockLayout.touchSize(), loadW * shrink);
			cancelW = Math.max(BlockLayout.touchSize(), cancelW * shrink);
			deleteW = Math.max(BlockLayout.touchSize(), deleteW * shrink);
		}

		var right:Float = _innerX + _innerW;
		paintButton(_loadBtn, right - loadW, _buttonsY, loadW, _ctlH);
		paintButtonLabel(_loadBtn, 'LOAD');

		right -= loadW + _gap;
		paintButton(_cancelBtn, right - cancelW, _buttonsY, cancelW, _ctlH);
		paintButtonLabel(_cancelBtn, 'CANCEL');

		paintButton(_deleteBtn, _innerX, _buttonsY, deleteW, _ctlH);
		paintButtonLabel(_deleteBtn, 'DELETE');
	}

	function footerWidth(label:String):Float
	{
		return Math.round(Math.max(BlockLayout.buttonWidth(label), BlockLayout.touchSize() * 1.3));
	}

	function refreshFooterText():Void
	{
		if (_hintText == null)
			return;

		if (!_hintVisible)
		{
			_hintText.visible = false;
			return;
		}

		if (_messageTimer > 0 && _message.length > 0)
		{
			_hintText.color = _messageError ? COLOR_DANGER : COLOR_WARN;
			_hintText.text = clipText(_message, _innerW, _fontSmall);
		}
		else
		{
			_hintText.color = COLOR_DIM;
			_hintText.text = clipText(footerHint(), _innerW, _fontSmall);
		}

		_hintText.visible = true;
	}

	function footerHint():String
	{
		if (_editingSearch)
			return 'Type to filter. ENTER keeps it, ESC cancels.';

		if (BlockLayout.isMobile())
			return supportsDelete() ? 'Tap to select, tap again to load. Hold to delete.' : 'Tap a script to select it, tap it again to open it.';

		return supportsDelete() ? 'Click to select, click again to load. Click and hold to delete.' : 'Click a script to select it, click it again to open it.';
	}

	function status(message:String, isError:Bool):Void
	{
		_message = message;
		_messageError = isError;
		_messageTimer = MESSAGE_TIME;
		refreshFooterText();
	}

	// --- Empty state -------------------------------------------------------------------

	/**
	 * The state a beginner meets first: either nothing is on disk yet (so the panel names
	 * the folders `BlockFileIO` writes into) or the current filter/search has no hits (so
	 * the panel offers the way back to the full list).
	 */
	function refreshEmptyState():Void
	{
		if (_emptyTitle == null)
			return;

		clampScroll();

		if (_filtered.length > 0)
		{
			_emptyTitle.visible = false;
			for (text in _emptyLines)
				text.visible = false;
			_resetBtn.shown = false;
			refreshButton(_resetBtn);
			_emptyH = 0;
			return;
		}

		buildEmptyContent();

		var x:Float = _emptyX;
		var w:Float = _emptyW;
		var y:Float = _emptyY - _scroll;

		_emptyTitle.visible = true;
		_emptyTitle.color = _emptyColors[0];
		_emptyTitle.fieldWidth = w;
		_emptyTitle.text = clipText(_emptyContent[0], w, _fontBody, false);
		_emptyTitle.setPosition(Math.round(x), Math.round(y));
		y += Math.round(_fontBody * 1.35);

		for (i in 0..._emptyLines.length)
		{
			var text:FlxText = _emptyLines[i];
			var index:Int = i + 1;

			if (index >= _emptyContent.length)
			{
				text.visible = false;
				continue;
			}

			var line:String = _emptyContent[index];
			text.visible = true;
			text.color = _emptyColors[index];
			text.fieldWidth = w;
			text.text = clipText(line, w, _fontSmall, line.length > 0 && line.charAt(0) == ' ');
			text.setPosition(Math.round(x), Math.round(y));
			y += line.length < 1 ? Math.round(_lineH * 0.6) : _lineH;
		}

		_resetBtn.shown = _all.length > 0 && (_search.length > 0 || _filterKind != 'all');
		if (_resetBtn.shown)
		{
			var label:String = 'SHOW ALL';
			var buttonW:Float = Math.max(footerWidth(label), label.length * _fontBody * CHAR_W + _pad * 2);
			y += _gap;
			paintButton(_resetBtn, x, y, buttonW, _ctlH);
			paintButtonLabel(_resetBtn, label);
			y += _ctlH;
		}
		else
		{
			refreshButton(_resetBtn);
		}

		_emptyH = Math.max(1, y - (_emptyY - _scroll)) + _pad;
		clampScroll();
	}

	function buildEmptyContent():Void
	{
		_emptyContent = [];
		_emptyColors = [];

		if (_all.length > 0)
		{
			var needle:String = _search.trim();

			if (needle.length > 0)
				pushEmpty('No script matches "' + needle + '"', COLOR_TEXT);
			else if (_filterKind == 'song')
				pushEmpty('No script in this song folder yet', COLOR_TEXT);
			else if (_filterKind == 'mod' || _filterKind == 'mods')
				pushEmpty('No script in that mod folder', COLOR_TEXT);
			else
				pushEmpty('No script matches the current filter', COLOR_TEXT);

			pushEmpty('', COLOR_DIM);
			pushEmpty('Pick ALL, or clear the search box, to list every script.', COLOR_DIM);

			if (_filterKind == 'song' && _songName.length > 0)
				pushEmpty('This song is scanned as "' + Paths.formatToSongPath(_songName) + '".', COLOR_DIM);

			return;
		}

		pushEmpty('No .lua script found yet', COLOR_TEXT);
		pushEmpty('', COLOR_DIM);
		pushEmpty('The editor loads every .lua it finds in these folders:', COLOR_DIM);

		var seen:Array<String> = [];
		for (target in BlockFileIO.execTargetsFor(_songName))
		{
			var shown:String = displayPath(target);
			if (shown.length < 1 || seen.contains(shown))
				continue;
			seen.push(shown);
			pushEmpty('   ' + shown, COLOR_DIM);
		}

		if (_songName.length < 1)
		{
			pushEmpty('', COLOR_DIM);
			pushEmpty('Open a song first to get a song folder here.', COLOR_WARN);
		}

		pushEmpty('', COLOR_DIM);
		pushEmpty('Build blocks, then press SAVE in the Save panel - the script', COLOR_DIM);
		pushEmpty('is written into one of these folders. An existing .lua can', COLOR_DIM);
		pushEmpty('just be dropped into one of them.', COLOR_DIM);
		pushEmpty('', COLOR_DIM);
		pushEmpty('Your own blocks live in <mod>/blockcode/blocks.json.', COLOR_DIM);
	}

	function pushEmpty(text:String, color:Int):Void
	{
		if (_emptyContent.length > EMPTY_LINE_POOL)
			return;

		_emptyContent.push(text);
		_emptyColors.push(color);
	}

	// --- Delete confirmation -----------------------------------------------------------

	function refreshConfirm():Void
	{
		if (_confirmTitle == null)
			return;

		var open:Bool = _confirmIndex >= 0 && _confirmIndex < _filtered.length;

		_confirmScrim.visible = open;
		_confirmCard.visible = open;
		_confirmEdge.visible = open;
		_confirmTitle.visible = open;
		_confirmName.visible = open;
		_confirmBody.visible = open;
		_yesBtn.shown = open;
		_noBtn.shown = open;

		if (!open)
		{
			refreshButton(_yesBtn);
			refreshButton(_noBtn);
			_confirmCardX = 0;
			_confirmCardY = 0;
			_confirmCardW = 0;
			_confirmCardH = 0;
			return;
		}

		var entry:ScriptEntry = _filtered[_confirmIndex];
		var backupName:String = _confirmBackup.length > 0 ? _confirmBackup : entry.name + '.bak';

		var cardW:Float = Math.min(Math.max(240, _listW * 0.86), 460 * BlockLayout.scale);
		if (cardW > _listW - _pad * 2)
			cardW = Math.max(160, _listW - _pad * 2);

		var nameH:Float = Math.round(_fontBody * 1.3);
		var bodyH:Float = _lineH * 2;
		var cardH:Float = _pad + nameH + _gapTight + nameH + _gapTight + bodyH + _gap + _ctlH + _pad;

		_confirmCardW = Math.round(cardW);
		_confirmCardH = Math.round(cardH);
		_confirmCardX = Math.round((_listW - cardW) / 2);
		_confirmCardY = Math.round((_listH - cardH) / 2);
		if (_confirmCardY < _pad)
			_confirmCardY = _pad;

		paint(_confirmScrim, 0, 0, _listW, _listH, COLOR_SCRIM);
		paint(_confirmCard, _confirmCardX, _confirmCardY, _confirmCardW, _confirmCardH, COLOR_BOX);
		paint(_confirmEdge, _confirmCardX, _confirmCardY, _confirmCardW, 3, COLOR_DANGER);

		var inner:Float = Math.max(40, _confirmCardW - _pad * 2);
		var y:Float = _confirmCardY + _pad;

		placeText(_confirmTitle, _confirmCardX + _pad, y, inner, FlxTextAlign.CENTER, _fontBody);
		_confirmTitle.text = clipText('MOVE SCRIPT TO BACKUP?', inner, _fontBody);
		y += nameH + _gapTight;

		placeText(_confirmName, _confirmCardX + _pad, y, inner, FlxTextAlign.CENTER, _fontBody);
		_confirmName.text = clipText(entry.name, inner, _fontBody);
		y += nameH + _gapTight;

		// The file itself is never deleted: it is renamed, and renaming it back restores it.
		// Both lines are clipped by hand so the two of them always fit the reserved height.
		placeText(_confirmBody, _confirmCardX + _pad, y, inner, FlxTextAlign.CENTER, _fontSmall);
		_confirmBody.text = clipText('The file is renamed to ' + backupName + '.', inner, _fontSmall)
			+ '\n'
			+ clipText('Rename it back to restore it.', inner, _fontSmall);

		var buttonW:Float = Math.max(BlockLayout.touchSize(), (_confirmCardW - _pad * 2 - _gap) / 2);
		var buttonY:Float = _confirmCardY + _confirmCardH - _pad - _ctlH;

		paintButton(_yesBtn, _confirmCardX + _pad, buttonY, buttonW, _ctlH);
		paintButtonLabel(_yesBtn, 'MOVE TO .BAK');

		paintButton(_noBtn, _confirmCardX + _pad + buttonW + _gap, buttonY, buttonW, _ctlH);
		paintButtonLabel(_noBtn, 'KEEP');
	}

	function inConfirmCard(px:Float, py:Float):Bool
	{
		if (_confirmIndex < 0 || _confirmCardW <= 0)
			return false;

		var lx:Float = px - _listX;
		var ly:Float = py - _listY;
		return lx >= _confirmCardX && lx <= _confirmCardX + _confirmCardW && ly >= _confirmCardY && ly <= _confirmCardY + _confirmCardH;
	}

	// --- File actions ------------------------------------------------------------------

	function pick(index:Int):Void
	{
		if (index < 0 || index >= _filtered.length)
			return;

		var path:String = _filtered[index].path;
		playSound('confirmMenu');

		var callback:String->Void = _pick;
		if (callback != null)
			callback(path);

		// A callback that closed the browser itself already fired `onClosed`; this is a no-op then.
		close();
	}

	function openConfirm(index:Int):Void
	{
		if (!supportsDelete() || index < 0 || index >= _filtered.length)
			return;

		_confirmIndex = index;
		_confirmBackup = fileNameOf(unusedBackupPath(_filtered[index].path));
		layoutFooterButtons();
		refreshConfirm();
		refreshFooter();
		playSound('scrollMenu');
	}

	function closeConfirm():Void
	{
		if (_confirmIndex < 0)
			return;

		_confirmIndex = -1;
		refreshConfirm();
		refreshFooter();
		refreshRows();
	}

	function deleteConfirmed():Void
	{
		var index:Int = _confirmIndex;
		closeConfirm();

		#if sys
		if (index < 0 || index >= _filtered.length)
			return;

		var entry:ScriptEntry = _filtered[index];
		var backup:String = unusedBackupPath(entry.path);
		playSound('cancelMenu');

		if (moveToBackup(entry.path, backup))
		{
			status(entry.name + ' moved to ' + fileNameOf(backup) + '.', false);
			_selected = -1;
			rescan();
			refreshConfigStatus();
			applyFilter();
		}
		else
		{
			status('Could not move ' + entry.name + ' aside.', true);
		}
		#end
	}

	/**
	 * Copies `from` to `to` and only then removes the original, so a failure at any step
	 * leaves the script exactly where it was. An existing target is never overwritten: the
	 * caller asks for a free name first.
	 */
	static function moveToBackup(from:String, to:String):Bool
	{
		#if sys
		try
		{
			if (!FileSystem.exists(from) || FileSystem.isDirectory(from))
				return false;
			if (FileSystem.exists(to))
				return false;

			File.saveContent(to, File.getContent(from));
			if (!FileSystem.exists(to))
				return false;

			FileSystem.deleteFile(from);
			return !FileSystem.exists(from);
		}
		catch (e:Dynamic)
		{
			trace('BlockFileBrowser: could not move "$from" to "$to": $e');
			return false;
		}
		#else
		return false;
		#end
	}

	/** `<file>.lua.bak`, or `.lua.bak2`, `.lua.bak3`... so an older backup is never lost. */
	static function unusedBackupPath(path:String):String
	{
		var candidate:String = path + '.bak';

		#if sys
		if (!fileExists(candidate))
			return candidate;

		var n:Int = 2;
		while (n < 100)
		{
			candidate = path + '.bak' + n;
			if (!fileExists(candidate))
				return candidate;
			n++;
		}
		return path + '.bak' + Std.int(Date.now().getTime());
		#else
		return candidate;
		#end
	}

	static function fileExists(path:String):Bool
	{
		#if sys
		try
		{
			return FileSystem.exists(path) && !FileSystem.isDirectory(path);
		}
		catch (e:Dynamic)
		{
			return false;
		}
		#else
		return false;
		#end
	}

	static function supportsDelete():Bool
	{
		#if sys
		return true;
		#else
		return false;
		#end
	}

	static function fileNameOf(path:String):String
	{
		var index:Int = path.lastIndexOf('/');
		return index < 0 ? path : path.substring(index + 1);
	}

	static function formatSize(bytes:Float):String
	{
		if (bytes < 1024)
			return Std.int(bytes) + ' B';
		if (bytes < 1024 * 1024)
			return (Math.round(bytes / 102.4) / 10) + ' KB';
		return (Math.round(bytes / 104857.6) / 10) + ' MB';
	}

	/** Cuts the absolute storage prefix Android hands out, so the path stays readable. */
	static function displayPath(path:String):String
	{
		if (path == null)
			return '';

		var slash:String = path.replace('\\', '/');
		var marker:Int = slash.lastIndexOf('/mods/');
		if (marker >= 0)
			return slash.substring(marker + 1);
		return slash;
	}

	function clipText(text:String, width:Float, fontSize:Int, keepTail:Bool = false):String
	{
		if (text == null)
			return '';

		// `CHAR_W` is an estimate, and every field the result lands in has `wordWrap` on, so
		// a line that is a character too long would wrap into a second row. Keep a margin.
		var max:Int = Std.int((width * 0.96) / (fontSize * CHAR_W));
		if (max < 4)
			max = 4;
		if (text.length <= max)
			return text;

		if (!keepTail)
			return text.substr(0, max - 3) + '...';
		return '...' + text.substring(text.length - (max - 3));
	}

	function playSound(name:String):Void
	{
		if (FlxG.sound == null)
			return;

		var sound = Paths.sound(name);
		if (sound != null)
			FlxG.sound.play(sound);
	}

	// --- Text editing ------------------------------------------------------------------

	/**
	 * Opens the editor for the search box: the in-game sheet on touch platforms, which
	 * never fights the game for the system keyboard, and the native field (hardware keyboard
	 * on desktop, browser input on HTML5, system IME elsewhere) on the rest.
	 */
	function openTextEditor():Void
	{
		if (_editingSearch)
			return;

		_editingSearch = true;
		refreshSearchText();
		refreshFooterText();

		if (useVirtualKeyboard() && _vkb != null)
		{
			_vkb.setLayout(BlockVirtualKeyboard.LAYOUT_SYMBOLS);
			_vkb.open(_search, false);
			return;
		}

		_nativeEditing = true;
		BlockSoftKeyboard.targetRect = new Rectangle(_searchBtn.x, _searchBtn.y, _searchBtn.w, _searchBtn.h);
		BlockSoftKeyboard.open(_search, false, onNativeText, onNativeClose);
	}

	static function useVirtualKeyboard():Bool
	{
		#if (android || ios)
		return true;
		#else
		return false;
		#end
	}

	/** Puts a text editor away without running the commit path again. */
	function dismissTextEditor():Void
	{
		var wasEditing:Bool = _editingSearch;

		if (_nativeEditing)
		{
			_nativeEditing = false;
			BlockSoftKeyboard.destroy();
		}

		if (_vkb != null && _vkb.isOpen())
			_vkb.close();

		_editingSearch = false;
		if (wasEditing)
			refreshSearchText();
	}

	function onNativeText(text:String):Void
	{
		_search = text == null ? '' : text;
		refreshSearchText();
		applyFilter();
	}

	function onNativeClose():Void
	{
		if (!_nativeEditing)
			return;

		_nativeEditing = false;
		_editingSearch = false;
		refreshSearchText();
		refreshFooterText();
		applyFilter();
	}

	function onVirtualKey(key:String):Void
	{
		if (_vkb == null)
			return;

		_search = _vkb.getText();
		refreshSearchText();

		switch (key)
		{
			case 'enter':
				_vkb.close();
				_editingSearch = false;
				refreshSearchText();
				refreshFooterText();
				playSound('confirmMenu');
				applyFilter();
			case 'close':
				_editingSearch = false;
				refreshSearchText();
				refreshFooterText();
				playSound('cancelMenu');
				applyFilter();
			case 'backspace', 'clear':
				playSound('cancelMenu');
				applyFilter();
			default:
				applyFilter();
		}
	}

	function onVirtualKeyboardClosed():Void
	{
		if (!_editingSearch)
			return;

		_editingSearch = false;
		refreshSearchText();
		refreshFooterText();
	}

	function refreshSearchText():Void
	{
		if (_searchText == null)
			return;

		var width:Float = _searchTextW;

		if (_editingSearch)
		{
			_searchHint.visible = false;
			_searchText.visible = true;
			_searchText.text = clipText(_search, width, _fontBody, true) + '_';
		}
		else if (_search.length > 0)
		{
			_searchHint.visible = false;
			_searchText.visible = true;
			_searchText.text = clipText(_search, width, _fontBody, true);
		}
		else
		{
			_searchText.visible = false;
			_searchHint.text = 'Search scripts';
			_searchHint.visible = true;
		}

		_clearBtn.shown = _search.length > 0 && !_editingSearch;
		refreshButton(_clearBtn);
	}

	// --- Pointer -----------------------------------------------------------------------

	function pollPointer():Void
	{
		_ptrPressed = false;
		_ptrJustPressed = false;
		_ptrJustReleased = false;

		if (pollTouch())
			return;

		if (FlxG.mouse == null)
			return;

		var pos:FlxPoint = FlxG.mouse.getScreenPosition(_overlay, _pointer);
		_ptrX = pos.x;
		_ptrY = pos.y;
		_ptrPressed = FlxG.mouse.pressed;
		_ptrJustPressed = FlxG.mouse.justPressed;
		_ptrJustReleased = FlxG.mouse.justReleased;
	}

	/** Claims the first new touch and follows it until it is lifted, then falls back to the mouse. */
	function pollTouch():Bool
	{
		#if FLX_TOUCH
		if (FlxG.touches == null || FlxG.touches.list == null)
			return false;

		if (_touchId >= 0)
		{
			for (touch in FlxG.touches.list)
			{
				if (touch == null || touch.touchPointID != _touchId)
					continue;

				var pos:FlxPoint = touch.getScreenPosition(_overlay, _pointer);
				_ptrX = pos.x;
				_ptrY = pos.y;
				_ptrPressed = touch.pressed;
				_ptrJustPressed = touch.justPressed;
				_ptrJustReleased = touch.justReleased;
				if (touch.justReleased)
					_touchId = -1;
				return true;
			}

			_touchId = -1;
		}

		for (touch in FlxG.touches.list)
		{
			if (touch == null || !touch.justPressed)
				continue;

			_touchId = touch.touchPointID;
			var pos:FlxPoint = touch.getScreenPosition(_overlay, _pointer);
			_ptrX = pos.x;
			_ptrY = pos.y;
			_ptrPressed = true;
			_ptrJustPressed = true;
			return true;
		}
		#end

		return false;
	}

	/** Mouse hover only: on a touch screen the finger is the pointer and there is no hover. */
	function updateHover():Void
	{
		var target:BrowserButton = null;
		var row:Int = -1;

		if (!BlockLayout.isMobile() && !_ptrPressed && _touchId < 0 && !_editingSearch)
		{
			target = buttonAt(_ptrX, _ptrY);
			if (target == null && _confirmIndex < 0 && _gesture.length < 1)
				row = rowAt(_ptrX, _ptrY);
		}

		if (target != _hoverButton)
		{
			if (_hoverButton != null)
			{
				_hoverButton.hover = false;
				refreshButton(_hoverButton);
			}

			_hoverButton = target;

			if (_hoverButton != null)
			{
				_hoverButton.hover = true;
				refreshButton(_hoverButton);
			}
		}

		if (row != _hoverRow)
		{
			_hoverRow = row;
			refreshRows();
		}
	}

	function handlePointer(elapsed:Float):Void
	{
		if (_ptrJustPressed)
		{
			_pressButton = null;
			_pressOutsideConfirm = false;

			var pressed:BrowserButton = buttonAt(_ptrX, _ptrY);
			if (pressed != null && pressed.enabled)
			{
				pressed.held = true;
				refreshButton(pressed);
				_pressButton = pressed;
			}
			else if (_confirmIndex >= 0 && !inConfirmCard(_ptrX, _ptrY))
			{
				// Pressing outside the confirmation card cancels it, as a modal should.
				_pressOutsideConfirm = true;
			}

			if (_pressButton == null)
				startGesture();
		}

		if (_ptrJustReleased)
		{
			var pressed:BrowserButton = _pressButton;
			_pressButton = null;

			if (pressed != null)
			{
				pressed.held = false;
				refreshButton(pressed);
				if (pressed.enabled && buttonHit(pressed, _ptrX, _ptrY))
					activateButton(pressed);
			}

			if (_pressOutsideConfirm)
			{
				_pressOutsideConfirm = false;
				playSound('cancelMenu');
				closeConfirm();
			}

			if (_gesture.length > 0)
				finishGesture();
		}
		else if (_gesture.length > 0 && _ptrPressed)
		{
			continueGesture(elapsed);
		}

		handleWheel();
	}

	function startGesture():Void
	{
		// The confirmation owns the pointer while it is up.
		if (_confirmIndex >= 0)
			return;

		if (pointerOnBar(_ptrX, _ptrY))
		{
			_gesture = 'bar';
			beginBarDrag();
			return;
		}

		if (_cardBodyVisible && _cardScrollMax > 0 && inCardBody(_ptrX, _ptrY))
		{
			_gesture = 'card';
			_pressY = _ptrY;
			_pressScroll = _cardScroll;
			_pressDragged = false;
			return;
		}

		if (!inList(_ptrX, _ptrY))
			return;

		_gesture = 'list';
		_pressRow = rowAt(_ptrX, _ptrY);
		_pressTime = 0;
		_pressY = _ptrY;
		_pressScroll = _scroll;
		_pressDragged = false;
		refreshRows();
	}

	function continueGesture(elapsed:Float):Void
	{
		var dy:Float = _ptrY - _pressY;

		switch (_gesture)
		{
			case 'bar':
				barDragTo(_ptrY);
			case 'card':
				if (!_pressDragged && Math.abs(dy) > DRAG_SLOP)
					_pressDragged = true;
				if (_pressDragged)
				{
					_cardScroll = _pressScroll - dy / Math.max(1, _lineH);
					clampCardScroll();
					refreshCardBody();
					refreshCardScrollbar();
				}
			case 'list':
				_pressTime += elapsed;
				if (!_pressDragged && Math.abs(dy) > DRAG_SLOP)
					_pressDragged = true;

				if (_pressDragged)
				{
					scrollTo(_pressScroll - dy);
				}
				else if (_pressRow >= 0 && supportsDelete() && _pressTime >= LONG_PRESS)
				{
					var index:Int = _pressRow;
					_pressRow = -1;
					_gesture = '';
					openConfirm(index);
				}
		}
	}

	function finishGesture():Void
	{
		var was:String = _gesture;
		_gesture = '';

		if (was == 'list' && !_pressDragged && _pressRow >= 0 && _confirmIndex < 0)
			tapRow(_pressRow);

		_pressRow = -1;
		_pressDragged = false;
		refreshRows();
	}

	/** Presses on the scrollbar strip: on the thumb it drags, beside it it jumps. */
	function beginBarDrag():Void
	{
		var thumbTop:Float = _listY + _thumbY;
		if (_ptrY >= thumbTop && _ptrY <= thumbTop + _thumbH && _thumbH > 0)
		{
			_barGrab = _ptrY - thumbTop;
			return;
		}

		_barGrab = _thumbH * 0.5;
		barDragTo(_ptrY);
	}

	function barDragTo(py:Float):Void
	{
		var range:Float = _listH - _thumbH;
		if (range <= 0 || _maxScroll <= 0)
			return;

		var pct:Float = FlxMath.bound((py - _listY - _barGrab) / range, 0, 1);
		scrollTo(pct * _maxScroll);
	}

	function handleWheel():Void
	{
		if (FlxG.mouse == null || FlxG.mouse.wheel == 0 || _touchId >= 0)
			return;

		var pos:FlxPoint = FlxG.mouse.getScreenPosition(_overlay, _auxPoint);

		if (_cardBodyVisible && _cardScrollMax > 0 && inCardBody(pos.x, pos.y))
		{
			_cardScroll -= FlxG.mouse.wheel;
			clampCardScroll();
			refreshCardBody();
			refreshCardScrollbar();
			return;
		}

		if (!inList(pos.x, pos.y) || _maxScroll <= 0)
			return;

		scrollTo(_scroll - FlxG.mouse.wheel * WHEEL_STEP);
	}

	function tapRow(index:Int):Void
	{
		if (index < 0 || index >= _filtered.length)
			return;

		// A second tap on the row that is already selected loads it.
		if (index == _selected)
		{
			pick(index);
			return;
		}

		_selected = index;
		playSound('scrollMenu');
		refreshRows();
		refreshFooter();
	}

	function activateButton(btn:BrowserButton):Void
	{
		if (btn == null || !btn.enabled)
			return;

		if (btn == _closeBtn || btn == _cancelBtn)
		{
			playSound('cancelMenu');
			close();
			return;
		}

		if (btn == _reloadBtn)
		{
			reloadBlockConfig();
			return;
		}

		if (btn == _cardToggle)
		{
			toggleCard();
			return;
		}

		if (btn == _loadBtn)
		{
			pick(_selected);
			return;
		}

		if (btn == _deleteBtn)
		{
			openConfirm(_selected);
			return;
		}

		if (btn == _clearBtn)
		{
			_search = '';
			refreshSearchText();
			playSound('cancelMenu');
			applyFilter();
			return;
		}

		if (btn == _resetBtn)
		{
			resetFilters();
			return;
		}

		if (btn == _searchBtn)
		{
			openTextEditor();
			return;
		}

		if (btn == _yesBtn)
		{
			deleteConfirmed();
			return;
		}

		if (btn == _noBtn)
		{
			playSound('cancelMenu');
			closeConfirm();
			return;
		}

		var chip:Int = _chipButtons.indexOf(btn);
		if (chip >= 0)
			selectChip(chip);
	}

	function buttonAt(px:Float, py:Float):BrowserButton
	{
		if (_confirmIndex >= 0)
		{
			if (buttonHit(_yesBtn, px, py))
				return _yesBtn;
			if (buttonHit(_noBtn, px, py))
				return _noBtn;
			return null;
		}

		// Last registered wins: buttons built later draw on top of the ones before them, and
		// that is what makes the clear "X" inside the search field take the tap it needs.
		var i:Int = _buttons.length - 1;
		while (i >= 0)
		{
			var btn:BrowserButton = _buttons[i];
			if (btn != null && buttonHit(btn, px, py))
				return btn;
			i--;
		}
		return null;
	}

	/** Hit test in the space of the camera that draws the button. */
	function buttonHit(btn:BrowserButton, px:Float, py:Float):Bool
	{
		if (btn == null)
			return false;

		if (btn.listSpace)
			return btn.contains(px - _listX, py - _listY);
		return btn.contains(px, py);
	}

	function inList(px:Float, py:Float):Bool
	{
		return px >= _listX && px <= _listX + _listW && py >= _listY && py <= _listY + _listH;
	}

	function inCardBody(px:Float, py:Float):Bool
	{
		if (!_cardBodyVisible)
			return false;

		return px >= _cardBodyX && px <= _cardBodyX + _cardBodyW && py >= _cardBodyY && py <= _cardBodyY + _cardBodyH;
	}

	function pointerOnBar(px:Float, py:Float):Bool
	{
		if (_maxScroll <= 0 || !inList(px, py))
			return false;

		return px >= _listX + _barX;
	}

	/** Entry index under the pointer, or `-1`. The rows are drawn in list space, so this works in list space too. */
	function rowAt(px:Float, py:Float):Int
	{
		if (!inList(px, py))
			return -1;

		var local:Float = py - _listY + _scroll;
		if (local < 0)
			return -1;

		var index:Int = Std.int(local / Math.max(1, _rowH + _rowGap));
		if (index < 0 || index >= _filtered.length)
			return -1;
		return index;
	}

	// --- Block config ------------------------------------------------------------------

	/**
	 * Re-reads every block config file and refreshes the list, which is how a mod author
	 * checks that their JSON/Lua block definitions were picked up.
	 */
	function reloadBlockConfig():Void
	{
		BlockLibrary.reload();

		var blocks:Int = 0;
		var categories:Int = 0;
		if (BlockLibrary.categories != null)
		{
			for (cat in BlockLibrary.categories)
			{
				if (cat == null)
					continue;
				categories++;
				if (cat.blocks != null)
					blocks += cat.blocks.length;
			}
		}

		refresh();

		if (_configErrors.length > 0)
		{
			playSound('cancelMenu');
			status('Reloaded ' + blocks + ' blocks, ' + _configErrors.length + ' config problem(s).', true);
		}
		else
		{
			playSound('confirmMenu');
			status('Reloaded ' + blocks + ' blocks in ' + categories + ' categories.', false);
		}
	}
}
