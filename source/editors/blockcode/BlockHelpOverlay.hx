package editors.blockcode;

import editors.blockcode.BlockTypes.BlockCategory;
import editors.blockcode.BlockTypes.BlockData;
import editors.blockcode.BlockTypes.BlockParameter;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxGroup;
import flixel.input.touch.FlxTouch;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import openfl.geom.Rectangle;

/**
 * Beginner help overlay for the block-code editor substate.
 *
 * Two tabs, both written for someone who has never opened the editor before:
 *
 * - **Gestures** - one row per thing the editor can do: drag a block out of the sidebar, snap a
 *   block under another one, drop a round reporter block into a white input slot, drag a block to
 *   TRASH, hold SPACE and drag (or drag empty space on a phone) to pan, Ctrl+wheel / E and Q / two
 *   finger pinch to zoom, drag the timeline playhead to a second and add blocks there to make a
 *   real-time effect, tap "+ marker" to bind a stack to a step, Save to write a `.lua`, "Test in
 *   song" to run it, and tapping an input on a phone to raise the on-screen keyboard.
 * - **Blocks** - a searchable list of every block in `BlockLibrary.categories`, each row showing
 *   the category colour, the parameters and the beginner-facing `description`. The search box
 *   matches the block type, label, category and description, which is also how a mod author finds
 *   the blocks their own JSOM/Lua config added. The tab opens with a short "How a script runs"
 *   explainer: hat blocks (Events) start a function, timeline markers wrap their blocks in
 *   `if curStep == N then` inside `onStepHit`, and the generated Lua is what actually runs.
 *
 * Shape: a `FlxGroup` of flat-colour sprites sized to the `width`/`height` the caller passes (its
 * camera view), laid out in camera space (`scrollFactor 0`) so it can be added on top of a running
 * `PlayState`. The list scrolls by touch drag and by mouse wheel, every row is `ROW_H` tall, and
 * rows that stick out of the viewport while scrolling are hidden by the opaque header and footer
 * bands, which are added to the group *after* the rows. That is why the overlay needs no camera
 * and no clipping of its own.
 *
 * Typing goes through `BlockSoftKeyboard` (the real IME, which is also what raises the Android/iOS
 * keyboard) when the platform has one, and through `BlockVirtualKeyboard` (the in-game sheet)
 * everywhere else - desktop, HTML5 and any device without an IME.
 *
 * `open()` keeps the tab it was last left on and clears the search box; `close()` hides the
 * overlay, dismisses any typing surface and fires the `onClosed` callback exactly once, no matter
 * whether the overlay was closed by the CLOSE button, by ESC or by the caller.
 */
class BlockHelpOverlay extends FlxGroup
{
	// --- Theme (same palette as editors.BlockCodeEditorState) -----------------------------------
	static inline var COLOR_BACKDROP:Int = 0xD90A0A10;
	static inline var COLOR_CARD:Int = 0xFF16161E;
	static inline var COLOR_VIEWPORT:Int = 0xFF0F0F14;
	static inline var COLOR_ROW:Int = 0xFF1E2030;
	static inline var COLOR_ACCENT:Int = 0xFF3D59A1;
	static inline var COLOR_ACCENT_TEXT:Int = 0xFF7AA2F7;
	static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	static inline var COLOR_DIM:Int = 0xFF6E7891;
	static inline var COLOR_TAB_IDLE:Int = 0xFF252A3D;

	// --- Fonts ---------------------------------------------------------------------------------
	static inline var FONT_TITLE:Int = 20;
	static inline var FONT_SUBTITLE:Int = 12;
	static inline var FONT_TAB:Int = 16;
	static inline var FONT_EXPLAIN_TITLE:Int = 14;
	static inline var FONT_EXPLAIN:Int = 13;
	static inline var FONT_ROW_TITLE:Int = 15;
	static inline var FONT_ROW_DETAIL:Int = 13;
	static inline var FONT_HINT:Int = 12;

	// --- Layout --------------------------------------------------------------------------------
	static inline var MARGIN_X:Float = 24;
	static inline var MARGIN_Y:Float = 20;
	static inline var MIN_CARD_W:Float = 560;
	static inline var MIN_CARD_H:Float = 300;
	static inline var PAD:Float = 16;
	static inline var TITLE_H:Float = 58;
	static inline var TABS_H:Float = 50;
	static inline var TAB_W:Float = 172;
	static inline var TAB_H:Float = 46;
	static inline var TAB_GAP:Float = 10;
	static inline var CLOSE_W:Float = 132;
	static inline var CLOSE_H:Float = 44;
	static inline var PAGE_H:Float = 44;
	static inline var EXPLAIN_H:Float = 92;
	static inline var INTRO_H:Float = 26;
	static inline var SEARCH_H:Float = 48;
	static inline var ROW_H:Float = 44;
	static inline var ROW_GAP:Float = 4;

