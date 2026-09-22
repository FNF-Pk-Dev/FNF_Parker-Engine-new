package editors.blockcode;

import editors.blockcode.BlockTypes.BlockData;
import editors.blockcode.BlockTypes.BlockParameter;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxGroup;
import flixel.input.FlxInput.FlxInputState;
import flixel.input.keyboard.FlxKey;
import flixel.input.touch.FlxTouch;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import openfl.geom.Rectangle;

/**
 * Beginner guide for the block-code editor.
 *
 * The layout is derived from {@link BlockLayout} instead of fixed pixel constants, so the same
 * overlay is readable on a 1280x720 window, a 2340x1080 phone on its side, a 1080x2340 phone held
 * upright and an 800x1280 tablet:
 *
 * - A **left rail** carries the four sections (`Start here`, `Gestures`, `Blocks`, `Timeline`); in
 *   portrait or on a very small viewport the rail turns into a **chip row across the top**, because
 *   a column would eat a third of an upright phone.
 * - Every section is a **scrollable column of cards** instead of a wall of one-line rows. A card has
 *   a title, a wrapped body of two or three comfortable lines, an optional colour/number badge and
 *   an optional monospace snippet, so a row can breathe without wasting the screen.
 * - Card heights are measured (the text is wrapped here, with the vcr.ttf metrics, not by the
 *   engine), which is what lets the list scroll smoothly with variable-height content and never let
 *   a line run past the panel.
 * - Scrolling works by touch drag, by mouse wheel and by dragging the scrollbar (at least 10px wide,
 *   with a hit area grown to a fingertip).
 * - Everything is touch first (`FlxG.touches`), mouse second, and every control is at least
 *   {@link BlockLayout#touchSize} tall.
 *
 * Sections:
 *
 * - **Start here** - a numbered walkthrough: open the editor on a running song, drag blocks, fill the
 *   white slots, bind a stack to a timeline marker, Save, and watch Live apply it without a restart.
 * - **Gestures** - one card per thing the editor can do (drag, snap, drop a reporter into a slot,
 *   trash, pan, zoom, drag the playhead, add a marker, tap a field to raise the keyboard, long-press
 *   for the block menu, scroll a list, search the catalogue).
 * - **Blocks** - the searchable catalogue of `BlockLibrary.categories`, with a category filter chip
 *   row. Each row shows the category colour, the block name, its `description` and its parameters;
 *   tapping a row opens a detail panel with the block's Lua template (the `lua`/`hatLua` text the
 *   codegen fills in), its parameters with their defaults, and the file an external block came from.
 * - **Timeline** - how the ruler, the playhead, the markers and the generated `if curStep == N then`
 *   guard fit together.
 *
 * Shape: a `FlxGroup` of flat-colour sprites and `FlxText` sized to the `width`/`height` the caller
 * passes (its camera view), laid out in camera space (`scrollFactor 0`) so it can sit on top of a
 * running `PlayState`. The card sprites are created *before* the opaque bands (header, rail, search
 * bar, category chips, footer), so anything a card pushes past its viewport is covered by the band
 * in front of it - that is why the overlay needs no camera and no clipping of its own.
 *
 * Typing goes through `BlockSoftKeyboard` (the real IME, which is also what raises the Android/iOS
 * keyboard) when the platform has one, through `BlockVirtualKeyboard` (the in-game sheet) on touch
 * machines without an IME, and through the hardware keyboard on desktop.
 *
 * `open()` keeps the section it was last left on, forgets the search text and the selected block;
 * `close()` hides the overlay, dismisses any typing surface and fires the `onClosed` callback once,
 * whether it was closed by the CLOSE button, by ESC or by the caller.
 */
class BlockHelpOverlay extends FlxGroup
{
	// --- Theme (the editor palette, see editors.BlockCodeEditorState) --------------------------
	static inline var COLOR_BACKDROP:Int = 0xD90A0A10;
	static inline var COLOR_PANEL:Int = 0xFF16161E;
	static inline var COLOR_VIEW:Int = 0xFF0F0F14;
	static inline var COLOR_CARD:Int = 0xFF1E2030;
	static inline var COLOR_CARD_SELECTED:Int = 0xFF2B3350;
	static inline var COLOR_CHIP:Int = 0xFF252A3D;
	static inline var COLOR_CHIP_ACTIVE:Int = 0xFF3D59A1;
	static inline var COLOR_BORDER:Int = 0xFF414868;
	static inline var COLOR_ACCENT:Int = 0xFF3D59A1;
	static inline var COLOR_ACCENT_TEXT:Int = 0xFF7AA2F7;
	static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	static inline var COLOR_BODY_TEXT:Int = 0xFF9AA5CE;
	static inline var COLOR_DIM:Int = 0xFF6E7891;
	static inline var COLOR_OK:Int = 0xFF9ECE6A;
	static inline var COLOR_WARN:Int = 0xFFE0AF68;
	static inline var COLOR_DANGER:Int = 0xFFF7768E;

	// --- Sections ------------------------------------------------------------------------------
	static inline var SECTION_START:Int = 0;
	static inline var SECTION_GESTURES:Int = 1;
	static inline var SECTION_BLOCKS:Int = 2;
	static inline var SECTION_TIMELINE:Int = 3;

	/** Section labels, in rail order. */
	static var SECTION_LABELS:Array<String> = ['Start here', 'Gestures', 'Blocks', 'Timeline'];

	/** Subtitle shown under the title for the active section. */
	static var SECTION_HINTS:Array<String> = [
		'A first script in six steps.',
		'Everything you can do with a finger or a mouse.',
		'Every block that exists, and what it emits.',
		'How steps, playhead and markers fit together.'
	];

	// --- Card kinds ----------------------------------------------------------------------------
	static inline var CARD_PLAIN:String = 'plain';
	static inline var CARD_STEP:String = 'step';
	static inline var CARD_BLOCK:String = 'block';

	/** Category chip that shows every block. */
	static inline var CATEGORY_ALL:String = 'All';

	/** Pixels the mouse wheel scrolls per notch. */
	static inline var WHEEL_STEP:Float = 64;

	/** How far a finger may travel (times the touch size) before a tap becomes a scroll. */
	static inline var TAP_SLOP_RATIO:Float = 0.5;

	/** Upper bound on pooled card views per scroll area, whatever the viewport says. */
	static inline var MAX_VIEWS:Int = 48;

	/** Longest search query that is accepted. */
	static inline var MAX_QUERY:Int = 40;

	// --- View ----------------------------------------------------------------------------------
	var _viewW:Float = 0;
	var _viewH:Float = 0;
	var _initFlxW:Float = 0;
	var _initFlxH:Float = 0;
	var _builtSig:String = '';

	// --- Metrics -------------------------------------------------------------------------------
	var _scale:Float = 1;
	var _pad:Float = 8;
	var _gap:Float = 4;
	var _fontTitle:Int = 18;
	var _fontBody:Int = 15;
	var _fontSmall:Int = 13;
	var _fontTiny:Int = 11;
	var _stripeW:Float = 5;
	var _barW:Float = 12;
	var _barHitW:Float = 24;
	var _touch:Float = 34;

	// --- Panel geometry ------------------------------------------------------------------------
	var _panelX:Float = 0;
	var _panelY:Float = 0;
	var _panelW:Float = 0;
	var _panelH:Float = 0;
	var _headerH:Float = 0;
	var _footerH:Float = 0;
	var _closeX:Float = 0;
	var _closeY:Float = 0;
	var _closeW:Float = 0;
	var _closeH:Float = 0;
	var _titleY:Float = 0;
	var _subtitleY:Float = 0;
	var _footerY:Float = 0;

	// --- Rail (or chip row) --------------------------------------------------------------------
	var _railVertical:Bool = true;
	var _railX:Float = 0;
	var _railY:Float = 0;
	var _railW:Float = 0;
	var _railH:Float = 0;
	var _tabX:Array<Float> = [];
	var _tabY:Array<Float> = [];
	var _tabW:Array<Float> = [];
	var _tabH:Array<Float> = [];

	// --- Content area -------------------------------------------------------------------------
	var _contentX:Float = 0;
	var _contentY:Float = 0;
	var _contentW:Float = 0;
	var _contentH:Float = 0;
	var _textMaxW:Float = 0;

	// --- Search bar and category chips (Blocks section) ---------------------------------------
	var _searchX:Float = 0;
	var _searchY:Float = 0;
	var _searchW:Float = 0;
	var _searchH:Float = 0;
	var _catX:Float = 0;
	var _catY:Float = 0;
	var _catAreaH:Float = 0;
	var _catChipH:Float = 0;
	var _catChipX:Array<Float> = [];
	var _catChipY:Array<Float> = [];
	var _catChipW:Array<Float> = [];
	var _catNames:Array<String> = [];
	var _catLabels:Array<String> = [];

	// --- Detail panel -------------------------------------------------------------------------
	var _detailHeaderH:Float = 0;
	var _detailBackX:Float = 0;
	var _detailBackY:Float = 0;
	var _detailBackW:Float = 0;
	var _detailBackH:Float = 0;
	var _detailFull:Bool = false;
	var _detailFor:String = null;

	// --- Scroll areas -------------------------------------------------------------------------
	var _list:HelpScrollView = null;
	var _detail:HelpScrollView = null;

	// --- Document state -----------------------------------------------------------------------
	var _section:Int = SECTION_START;
	var _query:String = '';
	var _filter:String = CATEGORY_ALL;
	var _selected:BlockData = null;
	var _entries:Array<BlockData> = [];
	var _totalBlocks:Int = 0;
	var _sectionScroll:Array<Float> = [0, 0, 0, 0];

	// --- Run state ----------------------------------------------------------------------------
	var _isOpen:Bool = false;
	var _onClosed:Void->Void = null;
	var _searchFocused:Bool = false;
	var _caret:Float = 0;
	var _caretOn:Bool = false;

	// --- Widgets ------------------------------------------------------------------------------
	var _widgets:Array<FlxBasic> = [];
	var _backdrop:FlxSprite = null;
	var _panelBg:FlxSprite = null;
	var _panelEdges:Array<FlxSprite> = [];
	var _headerBand:FlxSprite = null;
	var _railBand:FlxSprite = null;
	var _footerBand:FlxSprite = null;
	var _searchBand:FlxSprite = null;
	var _catBand:FlxSprite = null;
	var _searchBox:FlxSprite = null;
	var _searchAccent:FlxSprite = null;
	var _tabBg:Array<FlxSprite> = [];
	var _tabText:Array<FlxText> = [];
	var _catChipBg:Array<FlxSprite> = [];
	var _catChipText:Array<FlxText> = [];
	var _titleText:FlxText = null;
	var _subtitleText:FlxText = null;
	var _closeBg:FlxSprite = null;
	var _closeText:FlxText = null;
	var _footerText:FlxText = null;
	var _searchText:FlxText = null;
	var _searchHint:FlxText = null;
	var _countText:FlxText = null;
	var _emptyText:FlxText = null;
	var _detailBand:FlxSprite = null;
	var _detailEdge:FlxSprite = null;
	var _detailTitle:FlxText = null;
	var _detailBackBg:FlxSprite = null;
	var _detailBackText:FlxText = null;

	// --- Pointer ------------------------------------------------------------------------------
	var _ptrPoint:FlxPoint = null;
	var _ptrX:Float = 0;
	var _ptrY:Float = 0;
	var _ptrPressed:Bool = false;
	var _ptrJustPressed:Bool = false;
	var _ptrJustReleased:Bool = false;
	var _activeTouchID:Int = -1;
	var _dragView:HelpScrollView = null;
	var _dragLastY:Float = 0;
	var _dragStartY:Float = 0;
	var _dragMoved:Bool = false;
	var _tapIndex:Int = -1;
	var _barDragView:HelpScrollView = null;
	var _barGrab:Float = 0;

