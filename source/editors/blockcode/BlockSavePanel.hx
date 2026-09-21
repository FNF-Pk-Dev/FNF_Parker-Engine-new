package editors.blockcode;

import editors.blockcode.Block.InputField;
import editors.blockcode.BlockTypes.BlockCodeEditorSettings;
import editors.blockcode.BlockTypes.ParamType;
import flixel.FlxCamera;
import flixel.group.FlxGroup;
import flixel.math.FlxPoint;
#if FLX_TOUCH
import flixel.input.touch.FlxTouch;
#end
import openfl.geom.Rectangle;

/**
 * Save / export settings sheet of the block-code editor substate.
 *
 * The panel owns no code of its own: it edits the fields of a `BlockCodeEditorSettings` (script
 * name, save location, exec mode, custom path, auto-reload, forced touch keyboard) and writes the
 * generated Lua through `BlockFileIO` when the substate hands it over. The substate assigns
 * `codeProvider` once - the callback that generates the Lua of the current blocks - and reacts to
 * `onSaved` / `onClosed`; layout, hit testing, scrolling, status and log stay inside this group.
 *
 * Self contained on purpose: the panel creates its own full screen `FlxCamera`, appends it to
 * `FlxG.cameras` (last, i.e. on top) on `open()` and removes it again on `close()`, so the rows
 * stay aligned with the screen whatever the editor does to its own cameras. Every member is drawn
 * through that camera with `scrollFactor == 0`, which also makes screen coordinates and panel
 * coordinates identical - `FlxPointer.getScreenPosition(cam)` is the hit test point, and the panel
 * camera is never scrolled or zoomed.
 *
 * Pointers are read from `FlxG.touches` first (only the first touch inside the sheet drives it) and
 * from `FlxG.mouse` as the desktop fallback. A row fires on release over the same row; a finger
 * that slides further than `DRAG_CANCEL` cancels the press and scrolls the content instead. Every
 * control is `CONTROL_HEIGHT` (44) tall inside a `ROW_HEIGHT` (48) tall row.
 *
 * The script name and the custom path reuse `Block`'s inline `InputField`, so both follow the same
 * edit path as block parameters: tapping a field calls `Block.requestTextEdit`. When nobody
 * installed that hook and the platform has a native IME (see `BlockSoftKeyboard.isNativeAvailable()`)
 * the panel opens `BlockSoftKeyboard` itself; while that invisible field is up the inline fields
 * skip their own key handling, so a character can never be applied twice.
 *
 * All colours come from the editor theme (`COLOR_*`), all text uses `Paths.font("vcr.ttf")` and all
 * sounds go through `Paths.sound()`. Nothing in this file touches the filesystem directly.
 */
class BlockSavePanel extends FlxGroup
{
	// --- Theme (same palette as the block-code editor) ---

	/** Scrim behind the sheet. */
	public static inline var COLOR_BG:Int = 0xFF16161E;

	/** Sheet background. */
	public static inline var COLOR_PANEL:Int = 0xFF1A1B26;

	/** Row / control background. */
	public static inline var COLOR_ROW:Int = 0xFF24283B;

	/** Row background of a row that is switched on. */
	public static inline var COLOR_ROW_ON:Int = 0xFF2F3349;

	public static inline var COLOR_ACCENT:Int = 0xFF3D59A1;
	public static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_DIM:Int = 0xFF565F89;
	public static inline var COLOR_WARN:Int = 0xFFF7768E;
	public static inline var COLOR_OK:Int = 0xFF9ECE6A;
	public static inline var COLOR_DARK_TEXT:Int = 0xFF16161E;
	public static inline var COLOR_CAPTION:Int = 0xFF565F89;
	public static inline var COLOR_SEPARATOR:Int = 0xFF414868;

	// --- Metrics ---
	static inline var DEFAULT_WIDTH:Float = 660;
	static inline var MARGIN:Float = 8;
	static inline var PAD:Float = 12;

	/** Every row of the sheet is at least this tall. */
	static inline var ROW_HEIGHT:Float = 48;

	/** Hit area of one control - one finger. */
	static inline var CONTROL_HEIGHT:Float = 44;

	static inline var CAPTION_HEIGHT:Float = 20;
	static inline var HEADER_HEIGHT:Float = 48;
	static inline var FOOTER_HEIGHT:Float = 54;
	static inline var GAP:Float = 6;
	static inline var SIDE_WIDTH:Float = 104;
	static inline var TARGET_LINE_HEIGHT:Float = 17;
	static inline var LOG_LINES:Int = 3;
	static inline var LOG_LINE_HEIGHT:Float = 15;

	/** Shortest item the header/footer bands can cover; taller ones need full visibility. */
	static inline var MAX_PARTIAL_HEIGHT:Float = 46;

	static inline var WHEEL_STEP:Float = 34;
	static inline var ROW_STEP:Float = ROW_HEIGHT + GAP;

	/** How far a finger may slide before a press turns into a scroll drag. */
	static inline var DRAG_CANCEL:Float = 14;

	static inline var MAX_LOG_ENTRIES:Int = 60;
	static inline var SCROLLBAR_WIDTH:Float = 4;
	static inline var SCROLLBAR_MIN_HEIGHT:Float = 32;
	static inline var ELLIPSIS:String = '...';
	static inline var FIELD_LABEL_WIDTH:Float = 0.6;

	// --- Public API ---

	/** Fired with the path that was written, or that the file now lives at after a rename. */
	public var onSaved:String->Void = null;

	/** Fired once by `close()`, never by `destroy()`. */
	public var onClosed:Void->Void = null;

	/**
	 * Assigned by the substate: returns the Lua the current blocks generate. `Save Lua` and
	 * `Save + Rename` write exactly what this returns (an empty script is a valid value); the panel
	 * never generates code itself and reports a status message while this is null.
	 */
	public var codeProvider:Void->String = null;

	public function new(width:Float)
	{
		super();

		_requestedWidth = (width > 0) ? width : DEFAULT_WIDTH;
		cam = createCamera();
		cameras = [cam];

		buildWidgets();

		visible = false;
		active = false;
	}

	/**
	 * Shows the sheet for `settings` and reads its current values. Passing null uses
	 * `BlockTypes.defaultSettings()`. Safe to call again while the panel is open, e.g. after the
	 * substate reloaded a project from disk.
	 */
	public function open(settings:BlockCodeEditorSettings, songName:String):Void
	{
		_settings = (settings != null) ? settings : BlockTypes.defaultSettings();
		_songName = (songName != null) ? songName : '';

		readSettings();
		computeGeometry();

		_isOpen = true;
		visible = true;
		active = true;
		ensureCamera();

		_keyboardAskedFor = null;
		_pressedCell = null;
		_dragging = false;
		scrollY = 0;
		logLines = [];

		layoutRows();
		applyScroll();
		refreshInfo();
		refreshConfigLine();
		refreshSaveLabels(true);

		addLog('save panel opened for "' + ((_songName.length > 0) ? _songName : 'no song') + '"');
		setStatus('target: ' + shortTarget(), true);
	}