	/** Pixels the mouse wheel moves the list per notch. */
	static inline var WHEEL_STEP:Float = 60;

	/** Which tab was picked. */
	static inline var TAB_GESTURES:Int = 0;

	static inline var TAB_BLOCKS:Int = 1;

	// --- Layout state --------------------------------------------------------------------------
	var _width:Float = 0;
	var _height:Float = 0;

	var _cardX:Float = 0;
	var _cardY:Float = 0;
	var _cardW:Float = 0;
	var _cardH:Float = 0;
	var _contentTop:Float = 0;
	var _pagerTop:Float = 0;
	var _viewX:Float = 0;
	var _viewW:Float = 0;
	var _viewY:Float = 0;
	var _viewH:Float = 0;
	var _gestureListY:Float = 0;
	var _gestureListH:Float = 0;
	var _blockListY:Float = 0;
	var _blockListH:Float = 0;
	var _unionListH:Float = 0;
	var _explainY:Float = 0;
	var _searchX:Float = 0;
	var _searchY:Float = 0;
	var _searchW:Float = 0;
	var _closeX:Float = 0;
	var _closeY:Float = 0;
	var _tabX:Float = 0;
	var _tabY:Float = 0;
	var _rowStep:Float = ROW_H + ROW_GAP;

	// --- State ---------------------------------------------------------------------------------
	var _isOpen:Bool = false;
	var _onClosed:Void->Void = null;
	var _tab:Int = TAB_GESTURES;
	var _query:String = '';
	var _scroll:Float = 0;
	var _maxScroll:Float = 0;
	var _caret:Float = 0;
	var _entries:Array<HelpEntry> = [];
	var _rows:Array<BlockHelpRow> = [];
	var _totalBlocks:Int = 0;
	var _thumbHeight:Int = -1;
	var _textCache:Map<String, HelpEntry> = new Map();
	var _cacheTextWidth:Float = -1;

	// Typing
	var _softOpen:Bool = false;
	var _virtualKb:BlockVirtualKeyboard = null;
	var _kbCam:FlxCamera = null;

	// Pointer
	var _ptrPoint:FlxPoint = null;
	var _ptrX:Float = 0;
	var _ptrY:Float = 0;
	var _ptrPressed:Bool = false;
	var _ptrJustPressed:Bool = false;
	var _ptrJustReleased:Bool = false;
	var _activeTouchID:Int = -1;
	var _draggingList:Bool = false;
	var _dragLastY:Float = 0;

	// Widgets the update loop moves around, or that the tab switch toggles.
	var _viewBg:FlxSprite = null;
	var _topLine:FlxSprite = null;
	var _bottomLine:FlxSprite = null;
	var _scrollTrack:FlxSprite = null;
	var _scrollThumb:FlxSprite = null;
	var _tabBg:Array<FlxSprite> = [];
	var _tabText:Array<FlxText> = [];
	var _gestureUi:Array<FlxBasic> = [];
	var _blockUi:Array<FlxBasic> = [];
	var _searchText:FlxText = null;
	var _searchHint:FlxText = null;
	var _countText:FlxText = null;
	var _emptyText:FlxText = null;
	var _measureTitle:FlxText = null;
	var _measureDetail:FlxText = null;

	// --- Public API ----------------------------------------------------------------------------

	/**
	 * Builds the overlay for a `width` x `height` view (the caller's camera size). Non-positive
	 * sizes fall back to `FlxG.width` / `FlxG.height`.
	 */
	public function new(width:Float, height:Float)
	{
		super();

		_width = (width > 0) ? width : FlxG.width;
		_height = (height > 0) ? height : FlxG.height;
		_ptrPoint = FlxPoint.get();

		BlockLibrary.ensureLoaded();
		computeLayout();
		createMeasureTexts();

		// Draw order: every sprite goes in as it is created, and the opaque bands that hide the
		// rows sticking out of the list viewport are added after the rows.
		createBackdrop();
		createRowPool();
		createListFrame();
		createHeader();
		createTabs();
		createGestureBand();
		createBlockBand();
		createPager();
		createCardFrame();

		visible = false;
	}

	/**
	 * Shows the overlay. The tab it was last left on is kept, the search box is cleared and the
	 * list is scrolled back to the top. `onClosed` is called once, when the overlay closes again.
	 */
	public function open(onClosed:Void->Void):Void
	{
		_onClosed = onClosed;
		_isOpen = true;
		visible = true;

		_query = '';
		_scroll = 0;
		_caret = 0;
		_draggingList = false;
		_activeTouchID = -1;

		BlockLibrary.ensureLoaded();
		applyTab();
		refreshEntries();

		playSound('scrollMenu');
	}

