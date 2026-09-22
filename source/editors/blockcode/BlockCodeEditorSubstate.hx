package editors.blockcode;

import editors.blockcode.Block.InputField;
import editors.blockcode.BlockTypes.BlockCategory;
import editors.blockcode.BlockTypes.BlockCodeEditorSettings;
import editors.blockcode.BlockTypes.BlockData;
import editors.blockcode.BlockTypes.BlockProject;
import editors.blockcode.BlockTypes.ImportResult;
import editors.blockcode.BlockTypes.ParamType;
import editors.blockcode.BlockTypes.TimelineMarker;
import flixel.FlxBasic;
import flixel.FlxState;
import flixel.addons.display.FlxGridOverlay;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.input.touch.FlxTouch;
import flixel.ui.FlxButton;
import flixel.ui.FlxButton.FlxButtonState;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/** One axis aligned rectangle in screen pixels; every surface of this substate speaks it. */
private typedef Rect =
{
	x:Float,
	y:Float,
	w:Float,
	h:Float
};

/**
 * The block-code editor of Parker Engine as a substate on top of a running `PlayState`.
 *
 * This is `editors.BlockCodeEditorState` rebuilt for the "edit while the song plays" workflow:
 * the same workspace, palette, snapping, panning and zooming, the same colours and the same
 * pointer helpers, but every sprite is put on one of four cameras this substate adds itself
 * (`camEditor` for the workspace, `camPaletteBack`/`camPalette` for the palette, `camHUD` on
 * top) instead of resetting the camera list the way a standalone state can.
 *
 * Every measurement comes from `BlockLayout`, which turns the viewport into fonts, rows and
 * touch targets:
 *
 * - **Landscape** keeps the left palette column (`BlockLayout.sidebarWidth()` plus the narrow
 *   category rail) with the search field and the scrolling block list next to it.
 * - **Portrait/compact** (`BlockLayout.sidebarVisible() == false`) moves the palette into the
 *   bottom sheet: a drag handle, a horizontally scrollable row of category chips and the block
 *   list under it. A chevron (or dragging the handle up/down) collapses the sheet down to the
 *   chip row, which hands the freed height back to the workspace and the timeline.
 * - The top bar wraps its buttons into `BlockLayout.topBarRows()` (or more) rows, keeping the
 *   block counter on the first row and never letting two buttons touch.
 * - A docked live code preview (the `BlockCodePreview` widget) sits against the right edge of
 *   the workspace, visible by default only in a roomy landscape viewport.
 *
 * What the migration adds beyond the layout:
 *
 * - **Live song** - `PlayState.instance.persistentUpdate` is turned on while the editor is open,
 *   so the song keeps running and drawing behind it; a translucent backdrop keeps both layers
 *   readable. The top bar can pause the song (audio + the conductor clock, so nothing drifts)
 *   and toggle the live reload of the generated script.
 * - **Timeline** - `BlockTimeline` along the bottom shows the song position, can seek the song
 *   (`BlockScriptRuntime.seekTo()`, music paused while dragging) and carries the markers whose
 *   block stacks fire at that moment.
 * - **Per-marker workspace** - a segmented control switches between the global scripts and the
 *   stack of the selected marker. A marker owns as many root stacks as the user builds; they are
 *   persisted as one `BlockSerializer` timeline entry per root, which round-trips unchanged.
 * - **Save / live reload** - Save (or Ctrl+S) regenerates the Lua, writes it through `BlockFileIO`
 *   and, when Live is on, reloads it into the running song with `BlockScriptRuntime`.
 * - **Undo/redo, autosave and the editor panels** (save settings, code, files, help, context menu).
 *
 * ESC closes the editor. Because the parent `PlayState` runs its own update first (and would open
 * the pause menu on the same key), the ESC/back press is consumed in a `preUpdate` signal handler
 * before the song sees it; the same press closes an open prompt, keyboard, panel or focused input
 * field first. `closeIfOpen()` is the hook for the Android back gesture handler.
 */
class BlockCodeEditorSubstate extends MusicBeatSubstate
{
	// --- Palette, mirrored from the legacy editor state ---
	public static inline var COLOR_BG:Int = 0xFF1A1B26;
	public static inline var COLOR_GRID_LINE:Int = 0xFF24283B;
	public static inline var COLOR_SIDEBAR_STRIP:Int = 0xFF16161E;
	public static inline var COLOR_SIDEBAR_BG:Int = 0xFF1A1B26;
	public static inline var COLOR_SEPARATOR:Int = 0xFF414868;
	public static inline var COLOR_STATUS_BAR:Int = 0xFF3D59A1;
	public static inline var COLOR_STATUS_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_BLOCK_COUNT:Int = 0xFF565F89;
	public static inline var COLOR_SCROLL_TRACK:Int = 0xFF16161E;
	public static inline var COLOR_SCROLL_THUMB:Int = 0xFF565F89;
	public static inline var COLOR_TRASH:Int = 0xFFF7768E;
	public static inline var COLOR_TOOLTIP_BG:Int = 0xEE0F0F14;
	public static inline var COLOR_BAR:Int = 0xFF16161E;
	public static inline var COLOR_BUTTON:Int = 0xFF24283B;
	public static inline var COLOR_BUTTON_ACTIVE:Int = 0xFF3D59A1;
	public static inline var COLOR_BUTTON_GOOD:Int = 0xFF9ECE6A;
	public static inline var COLOR_BUTTON_WARN:Int = 0xFFE0AF68;
	public static inline var COLOR_BUTTON_ACTION:Int = 0xFF7AA2F7;
	public static inline var COLOR_DIM:Int = 0xAA000000;
	public static inline var COLOR_SHEET_BG:Int = 0xFF16161E;
	public static inline var COLOR_HANDLE:Int = 0xFF414868;
	public static inline var COLOR_TILE_FILL:Int = 0xFFFFFFFF;
	public static inline var COLOR_TILE_BORDER:Int = 0xFF5A5A5A;
	public static inline var COLOR_TILE_GRIP:Int = 0xFF8A8A8A;

	// --- Behaviour (all geometry comes from `BlockLayout`) ---
	public static inline var SNAP_DISTANCE:Float = 30;
	public static inline var LONG_PRESS_TIME:Float = 0.5;
	public static inline var AUTOSAVE_INTERVAL:Float = 5;
	public static inline var MAX_UNDO:Int = 30;
	public static inline var STATUS_HOLD:Float = 3.5;
	public static inline var MIN_ZOOM:Float = 0.1;
	public static inline var MAX_ZOOM:Float = 3;
	public static inline var MAX_EVENT_OPTIONS:Int = 8;
	public static inline var SCROLLBAR_WIDTH:Float = 8;

	/** Pointer travel (px) before a palette tap turns into a drag. */
	public static inline var DRAG_SLOP:Float = 10;

	/** Throttle for regenerating the Lua the live preview shows. */
	public static inline var PREVIEW_CODE_INTERVAL:Float = 0.25;

	/** Workspace id of the global scripts; a marker id is the workspace id of its stack. */
	public static inline var GLOBAL_WORKSPACE:String = '';

	/** The editor currently on screen, so `closeIfOpen()` can find it. */
	public static var instance(default, null):BlockCodeEditorSubstate;

	// --- Cameras ---
	var camEditor:FlxCamera;
	var camHUD:FlxCamera;

	/** Static palette decoration (panel background, rail background, rail buttons, scrollbar): never scrolls. */
	var camPaletteBack:FlxCamera;

	/** Scrolling palette content (section headers and block tiles), anchored to the list rect. */
	var camPalette:FlxCamera;

	// --- Workspace ---
	var dimBackdrop:FlxSprite;
	var workspaceBg:FlxSprite;
	var gridBG:FlxSprite;
	var blockContainer:FlxTypedGroup<Block>;

	/** Which workspace (see `GLOBAL_WORKSPACE`) every block belongs to. */
	var blockWorkspace:Map<Block, String> = new Map();

	// --- Layout ---
	var ready:Bool = false;
	var layoutReady:Bool = false;
	var appliedWidth:Float = -1;
	var appliedHeight:Float = -1;
	var appliedScale:Float = -1;
	var appliedPortrait:Bool = false;
	var appliedCompact:Bool = false;
	var appliedNarrow:Bool = false;

	var inset:Float = 8;
	var gap:Float = 4;
	var buttonHeight:Float = 38;
	var barHeight:Float = 0;
	var barRows:Int = 1;
	var counterWidth:Float = 120;

	var wsRect:Rect;
	var timelineRect:Rect;
	var paletteBand:Rect;
	var paletteList:Rect;
	var paletteStrip:Rect;
	var searchRect:Rect;
	var chipsRect:Rect;
	var handleRect:Rect;
	var chevronRect:Rect;
	var scrollbarRect:Rect;
	var searchHeight:Float = 34;
	var chipsHeight:Float = 34;
	var sheetHeight:Float = 0;
	var trashSize:Float = 40;

	// --- Palette ---
	var paletteSections:Array<PaletteSection> = [];
	var railButtons:Array<CategoryButton> = [];
	var paletteChips:Array<CategoryButton> = [];
	var paletteScroll:Float = 0;
	var paletteContentHeight:Float = 0;
	var paletteCollapsed:Bool = false;
	var paletteBuildKey:String = '';
	var activeCategory:String = '';
	var chipsScroll:Float = 0;
	var chipsContentWidth:Float = 0;
	var railButtonSize:Float = 40;
	var scrollTrack:FlxSprite;
	var scrollThumb:FlxSprite;
	var paletteBg:FlxSprite;
	var paletteStripBg:FlxSprite;
	var paletteSeparator:FlxSprite;
	var handlePill:FlxSprite;
	var collapseButton:FlxButton;
	var searchField:InputField;
	var searchFieldWidth:Float = 0;
	var searchFieldHeight:Float = 0;
	var searchText:String = '';

	var isDraggingScroll:Bool = false;
	var scrollDragOffset:Float = 0;
	var paletteDragLastY:Float = 0;
	var mouseScrollActive:Bool = false;
	var paletteScrollTween:FlxTween;
	var paletteScrollProxy:{value:Float};
	var tilePress:PaletteTile = null;
	var tilePressX:Float = 0;
	var tilePressY:Float = 0;
	var tileDragStarted:Bool = false;
	var railPress:CategoryButton = null;
	var chipPress:CategoryButton = null;
	var chipsDragging:Bool = false;
	var chipsDragStartX:Float = 0;
	var chipsScrollStart:Float = 0;
	var sheetDragging:Bool = false;
	var sheetDragStartY:Float = 0;
	var sheetDragMoved:Bool = false;

	// --- HUD ---
	var topBarBg:FlxSprite;
	var globalTabButton:FlxButton;
	var markerTabButton:FlxButton;
	var pauseButton:FlxButton;
	var liveButton:FlxButton;
	var saveButton:FlxButton;
	var saveAsButton:FlxButton;
	var codeButton:FlxButton;
	var filesButton:FlxButton;
	var helpButton:FlxButton;
	var previewButton:FlxButton;
	var undoButton:FlxButton;
	var redoButton:FlxButton;
	var testButton:FlxButton;
	var closeButton:FlxButton;
	var markerButton:FlxButton;
	var barButtons:Array<FlxButton> = [];
	var barGroups:Array<Array<FlxButton>> = [];
	var buttonColors:Map<FlxButton, Int> = new Map();

	var statusBar:FlxSprite;
	var statusText:FlxText;
	var statusMessage:String = '';
	var statusHold:Float = 0;
	var blockCountText:FlxText;

	var trashCan:FlxSprite;
	var trashLabel:FlxText;
	var tooltipBox:FlxSprite;
	var tooltipText:FlxText;
	var tooltipMessage:String = '';
	var tooltipBoxWidth:Float = 0;
	var tooltipBoxHeight:Float = 0;

	// --- Timeline ---
	var timeline:BlockTimeline;
	var timelinePlaced:Rect;
	var songInfoReady:Bool = false;
	var songInfoPoll:Float = 0;
	var mappedSong:SwagSong = null;

	// --- Panels ---
	var savePanel:BlockSavePanel;
	var codePanel:BlockCodePanel;
	var fileBrowser:BlockFileBrowser;
	var helpOverlay:BlockHelpOverlay;
	var contextMenu:BlockContextMenu;
	var virtualKeyboard:BlockVirtualKeyboard;
	var prompt:PromptBox;
	var panelOpen:Bool = false;
	var panelsBuilt:Bool = false;
	var contextMenuWidth:Float = 0;
	var contextMenuHeight:Float = 0;

	// --- Live preview ---
	var preview:BlockCodePreview;
	var previewRect:Rect;
	var previewWanted:Bool = false;
	var previewToggled:Bool = false;
	var previewCodeDirty:Bool = true;
	var previewCodeTimer:Float = 0;

	// --- Interaction ---
	var draggingBlock:Block = null;
	var pendingDragBlock:Block = null;
	var pendingPan:Bool = false;
	var dragOffset:FlxPoint = FlxPoint.get();
	var isDragging:Bool = false;
	var isPanning:Bool = false;
	var panStart:FlxPoint = FlxPoint.get();
	var zoomLevel:Float = 1;
	var lastSpawnPos:FlxPoint = new FlxPoint(0, 0);

	var pressHeldTime:Float = 0;
	var pressStartX:Float = 0;
	var pressStartY:Float = 0;
	var pressConsumed:Bool = false;
	var pointerSwallowed:Bool = false;
	var contextMenuX:Float = 0;
	var contextMenuY:Float = 0;
	var contextBlock:Block = null;
	var markerMoveSnapshot:Bool = false;

	var seekDragActive:Bool = false;
	var seekWasPlaying:Bool = false;

	// --- Editing / persistence ---
	var settings:BlockCodeEditorSettings;
	var editingField:InputField = null;
	var liveReload:Bool = true;
	var songPaused:Bool = false;
	var frozenSongPosition:Float = -1;
	var dirty:Bool = false;
	var autosaveTimer:Float = 0;
	var undoStack:Array<BlockProject> = [];
	var redoStack:Array<BlockProject> = [];
	var restoringHistory:Bool = false;
	var parentState:FlxState = null;
	var previousPersistentUpdate:Bool = false;
	var preUpdateHooked:Bool = false;
	var preUpdateListener:Void->Void = null;
	var chartEventNamesCache:Array<String> = [];
	var suggestedSongName:String = '';

	// --- Per-marker workspace ---
	var activeMarkerId:String = '';
	var showingGlobals:Bool = true;

	#if android
	/** The editor's own pad: its X/Y buttons zoom, exactly like in the standalone editor. */
	var editorTouchPad:FlxTouchPad;
	#end

	public function new(?songName:String = null)
	{
		super();
		suggestedSongName = (songName == null) ? '' : songName;
	}

	// ============================================================================================
	// Lifecycle
	// ============================================================================================

	/** Opens the editor on top of the running `PlayState` (or of the current state) as its substate. */
	public static function open(?songName:String = null):BlockCodeEditorSubstate
	{
		if (instance != null)
			return instance;

		var editor:BlockCodeEditorSubstate = new BlockCodeEditorSubstate(songName);
		var host:FlxState = (PlayState.instance != null) ? PlayState.instance : FlxG.state;
		if (host != null)
			host.openSubState(editor); // replaces an already open substate, never the song itself
		else
			FlxG.switchState(editor);

		return editor;
	}

	/** Closes the editor when one is open; returns whether it closed something. */
	public static function closeIfOpen():Bool
	{
		if (instance == null)
			return false;

		instance.exitEditor();
		return true;
	}

	override function create():Void
	{
		instance = this;
		parentState = FlxG.state;

		// Keeps the song updating (and drawing) behind the editor. The value the song had is restored
		// in `destroy()`: `PlayState.create()` sets it to true itself (source/states/game/PlayState.hx),
		// so hard-setting it to false on close would change how the song behaves afterwards.
		if (PlayState.instance != null)
		{
			previousPersistentUpdate = PlayState.instance.persistentUpdate;
			PlayState.instance.persistentUpdate = true;
			// Keep the song playing for the live preview, but stop gameplay keys from hitting notes
			// (typing in the editor, block dragging and the on-screen keyboards all send key events).
			PlayState.blockEditorActive = true;
		}

		setupCameras();
		createBackdrop();

		blockContainer = new FlxTypedGroup<Block>();
		add(blockContainer);

		// Builds the top bar, the palette, the status bar, the timeline, the preview and the panels
		// in one pass, so a viewport change is handled by the very same code.
		ensureLayout();

		loadCachedProject();
		installInputHooks();
		refreshTimelineSongInfo();
		refreshWorkspace();

		FlxG.mouse.visible = true;
		#if android
		setupEditorTouchPad();
		#end

		// Opened on top of a paused song (e.g. from the pause menu): the audio is already stopped, so
		// the editor starts in its own paused state and only freezes the clock to match it.
		if (PlayState.instance != null && PlayState.instance.paused)
		{
			songPaused = true;
			frozenSongPosition = Conductor.songPosition;
			syncPauseButton();
		}

		hookPreUpdate();
		setStatus('Live editor - drag blocks, Space+drag to pan, Ctrl+S to save, ESC to close');

		ready = true;
		super.create();
	}

	override function destroy():Void
	{
		ready = false;
		saveCache();
		unhookPreUpdate();

		Block.requestTextEdit = null;
		Block.requestCodeEdit = null;
		Block.onAnyValueChanged = null;
		Block.externalEditorActive = false;

		BlockSoftKeyboard.destroy();

		if (PlayState.instance != null)
			PlayState.instance.persistentUpdate = previousPersistentUpdate;

		PlayState.blockEditorActive = false;

		instance = null;
		clearBlocks();
		destroyPaletteContent();
		removeCameras();

		super.destroy();
	}

	// ============================================================================================
	// Cameras and backdrop
	// ============================================================================================

	function setupCameras():Void
	{
		camEditor = new FlxCamera();
		camEditor.bgColor.alpha = 0; // the running song has to stay visible behind the editor
		camEditor.scroll.set(0, 0);
		camEditor.zoom = 1;

		camPaletteBack = new FlxCamera(0, 0, 1, 1);
		camPaletteBack.bgColor.alpha = 0;

		camPalette = new FlxCamera(0, 0, 1, 1);
		camPalette.bgColor.alpha = 0;

		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;

		// Never the default draw target: the song's own sprites have to keep drawing on their cameras.
		FlxG.cameras.add(camEditor, false);
		FlxG.cameras.add(camPaletteBack, false);
		FlxG.cameras.add(camPalette, false);
		FlxG.cameras.add(camHUD, false);

		zoomLevel = 1;
		lastSpawnPos.set(0, 0);
	}

	function removeCameras():Void
	{
		if (FlxG.cameras == null)
			return;

		if (camHUD != null)
		{
			FlxG.cameras.remove(camHUD, true);
			camHUD = null;
		}
		if (camPalette != null)
		{
			FlxG.cameras.remove(camPalette, true);
			camPalette = null;
		}
		if (camPaletteBack != null)
		{
			FlxG.cameras.remove(camPaletteBack, true);
			camPaletteBack = null;
		}
		if (camEditor != null)
		{
			FlxG.cameras.remove(camEditor, true);
			camEditor = null;
		}
	}

	function createBackdrop():Void
	{
		// Dims the song instead of hiding it: the two layers have to stay readable at the same time.
		dimBackdrop = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, COLOR_DIM);
		dimBackdrop.scrollFactor.set(0, 0);
		dimBackdrop.cameras = [camEditor];
		add(dimBackdrop);

