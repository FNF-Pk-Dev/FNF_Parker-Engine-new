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

	/** Primary action: drawn in the accent colour. */
	public var accent:Bool = false;

	public var held:Bool = false;

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

/** One pooled list row: the background plus the three text fields of a script file. */
private class BrowserRow
{
	public var bg:FlxSprite;
	public var name:FlxText;
	public var path:FlxText;
	public var size:FlxText;
	public var selected:Bool = false;

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
 * Pointer input is touch first (`FlxG.touches`) and mouse second, every press target is at
 * least 44px tall, and all disk access goes through `BlockFileIO`, `#if sys` guarded and
 * inside `try/catch`.
 */
class BlockFileBrowser extends FlxGroup
{
	// --- Theme -------------------------------------------------------------------------
	public static inline var COLOR_BG:Int = 0xFF16161E;
	public static inline var COLOR_ROW:Int = 0xFF1A1B26;
	public static inline var COLOR_SELECTED:Int = 0xFF3D59A1;
	public static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_DIM:Int = 0xFF565F89;
	public static inline var COLOR_BOX:Int = 0xFF24283B;
	public static inline var COLOR_EDGE:Int = 0xFF414868;
	public static inline var COLOR_WARN:Int = 0xFFE0AF68;
	public static inline var COLOR_DANGER:Int = 0xFFF7768E;
	public static inline var COLOR_SCRIM:Int = 0xB3000000;

	// --- Metrics -----------------------------------------------------------------------

	/** One list row. Comfortably more than the 44px a finger needs. */
	static inline var ROW_H:Float = 58;

	static inline var TITLE_H:Float = 46;
	static inline var STATUS_H:Float = 68;
	static inline var CHIP_H:Float = 54;
	static inline var SEARCH_H:Float = 56;
	static inline var FOOTER_H:Float = 60;

	/** Everything the panel reserves above and below the list. */
	static inline var FIXED_H:Float = TITLE_H + STATUS_H + CHIP_H + SEARCH_H + FOOTER_H;

	/** Shortest list the panel still gives to the rows. */
	static inline var MIN_LIST_H:Float = 72;

	static inline var MIN_PANEL_W:Float = 420;
	static inline var PAD:Float = 14;
	static inline var BUTTON_H:Float = 44;
	static inline var GAP:Float = 8;
	static inline var CHIP_GAP:Float = 6;
	static inline var MAX_CHIPS:Int = 6;
	static inline var CLOSE_W:Float = 44;
	static inline var RELOAD_W:Float = 92;
	static inline var SCROLLBAR_W:Float = 8;
	static inline var ROW_TEXT_X:Float = 12;
	static inline var SIZE_BOX_W:Float = 96;

	static inline var FONT_SMALL:Int = 12;
	static inline var FONT_BODY:Int = 14;
	static inline var FONT_TITLE:Int = 18;

	/** How long a press on a row lasts before the delete confirmation opens. */
	static inline var LONG_PRESS:Float = 0.55;

	/** How far a finger may travel before the gesture counts as a scroll instead of a tap. */
	static inline var DRAG_SLOP:Float = 8;

	static inline var WHEEL_STEP:Float = 52;

	/** Seconds a status message stays in the footer before the hint comes back. */
	static inline var MESSAGE_TIME:Float = 5;

	/** `vcr.ttf` is monospace, so the font size gives a usable estimate for clipping. */
	static inline var CHAR_W:Float = 0.62;

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

	// --- Panel geometry ----------------------------------------------------------------
	var _panelX:Float = 0;
	var _panelY:Float = 0;
	var _panelW:Float = 0;
	var _panelH:Float = 0;
	var _titleY:Float = 0;
	var _statusY:Float = 0;
	var _chipY:Float = 0;
	var _searchY:Float = 0;
	var _listX:Float = 0;
	var _listY:Float = 0;
	var _listW:Float = 0;
	var _listH:Float = 0;
	var _footerY:Float = 0;
	var _innerX:Float = 0;
	var _innerW:Float = 0;
	var _footerTextW:Float = 40;

	// --- Chrome ------------------------------------------------------------------------
	var _scrim:FlxSprite;
	var _panel:FlxSprite;
	var _titleEdge:FlxSprite;
	var _footerEdge:FlxSprite;
	var _titleText:FlxText;
	var _countText:FlxText;
	var _statusLines:Array<FlxText> = [];
	var _searchText:FlxText;
	var _searchHint:FlxText;
	var _footerText:FlxText;

