package editors.blockcode;

import flixel.group.FlxGroup;
import flixel.input.touch.FlxTouch;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

/**
 * Right click / long press context menu of the block-code editor.
 *
 * The menu only draws and reports: it never touches the document itself. The substate that owns
 * the canvas decides when a context menu is due (right click on desktop, long press on touch),
 * calls `openAt()` with the block under the pointer (`null` for the empty workspace) and receives
 * the chosen action through the `onAction` callback.
 *
 * Actions the menu can report:
 *
 * - on a block: `duplicate`, `editInputs`, `detach` (only when the block is plugged into another
 *   block's input), `addMarker` and — behind a separator, tinted red — `delete`
 * - on the empty workspace: `addMarker`, `attachEvent`, `reloadBlocks` and — behind a separator,
 *   tinted red — `clearWorkspace`
 *
 * Every size comes from {@link BlockLayout}, which derives the whole layout from the current
 * viewport, so the menu is the same widget on a 1280x720 window, a phone in landscape, a phone in
 * portrait and a tablet:
 *
 * - rows are at least `BlockLayout.touchSize()` tall, each one a full width hit target with a
 *   square glyph chip in front of the name
 * - the panel has a title line, a one line hint describing the highlighted entry, a separator
 *   before the destructive entries, a rounded 0xFF0F0F14 body, a 1px 0xFF414868 border and a drop
 *   shadow
 * - when the entries do not fit the height the caller asked for (or the viewport), the list scrolls
 *   by row instead of running off the screen: touch drag, mouse wheel and a thin scrollbar
 * - a press fills the whole row (accent, or a dark red for the destructive entries), so the state
 *   is visible under a finger
 * - the menu closes on an entry, a tap outside, ESC and the Android back button, and stays
 *   invisible and non-updating while closed
 *
 * Everything is built from plain `FlxSprite`s and `FlxText`s with `scrollFactor` 0, so the menu
 * stays glued to the screen whatever camera the substate draws it on, and the whole body is torn
 * down and rebuilt on every open. `menuX`/`menuY`/`menuWidth`/`menuHeight` expose the rect the
 * panel actually occupies, so a substate can hit test against it without guessing.
 */
class BlockContextMenu extends FlxGroup
{
	/** Body of the panel. */
	public static inline var COLOR_BG:Int = 0xFF0F0F14;

	/** The 1px outline of the panel. */
	public static inline var COLOR_BORDER:Int = 0xFF414868;

	/** Accent fill of a row held down. */
	public static inline var COLOR_HIGHLIGHT:Int = 0xFF3D59A1;

	public static inline var COLOR_TEXT:Int = 0xFFC0CAF5;

	public static inline var COLOR_HINT:Int = 0xFF565F89;

	/** `delete` and `clearWorkspace` only. */
	public static inline var COLOR_DESTRUCTIVE:Int = 0xFFF7768E;

	public static inline var COLOR_SEPARATOR:Int = 0xFF24283B;

	/** Translucent drop shadow drawn behind the panel. */
	public static inline var COLOR_SHADOW:Int = 0x66000000;

	/** Tint of a row the pointer merely hovers. */
	public static inline var COLOR_ROW_HOVER:Int = 0xFF20233A;

	/** Tint of a destructive row held down. */
	public static inline var COLOR_ROW_PRESSED_DANGER:Int = 0xFF3C1D28;

	/** Fill of the little glyph chip in front of every entry. */
	public static inline var COLOR_CHIP:Int = 0xFF1E2130;

	/** Trough of the scrollbar. */
	public static inline var COLOR_TRACK:Int = 0xFF1B1D28;

	static inline var MIN_WIDTH:Float = 260;
	static inline var MAX_WIDTH:Float = 470;
	static inline var MAX_HINT_CHARS:Int = 44;
	static inline var CHAR_RATIO:Float = 0.72;
	static inline var SCROLLBAR_WIDTH:Float = 4;
	static inline var TAP_SLOP_RATIO:Float = 0.4;
	static inline var SCROLL_WHEEL_STEP:Int = 1;

	/** True while the menu is on screen. The substate checks it to avoid opening a second menu. */
	public var isOpen(default, null):Bool = false;

	/** Screen rect of the panel while open; 0 sized while closed. */
	public var menuX(default, null):Float = 0;

	public var menuY(default, null):Float = 0;

	public var menuWidth(default, null):Float = 0;

	public var menuHeight(default, null):Float = 0;

	// Size hints from the constructor. They cap the panel, but never to the point of making it
	// unusable: a tiny hint still gets enough room for the header and two rows.
	var requestedWidth:Float = 0;
	var requestedHeight:Float = 0;

	// Rebuilt on every open, destroyed on every close.
	var content:Array<FlxSprite> = [];
	var rows:Array<ContextRow> = [];
	var rowOffsets:Array<Float> = [];
	var title:FlxText = null;
	var hint:FlxText = null;
	var scrollTrack:FlxSprite = null;
	var scrollThumb:FlxSprite = null;
	var scrollThumbHeight:Float = 0;
	var panel:FlxSprite = null;
	var shadow:FlxSprite = null;

