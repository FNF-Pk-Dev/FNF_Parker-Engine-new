package editors.blockcode;

import flixel.group.FlxGroup;
import flixel.input.touch.FlxTouch;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

/**
 * Right click / long press context menu of the block-code editor.
 *
 * The menu only draws and reports: it never touches the document itself. The
 * substate that owns the canvas decides when a context menu is due (right click
 * on desktop, long press on touch), calls `openAt()` with the block under the
 * pointer (`null` for the empty workspace) and receives the chosen action
 * through the `onAction` callback.
 *
 * Actions the menu can report:
 *
 * - on a block: `duplicate`, `delete`, `editInputs`, `detach` (only when the
 *   block is plugged into another block's input) and `addMarker`
 * - on the empty workspace: `addMarker`, `clearWorkspace`, `attachEvent` and
 *   `reloadBlocks`
 *
 * Everything is drawn from plain `FlxSprite`s and `FlxText`s with
 * `scrollFactor` 0, so the menu stays glued to the screen whatever camera the
 * substate draws it on. Rows are 44+ pixels tall for fingers, every hover or
 * press updates the one line hint under the title, and closing the menu makes
 * it invisible and inactive so it never swallows a touch meant for the editor.
 */
class BlockContextMenu extends FlxGroup
{
	/** Height of one entry. Kept above 44 so a finger can hit it. */
	public static inline var ROW_HEIGHT:Float = 46;

	public static inline var COLOR_BG:Int = 0xFF0F0F14;
	public static inline var COLOR_BORDER:Int = 0xFF414868;
	public static inline var COLOR_HIGHLIGHT:Int = 0xFF3D59A1;
	public static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_HINT:Int = 0xFF565F89;
	public static inline var COLOR_DESTRUCTIVE:Int = 0xFFF7768E;
	public static inline var COLOR_SEPARATOR:Int = 0xFF24283B;

	static inline var MIN_WIDTH:Float = 250;
	static inline var MAX_WIDTH:Float = 430;
	static inline var PADDING:Float = 8;
	static inline var LABEL_LEAD:Float = 14;
	static inline var TITLE_SIZE:Int = 15;
	static inline var HINT_SIZE:Int = 11;
	static inline var LABEL_SIZE:Int = 16;
	static inline var TITLE_HEIGHT:Float = TITLE_SIZE + 7;
	static inline var TITLE_GAP:Float = 2;
	static inline var HINT_HEIGHT:Float = HINT_SIZE + 5;
	static inline var HINT_GAP:Float = 8;
	static inline var SEPARATOR_HEIGHT:Float = 1;
	static inline var SEPARATOR_INSET:Float = 8;
	static inline var SCREEN_MARGIN:Float = 8;
	static inline var CHAR_RATIO:Float = 0.72;

	/** True while the menu is on screen. The substate checks it to avoid opening a second menu. */
	public var isOpen(default, null):Bool = false;

	// Viewport the menu is clamped to, in screen pixels
	var viewWidth:Float = 0;
	var viewHeight:Float = 0;

	// Always visible furniture
	var panel:FlxSprite;
	var title:FlxText;
	var hint:FlxText;

	// Rebuilt on every open
	var rows:Array<ContextRow> = [];

	var menuX:Float = 0;
	var menuY:Float = 0;
	var menuWidth:Float = MIN_WIDTH;
	var menuHeight:Float = 0;
	var rowsTop:Float = 0;

	var callback:String->Void = null;
	var defaultHint:String = '';

	// Pointer state
	var pressIndex:Int = -1;
	var activeRow:Int = -2;

	/**
	 * True until the press that opened the menu is released, so the finger or
	 * button that triggered the menu does not also trigger a row.
	 */
	var awaitingRelease:Bool = false;

	/**
	 * Frames left to ignore pointer input for. The substate may open the menu from the very
	 * press the menu would otherwise read as a tap outside it, which would close it again.
	 */
	var openGuard:Int = 0;

	public function new(width:Float, height:Float)
	{
		super();

		viewWidth = (width > 0) ? width : FlxG.width;
		viewHeight = (height > 0) ? height : FlxG.height;

		panel = new FlxSprite();
		panel.scrollFactor.set(0, 0);
		add(panel);

		title = makeLabel(TITLE_SIZE, COLOR_TEXT);
		add(title);

		hint = makeLabel(HINT_SIZE, COLOR_HINT);
		add(hint);

		setOpenState(false);
	}