		workspaceBg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, COLOR_BG);
		workspaceBg.alpha = 0.35;
		workspaceBg.scrollFactor.set(0, 0);
		workspaceBg.cameras = [camEditor];
		add(workspaceBg);

		gridBG = FlxGridOverlay.create(40, 40, Std.int(FlxG.width * 3), Std.int(FlxG.height * 3), true, COLOR_GRID_LINE, COLOR_BG);
		if (gridBG != null)
		{
			gridBG.alpha = 0.4;
			gridBG.scrollFactor.set(0.5, 0.5);
			gridBG.screenCenter();
			gridBG.cameras = [camEditor];
			add(gridBG);
		}
	}

	/** Resizes the canvas backdrop after a viewport change. */
	function resizeBackdrop():Void
	{
		if (dimBackdrop != null
			&& (Std.int(dimBackdrop.width) != Std.int(BlockLayout.width) || Std.int(dimBackdrop.height) != Std.int(BlockLayout.height)))
			dimBackdrop.makeGraphic(Std.int(Math.max(1, BlockLayout.width)), Std.int(Math.max(1, BlockLayout.height)), COLOR_DIM);

		if (workspaceBg != null
			&& (Std.int(workspaceBg.width) != Std.int(BlockLayout.width) || Std.int(workspaceBg.height) != Std.int(BlockLayout.height)))
			workspaceBg.makeGraphic(Std.int(Math.max(1, BlockLayout.width)), Std.int(Math.max(1, BlockLayout.height)), COLOR_BG);
	}

	// ============================================================================================
	// Layout: everything is derived from BlockLayout
	// ============================================================================================

	/** Recomputes the whole layout, but only when the viewport really changed. */
	function ensureLayout():Void
	{
		BlockLayout.ensure();

		if (layoutReady
			&& BlockLayout.width == appliedWidth
			&& BlockLayout.height == appliedHeight
			&& BlockLayout.scale == appliedScale
			&& BlockLayout.portrait == appliedPortrait
			&& BlockLayout.compact == appliedCompact
			&& BlockLayout.narrow == appliedNarrow)
			return;

		appliedWidth = BlockLayout.width;
		appliedHeight = BlockLayout.height;
		appliedScale = BlockLayout.scale;
		appliedPortrait = BlockLayout.portrait;
		appliedCompact = BlockLayout.compact;
		appliedNarrow = BlockLayout.narrow;

		applyLayout();
	}

	function emptyRect():Rect
	{
		return {
			x: 0,
			y: 0,
			w: 0,
			h: 0
		};
	}

	static function pointInRect(x:Float, y:Float, r:Rect):Bool
	{
		if (r == null || r.w <= 0 || r.h <= 0)
			return false;

		return (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h);
	}

	static function rectChanged(a:Rect, b:Rect):Bool
	{
		if (a == null || b == null)
			return true;

		return (a.x != b.x || a.y != b.y || a.w != b.w || a.h != b.h);
	}

	/** Height of the collapsed bottom sheet: the handle plus the category chips. */
	function collapsedSheetHeight():Float
	{
		return gap + BlockLayout.touchSize() + gap + BlockLayout.touchSize() + gap;
	}

	/** Height of the palette column (landscape) or sheet (portrait), honouring the collapse. */
	function currentSheetHeight():Float
	{
		if (!BlockLayout.portrait)
			return 0;

		return paletteCollapsed ? collapsedSheetHeight() : BlockLayout.paletteSheetHeight();
	}

	/** The band the palette occupies: the left column in landscape, the bottom sheet upright. */
	function computePaletteBand():Rect
	{
		if (BlockLayout.sidebarVisible())
			return {
				x: 0,
				y: wsRect.y,
				w: BlockLayout.sidebarWidth(),
				h: wsRect.h
			};

		var h:Float = currentSheetHeight();
		return {
			x: 0,
			y: BlockLayout.height - BlockLayout.statusHeight() - h,
			w: BlockLayout.width,
			h: h
		};
	}

	/** Screen rect of the live code preview: docked against the right edge of the workspace. */
	function computePreviewRect():Rect
	{
		var top:Float = wsRect.y + inset;
		var bottom:Float = wsRect.y + wsRect.h - inset;

		if (BlockLayout.portrait)
			top += BlockLayout.touchSize() + gap;
		else
			bottom -= buttonHeight + gap;

		var w:Float = Math.min(wsRect.w * 0.34, 420 * BlockLayout.scale);
		var h:Float = Math.max(90, bottom - top);

		return {
			x: wsRect.x + wsRect.w - w - inset,
			y: top,
			w: w,
			h: h
		};
	}

	/** Rebuilds every rect, camera and widget position for the current `BlockLayout` metrics. */
	function applyLayout():Void
	{
		layoutReady = true;

		inset = BlockLayout.inset();
		gap = BlockLayout.spacing('tight');
		buttonHeight = BlockLayout.buttonHeight();
		counterWidth = Math.max(BlockLayout.buttonWidth('Blocks: 000'), 84 * BlockLayout.scale);

		ensureTopBar();
		resizeBarButtons();

		barRows = wrapTopBar(false);
		barHeight = BlockLayout.topBarHeight(barRows);
		buttonHeight = BlockLayout.buttonHeight();

		computeRects();
		applyCameraRects();
		resizeBackdrop();

		ensureStatusBar();
		ensureTrash();
		ensureTooltip();
		ensureMarkerButton();

		layoutTopBar();
		layoutBlockCounter();
		layoutStatusBar();
		ensurePaletteChrome();
		layoutPaletteChrome();
		ensureSearchField();
		rebuildPaletteContent();
		layoutTrash();
		layoutMarkerButton();
		placeTimeline();
		placePreview();
		placePanels();

		if (!previewToggled)
			previewWanted = !BlockLayout.portrait && !BlockLayout.compact;

		syncPreview();
		updatePreviewButton();
		refreshPaletteVisibility();

		#if android
		if (ready)
			setupEditorTouchPad();
		#end
	}

	/** The canvas band: below the real (wrapped) top bar, above the timeline. */
	function computeRects():Void
	{
		var statusY:Float = BlockLayout.height - BlockLayout.statusHeight();

		sheetHeight = currentSheetHeight();

		var timelineHeight:Float = BlockLayout.timelineHeight();
		var timelineY:Float = BlockLayout.portrait ? (statusY - sheetHeight - timelineHeight) : (statusY - timelineHeight);

		var sidebar:Float = BlockLayout.sidebarVisible() ? BlockLayout.sidebarWidth() : 0;
		var wsY:Float = Math.max(BlockLayout.workspace().y, barHeight + gap);

		wsRect = {
			x: sidebar,
			y: wsY,
			w: Math.max(160, BlockLayout.width - sidebar),
			h: Math.max(100, timelineY - gap - wsY)
		};

		var timelineX:Float = BlockLayout.sidebarVisible() ? (sidebar + gap) : inset;
		var timelineRight:Float = BlockLayout.portrait ? inset : BlockLayout.timelineRightMargin();

		timelineRect = {
			x: timelineX,
			y: timelineY,
			w: Math.max(160, BlockLayout.width - timelineX - timelineRight),
			h: timelineHeight
		};

		paletteBand = computePaletteBand();

		searchHeight = Math.max(BlockLayout.touchSize() * (BlockLayout.portrait ? 0.9 : 1), 34 * BlockLayout.scale);
		chipsHeight = BlockLayout.touchSize();

		if (BlockLayout.sidebarVisible())
		{
			var stripW:Float = BlockLayout.categoryStripWidth();
			paletteStrip = {
				x: 0,
				y: paletteBand.y,
				w: stripW,
				h: paletteBand.h
			};

			var columnX:Float = stripW + gap;
			var columnW:Float = Math.max(80, paletteBand.w - stripW - gap * 2 - SCROLLBAR_WIDTH * BlockLayout.scale);
			var normal:Float = BlockLayout.spacing('normal');

			searchRect = {
				x: columnX,
				y: paletteBand.y + gap,
				w: columnW,
				h: searchHeight
			};

			// The list starts directly under the search field, and its first category header is the
			// first row of the list content, so `normal` is the entire gap between the two.
			paletteList = {
				x: columnX,
				y: searchRect.y + searchHeight + normal,
				w: columnW,
				h: Math.max(40, paletteBand.y + paletteBand.h - (searchRect.y + searchHeight + normal) - gap)
			};

			// The chip row belongs to the portrait sheet; in the column the categories live in the rail.
			chipsHeight = 0;
			chipsRect = emptyRect();
			handleRect = emptyRect();
			chevronRect = emptyRect();
		}
		else
		{
			paletteStrip = emptyRect();

			var handleH:Float = BlockLayout.touchSize();
			var columnX:Float = gap;
			var columnW:Float = Math.max(80, paletteBand.w - gap * 2 - SCROLLBAR_WIDTH * BlockLayout.scale);

			handleRect = {
				x: 0,
				y: paletteBand.y,
				w: paletteBand.w,
				h: handleH
			};
			chevronRect = {
				x: paletteBand.w - inset - BlockLayout.touchSize(),
				y: paletteBand.y,
				w: BlockLayout.touchSize(),
				h: handleH
			};

			if (paletteCollapsed)
			{
				searchRect = emptyRect();
				paletteList = emptyRect();
				chipsRect = {
					x: gap,
					y: paletteBand.y + handleH + gap,
					w: paletteBand.w - gap * 2,
					h: chipsHeight
				};
			}
			else
			{
				searchRect = {
					x: columnX,
					y: paletteBand.y + handleH + gap,
					w: columnW,
					h: searchHeight
				};
				chipsRect = {
					x: gap,
					y: searchRect.y + searchHeight + gap,
					w: paletteBand.w - gap * 2,
					h: chipsHeight
				};
				paletteList = {
					x: columnX,
					y: chipsRect.y + chipsHeight + BlockLayout.spacing('normal'),
					w: columnW,
					h: Math.max(40, paletteBand.y + paletteBand.h - (chipsRect.y + chipsHeight + BlockLayout.spacing('normal')) - gap)
				};
			}
		}

		if (paletteList.h > 0)
			scrollbarRect = {
				x: paletteBand.x + paletteBand.w - SCROLLBAR_WIDTH * BlockLayout.scale - gap * 0.5,
				y: paletteList.y,
				w: SCROLLBAR_WIDTH * BlockLayout.scale,
				h: paletteList.h
			};
		else
			scrollbarRect = emptyRect();

		previewRect = computePreviewRect();
	}

	/** Sizes and places the four cameras on the rects `computeRects()` produced. */
	function applyCameraRects():Void
	{
		var screenW:Int = Std.int(Math.max(1, BlockLayout.width));
		var screenH:Int = Std.int(Math.max(1, BlockLayout.height));

		if (camEditor != null)
		{
			camEditor.setSize(screenW, screenH);
			camEditor.setPosition(0, 0);
		}

		if (camHUD != null)
		{
			camHUD.setSize(screenW, screenH);
			camHUD.setPosition(0, 0);
			camHUD.scroll.set(0, 0);
		}

		if (camPaletteBack != null)
		{
			camPaletteBack.setSize(Std.int(Math.max(1, paletteBand.w)), Std.int(Math.max(1, paletteBand.h)));
			camPaletteBack.setPosition(Std.int(paletteBand.x), Std.int(paletteBand.y));
			// Sprites of the palette are laid out in screen coordinates, so the camera has to look at
			// exactly the band it covers: world == screen at scroll 0.
			camPaletteBack.scroll.set(paletteBand.x, paletteBand.y);
			camPaletteBack.visible = (paletteBand.w > 0 && paletteBand.h > 0);
		}

		if (camPalette != null)
		{
			// The palette content is authored in list-local coordinates and this camera *is* the list
			// rect, so the content can never be offset by the band it lives in: local (0, 0) is the top
			// left corner of the list, and only the scroll moves it.
			camPalette.setSize(Std.int(Math.max(1, paletteList.w)), Std.int(Math.max(1, paletteList.h)));
			camPalette.setPosition(Std.int(paletteList.x), Std.int(paletteList.y));
			camPalette.scroll.set(0, paletteScroll);
			camPalette.visible = (paletteList.w > 0 && paletteList.h > 0);
		}
	}

	// ============================================================================================
	// Top bar
	// ============================================================================================

	function ensureTopBar():Void
	{
		if (topBarBg != null)
			return;

		topBarBg = new FlxSprite().makeGraphic(1, 1, COLOR_BAR);
		topBarBg.scrollFactor.set(0, 0);
		topBarBg.cameras = [camHUD];
		add(topBarBg);

		globalTabButton = makeButton('Global scripts', selectGlobalWorkspace, COLOR_BUTTON_ACTIVE);
		markerTabButton = makeButton('No marker', selectMarkerWorkspace, COLOR_BUTTON);
		pauseButton = makeButton('Pause song', toggleSongPause, COLOR_BUTTON_WARN);
		liveButton = makeButton('Live on', toggleLiveReload, COLOR_BUTTON_GOOD);
		saveButton = makeButton('Save', saveAndReload, COLOR_BUTTON_GOOD);
		saveAsButton = makeButton('Save as', openSavePanel, COLOR_BUTTON);
		codeButton = makeButton('Code', openCodePanel, COLOR_BUTTON_ACTION);
		filesButton = makeButton('Files', openFileBrowser, COLOR_BUTTON_ACTION);
		helpButton = makeButton('Help', openHelpPanel, COLOR_BUTTON);
		previewButton = makeButton('Preview', togglePreview, COLOR_BUTTON);
		undoButton = makeButton('Undo', undo, COLOR_BUTTON);
		redoButton = makeButton('Redo', redo, COLOR_BUTTON);
		testButton = makeButton('Test', testInSong, COLOR_BUTTON_GOOD);
		closeButton = makeButton('Close', exitEditor, COLOR_TRASH);

		// The bar reads as groups: which workspace is being edited, the song controls, saving, the
		// side panels, the live preview and finally the history / session buttons.
		barGroups = [
			[globalTabButton, markerTabButton],
			[pauseButton, liveButton],
			[saveButton, saveAsButton],
			[codeButton, filesButton, helpButton],
			[previewButton],
			[undoButton, redoButton, testButton, closeButton]
		];

		barButtons = [];
		for (group in barGroups)
		{
			for (button in group)
			{
				if (button != null)
					barButtons.push(button);
			}
		}

		updatePreviewButton();
	}

	function makeButton(label:String, callback:Void->Void, color:Int):FlxButton
	{
		var button:FlxButton = new FlxButton(0, 0, label, callback);
		button.makeGraphic(Std.int(BlockLayout.buttonWidth(label)), Std.int(BlockLayout.buttonHeight()), color);
		button.visible = false;
		button.cameras = [camHUD];
		buttonColors.set(button, color);
		styleButtonLabel(button);
		// Buttons are only created here, so this is the one place that has to register them with
		// the substate: without it they exist, get positioned, and are never drawn.
		add(button);

		return button;
	}

	function buttonColor(button:FlxButton):Int
	{
		if (button == null)
			return COLOR_BUTTON;

		var color:Null<Int> = buttonColors.get(button);
		return (color == null) ? COLOR_BUTTON : color;
	}

	function styleButtonLabel(button:FlxButton):Void
	{
		if (button == null || button.label == null)
			return;

		button.label.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('body'), FlxColor.WHITE, CENTER);
		button.label.fieldWidth = Std.int(Math.max(1, button.width));
		centerButtonLabel(button);
	}

	function centerButtonLabel(button:FlxButton):Void
	{
		if (button == null || button.label == null || button.labelOffsets == null)
			return;

		var offset:Float = (buttonHeight - button.label.height) * 0.5;
		if (offset < 0)
			offset = 0;

		for (point in button.labelOffsets)
		{
			if (point != null)
				point.set(point.x, offset);
		}
	}

	function setButtonText(button:FlxButton, label:String):Void
	{
		if (button == null)
			return;

		button.text = label;
		styleButtonLabel(button);
	}

	function setButtonColor(button:FlxButton, color:Int):Void
	{
		if (button == null)
			return;

		buttonColors.set(button, color);
		button.makeGraphic(Std.int(Math.max(1, button.width)), Std.int(Math.max(1, button.height)), color);
		styleButtonLabel(button);
	}

	/** Resizes every bar button to the current metrics, keeping its colour and its label. */
	function resizeBarButtons():Void
	{
		for (button in barButtons)
		{
			if (button == null)
				continue;

			var w:Int = Std.int(Math.max(1, BlockLayout.buttonWidth(button.text)));
			var h:Int = Std.int(Math.max(1, BlockLayout.buttonHeight()));
			if (Std.int(button.width) == w && Std.int(button.height) == h)
				continue;

			button.makeGraphic(w, h, buttonColor(button));
			styleButtonLabel(button);
		}
	}

	/** Right limit for the buttons of one row: row 0 keeps clear of the block counter. */
	function topBarRowLimit(row:Int):Float
	{
		if (row == 0)
			return BlockLayout.width - counterWidth - inset;

		return BlockLayout.width - inset;
	}

	/**
	 * Lays the grouped buttons out with `BlockLayout.spacing()` between them, wrapping a whole
	 * group onto the next row when it would cross the counter (row 0) or the screen edge.
	 * With `apply == false` it only counts the rows.
	 */
	function wrapTopBar(apply:Bool):Int
	{
		var groupGap:Float = BlockLayout.spacing('normal');
		var x:Float = inset;
		var y:Float = gap;
		var row:Int = 0;
		var limit:Float = topBarRowLimit(0);

		for (group in barGroups)
		{
			if (group == null || group.length == 0)
				continue;

			var groupWidth:Float = 0;
			var used:Int = 0;
			for (button in group)
			{
				if (button == null)
					continue;

				if (used > 0)
					groupWidth += gap;
				groupWidth += Math.max(1, button.width);
				used++;
			}

			if (used == 0)
				continue;

			if (x > inset && x + groupWidth > limit)
			{
				row++;
				x = inset;
				y = gap + row * (buttonHeight + gap);
				limit = topBarRowLimit(row);
			}

			for (button in group)
			{
				if (button == null)
					continue;

				if (apply)
				{
					button.setPosition(x, y);
					button.visible = true;
				}

				x += Math.max(1, button.width) + gap;
			}

			x += groupGap - gap;
		}

		return row + 1;
	}

	function layoutTopBar():Void
	{
		var h:Int = Std.int(Math.max(1, barHeight));
		if (topBarBg == null)
			return;

		if (Std.int(topBarBg.width) != Std.int(BlockLayout.width) || Std.int(topBarBg.height) != h)
			topBarBg.makeGraphic(Std.int(Math.max(1, BlockLayout.width)), h, COLOR_BAR);

		topBarBg.setPosition(0, 0);
		wrapTopBar(true);
	}

	function layoutBlockCounter():Void
	{
		if (blockCountText == null)
			return;

		blockCountText.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('small'), COLOR_BLOCK_COUNT, RIGHT);
		blockCountText.fieldWidth = Std.int(Math.max(40, counterWidth));
		blockCountText.wordWrap = false;
		blockCountText.setPosition(BlockLayout.width - counterWidth - inset, gap + (buttonHeight - blockCountText.height) * 0.5);
	}

	function updatePreviewButton():Void
	{
		if (previewButton == null)
			return;

		setButtonText(previewButton, 'Preview');
		setButtonColor(previewButton, previewWanted ? COLOR_BUTTON_ACTIVE : COLOR_BUTTON);
	}

	// ============================================================================================
	// Status bar, block counter, trash, tooltip
	// ============================================================================================

	function layoutStatusBar():Void
	{
		if (statusBar == null || statusText == null)
			return;

		var h:Int = Std.int(Math.max(1, BlockLayout.statusHeight()));

		if (Std.int(statusBar.width) != Std.int(BlockLayout.width) || Std.int(statusBar.height) != h)
			statusBar.makeGraphic(Std.int(Math.max(1, BlockLayout.width)), h, COLOR_STATUS_BAR);

		statusBar.setPosition(0, BlockLayout.height - BlockLayout.statusHeight());

		statusText.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('small'), COLOR_STATUS_TEXT, LEFT);
		statusText.fieldWidth = Std.int(Math.max(60, BlockLayout.width - inset * 2));
		statusText.wordWrap = false; // the two line wrap is done by `wrapStatus()`
		statusText.setPosition(inset, BlockLayout.height - BlockLayout.statusHeight() + Math.max(2, gap * 0.5));
		renderStatus(statusMessage);
	}

	function createStatusBar():Void
	{
		statusBar = new FlxSprite().makeGraphic(1, 1, COLOR_STATUS_BAR);
		statusBar.scrollFactor.set(0, 0);
		statusBar.cameras = [camHUD];
		add(statusBar);

		statusText = new FlxText(0, 0, 100, '', BlockLayout.font('small'));
		statusText.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('small'), COLOR_STATUS_TEXT, LEFT);
		statusText.scrollFactor.set(0, 0);
		statusText.cameras = [camHUD];
		add(statusText);

		blockCountText = new FlxText(0, 0, 100, 'Blocks: 0', BlockLayout.font('small'));
		blockCountText.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('small'), COLOR_BLOCK_COUNT, RIGHT);
		blockCountText.scrollFactor.set(0, 0);
		blockCountText.cameras = [camHUD];
		add(blockCountText);
	}

	/** Sets the status line and restarts the hold timer. */
	function setStatus(message:String):Void
	{
		statusHold = STATUS_HOLD;
		statusMessage = (message == null) ? '' : message;
		renderStatus(statusMessage);
	}

	/**
	 * Draws a status message. Narrow viewports (phones in landscape, small windows) only have a
	 * one line tall status bar, so the message is wrapped into two lines there — written here
	 * instead of relying on `FlxText` wrapping, which would just overflow the bar.
	 */
	function renderStatus(message:String):Void
	{
		if (statusText == null)
			return;

		var text:String = (message == null) ? '' : message;
		var rendered:String = BlockLayout.narrow ? wrapStatus(text) : text;

		// Only on a real change: `FlxText` regenerates its field whenever the text is assigned.
		if (statusText.text != rendered)
			statusText.text = rendered;

		if (preview != null && preview.isOpen())
			preview.setStatus(text);
	}

	function wrapStatus(message:String):String
	{
		var maxWidth:Float = Math.max(80, BlockLayout.width - inset * 2 - counterWidth);
		var perLine:Int = Std.int(Math.max(16, maxWidth / (BlockLayout.font('small') * 0.56)));
		if (message.length <= perLine)
			return message;

		var cut:Int = -1;
		var last:Int = message.length;
		for (i in 0...perLine)
		{
			var index:Int = perLine - i;
			if (index <= 0 || index >= message.length)
				continue;
			if (message.charAt(index) == ' ')
			{
				cut = index;
				break;
			}
		}

		if (cut <= 0)
			cut = perLine;
		if (cut > last)
			cut = last;

		var first:String = message.substr(0, cut);
		var rest:String = message.substr(cut);
		while (rest.length > 0 && rest.charAt(0) == ' ')
			rest = rest.substr(1);

		if (rest.length > perLine * 2)
			rest = rest.substr(0, perLine * 2 - 3) + '...';

		return first + '\n' + rest;
	}

	function updateStatusText(elapsed:Float):Void
	{
		if (statusText == null)
			return;

		if (statusHold > 0)
		{
			statusHold -= elapsed;
			if (statusHold > 0)
				return;
		}

		var hint:String = contextHint();
		statusMessage = hint;
		renderStatus(hint);
	}

	function contextHint():String
	{
		if (isDragging)
			return 'Drop on the trash or over the palette to delete - snapping distance is 30px';

		if (isPanning)
			return 'Panning - release to stop';

		var marker:TimelineMarker = activeMarker();
		if (marker != null)
		{
			var eventName:String = markerEventName(marker);
			var suffix:String = (eventName.length > 0) ? ' - reacts to event "' + eventName + '"' : '';
			return 'Marker ' + markerName(marker) + ' (step ' + marker.step + ')' + suffix + ' - blocks you add belong to this marker';
		}

		return 'Global scripts - drag blocks, Space+drag to pan, E/Q to zoom, Ctrl+S to save, ESC to close';
	}

	function refreshBlockCount():Void
	{
		if (blockCountText == null)
			return;

		blockCountText.text = 'Blocks: ' + workspaceBlocks(activeWorkspaceId()).length;
	}

	/** Rounded, tinted tile graphic: a white body and a grey outline the sprite tints per category. */
	public static function buildTileBitmap(w:Int, h:Int, fill:Int, border:Int, gripColor:Int, grip:Bool):BitmapData
	{
		var width:Int = Std.int(Math.max(w, 1));
		var height:Int = Std.int(Math.max(h, 1));
		var data:BitmapData = new BitmapData(width, height, true, 0x00000000);
		var radius:Int = Std.int(FlxMath.bound(height * 0.32, 3, 12));

		fillRounded(data, 0, 0, width, height, radius, border);
		fillRounded(data, 1, 1, width - 2, height - 2, Std.int(Math.max(radius - 1, 1)), fill);

		if (grip)
		{
			var dotSize:Int = Std.int(FlxMath.bound(height * 0.11, 2, 5));
			var dotGap:Int = dotSize + Std.int(FlxMath.bound(height * 0.09, 2, 6));
			var total:Int = dotSize * 3 + (dotGap - dotSize) * 2;
			var dotX:Int = Std.int(FlxMath.bound(height * 0.42, 6, 26));
			var dotY:Int = Std.int(Math.max(0, (height - total) * 0.5));

			for (i in 0...3)
				data.fillRect(new Rectangle(dotX, dotY + i * dotGap, dotSize, dotSize), gripColor);
		}

		return data;
	}

	public static function fillRounded(data:BitmapData, x:Int, y:Int, w:Int, h:Int, radius:Int, color:Int):Void
	{
		if (w <= 0 || h <= 0)
			return;

		var r:Int = Std.int(Math.min(radius, Math.min(Math.floor(w / 2), Math.floor(h / 2))));
		if (r <= 0)
		{
			data.fillRect(new Rectangle(x, y, w, h), color);
			return;
		}

		data.fillRect(new Rectangle(x, y + r, w, h - r * 2), color);

		for (i in 0...r)
		{
			var dy:Float = r - i - 0.5;
			var inset:Int = Std.int(Math.ceil(r - Math.sqrt(Math.max(r * r - dy * dy, 0))));

			data.fillRect(new Rectangle(x + inset, y + i, Math.max(1, w - inset * 2), 1), color);
			data.fillRect(new Rectangle(x + inset, y + h - 1 - i, Math.max(1, w - inset * 2), 1), color);
		}
	}

	/** Paints a sprite with a rounded body in `color` without touching its labels. */
	public static function paintRounded(sprite:FlxSprite, w:Float, h:Float, color:Int, grip:Bool):Void
	{
		if (sprite == null)
			return;

		var iw:Int = Std.int(Math.max(1, w));
		var ih:Int = Std.int(Math.max(1, h));

		// Repainting an already matching body would allocate a fresh bitmap on every layout pass.
		if (sprite.graphic != null && Std.int(sprite.width) == iw && Std.int(sprite.height) == ih && sprite.color == color)
			return;

		var data:BitmapData = buildTileBitmap(iw, ih, COLOR_TILE_FILL, COLOR_TILE_BORDER, COLOR_TILE_GRIP, grip);
		sprite.pixels = data;
		sprite.color = color;
	}

	function layoutTrash():Void
	{
		if (trashCan == null || trashLabel == null)
			return;

		if (BlockLayout.portrait)
		{
			trashSize = Math.max(BlockLayout.touchSize() * 1.15, 46 * BlockLayout.scale);
			trashCan.setPosition(wsRect.x + wsRect.w - inset - trashSize, wsRect.y + inset);
		}
		else
		{
			trashSize = Math.min(BlockLayout.timelineHeight() - gap * 2, Math.max(BlockLayout.touchSize(), 56 * BlockLayout.scale));
			var margin:Float = BlockLayout.timelineRightMargin();
			trashCan.setPosition(BlockLayout.width - margin + (margin - trashSize) * 0.5, timelineRect.y + (timelineRect.h - trashSize) * 0.5);
		}

		trashSize = Math.max(24, trashSize);
		paintRounded(trashCan, trashSize, trashSize, COLOR_TRASH, false);
		trashCan.setPosition(trashCan.x, trashCan.y);

		trashLabel.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('tiny'), FlxColor.WHITE, CENTER);
		trashLabel.fieldWidth = Std.int(trashSize);
		trashLabel.setPosition(trashCan.x, trashCan.y + (trashSize - trashLabel.height) * 0.5);
	}

	function createTrashCan():Void
	{
		trashCan = new FlxSprite().makeGraphic(1, 1, COLOR_TRASH);
		trashCan.scrollFactor.set(0, 0);
		trashCan.cameras = [camHUD];
		add(trashCan);

		trashLabel = new FlxText(0, 0, 60, 'TRASH', BlockLayout.font('tiny'));
		trashLabel.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('tiny'), FlxColor.WHITE, CENTER);
		trashLabel.scrollFactor.set(0, 0);
		trashLabel.cameras = [camHUD];
		add(trashLabel);
	}

	function createTooltip():Void
	{
		tooltipBox = new FlxSprite().makeGraphic(1, 1, COLOR_TOOLTIP_BG);
		tooltipBox.scrollFactor.set(0, 0);
		tooltipBox.cameras = [camHUD];
		tooltipBox.visible = false;
		add(tooltipBox);

		tooltipText = new FlxText(0, 0, 100, '', BlockLayout.font('small'));
		tooltipText.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('small'), FlxColor.WHITE);
		tooltipText.scrollFactor.set(0, 0);
		tooltipText.cameras = [camHUD];
		tooltipText.visible = false;
		add(tooltipText);
	}

	function showTooltip(text:String):Void
	{
		if (tooltipBox == null || tooltipText == null)
			return;

		if (text == null || text.length == 0)
		{
			tooltipBox.visible = false;
			tooltipText.visible = false;
			tooltipMessage = '';
			return;
		}

		if (text != tooltipMessage)
		{
			tooltipMessage = text;
			tooltipText.text = text;

			var fontSize:Int = BlockLayout.font('small');
			var pad:Float = BlockLayout.spacing('normal');
			var maxWidth:Float = Math.min(BlockLayout.width * 0.5, 380 * BlockLayout.scale);
			var wanted:Float = Math.min(maxWidth, text.length * fontSize * 0.62 + pad * 2);

			tooltipBoxWidth = Math.max(80, wanted);
			tooltipBoxHeight = Math.max(24, tooltipText.height + pad * 2);
			tooltipText.setFormat(Paths.font('vcr.ttf'), fontSize, FlxColor.WHITE, LEFT);
			tooltipText.fieldWidth = Std.int(Math.max(40, tooltipBoxWidth - pad * 2));
			tooltipText.wordWrap = false;
			tooltipText.setPosition(tooltipText.x, tooltipText.y);

			tooltipBox.makeGraphic(Std.int(tooltipBoxWidth), Std.int(tooltipBoxHeight), COLOR_TOOLTIP_BG);
		}

		tooltipBox.visible = true;
		tooltipText.visible = true;

		var x:Float = getPointerScreenX() + 15;
		var y:Float = getPointerScreenY() + 15;
		if (x + tooltipBoxWidth + 8 > BlockLayout.width)
			x = Math.max(inset, BlockLayout.width - tooltipBoxWidth - 8);
		if (y + tooltipBoxHeight + 8 > BlockLayout.height)
			y = Math.max(inset, BlockLayout.height - tooltipBoxHeight - 8);

		tooltipBox.setPosition(x, y);
		tooltipText.setPosition(x + BlockLayout.spacing('normal'), y + BlockLayout.spacing('normal') * 0.5);
	}

	// ============================================================================================
	// Palette: chrome, category rail, chips, search and the block list
	// ============================================================================================

	/** Resizes a sprite to a rect when needed and moves it there. */
	static function fitSprite(sprite:FlxSprite, x:Float, y:Float, w:Float, h:Float, color:Int):Void
	{
		if (sprite == null)
			return;

		var iw:Int = Std.int(Math.max(1, w));
		var ih:Int = Std.int(Math.max(1, h));
		if (Std.int(sprite.width) != iw || Std.int(sprite.height) != ih)
			sprite.makeGraphic(iw, ih, color);

		sprite.setPosition(x, y);
	}

	function ensureStatusBar():Void
	{
		if (statusBar == null)
			createStatusBar();
	}

	function ensureTrash():Void
	{
		if (trashCan == null)
			createTrashCan();
	}

	function ensureTooltip():Void
	{
		if (tooltipBox == null)
			createTooltip();
	}

	function ensureMarkerButton():Void
	{
		if (markerButton != null)
			return;

		markerButton = makeButton('+ marker', function()
		{
			addMarkerAtCurrentStep();
		}, COLOR_BUTTON_ACTIVE);
	}

	function ensurePaletteChrome():Void
	{
		if (paletteBg != null)
			return;

		paletteBg = new FlxSprite().makeGraphic(1, 1, COLOR_SIDEBAR_BG);
		paletteBg.scrollFactor.set(0, 0);
		paletteBg.cameras = [camPaletteBack];
		add(paletteBg);

		paletteStripBg = new FlxSprite().makeGraphic(1, 1, COLOR_SIDEBAR_STRIP);
		paletteStripBg.scrollFactor.set(0, 0);
		paletteStripBg.cameras = [camPaletteBack];
		add(paletteStripBg);

		paletteSeparator = new FlxSprite().makeGraphic(1, 1, COLOR_SEPARATOR);
		paletteSeparator.scrollFactor.set(0, 0);
		paletteSeparator.cameras = [camPaletteBack];
		add(paletteSeparator);

		scrollTrack = new FlxSprite().makeGraphic(1, 1, COLOR_SCROLL_TRACK);
		scrollTrack.scrollFactor.set(0, 0);
		scrollTrack.cameras = [camPaletteBack];
		add(scrollTrack);

		scrollThumb = new FlxSprite().makeGraphic(1, 1, COLOR_SCROLL_THUMB);
		scrollThumb.scrollFactor.set(0, 0);
		scrollThumb.cameras = [camPaletteBack];
		add(scrollThumb);

		handlePill = new FlxSprite().makeGraphic(1, 1, COLOR_HANDLE);
		handlePill.scrollFactor.set(0, 0);
		handlePill.cameras = [camHUD];
		add(handlePill);

		collapseButton = makeButton('v', togglePaletteCollapsed, COLOR_BUTTON);
	}

	function layoutPaletteChrome():Void
	{
		if (paletteBg == null)
			return;

		if (BlockLayout.sidebarVisible())
		{
			var stripW:Float = paletteStrip.w;
			fitSprite(paletteStripBg, 0, paletteBand.y, stripW, paletteBand.h, COLOR_SIDEBAR_STRIP);
			paletteStripBg.visible = true;

			fitSprite(paletteBg, stripW, paletteBand.y, Math.max(1, paletteBand.w - stripW), paletteBand.h, COLOR_SIDEBAR_BG);
			paletteBg.visible = true;

			// Vertical separator between the palette column and the canvas.
			fitSprite(paletteSeparator, paletteBand.w - 1, paletteBand.y, 1, paletteBand.h, COLOR_SEPARATOR);
		}
		else
		{
			paletteStripBg.visible = false;
			fitSprite(paletteBg, paletteBand.x, paletteBand.y, paletteBand.w, paletteBand.h, COLOR_SHEET_BG);
			paletteBg.visible = true;

			// Horizontal separator between the canvas and the sheet.
			fitSprite(paletteSeparator, paletteBand.x, paletteBand.y, paletteBand.w, 1, COLOR_SEPARATOR);
		}

		layoutSheetHandle();

		if (collapseButton != null)
		{
			if (BlockLayout.portrait)
			{
				setButtonText(collapseButton, paletteCollapsed ? 'v' : '^');
				fitButton(collapseButton, chevronRect.w, chevronRect.h);
				centerButtonLabelIn(collapseButton, chevronRect.h);
				collapseButton.setPosition(chevronRect.x, chevronRect.y);
				collapseButton.visible = true;
			}
			else
			{
				collapseButton.visible = false;
			}
		}

		ensureSearchField();
		layoutSearchField();
	}

	/** The grab pill of the bottom sheet; dragging it collapses or expands the sheet. */
	function layoutSheetHandle():Void
	{
		if (handlePill == null)
			return;

		if (!BlockLayout.portrait)
		{
			handlePill.visible = false;
			return;
		}

		var pillW:Float = Math.min(72 * BlockLayout.scale, paletteBand.w * 0.35);
		var pillH:Float = Math.max(4, 6 * BlockLayout.scale);

		handlePill.visible = true;
		fitSprite(handlePill, paletteBand.x + (paletteBand.w - pillW) * 0.5, handleRect.y + (handleRect.h - pillH) * 0.5, pillW, pillH, COLOR_HANDLE);
	}

	function fitButton(button:FlxButton, w:Float, h:Float):Void
	{
		if (button == null)
			return;

		var iw:Int = Std.int(Math.max(1, w));
		var ih:Int = Std.int(Math.max(1, h));
		if (Std.int(button.width) != iw || Std.int(button.height) != ih)
			button.makeGraphic(iw, ih, buttonColor(button));

		styleButtonLabel(button);
	}

	function centerButtonLabelIn(button:FlxButton, height:Float):Void
	{
		if (button == null || button.label == null || button.labelOffsets == null)
			return;

		var offset:Float = Math.max(0, (height - button.label.height) * 0.5);
		for (point in button.labelOffsets)
		{
			if (point != null)
				point.set(point.x, offset);
		}
	}

	// --- Search field ---------------------------------------------------------------------------

	function ensureSearchField():Void
	{
		var wantW:Float = Math.max(80, searchRect.w);
		var wantH:Float = Math.max(28, searchHeight);

		if (searchField != null && searchFieldWidth == wantW && searchFieldHeight == wantH)
			return;

		destroySearchField();

		searchField = new InputField(searchRect.x, searchRect.y, wantW, wantH, '', ParamType.STRING, 'Search blocks');
		searchField.value = searchText;
		searchFieldWidth = wantW;
		searchFieldHeight = wantH;

		searchField.bg.cameras = [camHUD];
		searchField.text.cameras = [camHUD];
		searchField.placeholderText.cameras = [camHUD];
		add(searchField.bg);
		add(searchField.text);
		add(searchField.placeholderText);

		styleSearchField();
	}

	function destroySearchField():Void
	{
		if (searchField == null)
			return;

		if (editingField == searchField)
		{
			editingField = null;
			Block.externalEditorActive = false;
		}

		remove(searchField.bg, true);
		remove(searchField.text, true);
		remove(searchField.placeholderText, true);
		FlxDestroyUtil.destroy(searchField.bg);
		FlxDestroyUtil.destroy(searchField.text);
		FlxDestroyUtil.destroy(searchField.placeholderText);

		searchField = null;
		searchFieldWidth = 0;
		searchFieldHeight = 0;
	}

	/** `InputField` centres its text; the search field reads better left aligned. */
	function styleSearchField():Void
	{
		if (searchField == null)
			return;

		searchField.text.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('body'), COLOR_STATUS_TEXT, LEFT);
		searchField.placeholderText.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('body'), COLOR_BLOCK_COUNT, LEFT);
	}

	function layoutSearchField():Void
	{
		if (searchField == null)
			return;

		searchField.width = Math.max(80, searchRect.w);
		searchField.updatePosition(searchRect.x, searchRect.y);
		styleSearchField();

		var shown:Bool = searchRect.h > 0;
		if (shown)
		{
			searchField.update(0);
		}
		else
		{
			searchField.unfocus();
			searchField.bg.visible = false;
			searchField.text.visible = false;
			searchField.placeholderText.visible = false;
		}
	}

	function updateSearchField(elapsed:Float):Void
	{
		if (searchField == null || searchRect.h <= 0)
			return;

		searchField.update(elapsed);

		if (searchField.text.alignment != FlxTextAlign.LEFT)
			styleSearchField();

		var current:String = (searchField.value == null) ? '' : Std.string(searchField.value);
		if (current != searchText)
		{
			searchText = current;
			refreshPaletteVisibility();
		}
	}

	// --- Content: sections, tiles, rail and chips ------------------------------------------------

	function rebuildPaletteContent():Void
	{
		var key:String = Std.string(BlockLayout.width) + 'x' + Std.string(BlockLayout.height) + 'x' + Std.string(BlockLayout.scale)
			+ (BlockLayout.portrait ? 'p' : 'l') + (BlockLayout.compact ? 'c' : 'n');

		if (paletteBuildKey == key && paletteSections.length > 0)
		{
			if (BlockLayout.portrait && paletteCollapsed)
			{
				// The sheet is folded away: keep the content laid out as it was, so unfolding it
				// restores the very same scroll position.
				refreshPaletteVisibility();
				applyPaletteScroll();
				return;
			}

			layoutPaletteContent();
			layoutRail();
			layoutChips();
			refreshPaletteVisibility();
			applyPaletteScroll();
			return;
		}

		paletteBuildKey = key;

		destroyPaletteContent();
		BlockLibrary.ensureLoaded();

		var categories:Array<BlockCategory> = BlockLibrary.categories;

		buildRail(categories);
		buildChips(categories);
		buildSections(categories);

		paletteScroll = 0;
		chipsScroll = 0;
		layoutPaletteContent();
		layoutRail();
		layoutChips();
		refreshPaletteVisibility();
		applyPaletteScroll();
	}

	/**
	 * The context menu's "reload blocks": picks up block configs a mod added (or fixed) while the
	 * song runs. The palette caches itself per viewport, so the key is dropped to force a rebuild
	 * from the reloaded library, and the loader's errors are reported in the status bar.
	 */
	function reloadBlockLibrary():Void
	{
		BlockLibrary.reload();

		paletteBuildKey = '';
		rebuildPaletteContent();

		var blocks:Int = BlockLibrary.allBlocks().length;
		var errors:Array<String> = BlockConfigLoader.lastErrors();

		if (errors != null && errors.length > 0)
			setStatus('Block library reloaded - ' + blocks + ' blocks, ' + errors.length + ' config error(s): ' + errors[0]);
		else
			setStatus('Block library reloaded - ' + blocks + ' blocks');

		playSound('confirmMenu');
	}

	function destroyPaletteContent():Void
	{
		for (section in paletteSections)
		{
			if (section == null)
				continue;

			for (tile in section.tiles)
			{
				if (tile == null)
					continue;

				remove(tile.bg, true);
				remove(tile.label, true);
				tile.destroy();
			}

			remove(section.header, true);
			remove(section.line, true);
			section.destroy();
		}
		paletteSections = [];

		for (button in railButtons)
			destroyCategoryButton(button);
		railButtons = [];

		for (chip in paletteChips)
			destroyCategoryButton(chip);
		paletteChips = [];

		activeCategory = '';
		paletteContentHeight = 0;
		chipsContentWidth = 0;
	}

	function destroyCategoryButton(button:CategoryButton):Void
	{
		if (button == null)
			return;

		remove(button.bg, true);
		remove(button.label, true);
		button.destroy();
	}

	function addCategoryButton(button:CategoryButton):Void
	{
		if (button == null)
			return;

		add(button.bg);
		add(button.label);
	}

	/** Landscape only: the narrow rail of category buttons down the left of the palette column. */
	function buildRail(categories:Array<BlockCategory>):Void
	{
		if (!BlockLayout.sidebarVisible() || categories == null)
			return;

		var count:Int = 0;
		for (category in categories)
		{
			if (category != null)
				count++;
		}
		if (count == 0)
			return;

		var size:Float = railSizeFor(count);
		railButtonSize = size;

		for (category in categories)
		{
			if (category == null)
				continue;

			// The rail is static chrome, so it lives on the palette background camera (which never
			// scrolls) instead of the scrolling block list.
			var button:CategoryButton = new CategoryButton(category, 0, 0, size, size, camPaletteBack, category.icon, Std.int(size * 0.55));
			addCategoryButton(button);
			button.setActive(false);
			railButtons.push(button);
		}
	}

	function railSizeFor(count:Int):Float
	{
		var stripW:Float = Math.max(24, BlockLayout.categoryStripWidth());
		// Keep the rail (and its rounded outlines) clear of the screen edge.
		var railW:Float = Math.max(24, stripW - inset * 2);
		var available:Float = Math.max(40, paletteStrip.h - inset * 2);
		var slot:Float = (available - BlockLayout.spacing('normal') * (count - 1)) / Math.max(1, count);
		var wanted:Float = Math.min(slot, 56 * BlockLayout.scale);

		return Math.max(20, Math.min(railW, wanted));
	}

	/** Portrait only: the horizontally scrollable category chips of the bottom sheet. */
	function buildChips(categories:Array<BlockCategory>):Void
	{
		if (BlockLayout.sidebarVisible() || categories == null)
			return;

		var fontSize:Int = BlockLayout.font('small');

		for (category in categories)
		{
			if (category == null)
				continue;

			var text:String = (category.icon == null || category.icon.length == 0) ? category.name : (category.icon + ' ' + category.name);
			var width:Float = Math.max(chipsHeight, BlockLayout.buttonWidth(text) + gap * 2);

			var chip:CategoryButton = new CategoryButton(category, 0, 0, width, chipsHeight, camHUD, text, fontSize);
			addCategoryButton(chip);
			chip.setActive(false);
			paletteChips.push(chip);
		}
	}

	function buildSections(categories:Array<BlockCategory>):Void
	{
		if (categories == null)
			return;

		var headerSize:Int = BlockLayout.font('small');
		var compact:Bool = BlockLayout.compact;
		var listW:Float = Math.max(40, paletteList.w);
		var rowH:Float = BlockLayout.paletteRowHeight();

		for (category in categories)
		{
			if (category == null || category.blocks == null || category.blocks.length == 0)
				continue;

			var section:PaletteSection = new PaletteSection(category, camPalette, headerSize);
			section.header.text = category.name;
			section.header.fieldWidth = Std.int(listW);
			add(section.header);
			add(section.line);

			for (data in category.blocks)
			{
				if (data == null)
					continue;

				var tile:PaletteTile = new PaletteTile(data, category, listW, rowH, camPalette, compact);
				add(tile.bg);
				add(tile.label);
				section.tiles.push(tile);
			}

			paletteSections.push(section);
		}
	}

	/**
	 * Lays the sections and tiles out in list-local coordinates: `0` is the top left corner of the
	 * list rect, which is also the corner `camPalette` is anchored to.
	 */
	function layoutPaletteContent():Void
	{
		var listW:Float = Math.max(40, paletteList.w);
		var rowH:Float = BlockLayout.paletteRowHeight();
		var loose:Float = BlockLayout.spacing('loose');
		var y:Float = 0;
		var headerSize:Int = BlockLayout.font('small');
		var first:Bool = true;

		for (section in paletteSections)
		{
			if (section == null || section.tiles.length == 0)
				continue;

			// The rect of the list already holds the gap to the search field / chip row above, so the
			// first header starts flush with it; the sections after it keep the roomy spacing.
			if (!first)
				y += loose;
			first = false;

			section.contentTop = y;
			section.headerY = y;
			section.headerHeight = Math.round(headerSize * 1.25);
			section.header.setFormat(Paths.font('vcr.ttf'), headerSize, section.category.color, LEFT);
			section.header.fieldWidth = Std.int(listW);
			section.header.setPosition(0, y);

			fitSprite(section.line, 0, y + section.headerHeight, listW, 1, section.category.color);
			section.line.alpha = 0.55;

			y += section.headerHeight + gap;

			for (tile in section.tiles)
			{
				tile.x = 0;
				tile.y = y;
				tile.place(0, y, listW, rowH);
				y += rowH + gap;
			}

			section.contentBottom = y;
			y += BlockLayout.spacing('normal');
		}

		paletteContentHeight = Math.max(0, y - gap);
		if (paletteList.h > 0)
			paletteScroll = FlxMath.bound(paletteScroll, 0, Math.max(0, paletteContentHeight - paletteList.h));
	}

	function layoutRail():Void
	{
		if (railButtons.length == 0)
			return;

		var size:Float = railButtonSize;
		var gapY:Float = BlockLayout.spacing('normal');
		var total:Float = size * railButtons.length + gapY * (railButtons.length - 1);

		// The chips never touch the screen edge: the rail is inset, and they are centred in whatever
		// width is left between the two insets.
		var left:Float = paletteStrip.x + inset;
		var railW:Float = Math.max(size, paletteStrip.w - inset * 2);
		var y:Float = paletteStrip.y + Math.max(inset, (paletteStrip.h - total) * 0.5);
		var x:Float = left + (railW - size) * 0.5;

		for (button in railButtons)
		{
			button.moveTo(x, y);
			y += size + gapY;
		}
	}

	function layoutChips():Void
	{
		if (paletteChips.length == 0)
		{
			chipsContentWidth = 0;
			return;
		}

		var x:Float = chipsRect.x;
		var y:Float = chipsRect.y + (chipsRect.h - chipsHeight) * 0.5;

		for (chip in paletteChips)
		{
			chip.moveTo(x, y);
			x += chip.width + gap;
		}

		chipsContentWidth = Math.max(0, x - chipsRect.x - gap);
		chipsScroll = FlxMath.bound(chipsScroll, 0, Math.max(0, chipsContentWidth - chipsRect.w));
		applyChipsScroll();
	}

	function applyChipsScroll():Void
	{
		for (chip in paletteChips)
			chip.setOffset(-chipsScroll);
	}

	/** Content y -> screen y: the palette camera scrolls the content inside the list rect. */
	function paletteScreenY(contentY:Float):Float
	{
		return paletteList.y + contentY - paletteScroll;
	}

	/** Hides tiles and headers that scroll out of the list, and applies the search filter. */
	function refreshPaletteVisibility():Void
	{
		var filter:String = (searchText == null) ? '' : searchText.toLowerCase();
		var list:Rect = paletteList;
		var showList:Bool = (list.h > 0) && !(BlockLayout.portrait && paletteCollapsed);

		for (section in paletteSections)
		{
			if (section == null)
				continue;

			var anyMatch:Bool = false;

			for (tile in section.tiles)
			{
				if (tile == null)
					continue;

				var matches:Bool = (filter.length == 0) || tileMatches(tile, filter);
				if (matches)
					anyMatch = true;
				else
					tile.setVisible(false);

				if (!matches)
					continue;

				var top:Float = paletteScreenY(tile.y);
				var inside:Bool = showList && (top + tile.h > list.y) && (top < list.y + list.h);
				tile.setVisible(inside);
			}

			var headerTop:Float = paletteScreenY(section.headerY);
			var headerInside:Bool = showList && (headerTop + section.headerHeight > list.y) && (headerTop < list.y + list.h);
			section.setHeaderVisible(anyMatch && headerInside);
		}

		if (filter.length > 0)
		{
			for (button in railButtons)
			{
				if (button != null)
					button.setDimmed(!categoryHasMatch(button.category, filter));
			}
		}
		else
		{
			for (button in railButtons)
			{
				if (button != null)
					button.setDimmed(false);
			}
		}
	}

	/** Matches a tile against the search text: label, block type, category and description. */
	function tileMatches(tile:PaletteTile, filter:String):Bool
	{
		if (tile == null || tile.data == null)
			return false;

		if (tile.data.label != null && tile.data.label.toLowerCase().indexOf(filter) >= 0)
			return true;
		if (tile.data.type != null && tile.data.type.toLowerCase().indexOf(filter) >= 0)
			return true;
		if (tile.data.category != null && tile.data.category.toLowerCase().indexOf(filter) >= 0)
			return true;
		if (tile.data.description != null && tile.data.description.toLowerCase().indexOf(filter) >= 0)
			return true;

		return false;
	}

	function categoryHasMatch(category:BlockCategory, filter:String):Bool
	{
		if (category == null || category.blocks == null)
			return false;

		if (category.name != null && category.name.toLowerCase().indexOf(filter) >= 0)
			return true;

		for (data in category.blocks)
		{
			if (data == null)
				continue;
			if (data.label != null && data.label.toLowerCase().indexOf(filter) >= 0)
				return true;
			if (data.type != null && data.type.toLowerCase().indexOf(filter) >= 0)
				return true;
		}

		return false;
	}

	function findSection(categoryName:String):PaletteSection
	{
		for (section in paletteSections)
		{
			if (section != null && section.category != null && section.category.name == categoryName)
				return section;
		}

		return null;
	}

	function setActiveCategory(categoryName:String):Void
	{
		if (activeCategory == categoryName)
			return;

		activeCategory = categoryName;

		for (button in railButtons)
		{
			if (button != null && button.category != null)
				button.setActive(button.category.name == categoryName);
		}

		for (chip in paletteChips)
		{
			if (chip != null && chip.category != null)
				chip.setActive(chip.category.name == categoryName);
		}
	}

	/** Highlights the category whose section sits at the top of the list. */
	function updateActiveCategoryFromScroll():Void
	{
		var probe:Float = paletteScroll + gap;
		var found:String = '';

		for (section in paletteSections)
		{
			if (section == null || section.tiles.length == 0)
				continue;
			if (probe >= section.contentTop && probe < section.contentBottom + BlockLayout.spacing('normal'))
			{
				found = section.category.name;
				break;
			}
		}

		if (found.length > 0)
			setActiveCategory(found);
	}

	function scrollToCategory(categoryName:String):Void
	{
		var section:PaletteSection = findSection(categoryName);
		if (section == null)
			return;

		var maxScroll:Float = Math.max(0, paletteContentHeight - paletteList.h);
		var target:Float = FlxMath.bound(section.contentTop - gap * 2, 0, maxScroll);

		setActiveCategory(categoryName);
		tweenPaletteScroll(target);

		setStatus('Jumped to ' + categoryName);
		playSound('scrollMenu');
	}

	/** Smoothly scrolls the palette list to a content offset. */
	function tweenPaletteScroll(target:Float):Void
	{
		if (paletteScrollTween != null)
		{
			paletteScrollTween.cancel();
			paletteScrollTween = null;
		}

		if (Math.abs(target - paletteScroll) < 1)
		{
			setPaletteScroll(target);
			return;
		}

		paletteScrollProxy = {value: paletteScroll};
		paletteScrollTween = FlxTween.tween(paletteScrollProxy, {value: target}, 0.35, {
			ease: FlxEase.quartOut,
			onUpdate: function(tween:FlxTween):Void
			{
				setPaletteScroll(paletteScrollProxy.value);
			},
			onComplete: function(tween:FlxTween):Void
			{
				paletteScrollTween = null;
			}
		});
	}

	function setPaletteScroll(value:Float):Void
	{
		var maxScroll:Float = Math.max(0, paletteContentHeight - paletteList.h);
		var clamped:Float = FlxMath.bound(value, 0, maxScroll);
		if (clamped == paletteScroll)
		{
			applyPaletteScroll();
			return;
		}

		paletteScroll = clamped;
		applyPaletteScroll();
		refreshPaletteVisibility();
		updateActiveCategoryFromScroll();
	}

	function applyPaletteScroll():Void
	{
		if (camPalette != null)
			camPalette.scroll.y = paletteScroll;

		updateScrollThumb();
	}

	function updateScrollThumb():Void
	{
		if (scrollTrack == null || scrollThumb == null)
			return;

		var maxScroll:Float = Math.max(0, paletteContentHeight - paletteList.h);
		var trackH:Float = scrollbarRect.h;

		if (maxScroll <= 0 || trackH <= 0 || paletteList.h <= 0)
		{
			scrollTrack.visible = false;
			scrollThumb.visible = false;
			return;
		}

		var ratio:Float = Math.min(1, paletteList.h / Math.max(1, paletteContentHeight));
		var thumbH:Float = Math.max(24, trackH * ratio);
		var thumbY:Float = scrollbarRect.y + (paletteScroll / maxScroll) * Math.max(0, trackH - thumbH);

		scrollTrack.visible = true;
		scrollThumb.visible = true;
		fitSprite(scrollTrack, scrollbarRect.x, scrollbarRect.y, scrollbarRect.w, trackH, COLOR_SCROLL_TRACK);
		fitSprite(scrollThumb, scrollbarRect.x, thumbY, scrollbarRect.w, thumbH, COLOR_SCROLL_THUMB);
	}

	function togglePaletteCollapsed():Void
	{
		setPaletteCollapsed(!paletteCollapsed);
	}

	/** Collapses the bottom sheet down to its chip row so the workspace can grow. */
	function setPaletteCollapsed(collapsed:Bool):Void
	{
		if (!BlockLayout.portrait || paletteCollapsed == collapsed)
			return;

		paletteCollapsed = collapsed;
		if (collapsed)
			closeFieldEditor();

		playSound('scrollMenu');
		setStatus(collapsed ? 'Palette folded away - tap the chevron to bring it back' : 'Palette open');
		applyLayout();
		refreshPaletteVisibility();
	}

	// --- Palette scrolling ----------------------------------------------------------------------

	function updatePaletteScroll(elapsed:Float):Void
	{
		if (camPalette == null)
			return;

		var blocked:Bool = pointerBlocked();
		var list:Rect = paletteList;
		var maxScroll:Float = Math.max(0, paletteContentHeight - list.h);

		if (list.h <= 0)
		{
			updateScrollThumb();
			return;
		}

		var px:Float = getPointerScreenX();
		var py:Float = getPointerScreenY();
		var before:Float = paletteScroll;

		if (!blocked && !isDragging && tilePress == null && railPress == null && chipPress == null && !chipsDragging && !sheetDragging && !isDraggingScroll
			&& !isPanning)
		{
			var overList:Bool = pointInRect(px, py, list);
			var overPalette:Bool = isPointerOverPalette();

			if (overList)
			{
				var touch:FlxTouch = getPrimaryTouch();

				if (touch != null)
				{
					if (touch.justPressed)
						paletteDragLastY = py;
					else if (touch.pressed)
					{
						paletteScroll += paletteDragLastY - py;
						paletteDragLastY = py;
					}
				}
				else if (FlxG.mouse.pressed && !isPointerJustPressed())
				{
					// Dragging the list with the mouse works too (touch-screen laptops).
					if (!mouseScrollActive)
					{
						mouseScrollActive = true;
						paletteDragLastY = py;
					}
					else
					{
						paletteScroll += paletteDragLastY - py;
						paletteDragLastY = py;
					}
				}
			}

			if (FlxG.mouse.wheel != 0)
			{
				if (overPalette)
					paletteScroll -= FlxG.mouse.wheel * 40 * BlockLayout.scale;
				else if (!isPointerOverTimeline())
				{
					if (FlxG.keys.pressed.CONTROL)
					{
						zoomLevel += FlxG.mouse.wheel * 0.1;
						zoomLevel = FlxMath.bound(zoomLevel, MIN_ZOOM, MAX_ZOOM);
						camEditor.zoom = zoomLevel;
						setStatus('Zoom: ' + Math.round(zoomLevel * 100) + '%');
					}
					else
					{
						camEditor.scroll.y -= (FlxG.mouse.wheel * 40) / zoomLevel;
					}
				}
			}
		}

		if (!isPointerPressed())
			mouseScrollActive = false;

		if (paletteScroll != before)
		{
			paletteScroll = FlxMath.bound(paletteScroll, 0, maxScroll);
			applyPaletteScroll();
			refreshPaletteVisibility();
			updateActiveCategoryFromScroll();
		}
		else
		{
			// Also re-asserts the camera scroll, so the content cannot stay offset if anything else
			// ever moves that camera.
			applyPaletteScroll();
		}
	}

	// --- Palette pointer handling ---------------------------------------------------------------

	function handlePalettePress(justPressed:Bool, justReleased:Bool, pressed:Bool, px:Float, py:Float):Bool
	{
		var inside:Bool = pointInRect(px, py, paletteBand);
		var busy:Bool = (tilePress != null || railPress != null || chipPress != null || chipsDragging || sheetDragging || isDraggingScroll);

		if (justReleased)
		{
			finishPalettePress(px, py);
			return busy || inside;
		}

		if (justPressed && inside)
		{
			pressConsumed = true;

			if (BlockLayout.portrait && pointInRect(px, py, chevronRect))
			{
				togglePaletteCollapsed();
				return true;
			}

			if (BlockLayout.portrait && pointInRect(px, py, handleRect))
			{
				sheetDragging = true;
				sheetDragMoved = false;
				sheetDragStartY = py;
				return true;
			}

			if (searchField != null && pointInRect(px, py, searchRect))
			{
				// The `InputField` owns the tap: it goes through `Block.requestTextEdit` into
				// `beginFieldEdit()`, which is where the soft/virtual keyboard opens.
				return true;
			}

			if (chipsRect.h > 0 && pointInRect(px, py, chipsRect))
			{
				chipPress = chipAt(px, py);
				chipsDragging = false;
				chipsDragStartX = px;
				chipsScrollStart = chipsScroll;
				return true;
			}

			if (isOverScrollbar(px, py))
			{
				isDraggingScroll = true;
				scrollDragOffset = py - scrollThumb.y;
				return true;
			}

			railPress = railButtonAt(px, py);
			if (railPress != null)
				return true;

			tilePress = tileAt(px, py);
			if (tilePress != null)
			{
				tileDragStarted = false;
				tilePressX = px;
				tilePressY = py;
				return true;
			}

			return true; // empty palette space still belongs to the palette
		}

		if (!pressed)
			return busy || inside;

		if (sheetDragging)
		{
			var travel:Float = py - sheetDragStartY;
			var threshold:Float = BlockLayout.touchSize() * 0.5;
			if (Math.abs(travel) > threshold)
			{
				sheetDragMoved = true;
				setPaletteCollapsed(travel < 0);
				sheetDragStartY = py;
			}
			return true;
		}

		if (tilePress != null && !isDragging && !tileDragStarted)
		{
			if (Math.abs(px - tilePressX) + Math.abs(py - tilePressY) > DRAG_SLOP)
				startPaletteDrag(tilePress, px, py);
			return true;
		}

		if (chipPress != null || chipsDragging)
		{
			if (!chipsDragging && Math.abs(px - chipsDragStartX) > DRAG_SLOP)
				chipsDragging = true;

			if (chipsDragging)
			{
				var maxScroll:Float = Math.max(0, chipsContentWidth - chipsRect.w);
				chipsScroll = FlxMath.bound(chipsScrollStart - (px - chipsDragStartX), 0, maxScroll);
				applyChipsScroll();
			}

			return true;
		}

		if (isDraggingScroll)
		{
			var trackH:Float = scrollbarRect.h;
			var travel:Float = trackH - scrollThumb.height;
			var ratio:Float = (travel <= 0) ? 0 : (py - scrollDragOffset - scrollbarRect.y) / travel;
			setPaletteScroll(FlxMath.bound(ratio, 0, 1) * Math.max(0, paletteContentHeight - paletteList.h));
			return true;
		}

		return busy || inside;
	}

	function finishPalettePress(px:Float, py:Float):Void
	{
		if (tilePress != null)
		{
			var tile:PaletteTile = tilePress;
			tilePress = null;
			if (!tileDragStarted)
				spawnBlockFromTile(tile);
		}

		if (railPress != null)
		{
			var rail:CategoryButton = railPress;
			railPress = null;
			if (pointInRect(px, py, rail.rect))
				scrollToCategory(rail.category.name);
		}

		if (chipPress != null)
		{
			var chip:CategoryButton = chipPress;
			chipPress = null;
			if (!chipsDragging && pointInRect(px, py, chip.rect))
				scrollToCategory(chip.category.name);
		}

		if (sheetDragging)
		{
			var moved:Bool = sheetDragMoved;
			sheetDragging = false;
			sheetDragMoved = false;
			if (!moved)
				togglePaletteCollapsed();
		}

		chipsDragging = false;
		isDraggingScroll = false;
		tileDragStarted = false;
	}

	function tileScreenRect(tile:PaletteTile):Rect
	{
		return {
			x: paletteList.x + tile.x,
			y: paletteScreenY(tile.y),
			w: tile.w,
			h: tile.h
		};
	}

	function tileAt(px:Float, py:Float):PaletteTile
	{
		for (section in paletteSections)
		{
			if (section == null)
				continue;

			for (tile in section.tiles)
			{
				if (tile == null || !tile.isShown())
					continue;
				if (pointInRect(px, py, tileScreenRect(tile)))
					return tile;
			}
		}

		return null;
	}

	function railButtonAt(px:Float, py:Float):CategoryButton
	{
		for (button in railButtons)
		{
			if (button != null && pointInRect(px, py, button.rect))
				return button;
		}

		return null;
	}

	function chipAt(px:Float, py:Float):CategoryButton
	{
		for (chip in paletteChips)
		{
			if (chip != null && pointInRect(px, py, chip.rect))
				return chip;
		}

		return null;
	}

	function isOverScrollbar(px:Float, py:Float):Bool
	{
		if (scrollTrack == null || !scrollTrack.visible)
			return false;

		return pointInRect(px, py, {
			x: scrollbarRect.x,
			y: scrollbarRect.y,
			w: scrollbarRect.w,
			h: scrollbarRect.h
		});
	}

	/** A tap on a tile drops the block into the middle of the visible workspace. */
	function spawnBlockFromTile(tile:PaletteTile):Void
	{
		if (tile == null || tile.data == null)
			return;

		addBlock(tile.data);
	}

	/** Dragging a tile creates the real block under the pointer and hands over to the block drag. */
	function startPaletteDrag(tile:PaletteTile, px:Float, py:Float):Void
	{
		tileDragStarted = true;
		tilePress = null;

		if (tile == null || tile.data == null || blockContainer == null)
			return;

		var block:Block = createBlockAt(tile.data, px, py);
		if (block == null)
			return;

		FlxTween.cancelTweensOf(block.scale);
		var z:Float = (camEditor != null) ? camEditor.zoom : 1;
		block.scale.set(z, z);
		block.alpha = 1;

		startDrag(block, px, py);
		setStatus('Dragging ' + tile.data.label + ' - drop it on the canvas');
	}

	// ============================================================================================
	// Timeline and markers
	// ============================================================================================

	/**
	 * Creates or re-creates the timeline at the current rect. `BlockTimeline` has no resize API, so
	 * a viewport change rebuilds it and re-adds the markers it carried.
	 */
	function placeTimeline():Void
	{
		if (camHUD == null)
			return;

		if (timeline != null && !rectChanged(timelinePlaced, timelineRect))
			return;

		var markers:Array<TimelineMarker> = [];
		var selected:String = '';

		if (timeline != null)
		{
			markers = timeline.markers.copy();
			selected = timeline.selectedId;
			remove(timeline, true);
			FlxDestroyUtil.destroy(timeline);
			timeline = null;
		}

		songInfoReady = false;
		mappedSong = null;

		timeline = new BlockTimeline(timelineRect.x, timelineRect.y, timelineRect.w, timelineRect.h, camHUD);
		timeline.onSeek = onTimelineSeek;
		timeline.onMarkerSelected = onMarkerSelected;
		timeline.onMarkerMoved = onMarkerMoved;
		timeline.onMarkerRemove = onMarkerRemove;
		add(timeline);

		for (marker in markers)
		{
			if (marker != null)
				timeline.addMarker(marker);
		}

		if (selected != null && selected.length > 0)
			timeline.selectMarker(selected);

		timelinePlaced = {
			x: timelineRect.x,
			y: timelineRect.y,
			w: timelineRect.w,
			h: timelineRect.h
		};
		refreshTimelineSongInfo();
	}

	function layoutMarkerButton():Void
	{
		if (markerButton == null)
			return;

		var w:Float = Math.max(BlockLayout.touchSize(), BlockLayout.buttonWidth('+ marker'));

		if (BlockLayout.portrait)
		{
			var size:Float = Math.max(BlockLayout.touchSize() * 1.15, 46 * BlockLayout.scale);
			fitButton(markerButton, w, size);
			centerButtonLabelIn(markerButton, size);
			markerButton.setPosition(wsRect.x + wsRect.w - inset - trashSize - gap - w, wsRect.y + inset + (trashSize - size) * 0.5);
		}
		else
		{
			fitButton(markerButton, w, buttonHeight);
			centerButtonLabelIn(markerButton, buttonHeight);
			markerButton.setPosition(BlockLayout.width - inset - w, timelineRect.y - buttonHeight - gap);
		}

		markerButton.visible = true;
	}

	function refreshTimelineSongInfo():Void
	{
		if (timeline == null)
			return;

		var length:Float = BlockScriptRuntime.songLength();
		timeline.setSongInfo(length, Conductor.bpm, Conductor.stepCrochet, Conductor.crochet);

		if (PlayState.instance != null && PlayState.SONG != null && PlayState.SONG.notes != null)
		{
			// Fills Conductor.bpmChangeMap, which is what the strip follows. The map is re-derived only
			// once per song; the trace inside `mapBPMChanges()` is noisy and the call is not cheap.
			if (mappedSong != PlayState.SONG)
			{
				mappedSong = PlayState.SONG;
				Conductor.mapBPMChanges(PlayState.SONG);
			}

			var changes:Array<Dynamic> = [];
			if (Conductor.bpmChangeMap != null)
			{
				for (change in Conductor.bpmChangeMap)
					changes.push(change);
			}
			timeline.setBPMChanges(changes);
		}
		else
		{
			timeline.setBPMChanges(null);
		}

		songInfoReady = length > 0;
	}

	function updateTimeline(elapsed:Float):Void
	{
		if (timeline == null)
			return;

		if (!songInfoReady)
		{
			songInfoPoll += elapsed;
			if (songInfoPoll >= 1)
			{
				songInfoPoll = 0;
				refreshTimelineSongInfo();
			}
		}

		timeline.setCurrentTime(Conductor.songPosition);

		// The song was frozen for a scrub: hold the conductor at the frozen moment.
		if (frozenSongPosition >= 0)
			Conductor.songPosition = frozenSongPosition;

		if (seekDragActive && !isPointerPressed())
		{
			seekDragActive = false;
			if (seekWasPlaying)
				resumeSong();
		}
	}

	function onTimelineSeek(ms:Float):Void
	{
		if (!seekDragActive)
		{
			seekDragActive = true;
			seekWasPlaying = !songPaused && isMusicPlaying();
			pauseAudio();
		}

		frozenSongPosition = ms;
		BlockScriptRuntime.seekTo(ms);
	}

	function onMarkerSelected(id:String):Void
	{
		var marker:TimelineMarker = timeline.getMarker(id);
		activeMarkerId = (marker != null) ? marker.id : '';
		showingGlobals = (marker == null);
		cancelDrag();
		refreshWorkspace();

		if (marker != null)
			setStatus('Editing marker ' + markerName(marker) + ' (step ' + marker.step + ')');
	}

	function onMarkerMoved(id:String):Void
	{
		if (!markerMoveSnapshot)
		{
			markerMoveSnapshot = true;
			pushUndo();
		}
		markDirty();
	}

	function onMarkerRemove(id:String):Void
	{
		var marker:TimelineMarker = timeline.getMarker(id);
		if (marker == null)
			return;

		askPrompt('Remove marker', 'Delete ' + markerName(marker) + ' (step ' + marker.step + ') and everything placed on it?', ['Remove'],
			function(choice:Int)
			{
				if (choice == 0)
					removeMarker(marker.id);
			});
	}

	function removeMarker(id:String):Void
	{
		var roots:Array<Block> = workspaceRoots(id);
		pushUndo();

		for (root in roots)
			removeStack(root);

		for (block in blockContainer.members.copy())
		{
			if (blockWorkspace.get(block) == id)
				removeStack(block);
		}

		timeline.removeMarker(id);

		if (activeMarkerId == id)
		{
			activeMarkerId = '';
			showingGlobals = true;
		}

		markDirty();
		refreshWorkspace();
		setStatus('Marker removed');
		playSound('cancelMenu');
	}

	/**
	 * Adds a marker at the current step and selects it. When a block is given, the whole stack it
	 * belongs to moves under the new marker, which is what the context menu promises.
	 */
	function addMarkerAtCurrentStep(?block:Block):Void
	{
		var step:Int = currentStep();
		var sequence:Int = 0;
		var id:String = 'marker_' + step + '_' + sequence;
		while (timeline.getMarker(id) != null)
		{
			sequence++;
			id = 'marker_' + step + '_' + sequence;
		}

		var marker:TimelineMarker = {
			id: id,
			step: step,
			time: timeline.stepToMs(step),
			name: 'Step ' + step
		};

		pushUndo();
		timeline.addMarker(marker);
		timeline.selectMarker(marker.id);
		timeline.markDirty();
		activeMarkerId = marker.id;
		showingGlobals = false;

		var moved:String = '';
		if (block != null && !block.isReporter && workspaceOf(block) == GLOBAL_WORKSPACE)
		{
			// A root of the global workspace can be handed over to the new marker; a block that is
			// stacked under another one keeps its position and only the marker is created.
			var root:Block = stackRootOf(block);
			if (root != null && root == block)
			{
				assignWorkspace(root, marker.id);
				moved = ' - ' + block.blockData.label + ' moved onto it';
			}
		}

		markDirty();
		refreshWorkspace();
		setStatus('Marker added at step ' + step + moved);
		playSound('confirmMenu');
	}

	/** Walks up the chain (and out of a reporter's input) to the block the stack starts at. */
	function stackRootOf(block:Block):Block
	{
		var current:Block = block;
		var guard:Int = 0;

		while (current != null && guard++ < 4096)
		{
			if (current.parentInput != null)
			{
				current = current.parentInput.parentBlock;
				continue;
			}
			if (current.prevBlock != null)
			{
				current = current.prevBlock;
				continue;
			}

			return current;
		}

		return null;
	}

	function activeMarker():TimelineMarker
	{
		if (activeMarkerId == null || activeMarkerId.length == 0 || timeline == null)
			return null;

		return timeline.getMarker(activeMarkerId);
	}

	function currentStep():Int
	{
		var position:Float = Conductor.songPosition - ClientPrefs.noteOffset;
		var step:Float = Conductor.getStep(position);
		if (Math.isNaN(step) || step < 0)
			return 0;

		return Std.int(Math.floor(step));
	}

	static function markerName(marker:TimelineMarker):String
	{
		if (marker == null)
			return '';

		return (marker.name != null && marker.name.length > 0) ? marker.name : ('Step ' + marker.step);
	}

	static function markerEventName(marker:TimelineMarker):String
	{
		if (marker == null)
			return '';

		var name:Dynamic = Reflect.field(marker, 'eventName');
		return (name == null) ? '' : Std.string(name);
	}

	function chartEventNames():Array<String>
	{
		if (chartEventNamesCache.length > 0)
			return chartEventNamesCache;

		var names:Array<String> = [];
		var song:SwagSong = PlayState.SONG;
		if (song == null || song.events == null)
			return names;

		for (event in song.events)
		{
			if (event == null)
				continue;

			var name:String = '';
			if (Std.isOfType(event, Array))
			{
				var list:Array<Dynamic> = cast event;
				if (list.length > 0 && list[0] != null)
					name = Std.string(list[0]);
			}

			if (name.length > 0 && !names.contains(name))
				names.push(name);
		}

		chartEventNamesCache = names;
		return names;
	}

	// ============================================================================================
	// Panels
	// ============================================================================================

	/**
	 * Builds the overlay widgets. They bake the viewport into their own layout, so a viewport change
	 * throws them away and rebuilds them; doing it here also keeps them above every other HUD layer.
	 */
	function placePanels():Void
	{
		if (camHUD == null)
			return;

		destroyPanels();

		// These panels bring their own camera along and add it to `FlxG.cameras` while they are open,
		// so they end up above `camHUD` and must keep their `cameras` untouched.
		savePanel = new BlockSavePanel(BlockLayout.width);
		savePanel.codeProvider = currentLua;
		savePanel.onSaved = onPanelSaved;
		savePanel.onClosed = onPanelClosed;
		add(savePanel);

		// This one keeps a camera the caller assigned, so the editor's own HUD camera is used.
		codePanel = new BlockCodePanel(BlockLayout.width, BlockLayout.height);
		codePanel.cameras = [camHUD];
		add(codePanel);

		fileBrowser = new BlockFileBrowser(BlockLayout.width, BlockLayout.height);
		add(fileBrowser);

		helpOverlay = new BlockHelpOverlay(BlockLayout.width, BlockLayout.height);
		helpOverlay.cameras = [camHUD];
		add(helpOverlay);

		contextMenuWidth = 220 * BlockLayout.scale;
		contextMenuHeight = 300 * BlockLayout.scale;
		contextMenu = new BlockContextMenu(contextMenuWidth, contextMenuHeight);
		contextMenu.cameras = [camHUD];
		add(contextMenu);

		virtualKeyboard = new BlockVirtualKeyboard(camHUD);
		virtualKeyboard.onKey = onVirtualKey;
		virtualKeyboard.onClose = onVirtualKeyboardClosed;
		add(virtualKeyboard);

		prompt = new PromptBox(BlockLayout.scale);
		prompt.cameras = [camHUD];
		add(prompt);

		panelsBuilt = true;
	}

	function destroyPanels():Void
	{
		if (!panelsBuilt && savePanel == null && codePanel == null && fileBrowser == null && helpOverlay == null && contextMenu == null
			&& virtualKeyboard == null && prompt == null)
			return;

		closeFieldEditor();
		panelOpen = false;
		contextBlock = null;

		destroyPanelWidget(savePanel);
		savePanel = null;
		destroyPanelWidget(codePanel);
		codePanel = null;
		destroyPanelWidget(fileBrowser);
		fileBrowser = null;
		destroyPanelWidget(helpOverlay);
		helpOverlay = null;
		destroyPanelWidget(contextMenu);
		contextMenu = null;
		destroyPanelWidget(virtualKeyboard);
		virtualKeyboard = null;
		destroyPanelWidget(prompt);
		prompt = null;

		panelsBuilt = false;
	}

	function destroyPanelWidget(widget:FlxBasic):Void
	{
		if (widget == null)
			return;

		remove(widget, true);
		widget.destroy();
	}

	function openSavePanel():Void
	{
		if (savePanel == null)
			return;

		closeFieldEditor();
		panelOpen = true;
		savePanel.open(settings, songName());
	}

	function onPanelSaved(path:String):Void
	{
		if (savePanel != null)
		{
			savePanel.applyTo(settings);
			liveReload = settings.autoReload;
			setButtonText(liveButton, liveReload ? 'Live on' : 'Live off');
			setButtonColor(liveButton, liveReload ? COLOR_BUTTON_GOOD : COLOR_BUTTON);
		}

		dirty = false;
		saveCache();

		var target:String = (path == null) ? '' : path;
		if (liveReload && BlockScriptRuntime.isAvailable() && target.length > 0)
		{
			if (BlockScriptRuntime.reload(target, settings.scriptName))
				setStatus('Saved and live: ' + target);
			else
				setStatus('Saved ' + target + ' - the live reload failed');
		}
		else
		{
			setStatus('Saved ' + target);
		}

		playSound('confirmMenu');
	}

	function onPanelClosed():Void
	{
		panelOpen = false;
	}

	function openCodePanel():Void
	{
		if (codePanel == null)
			return;

		closeFieldEditor();
		panelOpen = true;
		codePanel.open(currentLua(), onCodeApplied, onPanelClosed);
	}

	function onCodeApplied(lua:String):Void
	{
		applyImportedLua(lua, 'code panel');
	}

	function openFileBrowser():Void
	{
		if (fileBrowser == null)
			return;

		closeFieldEditor();
		panelOpen = true;
		fileBrowser.setSongFilter(songName());
		fileBrowser.open(onFilePicked, onPanelClosed);
	}

	function onFilePicked(path:String):Void
	{
		if (path == null || path.length == 0)
			return;

		var text:String = BlockFileIO.read(path);
		if (text == null || text.length == 0)
		{
			setStatus('Could not read ' + path);
			playSound('cancelMenu');
			return;
		}

		if (!BlockLuaImporter.looksLikeGenerated(text))
			setStatus('Warning: ' + path + ' was not written by the block editor - importing anyway');

		applyImportedLua(text, path);
	}

	function openHelpPanel():Void
	{
		if (helpOverlay == null)
			return;

		closeFieldEditor();
		panelOpen = true;
		helpOverlay.open(onPanelClosed);
	}

	function closeOpenPanel():Void
	{
		if (!panelOpen)
			return;

		panelOpen = false;

		if (savePanel != null)
			savePanel.close();
		if (codePanel != null)
			codePanel.close();
		if (fileBrowser != null)
			fileBrowser.close();
		if (helpOverlay != null)
			helpOverlay.close();
	}

	function applyImportedLua(lua:String, source:String):Void
	{
		var result:ImportResult = BlockLuaImporter.importCode(lua);
		if (result == null)
		{
			setStatus('Import failed - nothing was replaced');
			playSound('cancelMenu');
			return;
		}

		var project:BlockProject = {
			version: BlockTypes.PROJECT_VERSION,
			stacks: result.stacks,
			timeline: result.timeline,
			settings: settings
		};

		restoreProject(project);
		markDirty();

		var warnings:Array<String> = result.warnings;
		if (warnings != null && warnings.length > 0)
			setStatus('Imported from ' + source + ' with ' + warnings.length + ' warning(s): ' + warnings[0]);
		else
			setStatus('Imported from ' + source);
	}

	// ============================================================================================
	// Live code preview
	// ============================================================================================

	function placePreview():Void
	{
		if (camHUD == null)
			return;

		var rect:Rect = previewRect;

		if (preview == null)
		{
			preview = new BlockCodePreview(rect.x, rect.y, rect.w, rect.h, camHUD);
			preview.onExpand = function():Void
			{
				openCodePanel();
			};
			preview.onClose = function():Void
			{
				setPreviewVisible(false);
			};
			add(preview);
		}
		else
		{
			preview.resize(rect.x, rect.y, rect.w, rect.h);
		}

		syncPreview();
	}

	function togglePreview():Void
	{
		setPreviewVisible(!previewWanted);
	}

	function setPreviewVisible(visible:Bool):Void
	{
		previewWanted = visible;
		previewToggled = true;
		syncPreview();
		updatePreviewButton();
		playSound(visible ? 'confirmMenu' : 'cancelMenu');
		setStatus(visible ? 'Live code preview on' : 'Live code preview off');
	}

	function syncPreview():Void
	{
		if (preview == null)
			return;

		if (previewWanted)
		{
			if (!preview.isOpen())
				preview.open();

			preview.resize(previewRect.x, previewRect.y, previewRect.w, previewRect.h);
			preview.setStatus(statusMessage);
			preview.setCurrentStep(currentStep());
			previewCodeDirty = true;
			previewCodeTimer = 0;
			updatePreviewCode();
		}
		else if (preview.isOpen())
		{
			preview.close();
		}
	}

	function updatePreview(elapsed:Float):Void
	{
		if (preview == null || !preview.isOpen())
			return;

		preview.setCurrentStep(currentStep());

		if (!previewCodeDirty)
			return;

		previewCodeTimer -= elapsed;
		if (previewCodeTimer > 0)
			return;

		updatePreviewCode();
	}

	function updatePreviewCode():Void
	{
		if (preview == null || !preview.isOpen())
			return;

		previewCodeDirty = false;
		previewCodeTimer = PREVIEW_CODE_INTERVAL;
		preview.setCode(currentLua());
	}

	// ============================================================================================
	// Persistence: cache, undo/redo, project building
	// ============================================================================================

	function loadCachedProject():Void
	{
		settings = BlockSerializer.loadSettings();
		if (settings == null)
			settings = BlockTypes.defaultSettings();

		liveReload = settings.autoReload;
		zoomLevel = FlxMath.bound(settings.zoom, MIN_ZOOM, MAX_ZOOM);
		camEditor.zoom = zoomLevel;

		var project:BlockProject = BlockSerializer.load();
		if (project != null)
			restoreProject(project);

		dirty = false;
		autosaveTimer = 0;
	}

	function buildProject():BlockProject
	{
		return BlockSerializer.project(workspaceRoots(GLOBAL_WORKSPACE), timelineEntries(), settings);
	}

	function timelineEntries():Array<{marker:TimelineMarker, root:Block}>
	{
		var entries:Array<{marker:TimelineMarker, root:Block}> = [];
		if (timeline == null)
			return entries;

		for (marker in timeline.markers)
		{
			if (marker == null)
				continue;

			var roots:Array<Block> = workspaceRoots(marker.id);
			if (roots.length == 0)
			{
				// Keep the marker itself: a marker without blocks still has to survive a reload.
				entries.push({marker: marker, root: null});
				continue;
			}

			for (root in roots)
				entries.push({marker: marker, root: root});
		}

		return entries;
	}

	function restoreProject(project:BlockProject):Void
	{
		if (project == null)
			return;

		restoringHistory = true;
		clearBlocks();

		if (timeline != null)
		{
			for (marker in timeline.markers.copy())
			{
				if (marker != null)
					timeline.removeMarker(marker.id);
			}
		}

		var restored:{globals:Array<Block>, timeline:Array<{marker:TimelineMarker, root:Block}>} = BlockSerializer.restoreStacks(project, blockContainer);

		if (restored.globals != null)
		{
			for (root in restored.globals)
			{
				if (root != null)
					assignWorkspace(root, GLOBAL_WORKSPACE);
			}
		}

		if (restored.timeline != null && timeline != null)
		{
			for (entry in restored.timeline)
			{
				if (entry == null || entry.marker == null)
					continue;

				timeline.addMarker(entry.marker);
				if (entry.root != null)
					assignWorkspace(entry.root, entry.marker.id);
			}
		}

		activeMarkerId = '';
		showingGlobals = true;
		restoringHistory = false;

		if (timeline != null)
			timeline.markDirty();

		cancelDrag();
		refreshWorkspace();
		refreshTimelineSongInfo();
	}

	function saveCache():Void
	{
		if (settings == null)
			return;

		BlockSerializer.save(buildProject());
		BlockSerializer.saveSettings(settings);
		dirty = false;
		autosaveTimer = 0;
	}

	function markDirty():Void
	{
		dirty = true;
		autosaveTimer = 0;
		previewCodeDirty = true;
	}

	function updateAutosave(elapsed:Float):Void
	{
		if (!dirty)
			return;

		autosaveTimer += elapsed;
		if (autosaveTimer >= AUTOSAVE_INTERVAL)
			saveCache();
	}

	function pushUndo():Void
	{
		if (restoringHistory || blockContainer == null)
			return;

		undoStack.push(buildProject());
		while (undoStack.length > MAX_UNDO)
			undoStack.shift();

		redoStack = [];
		refreshHistoryButtons();
	}

	function undo():Void
	{
		if (undoStack.length == 0)
		{
			setStatus('Nothing to undo');
			return;
		}

		redoStack.push(buildProject());
		while (redoStack.length > MAX_UNDO)
			redoStack.shift();

		var project:BlockProject = undoStack.pop();
		restoreProject(project);
		dirty = true;
		previewCodeDirty = true;
		refreshHistoryButtons();
		setStatus('Undo (' + undoStack.length + ' left)');
		playSound('scrollMenu');
	}

	function redo():Void
	{
		if (redoStack.length == 0)
		{
			setStatus('Nothing to redo');
			return;
		}

		undoStack.push(buildProject());
		while (undoStack.length > MAX_UNDO)
			undoStack.shift();

		var project:BlockProject = redoStack.pop();
		restoreProject(project);
		dirty = true;
		previewCodeDirty = true;
		refreshHistoryButtons();
		setStatus('Redo (' + redoStack.length + ' left)');
		playSound('scrollMenu');
	}

	function refreshHistoryButtons():Void
	{
		if (undoButton != null)
			undoButton.status = (undoStack.length > 0) ? FlxButtonState.NORMAL : FlxButtonState.DISABLED;
		if (redoButton != null)
			redoButton.status = (redoStack.length > 0) ? FlxButtonState.NORMAL : FlxButtonState.DISABLED;
	}

	function songName():String
	{
		if (PlayState.SONG != null && PlayState.SONG.song != null)
			return PlayState.SONG.song;

		return suggestedSongName;
	}

	// ============================================================================================
	// Workspaces
	// ============================================================================================

	function activeWorkspaceId():String
	{
		if (showingGlobals || activeMarkerId == null || activeMarkerId.length == 0)
			return GLOBAL_WORKSPACE;

		return activeMarkerId;
	}

	function workspaceOf(block:Block):String
	{
		if (block == null)
			return GLOBAL_WORKSPACE;

		var workspace:String = blockWorkspace.get(block);
		return (workspace == null) ? GLOBAL_WORKSPACE : workspace;
	}

	function workspaceBlocks(workspaceId:String):Array<Block>
	{
		var out:Array<Block> = [];
		if (blockContainer == null)
			return out;

		for (block in blockContainer.members)
		{
			if (block == null || workspaceOf(block) != workspaceId)
				continue;

			out.push(block);
		}

		return out;
	}

	function workspaceRoots(workspaceId:String):Array<Block>
	{
		var out:Array<Block> = [];
		if (blockContainer == null)
			return out;

		for (block in blockContainer.members)
		{
			if (block == null || block.prevBlock != null || block.parentInput != null)
				continue;
			if (workspaceOf(block) != workspaceId)
				continue;

			out.push(block);
		}

		return out;
	}

	function refreshWorkspace():Void
	{
		updateWorkspaceVisibility();
		refreshBlockCount();
		refreshMarkerTabs();
		refreshHistoryButtons();
		previewCodeDirty = true;
	}

	function updateWorkspaceVisibility():Void
	{
		var workspace:String = activeWorkspaceId();
		for (block in blockContainer.members)
		{
			if (block == null)
				continue;

			var visible:Bool = (workspaceOf(block) == workspace);
			block.visible = visible;
			block.active = visible;
		}
	}

	function selectGlobalWorkspace():Void
	{
		if (showingGlobals)
			return;

		showingGlobals = true;
		cancelDrag();
		refreshWorkspace();
		setStatus('Editing the global scripts');
		playSound('scrollMenu');
	}

	function selectMarkerWorkspace():Void
	{
		var marker:TimelineMarker = activeMarker();
		if (marker == null)
		{
			setStatus('Select a marker on the timeline first');
			playSound('cancelMenu');
			return;
		}

		showingGlobals = false;
		cancelDrag();
		refreshWorkspace();
		setStatus('Editing ' + markerName(marker));
		playSound('scrollMenu');
	}

	/** Tags a whole stack (chain plus plugged-in reporters) as belonging to one workspace. */
	function assignWorkspace(root:Block, workspaceId:String, depth:Int = 1):Void
	{
		if (root == null || depth > 128)
			return;

		var current:Block = root;
		var guard:Int = 0;

		while (current != null && guard++ < 4096)
		{
			blockWorkspace.set(current, workspaceId);

			if (current.inputFields != null)
			{
				for (input in current.inputFields)
				{
					if (input != null && input.attachedBlock != null)
						assignWorkspace(input.attachedBlock, workspaceId, depth + 1);
				}
			}

			current = current.nextBlock;
		}
	}

	function refreshMarkerTabs():Void
	{
		if (globalTabButton == null || markerTabButton == null)
			return;

		var marker:TimelineMarker = activeMarker();
		var eventName:String = markerEventName(marker);
		var label:String = 'No marker';
		if (marker != null)
		{
			var name:String = markerName(marker);
			if (name.length > 10)
				name = name.substr(0, 9) + '.';
			label = (eventName.length > 0 ? '! ' : '') + name;
		}

		setButtonText(markerTabButton, label);
		setButtonColor(globalTabButton, showingGlobals ? COLOR_BUTTON_ACTIVE : COLOR_BUTTON);
		setButtonColor(markerTabButton, (!showingGlobals && marker != null) ? COLOR_BUTTON_ACTIVE : COLOR_BUTTON);

		// The button keeps its width, so the bar only has to be walked again.
		wrapTopBar(true);
	}

	// ============================================================================================
	// Blocks
	// ============================================================================================

	/** Spawns a block in the middle of the visible workspace, cascading a little for repeats. */
	function addBlock(data:BlockData):Block
	{
		if (data == null || blockContainer == null)
			return null;

		pushUndo();

		var block:Block = new Block(0, 0, data);
		block.cameras = [camEditor];
		block.scrollFactor.set(1, 1);
		blockContainer.add(block);
		assignWorkspace(block, activeWorkspaceId());

		FlxTween.cancelTweensOf(block.scale);
		block.scale.set(1, 1);
		block.alpha = 1;

		var z:Float = (camEditor != null) ? camEditor.zoom : 1;
		var centreX:Float = wsRect.x + wsRect.w * 0.5;
		var centreY:Float = wsRect.y + wsRect.h * 0.5;

		block.x = camEditor.scroll.x + centreX / z - block.width * 0.5 + lastSpawnPos.x;
		block.y = camEditor.scroll.y + centreY / z - block.height * 0.5 + lastSpawnPos.y;

		lastSpawnPos.x = (lastSpawnPos.x + 30) % 120;
		lastSpawnPos.y = (lastSpawnPos.y + 20) % 120;

		markDirty();
		updateWorkspaceVisibility();
		refreshBlockCount();
		setStatus('Added ' + data.label);
		playSound('scrollMenu');

		return block;
	}

	/** Creates a block whose middle sits at the given screen position (used when dragging a tile). */
	function createBlockAt(data:BlockData, screenX:Float, screenY:Float):Block
	{
		if (data == null || blockContainer == null)
			return null;

		pushUndo();

		var block:Block = new Block(0, 0, data);
		block.cameras = [camEditor];
		block.scrollFactor.set(1, 1);
		blockContainer.add(block);
		assignWorkspace(block, activeWorkspaceId());

		var z:Float = (camEditor != null) ? camEditor.zoom : 1;
		block.x = camEditor.scroll.x + screenX / z - block.width * z * 0.5;
		block.y = camEditor.scroll.y + screenY / z - block.height * z * 0.5;

		markDirty();
		updateWorkspaceVisibility();
		refreshBlockCount();

		return block;
	}

	function duplicateBlock(block:Block):Void
	{
		if (block == null)
			return;

		var data:Dynamic = BlockSerializer.serializeStack(block);
		if (data == null)
			return;

		pushUndo();

		var copy:Block = BlockSerializer.deserializeStack(data, blockContainer);
		if (copy == null)
		{
			setStatus('Could not duplicate this block');
			return;
		}

		shiftStack(copy, 40, 40);
		copy.cameras = [camEditor];
		assignWorkspace(copy, workspaceOf(block));

		markDirty();
		updateWorkspaceVisibility();
		refreshBlockCount();
		setStatus('Duplicated ' + block.blockData.label);
		playSound('confirmMenu');
	}

	function shiftStack(root:Block, dx:Float, dy:Float):Void
	{
		var current:Block = root;
		var guard:Int = 0;

		while (current != null && guard++ < 4096)
		{
			current.x += dx;
			current.y += dy;

			if (current.inputFields != null)
			{
				for (input in current.inputFields)
				{
					if (input != null && input.attachedBlock != null)
						shiftStack(input.attachedBlock, dx, dy);
				}
			}

			current = current.nextBlock;
		}
	}

	function detachBlock(block:Block):Void
	{
		if (block == null)
			return;

		pushUndo();

		if (block.parentInput != null)
		{
			var parent:Block = block.parentInput.parentBlock;
			block.parentInput.attachedBlock = null;
			block.parentInput = null;
			if (parent != null)
				parent.recalculateSize();
		}

		if (block.prevBlock != null)
		{
			block.prevBlock.nextBlock = null;
			block.prevBlock = null;
			block.isSnapped = false;
		}

		block.x = block.x + 20;
		block.y = block.y + 20;

		if (!blockWorkspace.exists(block))
			blockWorkspace.set(block, activeWorkspaceId());

		markDirty();
		updateWorkspaceVisibility();
		refreshBlockCount();
		setStatus('Detached ' + block.blockData.label);
		playSound('scrollMenu');
	}

	function deleteBlock(block:Block):Void
	{
		if (block == null)
			return;

		pushUndo();

		var parentInput:InputField = block.parentInput;
		var previous:Block = block.prevBlock;
		var following:Block = block.nextBlock;

		if (parentInput != null)
		{
			parentInput.attachedBlock = null;
			block.parentInput = null;
			if (parentInput.parentBlock != null)
				parentInput.parentBlock.recalculateSize();
		}

		if (previous != null)
		{
			previous.nextBlock = null;
			block.prevBlock = null;
		}

		if (following != null)
		{
			following.prevBlock = null;
			following.isSnapped = false;
		}

		removeBlockWithReporters(block);
		markDirty();
		updateWorkspaceVisibility();
		refreshBlockCount();
		setStatus('Deleted block');
		playSound('cancelMenu');
	}

	/** Takes one block out of the container and disposes of it and of its inline widgets. */
	function removeBlock(block:Block):Void
	{
		if (block == null)
			return;

		blockWorkspace.remove(block);
		blockContainer.remove(block, true);

		if (block.inputFields != null)
		{
			for (input in block.inputFields)
			{
				if (input == null)
					continue;

				FlxDestroyUtil.destroy(input.bg);
				FlxDestroyUtil.destroy(input.text);
				FlxDestroyUtil.destroy(input.placeholderText);
			}
			block.inputFields = [];
		}

		FlxDestroyUtil.destroy(block.label);
		FlxDestroyUtil.destroy(block.icon);
		block.label = null;
		block.icon = null;

		block.destroy();
	}

	/** Removes a whole chain (and the reporters plugged into it) starting at `root`. */
	function removeStack(root:Block):Void
	{
		if (root == null)
			return;

		var current:Block = root;
		var guard:Int = 0;

		while (current != null && guard++ < 4096)
		{
			var following:Block = current.nextBlock;

			if (current.inputFields != null)
			{
				for (input in current.inputFields)
				{
					if (input != null && input.attachedBlock != null)
						removeStack(input.attachedBlock);
				}
			}

			current.nextBlock = null;
			current.prevBlock = null;
			removeBlock(current);
			current = following;
		}
	}

	function clearBlocks():Void
	{
		if (blockContainer == null)
			return;

		for (block in blockContainer.members.copy())
			removeStack(block);

		blockContainer.clear();
		blockWorkspace = new Map();
	}

	function findBlockAt(worldX:Float, worldY:Float):Block
	{
		var index:Int = blockContainer.members.length - 1;
		while (index >= 0)
		{
			var block:Block = blockContainer.members[index];
			index--;

			if (block == null || !block.active || !block.visible)
				continue;
			if (worldX >= block.x && worldX <= block.x + block.width && worldY >= block.y && worldY <= block.y + block.height)
				return block;
		}

		return null;
	}

	function findInputAt(worldX:Float, worldY:Float):InputField
	{
		var index:Int = blockContainer.members.length - 1;
		while (index >= 0)
		{
			var block:Block = blockContainer.members[index];
			index--;

			if (block == null || !block.active || !block.visible || block.inputFields == null)
				continue;

			for (input in block.inputFields)
			{
				if (input == null || input.attachedBlock != null)
					continue;
				if (worldX >= input.bg.x && worldX <= input.bg.x + input.width && worldY >= input.bg.y && worldY <= input.bg.y + input.height)
					return input;
			}
		}

		return null;
	}

	// ============================================================================================
	// Update loop
	// ============================================================================================

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (ready)
			ensureLayout();

		// A press outside an open context menu dismisses it and is swallowed.
		if (isContextMenuOpen() && isPointerJustPressed() && !isPointerOverContextMenu())
		{
			closeContextMenu();
			pointerSwallowed = true;
		}

		var pointerLocked:Bool = pointerBlocked();

		updateTimeline(elapsed);
		updateAutosave(elapsed);
		updateStatusText(elapsed);
		updateSearchField(elapsed);
		updatePaletteScroll(elapsed);
		updatePreview(elapsed);

		if (!pointerLocked)
		{
			handleShortcuts(elapsed);
			handlePointer(elapsed);
		}
		else
		{
			releaseConsumedPointer();
		}

		handleTooltips(elapsed);

		if (!isPointerPressed() && !isPointerJustReleased())
		{
			// Nothing is being held: no deferred drag or pan can still be waiting.
			pendingDragBlock = null;
			pendingPan = false;
		}

		if (editingField != null && !editingField.isFocused)
			editingField = null;

		if (markerMoveSnapshot && !isPointerPressed())
			markerMoveSnapshot = false;
	}

	/** True while another layer owns the pointer: prompt, panel, keyboard, context menu, preview. */
	function pointerBlocked():Bool
	{
		if (pointerSwallowed)
			return true;
		if (prompt != null && prompt.isShowing())
			return true;
		if (panelOpen)
			return true;
		if (virtualKeyboard != null && virtualKeyboard.isOpen())
			return true;
		if (isContextMenuOpen())
			return true;

		return false;
	}

	function releaseConsumedPointer():Void
	{
		if (!pointerSwallowed)
			return;

		if (!isPointerPressed() && !isPointerJustReleased())
		{
			pointerSwallowed = false;
			return;
		}

		if (isPointerJustReleased())
			pointerSwallowed = false;
	}

	// ============================================================================================
	// Keyboard / pointer helpers, ported from the legacy state
	// ============================================================================================

	function getPrimaryTouch():FlxTouch
	{
		for (touch in FlxG.touches.list)
		{
			if (touch != null && (touch.pressed || touch.justPressed || touch.justReleased))
				return touch;
		}

		return null;
	}

	function getPointerScreenX():Float
	{
		var touch:FlxTouch = getPrimaryTouch();
		return (touch != null) ? touch.screenX : FlxG.mouse.screenX;
	}

	function getPointerScreenY():Float
	{
		var touch:FlxTouch = getPrimaryTouch();
		return (touch != null) ? touch.screenY : FlxG.mouse.screenY;
	}

	function isPointerJustPressed():Bool
	{
		var touch:FlxTouch = getPrimaryTouch();
		return (touch != null) ? touch.justPressed : FlxG.mouse.justPressed;
	}

	function isPointerJustReleased():Bool
	{
		var touch:FlxTouch = getPrimaryTouch();
		return (touch != null) ? touch.justReleased : FlxG.mouse.justReleased;
	}

	function isPointerPressed():Bool
	{
		var touch:FlxTouch = getPrimaryTouch();
		return (touch != null) ? touch.pressed : FlxG.mouse.pressed;
	}

	function isPointerRightPressed():Bool
	{
		if (getPrimaryTouch() != null)
			return false;

		return FlxG.mouse.justPressedRight;
	}

	function getPointerWorldPosition(cam:FlxCamera):FlxPoint
	{
		var touch:FlxTouch = getPrimaryTouch();
		if (touch != null)
			return new FlxPoint(cam.scroll.x + (touch.screenX - cam.x) / cam.zoom, cam.scroll.y + (touch.screenY - cam.y) / cam.zoom);

		return FlxG.mouse.getWorldPosition(cam);
	}

	function isPointerOverScreenSprite(sprite:FlxSprite):Bool
	{
		if (sprite == null || !sprite.visible)
			return false;

		var x:Float = getPointerScreenX();
		var y:Float = getPointerScreenY();
		return (x >= sprite.x && x <= sprite.x + sprite.width && y >= sprite.y && y <= sprite.y + sprite.height);
	}

	function isPointerOverBlock(worldPos:FlxPoint):Bool
	{
		return findBlockAt(worldPos.x, worldPos.y) != null;
	}

	function isPointerOverTimeline():Bool
	{
		return pointInRect(getPointerScreenX(), getPointerScreenY(), timelineRect);
	}

	function isPointerOverMarkerButton():Bool
	{
		return (markerButton != null && markerButton.visible && isPointerOverScreenSprite(markerButton));
	}

	function isPointerOverTopBar():Bool
	{
		return getPointerScreenY() <= barHeight;
	}

	function isPointerOverStatusBar():Bool
	{
		return getPointerScreenY() >= BlockLayout.height - BlockLayout.statusHeight();
	}

	function isPointerOverPalette():Bool
	{
		return pointInRect(getPointerScreenX(), getPointerScreenY(), paletteBand);
	}

	function isPointerOverPreview():Bool
	{
		if (preview == null || !preview.isOpen())
			return false;

		return pointInRect(getPointerScreenX(), getPointerScreenY(), previewRect);
	}

	function isPointerOverContextMenu():Bool
	{
		if (!isContextMenuOpen())
			return false;

		var x:Float = getPointerScreenX();
		var y:Float = getPointerScreenY();
		return (x >= contextMenuX && x <= contextMenuX + contextMenuWidth && y >= contextMenuY && y <= contextMenuY + contextMenuHeight);
	}

	function isPointerOverWorkspace():Bool
	{
		if (isPointerOverTopBar() || isPointerOverStatusBar() || isPointerOverTimeline())
			return false;
		if (isPointerOverPalette() || isPointerOverPreview())
			return false;
		if (isPointerOverMarkerButton())
			return false;
		if (isPointerOverScreenSprite(trashCan))
			return false;

		var y:Float = getPointerScreenY();
		return (y >= wsRect.y && y <= wsRect.y + wsRect.h);
	}

	// ============================================================================================
	// Shortcuts
	// ============================================================================================

	function handleShortcuts(elapsed:Float):Void
	{
		if (hasFocusedField())
			return;

		if (FlxG.keys.pressed.CONTROL)
		{
			if (FlxG.keys.justPressed.S)
			{
				saveAndReload();
				return;
			}
			if (FlxG.keys.justPressed.Z)
			{
				undo();
				return;
			}
			if (FlxG.keys.justPressed.Y)
			{
				redo();
				return;
			}
		}

		if (FlxG.keys.pressed.E)
		{
			zoomLevel += elapsed * zoomLevel;
			if (zoomLevel > MAX_ZOOM)
				zoomLevel = MAX_ZOOM;
			camEditor.zoom = zoomLevel;
		}
		if (FlxG.keys.pressed.Q)
		{
			zoomLevel -= elapsed * zoomLevel;
			if (zoomLevel < MIN_ZOOM)
				zoomLevel = MIN_ZOOM;
			camEditor.zoom = zoomLevel;
		}

		#if android
		if (editorTouchPad != null)
		{
			if (editorTouchPad.buttonX.pressed)
			{
				zoomLevel += elapsed * zoomLevel;
				if (zoomLevel > MAX_ZOOM)
					zoomLevel = MAX_ZOOM;
				camEditor.zoom = zoomLevel;
			}
			if (editorTouchPad.buttonY.pressed)
			{
				zoomLevel -= elapsed * zoomLevel;
				if (zoomLevel < MIN_ZOOM)
					zoomLevel = MIN_ZOOM;
				camEditor.zoom = zoomLevel;
			}
		}
		#end

		var moveSpeed:Float = 500.0;
		if (FlxG.keys.pressed.SHIFT)
			moveSpeed *= 2;

		if (FlxG.keys.pressed.I || FlxG.keys.pressed.UP)
			camEditor.scroll.y -= moveSpeed * elapsed;
		if (FlxG.keys.pressed.K || FlxG.keys.pressed.DOWN)
			camEditor.scroll.y += moveSpeed * elapsed;
		if (FlxG.keys.pressed.J || FlxG.keys.pressed.LEFT)
			camEditor.scroll.x -= moveSpeed * elapsed;
		if (FlxG.keys.pressed.L || FlxG.keys.pressed.RIGHT)
			camEditor.scroll.x += moveSpeed * elapsed;

		// Panning: Space + drag on desktop, drag from empty space on touch.
		var touch:FlxTouch = getPrimaryTouch();
		if (touch == null && FlxG.keys.pressed.SPACE && !isDragging)
		{
			var screenX:Float = getPointerScreenX();
			var screenY:Float = getPointerScreenY();

			if (isPointerJustPressed() && isPointerOverWorkspace())
			{
				isPanning = true;
				panStart.set(screenX, screenY);
			}

			if (isPanning && isPointerPressed())
			{
				camEditor.scroll.x += (panStart.x - screenX) / zoomLevel;
				camEditor.scroll.y += (panStart.y - screenY) / zoomLevel;
				panStart.set(screenX, screenY);
			}
		}
		else if (isPanning && touch == null)
		{
			isPanning = false;
		}

		if (touch != null)
		{
			if (touch.justPressed && !isDragging && !pendingPan && isPointerOverWorkspace() && !isPointerOverMarkerButton())
			{
				var worldPos:FlxPoint = getPointerWorldPosition(camEditor);
				if (!isPointerOverBlock(worldPos))
				{
					// A tap on empty canvas stays a tap until the finger actually moves.
					pendingPan = true;
					panStart.set(touch.screenX, touch.screenY);
				}
			}

			if (pendingPan && touch.pressed)
			{
				if (Math.abs(touch.screenX - panStart.x) + Math.abs(touch.screenY - panStart.y) > 4)
				{
					pendingPan = false;
					isPanning = true;
				}
			}

			if (isPanning && touch.pressed)
			{
				camEditor.scroll.x += (panStart.x - touch.screenX) / zoomLevel;
				camEditor.scroll.y += (panStart.y - touch.screenY) / zoomLevel;
				panStart.set(touch.screenX, touch.screenY);
			}

			if (touch.justReleased)
			{
				isPanning = false;
				pendingPan = false;
			}
		}
	}

	function hasFocusedField():Bool
	{
		if (editingField != null && editingField.isFocused)
			return true;
		if (searchField != null && searchField.isFocused)
			return true;
		if (blockContainer == null)
			return false;

		for (block in blockContainer.members)
		{
			if (block == null || block.inputFields == null)
				continue;

			for (input in block.inputFields)
			{
				if (input != null && input.isFocused)
					return true;
			}
		}

		return false;
	}

	function unfocusAllFields():Void
	{
		if (searchField != null)
			searchField.unfocus();
		if (blockContainer == null)
			return;

		for (block in blockContainer.members)
		{
			if (block == null || block.inputFields == null)
				continue;

			for (input in block.inputFields)
			{
				if (input != null && input.isFocused)
					input.unfocus();
			}
		}

		editingField = null;
	}

	// ============================================================================================
	// Workspace pointer handling (dragging, snapping, dropping)
	// ============================================================================================

	function handlePointer(elapsed:Float):Void
	{
		var pointerX:Float = getPointerScreenX();
		var pointerY:Float = getPointerScreenY();
		var justPressed:Bool = isPointerJustPressed();
		var justReleased:Bool = isPointerJustReleased();
		var pressed:Bool = isPointerPressed();
		var touch:FlxTouch = getPrimaryTouch();

		if (isPanning)
		{
			pendingDragBlock = null;
			return;
		}

		var worldPos:FlxPoint = getPointerWorldPosition(camEditor);

		// Right click opens the context menu like a long press does on touch.
		if (isPointerRightPressed() && isPointerOverWorkspace())
		{
			openContextMenuAtPointer();
			return;
		}

		if (justPressed && searchField != null && searchField.isFocused && !pointInRect(pointerX, pointerY, searchRect))
			searchField.unfocus();

		var paletteConsumed:Bool = false;
		if (!isDragging)
			paletteConsumed = handlePalettePress(justPressed, justReleased, pressed, pointerX, pointerY);

		if (!isDragging && !paletteConsumed)
		{
			if (justPressed)
			{
				pressStartX = pointerX;
				pressStartY = pointerY;
				pressHeldTime = 0;
				pressConsumed = false;

				if (isPointerOverWorkspace())
				{
					var input:InputField = findInputAt(worldPos.x, worldPos.y);
					if (input != null)
					{
						// The field itself owns the tap; the canvas only clears the other fields.
						unfocusFieldsOutside(worldPos);
						return;
					}

					var block:Block = findBlockAt(worldPos.x, worldPos.y);
					if (block == null)
						unfocusAllFields();
					else if (touch != null)
						pendingDragBlock = block; // touch: the long press has to win before the drag starts
					else
						startDrag(block, pointerX, pointerY);
				}
				else
				{
					unfocusFieldsOutside(worldPos);
				}
			}
			else if (pressed && !pressConsumed)
			{
				if (Math.abs(pointerX - pressStartX) + Math.abs(pointerY - pressStartY) > 6)
				{
					pressConsumed = true;
					if (pendingDragBlock != null)
					{
						var pending:Block = pendingDragBlock;
						pendingDragBlock = null;
						startDrag(pending, pointerX, pointerY);
					}
				}
				else if (!isDragging && touch != null && isPointerOverWorkspace())
				{
					pressHeldTime += elapsed;
					if (pressHeldTime >= LONG_PRESS_TIME)
					{
						pressConsumed = true;
						pendingDragBlock = null;
						openContextMenuAtPointer();
						return;
					}
				}
			}
			else if (!pressed && !justReleased)
			{
				pressHeldTime = 0;
				pressConsumed = false;
				pendingDragBlock = null;
			}
		}

		if (isDragging && draggingBlock != null)
		{
			draggingBlock.x = pointerX - dragOffset.x;
			draggingBlock.y = pointerY - dragOffset.y;

			if (isPointerOverScreenSprite(trashCan))
			{
				trashCan.scale.set(1.2, 1.2);
				draggingBlock.alpha = 0.5;
			}
			else
			{
				trashCan.scale.set(1.0, 1.0);
				draggingBlock.alpha = 1.0;
			}

			if (draggingBlock.isReporter)
				checkInputSnapping(draggingBlock);
			else
				checkSnapping(draggingBlock);
		}

		if (justReleased)
		{
			pendingDragBlock = null;

			if (isDragging && draggingBlock != null)
				dropDraggedBlock();
			else
			{
				if (draggingBlock != null)
					draggingBlock.isDragging = false;
				draggingBlock = null;
				isDragging = false;
				trashCan.scale.set(1.0, 1.0);
			}
		}
	}

	function startDrag(block:Block, pointerX:Float, pointerY:Float):Void
	{
		draggingBlock = block;
		draggingBlock.isDragging = true;

		var screenPos:FlxPoint = block.getScreenPosition(null, camEditor);
		block.cameras = [camHUD];
		block.x = screenPos.x;
		block.y = screenPos.y;
		block.scale.set(zoomLevel, zoomLevel);
		screenPos.put();

		dragOffset.set(pointerX - block.x, pointerY - block.y);
		isDragging = true;

		blockContainer.remove(block, true);
		blockContainer.add(block);

		if (block.parentInput != null)
		{
			var oldParent:Block = block.parentInput.parentBlock;
			block.parentInput.attachedBlock = null;
			block.parentInput = null;
			if (oldParent != null)
				oldParent.recalculateSize();
		}

		if (block.prevBlock != null)
		{
			block.prevBlock.nextBlock = null;
			block.prevBlock = null;
			block.isSnapped = false;
		}
	}

	function dropDraggedBlock():Void
	{
		var dropped:Block = draggingBlock;
		draggingBlock = null;
		isDragging = false;
		dropped.isDragging = false;

		if (isPointerOverScreenSprite(trashCan))
		{
			trashCan.scale.set(1.0, 1.0);
			pushUndo();
			discardDraggedBlock(dropped);
			return;
		}

		var worldPos:FlxPoint = getPointerWorldPosition(camEditor);
		dropped.x = worldPos.x - (dragOffset.x / zoomLevel);
		dropped.y = worldPos.y - (dragOffset.y / zoomLevel);
		dropped.cameras = [camEditor];
		dropped.scale.set(1, 1);
		dropped.alpha = 1.0;

		if (dropped.isReporter)
			applyInputSnapping(dropped);
		else
			applySnapping(dropped);

		if (isPointerOverPalette())
		{
			// Dropped over the palette: shrink away like in the standalone editor.
			pushUndo();
			FlxTween.tween(dropped.scale, {x: 0, y: 0}, 0.2, {
				ease: FlxEase.backIn,
				onComplete: function(tween:FlxTween)
				{
					discardDraggedBlock(dropped);
				}
			});
			playSound('cancelMenu');
			return;
		}

		markDirty();
		updateWorkspaceVisibility();
		refreshBlockCount();
	}

	/** Unlinks a dropped block and removes it (and the reporters plugged into it) from the canvas. */
	function discardDraggedBlock(block:Block):Void
	{
		if (block == null)
			return;

		var parentInput:InputField = block.parentInput;
		var previous:Block = block.prevBlock;
		var following:Block = block.nextBlock;

		if (parentInput != null)
		{
			parentInput.attachedBlock = null;
			block.parentInput = null;
			if (parentInput.parentBlock != null)
				parentInput.parentBlock.recalculateSize();
		}

		if (previous != null)
		{
			previous.nextBlock = null;
			block.prevBlock = null;
		}

		if (following != null)
		{
			following.prevBlock = null;
			following.isSnapped = false;
		}

		removeBlockWithReporters(block);
		markDirty();
		updateWorkspaceVisibility();
		refreshBlockCount();
		setStatus('Deleted block');
		playSound('cancelMenu');
	}

	function removeBlockWithReporters(block:Block):Void
	{
		if (block == null)
			return;

		if (block.inputFields != null)
		{
			for (input in block.inputFields)
			{
				if (input == null || input.attachedBlock == null)
					continue;

				var attached:Block = input.attachedBlock;
				input.attachedBlock = null;
				attached.parentInput = null;
				removeBlockWithReporters(attached);
			}
		}

		removeBlock(block);
	}

	function cancelDrag():Void
	{
		if (isDragging && draggingBlock != null)
			draggingBlock.isDragging = false;

		pendingDragBlock = null;
		pendingPan = false;
		isDragging = false;
		draggingBlock = null;
		isPanning = false;
		tilePress = null;
		tileDragStarted = false;
		railPress = null;
		chipPress = null;
		chipsDragging = false;
		sheetDragging = false;
		isDraggingScroll = false;

		if (trashCan != null)
			trashCan.scale.set(1.0, 1.0);
	}

	// --- Snapping ---

	function checkSnapping(current:Block):Void
	{
		var worldPos:FlxPoint = getPointerWorldPosition(camEditor);
		var proposedX:Float = worldPos.x - (dragOffset.x / zoomLevel);
		var proposedY:Float = worldPos.y - (dragOffset.y / zoomLevel);
		var bestDist:Float = SNAP_DISTANCE;

		for (other in blockContainer.members)
		{
			if (other == null || other == current || other.isReporter || !other.active || !other.visible)
				continue;
			if (other.nextBlock != null)
				continue;

			var targetY:Float = other.y + other.height;
			var distance:Float = distanceBetween(proposedX, proposedY, other.x, targetY);
			if (distance < bestDist)
				bestDist = distance;
		}

		if (bestDist < SNAP_DISTANCE)
			current.alpha = 0.85;
		else if (!isPointerOverScreenSprite(trashCan))
			current.alpha = 1.0;
	}

	function checkInputSnapping(current:Block):Void
	{
		var worldPos:FlxPoint = getPointerWorldPosition(camEditor);
		var proposedX:Float = worldPos.x - (dragOffset.x / zoomLevel);
		var proposedY:Float = worldPos.y - (dragOffset.y / zoomLevel);
		var bestDist:Float = SNAP_DISTANCE;

		for (other in blockContainer.members)
		{
			if (other == null || other == current || !other.active || !other.visible)
				continue;

			if (other.inputFields == null)
				continue;

			for (input in other.inputFields)
			{
				if (input == null || input.attachedBlock != null)
					continue;

				var distance:Float = distanceBetween(proposedX, proposedY, input.bg.x, input.bg.y);
				if (distance < bestDist)
					bestDist = distance;
			}
		}

		if (bestDist < SNAP_DISTANCE)
			current.alpha = 0.85;
		else if (!isPointerOverScreenSprite(trashCan))
			current.alpha = 1.0;
	}

	function applySnapping(current:Block):Void
	{
		var best:Block = null;
		var bestDist:Float = SNAP_DISTANCE;
		var bestX:Float = current.x;
		var bestY:Float = current.y;

		for (other in blockContainer.members)
		{
			if (other == null || other == current || other.isReporter || !other.active || !other.visible)
				continue;
			if (other.nextBlock != null)
				continue;

			var targetY:Float = other.y + other.height;
			var distance:Float = distanceBetween(current.x, current.y, other.x, targetY);
			if (distance < bestDist)
			{
				best = other;
				bestDist = distance;
				bestX = other.x;
				bestY = targetY;
			}
		}

		if (best == null)
		{
			current.isSnapped = false;
			return;
		}

		current.x = bestX;
		current.y = bestY;
		FlxTween.tween(current, {x: bestX, y: bestY}, 0.08, {ease: FlxEase.quadOut});
		best.nextBlock = current;
		current.prevBlock = best;
		current.isSnapped = true;
		setStatus('Snapped!');
		playSound('scrollMenu');
	}

	function applyInputSnapping(current:Block):Void
	{
		for (other in blockContainer.members)
		{
			if (other == null || other == current || !other.active || !other.visible)
				continue;
			if (other.inputFields == null)
				continue;

			for (input in other.inputFields)
			{
				if (input == null || input.attachedBlock != null)
					continue;

				var distance:Float = distanceBetween(current.x, current.y, input.bg.x, input.bg.y);
				if (distance >= SNAP_DISTANCE)
					continue;

				input.attachedBlock = current;
				current.parentInput = input;
				current.x = input.bg.x;
				current.y = input.bg.y;
				FlxTween.tween(current, {x: input.bg.x, y: input.bg.y}, 0.08, {ease: FlxEase.quadOut});
				other.recalculateSize();
				setStatus('Attached to input!');
				playSound('scrollMenu');
				return;
			}
		}
	}

	static function distanceBetween(x1:Float, y1:Float, x2:Float, y2:Float):Float
	{
		var dx:Float = x1 - x2;
		var dy:Float = y1 - y2;
		return Math.sqrt(dx * dx + dy * dy);
	}

	// ============================================================================================
	// Tooltips
	// ============================================================================================

	function handleTooltips(elapsed:Float):Void
	{
		if (tooltipBox == null || tooltipText == null)
			return;

		if (getPrimaryTouch() != null
			|| pointerBlocked()
			|| isPointerOverTopBar()
			|| isPointerOverTimeline()
			|| isPointerOverStatusBar())
		{
			showTooltip(null);
			return;
		}

		var description:String = '';

		if (isPointerOverPalette())
		{
			var tile:PaletteTile = tileAt(getPointerScreenX(), getPointerScreenY());
			if (tile != null && tile.data != null && tile.data.description != null)
				description = tile.data.description;
		}
		else if (isPointerOverWorkspace())
		{
			var worldPos:FlxPoint = FlxG.mouse.getWorldPosition(camEditor);
			var block:Block = findBlockAt(worldPos.x, worldPos.y);
			if (block != null && block.blockData != null && block.blockData.description != null)
				description = block.blockData.description;
		}

		showTooltip(description);
	}

	// ============================================================================================
	// Context menu, prompts and block actions
	// ============================================================================================

	function isContextMenuOpen():Bool
	{
		return contextMenu != null && contextMenu.isOpen;
	}

	function closeContextMenu():Void
	{
		contextBlock = null;
		if (contextMenu != null)
			contextMenu.close();
	}

	function openContextMenuAtPointer():Void
	{
		if (contextMenu == null || (prompt != null && prompt.isShowing()))
			return;

		var worldPos:FlxPoint = getPointerWorldPosition(camEditor);
		var block:Block = isPointerOverWorkspace() ? findBlockAt(worldPos.x, worldPos.y) : null;
		contextBlock = block;
		contextMenuX = FlxMath.bound(getPointerScreenX(), inset, Math.max(inset, BlockLayout.width - contextMenuWidth - inset));
		contextMenuY = getPointerScreenY();
		if (contextMenuY + contextMenuHeight > BlockLayout.height - BlockLayout.statusHeight())
			contextMenuY = BlockLayout.height - BlockLayout.statusHeight() - contextMenuHeight;
		if (contextMenuY < barHeight + gap)
			contextMenuY = barHeight + gap;

		pointerSwallowed = true;
		contextMenu.openAt(contextMenuX, contextMenuY, block, onContextAction);
		playSound('scrollMenu');
	}

	function onContextAction(action:String):Void
	{
		pointerSwallowed = true;

		var block:Block = contextBlock;
		contextBlock = null;

		switch (action)
		{
			case 'duplicate':
				if (block != null)
					duplicateBlock(block);
			case 'delete':
				if (block != null)
					deleteBlock(block);
			case 'editInputs':
				if (block != null)
					focusFirstInput(block);
			case 'detach':
				if (block != null)
					detachBlock(block);
			case 'addMarker':
				addMarkerAtCurrentStep(block);
			case 'clearWorkspace':
				askClearWorkspace();
			case 'attachEvent':
				askAttachEvent();
			case 'reloadBlocks':
				reloadBlockLibrary();
			default:
				setStatus('Unknown action "' + action + '"');
		}
	}

	function focusFirstInput(block:Block):Void
	{
		if (block == null || block.inputFields == null || block.inputFields.length == 0)
		{
			setStatus((block == null) ? 'No block selected' : 'This block has no inputs');
			return;
		}

		block.inputFields[0].focus(true);
	}

	function askClearWorkspace():Void
	{
		var workspace:String = activeWorkspaceId();
		var count:Int = workspaceBlocks(workspace).length;
		if (count == 0)
		{
			setStatus('This workspace is already empty');
			return;
		}

		askPrompt('Reset workspace', 'Delete all ' + count + ' blocks of ' + workspaceLabel(workspace) + '?', ['Reset'], function(choice:Int)
		{
			if (choice != 0)
				return;

			pushUndo();
			for (root in workspaceRoots(workspace))
				removeStack(root);
			for (block in blockContainer.members.copy())
			{
				if (workspaceOf(block) == workspace)
					removeStack(block);
			}

			markDirty();
			updateWorkspaceVisibility();
			refreshBlockCount();
			setStatus('Workspace cleared');
			playSound('cancelMenu');
		});
	}

	function askAttachEvent():Void
	{
		var marker:TimelineMarker = activeMarker();
		if (marker == null)
		{
			setStatus('Select a marker on the timeline first');
			playSound('cancelMenu');
			return;
		}

		var names:Array<String> = chartEventNames();
		if (names.length == 0)
		{
			setStatus('This song has no chart events');
			playSound('cancelMenu');
			return;
		}

		var options:Array<String> = names;
		if (options.length > MAX_EVENT_OPTIONS)
			options = options.slice(0, MAX_EVENT_OPTIONS);

		askPrompt('Attach chart event', 'Pick the event that also runs this marker:', options, function(choice:Int)
		{
			if (choice < 0 || choice >= options.length)
				return;

			pushUndo();
			marker.eventName = options[choice];
			timeline.addMarker(marker);
			timeline.markDirty();
			markDirty();
			refreshMarkerTabs();
			setStatus('Marker reacts to event "' + options[choice] + '"');
			playSound('confirmMenu');
		});
	}

	function workspaceLabel(workspace:String):String
	{
		if (workspace == GLOBAL_WORKSPACE)
			return 'the global scripts';

		var marker:TimelineMarker = timeline.getMarker(workspace);
		return (marker == null) ? 'the marker' : ('marker ' + markerName(marker));
	}

	function askPrompt(title:String, body:String, options:Array<String>, callback:Int->Void):Void
	{
		if (prompt == null)
		{
			callback(0);
			return;
		}

		prompt.uiScale = BlockLayout.scale;
		prompt.ask(title, body, options, callback);
	}

	// ============================================================================================
	// Input fields, soft keyboard, virtual keyboard
	// ============================================================================================

	function installInputHooks():Void
	{
		Block.requestTextEdit = onRequestTextEdit;
		Block.requestCodeEdit = onRequestCodeEdit;
		Block.onAnyValueChanged = onBlockValueChanged;
	}

	function onBlockValueChanged():Void
	{
		if (searchField != null && searchField.isFocused)
		{
			// Typing in the search box filters the palette; it does not change the project.
			var current:String = (searchField.value == null) ? '' : Std.string(searchField.value);
			if (current != searchText)
			{
				searchText = current;
				refreshPaletteVisibility();
			}
			return;
		}

		markDirty();
	}

	function onRequestTextEdit(field:InputField):Void
	{
		beginFieldEdit(field, false);
	}

	function onRequestCodeEdit(field:InputField):Void
	{
		beginFieldEdit(field, true);
	}

	function beginFieldEdit(field:InputField, isCode:Bool):Void
	{
		if (field == null || settings == null)
			return;

		if (virtualKeyboard != null && virtualKeyboard.isOpen())
			closeFieldEditor();

		editingField = field;
		field.focus(false);

		var initial:String = (field.value == null) ? '' : Std.string(field.value);
		var multiline:Bool = isCode || field.isCode();
		var nativeKeyboard:Bool = BlockSoftKeyboard.isNativeAvailable() && !settings.forceVirtualKeyboard;
		var autoOpen:Bool = nativeKeyboard || multiline;
		#if web
		autoOpen = true;
		#end

		if (!autoOpen)
		{
			// Desktop keeps the legacy physical-key typing of `InputField`.
			Block.externalEditorActive = false;
			setStatus('Editing ' + inputLabel(field) + ' - type and press Enter');
			return;
		}

		if (nativeKeyboard)
		{
			BlockSoftKeyboard.targetRect = fieldScreenRect(field);
			Block.externalEditorActive = true;
			BlockSoftKeyboard.open(initial, multiline, onSoftKeyboardText, onSoftKeyboardClosed);
			setStatus('Editing ' + inputLabel(field));
			return;
		}

		if (virtualKeyboard == null)
			return;

		Block.externalEditorActive = true;
		virtualKeyboard.setLayout(multiline ? BlockVirtualKeyboard.LAYOUT_CODE : BlockVirtualKeyboard.LAYOUT_LETTERS);
		virtualKeyboard.open(initial, multiline);
		setStatus('Editing ' + inputLabel(field));
	}

	function onSoftKeyboardText(text:String):Void
	{
		if (editingField == null)
			return;

		editingField.setValue(text == null ? '' : text);
	}

	function onSoftKeyboardClosed():Void
	{
		if (editingField != null)
		{
			editingField.unfocus();
			editingField = null;
		}
	}

	function onVirtualKeyboardClosed():Void
	{
		onSoftKeyboardClosed();
	}

	function onVirtualKey(key:String):Void
	{
		if (editingField == null || key == null)
			return;

		switch (key)
		{
			case 'backspace':
				editingField.backspace();
			case 'clear':
				editingField.setValue('');
			case 'space':
				editingField.appendText(' ');
			case 'tab':
				editingField.appendText(BlockVirtualKeyboard.TAB_SPACES);
			case 'enter':
				if (editingField.isCode())
					editingField.appendText('\n');
				else
					closeFieldEditor();
			case 'shift':
				// The sheet owns the shift state; nothing to mirror.
			case 'close':
				closeFieldEditor();
			default:
				if (key.length == 1)
					editingField.appendText(key);
		}
	}

	function closeFieldEditor():Void
	{
		Block.externalEditorActive = false;

		if (virtualKeyboard != null && virtualKeyboard.isOpen())
			virtualKeyboard.close();

		if (BlockSoftKeyboard.isOpen())
			BlockSoftKeyboard.close();

		if (editingField != null)
		{
			editingField.unfocus();
			editingField = null;
		}
	}

	function inputLabel(field:InputField):String
	{
		if (field == null || field.placeholder == null || field.placeholder.length == 0)
			return 'value';

		return field.placeholder;
	}

	function fieldScreenRect(field:InputField):Rectangle
	{
		var camera:FlxCamera = camEditor;
		if (field.bg != null && field.bg.cameras != null && field.bg.cameras.length > 0 && field.bg.cameras[0] != null)
			camera = field.bg.cameras[0];

		var x:Float = field.bg.x - camera.scroll.x + camera.x;
		var y:Float = field.bg.y - camera.scroll.y + camera.y;
		return new Rectangle(x, y, Math.max(field.width, 48), Math.max(field.height, 32));
	}

	function unfocusFieldsOutside(worldPos:FlxPoint):Void
	{
		if (virtualKeyboard != null && virtualKeyboard.isOpen())
			return;
		if (BlockSoftKeyboard.isOpen())
			return;

		for (block in blockContainer.members)
		{
			if (block == null || block.inputFields == null)
				continue;

			for (input in block.inputFields)
			{
				if (input == null || !input.isFocused)
					continue;
				if (worldPos.x >= input.bg.x
					&& worldPos.x <= input.bg.x + input.width
					&& worldPos.y >= input.bg.y
					&& worldPos.y <= input.bg.y + input.height)
					continue;

				input.unfocus();
			}
		}

		if (editingField != null && !editingField.isFocused)
			editingField = null;
	}

	// ============================================================================================
	// Song control, save and live reload
	// ============================================================================================

	function toggleSongPause():Void
	{
		if (PlayState.instance == null)
		{
			setStatus('No song is running');
			return;
		}

		if (songPaused)
		{
			resumeSong();
			setStatus('Song resumed');
		}
		else
		{
			songPaused = true;
			pauseAudio();
			freezeSongClock();
			syncPauseButton();
			setStatus('Song paused - the song clock is frozen, the editor keeps running');
		}

		playSound('scrollMenu');
	}

	function resumeSong():Void
	{
		songPaused = false;
		frozenSongPosition = -1;
		resumeAudio();
		syncPauseButton();
	}

	/** Holds the song clock where the audio was stopped, so the two stay aligned on resume. */
	function freezeSongClock():Void
	{
		frozenSongPosition = Conductor.songPosition;
		BlockScriptRuntime.seekTo(frozenSongPosition);
	}

	function syncPauseButton():Void
	{
		setButtonText(pauseButton, songPaused ? 'Resume' : 'Pause song');
		setButtonColor(pauseButton, songPaused ? COLOR_BUTTON_GOOD : COLOR_BUTTON_WARN);
	}

	function isMusicPlaying():Bool
	{
		return FlxG.sound != null && FlxG.sound.music != null && FlxG.sound.music.playing;
	}

	function pauseAudio():Void
	{
		if (FlxG.sound != null && FlxG.sound.music != null)
			FlxG.sound.music.pause();

		var playState:PlayState = PlayState.instance;
		if (playState == null)
			return;

		if (playState.vocals != null)
			playState.vocals.pause();
		if (playState.opponentVocals != null)
			playState.opponentVocals.pause();
	}

	function resumeAudio():Void
	{
		if (FlxG.sound != null && FlxG.sound.music != null)
			FlxG.sound.music.resume();

		var playState:PlayState = PlayState.instance;
		if (playState == null)
			return;

		if (playState.vocals != null)
			playState.vocals.resume();
		if (playState.opponentVocals != null)
			playState.opponentVocals.resume();
	}

	function toggleLiveReload():Void
	{
		liveReload = !liveReload;
		if (settings != null)
		{
			settings.autoReload = liveReload;
			BlockSerializer.saveSettings(settings);
		}

		setButtonText(liveButton, liveReload ? 'Live on' : 'Live off');
		setButtonColor(liveButton, liveReload ? COLOR_BUTTON_GOOD : COLOR_BUTTON);
		setStatus(liveReload ? 'Live reload on: saving updates the running song' : 'Live reload off');
		playSound('scrollMenu');
	}

	function currentLua():String
	{
		return BlockLuaGenerator.generate(workspaceRoots(GLOBAL_WORKSPACE), timelineEntries());
	}

	function saveAndReload():Void
	{
		if (settings == null)
			return;

		var script:String = currentLua();
		var path:String = BlockFileIO.save(settings, script, songName());
		if (path == null || path.length == 0)
		{
			setStatus('Save failed - check the target folder in "Save as"');
			playSound('cancelMenu');
			return;
		}

		dirty = false;
		saveCache();

		if (liveReload && BlockScriptRuntime.isAvailable())
		{
			if (BlockScriptRuntime.reload(path, settings.scriptName))
				setStatus('Saved and live: ' + path);
			else
				setStatus('Saved ' + path + ' - the live reload failed');
		}
		else
		{
			setStatus('Saved ' + path);
		}

		playSound('confirmMenu');
	}

	function testInSong():Void
	{
		if (PlayState.instance != null)
		{
			setStatus('A song is already running - use Save or Live instead');
			playSound('cancelMenu');
			return;
		}

		#if sys
		var script:String = currentLua();
		var path:String = 'mods/data/testScript.lua';
		if (!FileSystem.exists('mods/data'))
			FileSystem.createDirectory('mods/data');
		File.saveContent(path, script);

		PlayState.isBlockTest = true;
		PlayState.blockScriptPath = path;

		if (PlayState.SONG == null)
			PlayState.SONG = Song.loadFromJson('tutorial', 'tutorial');

		LoadingState.loadAndSwitchState(new PlayState());
		#else
		setStatus('Testing a script needs a filesystem');
		#end
	}

	// ============================================================================================
	// ESC / back press
	// ============================================================================================

	function hookPreUpdate():Void
	{
		if (preUpdateHooked)
			return;

		// The listener is kept in a field so `remove()` gets the very same reference back.
		preUpdateListener = function():Void
		{
			onPreUpdate();
		};
		FlxG.signals.preUpdate.add(preUpdateListener);
		preUpdateHooked = true;
	}

	function unhookPreUpdate():Void
	{
		if (!preUpdateHooked || preUpdateListener == null)
			return;

		FlxG.signals.preUpdate.remove(preUpdateListener);
		preUpdateListener = null;
		preUpdateHooked = false;
	}

	/**
	 * Runs before `FlxGame` hands the frame's key state to the states, so ESC (and the Android back
	 * gesture) are taken away from the running song: otherwise `PlayState` would open its pause menu
	 * on the very press that is meant to close the editor.
	 */
	function onPreUpdate():Void
	{
		if (parentState == null || parentState.subState != this)
			return;

		var escape:Bool = FlxG.keys.justPressed.ESCAPE;
		var back:Bool = false;
		#if android
		back = FlxG.android.justReleased.BACK;
		#end

		if (!escape && !back)
			return;

		FlxG.keys.reset();
		#if android
		FlxG.android.reset();
		#end

		handleEscape();
	}

	function handleEscape():Void
	{
		if (prompt != null && prompt.isShowing())
		{
			prompt.hide();
			return;
		}

		if (virtualKeyboard != null && virtualKeyboard.isOpen())
		{
			closeFieldEditor();
			return;
		}

		if (isContextMenuOpen())
		{
			closeContextMenu();
			return;
		}

		if (panelOpen)
		{
			closeOpenPanel();
			return;
		}

		if (hasFocusedField())
		{
			closeFieldEditor();
			return;
		}

		exitEditor();
	}

	function exitEditor():Void
	{
		// Closing the editor always hands a playing song back, whatever the pause toggle was set to.
		if (songPaused)
			resumeSong();

		saveCache();
		close();
	}

	// ============================================================================================
	// Platform helpers
	// ============================================================================================

	function playSound(key:String):Void
	{
		if (FlxG.sound == null)
			return;

		var sound = Paths.sound(key);
		if (sound != null)
			FlxG.sound.play(sound);
	}

	#if android
	/**
	 * Same pad the standalone editor added, used for its X/Y zoom buttons. It is built directly
	 * instead of through `addTouchPad()` so the running song keeps its own pad bindings.
	 */
	function setupEditorTouchPad():Void
	{
		if (editorTouchPad != null)
		{
			remove(editorTouchPad, true);
			editorTouchPad.destroy();
			editorTouchPad = null;
		}

		editorTouchPad = new FlxTouchPad('FULL', 'A_B_X_Y');
		add(editorTouchPad);
		editorTouchPad.cameras = [camHUD];
	}
	#end
}