	/** Hides the sheet, drops the camera and fires `onClosed`. A second call does nothing. */
	public function close():Void
	{
		if (!_isOpen)
			return;

		_isOpen = false;
		visible = false;
		active = false;
		_pressedCell = null;
		_dragging = false;

		if (_ownsSoftKeyboard)
		{
			_ownsSoftKeyboard = false;
			_softField = null;
			_keyboardAskedFor = null;
			BlockSoftKeyboard.close();
		}

		if (nameField != null)
			nameField.unfocus();
		if (pathField != null)
			pathField.unfocus();

		detachCamera();

		if (onClosed != null)
			onClosed();
	}

	/** Writes the panel's current choices back into `settings` (and nothing else). */
	public function applyTo(settings:BlockCodeEditorSettings):Void
	{
		if (settings == null)
			return;

		settings.scriptName = BlockFileIO.sanitizeName(currentName());
		settings.execMode = _mode;
		settings.customExecPath = _customPath;
		settings.autoReload = _autoReload;
		settings.forceVirtualKeyboard = _forceVirtualKeyboard;
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (!_isOpen)
			return;

		ensureCamera();
		pollPointer();
		handlePointer();
		updateScrollInput();
		updateFields(elapsed);
		refreshSaveLabels(false);

		if (scrollY != _appliedScrollY)
			applyScroll();
	}

	override public function draw():Void
	{
		super.draw();

		// InputFields are not FlxBasic and cannot be group members; their parts carry `cam`.
		drawField(nameField);
		drawField(pathField);
	}

	override public function destroy():Void
	{
		detachCamera();
		if (cam != null)
		{
			cam.destroy();
			cam = null;
		}

		if (_ownsSoftKeyboard && BlockSoftKeyboard.isOpen())
		{
			_ownsSoftKeyboard = false;
			BlockSoftKeyboard.destroy();
		}

		destroyField(nameField);
		nameField = null;
		destroyField(pathField);
		pathField = null;

		cells = null;
		modeCells = null;
		targetLines = null;
		plains = null;
		logLines = null;

		super.destroy();
	}

	// --- State ---
	var _isOpen:Bool = false;
	var _requestedWidth:Float = DEFAULT_WIDTH;
	var _settings:BlockCodeEditorSettings = null;
	var _songName:String = '';

	// Mirrors of the settings being edited.
	var _mode:String = 'song';
	var _autoReload:Bool = true;
	var _forceVirtualKeyboard:Bool = false;
	var _customPath:String = '';

	// Geometry.
	var panelX:Float = 0;
	var panelY:Float = 0;
	var panelW:Float = DEFAULT_WIDTH;
	var panelH:Float = 600;
	var contentTop:Float = 0;
	var contentBottom:Float = 0;
	var contentHeight:Float = 0;
	var scrollY:Float = 0;
	var maxScroll:Float = 0;
	var _appliedScrollY:Float = -1;
	var _camW:Int = 0;
	var _camH:Int = 0;

	// Camera and chrome.
	var cam:FlxCamera = null;
	var scrim:FlxSprite = null;
	var panelBg:FlxSprite = null;
	var panelEdgeTop:FlxSprite = null;
	var panelEdgeBottom:FlxSprite = null;
	var headerBg:FlxSprite = null;
	var headerText:FlxText = null;
	var headerHint:FlxText = null;
	var footerBg:FlxSprite = null;
	var statusText:FlxText = null;
	var configText:FlxText = null;
	var scrollTrack:FlxSprite = null;
	var scrollThumb:FlxSprite = null;

	// Scrolling content: hittable cells plus plain captions/labels/log.
	var cells:Array<BlockSaveCell> = [];
	var plains:Array<
		{
			sprite:FlxSprite,
			baseY:Float,
			height:Float
		}> = [];

	// Content widgets.
	var capScriptName:FlxText = null;
	var capTargets:FlxText = null;
	var capSaveLocation:FlxText = null;
	var capLog:FlxText = null;
	var targetLines:Array<FlxText> = [];
	var logBg:FlxSprite = null;
	var logText:FlxText = null;
	var logTextW:Float = 0;

	// Rows.
	var nameField:InputField = null;
	var pathField:InputField = null;
	var renameCell:BlockSaveCell = null;
	var applyPathCell:BlockSaveCell = null;
	var modeCells:Array<BlockSaveCell> = [];
	var autoReloadCell:BlockSaveCell = null;
	var forceKeyboardCell:BlockSaveCell = null;
	var saveCell:BlockSaveCell = null;
	var saveRenameCell:BlockSaveCell = null;
	var reloadCell:BlockSaveCell = null;
	var closeCell:BlockSaveCell = null;
	var copyCell:BlockSaveCell = null;

	// Field placement, kept so the fields can follow the scroll offset.
	var nameFieldX:Float = 0;
	var nameFieldW:Float = 200;
	var nameFieldBaseY:Float = 0;
	var pathFieldX:Float = 0;
	var pathFieldW:Float = 200;
	var pathFieldBaseY:Float = 0;
	var nameFieldShown:Bool = false;
	var pathFieldShown:Bool = false;

	// Log.
	var logLines:Array<String> = [];

	// Pointer.
	var _ptrPoint:FlxPoint = new FlxPoint(0, 0);
	var ptrX:Float = 0;
	var ptrY:Float = 0;
	var ptrPressed:Bool = false;
	var ptrJustPressed:Bool = false;
	var ptrJustReleased:Bool = false;
	var _activeTouchID:Int = -1;
	var _pressedCell:BlockSaveCell = null;
	var _pressY:Float = 0;
	var _dragging:Bool = false;
	var _dragLastY:Float = 0;

	// Text entry.
	var _ownsSoftKeyboard:Bool = false;
	var _softField:InputField = null;
	var _keyboardAskedFor:InputField = null;

	/** Cached so the label refresh stays allocation free and only touches the text on change. */
	var _lastSaveAvailable:Bool = false;

	// =========================== build ===========================