	// --- Typing -------------------------------------------------------------------------------
	var _softOpen:Bool = false;
	var _virtualKb:BlockVirtualKeyboard = null;
	var _kbCam:FlxCamera = null;

	// --- Text measuring -----------------------------------------------------------------------
	var _measure:FlxText = null;
	var _charW:Map<Int, Float> = new Map();
	var _lineH:Map<Int, Float> = new Map();
	var _keyChars:Array<KeyChar> = buildKeyChars();

	// --- Public API ---------------------------------------------------------------------------

	/**
	 * Builds the overlay for a `width` x `height` view (the caller's camera size). Non-positive
	 * sizes fall back to the current viewport.
	 */
	public function new(width:Float, height:Float)
	{
		super();

		_initFlxW = FlxG.width;
		_initFlxH = FlxG.height;

		BlockLayout.ensure();
		_viewW = (width > 0) ? width : BlockLayout.width;
		_viewH = (height > 0) ? height : BlockLayout.height;
		_ptrPoint = FlxPoint.get();

		BlockLibrary.ensureLoaded();

		buildMeasure();
		createUi();

		visible = false;
	}

	/**
	 * Shows the overlay on the section it was last left on. The search box is cleared and the
	 * selected block is dropped. `onClosed` is called once, when the overlay closes again.
	 */
	public function open(onClosed:Void->Void):Void
	{
		_onClosed = onClosed;
		_isOpen = true;
		visible = true;

		_query = '';
		_searchFocused = false;
		_caretOn = false;
		_caret = 0;
		_selected = null;
		_activeTouchID = -1;
		_dragView = null;
		_barDragView = null;
		_tapIndex = -1;
		_dragMoved = false;

		for (i in 0..._sectionScroll.length)
			_sectionScroll[i] = 0;

		BlockLibrary.ensureLoaded();
		if (uiSignature() != _builtSig)
			rebuildUi();

		applyLayout();

		// Every open starts at the top of the list, whatever the last visit scrolled to.
		if (_list != null)
		{
			_list.setScroll(0);
			if (_section < _sectionScroll.length)
				_sectionScroll[_section] = 0;
		}
		if (_detail != null)
			_detail.setScroll(0);

		renderViews();
		playSound('scrollMenu');
	}

	/** Hides the overlay, drops any typing surface and fires `onClosed` (once per `open()`). */
	public function close():Void
	{
		if (!_isOpen)
			return;

		_isOpen = false;
		visible = false;
		_searchFocused = false;
		_activeTouchID = -1;
		_dragView = null;
		_barDragView = null;
		_tapIndex = -1;

		dismissTyping();

		var notify:Void->Void = _onClosed;
		_onClosed = null;
		if (notify != null)
			notify();
	}

	override public function destroy():Void
	{
		_isOpen = false;
		_onClosed = null;

		dismissTyping();
		destroyWidgets();

		_virtualKb = null;
		_kbCam = null;
		_list = null;
		_detail = null;
		_entries = [];
		_charW = new Map();
		_lineH = new Map();
		_measure = FlxDestroyUtil.destroy(_measure);
		_ptrPoint = FlxDestroyUtil.put(_ptrPoint);

		super.destroy();
	}

	// --- Per frame -----------------------------------------------------------------------------

	override public function update(elapsed:Float):Void
	{
		if (!_isOpen)
			return;

		super.update(elapsed);

		_caret += elapsed;
		if (_caret > 1)
			_caret = 0;

		var caretOn:Bool = _searchFocused && (_caret % 1.0) < 0.55;
		if (caretOn != _caretOn)
		{
			_caretOn = caretOn;
			refreshSearchText();
		}

		if (viewportChanged())
			rebuildUi();

		handleKeyboard();
		pollPointer();

		if (!pointerOverSheet())
			handlePointer();

		renderViews();
	}

	/** Metrics and layout follow a window resize / device rotation, as long as the viewport moved. */
	function viewportChanged():Bool
	{
		BlockLayout.ensure();

		if (FlxG.width == _initFlxW && FlxG.height == _initFlxH)
			return false;

		_initFlxW = FlxG.width;
		_initFlxH = FlxG.height;

		if (BlockLayout.width <= 0 || BlockLayout.height <= 0)
			return false;

		if (Math.abs(BlockLayout.width - _viewW) < 0.5 && Math.abs(BlockLayout.height - _viewH) < 0.5)
			return false;

		_viewW = BlockLayout.width;
		_viewH = BlockLayout.height;
		return true;
	}

	// --- Keyboard ------------------------------------------------------------------------------

	/** ESC, TAB, the page / home / end keys and - on desktop - typed search text. */
	function handleKeyboard():Void
	{
		if (typingOpen())
			return;

		if (FlxG.keys == null)
			return;

		pollHardwareTyping();

		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (_searchFocused)
			{
				_searchFocused = false;
				playSound('cancelMenu');
				refreshSearchText();
				return;
			}

			playSound('cancelMenu');
			close();
			return;
		}

		if (FlxG.keys.justPressed.TAB)
		{
			setSection((_section + 1) % SECTION_LABELS.length);
			return;
		}