/** One palette section: the category, its header row and every block tile under it. */
private class PaletteSection
{
	public var category:BlockCategory;
	public var header:FlxText;
	public var line:FlxSprite;
	public var tiles:Array<PaletteTile> = [];
	public var headerY:Float = 0;
	public var headerHeight:Float = 0;
	public var contentTop:Float = 0;
	public var contentBottom:Float = 0;

	public function new(category:BlockCategory, cam:FlxCamera, headerSize:Int)
	{
		this.category = category;

		header = new FlxText(0, 0, 100, (category == null) ? '' : category.name, headerSize);
		header.setFormat(Paths.font('vcr.ttf'), headerSize, (category == null) ? FlxColor.WHITE : category.color, LEFT);
		header.scrollFactor.set(0, 0);
		header.cameras = [cam];

		line = new FlxSprite().makeGraphic(1, 1, (category == null) ? FlxColor.WHITE : category.color);
		line.alpha = 0.55;
		line.scrollFactor.set(0, 0);
		line.cameras = [cam];
	}

	public function setHeaderVisible(visible:Bool):Void
	{
		header.visible = visible;
		line.visible = visible;
	}

	public function destroy():Void
	{
		FlxDestroyUtil.destroy(header);
		FlxDestroyUtil.destroy(line);
		header = null;
		line = null;
		tiles = [];
	}
}