	// Graphics are only regenerated when the rounded size changed, so repeated opens reuse them.
	var panelBitmap:BitmapData = null;
	var shadowBitmap:BitmapData = null;
	var panelBitmapW:Int = -1;
	var panelBitmapH:Int = -1;
	var shadowBitmapW:Int = -1;
	var shadowBitmapH:Int = -1;

	// Layout metrics, only meaningful while open.
	var rowHeight:Float = 0;
	var rowShowsHint:Bool = false;
	var rowChipWidth:Float = 0;
	var rowChipHeight:Float = 0;
	var rowInset:Float = 0;
	var headerTextWidth:Float = 0;
	var hintFont:Int = 13;
	var listLeft:Float = 0;
	var listRight:Float = 0;
	var listTop:Float = 0;
	var listHeight:Float = 0;
	var visibleRows:Int = 0;
	var scrollRow:Int = 0;
	var maxScrollRow:Int = 0;
	var separatorGap:Float = 0;

	// Document the menu was opened for, kept so a viewport change can rebuild it in place.
	var currentBlock:Block = null;
	var anchorX:Float = 0;
	var anchorY:Float = 0;
	var callback:String->Void = null;
	var defaultHint:String = '';

	// Pointer state.
	var activeRow:Int = -2;
	var pressIndex:Int = -1;
	var pressStartY:Float = 0;
	var pressStartScroll:Int = 0;
	var dragging:Bool = false;
	var dragMoved:Bool = false;
	var pointer:FlxPoint = FlxPoint.get();

	/**
	 * True until the press that opened the menu is released, so the finger or button that triggered
	 * the menu does not also trigger a row.
	 */
	var awaitingRelease:Bool = false;

	/**
	 * Frames left to ignore pointer input for. The substate may open the menu from the very press
	 * the menu would otherwise read as a tap outside it, which would close it again.
	 */
	var openGuard:Int = 0;

	var lastViewWidth:Float = -1;
	var lastViewHeight:Float = -1;

	/**
	 * `width` and `height` are the size the caller expects the menu to stay within. The menu derives
	 * its own metrics from {@link BlockLayout} and uses these as upper bounds only.
	 */
	public function new(width:Float, height:Float)
	{
		super();

		requestedWidth = (width > 0) ? width : 0;
		requestedHeight = (height > 0) ? height : 0;

		setOpenState(false);
	}

	// ---------------------------------------------------------------------------------------------
	// Public API
	// ---------------------------------------------------------------------------------------------

	/**
	 * Opens the menu with its top left corner at `x`, `y` (screen pixels, clamped so the whole menu
	 * stays inside the viewport). `block` is the block the menu belongs to, or `null` for the empty
	 * workspace; `onAction` receives the chosen action name after the menu closed.
	 */
	public function openAt(x:Float, y:Float, block:Block, onAction:String->Void):Void
	{
		BlockLayout.ensure();

		callback = onAction;
		currentBlock = block;
		anchorX = x;
		anchorY = y;
		resetPointerState();
		awaitingRelease = true;
		openGuard = 1;

		build();
		setOpenState(true);
		refreshHint();
	}

	/**
	 * Hides the menu without reporting anything. Safe to call when already closed, and silent: only
	 * `activate()` plays a sound, so the substate keeps owning the open sound.
	 */
	public function close():Void
	{
		callback = null;
		currentBlock = null;
		resetPointerState();
		awaitingRelease = false;
		openGuard = 0;
		activeRow = -2;

		clearContent();
		setOpenState(false);
	}

	/** True while the menu is open and the point is inside the panel (both in screen pixels). */
	public function containsPoint(x:Float, y:Float):Bool
	{
		if (!isOpen)
			return false;

		return (x >= menuX && x <= menuX + menuWidth && y >= menuY && y <= menuY + menuHeight);
	}

	override public function update(elapsed:Float):Void
	{
		if (!isOpen)
			return;

		BlockLayout.ensure();

		if (openGuard > 0)
		{
			openGuard--;
			return;
		}

		// A resize (or a phone rotation) invalidates every metric the menu was laid out with.
		if (BlockLayout.width != lastViewWidth || BlockLayout.height != lastViewHeight)
			build();

		if (backJustPressed())
		{
			close();
			return;
		}

		var touch:FlxTouch = primaryTouch();
		var justPressed:Bool = (touch != null) ? touch.justPressed : FlxG.mouse.justPressed;
		var held:Bool = (touch != null) ? touch.pressed : FlxG.mouse.pressed;
		var justReleased:Bool = (touch != null) ? touch.justReleased : FlxG.mouse.justReleased;
		// Desktop only: the touch path never uses the secondary button.
		var rightPressed:Bool = (touch == null) && FlxG.mouse.justPressedRight;

		if (awaitingRelease)
		{
			// Right click releases the secondary button, so the primary state already runs false.
			if (!held)
				awaitingRelease = false;
			return;
		}

		pollPointer(touch);

		var px:Float = pointer.x;
		var py:Float = pointer.y;
		var inside:Bool = containsPoint(px, py);

		if (inside && canScroll() && FlxG.mouse != null && FlxG.mouse.wheel != 0)
			scrollBy(-FlxG.mouse.wheel * SCROLL_WHEEL_STEP);

		var index:Int = indexAt(px, py);

		if (justPressed || rightPressed)
		{
			if (!inside)
			{
				// A click or tap anywhere outside the menu dismisses it; the click is not used otherwise.
				close();
				return;
			}

			if (rightPressed)
				return;

			beginPress(py, index);
			return;
		}

		if (pressIndex >= 0 || dragging)
		{
			if (held)
			{
				holdPress(py, index);
				return;
			}

			releasePress(index, justReleased);
			return;
		}

		setActiveRow(index);
	}