	function buildWidgets():Void
	{
		scrim = addVisual(new FlxSprite(0, 0));
		scrim.makeGraphic(1, 1, FlxColor.WHITE);
		scrim.color = 0xFF000000;
		scrim.alpha = 0.45;

		panelBg = addVisual(new FlxSprite(0, 0));
		panelBg.makeGraphic(1, 1, FlxColor.WHITE);
		panelBg.color = COLOR_PANEL;

		capScriptName = addVisual(makeText('SCRIPT NAME', 14, COLOR_CAPTION));
		capTargets = addVisual(makeText('WHERE EACH MODE WRITES (default name blockcode.lua)', 14, COLOR_CAPTION));
		capSaveLocation = addVisual(makeText('SAVE LOCATION', 14, COLOR_CAPTION));
		capLog = addVisual(makeText('LOG', 14, COLOR_CAPTION));

		for (i in 0...3)
			targetLines.push(addVisual(makeText('', 14, COLOR_DIM)));

		logBg = addVisual(new FlxSprite(0, 0));
		logBg.makeGraphic(1, 1, FlxColor.WHITE);
		logBg.color = COLOR_BG;
		logText = addVisual(makeText('', 13, COLOR_TEXT));

		renameCell = addCell(new BlockSaveCell(0, 0, 10, CONTROL_HEIGHT, 'Rename', COLOR_ROW, COLOR_TEXT, 15));
		applyPathCell = addCell(new BlockSaveCell(0, 0, 10, CONTROL_HEIGHT, 'Apply', COLOR_ROW, COLOR_TEXT, 15));

		var segmentLabels:Array<String> = ['Song', 'Global', 'Custom'];
		var segmentNames:Array<String> = ['song', 'global', 'custom'];
		for (i in 0...segmentLabels.length)
		{
			var cell:BlockSaveCell = addCell(new BlockSaveCell(0, 0, 10, CONTROL_HEIGHT, segmentLabels[i], COLOR_ROW, COLOR_TEXT, 15));
			cell.modeName = segmentNames[i];
			modeCells.push(cell);
		}

		autoReloadCell = addCell(new BlockSaveCell(0, 0, 10, CONTROL_HEIGHT, '', COLOR_ROW_ON, COLOR_TEXT, 15));
		forceKeyboardCell = addCell(new BlockSaveCell(0, 0, 10, CONTROL_HEIGHT, '', COLOR_ROW_ON, COLOR_TEXT, 15));
		saveCell = addCell(new BlockSaveCell(0, 0, 10, CONTROL_HEIGHT, 'Save Lua', COLOR_OK, COLOR_DARK_TEXT, 15));
		saveRenameCell = addCell(new BlockSaveCell(0, 0, 10, CONTROL_HEIGHT, 'Save + Rename', COLOR_ACCENT, COLOR_TEXT, 15));
		reloadCell = addCell(new BlockSaveCell(0, 0, 10, CONTROL_HEIGHT, 'Reload block config', COLOR_ROW, COLOR_TEXT, 15));
		closeCell = addCell(new BlockSaveCell(0, 0, 10, CONTROL_HEIGHT, 'Close', COLOR_WARN, COLOR_DARK_TEXT, 15));
		copyCell = addCell(new BlockSaveCell(0, 0, 10, CONTROL_HEIGHT, 'Folder: -  (tap to copy)', COLOR_ROW, COLOR_TEXT, 15));

		scrollTrack = addVisual(new FlxSprite(0, 0));
		scrollTrack.makeGraphic(Std.int(SCROLLBAR_WIDTH), 1, FlxColor.WHITE);
		scrollTrack.color = COLOR_ROW;
		scrollTrack.alpha = 0.5;
		scrollThumb = addVisual(new FlxSprite(0, 0));
		scrollThumb.makeGraphic(Std.int(SCROLLBAR_WIDTH), Std.int(SCROLLBAR_MIN_HEIGHT), FlxColor.WHITE);
		scrollThumb.color = COLOR_DIM;

		headerBg = addVisual(new FlxSprite(0, 0));
		headerBg.makeGraphic(1, 1, FlxColor.WHITE);
		headerBg.color = COLOR_ACCENT;
		headerText = addVisual(makeText('SAVE / EXPORT', 20, COLOR_TEXT));
		headerHint = addVisual(makeText('', 14, COLOR_TEXT));
		headerHint.alignment = RIGHT;

		footerBg = addVisual(new FlxSprite(0, 0));
		footerBg.makeGraphic(1, 1, FlxColor.WHITE);
		footerBg.color = COLOR_BG;
		statusText = addVisual(makeText('', 15, COLOR_TEXT));
		configText = addVisual(makeText('', 13, COLOR_DIM));

		panelEdgeTop = addVisual(new FlxSprite(0, 0));
		panelEdgeTop.makeGraphic(1, 2, FlxColor.WHITE);
		panelEdgeTop.color = COLOR_SEPARATOR;
		panelEdgeBottom = addVisual(new FlxSprite(0, 0));
		panelEdgeBottom.makeGraphic(1, 2, FlxColor.WHITE);
		panelEdgeBottom.color = COLOR_SEPARATOR;

		nameField = makeField('blockcode');
		pathField = makeField('absolute path or folder');

		wireActions();
	}

	function addVisual<T:FlxSprite>(visual:T):T
	{
		visual.scrollFactor.set(0, 0);
		add(visual);
		return visual;
	}

	function addCell(cell:BlockSaveCell):BlockSaveCell
	{
		cells.push(cell);
		addVisual(cell);
		return cell;
	}

	function makeText(text:String, size:Int, color:Int):FlxText
	{
		var label:FlxText = new FlxText(0, 0, 0, text, size);
		label.setFormat(Paths.font("vcr.ttf"), size, color, LEFT);
		label.scrollFactor.set(0, 0);
		return label;
	}

	function makeField(placeholder:String):InputField
	{
		var field:InputField = new InputField(0, 0, 200, CONTROL_HEIGHT, '', ParamType.STRING, placeholder);
		assignFieldCamera(field);
		return field;
	}

	function wireActions():Void
	{
		renameCell.action = doRename;
		applyPathCell.action = applyCustomPath;
		saveCell.action = function():Void
		{
			saveWithRename(false);
		};
		saveRenameCell.action = function():Void
		{
			saveWithRename(true);
		};
		reloadCell.action = reloadBlockConfig;
		closeCell.action = close;
		copyCell.action = copyFolderPath;

		autoReloadCell.action = function():Void
		{
			_autoReload = !_autoReload;
			refreshInfo();
			playSound('scrollMenu');
			setStatus('auto-reload after save: ' + onOff(_autoReload), true);
		};

		forceKeyboardCell.action = function():Void
		{
			_forceVirtualKeyboard = !_forceVirtualKeyboard;
			refreshInfo();
			playSound('scrollMenu');
			setStatus('force in-game touch keyboard: ' + onOff(_forceVirtualKeyboard), true);
		};

		for (i in 0...modeCells.length)
		{
			var cell:BlockSaveCell = modeCells[i];
			cell.action = function():Void
			{
				setMode(cell.modeName);
			};
		}
	}

	// =========================== geometry and layout ===========================

	static function screenWidth():Int
	{
		return (FlxG.width > 0) ? Std.int(FlxG.width) : 1280;
	}

	static function screenHeight():Int
	{
		return (FlxG.height > 0) ? Std.int(FlxG.height) : 720;
	}

	function createCamera():FlxCamera
	{
		var camera:FlxCamera = new FlxCamera(0, 0, screenWidth(), screenHeight());
		camera.bgColor.alpha = 0;
		camera.zoom = 1;
		camera.scroll.set(0, 0);
		return camera;
	}