/**
 * One block tile of the palette: drawn like the block it spawns (a rounded body in the category
 * colour, a darker outline and a three dot grip on the left) with its name left aligned.
 */
private class PaletteTile
{
	public var data:BlockData;
	public var category:BlockCategory;
	public var bg:FlxSprite;
	public var label:FlxText;
	public var x:Float = 0;
	public var y:Float = 0;
	public var w:Float = 0;
	public var h:Float = 0;

	var tint:Int = 0xFF24283B;
	var gripDots:Bool = true;
	var compactMode:Bool = false;

	public function new(data:BlockData, category:BlockCategory, w:Float, h:Float, cam:FlxCamera, compact:Bool)
	{
		this.data = data;
		this.category = category;
		this.w = Math.max(1, w);
		this.h = Math.max(1, h);
		compactMode = compact;
		gripDots = !compact;
		tint = (data == null) ? 0xFF24283B : data.color;

		var text:String = compact ? categoryIcon(category) : ((data == null) ? '' : data.label);
		var fontSize:Int = BlockLayout.font('body');

		bg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		bg.scrollFactor.set(0, 0);
		bg.cameras = [cam];
		BlockCodeEditorSubstate.paintRounded(bg, this.w, this.h, tint, gripDots);

		label = new FlxText(0, 0, this.w, text, fontSize);
		label.setFormat(Paths.font('vcr.ttf'), fontSize, FlxColor.WHITE, compact ? CENTER : LEFT, FlxTextBorderStyle.OUTLINE, 0x66000000);
		label.borderSize = 1.5;
		label.scrollFactor.set(0, 0);
		label.cameras = [cam];
		label.wordWrap = false;
		label.updateHitbox();

		place(0, 0, this.w, this.h);
	}