	var _closeBtn:BrowserButton;
	var _reloadBtn:BrowserButton;
	var _loadBtn:BrowserButton;
	var _deleteBtn:BrowserButton;
	var _cancelBtn:BrowserButton;
	var _clearBtn:BrowserButton;
	var _searchBtn:BrowserButton;
	var _yesBtn:BrowserButton;
	var _noBtn:BrowserButton;

	var _chips:Array<BrowserButton> = [];
	var _chipTexts:Array<String> = [];
	var _chipKinds:Array<String> = [];
	var _chipMods:Array<String> = [];

	var _buttons:Array<BrowserButton> = [];

	// --- List (drawn by the list camera, so these are list-local coordinates) -----------
	var _rows:Array<BrowserRow> = [];
	var _emptyText:FlxText;
	var _scrollTrack:FlxSprite;
	var _scrollThumb:FlxSprite;
	var _confirmBg:FlxSprite;
	var _confirmTitle:FlxText;
	var _confirmBody:FlxText;
	var _confirmIndex:Int = -1;

	var _vkb:BlockVirtualKeyboard;

	// --- Data --------------------------------------------------------------------------
	var _songName:String = '';
	var _all:Array<ScriptEntry> = [];
	var _filtered:Array<ScriptEntry> = [];
	var _filterKind:String = 'all';
	var _filterMod:String = '';
	var _search:String = '';

	/** `kind|mod|search` of the last filtering, used to drop the selection when it changes. */
	var _filterKey:String = '';

	var _selected:Int = -1;
	var _scroll:Float = 0;
	var _contentH:Float = 0;
	var _maxScroll:Float = 0;

	var _configFiles:Array<String> = [];
	var _configErrors:Array<String> = [];
	var _configRuntime:Int = 0;

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

	var _gestureActive:Bool = false;
	var _pressRow:Int = -1;
	var _pressTime:Float = 0;
	var _pressY:Float = 0;
	var _pressScroll:Float = 0;
	var _pressDragged:Bool = false;
	var _pressButton:BrowserButton = null;

	var _editingSearch:Bool = false;
	var _nativeEditing:Bool = false;

	/**
	 * @param width  Width the panel should have in pixels; clamped to the screen.
	 * @param height Height the panel should have in pixels; clamped to the screen.
	 */
	public function new(width:Float, height:Float)
	{
		super();

		_requestedW = width;
		_requestedH = height;
		_pointer = FlxPoint.get();
		_auxPoint = FlxPoint.get();

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
		_gestureActive = false;
		_pressDragged = false;
		_selected = -1;
		_scroll = 0;
		detachCameras();

		if (_closed != null)
		{
			var notify:Void->Void = _closed;
			_closed = null;
			notify();
		}
	}