	function computeGeometry():Void
	{
		var width:Float = screenWidth();
		var height:Float = screenHeight();

		panelW = Math.min(Math.max(_requestedWidth, 320), Math.max(320, width - MARGIN * 2));
		panelX = Math.floor((width - panelW) * 0.5);
		panelY = MARGIN;
		panelH = Math.max(240, height - MARGIN * 2);

		contentTop = panelY + HEADER_HEIGHT;
		contentBottom = panelY + panelH - FOOTER_HEIGHT;

		var w:Int = Std.int(panelW);
		var h:Int = Std.int(panelH);
		if (_camW != w || _camH != h || cam.width != screenWidth() || cam.height != screenHeight())
		{
			_camW = w;
			_camH = h;
			cam.width = screenWidth();
			cam.height = screenHeight();
		}

		scrim.setPosition(0, 0);
		resizeSprite(scrim, screenWidth(), screenHeight());
		panelBg.setPosition(panelX, panelY);
		resizeSprite(panelBg, w, h);

		panelEdgeTop.setPosition(panelX, panelY);
		resizeSprite(panelEdgeTop, w, 2);
		panelEdgeBottom.setPosition(panelX, panelY + panelH - 2);
		resizeSprite(panelEdgeBottom, w, 2);

		headerBg.setPosition(panelX, panelY);
		resizeSprite(headerBg, w, Std.int(HEADER_HEIGHT));
		headerText.setPosition(panelX + PAD, panelY + 12);
		headerText.fieldWidth = Std.int(panelW * 0.45);
		headerHint.setPosition(panelX + panelW * 0.45, panelY + 16);
		headerHint.fieldWidth = Std.int(panelW * 0.55 - PAD);

		footerBg.setPosition(panelX, panelY + panelH - FOOTER_HEIGHT);
		resizeSprite(footerBg, w, Std.int(FOOTER_HEIGHT));
		statusText.setPosition(panelX + PAD, panelY + panelH - FOOTER_HEIGHT + 8);
		statusText.fieldWidth = Std.int(panelW - PAD * 2);
		configText.setPosition(panelX + PAD, panelY + panelH - FOOTER_HEIGHT + 30);
		configText.fieldWidth = Std.int(panelW - PAD * 2);

		scrollTrack.setPosition(panelX + panelW - SCROLLBAR_WIDTH - 4, contentTop);
		resizeSprite(scrollTrack, Std.int(SCROLLBAR_WIDTH), Std.int(Math.max(1, contentBottom - contentTop)));
		scrollThumb.setPosition(panelX + panelW - SCROLLBAR_WIDTH - 4, contentTop);
	}

	function layoutRows():Void
	{
		if (_settings == null)
			return;

		plains = [];

		var avail:Float = panelW - PAD * 2;
		var x0:Float = panelX + PAD;
		var fieldW:Float = Math.max(120, avail - SIDE_WIDTH - GAP);
		var halfW:Float = (avail - GAP) * 0.5;
		var customShown:Bool = (_mode == 'custom');
		var cursor:Float = 0;

		// Script name row.
		cursor = placePlain(capScriptName, x0, cursor, CAPTION_HEIGHT);
		nameFieldX = x0;
		nameFieldW = fieldW;
		nameFieldBaseY = contentTop + cursor + (ROW_HEIGHT - CONTROL_HEIGHT) * 0.5;
		nameField.width = nameFieldW;
		placeCell(renameCell, x0 + avail - SIDE_WIDTH, cursor, SIDE_WIDTH);
		cursor += ROW_HEIGHT + GAP;

		// Where every mode would write.
		cursor = placePlain(capTargets, x0, cursor, CAPTION_HEIGHT);
		for (line in targetLines)
			cursor = placePlain(line, x0, cursor, TARGET_LINE_HEIGHT);
		cursor += GAP;

		// Save location: the three exec modes plus the custom path row.
		cursor = placePlain(capSaveLocation, x0, cursor, CAPTION_HEIGHT);
		var segmentW:Float = (avail - GAP * 2) / 3;
		for (i in 0...modeCells.length)
			placeCell(modeCells[i], x0 + i * (segmentW + GAP), cursor, segmentW);
		cursor += ROW_HEIGHT + GAP;

		pathFieldX = x0;
		pathFieldW = fieldW;
		pathFieldBaseY = contentTop + cursor + (ROW_HEIGHT - CONTROL_HEIGHT) * 0.5;
		pathField.width = pathFieldW;
		placeCell(applyPathCell, x0 + avail - SIDE_WIDTH, cursor, SIDE_WIDTH);
		applyPathCell.shown = customShown;
		if (customShown)
			cursor += ROW_HEIGHT + GAP;

		// Options.
		placeCell(autoReloadCell, x0, cursor, avail);
		cursor += ROW_HEIGHT + GAP;
		placeCell(forceKeyboardCell, x0, cursor, avail);
		cursor += ROW_HEIGHT + GAP * 2;

		// Actions.
		placeCell(saveCell, x0, cursor, halfW);
		placeCell(saveRenameCell, x0 + halfW + GAP, cursor, halfW);
		cursor += ROW_HEIGHT + GAP;
		placeCell(reloadCell, x0, cursor, halfW);
		placeCell(closeCell, x0 + halfW + GAP, cursor, halfW);
		cursor += ROW_HEIGHT + GAP;
		placeCell(copyCell, x0, cursor, avail);
		cursor += ROW_HEIGHT + GAP * 2;

		// Log.
		cursor = placePlain(capLog, x0, cursor, CAPTION_HEIGHT);
		var logH:Float = 8 + LOG_LINES * (LOG_LINE_HEIGHT + 2) + 6;
		logTextW = avail - 16;
		placePlain(logBg, x0, cursor, logH);
		placePlain(logText, x0 + 8, cursor + 6, logH - 10);
		cursor += logH;

		contentHeight = cursor;
		maxScroll = Math.max(0, contentHeight - Math.max(1, contentBottom - contentTop));
		if (scrollY > maxScroll)
			scrollY = maxScroll;

		refreshLog();
		_appliedScrollY = -1;
	}

	function placeCell(cell:BlockSaveCell, x:Float, cursor:Float, w:Float):Void
	{
		var y:Float = contentTop + cursor + (ROW_HEIGHT - CONTROL_HEIGHT) * 0.5;
		cell.baseY = y;
		cell.setRect(x, y, w, CONTROL_HEIGHT);
	}

	function placePlain(sprite:FlxSprite, x:Float, cursor:Float, height:Float):Float
	{
		plains.push({
			sprite: sprite,
			baseY: contentTop + cursor,
			height: height
		});
		sprite.x = x;
		sprite.y = contentTop + cursor;

		return cursor + height;
	}

	static function resizeSprite(sprite:FlxSprite, w:Int, h:Int):Void
	{
		if (sprite == null)
			return;

		var width:Int = Std.int(Math.max(w, 1));
		var height:Int = Std.int(Math.max(h, 1));
		if (Std.int(sprite.width) == width && Std.int(sprite.height) == height)
			return;

		// White graphic plus `color` tint, so resizing never loses the theme colour.
		sprite.makeGraphic(width, height, FlxColor.WHITE);
	}