	override public function destroy():Void
	{
		close();
		clearContent();

		pointer = FlxDestroyUtil.put(pointer);
		panel = null;
		shadow = null;

		super.destroy();
	}

	/**
	 * Keeps the members on the same cameras as the menu itself, so a substate can simply do
	 * `menu.cameras = [camHUD]` and every row follows.
	 */
	override function set_cameras(value:Array<FlxCamera>):Array<FlxCamera>
	{
		_cameras = value;
		applyCameras();
		return _cameras;
	}

	// ---------------------------------------------------------------------------------------------
	// Entries
	// ---------------------------------------------------------------------------------------------

	function buildEntries(block:Block):Array<ContextEntry>
	{
		var entries:Array<ContextEntry> = [];

		if (block != null)
		{
			entries.push({
				action: 'duplicate',
				label: 'DUPLICATE',
				hint: 'Copy this block with everything stacked under it.',
				glyph: 'CP',
				destructive: false,
				separatorBefore: false
			});
			entries.push({
				action: 'editInputs',
				label: 'EDIT INPUTS',
				hint: 'Type values into the boxes of this block.',
				glyph: 'ED',
				destructive: false,
				separatorBefore: false
			});
			if (block.parentInput != null)
			{
				entries.push({
					action: 'detach',
					label: 'DETACH',
					hint: 'Unplug this block from the box it sits inside.',
					glyph: 'DT',
					destructive: false,
					separatorBefore: false
				});
			}
			entries.push({
				action: 'addMarker',
				label: 'ADD MARKER',
				hint: 'Put this stack on the timeline at the current step.',
				glyph: 'MK',
				destructive: false,
				separatorBefore: false
			});
			entries.push({
				action: 'delete',
				label: 'DELETE',
				hint: 'Remove this block and everything under it.',
				glyph: 'X',
				destructive: true,
				separatorBefore: true
			});
		}
		else
		{
			entries.push({
				action: 'addMarker',
				label: 'ADD MARKER',
				hint: 'Add a marker at the current step to hang blocks on.',
				glyph: 'MK',
				destructive: false,
				separatorBefore: false
			});
			entries.push({
				action: 'attachEvent',
				label: 'ATTACH EVENT',
				hint: 'Wrap the workspace blocks in an event block.',
				glyph: 'EV',
				destructive: false,
				separatorBefore: false
			});
			entries.push({
				action: 'reloadBlocks',
				label: 'RELOAD BLOCKS',
				hint: 'Reload custom blocks from the mods folder.',
				glyph: 'RL',
				destructive: false,
				separatorBefore: false
			});
			entries.push({
				action: 'clearWorkspace',
				label: 'CLEAR WORKSPACE',
				hint: 'Delete every block in this workspace.',
				glyph: 'X',
				destructive: true,
				separatorBefore: true
			});
		}

		return entries;
	}

	static function titleFor(block:Block):String
	{
		if (block == null || block.blockData == null)
			return 'WORKSPACE';

		return 'BLOCK: ' + block.blockData.label;
	}

	// ---------------------------------------------------------------------------------------------
	// Build: metrics, panel, rows
	// ---------------------------------------------------------------------------------------------