	static function categoryIcon(category:BlockCategory):String
	{
		if (category == null || category.icon == null)
			return '?';

		return category.icon;
	}

	/** Moves (and when needed resizes) the tile inside the palette list. */
	public function place(x:Float, y:Float, w:Float, h:Float):Void
	{
		this.x = x;
		this.y = y;

		var wantedW:Float = Math.max(1, w);
		var wantedH:Float = Math.max(1, h);

		if (this.w != wantedW || this.h != wantedH)
		{
			this.w = wantedW;
			this.h = wantedH;
			BlockCodeEditorSubstate.paintRounded(bg, this.w, this.h, tint, gripDots);
		}

		bg.setPosition(x, y);

		var offset:Float = compactMode ? 0 : Math.max(18, Math.round(this.h * 0.95));
		var padRight:Float = Math.max(6, this.h * 0.2);

		label.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('body'), FlxColor.WHITE, compactMode ? CENTER : LEFT, FlxTextBorderStyle.OUTLINE, 0x66000000);
		label.fieldWidth = Std.int(Math.max(20, this.w - offset - padRight));
		label.wordWrap = false; // a tile is one row tall: the name has to stay on one line
		label.x = x + offset;
		label.y = y + Math.max(0, (this.h - label.height) * 0.5);
	}

	public function setVisible(visible:Bool):Void
	{
		bg.visible = visible;
		label.visible = visible;
	}

	public function isShown():Bool
	{
		return bg != null && bg.visible && label != null && label.visible;
	}

	public function destroy():Void
	{
		FlxDestroyUtil.destroy(bg);
		FlxDestroyUtil.destroy(label);
		bg = null;
		label = null;
	}
}