	/**
	 * Items no taller than the header/footer bands may overlap them - those two are drawn on top,
	 * which looks like clipping. Taller ones are only shown while they fit completely.
	 */
	static function shouldShow(y:Float, height:Float, top:Float, bottom:Float):Bool
	{
		if (height > MAX_PARTIAL_HEIGHT)
			return (y >= top - 0.5) && (y + height <= bottom + 0.5);

		return (y + height > top) && (y < bottom);
	}

	// =========================== scrolling ===========================

	function setScroll(value:Float):Void
	{
		if (value < 0)
			value = 0;
		if (value > maxScroll)
			value = maxScroll;

		if (value == scrollY)
			return;

		scrollY = value;
		applyScroll();
	}

	function applyScroll():Void
	{
		if (_settings == null)
			return;

		var top:Float = contentTop;
		var bottom:Float = contentBottom;

		for (cell in cells)
		{
			var y:Float = cell.baseY - scrollY;
			cell.moveTo(y);
			cell.visible = cell.shown && shouldShow(y, cell.hitH, top, bottom);
		}

		for (entry in plains)
		{
			var y:Float = entry.baseY - scrollY;
			entry.sprite.y = y;
			entry.sprite.visible = shouldShow(y, entry.height, top, bottom);
		}

		syncFields();
		updateScrollBar();
		_appliedScrollY = scrollY;
	}

	function updateScrollBar():Void
	{
		var available:Bool = (maxScroll > 0.5) && (contentBottom > contentTop);
		scrollTrack.visible = available;
		scrollThumb.visible = available;
		if (!available)
			return;

		var viewH:Float = contentBottom - contentTop;
		var thumbH:Float = Math.max(SCROLLBAR_MIN_HEIGHT, viewH * viewH / Math.max(contentHeight, 1));
		scrollThumb.scale.y = thumbH / SCROLLBAR_MIN_HEIGHT;
		scrollThumb.y = contentTop + (viewH - thumbH) * (scrollY / maxScroll);
	}

	function beginDrag():Void
	{
		if (maxScroll <= 0)
			return;

		_dragging = true;
		_dragLastY = ptrY;
	}

	function updateScrollInput():Void
	{
		if (maxScroll <= 0)
		{
			_dragging = false;
		}
		else
		{
			if (FlxG.mouse != null && FlxG.mouse.wheel != 0)
				setScroll(scrollY - FlxG.mouse.wheel * WHEEL_STEP);

			if (_dragging)
			{
				if (ptrPressed)
				{
					setScroll(scrollY + (_dragLastY - ptrY));
					_dragLastY = ptrY;
				}
				else
				{
					_dragging = false;
				}
			}
		}

		#if !mobile
		if (!nameField.isFocused && !pathField.isFocused)
		{
			if (FlxG.keys.justPressed.PAGEUP)
				setScroll(scrollY - ROW_STEP * 2);
			else if (FlxG.keys.justPressed.PAGEDOWN)
				setScroll(scrollY + ROW_STEP * 2);
		}
		#end
	}

	// =========================== pointers ===========================

	function pollPointer():Void
	{
		ptrPressed = false;
		ptrJustPressed = false;
		ptrJustReleased = false;

		#if FLX_TOUCH
		if (FlxG.touches != null && pollTouch())
			return;
		#end

		if (FlxG.mouse == null)
			return;

		var point:FlxPoint = FlxG.mouse.getScreenPosition(cam, _ptrPoint);
		ptrX = point.x;
		ptrY = point.y;
		ptrPressed = FlxG.mouse.pressed;
		ptrJustPressed = FlxG.mouse.justPressed;
		ptrJustReleased = FlxG.mouse.justReleased;
	}