		// Only keys the song itself does not play on: the arrows and space stay free for the notes,
		// because the help can be open on top of a running PlayState.
		if (FlxG.keys.justPressed.PAGEDOWN)
			scrollActive(_contentH);
		if (FlxG.keys.justPressed.PAGEUP)
			scrollActive(-_contentH);
		if (FlxG.keys.justPressed.HOME)
			scrollActive(-999999);
		if (FlxG.keys.justPressed.END)
			scrollActive(999999);
	}

	/** Desktop typing in the search box, used when no on-screen keyboard is up. */
	function pollHardwareTyping():Void
	{
		if (!_searchFocused || typingOpen())
			return;

		if (FlxG.keys.checkStatus(FlxKey.BACKSPACE, FlxInputState.JUST_PRESSED))
		{
			if (_query.length > 0)
				setQuery(_query.substr(0, _query.length - 1));
			return;
		}

		if (FlxG.keys.checkStatus(FlxKey.ENTER, FlxInputState.JUST_PRESSED))
		{
			_searchFocused = false;
			playSound('confirmMenu');
			refreshSearchText();
			return;
		}

		for (entry in _keyChars)
		{
			if (!FlxG.keys.checkStatus(entry.key, FlxInputState.JUST_PRESSED))
				continue;

			setQuery(_query + entry.char);
			return;
		}
	}

	static function buildKeyChars():Array<KeyChar>
	{
		var out:Array<KeyChar> = [];

		for (i in 0...26)
		{
			var letter:FlxKey = 65 + i;
			out.push({key: letter, char: String.fromCharCode(97 + i)});
		}

		for (i in 0...10)
		{
			var digit:FlxKey = 48 + i;
			out.push({key: digit, char: String.fromCharCode(48 + i)});
		}

		out.push({key: FlxKey.SPACE, char: ' '});
		out.push({key: FlxKey.MINUS, char: '-'});
		out.push({key: FlxKey.PERIOD, char: '.'});

		return out;
	}

	// --- Pointer -------------------------------------------------------------------------------

	function pollPointer():Void
	{
		_ptrPressed = false;
		_ptrJustPressed = false;
		_ptrJustReleased = false;

		var cam:FlxCamera = activeCamera();
		if (cam == null)
			return;

		#if FLX_TOUCH
		if (pollTouch(cam))
			return;
		#end

		if (FlxG.mouse == null)
			return;

		var pos:FlxPoint = FlxG.mouse.getScreenPosition(cam, _ptrPoint);
		_ptrX = pos.x;
		_ptrY = pos.y;
		_ptrPressed = FlxG.mouse.pressed;
		_ptrJustPressed = FlxG.mouse.justPressed;
		_ptrJustReleased = FlxG.mouse.justReleased;
	}

	#if FLX_TOUCH
	/** Touch first: a touch claims the overlay until it is released, then the mouse is used. */
	function pollTouch(cam:FlxCamera):Bool
	{
		if (FlxG.touches == null)
			return false;

		if (_activeTouchID >= 0)
		{
			for (touch in FlxG.touches.list)
			{
				if (touch == null || touch.touchPointID != _activeTouchID)
					continue;

				applyTouch(cam, touch);
				_ptrJustPressed = false;
				if (!_ptrPressed)
					_activeTouchID = -1;
				return true;
			}

			_activeTouchID = -1;
			return false;
		}

		for (touch in FlxG.touches.list)
		{
			if (touch == null || !touch.justPressed)
				continue;

			_activeTouchID = touch.touchPointID;
			applyTouch(cam, touch);
			_ptrJustPressed = true;
			return true;
		}

		return false;
	}

	function applyTouch(cam:FlxCamera, touch:FlxTouch):Void
	{
		var pos:FlxPoint = touch.getScreenPosition(cam, _ptrPoint);
		_ptrX = pos.x;
		_ptrY = pos.y;
		_ptrPressed = touch.pressed;
		_ptrJustReleased = touch.justReleased;
	}
	#end

	function handlePointer():Void
	{
		if (_barDragView != null)
		{
			handleBarDrag();
			return;
		}

		if (_ptrJustPressed)
		{
			_dragView = null;
			_dragMoved = false;
			_tapIndex = -1;
			_dragLastY = _ptrY;
			_dragStartY = _ptrY;

			if (hit(_closeX, _closeY, _closeW, _closeH))
			{
				playSound('cancelMenu');
				close();
				return;
			}

			for (i in 0..._tabBg.length)
			{
				if (i >= _tabX.length)
					continue;

				if (hit(_tabX[i], _tabY[i], _tabW[i], _tabH[i]))
				{
					setSection(i);
					return;
				}
			}

			if (_section == SECTION_BLOCKS)
			{
				if (hit(_searchX, _searchY, _searchW, _searchH))
				{
					focusSearch();
					return;
				}

				for (i in 0..._catChipBg.length)
				{
					if (i >= _catNames.length || i >= _catChipX.length)
						continue;

					if (!hit(_catChipX[i], _catChipY[i], _catChipW[i], _catChipH))
						continue;

					setFilter(_catNames[i]);
					return;
				}
			}

			if (_detailHeaderH > 0 && _detail != null && _detail.enabled && hit(_detailBackX, _detailBackY, _detailBackW, _detailBackH))
			{
				clearSelection();
				return;
			}

			var view:HelpScrollView = barViewAt(_ptrX, _ptrY);
			if (view != null)
			{
				_barDragView = view;
				_barGrab = _ptrY - view.thumbTop();
				return;
			}

			view = scrollViewAt(_ptrX, _ptrY);
			if (view != null)
			{
				_dragView = view;
				_tapIndex = view.cardIndexAt(_ptrY);
			}

			_searchFocused = false;
		}

		if (_dragView != null)
		{
			if (_ptrPressed)
			{
				var dy:Float = _dragLastY - _ptrY;
				_dragLastY = _ptrY;

				if (!_dragMoved && Math.abs(_ptrY - _dragStartY) > _touch * TAP_SLOP_RATIO)
					_dragMoved = true;

				if (Math.abs(dy) > 0.5)
					_dragView.scrollBy(dy);
			}

			if (_ptrJustReleased)
			{
				if (!_dragMoved && _tapIndex >= 0)
					tapCard(_dragView, _tapIndex);

				_dragView = null;
				_tapIndex = -1;
			}
		}

		if (FlxG.mouse != null && FlxG.mouse.wheel != 0)
		{
			var wheelView:HelpScrollView = scrollViewAt(_ptrX, _ptrY);
			if (wheelView != null)
				wheelView.scrollBy(-FlxG.mouse.wheel * WHEEL_STEP * _scale);
		}
	}

	function handleBarDrag():Void
	{
		var view:HelpScrollView = _barDragView;
		if (view == null)
			return;

		if (_ptrPressed)
		{
			var thumbH:Float = view.thumbHeight();
			var travel:Float = view.h - thumbH;

			if (travel > 1 && view.maxScroll > 0)
			{
				var top:Float = FlxMath.bound(_ptrY - _barGrab, view.y, view.y + travel);
				view.setScroll(((top - view.y) / travel) * view.maxScroll);
			}
		}

		if (_ptrJustReleased || !_ptrPressed)
			_barDragView = null;
	}

	/** The scroll area that contains a point in the list viewport, or null. */
	function scrollViewAt(x:Float, y:Float):HelpScrollView
	{
		if (_list != null && _list.enabled && _list.contains(x, y))
			return _list;
		if (_detail != null && _detail.enabled && _detail.contains(x, y))
			return _detail;

		return null;
	}

	/** The scroll area whose scrollbar is under the pointer (with a fingertip sized hit area). */
	function barViewAt(x:Float, y:Float):HelpScrollView
	{
		if (_list != null && _list.enabled && _list.barHit(x, y, _barHitW))
			return _list;
		if (_detail != null && _detail.enabled && _detail.barHit(x, y, _barHitW))
			return _detail;

		return null;
	}

	/** A tap on a card: block rows open the detail panel, step cards open nothing else. */
	function tapCard(view:HelpScrollView, index:Int):Void
	{
		if (index < 0 || index >= view.cards.length)
			return;

		if (view != _list)
			return;

		var card:HelpCard = view.cards[index];
		if (card == null || card.block == null)
			return;

		if (_selected != null && _selected.type == card.block.type)
		{
			clearSelection();
			return;
		}

		_selected = card.block;
		playSound('confirmMenu');
		applyLayout();
	}

	function scrollActive(delta:Float):Void
	{
		var view:HelpScrollView = (_detail != null && _detail.enabled) ? _detail : _list;
		if (view != null)
			view.scrollBy(delta);
	}

	// --- Build and layout ----------------------------------------------------------------------

	/** Tears every widget down and builds the overlay again for the current viewport metrics. */
	function rebuildUi():Void
	{
		dismissTyping();
		destroyWidgets();
		buildMeasure();
		createUi();
	}

	function createUi():Void
	{
		prepareScrollAreas();
		computeLayout();

		buildPanel();
		buildScrollAreas();
		buildRail();
		buildHeader();
		buildFooter();
		buildSearchBar();
		buildCategoryChips();
		buildDetailHeader();
		buildPanelEdges();

		layoutWidgets();
		refreshSection();
		_builtSig = uiSignature();
	}

	/** Recomputes the geometry and puts every widget back on it. Cards are rebuilt as well. */
	function applyLayout():Void
	{
		computeLayout();
		layoutWidgets();
		refreshSection();
	}

	/** Everything that changes the widget count: the viewport and the catalogue it lists. */
	function uiSignature():String
	{
		var cats:String = '';
		for (cat in BlockLibrary.categories)
		{
			if (cat == null)
				continue;

			cats += cat.name + ':' + ((cat.blocks != null) ? cat.blocks.length : 0) + ';';
		}

		return Std.int(_viewW) + 'x' + Std.int(_viewH) + '|' + Std.int(BlockLayout.scale * 100) + '|' + cats;
	}

	/**
	 * Turns the current viewport into the panel, rail / chip row, content and scroll area rects.
	 * Runs before every widget creation and after every section or selection change.
	 */
	function computeLayout():Void
	{
		_scale = BlockLayout.scale;
		_touch = BlockLayout.touchSize();
		_pad = Math.max(6, BlockLayout.spacing('normal'));
		_gap = BlockLayout.spacing('tight');
		_fontTitle = BlockLayout.font('title');
		_fontBody = BlockLayout.font('body');
		_fontSmall = BlockLayout.font('small');
		_fontTiny = BlockLayout.font('tiny');
		_stripeW = Math.max(4, 5 * _scale);
		_barW = FlxMath.bound(10 * _scale, 10, 18);
		_barHitW = Math.max(_barW + 6 * _scale, _touch * 0.6);

		var size:{w:Float, h:Float} = BlockLayout.panelSize();
		_panelW = Math.max(260, size.w);
		_panelH = Math.max(220, size.h);
		_panelX = Math.max(0, (_viewW - _panelW) * 0.5);
		_panelY = Math.max(0, (_viewH - _panelH) * 0.5);

		// Header: title, subtitle and a CLOSE button that is at least a fingertip tall.
		_closeH = Math.max(_touch, BlockLayout.buttonHeight());
		_closeW = Math.min(Math.max(BlockLayout.buttonWidth('Close'), _touch * 1.6), _panelW * 0.34);
		var headerText:Float = _pad + lineHeight(_fontTitle) + _gap * 0.5 + lineHeight(_fontSmall) + _pad;
		_headerH = FlxMath.bound(Math.max(_closeH + _pad * 2, headerText), _closeH + _pad, _panelH * 0.3);

		_closeX = _panelX + _panelW - _pad - _closeW;
		_closeY = _panelY + (_headerH - _closeH) * 0.5;
		_titleY = _panelY + (_headerH - (lineHeight(_fontTitle) + _gap * 0.5 + lineHeight(_fontSmall))) * 0.5;
		_subtitleY = _titleY + lineHeight(_fontTitle) + _gap * 0.5;

		_footerH = Math.max(BlockLayout.statusHeight(), lineHeight(_fontTiny) * 1.7) + _gap;
		_footerY = _panelY + _panelH - _footerH + _gap * 0.5;

		var innerY:Float = _panelY + _headerH + _gap;
		var innerBottom:Float = _panelY + _panelH - _footerH - _gap;
		var innerH:Float = Math.max(60, innerBottom - innerY);

		// The rail only fits in landscape on a wide enough panel; everywhere else the sections are a
		// chip row across the top, which is what a thumb can actually reach on a phone.
		_railVertical = !BlockLayout.portrait && !BlockLayout.compact && _panelW >= 500;
		var tabH:Float = Math.max(_touch, BlockLayout.buttonHeight());
		var chipRowH:Float = 0;

		if (_railVertical)
		{
			_railW = FlxMath.bound(BlockLayout.buttonWidth('Start here') * 1.08, 88, _panelW * 0.32);
			_railX = _panelX + _pad;
			_railY = innerY;
			_railH = innerH;
			contentRect(_railX + _railW + _gap, innerY, Math.max(140, _panelX + _panelW - _pad - (_railX + _railW + _gap)), innerH);
		}
		else
		{
			_railX = _panelX + _pad;
			_railY = innerY;
			_railW = Math.max(140, _panelW - _pad * 2);
			var chipRows:Int = packChips(SECTION_LABELS, _railX, _railY, _railW, tabH, _gap, 2, _tabX, _tabY, _tabW);
			chipRowH = (chipRows > 0) ? (chipRows * (tabH + _gap) - _gap) : 0;
			_railH = chipRowH;
			contentRect(_panelX + _pad, innerY + chipRowH + _gap, Math.max(140, _panelW - _pad * 2), Math.max(60, innerBottom - (innerY + chipRowH + _gap)));
		}

		if (_railVertical)
			packChips(SECTION_LABELS, _railX, _railY, _railW, tabH, _gap, SECTION_LABELS.length, _tabX, _tabY, _tabW);

		_tabH = [];
		for (i in 0..._tabX.length)
			_tabH.push(tabH);

		// Category filter chips and the search bar only exist on the Blocks section, but their rects
		// are computed anyway so the widgets keep their identity when the section changes.
		buildCategoryNames();
		_searchH = Math.max(_touch + 4 * _scale, 38 * _scale);
		_searchX = _contentX;
		_searchY = _contentY;
		_searchW = _contentW;
		_catChipH = Math.max(_touch * 0.85, 32 * _scale);
		_catX = _contentX;
		_catY = _searchY + _searchH + _gap;
		var catRows:Int = packChips(_catLabels, _catX, _catY, _contentW, _catChipH, _gap, 2, _catChipX, _catChipY, _catChipW);
		_catAreaH = (catRows > 0) ? (catRows * (_catChipH + _gap) - _gap) : 0;

		var listTop:Float = (_section == SECTION_BLOCKS) ? (_catY + _catAreaH + _gap) : _contentY;
		layoutScrollAreas(listTop, Math.max(60, _contentY + _contentH - listTop));
	}

	function contentRect(x:Float, y:Float, w:Float, h:Float):Void
	{
		_contentX = x;
		_contentY = y;
		_contentW = w;
		_contentH = h;
	}

	/**
	 * Splits the content area between the card list and the block detail panel. When the two cannot
	 * both breathe (a small window, a phone on its side), the detail takes the whole area instead.
	 */
	function layoutScrollAreas(top:Float, height:Float):Void
	{
		var barSpace:Float = _barW + Math.max(3, _gap * 0.5);
		var detailOn:Bool = (_section == SECTION_BLOCKS) && (_selected != null);

		_detailFull = false;
		_detailHeaderH = 0;

		var listH:Float = height;
		var detailY:Float = top;
		var detailH:Float = 0;

		if (detailOn)
		{
			var wanted:Float = height * 0.38;
			var floorH:Float = Math.max(_touch * 3.4, 150 * _scale);
			var ceiling:Float = Math.max(floorH, height * 0.62);
			detailH = FlxMath.bound(wanted, Math.min(floorH, ceiling), ceiling);

			if (height - detailH - _gap < Math.max(_touch * 1.6, 64 * _scale))
			{
				_detailFull = true;
				detailH = height;
			}
			else
				listH = height - detailH - _gap;

			detailY = top + height - detailH;

			_detailBackH = Math.max(_touch * 0.9, 30 * _scale);
			_detailBackW = Math.min(Math.max(BlockLayout.buttonWidth('Back'), _touch * 2), _contentW * 0.32);
			_detailHeaderH = Math.max(_detailBackH + _gap * 0.5, lineHeight(_fontSmall) + _pad);
			_detailBackX = _contentX + _contentW - _pad - _detailBackW;
			_detailBackY = detailY + (_detailHeaderH - _detailBackH) * 0.5;
		}

		_list.cardGap = _gap;
		_detail.cardGap = _gap;
		_list.setRect(_contentX, top, _contentW, listH, barSpace);
		if (detailOn)
			_detail.setRect(_contentX, detailY + _detailHeaderH, _contentW, Math.max(40, detailH - _detailHeaderH), barSpace);
		else
			_detail.setRect(_contentX, top, _contentW, 0, barSpace);

		// Text column: the card width minus its own padding, and never wider than a comfortable line.
		var avail:Float = Math.max(80, _list.cardW - (_pad * 2 + _stripeW + _gap * 1.5));
		_textMaxW = Math.min(avail, 96 * charWidth(_fontSmall));
	}

	/** Every category of the catalogue plus the "All" chip, as the filter row shows them. */
	function buildCategoryNames():Void
	{
		var names:Array<String> = [CATEGORY_ALL];
		var labels:Array<String> = ['All blocks'];

		for (cat in BlockLibrary.categories)
		{
			if (cat == null || cat.name == null)
				continue;

			names.push(cat.name);
			labels.push(cat.name);
		}

		_catNames = names;
		_catLabels = labels;

		if (_filter != CATEGORY_ALL && names.indexOf(_filter) == -1)
			_filter = CATEGORY_ALL;
	}

	/**
	 * Packs chips into rows no wider than `w`, shrinking them (never below a thumb) until they fit
	 * `maxRows`. Returns how many rows were used.
	 */
	function packChips(labels:Array<String>, x:Float, y:Float, w:Float, h:Float, gap:Float, maxRows:Int, outX:Array<Float>, outY:Array<Float>,
			outW:Array<Float>):Int
	{
		outX.resize(0);
		outY.resize(0);
		outW.resize(0);

		if (labels == null || labels.length == 0)
			return 0;

		var minW:Float = Math.max(_touch * 0.9, 44 * _scale);
		var widths:Array<Float> = [];
		for (label in labels)
			widths.push(FlxMath.bound(BlockLayout.buttonWidth(label), minW, w));

		var rows:Array<Array<Int>> = [];
		for (attempt in 0...8)
		{
			rows = greedyRows(widths, w, gap);
			if (rows.length <= maxRows)
				break;

			var factor:Float = Math.max(0.5, (maxRows / rows.length) * 0.96);
			for (i in 0...widths.length)
				widths[i] = Math.max(minW, widths[i] * factor);
		}

		var rowY:Float = y;
		for (row in rows)
		{
			var used:Float = gap * Math.max(0, row.length - 1);
			for (i in row)
				used += widths[i];

			var cursor:Float = x + Math.max(0, (w - used) * 0.5);
			for (i in row)
			{
				outX.push(cursor);
				outY.push(rowY);
				outW.push(widths[i]);
				cursor += widths[i] + gap;
			}

			rowY += h + gap;
		}

		return rows.length;
	}

	static function greedyRows(widths:Array<Float>, w:Float, gap:Float):Array<Array<Int>>
	{
		var rows:Array<Array<Int>> = [];
		var row:Array<Int> = null;
		var used:Float = 0;

		for (i in 0...widths.length)
		{
			var need:Float = widths[i] + ((row != null && row.length > 0) ? gap : 0);
			if (row == null || used + need > w)
			{
				row = [];
				rows.push(row);
				used = 0;
				need = widths[i];
			}

			row.push(i);
			used += need;
		}

		return rows;
	}

	// --- Widget construction -------------------------------------------------------------------

	function buildPanel():Void
	{
		_backdrop = makeRect(0, 0, _viewW, _viewH, COLOR_BACKDROP);
		_panelBg = makeRect(_panelX, _panelY, _panelW, _panelH, COLOR_PANEL);
	}

	/**
	 * The two scroll areas, in draw order: the list background, its card pool and its frame, then the
	 * opaque detail panel in front of them (which is what hides list cards that overhang), then the
	 * detail's own card pool.
	 */
	function buildScrollAreas():Void
	{
		_list.bg = makeRect(0, 0, 16, 16, COLOR_VIEW);
		createViews(_list, poolSize(_list.h));
		_list.topLine = makeRect(0, 0, 16, 1, COLOR_BORDER);
		_list.bottomLine = makeRect(0, 0, 16, 1, COLOR_BORDER);
		_list.track = makeRect(0, 0, _barW, 16, COLOR_VIEW);
		_list.thumb = makeRect(0, 0, _barW, 16, COLOR_CHIP);

		_detailBand = makeRect(0, 0, 16, 16, COLOR_PANEL);
		_detail.bg = makeRect(0, 0, 16, 16, COLOR_VIEW);
		createViews(_detail, poolSize(_detail.h));
		_detail.topLine = makeRect(0, 0, 16, 1, COLOR_BORDER);
		_detail.bottomLine = makeRect(0, 0, 16, 1, COLOR_BORDER);
		_detail.track = makeRect(0, 0, _barW, 16, COLOR_VIEW);
		_detail.thumb = makeRect(0, 0, _barW, 16, COLOR_CHIP);
		_detailEdge = makeRect(0, 0, 16, 3, COLOR_ACCENT);
	}

	/** The scroll areas exist before `computeLayout()` so it can hand them their rects. */
	function prepareScrollAreas():Void
	{
		_list = new HelpScrollView();
		_detail = new HelpScrollView();
	}

	/**
	 * Pool size: the most cards that can be on screen at once, using the shortest card the builders
	 * can produce as the lower bound, so nothing ever needs a view created after the bands exist.
	 */
	function poolSize(viewH:Float):Int
	{
		var minCardH:Float = _pad * 2 + lineHeight(_fontBody) + _gap + lineHeight(_fontSmall);
		var count:Int = Math.ceil(Math.max(60, viewH) / Math.max(24, minCardH)) + 2;

		return Std.int(FlxMath.bound(count, 3, MAX_VIEWS));
	}

	function createViews(view:HelpScrollView, count:Int):Void
	{
		for (i in 0...count)
		{
			var card:HelpCardView = new HelpCardView();
			card.bg = makeRect(0, 0, 32, 32, FlxColor.WHITE);
			card.stripe = makeRect(0, 0, 8, 32, FlxColor.WHITE);
			card.swatch = makeRect(0, 0, 16, 16, FlxColor.WHITE);
			card.badgeBg = makeRect(0, 0, 16, 16, FlxColor.WHITE);
			card.badgeText = makeLabel(_fontBody, FlxColor.WHITE);
			card.title = makeLabel(_fontBody, COLOR_TEXT);
			card.body = makeLabel(_fontSmall, COLOR_BODY_TEXT);
			card.luaBg = makeRect(0, 0, 16, 16, FlxColor.WHITE);
			card.luaText = makeLabel(_fontTiny, COLOR_ACCENT_TEXT);
			card.hide();
			view.views.push(card);
		}
	}

	function buildRail():Void
	{
		_railBand = makeRect(0, 0, 16, 16, COLOR_PANEL);

		for (i in 0...SECTION_LABELS.length)
		{
			_tabBg.push(makeRect(0, 0, 16, 16, COLOR_CHIP));
			_tabText.push(makeLabel(_fontSmall, COLOR_DIM));
		}
	}

	function buildHeader():Void
	{
		_headerBand = makeRect(0, 0, 16, 16, COLOR_PANEL);
		_titleText = makeLabel(_fontTitle, COLOR_TEXT);
		_subtitleText = makeLabel(_fontSmall, COLOR_ACCENT_TEXT);
		_closeBg = makeRect(0, 0, 16, 16, COLOR_ACCENT);
		_closeText = makeLabel(_fontBody, FlxColor.WHITE);
		setText(_closeText, 'CLOSE');
	}

	function buildFooter():Void
	{
		_footerBand = makeRect(0, 0, 16, 16, COLOR_PANEL);
		_footerText = makeLabel(_fontTiny, COLOR_DIM);
	}

	function buildSearchBar():Void
	{
		_searchBand = makeRect(0, 0, 16, 16, COLOR_PANEL);
		_searchBox = makeRect(0, 0, 16, 16, COLOR_VIEW);
		_searchAccent = makeRect(0, 0, 4, 16, COLOR_ACCENT);
		_searchText = makeLabel(_fontBody, COLOR_TEXT);
		_searchHint = makeLabel(_fontBody, COLOR_DIM);
		_countText = makeLabel(_fontTiny, COLOR_DIM);
		_countText.alignment = RIGHT;
	}

	function buildCategoryChips():Void
	{
		_catBand = makeRect(0, 0, 16, 16, COLOR_PANEL);

		for (i in 0..._catNames.length)
		{
			_catChipBg.push(makeRect(0, 0, 16, 16, COLOR_CHIP));
			var label:FlxText = makeLabel(_fontSmall, COLOR_DIM);
			label.alignment = CENTER;
			_catChipText.push(label);
		}

		_emptyText = makeLabel(_fontSmall, COLOR_DIM);
		_emptyText.alignment = CENTER;
	}

	function buildDetailHeader():Void
	{
		_detailTitle = makeLabel(_fontSmall, COLOR_ACCENT_TEXT);
		setText(_detailTitle, 'BLOCK DETAILS');
		_detailBackBg = makeRect(0, 0, 16, 16, COLOR_CHIP);
		_detailBackText = makeLabel(_fontSmall, COLOR_TEXT);
		_detailBackText.alignment = CENTER;
		setText(_detailBackText, 'Close');
	}

	/** The accent edges go on last so nothing can paint over the panel border. */
	function buildPanelEdges():Void
	{
		_panelEdges.push(makeRect(0, 0, 16, 3, COLOR_ACCENT));
		_panelEdges.push(makeRect(0, 0, 16, 3, COLOR_ACCENT));
	}

	/** Places every persistent widget on the rects {@link computeLayout} produced. */
	function layoutWidgets():Void
	{
		sizeOf(_backdrop, _viewW, _viewH);
		place(_backdrop, 0, 0);

		place(_panelBg, _panelX, _panelY);
		sizeOf(_panelBg, _panelW, _panelH);

		if (_panelEdges.length > 0)
		{
			place(_panelEdges[0], _panelX, _panelY);
			sizeOf(_panelEdges[0], _panelW, 3);
		}
		if (_panelEdges.length > 1)
		{
			place(_panelEdges[1], _panelX, _panelY + _panelH - 3);
			sizeOf(_panelEdges[1], _panelW, 3);
		}

		place(_headerBand, _panelX, _panelY);
		sizeOf(_headerBand, _panelW, _headerH);
		setText(_titleText, 'BLOCK EDITOR HELP');
		place(_titleText, _panelX + _pad, _titleY);
		setText(_subtitleText, SECTION_HINTS[_section]);
		place(_subtitleText, _panelX + _pad, _subtitleY);

		place(_closeBg, _closeX, _closeY);
		sizeOf(_closeBg, _closeW, _closeH);
		setFieldWidth(_closeText, _closeW);
		place(_closeText, _closeX, _closeY + (_closeH - lineHeight(_fontBody)) * 0.5);

		place(_footerBand, _panelX, _panelY + _panelH - _footerH);
		sizeOf(_footerBand, _panelW, _footerH - 3);
		setText(_footerText, footerHint());
		place(_footerText, _panelX + _pad, _footerY);

		place(_railBand, _railX - _pad * 0.5, _railY - _gap * 0.5);
		sizeOf(_railBand, (_railVertical ? _railW + _pad : _railW + _pad * 2), _railH + _gap);

		for (i in 0..._tabBg.length)
		{
			if (i >= _tabX.length)
			{
				_tabBg[i].visible = false;
				_tabText[i].visible = false;
				continue;
			}

			place(_tabBg[i], _tabX[i], _tabY[i]);
			sizeOf(_tabBg[i], _tabW[i], _tabH[i]);
			_tabText[i].alignment = _railVertical ? LEFT : CENTER;
			setFieldWidth(_tabText[i], _railVertical ? 0 : _tabW[i]);
			setText(_tabText[i], fitText(SECTION_LABELS[i], _tabW[i] - _pad * (_railVertical ? 0.5 : 1)));
			place(_tabText[i], _tabX[i] + (_railVertical ? _pad * 0.5 : 0), _tabY[i] + (_tabH[i] - lineHeight(_fontSmall)) * 0.5);
		}

		place(_searchBand, _contentX - _pad, _contentY - _gap);
		sizeOf(_searchBand, _contentW + _pad * 2, _searchH + _gap * 2);

		place(_searchBox, _searchX, _searchY);
		sizeOf(_searchBox, _searchW, _searchH);
		place(_searchAccent, _searchX, _searchY);
		sizeOf(_searchAccent, Math.max(3, 4 * _scale), _searchH);
		setFieldWidth(_searchText, 0);
		place(_searchText, _searchX + _pad, _searchY + (_searchH - lineHeight(_fontBody)) * 0.5);
		setText(_searchHint, BlockLayout.isMobile() ? 'Search blocks: tap here and type' : 'Search blocks: click here and type');
		place(_searchHint, _searchX + _pad, _searchY + (_searchH - lineHeight(_fontBody)) * 0.5);
		setFieldWidth(_countText, Math.min(_searchW * 0.55, 220 * _scale));
		place(_countText, _searchX
			+ _searchW
			- Math.min(_searchW * 0.55, 220 * _scale)
			- _pad, _searchY
			+ (_searchH - lineHeight(_fontTiny)) * 0.5);

		place(_catBand, _contentX - _pad, _catY - _gap);
		sizeOf(_catBand, _contentW + _pad * 2, Math.max(_gap, _catAreaH + _gap));

		for (i in 0..._catChipBg.length)
		{
			if (i >= _catChipX.length || i >= _catNames.length)
			{
				_catChipBg[i].visible = false;
				_catChipText[i].visible = false;
				continue;
			}

			place(_catChipBg[i], _catChipX[i], _catChipY[i]);
			sizeOf(_catChipBg[i], _catChipW[i], _catChipH);
			setFieldWidth(_catChipText[i], _catChipW[i]);
			setText(_catChipText[i], fitText(_catLabels[i], _catChipW[i] - _pad));
			place(_catChipText[i], _catChipX[i], _catChipY[i] + (_catChipH - lineHeight(_fontSmall)) * 0.5);
		}

		placeScrollArea(_list);
		placeScrollArea(_detail);

		if (_detail != null)
		{
			place(_detailBand, _detail.x, _detail.y);
			sizeOf(_detailBand, _detail.w, Math.max(1, _detail.h));
			place(_detailEdge, _detail.x, _detail.y);
			sizeOf(_detailEdge, _detail.w, 3);
		}

		if (_detailHeaderH > 0 && _detail != null)
		{
			setText(_detailTitle, 'BLOCK DETAILS');
			place(_detailTitle, _contentX + _pad, _detailBackY + (_detailBackH - lineHeight(_fontSmall)) * 0.5);
			place(_detailBackBg, _detailBackX, _detailBackY);
			sizeOf(_detailBackBg, _detailBackW, _detailBackH);
			setFieldWidth(_detailBackText, _detailBackW);
			place(_detailBackText, _detailBackX, _detailBackY + (_detailBackH - lineHeight(_fontSmall)) * 0.5);
		}

		if (_emptyText != null)
		{
			setFieldWidth(_emptyText, Math.max(60, _list.cardW - _pad * 2));
			place(_emptyText, _list.x + _pad, _list.y + _pad * 2);
		}
	}

	function placeScrollArea(view:HelpScrollView):Void
	{
		if (view == null)
			return;

		place(view.bg, view.x, view.y);
		sizeOf(view.bg, view.w, Math.max(1, view.h));
		place(view.topLine, view.x, view.y);
		sizeOf(view.topLine, Math.max(1, view.cardW), 1);
		place(view.bottomLine, view.x, view.y + view.h - 1);
		sizeOf(view.bottomLine, Math.max(1, view.cardW), 1);
		place(view.track, view.x + view.w - _barW, view.y);
		sizeOf(view.track, _barW, Math.max(4, view.h));
	}

	/** The footer hint, shortened when the panel is too narrow for the full sentence. */
	function footerHint():String
	{
		var hint:String = 'Drag to scroll, or use the wheel, or drag the bar   |   TAB switches section   |   ESC closes';
		if (estimateWidth(hint, _fontTiny) > _panelW - _pad * 2)
			hint = 'Drag to scroll   |   TAB switches   |   ESC closes';

		return fitText(hint, _panelW - _pad * 2);
	}

	// --- Section state -------------------------------------------------------------------------

	function setSection(section:Int):Void
	{
		if (section < 0 || section >= SECTION_LABELS.length || section == _section)
			return;

		if (_list != null && _section < _sectionScroll.length)
			_sectionScroll[_section] = _list.scroll;

		_section = section;
		_dragView = null;
		_barDragView = null;
		_tapIndex = -1;
		_searchFocused = false;
		_caretOn = false;
		dismissTyping();
		playSound('scrollMenu');

		applyLayout();

		if (_list != null && section < _sectionScroll.length)
			_list.scroll = _sectionScroll[section];

		renderViews();
	}

	function setFilter(name:String):Void
	{
		if (name == null || name == _filter)
			return;

		_filter = name;
		playSound('scrollMenu');
		refreshSection(true);
		renderViews();
	}

	function setQuery(text:String):Void
	{
		var value:String = (text == null) ? '' : text;
		if (value.length > MAX_QUERY)
			value = value.substr(0, MAX_QUERY);
		if (value == _query)
			return;

		_query = value;
		refreshSection(true);
		renderViews();
	}

	function clearSelection():Void
	{
		if (_selected == null)
			return;

		_selected = null;
		playSound('cancelMenu');
		applyLayout();
		renderViews();
	}

	/** Shows the widgets of the active section and rebuilds its cards. */
	function refreshSection(?resetScroll:Bool = false):Void
	{
		var blocks:Bool = (_section == SECTION_BLOCKS);
		var detailOn:Bool = blocks && (_selected != null);

		setVisible(_searchBand, blocks);
		setVisible(_searchBox, blocks);
		setVisible(_searchAccent, blocks);
		setVisible(_searchText, blocks);
		setVisible(_searchHint, blocks);
		setVisible(_countText, blocks);
		setVisible(_catBand, blocks);

		for (i in 0..._catChipBg.length)
		{
			setVisible(_catChipBg[i], blocks);
			setVisible(_catChipText[i], blocks);
		}

		setVisible(_detailBand, detailOn);
		setVisible(_detailEdge, detailOn);
		setVisible(_detailTitle, detailOn);
		setVisible(_detailBackBg, detailOn);
		setVisible(_detailBackText, detailOn);

		setText(_subtitleText, SECTION_HINTS[_section]);

		for (i in 0..._tabBg.length)
		{
			var active:Bool = (i == _section);
			_tabBg[i].color = active ? COLOR_CHIP_ACTIVE : COLOR_CHIP;
			_tabText[i].color = active ? FlxColor.WHITE : COLOR_DIM;
		}

		for (i in 0..._catChipBg.length)
		{
			var active:Bool = (i < _catNames.length) && (_catNames[i] == _filter);
			_catChipBg[i].color = active ? COLOR_CHIP_ACTIVE : COLOR_CHIP;
			_catChipText[i].color = active ? FlxColor.WHITE : COLOR_DIM;
		}

		rebuildCards(resetScroll);
		refreshSearchText();
	}

	static function setVisible(target:FlxBasic, value:Bool):Void
	{
		if (target != null)
			target.visible = value;
	}

	/** Fills both scroll areas with the cards of the current section. */
	function rebuildCards(resetScroll:Bool):Void
	{
		var cards:Array<HelpCard> = [];
		switch (_section)
		{
			case SECTION_START:
				cards = startCards();
			case SECTION_GESTURES:
				cards = gestureCards();
			case SECTION_BLOCKS:
				cards = blockCards();
			default:
				cards = timelineCards();
		}

		var keep:Float = (_list != null) ? _list.scroll : 0;

		_list.enabled = !_detailFull;
		_list.setCards(cards);
		_list.scroll = resetScroll ? 0 : Math.min(keep, _list.maxScroll);

		if (_section == SECTION_BLOCKS && _selected != null)
		{
			var type:String = _selected.type;
			_detail.enabled = true;
			_detail.setCards(blockDetailCards(_selected));
			if (_detailFor != type)
			{
				_detail.scroll = 0;
				_detailFor = type;
			}
		}
		else
		{
			_detail.enabled = false;
			_detail.setCards([]);
			_detailFor = null;
		}

		if (_section < _sectionScroll.length)
			_sectionScroll[_section] = _list.scroll;
	}

	// --- Card content --------------------------------------------------------------------------

	/** The numbered walkthrough. */
	function startCards():Array<HelpCard>
	{
		var out:Array<HelpCard> = [];

		out.push(stepCard(1, 'Open the editor while the song plays',
			'Start any song, then press the block-editor key (Key 3 by default, remap it in Controls) or tap Play in the standalone editor. The editor opens on top of the running game, so the music keeps going.'));

		out.push(stepCard(2, 'Drag a block out of the palette',
			'Tap a category to see its blocks, then drag one into the grid. Dropping it on the lower half of another block snaps it in underneath: blocks run top to bottom, in order.'));

		out.push(stepCard(3, 'Fill the white slots',
			'A white box is an argument. Tap it and type, or drop a round reporter block into it (curStep, +, getProperty, ...) to use a value instead of a fixed one.'));

		out.push(stepCard(4, 'Pin a stack to a timeline marker',
			'Drag the playhead on the timeline to the moment you want, tap "+ marker", then drop your blocks onto that marker. They run once, exactly at that step, every time the song reaches it.'));

		out.push(stepCard(5, 'Press Save',
			"Save writes a real .lua file into your mod's script folder. The next time the song loads, the game reads it like any other script."));

		out.push(stepCard(6, 'Watch it run straight away',
			'With Live (auto reload) on, Save is applied inside the song you are playing right now: no restart, no reload. If something is off, the warnings in the code panel say what.'));

		out.push(tipCard('What you are looking at',
			'Palette - every block, grouped by colour. Workspace - the grid you drag blocks onto and snap them together on. Timeline - the steps of the song, with one marker per stack that fires at a step. Status bar - the step and beat you are on and the last thing you saved.'));

		out.push(tipCard('Stuck?',
			'The Blocks section of this help lists every block with its description, its parameters and the Lua it produces. Tap a row there to read what that block emits.'));

		return out;
	}

	/** Every gesture, phone-only ones in warning colour. */
	function gestureCards():Array<HelpCard>
	{
		var out:Array<HelpCard> = [];

		out.push(gestureCard('Drag a block out of the palette',
			'Tap a category, then drag a block into the workspace. The translucent copy under your finger is the block you are placing.'));

		out.push(gestureCard('Snap a block under another one',
			'Drop a block on the lower half of another and it clicks into place. Blocks under a hat run top to bottom, in order, so the order you stack them in is the order they run.'));

		out.push(gestureCard('Drop a reporter into a slot',
			'Round blocks give a value back. Drop one on a white input box to use it there instead of typing a number or a name.'));

		out.push(gestureCard('Trash a block', 'Drag it onto the red TRASH box, or drop it back over the palette. Nothing disappears until you let go there.'));

		out.push(gestureCard('Pan the view',
			'Desktop: hold SPACE (or the middle mouse button) and drag. Phone: drag an empty part of the grid with one finger. Panning only moves the view - it never moves your blocks.'));

		out.push(gestureCard('Zoom in and out',
			'Ctrl + mouse wheel, or hold E and Q. On a phone, pinch with two fingers. Zoom is a view setting only, so it is not saved into the script.'));

		out.push(gestureCard('Drag the playhead',
			'The playhead marks where the song is. Drag it along the timeline ruler to park it on a step and add blocks that fire right there.'));

		out.push(gestureCard('Add a marker to a step',
			'Tap "+ marker" to pin a stack to the step the playhead is on. A marker compiles to an if curStep == N then guard inside onStepHit, so its blocks run once, at exactly that step.'));

		out.push(gestureCard('Rename a marker',
			'Tap the name on a marker to type something you will recognise later ("drop the beat"). Give a marker an event name and its blocks also run from onEvent, for chart events.'));

		out.push(gestureCard('Tap a field to type (phone)',
			'Tapping a white slot, a code block or the search box in this help raises the on-screen keyboard. Tap Done to put it away again.', COLOR_WARN));

		out.push(gestureCard('Long-press a block for its menu (phone)',
			'Hold a block for about half a second to open the menu of actions for that block - the same menu a right-click opens on desktop.', COLOR_WARN));

		out.push(gestureCard('Tap a block row in this help',
			'The Blocks section lists the whole catalogue. Tap a row and the panel below shows what that block emits, with every parameter and its default.',
			COLOR_WARN));

		out.push(gestureCard('Scroll a list',
			'Drag the list with a finger, turn the mouse wheel, or drag the bar on its right edge. The scrollbar is at least 10px wide, with a hit area grown for a fingertip.'));

		out.push(gestureCard('Close this help',
			'ESC on desktop, the CLOSE button in the top right on a phone, or TAB to move between sections. The section you were reading is remembered.'));

		return out;
	}

	/** How the timeline, the playhead and the markers fit together. */
	function timelineCards():Array<HelpCard>
	{
		var out:Array<HelpCard> = [];

		out.push(gestureCard('The ruler is the song',
			'Steps are quarter beats: four steps to a beat, sixteen to a bar. The playhead shows the step the song is on right now, and the marks on the ruler are the steps you can drop blocks on.'));

		out.push(gestureCard('Markers pin blocks to a step',
			'A marker is a step plus the stack of blocks you put on it. Drop a stack on a marker and it runs once, at that step, every time the song passes it.'));

		out.push(makeCard(CARD_PLAIN, 'What a marker compiles to',
			'In the script the editor writes for you, a marker becomes a guard around its blocks, so nothing runs until the song reaches that step.',
			COLOR_ACCENT_TEXT, "if curStep == 32 then\n    -- the blocks you dropped on the marker\nend"));

		out.push(gestureCard('Events instead of steps',
			'Give a marker an event name and its blocks also run from onEvent, which is how chart events (including your own custom events) get answered.'));

		out.push(gestureCard('Move and remove a marker',
			'Drag a marker along the ruler to change its step - its blocks travel with it. Tap a marker to select it; the remove action deletes an empty one.'));

		out.push(gestureCard('Seek by tapping the ruler',
			'Tap or drag on the ruler to move the playhead. Nothing is written into the song until you actually drop blocks on a marker.'));

		out.push(gestureCard('Zoom and BPM changes',
			'Zoom the ruler in for fine placement. A chart that changes tempo shows its BPM changes, so a marker keeps the step it was placed on even when the tempo shifts.'));

		out.push(gestureCard('Try the timing before you commit',
			'Test in song runs the blocks you can see, saved or not, so you can check the timing of a marker before you keep it.'));

		return out;
	}

	/** The catalogue: every block of every category, filtered by the chip row and the search box. */
	function blockCards():Array<HelpCard>
	{
		var out:Array<HelpCard> = [];
		var needle:String = _query.toLowerCase();

		_entries = [];
		_totalBlocks = 0;

		for (cat in BlockLibrary.categories)
		{
			if (cat == null || cat.blocks == null)
				continue;

			_totalBlocks += cat.blocks.length;

			if (_filter != CATEGORY_ALL && cat.name != _filter)
				continue;

			for (block in cat.blocks)
			{
				if (block == null || !blockMatches(block, needle))
					continue;

				_entries.push(block);
				out.push(blockCard(block, cat.color, cat.name));
			}
		}

		return out;
	}

	/** Everything a search can match: type, label, category, description, parameters and the Lua. */
	static function blockMatches(block:BlockData, needle:String):Bool
	{
		if (needle.length == 0)
			return true;

		if (contains(block.type, needle) || contains(block.label, needle))
			return true;
		if (contains(block.category, needle) || contains(block.description, needle))
			return true;
		if (contains(block.lua, needle) || contains(block.hatLua, needle))
			return true;
		if (contains(block.source, needle))
			return true;

		if (block.parameters != null)
		{
			for (param in block.parameters)
			{
				if (param == null)
					continue;

				if (contains(param.name, needle) || contains(param.description, needle))
					return true;
			}
		}

		return false;
	}

	static function contains(value:String, needle:String):Bool
	{
		if (value == null || needle.length == 0)
			return false;

		return value.toLowerCase().indexOf(needle) != -1;
	}

	function blockCard(block:BlockData, color:Int, category:String):HelpCard
	{
		var title:String = blockTitle(block);

		var parts:Array<String> = [];
		if (block.description != null && block.description.length > 0)
			parts.push(block.description);

		var params:String = parameterSummary(block.parameters);
		if (params.length > 0)
			parts.push('Takes ' + params + '.');

		if (block.external == true)
			parts.push('Added by a mod config.');

		var body:String = parts.join(' ');
		if (body.length == 0)
			body = 'No description yet - open its details to see the Lua it emits.';

		return makeCard(CARD_BLOCK, title, body, color, null, null, true, block);
	}

	static function blockTitle(block:BlockData):String
	{
		var title:String = (block.label != null && block.label.length > 0) ? block.label : block.type;
		if (block.isHat == true)
			title += '   [hat]';
		else if (block.isReporter == true)
			title += '   [value]';

		return title;
	}

	static function parameterSummary(params:Array<BlockParameter>):String
	{
		if (params == null || params.length == 0)
			return '';

		var parts:Array<String> = [];
		for (param in params)
		{
			if (param == null)
				continue;

			parts.push(param.name + ' (' + Std.string(param.type) + ')');
		}

		return parts.join(', ');
	}

	/** The four cards of the detail panel: what it is, its parameters, its Lua and where it lives. */
	function blockDetailCards(block:BlockData):Array<HelpCard>
	{
		var out:Array<HelpCard> = [];

		var title:String = blockTitle(block);
		var kind:String = 'stack block';
		if (block.isHat == true)
			kind = 'hat block - starts a function';
		else if (block.isReporter == true)
			kind = 'reporter - gives a value back';

		var parts:Array<String> = [];
		if (block.description != null && block.description.length > 0)
			parts.push(block.description);
		parts.push('A ' + kind + '.');
		parts.push('Category: ' + block.category + '.');
		parts.push('Type: ' + block.type + '.');

		out.push(makeCard(CARD_BLOCK, title, parts.join(' '), block.color, null, null, true, block));
		out.push(parametersCard(block));
		out.push(emitsCard(block));
		out.push(sourceCard(block));

		return out;
	}

	function parametersCard(block:BlockData):HelpCard
	{
		var params:Array<BlockParameter> = block.parameters;
		if (params == null || params.length == 0)
			return plainCard('Parameters', 'This block takes no parameters: it does exactly one thing every time it runs.');

		var lines:Array<String> = [];
		for (param in params)
		{
			if (param == null)
				continue;

			var line:String = param.name + ' - ' + Std.string(param.type) + ', default ' + Std.string(param.defaultValue);
			if (param.description != null && param.description.length > 0)
				line += ': ' + param.description;

			lines.push(line);
		}

		return plainCard('Parameters (filled in from left to right)', lines.join('\n'));
	}

	function emitsCard(block:BlockData):HelpCard
	{
		if (block.isHat == true && block.hatLua != null && block.hatLua.length > 0)
		{
			return makeCard(CARD_PLAIN, 'What it emits',
				'A hat opens a Lua function. Everything you stack under it becomes the body of that function, and the engine calls it at the matching moment.',
				COLOR_ACCENT_TEXT, block.hatLua);
		}

		if (block.lua != null && block.lua.length > 0)
		{
			return makeCard(CARD_PLAIN, 'What it emits',
				"The template below is filled in from your parameters: $1, $2 ... are the parameters in order, and ${name} is the parameter called name.",
				COLOR_ACCENT_TEXT, block.lua);
		}

		return plainCard('What it emits',
			'The engine writes this block\'s line itself: BlockLuaGenerator turns the parameters above into Lua. A block imported from a config carries its own template, and that template shows up here.');
	}

	function sourceCard(block:BlockData):HelpCard
	{
		if (block.external == true)
		{
			var where:String = (block.source != null && block.source.length > 0) ? block.source : 'a mod block config';
			return plainCard('Where it comes from', 'Read from ' + where + '. Edit that file to change the block everywhere it is used.');
		}

		return plainCard('Where it comes from', 'Built into the editor: BlockLibrary ships this block and BlockLuaGenerator knows how to write it.');
	}

	function emptyMessage():String
	{
		var filterNote:String = (_filter != CATEGORY_ALL) ? (' in ' + _filter) : '';

		return 'Nothing matches "'
			+ _query
			+ '"'
			+ filterNote
			+ '.\nTry a shorter word: "step", "sprite", "camera", "sound", or tap All blocks.';
	}

	// --- Card factory --------------------------------------------------------------------------

	function stepCard(number:Int, title:String, body:String):HelpCard
	{
		return makeCard(CARD_STEP, title, body, COLOR_ACCENT, null, Std.string(number));
	}

	function plainCard(title:String, body:String):HelpCard
	{
		return makeCard(CARD_PLAIN, title, body, COLOR_BORDER);
	}

	function tipCard(title:String, body:String):HelpCard
	{
		return makeCard(CARD_PLAIN, title, body, COLOR_OK);
	}

	function gestureCard(title:String, body:String, ?color:Int = COLOR_ACCENT_TEXT):HelpCard
	{
		return makeCard(CARD_PLAIN, title, body, color);
	}

	/**
	 * Builds one card: wraps its text with the measured vcr.ttf metrics, indents it past the badge or
	 * swatch, and returns the height the card needs so the list can stack the next one under it.
	 */
	function makeCard(kind:String, title:String, body:String, color:Int, ?lua:String, ?badge:String, swatch:Bool = false, ?block:BlockData):HelpCard
	{
		var titleSize:Int = _fontBody;
		var bodySize:Int = _fontSmall;
		var luaSize:Int = _fontTiny;

		var badgeSize:Float = Math.round(_fontBody * 1.9);
		var swatchSize:Float = Math.round(_fontBody * 1.1);
		var indent:Float = 0;

		if (kind == CARD_STEP)
			indent = badgeSize + _gap * 1.5;
		else if (swatch)
			indent = swatchSize + _gap * 1.5;

		var textW:Float = Math.max(60, _textMaxW - indent);
		var titleLines:Array<String> = wrapText(title, textW, titleSize);
		var bodyLines:Array<String> = wrapText((body == null) ? '' : body, textW, bodySize);
		var luaLines:Array<String> = ((lua == null || lua.length == 0) ? [] : wrapText(lua, Math.max(40, textW - _gap * 1.5), luaSize));

		var height:Float = _pad * 2 + titleLines.length * lineHeight(titleSize);
		if (bodyLines.length > 0)
			height += _gap + bodyLines.length * lineHeight(bodySize);
		if (luaLines.length > 0)
			height += _gap + luaLines.length * lineHeight(luaSize) + _gap * 1.5;

		var minHeight:Float = _pad * 2 + lineHeight(bodySize) + _gap + lineHeight(bodySize);
		if (kind == CARD_STEP)
			minHeight = Math.max(minHeight, _pad * 2 + badgeSize);

		if (height < minHeight)
			height = minHeight;

		return {
			kind: kind,
			badge: (badge == null) ? '' : badge,
			title: titleLines.join('\n'),
			titleLines: (titleLines.length > 0) ? titleLines.length : 1,
			body: bodyLines.join('\n'),
			bodyLines: bodyLines.length,
			lua: luaLines.join('\n'),
			luaLines: luaLines.length,
			color: color,
			swatch: swatch,
			height: Math.ceil(height),
			block: block
		};
	}

	// --- Rendering -----------------------------------------------------------------------------

	/** Draws both scroll areas, their scrollbars and the empty state, every frame. */
	function renderViews():Void
	{
		renderScrollView(_list);
		renderScrollView(_detail);

		if (_emptyText != null)
		{
			var empty:Bool = (_section == SECTION_BLOCKS) && _list != null && _list.enabled && _list.cards.length == 0;
			_emptyText.visible = empty;
			if (empty)
				setText(_emptyText, emptyMessage());
		}

		refreshScrollbar(_list);
		refreshScrollbar(_detail);
	}

	function renderScrollView(view:HelpScrollView):Void
	{
		if (view == null || view.views.length == 0)
			return;

		if (!view.enabled)
		{
			for (cardView in view.views)
				cardView.hide();

			return;
		}

		var first:Int = view.firstVisible();

		for (i in 0...view.views.length)
		{
			var cardView:HelpCardView = view.views[i];
			var index:Int = first + i;

			if (index >= view.cards.length)
			{
				cardView.hide();
				continue;
			}

			var card:HelpCard = view.cards[index];
			var cardY:Float = view.y - view.scroll + view.tops[index];

			if (cardY >= view.y + view.h || cardY + card.height <= view.y)
			{
				cardView.hide();
				continue;
			}

			var selected:Bool = (card.block != null) && (_selected != null) && (card.block.type == _selected.type);
			drawCard(cardView, card, view.cardX, view.cardW, cardY, selected);
		}
	}

	/** Puts one card on screen: stripe, badge or swatch, title, wrapped body and Lua snippet. */
	function drawCard(view:HelpCardView, card:HelpCard, x:Float, w:Float, y:Float, selected:Bool):Void
	{
		var badgeSize:Float = Math.round(_fontBody * 1.9);
		var swatchSize:Float = Math.round(_fontBody * 1.1);
		var indent:Float = 0;
		var rowX:Float = x + _stripeW + _gap * 1.5;

		place(view.bg, x, y);
		sizeOf(view.bg, w, card.height);
		view.bg.color = selected ? COLOR_CARD_SELECTED : COLOR_CARD;
		view.bg.visible = true;

		place(view.stripe, x, y + _gap * 0.5);
		sizeOf(view.stripe, _stripeW, Math.max(2, card.height - _gap));
		view.stripe.color = card.color;
		view.stripe.visible = true;

		if (card.kind == CARD_STEP)
		{
			indent = badgeSize + _gap * 1.5;
			var badgeY:Float = y + Math.max(_pad, (card.height - badgeSize) * 0.5);
			place(view.badgeBg, rowX, badgeY);
			sizeOf(view.badgeBg, badgeSize, badgeSize);
			view.badgeBg.color = COLOR_ACCENT;
			view.badgeBg.visible = true;

			setText(view.badgeText, card.badge);
			setFieldWidth(view.badgeText, badgeSize);
			view.badgeText.alignment = CENTER;
			place(view.badgeText, rowX, badgeY + (badgeSize - lineHeight(_fontBody)) * 0.5);
			view.badgeText.visible = true;
		}
		else
		{
			view.badgeBg.visible = false;
			view.badgeText.visible = false;
		}

		if (card.swatch)
		{
			indent = swatchSize + _gap * 1.5;
			place(view.swatch, rowX, y + _pad + (lineHeight(_fontBody) - swatchSize) * 0.5);
			sizeOf(view.swatch, swatchSize, swatchSize);
			view.swatch.color = card.color;
			view.swatch.visible = true;
		}
		else
			view.swatch.visible = false;

		var textX:Float = rowX + indent;
		setText(view.title, card.title);
		place(view.title, textX, y + _pad);
		view.title.color = COLOR_TEXT;
		view.title.visible = true;

		var bodyY:Float = y + _pad + card.titleLines * lineHeight(_fontBody) + _gap;
		setText(view.body, card.body);
		place(view.body, textX, bodyY);
		view.body.color = COLOR_BODY_TEXT;
		view.body.visible = card.bodyLines > 0;

		if (card.luaLines > 0)
		{
			var luaY:Float = bodyY + card.bodyLines * lineHeight(_fontSmall) + _gap;
			var luaH:Float = card.luaLines * lineHeight(_fontTiny) + _gap * 1.5;

			place(view.luaBg, textX - _gap * 0.5, luaY);
			sizeOf(view.luaBg, Math.max(40, w - (textX - x) - _pad - _gap * 0.5), luaH);
			view.luaBg.color = COLOR_VIEW;
			view.luaBg.visible = true;

			setText(view.luaText, card.lua);
			place(view.luaText, textX + _gap, luaY + _gap * 0.75);
			view.luaText.color = COLOR_ACCENT_TEXT;
			view.luaText.visible = true;
		}
		else
		{
			view.luaBg.visible = false;
			view.luaText.visible = false;
		}
	}

	function refreshScrollbar(view:HelpScrollView):Void
	{
		if (view == null || view.track == null || view.thumb == null)
			return;

		var needed:Bool = view.enabled && view.maxScroll > 0.5 && view.cards.length > 0;
		view.track.visible = needed;
		view.thumb.visible = needed;

		if (!needed)
			return;

		place(view.thumb, view.x + view.w - _barW, view.thumbTop());
		sizeOf(view.thumb, _barW, view.thumbHeight());
	}

	// --- Typing --------------------------------------------------------------------------------

	/** Focuses the search box and raises whatever keyboard this machine can offer. */
	function focusSearch():Void
	{
		_searchFocused = true;
		playSound('confirmMenu');

		if (BlockSoftKeyboard.isNativeAvailable())
		{
			_softOpen = true;
			BlockSoftKeyboard.targetRect = new Rectangle(_searchX, _searchY, _searchW, _searchH);
			BlockSoftKeyboard.open(_query, false, onTyped, onTypingClosed);
			return;
		}

		// A desktop (or a mouse-driven web build) types on the hardware keyboard, so no sheet.
		if (!BlockLayout.isMobile())
			return;

		var kb:BlockVirtualKeyboard = ensureVirtualKeyboard();
		if (kb == null)
			return;

		kb.setText(_query);
		kb.open(_query, false);
	}

	function onTyped(text:String):Void
	{
		setQuery(text);
	}

	function onTypingClosed():Void
	{
		_softOpen = false;
	}

	function typingOpen():Bool
	{
		if (_softOpen)
			return true;

		return _virtualKb != null && _virtualKb.isOpen();
	}

	function dismissTyping():Void
	{
		if (_virtualKb != null && _virtualKb.isOpen())
			_virtualKb.close();

		if (_softOpen)
		{
			_softOpen = false;
			BlockSoftKeyboard.close();
		}
	}

	/** The in-game keyboard, rebuilt whenever the overlay is drawn on another camera. */
	function ensureVirtualKeyboard():BlockVirtualKeyboard
	{
		var cam:FlxCamera = activeCamera();
		if (cam == null)
			return null;

		if (_virtualKb != null && _kbCam != cam)
		{
			remove(_virtualKb, true);
			_virtualKb = null;
		}

		if (_virtualKb == null)
		{
			_kbCam = cam;
			_virtualKb = new BlockVirtualKeyboard(cam);
			_virtualKb.onKey = function(name:String):Void
			{
				onVirtualKey(name);
			};
			_virtualKb.onClose = function():Void
			{
				onVirtualKey('close');
			};
			add(_virtualKb);
		}

		return _virtualKb;
	}

	function onVirtualKey(name:String):Void
	{
		if (_virtualKb == null)
			return;

		setQuery(_virtualKb.getText());

		if (name == 'enter' || name == 'close')
			playSound('confirmMenu');
	}

	/** True while the pointer sits on the in-game keyboard, which handles that tap itself. */
	function pointerOverSheet():Bool
	{
		if (_virtualKb == null || !_virtualKb.isOpen())
			return false;

		var cam:FlxCamera = activeCamera();
		var zoom:Float = (cam != null && cam.zoom > 0.0001) ? cam.zoom : 1;
		var viewH:Float = ((cam != null && cam.height > 0) ? cam.height : _viewH) / zoom;
		var sheetH:Float = Math.max(BlockVirtualKeyboard.MIN_HEIGHT, viewH * BlockVirtualKeyboard.HEIGHT_RATIO);

		return _ptrY >= viewH - sheetH;
	}

	/** The search line, its caret and the "n of m blocks" counter. */
	function refreshSearchText():Void
	{
		if (_searchText == null)
			return;

		var blocks:Bool = (_section == SECTION_BLOCKS);
		var shown:String = fitTail(_query, Math.max(40, _searchW - _pad * 2 - 12), _fontBody);
		if (_searchFocused && _caretOn)
			shown += '_';

		setText(_searchText, shown);
		_searchText.visible = blocks && shown.length > 0;

		if (_searchHint != null)
			_searchHint.visible = blocks && !_searchText.visible;

		if (_countText != null)
		{
			var text:String = (_totalBlocks > 0) ? (_entries.length + ' of ' + _totalBlocks + ' blocks') : (_entries.length + ' blocks');
			if (_filter != CATEGORY_ALL)
				text += ' in ' + _filter;

			var w:Float = Math.min(_searchW * 0.55, 220 * _scale);
			setText(_countText, fitText(text, w, _fontTiny));
		}
	}

	// --- Text metrics --------------------------------------------------------------------------

	function buildMeasure():Void
	{
		if (_measure == null)
		{
			_measure = new FlxText(0, 0, 0, '', _fontBody);
			_measure.scrollFactor.set(0, 0);
		}

		_charW = new Map();
		_lineH = new Map();
	}

	/** Measures a string with the vcr.ttf face at `size` (the measuring text is never drawn). */
	function measure(text:String, size:Int):Float
	{
		if (_measure == null)
			return text.length * size * 0.62;

		_measure.setFormat(Paths.font('vcr.ttf'), size, FlxColor.WHITE, LEFT);
		_measure.text = text;
		_measure.updateHitbox();

		return _measure.width;
	}

	function measureHeight(text:String, size:Int):Float
	{
		if (_measure == null)
			return size * 1.3;

		measure(text, size);
		return _measure.height;
	}

	/** Width of one glyph, cached per size. vcr.ttf is monospaced, so this wraps exactly. */
	function charWidth(size:Int):Float
	{
		if (_charW.exists(size))
			return _charW.get(size);

		var w:Float = Math.max(measure('M', size), Math.max(measure('W', size), measure('m', size)));
		if (!(w > 0))
			w = size * 0.62;

		w = Math.min(w, size * 1.2) * 1.02;
		_charW.set(size, w);

		return w;
	}

	/** Line height, cached per size: measured from a two line probe, with a sane fallback. */
	function lineHeight(size:Int):Float
	{
		if (_lineH.exists(size))
			return _lineH.get(size);

		var one:Float = measureHeight('M', size);
		var two:Float = measureHeight('M\nM', size);
		var lh:Float = two - one;

		if (!(lh > 0) || lh < size * 0.85 || lh > size * 2.4)
			lh = size * 1.3;

		_lineH.set(size, lh);

		return lh;
	}

	function estimateWidth(text:String, size:Int):Float
	{
		if (text == null)
			return 0;

		return text.length * charWidth(size);
	}

	/** Shortens a label with "..." so it fits `maxWidth`. */
	function fitText(text:String, maxWidth:Float, ?size:Int = 0):String
	{
		if (text == null || text.length == 0)
			return '';

		var fontSize:Int = (size > 0) ? size : _fontSmall;
		var cw:Float = charWidth(fontSize);

		if (maxWidth <= cw)
			return '';
		if (estimateWidth(text, fontSize) <= maxWidth)
			return text;

		var maxChars:Int = Std.int(maxWidth / cw) - 3;
		if (maxChars < 1)
			return '';

		return text.substr(0, maxChars) + '...';
	}

	/** Keeps the tail of a string that fits, for a search box that scrolls with the caret. */
	function fitTail(text:String, maxWidth:Float, ?size:Int = 0):String
	{
		if (text == null || text.length == 0)
			return '';

		var fontSize:Int = (size > 0) ? size : _fontBody;
		var cw:Float = charWidth(fontSize);

		if (maxWidth <= cw)
			return '';
		if (estimateWidth(text, fontSize) <= maxWidth)
			return text;

		var maxChars:Int = Std.int(maxWidth / cw) - 3;
		if (maxChars < 1)
			return '';
		if (maxChars >= text.length)
			return text;

		return '...' + text.substr(text.length - maxChars);
	}

	/**
	 * Greedy word wrap with the measured metrics. Newlines in the source stay hard line breaks, a
	 * word longer than a line is split, and no card ever grows past `maxLines`.
	 */
	function wrapText(text:String, maxWidth:Float, size:Int, ?maxLines:Int = 8):Array<String>
	{
		var out:Array<String> = [];
		if (text == null || text.length == 0)
			return out;

		var maxChars:Int = Std.int(maxWidth / charWidth(size));
		if (maxChars < 8)
			maxChars = 8;

		for (block in text.split('\n'))
		{
			var line:String = '';

			for (word in block.split(' '))
			{
				if (word.length == 0)
					continue;

				if (line.length == 0)
					line = word;
				else if (line.length + 1 + word.length <= maxChars)
					line += ' ' + word;
				else
				{
					out.push(line);
					line = word;
				}

				while (line.length > maxChars)
				{
					out.push(line.substr(0, maxChars));
					line = line.substr(maxChars);
				}
			}

			if (line.length > 0)
				out.push(line);
		}

		if (maxLines > 0 && out.length > maxLines)
		{
			out.resize(maxLines);
			var last:String = out[maxLines - 1];
			out[maxLines - 1] = (last.length > 4) ? (last.substr(0, last.length - 3) + '...') : '...';
		}

		return out;
	}

	// --- Widget helpers ------------------------------------------------------------------------

	function makeRect(x:Float, y:Float, w:Float, h:Float, color:Int):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(Math.max(1, Math.ceil(w))), Std.int(Math.max(1, Math.ceil(h))), color);
		sprite.scrollFactor.set(0, 0);
		register(sprite);

		return sprite;
	}

	/** A text that sizes itself to its content: it is never wrapped by the engine, only by us. */
	function makeLabel(size:Int, color:Int, text:String = ''):FlxText
	{
		var label:FlxText = new FlxText(0, 0, 0, text, size);
		label.setFormat(Paths.font('vcr.ttf'), size, color, LEFT);
		label.scrollFactor.set(0, 0);
		register(label);

		return label;
	}

	function register(target:FlxBasic):Void
	{
		_widgets.push(target);
		add(target);
	}

	/** Destroys every widget this overlay created; the typing surface is not one of them. */
	function destroyWidgets():Void
	{
		for (widget in _widgets)
		{
			if (widget != null)
				remove(widget, true);
		}

		_widgets = [];
		_panelEdges = [];
		_tabBg = [];
		_tabText = [];
		_catChipBg = [];
		_catChipText = [];
		_list = null;
		_detail = null;
	}

	static function place(target:FlxObject, x:Float, y:Float):Void
	{
		if (target == null)
			return;

		target.x = x;
		target.y = y;
	}

	/** Resizes a sprite (and its hitbox) only when it is not already that size. */
	static function sizeOf(target:FlxSprite, w:Float, h:Float):Void
	{
		if (target == null)
			return;

		var tw:Float = Math.max(1, w);
		var th:Float = Math.max(1, h);

		if (Math.abs(target.width - tw) < 0.5 && Math.abs(target.height - th) < 0.5)
			return;

		target.setGraphicSize(Std.int(tw), Std.int(th));
		target.updateHitbox();
	}

	static function setFieldWidth(label:FlxText, w:Float):Void
	{
		if (label == null)
			return;

		var value:Float = (w > 1) ? w : 0;
		if (Math.abs(label.fieldWidth - value) > 0.5)
			label.fieldWidth = value;
	}

	static function setText(label:FlxText, value:String):Void
	{
		if (label != null && label.text != value)
			label.text = value;
	}

	function hit(x:Float, y:Float, w:Float, h:Float):Bool
	{
		if (w <= 0 || h <= 0)
			return false;

		return _ptrX >= x && _ptrX <= x + w && _ptrY >= y && _ptrY <= y + h;
	}

	static function playSound(name:String):Void
	{
		if (FlxG.sound == null)
			return;

		try
		{
			FlxG.sound.play(Paths.sound(name));
		}
		catch (e:Dynamic)
		{
			// A missing click must never break the help overlay.
		}
	}

	/** The camera the overlay is drawn on: the group's first camera, else the default one. */
	function activeCamera():FlxCamera
	{
		var cams:Array<FlxCamera> = cameras;
		if (cams != null && cams.length > 0 && cams[0] != null)
			return cams[0];

		return FlxG.camera;
	}
}