	// ---------------------------------------------------------------------------------------
	// Public API
	// ---------------------------------------------------------------------------------------

	/**
	 * Opens the menu with its top left corner at `x`, `y` (screen pixels, clamped so the
	 * whole menu stays visible). `block` is the block the menu belongs to, or `null` for the
	 * empty workspace; `onAction` receives the chosen action name after the menu closed.
	 */
	public function openAt(x:Float, y:Float, block:Block, onAction:String->Void):Void
	{
		callback = onAction;
		pressIndex = -1;
		activeRow = -2;
		awaitingRelease = true;
		openGuard = 1;

		clearRows();
		build(block, x, y);
		setOpenState(true);
		setActiveRow(-1);
	}

	/** Hides the menu without reporting anything. Safe to call when already closed. */
	public function close():Void
	{
		callback = null;
		pressIndex = -1;
		activeRow = -2;
		awaitingRelease = false;
		openGuard = 0;

		clearRows();
		setOpenState(false);
	}

	override public function update(elapsed:Float):Void
	{
		if (!isOpen)
			return;

		if (openGuard > 0)
		{
			openGuard--;
			return;
		}

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

		var px:Float = pointerX(touch);
		var py:Float = pointerY(touch);

		if (awaitingRelease)
		{
			if (!held)
				awaitingRelease = false;
			return;
		}

		var index:Int = indexAt(px, py);

		if (justPressed || rightPressed)
		{
			if (index < 0)
			{
				// A click or tap anywhere outside the menu dismisses it; the click is not used otherwise.
				if (!overMenu(px, py))
					close();
				return;
			}

			if (rightPressed)
				return;

			pressIndex = index;
			setActiveRow(index);
			return;
		}

		if (pressIndex >= 0)
		{
			if (held)
			{
				// Sliding off the pressed row cancels the highlight, so a drag out never fires.
				setActiveRow((index == pressIndex) ? index : -1);
				return;
			}

			var chosen:Int = pressIndex;
			pressIndex = -1;

			if (justReleased && chosen == index)
			{
				activate(chosen);
				return;
			}

			setActiveRow(index);
			return;
		}

		setActiveRow(index);
	}

	override public function destroy():Void
	{
		close();
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

	// ---------------------------------------------------------------------------------------
	// Entries
	// ---------------------------------------------------------------------------------------

	function buildEntries(block:Block):Array<ContextEntry>
	{
		var entries:Array<ContextEntry> = [];

		if (block != null)
		{
			entries.push({
				action: 'duplicate',
				label: 'DUPLICATE',
				hint: 'Copy this block with everything stacked under it.',
				destructive: false
			});
			entries.push({
				action: 'delete',
				label: 'DELETE',
				hint: 'Remove this block and everything under it.',
				destructive: true
			});
			entries.push({
				action: 'editInputs',
				label: 'EDIT INPUTS',
				hint: 'Type values into the boxes of this block.',
				destructive: false
			});
			if (block.parentInput != null)
			{
				entries.push({
					action: 'detach',
					label: 'DETACH',
					hint: 'Unplug this block from the box it sits inside.',
					destructive: false
				});
			}
			entries.push({
				action: 'addMarker',
				label: 'ADD MARKER',
				hint: 'Put this stack on the timeline at the current step.',
				destructive: false
			});
		}
		else
		{
			entries.push({
				action: 'addMarker',
				label: 'ADD MARKER',
				hint: 'Add a marker at the current step to hang blocks on.',
				destructive: false
			});
			entries.push({
				action: 'clearWorkspace',
				label: 'CLEAR WORKSPACE',
				hint: 'Delete every block in this workspace.',
				destructive: true
			});
			entries.push({
				action: 'attachEvent',
				label: 'ATTACH EVENT',
				hint: 'Wrap the workspace blocks in an event block.',
				destructive: false
			});
			entries.push({
				action: 'reloadBlocks',
				label: 'RELOAD BLOCKS',
				hint: 'Reload custom blocks from the mods folder.',
				destructive: false
			});
		}

		return entries;
	}

	function build(block:Block, x:Float, y:Float):Void
	{
		var entries:Array<ContextEntry> = buildEntries(block);
		var titleText:String = (block == null || block.blockData == null) ? 'WORKSPACE' : ('BLOCK: ' + block.blockData.label);

		defaultHint = (block == null) ? 'Choose what to do with the workspace.' : 'Choose what to do with this block.';

		var widest:Float = estimateTextWidth(titleText, TITLE_SIZE);
		for (entry in entries)
		{
			widest = Math.max(widest, estimateTextWidth(entry.label, LABEL_SIZE) + LABEL_LEAD);
			widest = Math.max(widest, estimateTextWidth(entry.hint, HINT_SIZE));
		}

		var limit:Float = Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, viewWidth - SCREEN_MARGIN * 2));
		menuWidth = clampF(Math.max(MIN_WIDTH, widest + PADDING * 2), MIN_WIDTH, limit);