	function build():Void
	{
		var keepScroll:Int = scrollRow;

		clearContent();

		lastViewWidth = BlockLayout.width;
		lastViewHeight = BlockLayout.height;

		var entries:Array<ContextEntry> = buildEntries(currentBlock);
		// `Math.max` returns Float even for two Ints, so the count has to be narrowed back.
		var count:Int = Std.int(Math.max(1, entries.length));
		var titleText:String = titleFor(currentBlock);

		defaultHint = (currentBlock == null) ? 'Choose what to do with the workspace.' : 'Choose what to do with this block.';

		var pad:Float = BlockLayout.spacing('normal');
		var gap:Float = BlockLayout.spacing('tight');
		var titleFont:Int = BlockLayout.font('title');
		hintFont = BlockLayout.font('small');
		var labelFont:Int = BlockLayout.font('body');
		var chipFont:Int = BlockLayout.font('small');
		var titleH:Float = lineHeight(titleFont);
		var hintH:Float = lineHeight(hintFont);
		var titleGap:Float = Math.max(2, gap * 0.5);
		var headerGap:Float = gap + 4;
		var headerH:Float = titleH + titleGap + hintH + headerGap;
		var footer:Float = pad + 1;
		var head:Float = 1 + pad + headerH;

		separatorGap = gap + Math.max(6, gap * 1.5);
		rowInset = gap;

		// --- row metrics -------------------------------------------------------------------------

		var rowOne:Float = Math.max(BlockLayout.touchSize(), lineHeight(labelFont) + gap * 2);
		var rowTwo:Float = Math.max(BlockLayout.touchSize(), lineHeight(labelFont) + Math.max(2, gap * 0.6) + lineHeight(hintFont) + gap * 2);

		var minUsableH:Float = head + rowOne * 2 + gap + footer;
		var viewportH:Float = Math.max(minUsableH, BlockLayout.height - BlockLayout.inset() * 2);
		var maxH:Float = viewportH;
		if (requestedHeight > 0)
			maxH = Math.min(maxH, Math.max(requestedHeight, minUsableH));

		// Prefer the roomier two line rows; drop to one line (and then to scrolling) when the menu
		// may not grow any further.
		rowShowsHint = (head + count * rowTwo + (count - 1) * gap + footer) <= maxH;
		rowHeight = rowShowsHint ? rowTwo : rowOne;

		// --- vertical layout ---------------------------------------------------------------------

		rowOffsets = [];
		for (i in 0...entries.length)
		{
			if (i == 0)
				rowOffsets.push(0);
			else
				rowOffsets.push(rowOffsets[i - 1] + rowHeight + (entries[i].separatorBefore ? separatorGap : gap));
		}

		var contentH:Float = (entries.length > 0) ? rowOffsets[entries.length - 1] + rowHeight : rowHeight;
		var fitsAll:Bool = (head + contentH + footer) <= maxH;

		if (fitsAll)
		{
			visibleRows = count;
			maxScrollRow = 0;
			listHeight = contentH;
		}
		else
		{
			var available:Float = Math.max(rowHeight, maxH - head - footer);
			var fit:Int = 1;
			for (v in 1...(count + 1))
			{
				if (spanOf(count - v, v) <= available)
					fit = v;
			}

			visibleRows = Std.int(Math.max(1, fit));
			maxScrollRow = Std.int(Math.max(0, count - visibleRows));
			listHeight = Math.max(spanOf(0, visibleRows), spanOf(count - visibleRows, visibleRows));
		}

		scrollRow = Std.int(FlxMath.bound(keepScroll, 0, maxScrollRow));

		var scrollable:Bool = maxScrollRow > 0;
		var scrollBarWidth:Float = SCROLLBAR_WIDTH * BlockLayout.scale;

		// --- width ------------------------------------------------------------------------------

		rowChipWidth = Math.max(BlockLayout.touchSize() * 0.62, estimateTextWidth('XX', chipFont) + gap * 1.5);
		rowChipHeight = Math.min(Math.max(chipFont + 6 * BlockLayout.scale, rowHeight * 0.45), Math.max(rowHeight - gap, 8));

		var labelW:Float = 0;
		var entryHintW:Float = 0;
		for (entry in entries)
		{
			labelW = Math.max(labelW, estimateTextWidth(entry.label, labelFont));
			entryHintW = Math.max(entryHintW, Math.min(estimateTextWidth(entry.hint, hintFont), MAX_HINT_CHARS * hintFont * CHAR_RATIO));
		}

		if (rowShowsHint)
			labelW = Math.max(labelW, entryHintW);

		var scrollReserve:Float = scrollable ? (scrollBarWidth + gap) : 0;
		var wanted:Float = 2 + pad * 2 + gap * 3 + rowChipWidth + labelW + scrollReserve;
		var limitW:Float = Math.max(120, BlockLayout.width - BlockLayout.inset() * 2);
		var minW:Float = Math.min(MIN_WIDTH * BlockLayout.scale, limitW);
		var maxW:Float = Math.min(MAX_WIDTH * BlockLayout.scale, limitW);
		if (requestedWidth > 0)
			maxW = Math.max(minW, Math.min(maxW, requestedWidth));

		menuWidth = Math.round(FlxMath.bound(wanted, minW, Math.max(minW, maxW)));
		menuHeight = Math.round(head + listHeight + footer);

		// --- position and inner rects -----------------------------------------------------------

		var inset:Float = BlockLayout.inset();
		var maxX:Float = Math.max(inset, BlockLayout.width - inset - menuWidth);
		var maxY:Float = Math.max(inset, BlockLayout.height - inset - menuHeight);

		menuX = Math.round(FlxMath.bound(anchorX, inset, maxX));
		menuY = Math.round(FlxMath.bound(anchorY, inset, maxY));

		// Rounded, so rows and text land on whole pixels and stay crisp.
		listTop = Math.round(menuY + head);
		listLeft = Math.round(menuX + 1 + pad);
		listRight = Math.round(menuX + menuWidth - 1 - pad - (scrollable ? (scrollBarWidth + gap) : 0));

		headerTextWidth = menuWidth - 2 - pad * 2;

		// --- panel ------------------------------------------------------------------------------

		drawPanel();

		var textTop:Float = menuY + 1 + pad;
		title = track(makeLabel(titleFont, COLOR_TEXT));
		title.text = fitText(titleText, titleFont, headerTextWidth);
		title.setPosition(Math.round(menuX + 1 + pad), Math.round(textTop));

		hint = track(makeLabel(hintFont, COLOR_HINT));
		hint.setPosition(Math.round(menuX + 1 + pad), Math.round(textTop + titleH + titleGap));

		var separator:FlxSprite = track(makeBox(Std.int(Math.max(headerTextWidth, 1)), 1, COLOR_SEPARATOR));
		separator.x = Math.round(menuX + 1 + pad);
		separator.y = Math.round(textTop + titleH + titleGap + hintH + headerGap * 0.5);

		// --- rows -------------------------------------------------------------------------------

		rows = [];
		for (i in 0...entries.length)
			rows.push(createRow(entries[i]));

		activeRow = -2;
		layoutRows();
		refreshHint();
		applyCameras();
	}