/** One keystroke that can be typed into the search box. */
private typedef KeyChar =
{
	var key:FlxKey;
	var char:String;
}

/** One card: what it says, how tall it is and which block it stands for (rows of the Blocks tab). */
private typedef HelpCard =
{
	var kind:String;
	var badge:String;
	var title:String;
	var titleLines:Int;
	var body:String;
	var bodyLines:Int;
	var lua:String;
	var luaLines:Int;
	var color:Int;
	var swatch:Bool;
	var height:Float;
	var block:BlockData;
}

/** The sprites of one card, reused as its scroll area moves. */
private class HelpCardView
{
	public var bg:FlxSprite = null;
	public var stripe:FlxSprite = null;
	public var swatch:FlxSprite = null;
	public var badgeBg:FlxSprite = null;
	public var badgeText:FlxText = null;
	public var title:FlxText = null;
	public var body:FlxText = null;
	public var luaBg:FlxSprite = null;
	public var luaText:FlxText = null;

	public function new()
	{
	}

	/** Hides every sprite of the card, leaving its text alone. */
	public function hide():Void
	{
		if (bg != null)
			bg.visible = false;
		if (stripe != null)
			stripe.visible = false;
		if (swatch != null)
			swatch.visible = false;
		if (badgeBg != null)
			badgeBg.visible = false;
		if (badgeText != null)
			badgeText.visible = false;
		if (title != null)
			title.visible = false;
		if (body != null)
			body.visible = false;
		if (luaBg != null)
			luaBg.visible = false;
		if (luaText != null)
			luaText.visible = false;
	}
}