		var rowsHeight:Float = entries.length * ROW_HEIGHT + Math.max(0, entries.length - 1) * SEPARATOR_HEIGHT;
		menuHeight = PADDING + TITLE_HEIGHT + TITLE_GAP + HINT_HEIGHT + HINT_GAP + rowsHeight + PADDING;

		menuX = clampF(x, SCREEN_MARGIN, viewWidth - SCREEN_MARGIN - menuWidth);
		menuY = clampF(y, SCREEN_MARGIN, viewHeight - SCREEN_MARGIN - menuHeight);

		drawPanel(menuWidth, menuHeight);

		title.text = fitText(titleText, TITLE_SIZE, menuWidth - PADDING * 2);
		title.setPosition(menuX + PADDING, menuY + PADDING);

		hint.setPosition(menuX + PADDING, menuY + PADDING + TITLE_HEIGHT + TITLE_GAP);

		rowsTop = menuY + PADDING + TITLE_HEIGHT + TITLE_GAP + HINT_HEIGHT + HINT_GAP;

		for (i in 0...entries.length)
		{
			var last:Bool = (i == entries.length - 1);
			rows.push(createRow(entries[i], rowsTop + i * (ROW_HEIGHT + SEPARATOR_HEIGHT), last));
		}

		applyCameras();
	}

	function createRow(entry:ContextEntry, rowY:Float, last:Bool):ContextRow
	{
		var row:ContextRow = new ContextRow(entry);

		var rowX:Float = menuX + 1;
		var rowW:Float = Math.max(menuWidth - 2, 16);

		row.x = rowX;
		row.y = rowY;
		row.width = rowW;
		row.height = ROW_HEIGHT;

		row.bg = makeBox(rowW, ROW_HEIGHT, COLOR_BG);
		row.bg.setPosition(rowX, rowY);
		add(row.bg);

		row.highlight = makeBox(rowW, ROW_HEIGHT, COLOR_HIGHLIGHT);
		row.highlight.setPosition(rowX, rowY);
		row.highlight.visible = false;
		add(row.highlight);

		row.label = makeLabel(LABEL_SIZE, entry.destructive ? COLOR_DESTRUCTIVE : COLOR_TEXT);
		row.label.text = fitText(entry.label, LABEL_SIZE, rowW - LABEL_LEAD - PADDING);
		row.label.setPosition(rowX + LABEL_LEAD, Math.round(rowY + (ROW_HEIGHT - LABEL_SIZE) * 0.5) - 1);
		add(row.label);

		if (!last)
		{
			row.separator = makeBox(rowW - SEPARATOR_INSET * 2, SEPARATOR_HEIGHT, COLOR_SEPARATOR);
			row.separator.setPosition(rowX + SEPARATOR_INSET, rowY + ROW_HEIGHT);
			add(row.separator);
		}

		return row;
	}

	// ---------------------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------------------

	function setOpenState(open:Bool):Void
	{
		isOpen = open;
		visible = open;
		active = open;

		if (panel != null)
			panel.visible = open;
		if (title != null)
			title.visible = open;
		if (hint != null)
			hint.visible = open;
	}

	function setActiveRow(index:Int):Void
	{
		var next:Int = (index >= 0 && index < rows.length) ? index : -1;
		if (next == activeRow)
			return;

		activeRow = next;

		for (i in 0...rows.length)
		{
			if (rows[i].highlight != null)
				rows[i].highlight.visible = (i == next);
		}

		if (next >= 0)
		{
			var entry:ContextEntry = rows[next].entry;
			hint.color = entry.destructive ? COLOR_DESTRUCTIVE : COLOR_HINT;
			hint.text = fitText(entry.hint, HINT_SIZE, menuWidth - PADDING * 2);
		}
		else
		{
			hint.color = COLOR_HINT;
			hint.text = fitText(defaultHint, HINT_SIZE, menuWidth - PADDING * 2);
		}
	}

	function activate(index:Int):Void
	{
		if (index < 0 || index >= rows.length)
			return;

		var action:String = rows[index].entry.action;
		var destructive:Bool = rows[index].entry.destructive;
		var handler:String->Void = callback;

		playSound(destructive ? 'cancelMenu' : 'confirmMenu');
		close();

		if (handler != null && action != null)
			handler(action);
	}

	function clearRows():Void
	{
		for (row in rows)
			removeRow(row);

		rows = [];
	}

	function removeRow(row:ContextRow):Void
	{
		if (row == null)
			return;

		if (row.bg != null)
		{
			remove(row.bg, true);
			row.bg.destroy();
		}
		if (row.highlight != null)
		{
			remove(row.highlight, true);
			row.highlight.destroy();
		}
		if (row.label != null)
		{
			remove(row.label, true);
			row.label.destroy();
		}
		if (row.separator != null)
		{
			remove(row.separator, true);
			row.separator.destroy();
		}
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

	// ---------------------------------------------------------------------------------------
	// Pointer helpers (touch first, mouse second)
	// ---------------------------------------------------------------------------------------

	function primaryTouch():FlxTouch
	{
		if (FlxG.touches == null)
			return null;

		for (touch in FlxG.touches.list)
		{
			if (touch != null)
				return touch;
		}

		return null;
	}

	function pointerX(touch:FlxTouch):Float
	{
		var zoom:Float = cameraZoom();
		return (touch != null) ? touch.screenX / zoom : FlxG.mouse.screenX / zoom;
	}

	function pointerY(touch:FlxTouch):Float
	{
		var zoom:Float = cameraZoom();
		return (touch != null) ? touch.screenY / zoom : FlxG.mouse.screenY / zoom;
	}

	function cameraZoom():Float
	{
		var cam:FlxCamera = currentCamera();
		var zoom:Float = (cam != null) ? cam.zoom : 1;
		return (zoom > 0) ? zoom : 1;
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
			if (py < row.y || py > row.y + row.height)
				continue;
			if (px < row.x || px > row.x + row.width)
				continue;

			return i;
		}

		return -1;
	}

	function overMenu(px:Float, py:Float):Bool
	{
		return (px >= menuX && px <= menuX + menuWidth && py >= menuY && py <= menuY + menuHeight);
	}

	// ---------------------------------------------------------------------------------------
	// Drawing helpers
	// ---------------------------------------------------------------------------------------

	function drawPanel(width:Float, height:Float):Void
	{
		var w:Int = Std.int(Math.max(width, 2));
		var h:Int = Std.int(Math.max(height, 2));

		var bitmap:BitmapData = new BitmapData(w, h, true, COLOR_BG);
		bitmap.fillRect(new Rectangle(0, 0, w, 1), COLOR_BORDER);
		bitmap.fillRect(new Rectangle(0, h - 1, w, 1), COLOR_BORDER);
		bitmap.fillRect(new Rectangle(0, 0, 1, h), COLOR_BORDER);
		bitmap.fillRect(new Rectangle(w - 1, 0, 1, h), COLOR_BORDER);

		panel.loadGraphic(bitmap);
		panel.setPosition(menuX, menuY);
	}

	function makeBox(width:Float, height:Float, color:Int):FlxSprite
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

	function playSound(key:String):Void
	{
		if (FlxG.sound == null)
			return;

		var sound = Paths.sound(key);
		if (sound == null)
			return;

		FlxG.sound.play(sound);
	}

	// ---------------------------------------------------------------------------------------
	// Text measuring: the menu fakes a width instead of measuring, so nothing has to be drawn
	// ---------------------------------------------------------------------------------------

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

	static inline function clampF(value:Float, low:Float, high:Float):Float
	{
		if (high < low)
			high = low;
		if (value < low)
			return low;

		return (value > high) ? high : value;
	}
}

/** One selectable entry: the action name handed back to the substate plus its presentation. */
private typedef ContextEntry =
{
	var action:String;
	var label:String;
	var hint:String;
	var destructive:Bool;
}

/** A built row plus its hit rect, so hit testing never has to redo the layout maths. */
private class ContextRow
{
	public var entry:ContextEntry;

	public var bg:FlxSprite;
	public var highlight:FlxSprite;
	public var label:FlxText;
	public var separator:FlxSprite;

	public var x:Float = 0;
	public var y:Float = 0;
	public var width:Float = 0;
	public var height:Float = 0;

	public function new(entry:ContextEntry)
	{
		this.entry = entry;
	}
}