	/**
	 * Song the SONG chip narrows to and the song folder `BlockFileIO` scans. An empty or
	 * null name just leaves that chip out.
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

		// A resize while the panel is up has to move the cameras with it.
		if (FlxG.width != _screenW || FlxG.height != _screenH)
			layout();

		// A text editor owns the pointer while it is up, and the tap that dismisses the
		// field is deliberately swallowed instead of also selecting a row behind it.
		if (_editingSearch)
			return;

		pollPointer();
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
		_titleEdge = overlay(new FlxSprite());
		_footerEdge = overlay(new FlxSprite());

		_titleText = overlay(makeText(FONT_TITLE, COLOR_TEXT));
		_titleText.text = 'Load Lua Script';

		_countText = overlay(makeText(FONT_SMALL, COLOR_DIM));
		_countText.alignment = FlxTextAlign.RIGHT;

		for (i in 0...3)
			_statusLines.push(overlay(makeText(FONT_SMALL, COLOR_DIM)));

		_searchBtn = makeButton(false, false);
		_searchText = overlay(makeText(FONT_BODY, COLOR_TEXT));
		_searchHint = overlay(makeText(FONT_BODY, COLOR_DIM));

		_closeBtn = makeButton(false, false);
		_reloadBtn = makeButton(false, false);
		_loadBtn = makeButton(false, true);
		_deleteBtn = makeButton(true, false);
		_cancelBtn = makeButton(false, false);
		_clearBtn = makeButton(false, false);
		_footerText = overlay(makeText(FONT_SMALL, COLOR_DIM));

		for (i in 0...MAX_CHIPS)
		{
			_chips.push(makeButton(false, false));
			_chipTexts.push('');
			_chipKinds.push('');
			_chipMods.push('');
		}

		// The keyboard draws on its own camera, which is the last one added, so it is above
		// the panel whatever the member order is.
		buildKeyboard();

		// List contents, in draw order. Everything here is clipped by the list camera, which
		// is why the delete confirmation can simply cover the list.
		buildRows();
		_scrollTrack = listChild(new FlxSprite());
		_scrollThumb = listChild(new FlxSprite());
		_emptyText = listChild(makeText(FONT_SMALL, COLOR_DIM));
		_emptyText.wordWrap = true;

		_confirmBg = listChild(new FlxSprite());
		_confirmTitle = listChild(makeText(FONT_BODY, COLOR_TEXT));
		_confirmBody = listChild(makeText(FONT_SMALL, COLOR_DIM));
		_yesBtn = makeButton(true, false, true);
		_noBtn = makeButton(false, false, true);
	}

	function buildRows():Void
	{
		// One slot per row the tallest possible panel can show, plus the row cut off at the
		// bottom. Built here so the scrollbar, the empty state and the confirmation are all
		// added after the rows and therefore draw above them.
		var slots:Int = Std.int(Math.ceil(_screenH / ROW_H)) + 2;
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
		row.name = insertRowSprite(makeText(16, COLOR_TEXT));
		row.path = insertRowSprite(makeText(FONT_SMALL, COLOR_DIM));
		row.size = insertRowSprite(makeText(FONT_SMALL, COLOR_DIM));
		row.size.alignment = FlxTextAlign.RIGHT;
		row.size.fieldWidth = SIZE_BOX_W;
		setRowVisible(row, false);
		_rows.push(row);
		return row;
	}

	/** Adds one more slot when the panel got taller (a window resize while the browser is up). */
	function ensureRowSlots():Void
	{
		var needed:Int = Std.int(Math.ceil(_listH / ROW_H)) + 2;
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
		btn.bg = onListCamera ? listChild(new FlxSprite()) : overlay(new FlxSprite());
		btn.label = onListCamera ? listChild(makeText(FONT_BODY, COLOR_TEXT)) : overlay(makeText(FONT_BODY, COLOR_TEXT));
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

	function makeText(size:Int, color:Int):FlxText
	{
		var text:FlxText = new FlxText(0, 0, 0, '', size);
		text.setFormat(Paths.font('vcr.ttf'), size, color);
		return text;
	}

	// --- Layout ------------------------------------------------------------------------

	function layout():Void
	{
		syncCameras();

		var availW:Float = Math.max(MIN_PANEL_W, _screenW - 16);
		var availH:Float = Math.max(160, _screenH - 16);

		_panelW = Math.min(Math.max(_requestedW, MIN_PANEL_W), availW);
		var minPanelH:Float = FIXED_H + MIN_LIST_H;
		_panelH = Math.min(Math.max(_requestedH, minPanelH), Math.max(minPanelH, availH));
		_panelX = Math.round((_screenW - _panelW) / 2);
		_panelY = Math.round((_screenH - _panelH) / 2);

		_innerX = _panelX + PAD;
		_innerW = _panelW - PAD * 2;

		_titleY = _panelY;
		_statusY = _titleY + TITLE_H;
		_chipY = _statusY + STATUS_H;
		_searchY = _chipY + CHIP_H;
		_listX = _panelX;
		_listY = _searchY + SEARCH_H;
		_listW = _panelW;
		_footerY = _panelY + _panelH - FOOTER_H;
		_listH = Math.max(MIN_LIST_H, _footerY - _listY);

		paint(_scrim, 0, 0, _screenW, _screenH, COLOR_SCRIM);
		paint(_panel, _panelX, _panelY, _panelW, _panelH, COLOR_BG);
		paint(_titleEdge, _panelX, _titleY + TITLE_H - 1, _panelW, 1, COLOR_EDGE);
		paint(_footerEdge, _panelX, _footerY, _panelW, 1, COLOR_EDGE);

		place(_titleText, _innerX, _titleY + 12);
		place(_countText, _panelX + _panelW - PAD - CLOSE_W - 8 - 120, _titleY + 16, 120);

		// The list camera has to be resized before anything is placed inside it.
		ensureListCamera();

		layoutStatus();
		layoutChips();
		layoutSearch();
		layoutFooter();
		layoutConfirm();
		layoutList();
		refreshSearchText();
		refreshFooterText();
	}

	function layoutStatus():Void
	{
		paintButton(_closeBtn, _panelX + _panelW - PAD - CLOSE_W, _titleY + 1, CLOSE_W, CLOSE_W);
		paintButtonLabel(_closeBtn, 'X');

		paintButton(_reloadBtn, _innerX + _innerW - RELOAD_W, _statusY + 12, RELOAD_W, BUTTON_H);
		paintButtonLabel(_reloadBtn, 'RELOAD');

		var textW:Float = _innerW - RELOAD_W - 10;
		for (i in 0..._statusLines.length)
			place(_statusLines[i], _innerX, _statusY + 8 + i * 17, textW);
	}

	function layoutChips():Void
	{
		var count:Int = 0;
		for (i in 0..._chips.length)
		{
			if (_chipKinds[i].length > 0)
				count++;
		}

		if (count < 1)
			return;

		var chipW:Float = (_innerW - CHIP_GAP * (count - 1)) / count;
		if (chipW > 170)
			chipW = 170;
		if (chipW < 48)
			chipW = 48;

		var x:Float = _innerX;
		for (i in 0..._chips.length)
		{
			var btn:BrowserButton = _chips[i];
			if (_chipKinds[i].length < 1)
			{
				btn.shown = false;
				refreshButton(btn);
				continue;
			}

			paintButton(btn, x, _chipY + (CHIP_H - BUTTON_H) / 2, chipW, BUTTON_H);
			paintButtonLabel(btn, _chipTexts[i]);
			x += chipW + CHIP_GAP;
		}
	}

	function layoutSearch():Void
	{
		var boxW:Float = _innerW - CLOSE_W - GAP;
		var y:Float = _searchY + (SEARCH_H - BUTTON_H) / 2;

		paintButton(_searchBtn, _innerX, y, boxW, BUTTON_H);
		paintButtonLabel(_searchBtn, '');

		place(_searchText, _innerX + 10, y + 13, boxW - 20);
		place(_searchHint, _innerX + 10, y + 13, boxW - 20);

		paintButton(_clearBtn, _innerX + boxW + GAP, y, CLOSE_W, BUTTON_H);
		paintButtonLabel(_clearBtn, 'X');
	}

	function layoutFooter():Void
	{
		var slotW:Float = (_innerW - GAP * 2) / 3;
		if (slotW > 132)
			slotW = 132;

		var deleteShown:Bool = supportsDelete() && _selected >= 0 && _confirmIndex < 0;

		_loadBtn.shown = true;
		_cancelBtn.shown = true;
		_deleteBtn.shown = deleteShown;

		var right:Float = _innerX + _innerW;
		var y:Float = _footerY + (FOOTER_H - BUTTON_H) / 2;

		paintButton(_loadBtn, right - slotW, y, slotW, BUTTON_H);
		paintButtonLabel(_loadBtn, 'LOAD');
		_loadBtn.enabled = _selected >= 0 && _selected < _filtered.length;
		refreshButton(_loadBtn);

		right -= slotW + GAP;
		if (deleteShown)
		{
			paintButton(_deleteBtn, right - slotW, y, slotW, BUTTON_H);
			paintButtonLabel(_deleteBtn, 'DELETE');
			_deleteBtn.enabled = true;
			refreshButton(_deleteBtn);
			right -= slotW + GAP;
		}
		else
		{
			refreshButton(_deleteBtn);
		}

		paintButton(_cancelBtn, right - slotW, y, slotW, BUTTON_H);
		paintButtonLabel(_cancelBtn, 'CANCEL');
		refreshButton(_cancelBtn);

		_footerTextW = Math.max(20, right - slotW - GAP - _innerX);
		place(_footerText, _innerX, y + 13, _footerTextW);
		refreshFooterText();
	}

	function layoutConfirm():Void
	{
		if (_confirmIndex < 0)
		{
			_confirmBg.visible = false;
			_confirmTitle.visible = false;
			_confirmBody.visible = false;
			_yesBtn.shown = false;
			_noBtn.shown = false;
			refreshButton(_yesBtn);
			refreshButton(_noBtn);
			return;
		}

		paint(_confirmBg, 0, 0, _listW, _listH, COLOR_BG);
		_confirmBg.visible = true;

		var pad:Float = 12;
		var btnW:Float = Math.min(170, (_listW - pad * 3) / 2);
		var btnY:Float = _listH - pad - BUTTON_H;

		_confirmTitle.visible = true;
		place(_confirmTitle, pad, pad, _listW - pad * 2);
		_confirmBody.visible = true;
		place(_confirmBody, pad, pad + 22, _listW - pad * 2);

		_yesBtn.shown = true;
		_noBtn.shown = true;
		paintButton(_yesBtn, pad, btnY, btnW, BUTTON_H);
		paintButtonLabel(_yesBtn, 'MOVE TO .BAK');
		paintButton(_noBtn, pad * 2 + btnW, btnY, btnW, BUTTON_H);
		paintButtonLabel(_noBtn, 'KEEP');
	}

	function layoutList():Void
	{
		paint(_scrollTrack, _listW - SCROLLBAR_W, 0, SCROLLBAR_W, _listH, COLOR_BG);
		_scrollTrack.visible = false;

		place(_emptyText, 12, 12, _listW - 24 - SCROLLBAR_W);

		confirmFileName();
		clampScroll();
		refreshRows();
		refreshScrollbar();
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

	/**
	 * Sizes, positions and repaints a solid box. Every sprite passed here keeps the same
	 * colour for its whole life (only buttons change colour, and they track it themselves),
	 * so the graphic is rebuilt on the first call and when the size changed - not on every
	 * scroll frame.
	 */
	function paint(sprite:FlxSprite, x:Float, y:Float, w:Float, h:Float, color:Int):Void
	{
		var iw:Int = Std.int(Math.max(1, Math.round(w)));
		var ih:Int = Std.int(Math.max(1, Math.round(h)));
		if (sprite.graphic == null || sprite.width != iw || sprite.height != ih)
			sprite.makeGraphic(iw, ih, color);

		sprite.setPosition(Math.round(x), Math.round(y));
	}

	function place(text:FlxText, x:Float, y:Float, width:Float = 0):Void
	{
		text.x = Math.round(x);
		text.y = Math.round(y);
		if (text.fieldWidth != width)
			text.fieldWidth = width;
	}

	function paintButton(btn:BrowserButton, x:Float, y:Float, w:Float, h:Float):Void
	{
		btn.x = Math.round(x);
		btn.y = Math.round(y);
		btn.w = Math.round(w);
		btn.h = Math.round(h);

		var color:Int = btn.danger ? COLOR_DANGER : (btn.accent ? COLOR_SELECTED : COLOR_BOX);
		var iw:Int = Std.int(Math.max(1, btn.w));
		var ih:Int = Std.int(Math.max(1, btn.h));
		if (btn.bg.width != iw || btn.bg.height != ih || btn.bgColor != color)
		{
			btn.bg.makeGraphic(iw, ih, color);
			btn.bgColor = color;
		}

		btn.bg.setPosition(btn.x, btn.y);
		btn.label.x = btn.x;
		btn.label.fieldWidth = btn.w;
		paintButtonLabel(btn, btn.label.text);
		refreshButton(btn);
	}

	function paintButtonLabel(btn:BrowserButton, text:String):Void
	{
		btn.label.text = clipText(text, btn.w - 8, FONT_BODY, false);
		btn.label.y = Math.round(btn.y + (btn.h - btn.label.height) / 2);
	}

	/** Applies the press feedback and the enabled state without touching the geometry. */
	function refreshButton(btn:BrowserButton):Void
	{
		btn.bg.visible = btn.shown;
		btn.label.visible = btn.shown && btn.label.text.length > 0;
		btn.bg.alpha = btn.held ? 0.7 : (btn.enabled ? 1 : 0.55);
		btn.label.alpha = btn.enabled ? 1 : 0.5;
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
		rebuildStatusText();
	}

	function rebuildStatusText():Void
	{
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

		var width:Float = _innerW - RELOAD_W - 10;
		setStatusLine(0, clipText('Blocks: ' + blocks + ' in ' + categories + ' categories - runtime: ' + _configRuntime, width, FONT_SMALL), COLOR_TEXT);

		if (_configFiles.length > 0)
		{
			var extra:String = _configFiles.length > 1 ? '  (+' + (_configFiles.length - 1) + ' more)' : '';
			var record:String = displayPath(configPathOf(_configFiles[0])) + fileStampOf(_configFiles[0]) + extra;
			setStatusLine(1, clipText(record, width, FONT_SMALL, true), COLOR_DIM);
		}
		else
		{
			setStatusLine(1, clipText('No external block config yet - add <mod>/blockcode/blocks.json', width, FONT_SMALL), COLOR_DIM);
		}

		if (_configErrors.length > 0)
			setStatusLine(2, clipText(_configErrors.length + ' config problem(s): ' + _configErrors[0], width, FONT_SMALL), COLOR_DANGER);
		else if (_configFiles.length > 1)
			setStatusLine(2, clipText('All scanned block config files loaded without errors.', width, FONT_SMALL), COLOR_DIM);
		else
			setStatusLine(2, '', COLOR_DIM);
	}

	function setStatusLine(index:Int, text:String, color:Int):Void
	{
		if (index < 0 || index >= _statusLines.length)
			return;

		var line:FlxText = _statusLines[index];
		line.text = text;
		line.color = color;
		line.visible = text.length > 0;
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

		clampScroll();
		refreshRows();
		refreshScrollbar();
		refreshEmptyState();
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
			default:
				return true;
		}
	}

	/** Builds the filter chips out of the mod folders that actually contain scripts. */
	function rebuildChips():Void
	{
		var mods:Array<String> = [];
		var counts:Map<String, Int> = new Map();

		for (entry in _all)
		{
			if (entry.mod.length < 1)
				continue;
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

		var labels:Array<String> = ['ALL'];
		var kinds:Array<String> = ['all'];
		var modNames:Array<String> = [''];

		var songChip:Bool = _filterKind == 'song';
		for (entry in _all)
		{
			if (entry.inSongFolder)
			{
				songChip = true;
				break;
			}
		}

		if (songChip)
		{
			labels.push('SONG');
			kinds.push('song');
			modNames.push('');
		}

		for (mod in mods)
		{
			if (labels.length >= MAX_CHIPS)
				break;
			labels.push(mod.toUpperCase());
			kinds.push('mod');
			modNames.push(mod);
		}

		// A filter whose chip is gone falls back to everything.
		if (_filterKind == 'song' && !kinds.contains('song'))
			_filterKind = 'all';
		if (_filterKind == 'mod' && !modNames.contains(_filterMod))
			_filterKind = 'all';

		for (i in 0...MAX_CHIPS)
		{
			_chipTexts[i] = i < labels.length ? labels[i] : '';
			_chipKinds[i] = i < kinds.length ? kinds[i] : '';
			_chipMods[i] = i < modNames.length ? modNames[i] : '';

			var btn:BrowserButton = _chips[i];
			if (_chipKinds[i].length < 1)
			{
				btn.shown = false;
				refreshButton(btn);
				continue;
			}

			btn.accent = (_chipKinds[i] == _filterKind) && (_filterKind != 'mod' || _chipMods[i] == _filterMod);
		}

		layoutChips();
	}

	function selectChip(index:Int):Void
	{
		if (index < 0 || index >= _chips.length || _chipKinds[index].length < 1)
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

	function refreshRows():Void
	{
		ensureRowSlots();

		var count:Int = _filtered.length;
		var first:Int = Std.int(Math.floor(_scroll / ROW_H));
		if (first < 0)
			first = 0;

		var rowW:Int = Std.int(Math.max(1, _listW - SCROLLBAR_W));

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
			var y:Float = index * ROW_H - _scroll;
			var selected:Bool = index == _selected;

			if (row.bg.width != rowW || row.bg.height != Std.int(ROW_H) || row.selected != selected)
			{
				row.selected = selected;
				row.bg.makeGraphic(rowW, Std.int(ROW_H), selected ? COLOR_SELECTED : COLOR_ROW);
			}

			setRowVisible(row, true);
			row.bg.setPosition(0, Math.round(y));
			row.name.text = clipText(entry.name, rowW - ROW_TEXT_X - SIZE_BOX_W - 12, 16, false);
			row.name.setPosition(ROW_TEXT_X, Math.round(y) + 7);
			row.path.text = clipText(displayPath(entry.path), rowW - ROW_TEXT_X * 2, FONT_SMALL, true);
			row.path.color = selected ? COLOR_TEXT : COLOR_DIM;
			row.path.setPosition(ROW_TEXT_X, Math.round(y) + 31);
			row.size.text = sizeLabel(entry);
			row.size.setPosition(rowW - SIZE_BOX_W - 10, Math.round(y) + 10);
		}
	}

	static function setRowVisible(row:BrowserRow, shown:Bool):Void
	{
		row.bg.visible = shown;
		row.name.visible = shown;
		row.path.visible = shown;
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

	function refreshScrollbar():Void
	{
		_contentH = _filtered.length * ROW_H;

		if (_contentH <= _listH || _listH <= 0)
		{
			_scrollTrack.visible = false;
			_scrollThumb.visible = false;
			return;
		}

		paint(_scrollTrack, _listW - SCROLLBAR_W, 0, SCROLLBAR_W, _listH, COLOR_BG);
		_scrollTrack.visible = true;

		var thumbH:Float = Math.max(28, _listH * (_listH / _contentH));
		var range:Float = Math.max(0, _listH - thumbH);
		var pct:Float = _maxScroll > 0 ? _scroll / _maxScroll : 0;
		if (pct < 0)
			pct = 0;
		if (pct > 1)
			pct = 1;

		paint(_scrollThumb, _listW - SCROLLBAR_W, pct * range, SCROLLBAR_W, thumbH, COLOR_DIM);
		_scrollThumb.visible = true;
	}

	function refreshCount():Void
	{
		var total:Int = _all.length;
		var shown:Int = _filtered.length;

		if (shown == total)
			_countText.text = total + ' script' + (total == 1 ? '' : 's');
		else
			_countText.text = shown + ' / ' + total + ' shown';
	}

	function refreshFooter():Void
	{
		var wantDelete:Bool = supportsDelete() && _selected >= 0 && _confirmIndex < 0;
		if (_deleteBtn.shown != wantDelete)
			layoutFooter();
		else
		{
			_loadBtn.enabled = _selected >= 0 && _selected < _filtered.length;
			refreshButton(_loadBtn);
			refreshButton(_deleteBtn);
		}
	}

	function refreshFooterText():Void
	{
		if (_footerText == null)
			return;

		if (_messageTimer > 0 && _message.length > 0)
		{
			_footerText.color = _messageError ? COLOR_DANGER : COLOR_WARN;
			_footerText.text = clipText(_message, _footerTextW, FONT_SMALL);
			_footerText.visible = true;
			return;
		}

		_footerText.color = COLOR_DIM;
		_footerText.text = clipText(footerHint(), _footerTextW, FONT_SMALL);
		_footerText.visible = true;
	}

	function footerHint():String
	{
		if (_editingSearch)
			return 'Type to filter. ENTER keeps it, ESC cancels.';

		#if sys
		return 'Tap to select, tap again to load. Press and hold to delete.';
		#else
		return 'Tap a script to select it, tap it again (or press LOAD) to open it.';
		#end
	}

	function status(message:String, isError:Bool):Void
	{
		_message = message;
		_messageError = isError;
		_messageTimer = MESSAGE_TIME;
		refreshFooterText();
	}

	function refreshEmptyState():Void
	{
		if (_filtered.length > 0)
		{
			_emptyText.visible = false;
			return;
		}

		_emptyText.visible = true;

		if (_all.length > 0)
		{
			_emptyText.text = 'Nothing matches the current filter.\n\nSet the filter back to ALL, or clear the search box, to see every script.';
			return;
		}

		var lines:Array<String> = [];
		lines.push('No .lua scripts found yet.');
		lines.push('');
		lines.push('The block editor saves scripts into these folders:');

		var usable:Float = _listW - 24 - SCROLLBAR_W;
		var seen:Array<String> = [];
		for (target in BlockFileIO.execTargetsFor(_songName))
		{
			var shown:String = clipText(displayPath(target), usable - 24, FONT_SMALL, true);
			if (seen.contains(shown))
				continue;
			seen.push(shown);
			lines.push('  ' + shown);
		}

		lines.push('');
		lines.push('Build blocks and press SAVE, or drop an existing .lua into one of them.');
		lines.push('Block definitions go into <mod>/blockcode/blocks.json.');
		_emptyText.text = lines.join('\n');
	}

	function clampScroll():Void
	{
		_contentH = _filtered.length * ROW_H;
		var maxScroll:Float = _contentH - _listH;
		if (maxScroll < 0)
			maxScroll = 0;
		_maxScroll = maxScroll;

		if (_scroll < 0)
			_scroll = 0;
		if (_scroll > maxScroll)
			_scroll = maxScroll;
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
		confirmFileName();
		layoutConfirm();
		layoutFooter();
		playSound('scrollMenu');
	}

	function closeConfirm():Void
	{
		if (_confirmIndex < 0)
			return;

		_confirmIndex = -1;
		layoutConfirm();
		layoutFooter();
	}

	function confirmFileName():Void
	{
		if (_confirmTitle == null || _confirmBody == null)
			return;

		if (_confirmIndex < 0 || _confirmIndex >= _filtered.length)
		{
			_confirmTitle.text = '';
			_confirmBody.text = '';
			return;
		}

		var entry:ScriptEntry = _filtered[_confirmIndex];
		var usable:Float = _listW - 24 - SCROLLBAR_W;
		_confirmTitle.text = clipText(entry.name + ' will become ' + entry.name + '.bak', usable, FONT_BODY);
		_confirmBody.text = clipText(displayPath(entry.path), usable, FONT_SMALL, true);
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
			applyFilter();
			refreshConfigStatus();
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

		var max:Int = Std.int(width / (fontSize * CHAR_W));
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
		var width:Float = _searchBtn.w - 20;

		if (_editingSearch)
		{
			_searchHint.visible = false;
			_searchText.visible = true;
			_searchText.text = clipText(_search, width, FONT_BODY, true) + '_';
		}
		else if (_search.length > 0)
		{
			_searchHint.visible = false;
			_searchText.visible = true;
			_searchText.text = clipText(_search, width, FONT_BODY, true);
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

	function handlePointer(elapsed:Float):Void
	{
		if (_ptrJustPressed)
		{
			var pressed:BrowserButton = buttonAt(_ptrX, _ptrY);
			if (pressed != null && pressed.enabled)
			{
				pressed.held = true;
				refreshButton(pressed);
				_pressButton = pressed;
			}
			else
			{
				_pressButton = null;
			}
		}

		if (_ptrJustReleased)
		{
			var pressed:BrowserButton = _pressButton;
			_pressButton = null;

			if (pressed != null)
			{
				pressed.held = false;
				refreshButton(pressed);
				if (pressed.enabled && pressed.contains(_ptrX, _ptrY))
					activateButton(pressed);
			}
		}

		// The confirmation owns the pointer while it is up.
		if (_confirmIndex >= 0)
			return;

		handleListGesture(elapsed);
		handleWheel();
	}

	function handleListGesture(elapsed:Float):Void
	{
		if (_ptrJustPressed && inList(_ptrX, _ptrY))
		{
			_gestureActive = true;
			_pressRow = rowAt(_ptrX, _ptrY);
			_pressTime = 0;
			_pressY = _ptrY;
			_pressScroll = _scroll;
			_pressDragged = false;
		}

		if (_gestureActive && _ptrPressed)
		{
			_pressTime += elapsed;

			if (!_pressDragged && Math.abs(_ptrY - _pressY) > DRAG_SLOP)
				_pressDragged = true;

			if (_pressDragged)
			{
				_scroll = _pressScroll - (_ptrY - _pressY);
				clampScroll();
				refreshRows();
				refreshScrollbar();
			}
			else if (_pressRow >= 0 && _pressTime >= LONG_PRESS)
			{
				var index:Int = _pressRow;
				_pressRow = -1;
				openConfirm(index);
			}
		}

		if (_ptrJustReleased)
		{
			if (_gestureActive && !_pressDragged && _pressRow >= 0 && _confirmIndex < 0)
				tapRow(_pressRow);

			_gestureActive = false;
			_pressRow = -1;
			_pressDragged = false;
		}
	}

	function handleWheel():Void
	{
		if (FlxG.mouse == null || FlxG.mouse.wheel == 0 || _touchId >= 0)
			return;

		var pos:FlxPoint = FlxG.mouse.getScreenPosition(_overlay, _auxPoint);
		if (!inList(pos.x, pos.y))
			return;

		_scroll -= FlxG.mouse.wheel * WHEEL_STEP;
		clampScroll();
		refreshRows();
		refreshScrollbar();
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

		var chip:Int = _chips.indexOf(btn);
		if (chip >= 0)
			selectChip(chip);
	}

	function buttonAt(px:Float, py:Float):BrowserButton
	{
		if (_confirmIndex >= 0)
		{
			if (_yesBtn.contains(px, py))
				return _yesBtn;
			if (_noBtn.contains(px, py))
				return _noBtn;
			return null;
		}

		for (btn in _buttons)
		{
			if (btn != null && btn.contains(px, py))
				return btn;
		}
		return null;
	}

	function inList(px:Float, py:Float):Bool
	{
		return px >= _listX && px <= _listX + _listW && py >= _listY && py <= _listY + _listH;
	}

	/** Entry index under the pointer, or `-1`. The rows are drawn in list space, so this works in list space too. */
	function rowAt(px:Float, py:Float):Int
	{
		if (!inList(px, py))
			return -1;

		var local:Float = py - _listY + _scroll;
		if (local < 0)
			return -1;

		var index:Int = Std.int(local / ROW_H);
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