/**
 * A category control of the palette: the square icon button of the landscape rail or a wide chip
 * of the portrait chip row. The body is painted once as a white rounded rect and tinted, so
 * activating it is a colour change and not a new bitmap.
 */
private class CategoryButton
{
	public var category:BlockCategory;
	public var bg:FlxSprite;
	public var label:FlxText;
	public var rect:Rect;
	public var width:Float = 0;
	public var height:Float = 0;

	var baseX:Float = 0;
	var baseY:Float = 0;
	var textSize:Int = 13;
	var active:Bool = false;
	var dimmed:Bool = false;

	public function new(category:BlockCategory, x:Float, y:Float, w:Float, h:Float, cam:FlxCamera, text:String, textSize:Int)
	{
		this.category = category;
		this.textSize = textSize;
		width = Math.max(1, w);
		height = Math.max(1, h);

		bg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		bg.scrollFactor.set(0, 0);
		bg.cameras = [cam];
		BlockCodeEditorSubstate.paintRounded(bg, width, height, BlockCodeEditorSubstate.COLOR_BUTTON, false);

		label = new FlxText(0, 0, width, (text == null) ? '' : text, textSize);
		label.setFormat(Paths.font('vcr.ttf'), textSize, FlxColor.WHITE, CENTER);
		label.scrollFactor.set(0, 0);
		label.cameras = [cam];
		label.wordWrap = false;
		label.updateHitbox();

		rect = {
			x: x,
			y: y,
			w: width,
			h: height
		};
		apply();
	}