/** One scrollable column of cards: a regular list, or the block detail panel under it. */
private class HelpScrollView
{
	public var x:Float = 0;
	public var y:Float = 0;
	public var w:Float = 0;
	public var h:Float = 0;
	public var cardX:Float = 0;
	public var cardW:Float = 0;
	public var cardGap:Float = 4;
	public var scroll:Float = 0;
	public var maxScroll:Float = 0;
	public var contentH:Float = 0;
	public var enabled:Bool = false;
	public var cards:Array<HelpCard> = [];
	public var tops:Array<Float> = [];
	public var views:Array<HelpCardView> = [];
	public var bg:FlxSprite = null;
	public var topLine:FlxSprite = null;
	public var bottomLine:FlxSprite = null;
	public var track:FlxSprite = null;
	public var thumb:FlxSprite = null;

	var _barSpace:Float = 14;

	public function new()
	{
	}

	/** Places the viewport; the cards themselves are narrower by the width of the scrollbar. */
	public function setRect(x:Float, y:Float, w:Float, h:Float, barSpace:Float):Void
	{
		this.x = x;
		this.y = y;
		this.w = w;
		this.h = h;
		_barSpace = barSpace;
		cardX = x;
		cardW = Math.max(60, w - barSpace);
		clamp();
	}

	/** Replaces the cards, recalculating every card's offset and the scrollable height. */
	public function setCards(list:Array<HelpCard>):Void
	{
		cards = [];

		for (card in list)
		{
			if (card != null)
				cards.push(card);
		}

		tops = [];
		contentH = 0;

		for (card in cards)
		{
			tops.push(contentH);
			contentH += card.height + cardGap;
		}

		if (contentH > 0)
			contentH -= cardGap;

		clamp();
	}