	/** Hides the overlay, drops any typing surface and fires `onClosed` (once per `open()`). */
	public function close():Void
	{
		if (!_isOpen)
			return;

		_isOpen = false;
		visible = false;
		_draggingList = false;
		_activeTouchID = -1;

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

		_virtualKb = null;
		_kbCam = null;
		_rows = [];
		_entries = [];
		_textCache = new Map();
		_measureTitle = FlxDestroyUtil.destroy(_measureTitle);
		_measureDetail = FlxDestroyUtil.destroy(_measureDetail);
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
		if (_caret > 1000)
			_caret = 0;

		refreshSearchText();
		handleKeyboard();

		pollPointer();
		if (!pointerOverSheet())
			handlePointer();

		refreshRows();
	}

	/** ESC, TAB and the page / home / end keys, skipped while a typing surface owns the keyboard. */
	function handleKeyboard():Void
	{
		if (typingOpen())
			return;

		if (FlxG.keys == null)
			return;

		if (FlxG.keys.justPressed.ESCAPE)
		{
			playSound('cancelMenu');
			close();
			return;
		}

		if (FlxG.keys.justPressed.TAB)
		{
			setTab((_tab == TAB_GESTURES) ? TAB_BLOCKS : TAB_GESTURES);
			return;
		}

		// Only keys the song itself does not play on: arrows and space stay free for the notes,
		// because the help can be open on top of a running PlayState.
		if (FlxG.keys.justPressed.PAGEDOWN)
			scrollBy(_viewH);
		if (FlxG.keys.justPressed.PAGEUP)
			scrollBy(-_viewH);
		if (FlxG.keys.justPressed.HOME)
			setScroll(0);
		if (FlxG.keys.justPressed.END)
			setScroll(_maxScroll);
	}

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
		if (_ptrJustPressed)
		{
			_draggingList = false;
			_dragLastY = _ptrY;

			if (hit(_closeX, _closeY, CLOSE_W, CLOSE_H))
			{
				playSound('cancelMenu');
				close();
				return;
			}

			for (i in 0..._tabBg.length)
			{
				if (hit(_tabX + i * (TAB_W + TAB_GAP), _tabY, TAB_W, TAB_H))
				{
					setTab(i);
					return;
				}
			}

			if (_tab == TAB_BLOCKS && hit(_searchX, _searchY, _searchW, SEARCH_H))
			{
				openTyping();
				return;
			}

			if (hit(_viewX, _viewY, _viewW, _viewH))
				_draggingList = true;
		}

		if (_draggingList)
		{
			if (_ptrPressed)
			{
				var dy:Float = _dragLastY - _ptrY;
				_dragLastY = _ptrY;
				if (dy != 0)
					scrollBy(dy);
			}

			if (_ptrJustReleased)
				_draggingList = false;
		}