	function createRow(entry:ContextEntry):ContextRow
	{
		var row:ContextRow = new ContextRow(entry);

		var rowW:Int = Std.int(Math.max(listRight - listLeft, 16));
		var rowH:Int = Std.int(Math.max(rowHeight, 16));

		row.bg = track(makeBox(rowW, rowH, COLOR_ROW_HOVER));
		row.bg.alpha = 0.5;

		// White bodies, tinted through `color`: `FlxSprite.color` multiplies, so a coloured graphic
		// would come out far too dark once tinted.
		row.press = track(makeBox(rowW, rowH, 0xFFFFFFFF));
		row.press.visible = false;

		row.chip = track(makeBox(Std.int(Math.max(rowChipWidth, 8)), Std.int(Math.max(rowChipHeight, 8)), 0xFFFFFFFF));
		row.chipGlyph = track(makeLabel(hintFont, entry.destructive ? COLOR_DESTRUCTIVE : COLOR_HINT));
		row.chipGlyph.text = entry.glyph;

		var labelFont:Int = BlockLayout.font('body');
		var textWidth:Float = Math.max(listRight - listLeft - rowInset * 3 - rowChipWidth, 24);

		row.label = track(makeLabel(labelFont, entry.destructive ? COLOR_DESTRUCTIVE : COLOR_TEXT));
		row.label.text = fitText(entry.label, labelFont, textWidth);

		if (rowShowsHint)
		{
			row.hintText = track(makeLabel(hintFont, COLOR_HINT));
			row.hintText.text = fitText(entry.hint, hintFont, textWidth);
		}

		if (entry.separatorBefore)
		{
			row.separator = track(makeBox(Std.int(Math.max(Std.int(listRight - listLeft - rowInset * 2), 1)), 1, COLOR_SEPARATOR));
		}

		return row;
	}

	/** Puts every row at its scrolled position and hides the ones outside the visible window. */
	function layoutRows():Void
	{
		var shift:Float = (scrollRow > 0 && scrollRow < rowOffsets.length) ? rowOffsets[scrollRow] : 0;
		var rowW:Int = Std.int(Math.max(listRight - listLeft, 16));
		var labelFont:Int = BlockLayout.font('body');
		var labelH:Float = lineHeight(labelFont);

		for (i in 0...rows.length)
		{
			var row:ContextRow = rows[i];
			var shown:Bool = (i >= scrollRow && i < scrollRow + visibleRows);
			var y:Float = Math.round(listTop + rowOffsets[i] - shift);

			row.x = listLeft;
			row.y = y;
			row.width = rowW;
			row.height = rowHeight;
			row.shown = shown;

			row.bg.setPosition(listLeft, y);
			row.press.setPosition(listLeft, y);

			var chipY:Float = Math.round(y + (rowHeight - rowChipHeight) * 0.5);
			var glyphH:Float = lineHeight(hintFont);
			row.chip.setPosition(Math.round(listLeft + rowInset), chipY);
			row.chipGlyph.setPosition(Math.round(row.chip.x + (rowChipWidth - row.chipGlyph.width) * 0.5), Math.round(chipY + (rowChipHeight - glyphH) * 0.5));

			var labelX:Float = Math.round(row.chip.x + rowChipWidth + rowInset);

			if (row.hintText != null)
			{
				var blockH:Float = labelH + Math.max(2, rowInset * 0.6) + lineHeight(hintFont);
				var blockTop:Float = Math.round(y + (rowHeight - blockH) * 0.5);

				row.label.setPosition(labelX, blockTop);
				row.hintText.setPosition(labelX, Math.round(blockTop + labelH + Math.max(2, rowInset * 0.6)));
			}
			else
			{
				row.label.setPosition(labelX, Math.round(y + (rowHeight - labelH) * 0.5));
			}

			if (row.separator != null)
				row.separator.setPosition(Math.round(listLeft + rowInset), Math.round(y - separatorGap * 0.5) - 1);

			setRowVisible(row, shown);
		}

		applyRowStates();
		updateScrollBar();
	}

	function setRowVisible(row:ContextRow, shown:Bool):Void
	{
		row.bg.visible = shown;
		row.label.visible = shown;
		row.chip.visible = shown;
		row.chipGlyph.visible = shown;

		if (row.hintText != null)
			row.hintText.visible = shown;
		if (row.separator != null)
			row.separator.visible = shown;
		if (row.press != null)
			row.press.visible = shown && row.pressed;
	}

	// ---------------------------------------------------------------------------------------------
	// Highlight / hint
	// ---------------------------------------------------------------------------------------------

	function setActiveRow(index:Int):Void
	{
		activeRow = (index >= 0 && index < rows.length && rows[index].shown) ? index : -1;

		applyRowStates();
		refreshHint();
	}