	#if FLX_TOUCH
	/** Reads the touch that owns the sheet, claiming the first new one inside it. Returns false to fall back to the mouse. */
	function pollTouch():Bool
	{
		if (_activeTouchID >= 0)
		{
			for (touch in FlxG.touches.list)
			{
				if (touch == null || touch.touchPointID != _activeTouchID)
					continue;

				updatePointerFrom(touch);
				if (!ptrPressed)
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

			updatePointerFrom(touch);
			if (!inPanelArea(ptrX, ptrY))
			{
				_activeTouchID = -1;
				ptrPressed = false;
				ptrJustPressed = false;
				return false;
			}

			_activeTouchID = touch.touchPointID;
			return true;
		}

		return false;
	}

	function updatePointerFrom(touch:FlxTouch):Void
	{
		var point:FlxPoint = touch.getScreenPosition(cam, _ptrPoint);
		ptrX = point.x;
		ptrY = point.y;
		ptrPressed = touch.pressed;
		ptrJustPressed = touch.justPressed;
		ptrJustReleased = touch.justReleased;
	}
	#end

	function inPanelArea(x:Float, y:Float):Bool
	{
		return (x >= panelX && x <= panelX + panelW && y >= panelY && y <= panelY + panelH);
	}

	function inContentArea(x:Float, y:Float):Bool
	{
		return (x >= panelX && x <= panelX + panelW && y >= contentTop && y <= contentBottom);
	}

	function handlePointer():Void
	{
		// While the soft keyboard is up its own field covers part of the sheet: the first tap only dismisses it.
		var typing:Bool = _ownsSoftKeyboard && BlockSoftKeyboard.isOpen();

		if (ptrJustPressed && !typing)
		{
			var cell:BlockSaveCell = cellAt(ptrX, ptrY);
			_pressedCell = cell;
			_pressY = ptrY;
			if (cell != null)
				cell.setPressed(true);
		}

		if (ptrPressed && _pressedCell != null)
		{
			// A finger that slides off the row (or far enough) cancels the press and scrolls instead.
			if (!_pressedCell.containsPoint(ptrX, ptrY) || Math.abs(ptrY - _pressY) > DRAG_CANCEL)
			{
				_pressedCell.setPressed(false);
				_pressedCell = null;
				beginDrag();
			}
		}

		if (ptrJustReleased)
		{
			var cell:BlockSaveCell = _pressedCell;
			_pressedCell = null;
			if (cell != null)
			{
				cell.setPressed(false);
				if (cell.containsPoint(ptrX, ptrY))
					activateCell(cell);
			}

			_dragging = false;
		}

		if (ptrJustPressed && !typing && _pressedCell == null && maxScroll > 0 && inContentArea(ptrX, ptrY))
			beginDrag();
	}

	function cellAt(x:Float, y:Float):BlockSaveCell
	{
		for (cell in cells)
		{
			if (cell.visible && cell.shown && cell.containsPoint(x, y))
				return cell;
		}

		return null;
	}

	function activateCell(cell:BlockSaveCell):Void
	{
		if (cell == null || cell.action == null)
			return;

		cell.action();
	}

	// =========================== text entry ===========================

	function assignFieldCamera(field:InputField):Void
	{
		if (field == null)
			return;

		if (field.bg != null)
			field.bg.cameras = [cam];
		if (field.text != null)
			field.text.cameras = [cam];
		if (field.placeholderText != null)
			field.placeholderText.cameras = [cam];
	}

	function setFieldVisible(field:InputField, value:Bool):Void
	{
		if (field == null)
			return;

		if (field.bg != null)
			field.bg.visible = value;
		if (field.text != null)
			field.text.visible = value;
		if (field.placeholderText != null)
			field.placeholderText.visible = value && (field.placeholderText.text.length > 0);
	}

	function drawField(field:InputField):Void
	{
		if (field == null || field.bg == null || !field.bg.visible)
			return;

		field.draw();
	}

	function destroyField(field:InputField):Void
	{
		if (field == null)
			return;

		FlxDestroyUtil.destroy(field.bg);
		FlxDestroyUtil.destroy(field.text);
		FlxDestroyUtil.destroy(field.placeholderText);
		field.bg = null;
		field.text = null;
		field.placeholderText = null;
	}

	/** Places the inline fields in the scrolled content and hides them when they leave the view. */
	function syncFields():Void
	{
		if (nameField == null || pathField == null)
			return;

		var nameY:Float = nameFieldBaseY - scrollY;
		nameFieldShown = shouldShow(nameY, CONTROL_HEIGHT, contentTop, contentBottom);
		if (nameFieldShown)
			nameField.updatePosition(nameFieldX, nameY);
		setFieldVisible(nameField, nameFieldShown);
		if (!nameFieldShown && nameField.isFocused)
			nameField.unfocus();

		var pathY:Float = pathFieldBaseY - scrollY;
		pathFieldShown = (_mode == 'custom') && shouldShow(pathY, CONTROL_HEIGHT, contentTop, contentBottom);
		if (pathFieldShown)
			pathField.updatePosition(pathFieldX, pathY);
		setFieldVisible(pathField, pathFieldShown);
		if (!pathFieldShown && pathField.isFocused)
			pathField.unfocus();
	}

	function updateFields(elapsed:Float):Void
	{
		// While the OpenFL input field is up it owns the keys; the inline fields would duplicate them.
		var typing:Bool = _ownsSoftKeyboard && BlockSoftKeyboard.isOpen();
		if (!typing)
		{
			var nameWasFocused:Bool = nameField.isFocused;
			var pathWasFocused:Bool = pathField.isFocused;

			if (nameFieldShown)
				nameField.update(elapsed);
			if (pathFieldShown)
				pathField.update(elapsed);

			// Only one field may hold the caret: the one that just took it wins.
			if (nameField.isFocused && pathField.isFocused)
			{
				if (!nameWasFocused)
					pathField.unfocus();
				else if (!pathWasFocused)
					nameField.unfocus();
				else
					nameField.unfocus();
			}
		}

		handleFallbackKeyboard();
	}

	/**
	 * Opens `BlockSoftKeyboard` for the focused field when nobody installed `Block.requestTextEdit`.
	 * Only a focus change opens it, so dismissing the keyboard does not immediately reopen it, and the
	 * close callback drops the focus so the next tap starts a new session. On targets without a native
	 * IME the inline field types from the hardware keyboard itself (see `InputField.update`), and a
	 * second OpenFL field on top of it would apply every character twice.
	 */
	function handleFallbackKeyboard():Void
	{
		if (Block.requestTextEdit != null || !BlockSoftKeyboard.isNativeAvailable())
		{
			_keyboardAskedFor = null;
			return;
		}

		if (BlockSoftKeyboard.isOpen())
			return;

		var focused:InputField = null;
		if (nameField.isFocused && nameFieldShown)
			focused = nameField;
		else if (pathField.isFocused && pathFieldShown)
			focused = pathField;

		if (focused == null)
		{
			_keyboardAskedFor = null;
			return;
		}

		if (focused == _keyboardAskedFor)
			return;

		_keyboardAskedFor = focused;
		openSoftKeyboard(focused);
	}

	function openSoftKeyboard(field:InputField):Void
	{
		var x:Float = (field == nameField) ? nameFieldX : pathFieldX;
		var w:Float = (field == nameField) ? nameFieldW : pathFieldW;
		var baseY:Float = (field == nameField) ? nameFieldBaseY : pathFieldBaseY;

		_softField = field;
		_ownsSoftKeyboard = true;

		BlockSoftKeyboard.targetRect = new Rectangle(x, baseY - scrollY, Math.max(w, 80), CONTROL_HEIGHT);
		BlockSoftKeyboard.open(Std.string(field.value), false, function(text:String):Void
		{
			applySoftKeyboardText(text);
		}, function():Void
		{
			onSoftKeyboardClosed();
		});
	}

	function applySoftKeyboardText(text:String):Void
	{
		var field:InputField = _softField;
		if (field == null || field.text == null)
			return;

		field.text.text = (text != null) ? text : '';
		field.commit();
	}

	function onSoftKeyboardClosed():Void
	{
		var field:InputField = _softField;
		_softField = null;
		_ownsSoftKeyboard = false;

		if (field == null)
			return;

		field.commit();
		field.unfocus(); // so the next tap on the row starts a new edit session
		commitField(field);
	}

	/** Stores an edited field in the settings, so the panel shows and saves the very same values. */
	function commitField(field:InputField):Void
	{
		if (_settings == null || field == null)
			return;

		if (field == nameField)
		{
			var name:String = BlockFileIO.sanitizeName(Std.string(field.value));
			field.value = name;
			_settings.scriptName = name;
			setStatus('script name: ' + name + '  (Rename moves the existing file)', true);
		}
		else
		{
			_customPath = Std.string(field.value).trim();
			_settings.customExecPath = _customPath;
			setStatus('custom path: ' + ((_customPath.length > 0) ? _customPath : '(empty - the default folder is used)'), true);
		}

		refreshInfo();
	}

	// =========================== state <-> settings ===========================

	function readSettings():Void
	{
		_mode = (_settings.execMode != null) ? _settings.execMode : 'song';
		if (_mode != 'song' && _mode != 'global' && _mode != 'custom')
			_mode = 'song';

		_autoReload = _settings.autoReload;
		_forceVirtualKeyboard = _settings.forceVirtualKeyboard;
		_customPath = (_settings.customExecPath != null) ? _settings.customExecPath : '';

		nameField.value = ((_settings.scriptName != null) && (_settings.scriptName.length > 0)) ? _settings.scriptName : BlockTypes.DEFAULT_SCRIPT_NAME;
		pathField.value = _customPath;

		setFieldVisible(nameField, true);
		setFieldVisible(pathField, (_mode == 'custom'));
	}

	function currentName():String
	{
		return Std.string(nameField.value);
	}

	function setMode(mode:String):Void
	{
		if (mode == null || mode == _mode)
			return;

		_mode = mode;
		applyTo(_settings);
		refreshInfo();
		playSound('scrollMenu');

		if (_mode != 'custom')
			pathField.unfocus();

		layoutRows();
		applyScroll();
		setStatus('save location: ' + modeLabel(_mode), true);
	}

	function applyCustomPath():Void
	{
		if (pathFieldShown)
			commitField(pathField);
		else
			setStatus('switch to the Custom mode to edit the path', false);
	}

	// =========================== operations ===========================

	function saveWithRename(renameFirst:Bool):Void
	{
		if (_settings == null)
			return;

		applyTo(_settings);

		var renamed:String = '';
		if (renameFirst)
		{
			renamed = BlockFileIO.rename(_settings, currentName(), _songName);
			nameField.value = _settings.scriptName;
		}

		if (codeProvider == null)
		{
			setStatus('nothing to save - the editor has not handed over its code yet', false);
			addLog('save skipped: no code source attached');
			playSound('cancelMenu');
			refreshInfo();
			return;
		}

		var code:String = codeProvider();
		if (code == null)
			code = '';

		var path:String = BlockFileIO.save(_settings, code, _songName);
		refreshInfo();

		if (path.length < 1)
		{
			setStatus('save failed: ' + BlockFileIO.describe(_settings, _songName), false);
			addLog('could not write ' + BlockFileIO.resolveTarget(_settings, _songName));
			playSound('cancelMenu');
			return;
		}

		setStatus('saved ' + path + (_autoReload ? '  (auto-reload on)' : ''), true);
		addLog('saved ' + path + ' (' + countLines(code) + ' lines)');
		if (renamed.length > 0 && renamed != path)
			addLog('renamed to ' + renamed);

		playSound('confirmMenu');

		if (onSaved != null)
			onSaved(path);
	}

	function doRename():Void
	{
		if (_settings == null)
			return;

		// Resolve the path the file lives at now, before the edited name is written into the settings.
		var previous:String = BlockFileIO.resolveTarget(_settings, _songName);
		var wanted:String = currentName();

		applyTo(_settings);

		var path:String = BlockFileIO.rename(_settings, wanted, _songName);
		nameField.value = _settings.scriptName;
		refreshInfo();

		if (path.length < 1)
		{
			setStatus('rename failed - no target path could be resolved', false);
			addLog('rename failed for "' + wanted + '"');
			playSound('cancelMenu');
			return;
		}

		setStatus('renamed to ' + path, true);
		addLog('renamed ' + previous + ' -> ' + path);
		playSound('confirmMenu');

		if (onSaved != null)
			onSaved(path);
	}

	function reloadBlockConfig():Void
	{
		BlockLibrary.reload();

		var errors:Array<String> = BlockConfigLoader.lastErrors();
		var blockCount:Int = BlockLibrary.allBlocks().length;
		var categoryCount:Int = BlockLibrary.categories.length;

		refreshConfigLine();

		if (errors == null || errors.length == 0)
		{
			setStatus('block config reloaded: ' + categoryCount + ' categories, ' + blockCount + ' blocks, no errors', true);
			addLog('config reloaded: ' + categoryCount + ' categories / ' + blockCount + ' blocks');
			playSound('confirmMenu');
			return;
		}

		setStatus('block config reloaded with ' + errors.length + ' error(s) - see the log', false);
		for (message in errors)
			addLog('config: ' + message);
		playSound('cancelMenu');
	}

	function copyFolderPath():Void
	{
		if (_settings == null)
			return;

		var dir:String = BlockFileIO.resolveDir(_settings, _songName);
		if (dir.length < 1)
		{
			setStatus('no folder to copy for this mode', false);
			playSound('cancelMenu');
			return;
		}

		try
		{
			openfl.system.System.setClipboard(dir);
			setStatus('folder path copied: ' + dir, true);
			addLog('copied folder: ' + dir);
			playSound('confirmMenu');
		}
		catch (e:Dynamic)
		{
			setStatus('this platform does not allow copying text', false);
			playSound('cancelMenu');
		}
	}

	// =========================== info, log, status ===========================

	function refreshInfo():Void
	{
		if (_settings == null)
			return;

		for (cell in modeCells)
			cell.setActive(cell.modeName == _mode);

		autoReloadCell.setText((_autoReload ? '[x]' : '[ ]') + '  Auto-reload script after save');
		autoReloadCell.setActive(_autoReload);
		forceKeyboardCell.setText((_forceVirtualKeyboard ? '[x]' : '[ ]') + '  Force in-game touch keyboard');
		forceKeyboardCell.setActive(_forceVirtualKeyboard);

		var avail:Float = panelW - PAD * 2;
		var targets:Array<String> = BlockFileIO.execTargetsFor(_songName);
		var modes:Array<String> = ['song', 'global', 'custom'];
		for (i in 0...targetLines.length)
		{
			var line:FlxText = targetLines[i];
			var path:String = (i < targets.length) ? targets[i] : '';
			var exists:Bool = (path.length > 0) && BlockFileIO.exists(path);
			var active:Bool = (modes[i] == _mode);

			line.text = (active ? '> ' : '  ') + modes[i] + ': ' + fitWidth(path, avail - 90, 14) + (exists ? '  [exists]' : '  [new]');
			line.color = active ? COLOR_TEXT : COLOR_DIM;
		}

		headerHint.text = fitWidth(shortTarget(), panelW * 0.55 - PAD, 14);
		copyCell.setText('Folder: ' + fitWidth(BlockFileIO.resolveDir(_settings, _songName), avail - 150, 15) + '  (tap to copy)');
	}

	function shortTarget():String
	{
		if (_settings == null)
			return '';

		return BlockFileIO.describe(_settings, _songName);
	}

	function refreshConfigLine():Void
	{
		var signature:String = BlockConfigLoader.configSignature();
		var files:Int = 0;
		var runtime:Int = 0;
		var sample:String = '';

		for (part in signature.split('\n'))
		{
			var line:String = part.trim();
			if (line.length < 1)
				continue;

			if (line.startsWith('runtime|'))
			{
				var parsed:Null<Int> = Std.parseInt(line.substr(8));
				if (parsed != null)
					runtime = parsed;
				continue;
			}

			files++;
			if (sample.length < 1)
				sample = baseName(line);
		}

		var text:String = 'config files: ' + files;
		if (sample.length > 0)
			text += ' (' + sample + ')';
		text += '   runtime blocks: ' + runtime;
		configText.text = fitWidth(text, panelW - PAD * 2, 13);
	}

	static function baseName(part:String):String
	{
		var file:String = part.split('|')[0];
		var slash:Int = file.lastIndexOf('/');
		return (slash >= 0) ? file.substr(slash + 1) : file;
	}

	function setStatus(message:String, ok:Bool):Void
	{
		statusText.color = ok ? COLOR_OK : COLOR_WARN;
		statusText.text = fitWidth(message, panelW - PAD * 2, 15);
	}

	function addLog(message:String):Void
	{
		if (message == null)
			return;

		logLines.push(message);
		while (logLines.length > MAX_LOG_ENTRIES)
			logLines.shift();

		refreshLog();
	}

	function refreshLog():Void
	{
		if (logText == null)
			return;

		var shown:Array<String> = [];
		var start:Int = Std.int(Math.max(0, logLines.length - LOG_LINES));
		for (i in start...logLines.length)
			shown.push(fitWidth(logLines[i], logTextW, 13));

		logText.text = shown.join('\n');
	}

	function refreshSaveLabels(force:Bool):Void
	{
		var available:Bool = (codeProvider != null);
		if (!force && available == _lastSaveAvailable)
			return;

		_lastSaveAvailable = available;
		saveCell.setText(available ? 'Save Lua' : 'Save Lua (no code)');
		saveRenameCell.setText(available ? 'Save + Rename' : 'Save + Rename (no code)');
	}

	/**
	 * Shortens `text` so it fits `maxWidth` at `fontSize`. The font is not measured; the estimate
	 * keeps the end of the string (the file name) visible, which is what a path row is for.
	 */
	static function fitWidth(text:String, maxWidth:Float, fontSize:Int):String
	{
		if (text == null)
			return '';
		if (maxWidth <= 0)
			return text;

		var maxChars:Int = Std.int(maxWidth / (fontSize * FIELD_LABEL_WIDTH));
		if (maxChars < 8)
			maxChars = 8;
		if (text.length <= maxChars)
			return text;

		var tail:Int = Std.int((maxChars - ELLIPSIS.length) * 0.6);
		var head:Int = maxChars - tail - ELLIPSIS.length;
		if (head < 1)
			head = 1;

		return text.substr(0, head) + ELLIPSIS + text.substr(text.length - tail);
	}

	static function countLines(code:String):Int
	{
		if (code == null || code.length < 1)
			return 0;

		return code.split('\n').length;
	}

	static function onOff(value:Bool):String
	{
		return value ? 'on' : 'off';
	}

	static function modeLabel(mode:String):String
	{
		if (mode == 'global')
			return 'global (mods scripts folder)';
		if (mode == 'custom')
			return 'custom path';

		return 'song (current song script)';
	}

	function playSound(name:String):Void
	{
		if (FlxG.sound == null)
			return;

		try
		{
			FlxG.sound.play(Paths.sound(name));
		}
		catch (e:Dynamic)
		{
			// A missing or blocked sound must never break the panel.
		}
	}

	// =========================== camera plumbing ===========================

	/** Keeps the panel's camera in `FlxG.cameras` (last, i.e. on top) while the panel is open. */
	function ensureCamera():Void
	{
		if (!_isOpen || FlxG.cameras == null)
			return;

		if (cam == null || cam.flashSprite == null)
		{
			cam = createCamera();
			cameras = [cam];
			assignFieldCamera(nameField);
			assignFieldCamera(pathField);
			_camW = 0;
			_camH = 0;
			computeGeometry();
			layoutRows();
			applyScroll();
		}

		var list:Array<FlxCamera> = FlxG.cameras.list;
		if (list != null && list.indexOf(cam) != -1)
			return;

		FlxG.cameras.add(cam, false);
	}

	function detachCamera():Void
	{
		if (cam == null || FlxG.cameras == null)
			return;

		var list:Array<FlxCamera> = FlxG.cameras.list;
		if (list != null && list.indexOf(cam) != -1)
			FlxG.cameras.remove(cam, false);
	}
}

/**
 * One touch target of `BlockSavePanel`: a flat rectangle, its label and the action it fires.
 *
 * The label is drawn by `draw()` (the way `Block` draws its own label and icon) instead of being a
 * group member, so a row stays one object for hit testing, scrolling and colour state.
 */
private class BlockSaveCell extends FlxSprite
{
	/** Row background colour while the cell is not the switched on choice. */
	public var normalColor:Int = 0xFF24283B;