		if (FlxG.mouse != null && FlxG.mouse.wheel != 0 && hit(_viewX, _viewY, _viewW, _viewH))
			scrollBy(-FlxG.mouse.wheel * WHEEL_STEP);
	}

	// --- Tabs and search ----------------------------------------------------------------------

	function setTab(tab:Int):Void
	{
		if (_tab == tab)
			return;

		_tab = tab;
		_scroll = 0;
		dismissTyping();
		playSound('scrollMenu');

		applyTab();
		refreshEntries();
	}

	/** Shows the widgets of the active tab, hides the list of the other one and re-tints the tabs. */
	function applyTab():Void
	{
		var gestures:Bool = (_tab == TAB_GESTURES);

		for (item in _gestureUi)
			item.visible = gestures;

		for (item in _blockUi)
			item.visible = !gestures;

		if (gestures)
		{
			_viewY = _gestureListY;
			_viewH = _gestureListH;
		}
		else
		{
			_viewY = _blockListY;
			_viewH = _blockListH;
		}

		for (i in 0..._tabBg.length)
		{
			var active:Bool = (i == _tab);
			_tabBg[i].color = active ? COLOR_ACCENT : COLOR_TAB_IDLE;
			_tabText[i].color = active ? 0xFFFFFFFF : COLOR_DIM;
		}

		refreshListFrame();
		refreshSearchText();
		clampScroll();
	}

	/** Opens whatever typing surface this platform offers for the search box. */
	function openTyping():Void
	{
		playSound('confirmMenu');

		if (BlockSoftKeyboard.isNativeAvailable())
		{
			_softOpen = true;
			BlockSoftKeyboard.targetRect = new Rectangle(_searchX, _searchY, _searchW, SEARCH_H);
			BlockSoftKeyboard.open(_query, false, onTyped, onTypingClosed);
			return;
		}

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

	function setQuery(text:String):Void
	{
		var value:String = (text != null) ? text : '';
		if (value == _query)
			return;

		_query = value;
		_scroll = 0;
		refreshEntries();
	}

	function refreshSearchText():Void
	{
		if (_searchText == null || _searchHint == null)
			return;

		var caretOn:Bool = typingOpen() && ((_caret % 1.0) < 0.6);
		var shown:String = _query;
		if (caretOn)
			shown += '_';

		setText(_searchText, shown);

		// The whole band is hidden while the gesture tab is up; applyTab() restores it.
		if (_tab != TAB_BLOCKS)
			return;

		_searchText.visible = shown.length > 0;
		_searchHint.visible = !_searchText.visible;

		if (_countText != null)
			setText(_countText, _totalBlocks + ' blocks, ' + _entries.length + ' shown');
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
			_virtualKb.destroy();
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
		var viewH:Float = ((cam != null && cam.height > 0) ? cam.height : _height) / zoom;

		return _ptrY >= viewH - _virtualKb.getSheetHeight();
	}

	// --- List content -------------------------------------------------------------------------

	function refreshEntries():Void
	{
		_entries = (_tab == TAB_GESTURES) ? gestureEntries() : blockEntries(_query);

		if (_tab == TAB_BLOCKS)
		{
			_totalBlocks = 0;
			for (cat in BlockLibrary.categories)
			{
				if (cat != null && cat.blocks != null)
					_totalBlocks += cat.blocks.length;
			}

			if (_emptyText != null)
			{
				var empty:Bool = _entries.length == 0;
				_emptyText.visible = empty;
				if (empty)
				{
					setText(_emptyText, 'Nothing matches "' + _query + '".\nTry a shorter word: "step", "sprite", "camera", "sound".');
				}
			}
		}
		else if (_emptyText != null)
			_emptyText.visible = false;

		clampScroll();
		refreshRows();
		refreshSearchText();
	}

	/** The plain-language gesture list of the first tab. */
	function gestureEntries():Array<HelpEntry>
	{
		var out:Array<HelpEntry> = [];
		out.push(gesture('1. Drag a block out of the sidebar',
			'Every block that exists is listed in the sidebar. Dropping one on the grid is how you place a line of script.'));
		out.push(gesture('2. Drop a block under another one to snap it', 'When it clicks into place it runs right after the block above it, top to bottom.'));
		out.push(gesture('3. Drag a round block into a white slot',
			'Reporters (curStep, +, getProperty...) give a value back. Drop one on a white input box to fill that box in.'));
		out.push(gesture('4. Drag a block onto TRASH to delete it',
			'The red box in the corner deletes whatever you drop on it. Dropping a block back over the sidebar works too.'));
		out.push(gesture('5. Pan: hold SPACE and drag', 'On a phone, drag an empty part of the grid instead. Panning only moves the view, never the script.'));
		out.push(gesture('6. Zoom: Ctrl + mouse wheel, or hold E and Q',
			'On a phone, pinch with two fingers. Zoom is only the view, so it is not saved into the script.'));
		out.push(gesture('7. Drag the timeline playhead to a second',
			'The playhead marks where the song is. Park it on a second, add blocks there, and they fire at that moment.'));
		out.push(gesture('8. Tap + marker to bind a stack to a step',
			'A marker wraps its blocks in "if curStep == N then" inside onStepHit, so they run once, exactly at that step.'));
		out.push(gesture('9. Save writes a .lua file',
			'The editor writes the Lua for you. That file is what the game loads, so keep it with your mod scripts.'));
		out.push(gesture('10. Test in song runs it now',
			'Your blocks become Lua and start on top of the song that is playing, so you can tune an effect live.'));
		out.push(gesture('11. On a phone, tap an input to type', 'Tapping a white slot, a code block or this search box raises the on-screen keyboard.'));
		out.push(gesture('12. Scroll a list by dragging it', 'The mouse wheel works too, and it only scrolls the list under the pointer.'));

		return out;
	}

	static function gesture(title:String, detail:String):HelpEntry
	{
		return {
			title: title,
			detail: detail,
			color: COLOR_ACCENT_TEXT,
			swatch: false
		};
	}

	/**
	 * Every block of `BlockLibrary.categories` whose type, label, category or description matches
	 * `query` (an empty query matches everything). Blocks a mod added through a config are in the
	 * same list, so searching for them is how a mod author finds their own blocks.
	 */
	function blockEntries(query:String):Array<HelpEntry>
	{
		var needle:String = (query != null) ? query.toLowerCase() : '';
		var textWidth:Float = rowTextWidth();

		if (_cacheTextWidth != textWidth)
		{
			_textCache = new Map();
			_cacheTextWidth = textWidth;
		}

		var out:Array<HelpEntry> = [];
		for (cat in BlockLibrary.categories)
		{
			if (cat == null || cat.blocks == null)
				continue;

			for (block in cat.blocks)
			{
				if (block == null || !matches(block, needle))
					continue;

				var key:String = cacheKey(block, cat.color);
				var entry:HelpEntry = _textCache.get(key);
				if (entry == null)
				{
					entry = {
						title: fitToWidth(_measureTitle, blockTitle(block), textWidth),
						detail: fitToWidth(_measureDetail, blockDetail(block), textWidth),
						color: cat.color,
						swatch: true
					};
					_textCache.set(key, entry);
				}

				out.push(entry);
			}
		}

		return out;
	}

	/** Cache key: everything the row text is built from, so a re-registered block is not stale. */
	static function cacheKey(block:BlockData, color:Int):String
	{
		var flags:String = (block.isHat == true) ? 'hat' : '';
		flags += (block.isReporter == true) ? 'rep' : '';
		flags += (block.external == true) ? 'ext' : '';

		var head:String = block.type + '|' + block.label + '|' + block.category + '|' + block.description;
		var tail:String = parameterList(block.parameters) + '|' + color;

		return head + '|' + flags + '|' + tail;
	}

	static function matches(block:BlockData, needle:String):Bool
	{
		if (needle.length == 0)
			return true;

		if (contains(block.type, needle) || contains(block.label, needle))
			return true;
		if (contains(block.category, needle) || contains(block.description, needle))
			return true;

		if (block.parameters != null)
		{
			for (param in block.parameters)
			{
				if (param != null && contains(param.name, needle))
					return true;
			}
		}

		return false;
	}

	static function contains(value:String, needle:String):Bool
	{
		if (value == null)
			return false;

		return value.toLowerCase().indexOf(needle) != -1;
	}

	static function blockTitle(block:BlockData):String
	{
		var title:String = (block.label != null) ? block.label : block.type;
		if (block.isHat == true)
			title += '   (hat)';
		else if (block.isReporter == true)
			title += '   (value)';

		return title;
	}

	static function blockDetail(block:BlockData):String
	{
		var parts:Array<String> = [];

		if (block.isHat == true)
			parts.push('starts a function');
		else if (block.isReporter == true)
			parts.push('gives a value back');

		var params:String = parameterList(block.parameters);
		if (params.length > 0)
			parts.push(params);

		if (block.description != null && block.description.length > 0)
			parts.push(block.description);

		if (block.type != block.label)
			parts.push(block.type);

		if (block.external == true)
			parts.push('from a mod config');

		return parts.join('   |   ');
	}

	static function parameterList(params:Array<BlockParameter>):String
	{
		if (params == null || params.length == 0)
			return '';

		var parts:Array<String> = [];
		for (param in params)
		{
			if (param == null)
				continue;

			parts.push(param.name + ': ' + Std.string(param.type));
		}

		if (parts.length == 0)
			return '';

		return 'takes ' + parts.join(', ');
	}

	// --- List rendering ------------------------------------------------------------------------

	function refreshRows():Void
	{
		var first:Int = Std.int(_scroll / _rowStep);
		if (first < 0)
			first = 0;

		var offset:Float = _scroll - first * _rowStep;

		for (i in 0..._rows.length)
		{
			var row:BlockHelpRow = _rows[i];
			var index:Int = first + i;
			var y:Float = _viewY - offset + i * _rowStep;

			if (index >= _entries.length || y + ROW_H <= _viewY - 2 || y >= _viewY + _viewH + 2)
			{
				hideRow(row);
				continue;
			}

			renderRow(row, _entries[index], y);
		}

		refreshScrollbar();
	}

	function renderRow(row:BlockHelpRow, entry:HelpEntry, y:Float):Void
	{
		row.bg.visible = true;
		row.bg.y = y;

		row.swatch.visible = entry.swatch;
		if (entry.swatch)
		{
			row.swatch.y = y + 6;
			row.swatch.color = entry.color;
		}

		row.title.visible = true;
		row.title.y = y + 5;
		setText(row.title, entry.title);

		row.detail.visible = true;
		row.detail.y = y + 24;
		setText(row.detail, entry.detail);
	}

	static function hideRow(row:BlockHelpRow):Void
	{
		row.bg.visible = false;
		row.swatch.visible = false;
		row.title.visible = false;
		row.detail.visible = false;
	}

	function refreshScrollbar():Void
	{
		if (_scrollTrack == null || _scrollThumb == null)
			return;

		if (_maxScroll <= 0 || _entries.length == 0)
		{
			_scrollTrack.visible = false;
			_scrollThumb.visible = false;
			return;
		}

		_scrollTrack.visible = true;
		_scrollThumb.visible = true;

		var contentH:Float = _maxScroll + _viewH;
		var thumbH:Int = Std.int(Math.max(28, _viewH * (_viewH / contentH)));
		if (thumbH > _viewH)
			thumbH = Std.int(_viewH);

		if (thumbH != _thumbHeight)
		{
			_thumbHeight = thumbH;
			_scrollThumb.setGraphicSize(6, thumbH);
			_scrollThumb.updateHitbox();
		}

		_scrollThumb.y = _viewY + (_scroll / _maxScroll) * (_viewH - thumbH);
	}

	function scrollBy(delta:Float):Void
	{
		setScroll(_scroll + delta);
	}

	function setScroll(value:Float):Void
	{
		_scroll = value;
		clampScroll();
	}

	function clampScroll():Void
	{
		var contentH:Float = (_entries.length > 0) ? ((_entries.length - 1) * _rowStep + ROW_H) : 0;
		_maxScroll = contentH - _viewH;
		if (_maxScroll < 0)
			_maxScroll = 0;

		if (_scroll < 0)
			_scroll = 0;
		if (_scroll > _maxScroll)
			_scroll = _maxScroll;
	}

	// --- Layout -------------------------------------------------------------------------------

	function computeLayout():Void
	{
		_cardX = MARGIN_X;
		_cardY = MARGIN_Y;
		_cardW = _width - MARGIN_X * 2;
		_cardH = _height - MARGIN_Y * 2;

		if (_cardW < MIN_CARD_W)
		{
			_cardW = MIN_CARD_W;
			_cardX = (_width - _cardW) * 0.5;
		}
		if (_cardH < MIN_CARD_H)
		{
			_cardH = MIN_CARD_H;
			_cardY = (_height - _cardH) * 0.5;
		}
		if (_cardX < 0)
			_cardX = 0;
		if (_cardY < 0)
			_cardY = 0;

		var tabsTop:Float = _cardY + TITLE_H;
		_contentTop = tabsTop + TABS_H + 6;
		_pagerTop = _cardY + _cardH - PAGE_H - 8;

		_viewX = _cardX + PAD;
		_viewW = _cardW - PAD * 2;

		_tabX = _cardX + PAD;
		_tabY = tabsTop + 2;

		_closeX = _cardX + _cardW - PAD - CLOSE_W;
		_closeY = _cardY + (TITLE_H - CLOSE_H) * 0.5;

		// Blocks tab: explainer, then the search box, then the list.
		_explainY = _contentTop;
		_searchX = _viewX;
		_searchY = _explainY + EXPLAIN_H + 8;
		_searchW = _viewW;
		_blockListY = _searchY + SEARCH_H + 8;
		_blockListH = _pagerTop - 6 - _blockListY;

		// Gestures tab: a single intro line, so its list starts higher up.
		_gestureListY = _contentTop + INTRO_H + 8;
		_gestureListH = _pagerTop - 6 - _gestureListY;

		if (_blockListH < ROW_H)
			_blockListH = ROW_H;
		if (_gestureListH < ROW_H)
			_gestureListH = ROW_H;

		_unionListH = _pagerTop - 6 - _gestureListY;

		_rowStep = ROW_H + ROW_GAP;
	}

	function rowTextWidth():Float
	{
		var textWidth:Float = _viewW - 30;
		if (textWidth < 40)
			textWidth = 40;

		return textWidth;
	}

	/** Invisible texts used only to measure how much of a row a string can fill. */
	function createMeasureTexts():Void
	{
		_measureTitle = new FlxText(0, 0, 0, '', FONT_ROW_TITLE);
		_measureTitle.setFormat(Paths.font('vcr.ttf'), FONT_ROW_TITLE, FlxColor.WHITE, LEFT);
		_measureTitle.scrollFactor.set(0, 0);

		_measureDetail = new FlxText(0, 0, 0, '', FONT_ROW_DETAIL);
		_measureDetail.setFormat(Paths.font('vcr.ttf'), FONT_ROW_DETAIL, FlxColor.WHITE, LEFT);
		_measureDetail.scrollFactor.set(0, 0);
	}

	// --- Widgets ------------------------------------------------------------------------------

	function createBackdrop():Void
	{
		makeRect(0, 0, _width, _height, COLOR_BACKDROP);
		makeRect(_cardX, _cardY, _cardW, _cardH, COLOR_CARD);
		_viewBg = makeRect(_viewX, _gestureListY, _viewW, _unionListH, COLOR_VIEWPORT);
	}

	/** One reusable sprite set per row that can be on screen at once. */
	function createRowPool():Void
	{
		var maxH:Float = Math.max(_blockListH, _gestureListH);
		var count:Int = Std.int(Math.ceil(maxH / _rowStep)) + 1;
		if (count < 2)
			count = 2;

		var textWidth:Float = rowTextWidth();

		for (i in 0...count)
		{
			var row:BlockHelpRow = new BlockHelpRow();
			row.bg = makeRect(_viewX, _gestureListY, _viewW, ROW_H, COLOR_ROW);
			row.swatch = makeRect(_viewX + 3, _gestureListY + 6, 5, ROW_H - 12, FlxColor.WHITE);
			row.title = makeText(_viewX + 16, _gestureListY + 5, textWidth, FONT_ROW_TITLE, COLOR_TEXT);
			row.detail = makeText(_viewX + 16, _gestureListY + 24, textWidth, FONT_ROW_DETAIL, COLOR_DIM);
			_rows.push(row);
		}
	}

	function createListFrame():Void
	{
		_topLine = makeRect(_viewX, _gestureListY, _viewW, 1, COLOR_ACCENT);
		_bottomLine = makeRect(_viewX, _gestureListY + _gestureListH - 1, _viewW, 1, COLOR_ACCENT);
		_scrollTrack = makeRect(_viewX + _viewW - 8, _gestureListY, 6, _gestureListH, COLOR_VIEWPORT);
		_scrollThumb = makeRect(_viewX + _viewW - 8, _gestureListY, 6, 28, COLOR_TAB_IDLE);
	}

	function createHeader():Void
	{
		makeRect(_cardX, _cardY, _cardW, _contentTop - _cardY, COLOR_CARD);

		makeText(_cardX + PAD, _cardY + 8, _cardW - PAD * 2 - CLOSE_W - 16, FONT_TITLE, COLOR_TEXT, 'BLOCK EDITOR HELP');
		makeText(_cardX + PAD, _cardY + 34, _cardW - PAD * 2 - CLOSE_W - 16, FONT_SUBTITLE, COLOR_ACCENT_TEXT,
			'Everything the editor can do, plus every block that exists.');

		makeRect(_closeX, _closeY, CLOSE_W, CLOSE_H, COLOR_ACCENT);
		var closeText:FlxText = makeText(_closeX, _closeY + 13, CLOSE_W, FONT_TAB, FlxColor.WHITE, 'CLOSE');
		closeText.alignment = CENTER;
	}

	function createTabs():Void
	{
		var labels:Array<String> = ['Gestures', 'Blocks'];

		for (i in 0...labels.length)
		{
			var x:Float = _tabX + i * (TAB_W + TAB_GAP);
			var bg:FlxSprite = makeRect(x, _tabY, TAB_W, TAB_H, COLOR_TAB_IDLE);
			var text:FlxText = makeText(x, _tabY + 13, TAB_W, FONT_TAB, COLOR_DIM, labels[i]);
			text.alignment = CENTER;

			_tabBg.push(bg);
			_tabText.push(text);
		}
	}

	function createGestureBand():Void
	{
		_gestureUi.push(makeRect(_cardX, _contentTop, _cardW, Math.max(1, _gestureListY - 4 - _contentTop), COLOR_CARD));
		_gestureUi.push(makeText(_viewX, _contentTop + 3, _viewW, FONT_EXPLAIN, COLOR_ACCENT_TEXT,
			'Twelve things you can do. Drag or wheel to scroll the list.'));
	}

	function createBlockBand():Void
	{
		_blockUi.push(makeRect(_cardX, _contentTop, _cardW, Math.max(1, _blockListY - 4 - _contentTop), COLOR_CARD));

		_blockUi.push(makeText(_viewX, _explainY + 2, _viewW, FONT_EXPLAIN_TITLE, COLOR_ACCENT_TEXT, 'How a script runs'));

		var lines:Array<String> = [
			'Hat blocks (the yellow Events) start a function: onStepHit, onBeatHit, onCreate...',
			'Blocks under a hat run top to bottom, in order, every time that event fires.',
			'A timeline marker adds "if curStep == N then" inside onStepHit, so its blocks run once, at that step.',
			'Save writes the .lua and Test in song runs it now: the generated Lua is what the game really runs.'
		];

		var y:Float = _explainY + 22;
		for (line in lines)
		{
			_blockUi.push(makeText(_viewX, y, _viewW, FONT_EXPLAIN, COLOR_TEXT, line));
			y += 17;
		}

		_blockUi.push(makeRect(_searchX, _searchY, _searchW, SEARCH_H, COLOR_VIEWPORT));
		_blockUi.push(makeRect(_searchX, _searchY, 4, SEARCH_H, COLOR_ACCENT));

		_searchText = makeText(_searchX + 14, _searchY + 15, _searchW - 300, FONT_ROW_TITLE, COLOR_TEXT);
		_searchHint = makeText(_searchX + 14, _searchY + 15, _searchW - 300, FONT_ROW_TITLE, COLOR_DIM,
			'Search blocks: tap or click here and type (colour, parameter, description...)');
		_countText = makeText(_searchX + _searchW - 280, _searchY + 15, 264, FONT_HINT, COLOR_DIM);
		_countText.alignment = RIGHT;
		_blockUi.push(_searchText);
		_blockUi.push(_searchHint);
		_blockUi.push(_countText);

		_emptyText = makeText(_viewX + 16, _blockListY + 20, _viewW - 32, FONT_ROW_DETAIL, COLOR_DIM);
		_blockUi.push(_emptyText);
	}

	function createPager():Void
	{
		makeRect(_cardX, _pagerTop, _cardW, Math.max(1, _cardY + _cardH - _pagerTop), COLOR_CARD);

		var pagerText:FlxText = makeText(_cardX + PAD, _pagerTop + 14, _cardW - PAD * 2, FONT_HINT, COLOR_DIM,
			'Drag the list or use the wheel to scroll   |   TAB switches tabs   |   ESC closes help');
		pagerText.alignment = CENTER;
	}

	function createCardFrame():Void
	{
		makeRect(_cardX, _cardY, _cardW, 3, COLOR_ACCENT);
		makeRect(_cardX, _cardY + _cardH - 3, _cardW, 3, COLOR_ACCENT);
	}

	function makeRect(x:Float, y:Float, w:Float, h:Float, color:Int):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite(x, y).makeGraphic(Std.int(Math.max(1, Math.ceil(w))), Std.int(Math.max(1, Math.ceil(h))), color);
		sprite.scrollFactor.set(0, 0);
		add(sprite);
		return sprite;
	}

	function makeText(x:Float, y:Float, w:Float, size:Int, color:Int, text:String = ''):FlxText
	{
		var label:FlxText = new FlxText(x, y, w, text, size);
		label.setFormat(Paths.font('vcr.ttf'), size, color, LEFT);
		label.scrollFactor.set(0, 0);
		add(label);
		return label;
	}

	/** Sizes and places the list background, its border lines and the scrollbar on the active tab. */
	function refreshListFrame():Void
	{
		if (_viewBg != null)
		{
			_viewBg.setGraphicSize(Std.int(Math.max(1, _viewW)), Std.int(Math.max(1, _unionListH)));
			_viewBg.updateHitbox();
			_viewBg.x = _viewX;
			_viewBg.y = _gestureListY;
		}

		if (_topLine != null)
		{
			_topLine.setGraphicSize(Std.int(Math.max(1, _viewW)), 1);
			_topLine.updateHitbox();
			_topLine.x = _viewX;
			_topLine.y = _viewY;
		}

		if (_bottomLine != null)
		{
			_bottomLine.setGraphicSize(Std.int(Math.max(1, _viewW)), 1);
			_bottomLine.updateHitbox();
			_bottomLine.x = _viewX;
			_bottomLine.y = _viewY + _viewH - 1;
		}

		if (_scrollTrack != null)
		{
			_scrollTrack.setGraphicSize(6, Std.int(Math.max(1, _viewH)));
			_scrollTrack.updateHitbox();
			_scrollTrack.x = _viewX + _viewW - 8;
			_scrollTrack.y = _viewY;
		}

		_thumbHeight = -1;
	}

	// --- Helpers ------------------------------------------------------------------------------

	/** The camera the overlay is drawn on: the group's first camera, else the default one. */
	function activeCamera():FlxCamera
	{
		var cams:Array<FlxCamera> = cameras;
		if (cams != null && cams.length > 0 && cams[0] != null)
			return cams[0];

		return FlxG.camera;
	}

	function hit(x:Float, y:Float, w:Float, h:Float):Bool
	{
		return _ptrX >= x && _ptrX <= x + w && _ptrY >= y && _ptrY <= y + h;
	}

	static function setText(label:FlxText, value:String):Void
	{
		if (label != null && label.text != value)
			label.text = value;
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
			// A missing click must never break the overlay.
		}
	}

	/** Shortens `text` until it fits `maxWidth`, measuring with the row's own font. */
	function fitToWidth(measure:FlxText, text:String, maxWidth:Float):String
	{
		if (text == null || text.length == 0)
			return '';
		if (measure == null || maxWidth < 40)
			return text;
		if (measureWidth(measure, text) <= maxWidth)
			return text;

		var low:Int = 1;
		var high:Int = text.length;
		var best:Int = 1;

		while (low <= high)
		{
			var mid:Int = Std.int((low + high) / 2);
			if (measureWidth(measure, text.substr(0, mid) + '...') <= maxWidth)
			{
				best = mid;
				low = mid + 1;
			}
			else
				high = mid - 1;
		}

		if (best >= text.length)
			return text;

		return text.substr(0, best) + '...';
	}

	function measureWidth(measure:FlxText, text:String):Float
	{
		measure.text = text;
		measure.updateHitbox();

		return measure.width;
	}
}

/** One entry of the help list: what the two text lines of a row show. */
private typedef HelpEntry =
{
	var title:String;
	var detail:String;

	/** Row colour: the category colour for blocks, the accent for the gesture list. */
	var color:Int;

	/** Whether the row shows the category colour swatch on its left edge. */
	var swatch:Bool;
}

/** The sprites of one list row, reused as the list scrolls. */
private class BlockHelpRow
{
	public var bg:FlxSprite = null;
	public var swatch:FlxSprite = null;
	public var title:FlxText = null;
	public var detail:FlxText = null;

	public function new()
	{
	}
}