	function applyRowStates():Void
	{
		for (i in 0...rows.length)
		{
			var row:ContextRow = rows[i];
			var hovered:Bool = (i == activeRow && row.shown);
			var pressed:Bool = hovered && (i == pressIndex);
			var danger:Bool = row.entry.destructive;

			row.pressed = pressed;

			// The whole row fills up, so a finger has something to look at while it is down.
			row.bg.alpha = (pressed || hovered) ? 0.9 : 0.5;

			row.press.visible = pressed;
			row.press.color = danger ? COLOR_ROW_PRESSED_DANGER : COLOR_HIGHLIGHT;

			row.label.color = pressed ? (danger ? 0xFFFFC0CB : 0xFFFFFFFF) : (danger ? COLOR_DESTRUCTIVE : COLOR_TEXT);
			row.chipGlyph.color = (pressed || hovered) ? (danger ? COLOR_DESTRUCTIVE : COLOR_TEXT) : (danger ? COLOR_DESTRUCTIVE : COLOR_HINT);
			row.chip.color = (pressed || hovered) ? COLOR_BORDER : COLOR_CHIP;
		}
	}

	/** One line under the title: what the highlighted entry does. */
	function refreshHint():Void
	{
		if (hint == null)
			return;

		var text:String = defaultHint;
		var color:Int = COLOR_HINT;

		if (activeRow >= 0 && activeRow < rows.length)
		{
			text = rows[activeRow].entry.hint;
			color = rows[activeRow].entry.destructive ? COLOR_DESTRUCTIVE : COLOR_HINT;
		}

		hint.color = color;
		hint.text = fitText(text, hintFont, headerTextWidth);
	}

	function activate(index:Int):Void
	{
		if (index < 0 || index >= rows.length)
			return;

		var action:String = rows[index].entry.action;
		var destructive:Bool = rows[index].entry.destructive;
		var handler:String->Void = callback;

		close();
		playSound(destructive ? 'cancelMenu' : 'confirmMenu');

		if (handler != null && action != null)
			handler(action);
	}

	// ---------------------------------------------------------------------------------------------
	// Scrolling
	// ---------------------------------------------------------------------------------------------

	function canScroll():Bool
	{
		return maxScrollRow > 0;
	}

	function scrollBy(delta:Int):Void
	{
		if (delta == 0 || !canScroll())
			return;

		setScrollRow(scrollRow + delta);
	}

	function setScrollRow(value:Int):Void
	{
		var next:Int = Std.int(FlxMath.bound(value, 0, maxScrollRow));
		if (next == scrollRow)
			return;

		scrollRow = next;
		layoutRows();
	}

	/** Row whose top is closest to the offset `delta` (row heights differ around a separator). */
	function rowForDelta(start:Int, delta:Float):Int
	{
		if (start < 0 || start >= rowOffsets.length)
			return 0;

		var target:Float = rowOffsets[start] + delta;
		var best:Int = 0;

		for (i in 0...rowOffsets.length)
		{
			if (rowOffsets[i] <= target)
				best = i;
		}

		return Std.int(FlxMath.bound(best, 0, maxScrollRow));
	}

	/** Pixels the rows starting at `start` occupy, `len` of them. */
	function spanOf(start:Int, len:Int):Float
	{
		if (rowOffsets.length == 0 || len <= 0)
			return rowHeight;

		var first:Int = Std.int(FlxMath.bound(start, 0, rowOffsets.length - 1));
		var last:Int = Std.int(FlxMath.bound(start + len - 1, first, rowOffsets.length - 1));

		return rowOffsets[last] + rowHeight - rowOffsets[first];
	}

	function updateScrollBar():Void
	{
		if (scrollTrack == null || scrollThumb == null)
			return;

		var trackH:Float = listHeight;
		var progress:Float = (maxScrollRow > 0) ? (scrollRow / maxScrollRow) : 0;
		var travel:Float = Math.max(0, trackH - scrollThumbHeight);

		scrollTrack.visible = canScroll();
		scrollThumb.visible = canScroll();
		scrollThumb.y = Math.round(listTop + travel * progress);
	}

	// ---------------------------------------------------------------------------------------------
	// Pointer
	// ---------------------------------------------------------------------------------------------

	function resetPointerState():Void
	{
		pressIndex = -1;
		pressStartY = 0;
		pressStartScroll = 0;
		dragging = false;
		dragMoved = false;
		activeRow = -2;
	}

	function beginPress(py:Float, index:Int):Void
	{
		pressStartY = py;
		pressStartScroll = scrollRow;
		dragMoved = false;
		pressIndex = (index >= 0) ? index : -1;
		// Anywhere inside the list box can start a scroll drag, rows included.
		dragging = canScroll() && py >= listTop && py <= listTop + listHeight;

		setActiveRow(index);
	}

	function holdPress(py:Float, index:Int):Void
	{
		if (!dragMoved && Math.abs(py - pressStartY) > Math.max(6, BlockLayout.touchSize() * TAP_SLOP_RATIO))
			dragMoved = true;

		if (dragMoved && canScroll())
		{
			// The row the finger started on travels with the finger; rows move one at a time.
			setScrollRow(rowForDelta(pressStartScroll, pressStartY - py));
			setActiveRow(-1);
			return;
		}

		// Sliding off the pressed row cancels the highlight, so a drag out never fires.
		if (pressIndex >= 0)
			setActiveRow((index == pressIndex) ? pressIndex : -1);
	}