	function colour():Int
	{
		return (category == null) ? BlockCodeEditorSubstate.COLOR_BUTTON : category.color;
	}

	public function moveTo(x:Float, y:Float):Void
	{
		baseX = x;
		baseY = y;
		rect.x = x;
		rect.y = y;
		apply();
	}

	/** Shifts the control inside its row (used by the horizontal chip scroll). */
	public function setOffset(dx:Float):Void
	{
		rect.x = baseX + dx;
		rect.y = baseY;
		apply();
	}

	function apply():Void
	{
		bg.setPosition(rect.x, rect.y);
		label.fieldWidth = Std.int(width);
		label.wordWrap = false;
		label.x = rect.x;
		label.y = rect.y + Math.max(0, (height - label.height) * 0.5);
	}

	public function setActive(value:Bool):Void
	{
		active = value;
		refreshColours();
	}

	public function setDimmed(value:Bool):Void
	{
		dimmed = value;
		refreshColours();
	}

	function refreshColours():Void
	{
		if (bg == null || label == null)
			return;

		var tint:Int = active ? colour() : BlockCodeEditorSubstate.COLOR_BUTTON;
		if (dimmed)
			tint = FlxColor.interpolate(tint, BlockCodeEditorSubstate.COLOR_SIDEBAR_BG, 0.6);

		bg.color = tint;
		label.setFormat(Paths.font('vcr.ttf'), textSize, active ? FlxColor.WHITE : colour(), CENTER);
		label.alpha = dimmed ? 0.5 : 1;
		label.updateHitbox();
		apply();
	}

