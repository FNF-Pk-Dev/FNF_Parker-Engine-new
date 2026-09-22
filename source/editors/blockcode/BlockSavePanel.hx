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
import openfl.text.TextField;
import openfl.text.TextFormat;

/** One wrapped line of a multi-line block: the text plus the colour it is drawn in. */
private typedef SaveLine =
{
	var text:String;
	var color:Int;
}

/**
 * Save / export settings sheet of the block-code editor substate.
 *
 * The panel owns no code of its own: it edits the fields of a `BlockCodeEditorSettings` (script
 * name, save location, exec mode, custom path, auto-reload, forced touch keyboard) and writes the
 * generated Lua through `BlockFileIO` when the substate hands it over. The substate assigns
 * `codeProvider` once - the callback that generates the Lua of the current blocks - and reacts to
 * `onSaved` / `onClosed`; layout, hit testing, scrolling, status and log stay inside this group.
 *
 * Everything is sized from `BlockLayout`, so the sheet survives a 60px desktop banner, a phone in
 * landscape, a phone held upright and a tablet: `BlockLayout.panelSize()` bounds the sheet, rows are
 * at least `BlockLayout.touchSize()` tall, fonts come from `BlockLayout.font()` and the padding from
 * `BlockLayout.scale`. Each setting sits on its own row with a plain-language label on the left and
 * its control on the right; sections are titled and separated, and the body is split into two
 * columns when the viewport is wide and upright screens get one scrollable column instead. The save
 * buttons are pinned in the footer band, outside the scroll area, so a thumb always reaches them.
 *
 * Self contained on purpose: the panel creates its own full screen `FlxCamera`, appends it to
 * `FlxG.cameras` (last, i.e. on top) on `open()` and removes it again on `close()`, so the rows
 * stay aligned with the screen whatever the editor does to its own cameras. Every sprite is drawn
 * through that camera with `scrollFactor == 0`, which also makes screen coordinates and panel
 * coordinates identical - `FlxPointer.getScreenPosition(cam)` is the hit test point, and the panel
 * camera is never scrolled or zoomed.
 *
 * `draw()` paints three layers: the sheet background (`underChrome`), the scrolling content (the
 * group members) and the fixed chrome (`overChrome` - header and footer bands, the pinned buttons,
 * the scroll bar, the panel edges). Because the bands are painted last, a block that scrolls behind
 * them is covered by them instead of being drawn over them, so only the tall block rows are allowed
 * to be half visible (`shouldShow`) while rows and tags always need to fit (`fitsInside`); the two
 * inline fields are drawn by hand as well and therefore also need to fit completely.
 *
 * Pointers are read from `FlxG.touches` first (only the first touch inside the sheet drives it) and
 * from `FlxG.mouse` as the desktop fallback. A row fires on release over the same row; a finger
 * that slides further than `DRAG_CANCEL` cancels the press and scrolls the content instead. The
 * footer buttons are hit tested before the scrolling rows, since they never move, and a row that a
 * band covers is not clickable there.
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

	/** Track of a switch that is off. */
	public static inline var COLOR_SWITCH_OFF:Int = 0xFF313244;

	/** Track of a switch that is on. */
	public static inline var COLOR_SWITCH_ON:Int = 0xFF9ECE6A;

	// --- Metrics ---

	/** Padding between the sheet border and its content, times `BlockLayout.scale`. */
	static inline var PAD_FACTOR:Float = 12;

	/** A row is at least this tall (times scale), and never shorter than a touch target. */
	static inline var ROW_FACTOR:Float = 46;

	/** The sheet never grows wider than this (times scale), even on a very wide viewport. */
	static inline var MAX_PANEL_WIDTH:Float = 1100;

	static inline var MIN_PANEL_WIDTH:Float = 280;
	static inline var MIN_PANEL_HEIGHT:Float = 240;
	static inline var EDGE_HEIGHT:Int = 2;

	/** Width of the section separator lines. */
	static inline var SEPARATOR_FACTOR:Float = 1.5;

	/** Two columns need at least this much usable width. */
	static inline var TWO_COLUMN_MIN:Float = 520;

	/** Rough share of one character width in the UI font, only used when measuring is impossible. */
	static inline var CHAR_WIDTH_FALLBACK:Float = 0.64;

	static inline var PREVIEW_LINES:Int = 10;
	static inline var TARGET_LINES:Int = 14;
	static inline var LOG_LINES:Int = 6;
	static inline var ERROR_LINES:Int = 5;
	static inline var MESSAGE_MAX_LINES:Int = 2;

	static inline var MAX_LOG_ENTRIES:Int = 60;
	static inline var DRAG_CANCEL:Float = 14;
	static inline var WHEEL_STEP:Float = 34;
	static inline var SCROLLBAR_MIN_HEIGHT:Float = 32;
	static inline var SCROLLBAR_FACTOR:Float = 5;
	static inline var ELLIPSIS:String = '...';

	static var MODE_LABELS:Array<String> = ['Song script', 'Global script', 'Custom folder'];
	static var SHORT_MODE_LABELS:Array<String> = ['Song', 'Global', 'Custom'];
	static var MODE_NAMES:Array<String> = ['song', 'global', 'custom'];

	static var MODE_HELP:Array<String> = [
		'Song script - written into this song\'s data folder and loaded together with the song.',
		'Global script - written into the mod\'s scripts folder and loaded in every song.',
		'Custom folder - written to a folder you type yourself, anywhere on the disk.'
	];

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

		_requestedWidth = (width > 0) ? width : BlockLayout.BASE_WIDTH;
		BlockLayout.ensure();

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
		BlockLayout.ensure();

		_settings = (settings != null) ? settings : BlockTypes.defaultSettings();
		_songName = (songName != null) ? songName : '';

		readSettings();
		refreshConfig();
		refreshPreviewCode();
		refreshInfo();

		_isOpen = true;
		visible = true;
		active = true;
		ensureCamera();

		_keyboardAskedFor = null;
		_pressedCell = null;
		_dragging = false;
		scrollY = 0;

		computeGeometry();
		layoutRows();
		applyScroll();
		refreshSaveLabels(true);

		addLog('save panel opened for "' + ((_songName.length > 0) ? _songName : 'no song') + '"');
		setStatus('target: ' + currentTarget(), true);
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
		syncViewport();
		pollPointer();
		handlePointer();
		updateScrollInput();
		updateFields(elapsed);
		refreshSaveLabels(false);

		if (_needsLayout)
		{
			_needsLayout = false;
			layoutRows();
			applyScroll();
		}
		else if (scrollY != _appliedScrollY)
		{
			applyScroll();
		}
	}

	override public function draw():Void
	{
		if (!visible)
			return;

		drawChrome(underChrome);
		super.draw();
		drawChrome(overChrome);

		// InputFields are not FlxBasic and cannot be group members; their parts carry `cam`.
		drawField(nameField);
		drawField(pathField);
	}

	function drawChrome(list:Array<FlxSprite>):Void
	{
		if (list == null)
			return;

		for (sprite in list)
		{
			if (sprite == null || !sprite.visible || !sprite.exists)
				continue;

			sprite.draw();
		}
	}

	override public function destroy():Void
	{
		detachCamera();
		if (cam != null)
		{
			cam.destroy();
			cam = null;
		}

		// The chrome is drawn by hand rather than being a group member, so it is destroyed here.
		for (list in [underChrome, overChrome])
		{
			if (list == null)
				continue;

			for (sprite in list)
				FlxDestroyUtil.destroy(sprite);
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
		pinnedCells = null;
		modeCells = null;
		plains = null;
		underChrome = null;
		overChrome = null;
		targetPool = null;
		codePool = null;
		errorPool = null;
		logPool = null;
		labelPool = null;
		hintPool = null;
		seps = null;
		_configErrors = null;
		_previewLines = null;

		super.destroy();
	}

	// --- State ---
	var _isOpen:Bool = false;
	var _requestedWidth:Float = BlockLayout.BASE_WIDTH;
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
	var panelW:Float = 0;
	var panelH:Float = 0;
	var headerH:Float = 0;
	var footerH:Float = 0;
	var contentTop:Float = 0;
	var contentBottom:Float = 0;
	var contentHeight:Float = 0;
	var scrollY:Float = 0;
	var maxScroll:Float = 0;
	var _appliedScrollY:Float = -1;
	var _layoutWidth:Float = -1;
	var _layoutHeight:Float = -1;
	var headerHintW:Float = 0;
	var _twoColumn:Bool = false;
	var colA:BlockSaveColumn = null;
	var colB:BlockSaveColumn = null;

	// Camera and chrome. The two lists are drawn by hand around the scrolling content: `underChrome`
	// first (scrim, sheet background), `overChrome` last (header/footer bands, pinned buttons, bar).
	var cam:FlxCamera = null;
	var underChrome:Array<FlxSprite> = [];
	var overChrome:Array<FlxSprite> = [];
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
	var codeBg:FlxSprite = null;
	var logBg:FlxSprite = null;

	// Section captions.
	var capFile:FlxText = null;
	var capTarget:FlxText = null;
	var capMode:FlxText = null;
	var capOptions:FlxText = null;
	var capConfig:FlxText = null;
	var capCode:FlxText = null;
	var capLog:FlxText = null;

	// Scrolling content: hittable cells plus plain captions/labels/blocks.
	var cells:Array<BlockSaveCell> = [];
	var pinnedCells:Array<BlockSaveCell> = [];
	var plains:Array<
		{
			sprite:FlxSprite,
			baseY:Float,
			height:Float
		}> = [];

	// Text pools: reused labels so a relayout never leaks a sprite.
	var labelPool:SaveLinePool = new SaveLinePool();
	var targetPool:SaveLinePool = new SaveLinePool();
	var codePool:SaveLinePool = new SaveLinePool();
	var errorPool:SaveLinePool = new SaveLinePool();
	var logPool:SaveLinePool = new SaveLinePool();

	/** Dim hint lines under the rows; `hintLines()` draws from this one. */
	var hintPool:SaveLinePool = new SaveLinePool();

	var seps:Array<FlxSprite> = [];
	var _sepUsed:Int = 0;

	// Rows.
	var nameField:InputField = null;
	var pathField:InputField = null;
	var renameCell:BlockSaveCell = null;
	var applyPathCell:BlockSaveCell = null;
	var copyTargetCell:BlockSaveCell = null;
	var copyFolderCell:BlockSaveCell = null;
	var targetBgCell:BlockSaveCell = null;
	var errorBgCell:BlockSaveCell = null;
	var modeCells:Array<BlockSaveCell> = [];
	var autoReloadCell:BlockSaveCell = null;
	var forceKeyboardCell:BlockSaveCell = null;
	var reloadCell:BlockSaveCell = null;
	var saveCell:BlockSaveCell = null;
	var saveRenameCell:BlockSaveCell = null;
	var closeCell:BlockSaveCell = null;

	// Field placement, kept so the fields can follow the scroll offset.
	var nameFieldX:Float = 0;
	var nameFieldW:Float = 200;
	var nameFieldBaseY:Float = 0;
	var pathFieldX:Float = 0;
	var pathFieldW:Float = 200;
	var pathFieldBaseY:Float = 0;
	var nameFieldShown:Bool = false;
	var pathFieldShown:Bool = false;
	var _fieldControlH:Float = -1;

	// Log, preview and config state.
	var logLines:Array<String> = [];
	var _previewLines:Array<String> = [];
	var _previewTotal:Int = 0;
	var _configSummary:String = '';
	var _configErrors:Array<String> = [];
	var _statusMessage:String = '';
	var _statusOk:Bool = true;
	var _needsLayout:Bool = false;

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
		// Chrome is drawn by hand around the scrolling content, so the bands always cover a row that
		// scrolls behind them instead of the row being drawn over the bands.
		scrim = addChrome(underChrome, new FlxSprite(0, 0));
		scrim.makeGraphic(1, 1, FlxColor.WHITE);
		scrim.color = 0xFF000000;
		scrim.alpha = 0.45;

		panelBg = addChrome(underChrome, makeSolid(COLOR_PANEL));

		headerBg = addChrome(overChrome, makeSolid(COLOR_ROW));
		headerText = addChrome(overChrome, makeText('SAVE / EXPORT', BlockLayout.font('title'), COLOR_TEXT));
		headerHint = addChrome(overChrome, makeText('', BlockLayout.font('small'), COLOR_DIM));

		footerBg = addChrome(overChrome, makeSolid(COLOR_ROW));
		statusText = addChrome(overChrome, makeText('', BlockLayout.font('body'), COLOR_TEXT));
		configText = addChrome(overChrome, makeText('', BlockLayout.font('small'), COLOR_DIM));

		panelEdgeTop = addChrome(overChrome, makeSolid(COLOR_SEPARATOR));
		panelEdgeBottom = addChrome(overChrome, makeSolid(COLOR_SEPARATOR));

		codeBg = addVisual(makeSolid(COLOR_BG));
		logBg = addVisual(makeSolid(COLOR_BG));

		capFile = addVisual(makeCaption('FILE'));
		capTarget = addVisual(makeCaption('WHERE THE FILE GOES'));
		capMode = addVisual(makeCaption('WHERE IT RUNS'));
		capOptions = addVisual(makeCaption('OPTIONS'));
		capConfig = addVisual(makeCaption('EXTERNAL BLOCKS'));
		capCode = addVisual(makeCaption('CODE THAT WILL BE WRITTEN'));
		capLog = addVisual(makeCaption('MESSAGES'));

		// Dark blocks the wrapped lines are drawn on; tapping the target one copies the target path.
		targetBgCell = addCell(new BlockSaveCell(0, 0, 10, 10, '', COLOR_BG, COLOR_TEXT, BlockLayout.font('small')));
		errorBgCell = addCell(new BlockSaveCell(0, 0, 10, 10, '', COLOR_BG, COLOR_TEXT, BlockLayout.font('small')));

		renameCell = addCell(new BlockSaveCell(0, 0, 10, 10, 'Rename', COLOR_ROW, COLOR_TEXT, BlockLayout.font('body')));
		applyPathCell = addCell(new BlockSaveCell(0, 0, 10, 10, 'Use path', COLOR_ROW, COLOR_TEXT, BlockLayout.font('body')));
		copyTargetCell = addCell(new BlockSaveCell(0, 0, 10, 10, 'Copy target path', COLOR_ROW, COLOR_TEXT, BlockLayout.font('body')));
		copyFolderCell = addCell(new BlockSaveCell(0, 0, 10, 10, 'Copy folder path', COLOR_ROW, COLOR_TEXT, BlockLayout.font('body')));
		reloadCell = addCell(new BlockSaveCell(0, 0, 10, 10, 'Reload block config', COLOR_ROW, COLOR_TEXT, BlockLayout.font('body')));

		// The selected segment is painted in the accent colour, the choices around it stay flat.
		for (i in 0...MODE_LABELS.length)
		{
			var cell:BlockSaveCell = addCell(new BlockSaveCell(0, 0, 10, 10, MODE_LABELS[i], COLOR_ROW, COLOR_TEXT, BlockLayout.font('body')));
			cell.modeName = MODE_NAMES[i];
			cell.setColors(COLOR_ROW, COLOR_ACCENT);
			modeCells.push(cell);
		}

		autoReloadCell = addCell(new BlockSaveCell(0, 0, 10, 10, 'Reload the script after saving', COLOR_ROW, COLOR_TEXT, BlockLayout.font('body'), true));
		autoReloadCell.setColors(COLOR_ROW, COLOR_ROW_ON);
		forceKeyboardCell = addCell(new BlockSaveCell(0, 0, 10, 10, 'Use the in-game touch keyboard', COLOR_ROW, COLOR_TEXT, BlockLayout.font('body'), true));
		forceKeyboardCell.setColors(COLOR_ROW, COLOR_ROW_ON);

		saveCell = addPinned(new BlockSaveCell(0, 0, 10, 10, 'Save Lua', COLOR_OK, COLOR_DARK_TEXT, BlockLayout.font('body')));
		saveRenameCell = addPinned(new BlockSaveCell(0, 0, 10, 10, 'Save + Rename', COLOR_ACCENT, COLOR_TEXT, BlockLayout.font('body')));
		closeCell = addPinned(new BlockSaveCell(0, 0, 10, 10, 'Close', COLOR_WARN, COLOR_DARK_TEXT, BlockLayout.font('body')));

		scrollTrack = addChrome(overChrome, makeSolid(COLOR_ROW));
		scrollTrack.alpha = 0.5;
		scrollThumb = addChrome(overChrome, makeSolid(COLOR_DIM));

		nameField = makeField('blockcode');
		pathField = makeField('absolute path or folder');
		_fieldControlH = controlHeight();

		wireActions();
	}

	function addVisual<T:FlxSprite>(visual:T):T
	{
		visual.scrollFactor.set(0, 0);
		add(visual);
		return visual;
	}

	/** A sprite of the fixed chrome: never a group member, drawn by `draw()` around the content. */
	function addChrome<T:FlxSprite>(list:Array<FlxSprite>, visual:T):T
	{
		visual.scrollFactor.set(0, 0);
		visual.cameras = [cam];
		list.push(visual);
		return visual;
	}

	function addCell(cell:BlockSaveCell):BlockSaveCell
	{
		cells.push(cell);
		addVisual(cell);
		return cell;
	}

	function addPinned(cell:BlockSaveCell):BlockSaveCell
	{
		pinnedCells.push(cell);
		addChrome(overChrome, cell);
		return cell;
	}

	static function makeSolid(color:Int):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite(0, 0);
		sprite.makeGraphic(1, 1, FlxColor.WHITE);
		sprite.color = color;
		return sprite;
	}

	function makeText(text:String, size:Int, color:Int):FlxText
	{
		var label:FlxText = new FlxText(0, 0, 0, text, size);
		label.setFormat(Paths.font("vcr.ttf"), size, color, LEFT);
		label.scrollFactor.set(0, 0);
		return label;
	}

	function makeCaption(text:String):FlxText
	{
		return makeText(text, BlockLayout.font('small'), COLOR_TEXT);
	}

	function makeField(placeholder:String):InputField
	{
		var field:InputField = new InputField(0, 0, 200, controlHeight(), '', ParamType.STRING, placeholder);
		assignFieldCamera(field);
		return field;
	}

	function wireActions():Void
	{
		renameCell.action = doRename;
		applyPathCell.action = applyCustomPath;
		copyTargetCell.action = function():Void
		{
			copyText(currentTarget(), 'target path');
		};
		copyFolderCell.action = function():Void
		{
			copyText(currentDir(), 'folder path');
		};
		targetBgCell.action = function():Void
		{
			copyText(currentTarget(), 'target path');
		};
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

		autoReloadCell.action = function():Void
		{
			_autoReload = !_autoReload;
			refreshInfo();
			playSound('scrollMenu');
			setStatus('reload the script after every save: ' + onOff(_autoReload), true);
		};

		forceKeyboardCell.action = function():Void
		{
			_forceVirtualKeyboard = !_forceVirtualKeyboard;
			refreshInfo();
			playSound('scrollMenu');
			setStatus('always use the in-game touch keyboard: ' + onOff(_forceVirtualKeyboard), true);
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

	// =========================== metrics ===========================

	static function innerPad():Float
	{
		return PAD_FACTOR * BlockLayout.scale;
	}

	static function rowGap():Float
	{
		return BlockLayout.spacing('tight');
	}

	function rowHeight():Float
	{
		return Math.max(BlockLayout.touchSize(), ROW_FACTOR * BlockLayout.scale);
	}

	function controlHeight():Float
	{
		return Math.max(BlockLayout.touchSize(), rowHeight() - rowGap());
	}

	/** Line box of a font size: what one line of a wrapped block covers. */
	public static function lineHeight(fontSize:Int):Float
	{
		return Math.round(fontSize * 1.35);
	}

	function headerHeight():Float
	{
		var byButton:Float = BlockLayout.buttonHeight() + BlockLayout.spacing('tight');
		var byTitle:Float = BlockLayout.font('title') + BlockLayout.spacing('normal') * 1.6;

		return Math.max(byButton, byTitle) + innerPad() * 0.5;
	}

	/** Footer buttons in one row when there is room for three legible labels, else in two. */
	function footerButtonRows():Int
	{
		var needed:Float = Math.max(88, 96 * BlockLayout.scale) * 3 + BlockLayout.spacing('tight') * 2;

		return (panelW - innerPad() * 2 >= needed) ? 1 : 2;
	}

	function footerHeight():Float
	{
		var rows:Int = footerButtonRows();
		var statusBand:Float = MESSAGE_MAX_LINES * lineHeight(BlockLayout.font('body'));
		var configBand:Float = lineHeight(BlockLayout.font('small'));

		return innerPad() + statusBand + configBand + rowGap() + rows * controlHeight() + (rows - 1) * rowGap() + innerPad();
	}

	static function screenWidth():Int
	{
		return (FlxG.width > 0) ? Std.int(FlxG.width) : Std.int(BlockLayout.BASE_WIDTH);
	}

	static function screenHeight():Int
	{
		return (FlxG.height > 0) ? Std.int(FlxG.height) : Std.int(BlockLayout.BASE_HEIGHT);
	}

	// =========================== geometry ===========================

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
		BlockLayout.ensure();

		var screenW:Float = screenWidth();
		var screenH:Float = screenHeight();
		var inset:Float = BlockLayout.inset();
		var size = BlockLayout.panelSize();

		var wanted:Float = (_requestedWidth > 0) ? _requestedWidth : size.w;
		var cap:Float = Math.max(MIN_PANEL_WIDTH, MAX_PANEL_WIDTH * BlockLayout.scale);
		var roomW:Float = Math.max(MIN_PANEL_WIDTH, screenW - inset * 2);
		var roomH:Float = Math.max(MIN_PANEL_HEIGHT, screenH - inset * 2);

		panelW = Math.min(Math.min(Math.max(wanted, MIN_PANEL_WIDTH), roomW), Math.min(Math.max(MIN_PANEL_WIDTH, size.w), cap));
		panelH = Math.max(MIN_PANEL_HEIGHT, Math.min(size.h, roomH));
		panelX = Math.floor((screenW - panelW) * 0.5);
		panelY = Math.floor((screenH - panelH) * 0.5);

		headerH = headerHeight();
		footerH = footerHeight();

		contentTop = panelY + headerH + rowGap();
		contentBottom = panelY + panelH - footerH - rowGap();

		_layoutWidth = BlockLayout.width;
		_layoutHeight = BlockLayout.height;

		if (cam != null)
		{
			if (cam.width != screenWidth())
				cam.width = screenWidth();
			if (cam.height != screenHeight())
				cam.height = screenHeight();
		}

		scrim.setPosition(0, 0);
		resizeSprite(scrim, screenWidth(), screenHeight());

		panelBg.setPosition(panelX, panelY);
		resizeSprite(panelBg, Std.int(panelW), Std.int(panelH));

		panelEdgeTop.setPosition(panelX, panelY);
		resizeSprite(panelEdgeTop, Std.int(panelW), EDGE_HEIGHT);
		panelEdgeBottom.setPosition(panelX, panelY + panelH - EDGE_HEIGHT);
		resizeSprite(panelEdgeBottom, Std.int(panelW), EDGE_HEIGHT);

		layoutHeader();
		layoutFooter();
		layoutScrollBar();
	}

	function layoutHeader():Void
	{
		var pad:Float = innerPad();
		var titleSize:Int = BlockLayout.font('title');
		var hintSize:Int = BlockLayout.font('small');

		headerBg.setPosition(panelX, panelY);
		resizeSprite(headerBg, Std.int(panelW), Std.int(panelH > 0 ? headerH : 1));

		headerText.setPosition(panelX + pad, panelY + (headerH - lineHeight(titleSize)) * 0.5);
		headerText.setFormat(Paths.font("vcr.ttf"), titleSize, COLOR_TEXT, LEFT);

		var titleRoom:Float = Math.max(40, panelW * 0.46 - pad);
		headerText.text = clipMiddle('SAVE / EXPORT', titleRoom, titleSize);

		headerHintW = Math.max(0, panelW - panelW * 0.46 - pad * 2);
		headerHint.setFormat(Paths.font("vcr.ttf"), hintSize, COLOR_DIM, RIGHT);
		headerHint.setPosition(panelX + panelW * 0.46, panelY + (headerH - lineHeight(hintSize)) * 0.5);
		headerHint.visible = (headerHintW > 90);
	}

	/** Pins the three action buttons plus the status and config lines to the bottom of the sheet. */
	function layoutFooter():Void
	{
		var pad:Float = innerPad();
		var gap:Float = rowGap();
		var rows:Int = footerButtonRows();
		var buttonH:Float = controlHeight();
		var footerTop:Float = panelY + panelH - footerH;
		var avail:Float = panelW - pad * 2;

		footerBg.setPosition(panelX, footerTop);
		resizeSprite(footerBg, Std.int(panelW), Std.int(footerH));

		var statusSize:Int = BlockLayout.font('body');
		var configSize:Int = BlockLayout.font('small');
		statusText.setPosition(panelX + pad, footerTop + pad);
		configText.setPosition(panelX + pad, footerTop + pad + MESSAGE_MAX_LINES * lineHeight(statusSize) + gap * 0.5);

		var buttonTop:Float = footerTop + footerH - pad - rows * buttonH - (rows - 1) * gap;

		if (rows == 1)
		{
			var buttonW:Float = (avail - gap * 2) / 3;
			saveCell.setRect(panelX + pad, buttonTop, buttonW, buttonH);
			saveRenameCell.setRect(panelX + pad + buttonW + gap, buttonTop, buttonW, buttonH);
			closeCell.setRect(panelX + pad + (buttonW + gap) * 2, buttonTop, buttonW, buttonH);
		}
		else
		{
			var half:Float = (avail - gap) * 0.5;
			saveCell.setRect(panelX + pad, buttonTop, half, buttonH);
			saveRenameCell.setRect(panelX + pad + half + gap, buttonTop, half, buttonH);
			closeCell.setRect(panelX + pad, buttonTop + buttonH + gap, avail, buttonH);
		}
	}

	function layoutScrollBar():Void
	{
		var barW:Float = Math.max(3, SCROLLBAR_FACTOR * BlockLayout.scale);
		var barX:Float = panelX + panelW - innerPad() * 0.5 - barW * 0.5;

		scrollTrack.setPosition(barX, contentTop);
		resizeSprite(scrollTrack, Std.int(barW), Std.int(Math.max(1, contentBottom - contentTop)));
		scrollThumb.setPosition(barX, contentTop);
		resizeSprite(scrollThumb, Std.int(barW), Std.int(SCROLLBAR_MIN_HEIGHT));
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
	 * Items longer than the band they scroll through may overlap the header/footer bands - those two
	 * are drawn over the content (see `draw()`), which looks like clipping. Short items are only
	 * shown while they fit completely, so no label is ever cut in half.
	 */
	function shouldShow(y:Float, height:Float, top:Float, bottom:Float):Bool
	{
		if (height > maxPartialHeight())
			return (y + height > top) && (y < bottom);

		return (y >= top - 0.5) && (y + height <= bottom + 0.5);
	}

	/** Objects drawn by hand (the fields) must fit completely: nothing may cover them. */
	static function fitsInside(y:Float, height:Float, top:Float, bottom:Float):Bool
	{
		return (y >= top - 0.5) && (y + height <= bottom + 0.5);
	}

	/** Only blocks taller than a row are allowed to slide under the header and footer bands. */
	function maxPartialHeight():Float
	{
		return rowHeight();
	}

	// =========================== layout ===========================

	function layoutRows():Void
	{
		if (_settings == null)
			return;

		plains = [];
		for (pool in allPools())
			pool.used = 0;
		_sepUsed = 0;

		// Anything the sections do not place again this pass stays hidden.
		for (cell in cells)
			cell.shown = false;

		var avail:Float = Math.max(160, panelW - innerPad() * 2);
		var gutter:Float = BlockLayout.spacing('loose');
		_twoColumn = !BlockLayout.narrow && !BlockLayout.portrait && (avail >= TWO_COLUMN_MIN * BlockLayout.scale);

		var colW:Float = _twoColumn ? (avail - gutter) * 0.5 : avail;

		colA = new BlockSaveColumn(panelX + innerPad(), colW);
		colB = _twoColumn ? new BlockSaveColumn(panelX + innerPad() + colW + gutter, colW) : colA;

		if (_twoColumn)
		{
			layoutFileSection(colA, true);
			layoutTargetSection(colA, false);
			layoutCodeSection(colA, false);

			layoutModeSection(colB, true);
			layoutOptionsSection(colB, false);
			layoutConfigSection(colB, false);
			layoutLogSection(colB, false);
		}
		else
		{
			layoutFileSection(colA, true);
			layoutModeSection(colA, false);
			layoutTargetSection(colA, false);
			layoutOptionsSection(colA, false);
			layoutConfigSection(colA, false);
			layoutCodeSection(colA, false);
			layoutLogSection(colA, false);
		}

		hideUnusedSprites();

		contentHeight = Math.max(1, Math.max(colA.cursor, colB.cursor) - rowGap());
		maxScroll = Math.max(0, contentHeight - Math.max(1, contentBottom - contentTop));
		if (scrollY > maxScroll)
			scrollY = maxScroll;

		refreshHeader();
		refreshFooter();

		_appliedScrollY = -1;
	}

	function allPools():Array<SaveLinePool>
	{
		return [labelPool, targetPool, codePool, errorPool, logPool, hintPool];
	}

	function hideUnusedSprites():Void
	{
		for (pool in allPools())
		{
			for (i in pool.used...pool.lines.length)
				pool.lines[i].visible = false;
		}

		for (i in _sepUsed...seps.length)
			seps[i].visible = false;
	}

	/** Section title with generous space above it and a separator line when it is not the first. */
	function sectionHeader(col:BlockSaveColumn, caption:FlxText, title:String, first:Bool):Void
	{
		var size:Int = BlockLayout.font('small');
		var height:Float = lineHeight(size);

		if (!first)
		{
			col.cursor += BlockLayout.spacing('loose');
			var sep:FlxSprite = takeSeparator();
			if (sep != null)
			{
				var sepH:Int = Std.int(Math.max(1, Math.round(SEPARATOR_FACTOR * BlockLayout.scale)));
				resizeSprite(sep, Std.int(Math.max(col.w, 1)), sepH);
				putPlain(sep, col.x, contentTop + col.cursor, sep.height);
				col.cursor += sep.height + BlockLayout.spacing('loose') * 0.6;
			}
		}

		var y:Float = nextRow(col, height + rowGap());
		caption.setFormat(Paths.font("vcr.ttf"), size, COLOR_CAPTION, LEFT);
		caption.text = clipMiddle(title, col.w, size);
		putPlain(caption, col.x, y, height + rowGap());
	}

	function takeSeparator():FlxSprite
	{
		if (_sepUsed < seps.length)
			return seps[_sepUsed++];

		var sep:FlxSprite = makeSolid(COLOR_SEPARATOR);
		addVisual(sep);
		seps.push(sep);
		_sepUsed++;
		return sep;
	}

	/** Advances the column cursor past one row and returns the absolute y of its top edge. */
	function nextRow(col:BlockSaveColumn, height:Float):Float
	{
		var y:Float = contentTop + col.cursor;
		col.cursor += height + rowGap();

		return y;
	}

	function placeCell(cell:BlockSaveCell, x:Float, y:Float, w:Float, h:Float):Void
	{
		cell.shown = true;
		cell.baseY = y;
		cell.setRect(x, y, w, h);
	}

	function putPlain(sprite:FlxSprite, x:Float, y:Float, height:Float):Void
	{
		if (sprite == null)
			return;

		plains.push({
			sprite: sprite,
			baseY: y,
			height: height
		});

		sprite.x = x;
		sprite.y = y;
		sprite.visible = true;
	}

	/** One reusable left-aligned line; the caller has already wrapped or clipped its text. */
	function lineFrom(pool:SaveLinePool, size:Int, color:Int):FlxText
	{
		while (pool.lines.length <= pool.used)
		{
			var label:FlxText = new FlxText(0, 0, 0, '', size);
			label.scrollFactor.set(0, 0);
			add(label);
			pool.lines.push(label);
		}

		var label:FlxText = pool.lines[pool.used++];
		label.setFormat(Paths.font("vcr.ttf"), size, color, LEFT);
		return label;
	}

	/** Stacks wrapped lines of one colour from `top` and returns nothing; height is the caller's. */
	function putLines(pool:SaveLinePool, lines:Array<SaveLine>, x:Float, top:Float, width:Float, size:Int):Void
	{
		var lh:Float = lineHeight(size);

		for (i in 0...lines.length)
		{
			var label:FlxText = lineFrom(pool, size, lines[i].color);
			label.text = lines[i].text;
			putPlain(label, x, top + i * lh, lh);
		}
	}

	/** A left-hand label of a two-part row, clipped so it can never run into its control. */
	function rowLabel(col:BlockSaveColumn, text:String, x:Float, y:Float, w:Float, h:Float, color:Int):FlxText
	{
		var size:Int = BlockLayout.font('body');
		var label:FlxText = lineFrom(labelPool, size, color);
		label.text = clipMiddle(text, Math.max(40, w - rowGap()), size);
		putPlain(label, col.x + x, y + (h - lineHeight(size)) * 0.5, lineHeight(size));

		return label;
	}

	/** One or more dim hint lines under a row, using the pool the section already draws from. */
	function hintLines(pool:SaveLinePool, col:BlockSaveColumn, text:String, color:Int):Void
	{
		var size:Int = BlockLayout.font('small');
		var lines:Array<String> = wrapLines(text, col.w, size, MESSAGE_MAX_LINES);
		if (lines.length < 1)
			return;

		var lh:Float = lineHeight(size);
		var top:Float = nextRow(col, lines.length * lh);

		for (i in 0...lines.length)
		{
			var label:FlxText = lineFrom(pool, size, color);
			label.text = lines[i];
			putPlain(label, col.x, top + i * lh, lh);
		}
	}

	// --- sections ---

	function layoutFileSection(col:BlockSaveColumn, first:Bool):Void
	{
		sectionHeader(col, capFile, 'FILE', first);

		var row:Float = rowHeight();
		var ctrl:Float = controlHeight();
		var gap:Float = rowGap();
		var size:Int = BlockLayout.font('body');
		var renameW:Float = Math.max(BlockLayout.buttonWidth('Rename'), 92 * BlockLayout.scale);
		var labelW:Float = labelRoom(col.w, renameW);
		var y:Float = nextRow(col, row);

		nameFieldX = col.x + labelW + gap;
		nameFieldW = Math.max(72, col.w - labelW - gap - renameW - gap);
		nameFieldBaseY = y + (row - ctrl) * 0.5;
		assignNameFieldWidth();

		renameCell.setFontSize(size);
		placeCell(renameCell, col.x + col.w - renameW, nameFieldBaseY, renameW, ctrl);
		rowLabel(col, 'Script file name', 0, y, labelW, row, COLOR_TEXT);

		hintLines(hintPool, col, 'Written as ' + BlockFileIO.sanitizeName(currentName()) + '.lua. Rename also moves a file that is already there.', COLOR_DIM);

		var half:Float = (col.w - gap) * 0.5;
		y = nextRow(col, ctrl);
		copyTargetCell.setFontSize(size);
		copyFolderCell.setFontSize(size);
		placeCell(copyTargetCell, col.x, y, half, ctrl);
		placeCell(copyFolderCell, col.x + half + gap, y, half, ctrl);
	}

	function layoutTargetSection(col:BlockSaveColumn, first:Bool):Void
	{
		sectionHeader(col, capTarget, 'WHERE THE FILE GOES', first);

		var size:Int = BlockLayout.font('small');
		var pad:Float = BlockLayout.spacing('normal');
		var textW:Float = Math.max(64, col.w - pad * 2);
		var lh:Float = lineHeight(size);
		var lines:Array<SaveLine> = wrapColored(targetItems(), textW, size, TARGET_LINES);
		var blockH:Float = pad * 2 + Math.max(1, lines.length) * lh;
		var top:Float = nextRow(col, blockH);

		placeCell(targetBgCell, col.x, top, col.w, blockH);
		putLines(targetPool, lines, col.x + pad, top + pad, textW, size);

		hintLines(hintPool, col, 'Tap the block to copy the target path. Every mode is listed with the default file name.', COLOR_DIM);
	}

	function layoutModeSection(col:BlockSaveColumn, first:Bool):Void
	{
		sectionHeader(col, capMode, 'WHERE IT RUNS', first);

		var ctrl:Float = controlHeight();
		var gap:Float = rowGap();
		var size:Int = BlockLayout.font('body');
		var segW:Float = Math.max(48, (col.w - gap * 2) / 3);
		var short:Bool = (segW < 132 * BlockLayout.scale);
		var y:Float = nextRow(col, ctrl);

		for (i in 0...modeCells.length)
		{
			var cell:BlockSaveCell = modeCells[i];
			var text:String = short ? SHORT_MODE_LABELS[i] : MODE_LABELS[i];
			cell.setFontSize(size);
			cell.setText(clipMiddle(text, segW - 12, size));
			placeCell(cell, col.x + i * (segW + gap), y, segW, ctrl);
		}

		hintLines(hintPool, col, modeHelpOf(_mode), COLOR_DIM);

		if (_mode != 'custom')
		{
			applyPathCell.shown = false;
			pathFieldShown = false;
			return;
		}

		var row:Float = rowHeight();
		var applyW:Float = Math.max(BlockLayout.buttonWidth('Use path'), 92 * BlockLayout.scale);
		var labelW:Float = labelRoom(col.w, applyW);
		y = nextRow(col, row);

		pathFieldX = col.x + labelW + gap;
		pathFieldW = Math.max(72, col.w - labelW - gap - applyW - gap);
		pathFieldBaseY = y + (row - ctrl) * 0.5;
		assignPathFieldWidth();

		applyPathCell.setFontSize(size);
		placeCell(applyPathCell, col.x + col.w - applyW, pathFieldBaseY, applyW, ctrl);
		rowLabel(col, 'Custom folder', 0, y, labelW, row, COLOR_TEXT);

		hintLines(hintPool, col, 'Example: D:/my-scripts or mods/my-mod/scripts', COLOR_DIM);
	}

	function layoutOptionsSection(col:BlockSaveColumn, first:Bool):Void
	{
		sectionHeader(col, capOptions, 'OPTIONS', first);

		var ctrl:Float = controlHeight();
		var size:Int = BlockLayout.font('body');
		var y:Float = nextRow(col, ctrl);

		autoReloadCell.setFontSize(size);
		autoReloadCell.setAlignLeft(true);
		placeCell(autoReloadCell, col.x, y, col.w, ctrl);
		autoReloadCell.setText(clipMiddle('Reload the script after saving', toggleLabelWidth(col.w), size));

		hintLines(hintPool, col, 'The running song picks the new script up right after a save.', COLOR_DIM);

		y = nextRow(col, ctrl);
		forceKeyboardCell.setFontSize(size);
		forceKeyboardCell.setAlignLeft(true);
		placeCell(forceKeyboardCell, col.x, y, col.w, ctrl);
		forceKeyboardCell.setText(clipMiddle('Use the in-game touch keyboard', toggleLabelWidth(col.w), size));

		hintLines(hintPool, col, 'Even when the device brings its own keyboard.', COLOR_DIM);
	}

	function layoutConfigSection(col:BlockSaveColumn, first:Bool):Void
	{
		sectionHeader(col, capConfig, 'EXTERNAL BLOCKS', first);

		var ctrl:Float = controlHeight();
		var y:Float = nextRow(col, ctrl);

		reloadCell.setFontSize(BlockLayout.font('body'));
		placeCell(reloadCell, col.x, y, col.w, ctrl);

		hintLines(hintPool, col,
			'Blocks come from blockcode/blocks.json or blockcode/blocks.lua inside a mod folder. Reload rescans them without restarting.', COLOR_DIM);

		if (_configErrors.length > 0)
		{
			var size:Int = BlockLayout.font('small');
			var pad:Float = BlockLayout.spacing('normal');
			var textW:Float = Math.max(64, col.w - pad * 2);
			var lh:Float = lineHeight(size);
			var lines:Array<SaveLine> = wrapColored(blockConfigErrorLines(), textW, size, ERROR_LINES + 1);
			var blockH:Float = pad * 2 + Math.max(1, lines.length) * lh;
			var top:Float = nextRow(col, blockH);

			placeCell(errorBgCell, col.x, top, col.w, blockH);
			putLines(errorPool, lines, col.x + pad, top + pad, textW, size);
		}
	}

	function layoutCodeSection(col:BlockSaveColumn, first:Bool):Void
	{
		sectionHeader(col, capCode, 'CODE THAT WILL BE WRITTEN', first);

		var size:Int = BlockLayout.font('small');
		var pad:Float = BlockLayout.spacing('normal');
		var textW:Float = Math.max(64, col.w - pad * 2);
		var lines:Array<SaveLine> = codePreviewLines(textW, size);
		var lh:Float = lineHeight(size);
		var blockH:Float = pad * 2 + lines.length * lh;
		var top:Float = nextRow(col, blockH);

		blitPlain(codeBg, col.x, top, col.w, blockH);
		putLines(codePool, lines, col.x + pad, top + pad, textW, size);

		hintLines(hintPool, col, codePreviewHint(), COLOR_DIM);
	}

	function layoutLogSection(col:BlockSaveColumn, first:Bool):Void
	{
		sectionHeader(col, capLog, 'MESSAGES', first);

		var size:Int = BlockLayout.font('small');
		var pad:Float = BlockLayout.spacing('normal');
		var textW:Float = Math.max(64, col.w - pad * 2);
		var lh:Float = lineHeight(size);
		var items:Array<SaveLine> = [];
		var start:Int = Std.int(Math.max(0, logLines.length - LOG_LINES));
		var newest:Int = logLines.length - 1;

		for (i in start...logLines.length)
		{
			items.push({
				text: ((i == newest) ? '> ' : '  ') + logLines[i],
				color: (i == newest) ? COLOR_TEXT : COLOR_DIM
			});
		}

		if (items.length < 1)
			items.push({text: 'nothing logged yet', color: COLOR_DIM});

		var lines:Array<SaveLine> = wrapColored(items, textW, size, LOG_LINES * 2);
		var blockH:Float = pad * 2 + lines.length * lh;
		var top:Float = nextRow(col, blockH);

		blitPlain(logBg, col.x, top, col.w, blockH);
		putLines(logPool, lines, col.x + pad, top + pad, textW, size);
	}

	/** A fixed background block of the scrolling content (not a button). */
	function blitPlain(sprite:FlxSprite, x:Float, y:Float, w:Float, h:Float):Void
	{
		if (sprite == null)
			return;

		resizeSprite(sprite, Std.int(Math.max(w, 1)), Std.int(Math.max(h, 1)));
		putPlain(sprite, x, y, h);
	}

	// --- section content ---

	function targetItems():Array<SaveLine>
	{
		var items:Array<SaveLine> = [];
		if (_settings == null)
			return items;

		items.push({text: 'Current setting:  ' + BlockFileIO.describe(_settings, _songName), color: COLOR_TEXT});
		items.push({text: 'Every mode, with the default file name:', color: COLOR_DIM});

		var targets:Array<String> = BlockFileIO.execTargetsFor(_songName);
		for (i in 0...MODE_NAMES.length)
		{
			var path:String = (i < targets.length) ? targets[i] : '';
			var state:String = ((path.length > 0) && BlockFileIO.exists(path)) ? '  [exists]' : '  [new file]';
			var active:Bool = (MODE_NAMES[i] == _mode);

			items.push({
				text: (active ? '> ' : '  ') + MODE_LABELS[i] + ':  ' + path + state,
				color: active ? COLOR_OK : COLOR_DIM
			});
		}

		return items;
	}

	function codePreviewLines(textW:Float, size:Int):Array<SaveLine>
	{
		var lines:Array<SaveLine> = [];

		if (codeProvider == null)
		{
			lines.push({text: 'No code yet - the editor has not handed its blocks over.', color: COLOR_DIM});
			return lines;
		}

		if (_previewTotal < 1 || (_previewLines.length == 1 && _previewLines[0].length < 1))
		{
			lines.push({text: '(the script is empty)', color: COLOR_DIM});
			return lines;
		}

		var count:Int = Std.int(Math.min(_previewLines.length, PREVIEW_LINES));
		for (i in 0...count)
			lines.push({text: clipEnd(_previewLines[i], textW, size), color: COLOR_TEXT});

		if (count < _previewLines.length)
			lines.push({text: '...', color: COLOR_DIM});

		return lines;
	}

	function codePreviewHint():String
	{
		if (codeProvider == null)
			return 'Waiting for the editor to hand over its code.';

		if (_previewTotal > PREVIEW_LINES)
			return 'First ' + PREVIEW_LINES + ' of ' + _previewTotal + ' lines.';

		return _previewTotal + ((_previewTotal == 1) ? ' line.' : ' lines.');
	}

	function blockConfigErrorLines():Array<SaveLine>
	{
		var lines:Array<SaveLine> = [];
		var shown:Int = Std.int(Math.min(_configErrors.length, ERROR_LINES + 1));

		for (i in 0...shown)
			lines.push({text: '! ' + _configErrors[i], color: COLOR_WARN});

		if (_configErrors.length > shown)
			lines.push({text: '! ... and ' + (_configErrors.length - shown) + ' more (see the messages below)', color: COLOR_WARN});

		return lines;
	}

	// --- header / footer text ---

	function refreshHeader():Void
	{
		if (headerHint == null)
			return;

		if (!headerHint.visible)
		{
			headerHint.text = '';
			return;
		}

		var size:Int = BlockLayout.font('small');
		headerHint.text = clipMiddle(currentTarget(), headerHintW, size);
	}

	function refreshFooter():Void
	{
		var bodySize:Int = BlockLayout.font('body');
		var smallSize:Int = BlockLayout.font('small');
		var room:Float = Math.max(80, panelW - innerPad() * 2);

		statusText.color = _statusOk ? COLOR_OK : COLOR_WARN;
		statusText.setFormat(Paths.font("vcr.ttf"), bodySize, statusText.color, LEFT);
		statusText.text = wrapLines(_statusMessage, room, bodySize, MESSAGE_MAX_LINES).join('\n');

		configText.setFormat(Paths.font("vcr.ttf"), smallSize, COLOR_DIM, LEFT);
		configText.text = clipMiddle(_configSummary, room, smallSize);
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
				setScroll(scrollY - FlxG.mouse.wheel * WHEEL_STEP * BlockLayout.scale);

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
				setScroll(scrollY - rowHeight() * 2);
			else if (FlxG.keys.justPressed.PAGEDOWN)
				setScroll(scrollY + rowHeight() * 2);
		}
		#end
	}

	// =========================== viewport ===========================

	/** Rebuilds the sheet when the window (or the device orientation) changed size. */
	function syncViewport():Void
	{
		BlockLayout.ensure();

		var sameViewport:Bool = (BlockLayout.width == _layoutWidth) && (BlockLayout.height == _layoutHeight);
		var sameCamera:Bool = (cam != null) && (cam.width == screenWidth()) && (cam.height == screenHeight());
		if (sameViewport && sameCamera)
			return;

		_layoutWidth = BlockLayout.width;
		_layoutHeight = BlockLayout.height;

		computeGeometry();
		layoutRows();
		applyScroll();
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
			if (!_pressedCell.containsPoint(ptrX, ptrY) || Math.abs(ptrY - _pressY) > DRAG_CANCEL * BlockLayout.touchScale())
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
		// The pinned footer never scrolls, so it is hit tested first.
		for (cell in pinnedCells)
		{
			if (cell.visible && cell.shown && cell.containsPoint(x, y))
				return cell;
		}

		for (cell in cells)
		{
			if (!cell.visible || !cell.shown)
				continue;

			// A block that slides under a band is only drawn there, so it is not clickable there.
			var y:Float = cell.baseY - scrollY;
			if (!fitsInside(y, cell.hitH, contentTop, contentBottom))
				continue;

			if (cell.containsPoint(x, y))
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

	function assignNameFieldWidth():Void
	{
		if (nameField != null)
			nameField.width = nameFieldW;
	}

	function assignPathFieldWidth():Void
	{
		if (pathField != null)
			pathField.width = pathFieldW;
	}

	/** Places the inline fields in the scrolled content and hides them when they leave the view. */
	function syncFields():Void
	{
		if (nameField == null || pathField == null)
			return;

		var ctrl:Float = controlHeight();

		var nameY:Float = nameFieldBaseY - scrollY;
		nameFieldShown = fitsInside(nameY, ctrl, contentTop, contentBottom);
		if (nameFieldShown)
			nameField.updatePosition(nameFieldX, nameY);
		setFieldVisible(nameField, nameFieldShown);
		if (!nameFieldShown && nameField.isFocused)
			nameField.unfocus();

		var pathY:Float = pathFieldBaseY - scrollY;
		pathFieldShown = (_mode == 'custom') && fitsInside(pathY, ctrl, contentTop, contentBottom);
		if (pathFieldShown)
			pathField.updatePosition(pathFieldX, pathY);
		setFieldVisible(pathField, pathFieldShown);
		if (!pathFieldShown && pathField.isFocused)
			pathField.unfocus();
	}

	function updateFields(elapsed:Float):Void
	{
		resizeFieldsIfNeeded();

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
	 * `InputField` fixes its own height while it is built, so a viewport change that moves the row
	 * height means the fields are rebuilt with the new metrics - only while neither of them is
	 * being edited, so no caret and no soft keyboard session is lost.
	 */
	function resizeFieldsIfNeeded():Void
	{
		var ctrl:Float = controlHeight();
		if (_fieldControlH < 0)
		{
			_fieldControlH = ctrl;
			return;
		}

		if (Math.abs(_fieldControlH - ctrl) < 2)
			return;

		if (nameField == null || pathField == null)
			return;
		if (nameField.isFocused || pathField.isFocused || _ownsSoftKeyboard)
			return;

		var nameValue:String = Std.string(nameField.value);
		var pathValue:String = Std.string(pathField.value);

		destroyField(nameField);
		destroyField(pathField);

		nameField = new InputField(0, 0, Math.max(80, nameFieldW), ctrl, nameValue, ParamType.STRING, 'blockcode');
		pathField = new InputField(0, 0, Math.max(80, pathFieldW), ctrl, pathValue, ParamType.STRING, 'absolute path or folder');
		assignFieldCamera(nameField);
		assignFieldCamera(pathField);

		_fieldControlH = ctrl;
		_needsLayout = true;
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

		BlockSoftKeyboard.targetRect = new Rectangle(x, baseY - scrollY, Math.max(w, 80), controlHeight());
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
			setStatus('custom folder: ' + ((_customPath.length > 0) ? _customPath : '(empty - the default folder is used)'), true);
		}

		_needsLayout = true;
		refreshInfo();
	}

	// =========================== state <-> settings ===========================

	function readSettings():Void
	{
		_mode = (_settings.execMode != null) ? _settings.execMode : 'song';
		if (modeIndex(_mode) < 0)
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

	/** The settings as the panel has them right now, without touching the ones handed to `open()`. */
	function snapshot():BlockCodeEditorSettings
	{
		var copy:BlockCodeEditorSettings = BlockTypes.defaultSettings();

		copy.scriptName = BlockFileIO.sanitizeName(currentName());
		copy.execMode = _mode;
		copy.customExecPath = _customPath;
		copy.autoReload = _autoReload;
		copy.forceVirtualKeyboard = _forceVirtualKeyboard;

		if (_settings != null)
		{
			copy.savePath = _settings.savePath;
			copy.zoom = _settings.zoom;
		}

		return copy;
	}

	function currentTarget():String
	{
		if (_settings == null)
			return '';

		return BlockFileIO.describe(snapshot(), _songName);
	}

	function currentDir():String
	{
		if (_settings == null)
			return '';

		return BlockFileIO.resolveDir(snapshot(), _songName);
	}

	static function modeIndex(mode:String):Int
	{
		if (mode == null)
			return 0;

		for (i in 0...MODE_NAMES.length)
		{
			if (MODE_NAMES[i] == mode)
				return i;
		}

		return -1;
	}

	static function modeLabelOf(mode:String):String
	{
		var index:Int = modeIndex(mode);

		return (index >= 0) ? MODE_LABELS[index] : MODE_LABELS[0];
	}

	static function modeHelpOf(mode:String):String
	{
		var index:Int = modeIndex(mode);

		return (index >= 0) ? MODE_HELP[index] : MODE_HELP[0];
	}

	/** Room a toggle row leaves for its text once the switch on its right has its space. */
	static function toggleLabelWidth(rowWidth:Float):Float
	{
		return Math.max(60, rowWidth - Math.max(56, 82 * BlockLayout.scale));
	}

	/**
	 * Width of the left-hand label of a row that also carries a field and a button, so the three of
	 * them always add up to `rowWidth` - a narrow sheet shortens the label before it lets a control
	 * run into its neighbour.
	 */
	static function labelRoom(rowWidth:Float, buttonW:Float):Float
	{
		var gap:Float = rowGap();
		var wanted:Float = Math.min(Math.max(110 * BlockLayout.scale, rowWidth * 0.32), rowWidth * 0.45);
		var spare:Float = rowWidth - (gap + buttonW + gap + Math.max(72, rowWidth * 0.3));

		return Math.max(48, Math.min(wanted, spare));
	}

	function setMode(mode:String):Void
	{
		if (mode == null || mode == _mode)
			return;

		_mode = mode;
		applyTo(_settings);
		refreshPreviewCode();
		playSound('scrollMenu');

		if (_mode != 'custom')
			pathField.unfocus();

		_needsLayout = true;
		setStatus('scripts are written as: ' + modeLabelOf(_mode), true);
	}

	function applyCustomPath():Void
	{
		if (pathFieldShown)
			commitField(pathField);
		else
			setStatus('switch to Custom folder to type a path of your own', false);
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
			_needsLayout = true;
			return;
		}

		var code:String = codeProvider();
		if (code == null)
			code = '';

		var path:String = BlockFileIO.save(_settings, code, _songName);
		refreshPreviewCode();
		_needsLayout = true;

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
		var nameWasEdited:Bool = (wanted != _settings.scriptName);

		applyTo(_settings);

		var path:String = BlockFileIO.rename(_settings, wanted, _songName);
		nameField.value = _settings.scriptName;
		refreshPreviewCode();
		_needsLayout = true;

		if (path.length < 1)
		{
			setStatus('rename failed - no target path could be resolved', false);
			addLog('rename failed for "' + wanted + '"');
			playSound('cancelMenu');
			return;
		}

		if (!nameWasEdited && previous == path)
		{
			setStatus('the file is already called ' + _settings.scriptName + '.lua', true);
			addLog('rename skipped: ' + path + ' is unchanged');
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
		refreshConfig();

		var blockCount:Int = BlockLibrary.allBlocks().length;
		var categoryCount:Int = BlockLibrary.categories.length;

		if (_configErrors.length == 0)
		{
			setStatus('block config reloaded: ' + blockCount + ' blocks in ' + categoryCount + ' groups, no errors', true);
			addLog('config reloaded: ' + blockCount + ' blocks / ' + categoryCount + ' groups');
			playSound('confirmMenu');
			return;
		}

		setStatus('block config reloaded with ' + _configErrors.length + ' problem(s) - see the list', false);
		for (message in _configErrors)
			addLog('config: ' + message);
		playSound('cancelMenu');
	}

	/** Puts `text` on the clipboard and reports the outcome in the status line. */
	function copyText(text:String, label:String):Void
	{
		var value:String = (text == null) ? '' : text.trim();
		if (value.length < 1)
		{
			setStatus('no ' + label + ' to copy in this mode', false);
			playSound('cancelMenu');
			return;
		}

		try
		{
			openfl.system.System.setClipboard(value);
			setStatus(label + ' copied: ' + value, true);
			addLog('copied ' + label + ': ' + value);
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

		var size:Int = BlockLayout.font('body');

		for (cell in modeCells)
		{
			cell.setFontSize(size);
			cell.setActive(cell.modeName == _mode);
		}

		autoReloadCell.setFontSize(size);
		autoReloadCell.setActive(_autoReload);
		autoReloadCell.setSwitch(_autoReload, true);

		forceKeyboardCell.setFontSize(size);
		forceKeyboardCell.setActive(_forceVirtualKeyboard);
		forceKeyboardCell.setSwitch(_forceVirtualKeyboard, true);

		_needsLayout = true;
	}

	/** Reads the block catalogue signature plus its error list once, not on every layout pass. */
	function refreshConfig():Void
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
				sample = shortName(line.split('|')[0]);
		}

		_configSummary = files + ((files == 1) ? ' config file' : ' config files');
		if (sample.length > 0)
			_configSummary += ' (' + sample + ')';
		_configSummary += '  -  ' + BlockLibrary.allBlocks().length + ' blocks in ' + BlockLibrary.categories.length + ' groups';
		if (runtime > 0)
			_configSummary += '  -  ' + runtime + ' registered by scripts';

		_configErrors = BlockConfigLoader.lastErrors();
		if (_configErrors == null)
			_configErrors = [];

		_needsLayout = true;
	}

	/** Caches the head of the generated script, so the preview never regenerates Lua per frame. */
	function refreshPreviewCode():Void
	{
		_previewLines = [];
		_previewTotal = 0;

		if (codeProvider == null)
			return;

		var code:String = codeProvider();
		if (code == null)
			code = '';

		var all:Array<String> = code.split('\n');
		_previewTotal = all.length;

		var count:Int = Std.int(Math.min(all.length, PREVIEW_LINES + 1));
		for (i in 0...count)
			_previewLines.push(all[i]);

		_needsLayout = true;
	}

	static function shortName(path:String):String
	{
		var file:String = (path == null) ? '' : path;
		var slash:Int = file.lastIndexOf('/');
		if (slash < 0)
			slash = file.lastIndexOf('\\');

		return (slash >= 0) ? file.substr(slash + 1) : file;
	}

	function setStatus(message:String, ok:Bool):Void
	{
		_statusMessage = (message == null) ? '' : message;
		_statusOk = ok;
		refreshFooter();
	}

	function addLog(message:String):Void
	{
		if (message == null)
			return;

		logLines.push(message);
		while (logLines.length > MAX_LOG_ENTRIES)
			logLines.shift();

		_needsLayout = true;
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

	// =========================== text measurement ===========================
	static var _charWidths:Map<Int, Float> = new Map();

	/**
	 * Average advance width of one character of the UI font at `fontSize`, measured once per size
	 * through the same `TextField`/`TextFormat` pair `FlxText` renders with. Falls back to a rough
	 * estimate when the font cannot be measured (headless targets, font not registered yet).
	 */
	static function avgCharWidth(fontSize:Int):Float
	{
		var cached:Null<Float> = _charWidths.get(fontSize);
		if (cached != null)
			return cached;

		var width:Float = fontSize * CHAR_WIDTH_FALLBACK;
		var sample:String = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._- ';

		try
		{
			var field:TextField = new TextField();
			field.defaultTextFormat = new TextFormat(Paths.font("vcr.ttf"), fontSize, 0xFFFFFF);
			field.text = sample;

			var measured:Float = field.textWidth;
			if (measured > 0)
				width = measured / sample.length;
		}
		catch (e:Dynamic)
		{
			// keep the estimate
		}

		if (width < 1)
			width = fontSize * CHAR_WIDTH_FALLBACK;

		_charWidths.set(fontSize, width);

		return width;
	}

	static function maxCharsFor(width:Float, fontSize:Int):Int
	{
		var count:Int = Std.int(width / avgCharWidth(fontSize));

		return (count < 8) ? 8 : count;
	}

	/**
	 * Breaks `text` into lines that fit `maxWidth`, honouring the explicit newlines in it and
	 * preferring to break after a path separator or a space. `maxLines` of 0 or less means "as many
	 * as needed"; when the text has to be cut, the last line is marked with an ellipsis.
	 */
	static function wrapLines(text:String, maxWidth:Float, fontSize:Int, maxLines:Int):Array<String>
	{
		var lines:Array<String> = [];
		if (text == null || text.length < 1)
			return lines;

		var source:String = (text.length > 4000) ? text.substr(0, 4000) : text;
		var maxChars:Int = maxCharsFor(maxWidth, fontSize);

		for (logical in source.split('\n'))
		{
			var rest:String = logical;
			while (rest.length > maxChars)
			{
				var cut:Int = breakIndex(rest, maxChars);
				lines.push(rest.substr(0, cut));
				rest = rest.substr(cut);
			}

			lines.push(rest);
		}

		if (maxLines > 0 && lines.length > maxLines)
		{
			lines = lines.slice(0, maxLines);
			var last:Int = maxLines - 1;
			lines[last] = ellipsize(lines[last], maxChars);
		}

		return lines;
	}

	/** Wraps coloured items and clamps the total to `maxLines`, marking what was dropped. */
	static function wrapColored(items:Array<SaveLine>, maxWidth:Float, fontSize:Int, maxLines:Int):Array<SaveLine>
	{
		var out:Array<SaveLine> = [];

		for (item in items)
		{
			for (line in wrapLines(item.text, maxWidth, fontSize, 0))
				out.push({text: line, color: item.color});
		}

		if (maxLines > 0 && out.length > maxLines)
		{
			out = out.slice(0, maxLines);
			var last:Int = maxLines - 1;
			out[last] = {
				text: ellipsize(out[last].text, maxCharsFor(maxWidth, fontSize)),
				color: out[last].color
			};
		}

		return out;
	}

	/** Index (exclusive) to break a line at, so the separator stays on the first line. */
	static function breakIndex(text:String, maxChars:Int):Int
	{
		var limit:Int = (maxChars < text.length) ? maxChars : text.length;
		var i:Int = limit - 1;

		while (i > 8)
		{
			var c:String = text.charAt(i);
			if (c == '/' || c == '\\' || c == ' ' || c == '-' || c == ',' || c == ';')
				return i + 1;
			i--;
		}

		return (limit < 1) ? 1 : limit;
	}

	static function ellipsize(text:String, maxChars:Int):String
	{
		var room:Int = maxChars - ELLIPSIS.length;
		if (room < 1)
			return ELLIPSIS;

		return (text.length > room) ? text.substr(0, room) + ELLIPSIS : text + ELLIPSIS;
	}

	/** Shortens `text` from the middle, which keeps the file name of a path readable. */
	static function clipMiddle(text:String, maxWidth:Float, fontSize:Int):String
	{
		if (text == null)
			return '';
		if (maxWidth <= 0)
			return text;

		var maxChars:Int = maxCharsFor(maxWidth, fontSize);
		if (text.length <= maxChars)
			return text;

		var tail:Int = Std.int((maxChars - ELLIPSIS.length) * 0.6);
		var head:Int = maxChars - tail - ELLIPSIS.length;
		if (head < 1)
			head = 1;
		if (tail < 1)
			tail = 1;

		return text.substr(0, head) + ELLIPSIS + text.substr(text.length - tail);
	}

	/** Shortens `text` at the end; used for code lines, which are read from the left. */
	static function clipEnd(text:String, maxWidth:Float, fontSize:Int):String
	{
		if (text == null)
			return '';
		if (maxWidth <= 0)
			return text;

		var maxChars:Int = maxCharsFor(maxWidth, fontSize);
		if (text.length <= maxChars)
			return text;

		return ellipsize(text.substr(0, maxChars), maxChars);
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
			_layoutWidth = -1;
			_layoutHeight = -1;
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

/** Vertical write position of one column of the scrolling body. */
private class BlockSaveColumn
{
	public var x:Float = 0;
	public var w:Float = 0;
	public var cursor:Float = 0;

	public function new(x:Float, w:Float)
	{
		this.x = x;
		this.w = w;
	}
}

/** Reused labels for one block of the body, so a relayout never leaks a sprite. */
private class SaveLinePool
{
	public var lines:Array<FlxText> = [];
	public var used:Int = 0;

	public function new()
	{
	}
}

/**
 * One touch target of `BlockSavePanel`: a flat rectangle, its label, an optional switch and the
 * action it fires.
 *
 * The label and the switch are drawn by `draw()` (the way `Block` draws its own label and icon)
 * instead of being group members, so a row stays one object for hit testing, scrolling and colour
 * state.
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

	var textColor:Int = 0xFFC0CAF5;
	var fontSize:Int = 15;
	var alignLeft:Bool = false;
	var labelPadX:Float = 8;
	var labelOffsetY:Float = 0;
	var isActive:Bool = false;
	var isPressed:Bool = false;

	var switchOn:Bool = false;
	var switchShown:Bool = false;
	var switchTrack:FlxSprite = null;
	var switchKnob:FlxSprite = null;

	public function new(x:Float, y:Float, w:Float, h:Float, text:String, color:Int, textColor:Int, size:Int = 15, alignLeft:Bool = false)
	{
		super(x, y);

		this.fontSize = size;
		this.textColor = textColor;
		this.alignLeft = alignLeft;
		normalColor = color;
		activeColor = color;
		labelPadX = Math.max(6, 8 * BlockLayout.scale);

		makeGraphic(Std.int(Math.max(w, 1)), Std.int(Math.max(h, 1)), FlxColor.WHITE);

		label = new FlxText(x + labelPadX, y, Std.int(Math.max(w - labelPadX * 2, 16)), text, size);
		label.scrollFactor.set(0, 0);
		applyFormat();

		setRect(x, y, w, h);
		refreshColor();
	}

	public function setFontSize(size:Int):Void
	{
		if (fontSize == size)
			return;

		fontSize = size;
		applyFormat();
		applyLabelRect();
	}

	public function setAlignLeft(value:Bool):Void
	{
		if (alignLeft == value)
			return;

		alignLeft = value;
		applyFormat();
	}

	/** Background pair of the row: the one it has while off and the one it has while switched on. */
	public function setColors(normal:Int, active:Int):Void
	{
		normalColor = normal;
		activeColor = active;
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

	/** Switches the right-hand switch on or off; `shown` false keeps it out of the way. */
	public function setSwitch(on:Bool, shown:Bool):Void
	{
		switchOn = on;

		if (shown && switchTrack == null)
			createSwitch();

		var changed:Bool = (switchShown != shown);
		switchShown = shown;

		if (changed)
		{
			applyLabelRect();
			layoutSwitch();
			return;
		}

		if (shown)
			layoutSwitch();
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

		applyLabelRect();
		layoutSwitch();
	}

	/** Follows the panel's scroll offset; the label and the switch move with the cell. */
	public function moveTo(y:Float):Void
	{
		this.y = y;

		if (label != null)
			label.y = y + labelOffsetY;

		layoutSwitch();
	}

	public function containsPoint(x:Float, y:Float):Bool
	{
		return (x >= this.x && x <= this.x + hitW && y >= this.y && y <= this.y + hitH);
	}

	override public function draw():Void
	{
		super.draw();

		if (switchShown && switchTrack != null && switchKnob != null)
		{
			switchTrack.scrollFactor.copyFrom(scrollFactor);
			switchTrack.cameras = cameras;
			switchTrack.draw();

			switchKnob.scrollFactor.copyFrom(scrollFactor);
			switchKnob.cameras = cameras;
			switchKnob.draw();
		}

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
		FlxDestroyUtil.destroy(switchTrack);
		switchTrack = null;
		FlxDestroyUtil.destroy(switchKnob);
		switchKnob = null;

		super.destroy();
	}

	function applyFormat():Void
	{
		if (label == null)
			return;

		label.setFormat(Paths.font("vcr.ttf"), fontSize, textColor, alignLeft ? LEFT : CENTER);
	}

	function applyLabelRect():Void
	{
		if (label == null)
			return;

		var room:Float = hitW - labelPadX * 2 - (switchShown ? switchSpace() + labelPadX : 0);
		labelOffsetY = (hitH - BlockSavePanel.lineHeight(fontSize)) * 0.5;
		label.fieldWidth = Std.int(Math.max(room, 16));
		// The field width centers the text; wrapping it into a second line would break the row.
		label.wordWrap = false;
		label.x = this.x + labelPadX;
		label.y = this.y + labelOffsetY;
	}

	function createSwitch():Void
	{
		switchTrack = new FlxSprite(0, 0);
		switchTrack.scrollFactor.set(0, 0);
		switchTrack.makeGraphic(1, 1, FlxColor.WHITE);

		switchKnob = new FlxSprite(0, 0);
		switchKnob.scrollFactor.set(0, 0);
		switchKnob.makeGraphic(1, 1, FlxColor.WHITE);
	}

	function switchSpace():Float
	{
		return switchTrackHeight() * 1.9;
	}

	function switchTrackHeight():Float
	{
		var wanted:Float = hitH - 10 * BlockLayout.scale;

		return Math.min(Math.max(wanted, 16), 30 * BlockLayout.scale);
	}

	function layoutSwitch():Void
	{
		if (!switchShown || switchTrack == null || switchKnob == null)
			return;

		var trackH:Float = switchTrackHeight();
		var trackW:Float = trackH * 1.9;
		var trackX:Float = this.x + hitW - labelPadX - trackW;
		var trackY:Float = this.y + (hitH - trackH) * 0.5;

		setGraphic(switchTrack, Std.int(trackW), Std.int(trackH));
		switchTrack.setPosition(trackX, trackY);
		switchTrack.color = switchOn ? BlockSavePanel.COLOR_SWITCH_ON : BlockSavePanel.COLOR_SWITCH_OFF;

		var knob:Float = Math.max(8, trackH - 6);
		setGraphic(switchKnob, Std.int(knob), Std.int(knob));
		switchKnob.setPosition(switchOn ? (trackX + trackW - knob - 3) : (trackX + 3), trackY + (trackH - knob) * 0.5);
		switchKnob.color = switchOn ? BlockSavePanel.COLOR_DARK_TEXT : BlockSavePanel.COLOR_TEXT;
	}

	static function setGraphic(sprite:FlxSprite, w:Int, h:Int):Void
	{
		if (sprite == null)
			return;

		var width:Int = Std.int(Math.max(w, 1));
		var height:Int = Std.int(Math.max(h, 1));
		if (Std.int(sprite.width) == width && Std.int(sprite.height) == height)
			return;

		sprite.makeGraphic(width, height, FlxColor.WHITE);
	}

	function refreshColor():Void
	{
		var tint:FlxColor = FlxColor.fromInt(isActive ? activeColor : normalColor);

		if (isPressed)
			tint = tint.getLightened(0.12);

		color = tint;
	}
}