	function releasePress(index:Int, released:Bool):Void
	{
		var chosen:Int = pressIndex;
		var moved:Bool = dragMoved;

		pressIndex = -1;
		dragging = false;
		dragMoved = false;

		// A press that never travelled and ended on the row it started on is the tap.
		if (released && !moved && chosen >= 0 && chosen == index)
		{
			activate(chosen);
			return;
		}

		setActiveRow(index);
	}

	/** Touch first, mouse second: the active touch wins, otherwise the mouse pointer. */
	function pollPointer(touch:FlxTouch):Void
	{
		var cam:FlxCamera = currentCamera();

		if (touch != null)
		{
			touch.getScreenPosition(cam, pointer);
			return;
		}

		if (FlxG.mouse != null)
		{
			FlxG.mouse.getScreenPosition(cam, pointer);
			return;
		}

		pointer.set(-1, -1);
	}

	function primaryTouch():FlxTouch
	{
		if (FlxG.touches == null || FlxG.touches.list == null)
			return null;

		for (touch in FlxG.touches.list)
		{
			if (touch != null && (touch.pressed || touch.justPressed || touch.justReleased))
				return touch;
		}

		return null;
	}

	function currentCamera():FlxCamera
	{
		if (_cameras != null && _cameras.length > 0 && _cameras[0] != null)
			return _cameras[0];

		return FlxG.camera;
	}

	function backJustPressed():Bool
	{
		var back:Bool = FlxG.keys.justPressed.ESCAPE;
		#if android
		back = back || FlxG.android.justReleased.BACK;
		#end
		return back;
	}

	function indexAt(px:Float, py:Float):Int
	{
		for (i in 0...rows.length)
		{
			var row:ContextRow = rows[i];
			if (!row.shown)
				continue;
			if (py < row.y || py > row.y + row.height)
				continue;
			if (px < row.x || px > row.x + row.width)
				continue;

			return i;
		}

		return -1;
	}

	// ---------------------------------------------------------------------------------------------
	// Drawing
	// ---------------------------------------------------------------------------------------------

	function drawPanel():Void
	{
		var w:Int = Std.int(Math.max(menuWidth, 2));
		var h:Int = Std.int(Math.max(menuHeight, 2));
		var radius:Int = Std.int(Math.max(6, Math.round(10 * BlockLayout.scale)));
		var offset:Int = Std.int(Math.max(3, Math.round(4 * BlockLayout.scale)));
		var sw:Int = w + offset;
		var sh:Int = h + offset;

		// The rounded bodies are only regenerated when the size changed, so opening the same menu
		// twice (the common case) reuses one pair of bitmaps.
		var freshShadow:Bool = (shadowBitmap == null || shadowBitmapW != sw || shadowBitmapH != sh);

		if (shadow == null)
			shadow = track(new FlxSprite());

		if (freshShadow)
		{
			shadowBitmapW = sw;
			shadowBitmapH = sh;
			shadowBitmap = new BitmapData(sw, sh, true, 0x00000000);
			fillRoundRect(shadowBitmap, offset, offset, w, h, radius, COLOR_SHADOW);
		}

		if (freshShadow || shadow.graphic == null)
			shadow.loadGraphic(shadowBitmap);

		shadow.scrollFactor.set(0, 0);
		shadow.setPosition(menuX - offset, menuY - offset);

		var freshPanel:Bool = (panelBitmap == null || panelBitmapW != w || panelBitmapH != h);

		if (panel == null)
			panel = track(new FlxSprite());

		if (freshPanel)
		{
			panelBitmapW = w;
			panelBitmapH = h;
			panelBitmap = new BitmapData(w, h, true, 0x00000000);
			fillRoundRect(panelBitmap, 0, 0, w, h, radius, COLOR_BORDER);
			fillRoundRect(panelBitmap, 1, 1, w - 2, h - 2, Math.max(1, radius - 1), COLOR_BG);
		}

		if (freshPanel || panel.graphic == null)
			panel.loadGraphic(panelBitmap);

		panel.scrollFactor.set(0, 0);
		panel.setPosition(menuX, menuY);

		// Thin scrollbar in the strip the rows leave free on their right.
		scrollThumbHeight = 0;
		scrollTrack = null;
		scrollThumb = null;

		if (maxScrollRow > 0)
		{
			var barW:Int = Std.int(Math.max(SCROLLBAR_WIDTH * BlockLayout.scale, 2));
			var total:Int = Std.int(Math.max(1, visibleRows + maxScrollRow));
			var ratio:Float = visibleRows / total;

			scrollThumbHeight = Math.max(BlockLayout.scale * 12, listHeight * Math.min(1, ratio));

			scrollTrack = track(makeBox(barW, Std.int(Math.max(listHeight, 8)), COLOR_TRACK));
			scrollTrack.x = Math.round(listRight + rowInset);

			scrollThumb = track(makeBox(barW, Std.int(Math.max(scrollThumbHeight, 8)), COLOR_HIGHLIGHT));
			scrollThumb.x = scrollTrack.x;
			scrollThumb.y = Math.round(listTop);
		}

		updateScrollBar();
	}

	/** Tracks a sprite so `clearContent()` can tear the whole menu body down again. */
	function track<T:FlxSprite>(sprite:T):T
	{
		content.push(sprite);
		add(sprite);
		return sprite;
	}