	public function destroy():Void
	{
		FlxDestroyUtil.destroy(bg);
		FlxDestroyUtil.destroy(label);
		bg = null;
		label = null;
	}
}

/**
 * Centred prompt the editor draws itself: title, explanation and one button per choice plus
 * `Cancel`, which reports `-1`. Used for marker removal, chart-event picking and workspace reset.
 */
private class PromptBox extends FlxSpriteGroup
{
	static inline var COLOR_PANEL:Int = 0xFF24283B;
	static inline var COLOR_TITLE:Int = 0xFFC0CAF5;
	static inline var COLOR_BODY:Int = 0xFF565F89;
	static inline var COLOR_CHOICE:Int = 0xFF3D59A1;
	static inline var COLOR_CANCEL:Int = 0xFF414868;
	static inline var HEADER_HEIGHT:Float = 92;

	var panel:FlxSprite;
	var titleText:FlxText;
	var bodyText:FlxText;
	var choices:Array<FlxButton> = [];
	var choiceCallback:Int->Void = null;
	var choiceCount:Int = 0;

	public var uiScale:Float = 1;

	var showing:Bool = false;

	public function new(scale:Float)
	{
		super(0, 0);

		uiScale = (scale > 0) ? scale : 1;

		panel = new FlxSprite();
		panel.scrollFactor.set(0, 0);
		add(panel);

		titleText = new FlxText(0, 0, 0, '', Std.int(18 * uiScale));
		titleText.setFormat(Paths.font('vcr.ttf'), Std.int(18 * uiScale), COLOR_TITLE, LEFT);
		titleText.scrollFactor.set(0, 0);
		add(titleText);

		bodyText = new FlxText(0, 0, 0, '', Std.int(14 * uiScale));
		bodyText.setFormat(Paths.font('vcr.ttf'), Std.int(14 * uiScale), COLOR_BODY, LEFT);
		bodyText.scrollFactor.set(0, 0);
		add(bodyText);

		visible = false;
	}

	public function isShowing():Bool
	{
		return showing;
	}

	public function ask(title:String, body:String, options:Array<String>, callback:Int->Void):Void
	{
		choiceCallback = callback;
		titleText.text = (title == null) ? '' : title;
		bodyText.text = (body == null) ? '' : body;

		var list:Array<String> = (options == null) ? [] : options;
		var rowHeight:Float = Math.max(48 * uiScale, 40);
		var width:Float = Math.min(FlxG.width - 60 * uiScale, 520 * uiScale);
		var height:Float = HEADER_HEIGHT * uiScale + (list.length + 1) * rowHeight;
		var boxX:Float = (FlxG.width - width) * 0.5;
		var boxY:Float = (FlxG.height - height) * 0.5;
		if (boxY < 0)
			boxY = 0;

		titleText.setFormat(Paths.font('vcr.ttf'), Std.int(18 * uiScale), COLOR_TITLE, LEFT);
		bodyText.setFormat(Paths.font('vcr.ttf'), Std.int(14 * uiScale), COLOR_BODY, LEFT);

		panel.makeGraphic(Std.int(width), Std.int(height), COLOR_PANEL);
		panel.setPosition(boxX, boxY);

		titleText.fieldWidth = Std.int(width - 24 * uiScale);
		titleText.setPosition(boxX + 12 * uiScale, boxY + 12 * uiScale);
		bodyText.fieldWidth = Std.int(width - 24 * uiScale);
		bodyText.setPosition(boxX + 12 * uiScale, boxY + 12 * uiScale + titleText.height + 6 * uiScale);

		var buttonWidth:Float = width - 24 * uiScale;
		var buttonX:Float = boxX + 12 * uiScale;
		var buttonY:Float = boxY + HEADER_HEIGHT * uiScale;

		ensureChoices(list.length + 1);

		var used:Int = 0;
		for (index in 0...list.length)
		{
			layoutChoice(index, list[index], buttonX, buttonY, buttonWidth, rowHeight - 6 * uiScale, COLOR_CHOICE);
			buttonY += rowHeight;
			used++;
		}

		// Cancel is the always-present last choice and reports -1.
		layoutChoice(used, 'Cancel', buttonX, buttonY, buttonWidth, rowHeight - 6 * uiScale, COLOR_CANCEL);
		used++;

		for (index in used...choices.length)
			choices[index].visible = false;

		choiceCount = used;
		showing = true;
		visible = true;
	}

	public function hide():Void
	{
		showing = false;
		visible = false;
		choiceCallback = null;
		choiceCount = 0;

		for (button in choices)
		{
			if (button != null)
				button.visible = false;
		}
	}

	/** Buttons are pooled: destroying one from inside its own click handler is not safe. */
	function ensureChoices(count:Int):Void
	{
		while (choices.length < count)
		{
			var index:Int = choices.length;
			var button:FlxButton = new FlxButton(0, 0, '', function()
			{
				pick(index);
			});
			button.makeGraphic(200, Std.int(Math.max(40 * uiScale, 40)), COLOR_CHOICE);
			if (button.label != null)
				button.label.setFormat(Paths.font('vcr.ttf'), Std.int(14 * uiScale), FlxColor.WHITE, CENTER);

			choices.push(button);
			add(button);
		}
	}

	function layoutChoice(index:Int, label:String, x:Float, y:Float, width:Float, height:Float, color:Int):Void
	{
		if (index < 0 || index >= choices.length)
			return;

		var button:FlxButton = choices[index];
		var pixelWidth:Int = Std.int(Math.max(width, 1));
		var pixelHeight:Int = Std.int(Math.max(height, 40 * uiScale));

		button.makeGraphic(pixelWidth, pixelHeight, color);
		if (button.label != null)
		{
			button.label.text = (label == null) ? '' : label;
			button.label.setFormat(Paths.font('vcr.ttf'), Std.int(14 * uiScale), FlxColor.WHITE, CENTER);
			button.label.fieldWidth = pixelWidth;
		}

		var offset:Float = (button.height - button.label.height) * 0.5;
		if (offset < 0)
			offset = 0;
		for (point in button.labelOffsets)
		{
			if (point != null)
				point.set(point.x, offset);
		}

		button.setPosition(x, y);
		button.visible = true;
		button.status = FlxButtonState.NORMAL;
	}

	function pick(index:Int):Void
	{
		// `index` is the position in the pool, which is the position in the option list; the last
		// button in use is Cancel and reports -1.
		var choice:Int = (index >= choiceCount - 1) ? -1 : index;
		var callback:Int->Void = choiceCallback;
		hide();

		if (callback != null)
			callback(choice);
	}
}