	public function clamp():Void
	{
		maxScroll = Math.max(0, contentH - h);

		if (scroll < 0)
			scroll = 0;
		if (scroll > maxScroll)
			scroll = maxScroll;
	}

	public function scrollBy(delta:Float):Void
	{
		setScroll(scroll + delta);
	}

	public function setScroll(value:Float):Void
	{
		scroll = value;
		clamp();
	}

	public function contains(px:Float, py:Float):Bool
	{
		if (!enabled)
			return false;

		return px >= x && px <= x + w && py >= y && py <= y + h;
	}

	/** The scrollbar, with a hit area grown sideways so a fingertip can grab it. */
	public function barHit(px:Float, py:Float, grow:Float):Bool
	{
		if (!enabled || maxScroll <= 0.5)
			return false;

		var left:Float = x + w - _barSpace - grow * 0.5;

		return px >= left && px <= x + w && py >= y && py <= y + h;
	}

	/** Index of the card whose top is at or above the current scroll position. */
	public function firstVisible():Int
	{
		if (tops.length == 0)
			return 0;

		var low:Int = 0;
		var high:Int = tops.length - 1;
		var best:Int = 0;

		while (low <= high)
		{
			var mid:Int = Std.int((low + high) / 2);
			if (tops[mid] <= scroll)
			{
				best = mid;
				low = mid + 1;
			}
			else
				high = mid - 1;
		}

		return best;
	}

	/** The card under a screen y, or -1 when the point lands in the gap between two cards. */
	public function cardIndexAt(py:Float):Int
	{
		if (cards.length == 0)
			return -1;

		var local:Float = scroll + (py - y);
		if (local < 0)
			return -1;

		var low:Int = 0;
		var high:Int = cards.length - 1;
		var best:Int = -1;

		while (low <= high)
		{
			var mid:Int = Std.int((low + high) / 2);
			if (tops[mid] <= local)
			{
				best = mid;
				low = mid + 1;
			}
			else
				high = mid - 1;
		}

		if (best < 0)
			return -1;

		if (local > tops[best] + cards[best].height)
			return -1;

		return best;
	}

	public function thumbHeight():Float
	{
		if (contentH <= 0 || h <= 0)
			return 0;

		var ratio:Float = FlxMath.bound(h / contentH, 0.08, 1);
		return Math.min(h, Math.max(Math.min(30, h), h * ratio));
	}

	public function thumbTop():Float
	{
		var travel:Float = h - thumbHeight();
		if (travel <= 1 || maxScroll <= 0)
			return y;

		return y + (scroll / maxScroll) * travel;
	}
}