	function clearContent():Void
	{
		for (sprite in content)
		{
			if (sprite == null)
				continue;

			remove(sprite, true);
			sprite.destroy();
		}

		content = [];
		rows = [];
		title = null;
		hint = null;
		scrollTrack = null;
		scrollThumb = null;
		panel = null;
		shadow = null;
	}

	function setOpenState(open:Bool):Void
	{
		isOpen = open;
		visible = open;
		active = open;

		if (!open)
		{
			menuX = 0;
			menuY = 0;
			menuWidth = 0;
			menuHeight = 0;
		}
	}

	function makeBox(width:Int, height:Int, color:Int):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite();
		sprite.makeGraphic(Std.int(Math.max(width, 1)), Std.int(Math.max(height, 1)), color);
		sprite.scrollFactor.set(0, 0);
		return sprite;
	}

	function makeLabel(size:Int, color:Int):FlxText
	{
		var label:FlxText = new FlxText(0, 0, 0, "", size);
		label.setFormat(Paths.font("vcr.ttf"), size, color, LEFT, FlxTextBorderStyle.OUTLINE, COLOR_BG);
		label.borderSize = 1;
		label.scrollFactor.set(0, 0);
		return label;
	}

	function applyCameras():Void
	{
		if (_cameras == null || _cameras.length == 0)
			return;

		for (member in members)
		{
			if (member != null)
				member.cameras = _cameras;
		}
	}

	function playSound(key:String):Void
	{
		if (FlxG.sound == null)
			return;

		var sound = Paths.sound(key);
		if (sound == null)
			return;

		FlxG.sound.play(sound);
	}

	// ---------------------------------------------------------------------------------------------
	// Drawing helpers
	// ---------------------------------------------------------------------------------------------

	/** Rounded rectangle fill: the mask is built row by row so no extra openfl shape is needed. */
	static function fillRoundRect(bitmap:BitmapData, x:Float, y:Float, w:Float, h:Float, radius:Float, color:Int):Void
	{
		var rx:Int = Std.int(Math.round(x));
		var ry:Int = Std.int(Math.round(y));
		var rw:Int = Std.int(Math.max(1, Math.round(w)));
		var rh:Int = Std.int(Math.max(1, Math.round(h)));
		var r:Int = Std.int(FlxMath.bound(Math.round(radius), 0, Math.floor(Math.min(rw, rh) / 2)));

		if (r <= 0)
		{
			bitmap.fillRect(new Rectangle(rx, ry, rw, rh), color);
			return;
		}

		for (row in 0...rh)
		{
			var inset:Int = 0;

			if (row < r)
				inset = cornerInset(r, row);
			else if (row >= rh - r)
				inset = cornerInset(r, rh - 1 - row);

			bitmap.fillRect(new Rectangle(rx + inset, ry + row, rw - inset * 2, 1), color);
		}
	}

	/** How far a rounded corner is cut in on the row `local` (0 at the very edge). */
	static function cornerInset(radius:Int, local:Int):Int
	{
		var dy:Float = radius - 1 - local + 0.5;
		var span:Float = Math.sqrt(Math.max(0, radius * radius - dy * dy));

		return Std.int(Math.max(0, Math.ceil(radius - span)));
	}

	// ---------------------------------------------------------------------------------------------
	// Text measuring: the menu fakes a width instead of measuring, so nothing has to be drawn
	// ---------------------------------------------------------------------------------------------

	/** Rendered height of one line of the bitmap font, used for centering and row sizing. */
	static function lineHeight(size:Int):Float
	{
		return Math.round(size * 1.25);
	}

	static function estimateTextWidth(text:String, size:Int):Float
	{
		if (text == null)
			return 0;

		return text.length * size * CHAR_RATIO;
	}

	/** Cuts `text` down to one line that fits `maxWidth` for the given font size. */
	static function fitText(text:String, size:Int, maxWidth:Float):String
	{
		if (text == null || maxWidth <= 0)
			return '';

		if (estimateTextWidth(text, size) <= maxWidth)
			return text;

		var maxChars:Int = Std.int(maxWidth / (size * CHAR_RATIO));
		if (maxChars <= 3)
			return text.substr(0, Std.int(Math.max(maxChars, 0)));

		if (maxChars >= text.length)
			return text;

		return text.substr(0, maxChars - 3) + '...';
	}
}

/** One selectable entry: the action name handed back to the substate plus its presentation. */
private typedef ContextEntry =
{
	var action:String;
	var label:String;
	var hint:String;

	/** Two letter glyph shown in the chip in front of the label. */
	var glyph:String;

	var destructive:Bool;

	/** Draw a separator above this entry: the destructive ones get one. */
	var separatorBefore:Bool;
}

/** A built row plus its hit rect, so hit testing never has to redo the layout maths. */
private class ContextRow
{
	public var entry:ContextEntry;

	public var bg:FlxSprite;
	public var press:FlxSprite;
	public var chip:FlxSprite;
	public var chipGlyph:FlxText;
	public var label:FlxText;
	public var hintText:FlxText;
	public var separator:FlxSprite;

	public var x:Float = 0;
	public var y:Float = 0;
	public var width:Float = 0;
	public var height:Float = 0;
	public var shown:Bool = false;
	public var pressed:Bool = false;

	public function new(entry:ContextEntry)
	{
		this.entry = entry;
	}
}