	/** Row background colour while the cell is switched on. */
	public var activeColor:Int = 0xFF24283B;

	/** Fired on release over the cell. */
	public var action:Void->Void = null;

	/** Rows the current mode does not use are hidden by the panel. */
	public var shown:Bool = true;

	/** Unscrolled top edge, used by the panel's scrolling. */
	public var baseY:Float = 0;

	public var hitW:Float = 0;
	public var hitH:Float = 0;

	/** Exec mode this cell selects; only set for the segmented selector. */
	public var modeName:String = '';

	public var label:FlxText = null;

	var fontSize:Int = 15;
	var labelOffsetY:Float = 0;
	var isActive:Bool = false;
	var isPressed:Bool = false;

	public function new(x:Float, y:Float, w:Float, h:Float, text:String, color:Int, textColor:Int, size:Int = 15)
	{
		super(x, y);

		fontSize = size;
		normalColor = color;
		activeColor = color;

		makeGraphic(Std.int(Math.max(w, 1)), Std.int(Math.max(h, 1)), FlxColor.WHITE);

		label = new FlxText(x + 8, y, Std.int(Math.max(w - 16, 16)), text, size);
		label.setFormat(Paths.font("vcr.ttf"), size, textColor, CENTER);
		label.scrollFactor.set(0, 0);

		setRect(x, y, w, h);
		refreshColor();
	}

	public function setActive(value:Bool):Void
	{
		if (isActive == value)
			return;

		isActive = value;
		refreshColor();
	}

	public function setPressed(value:Bool):Void
	{
		if (isPressed == value)
			return;

		isPressed = value;
		refreshColor();
	}

	public function setText(text:String):Void
	{
		if (label != null)
			label.text = text;
	}

	public function setRect(x:Float, y:Float, w:Float, h:Float):Void
	{
		hitW = Math.max(w, 1);
		hitH = Math.max(h, 1);
		baseY = y;

		var iw:Int = Std.int(hitW);
		var ih:Int = Std.int(hitH);
		if (Std.int(width) != iw || Std.int(height) != ih)
			makeGraphic(iw, ih, FlxColor.WHITE);

		this.x = x;
		this.y = y;

		if (label != null)
		{
			labelOffsetY = (hitH - fontSize) * 0.5 - 2;
			label.fieldWidth = Std.int(Math.max(hitW - 16, 16));
			label.x = x + 8;
			label.y = y + labelOffsetY;
		}
	}

	/** Follows the panel's scroll offset; the label moves with the cell. */
	public function moveTo(y:Float):Void
	{
		this.y = y;
		if (label != null)
			label.y = y + labelOffsetY;
	}

	public function containsPoint(x:Float, y:Float):Bool
	{
		return (x >= this.x && x <= this.x + hitW && y >= this.y && y <= this.y + hitH);
	}

	override public function draw():Void
	{
		super.draw();

		if (label == null || !label.visible)
			return;

		label.scrollFactor.copyFrom(scrollFactor);
		label.cameras = cameras;
		label.draw();
	}

	override public function destroy():Void
	{
		FlxDestroyUtil.destroy(label);
		label = null;
		super.destroy();
	}

	function refreshColor():Void
	{
		var tint:FlxColor = FlxColor.fromInt(isActive ? activeColor : normalColor);

		if (isPressed)
			tint = tint.getLightened(0.12);

		color = tint;
	}
}
