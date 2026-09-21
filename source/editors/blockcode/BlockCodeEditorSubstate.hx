package editors.blockcode;

import editors.blockcode.Block.InputField;
import editors.blockcode.BlockTypes.BlockCategory;
import editors.blockcode.BlockTypes.BlockCodeEditorSettings;
import editors.blockcode.BlockTypes.BlockData;
import editors.blockcode.BlockTypes.BlockProject;
import editors.blockcode.BlockTypes.ImportResult;
import editors.blockcode.BlockTypes.TimelineMarker;
import flixel.FlxState;
import flixel.addons.display.FlxGridOverlay;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.input.touch.FlxTouch;
import flixel.ui.FlxButton;
import flixel.ui.FlxButton.FlxButtonState;
import openfl.geom.Rectangle;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * The block-code editor of Parker Engine as a substate on top of a running `PlayState`.
 *
 * This is `editors.BlockCodeEditorState` rebuilt for the "edit while the song plays" workflow:
 * the same workspace, sidebar, snapping, panning and zooming, the same colours and the same
 * pointer helpers, but every sprite is put on one of three cameras this substate adds itself
 * (`camEditor` for the workspace, `camSidebar` for the 320px sidebar, `camHUD` on top) instead
 * of resetting the camera list the way a standalone state can.
 *
 * What the migration adds:
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

	// --- Layout ---
	public static inline var SIDEBAR_WIDTH:Float = 320;
	public static inline var CATEGORY_STRIP_WIDTH:Float = 70;
	public static inline var STATUS_HEIGHT:Float = 30;
	public static inline var TIMELINE_HEIGHT:Float = 120;
	public static inline var BASE_BUTTON_HEIGHT:Float = 44;
	public static inline var BASE_FONT_SIZE:Int = 14;
	public static inline var TOP_BAR_PADDING:Float = 5;
	public static inline var BLOCK_COUNTER_WIDTH:Float = 156;
	public static inline var ANDROID_SCALE:Float = 1.25;
	public static inline var SNAP_DISTANCE:Float = 30;
	public static inline var LONG_PRESS_TIME:Float = 0.5;
	public static inline var AUTOSAVE_INTERVAL:Float = 5;
	public static inline var MAX_UNDO:Int = 30;
	public static inline var STATUS_HOLD:Float = 3.5;
	public static inline var MIN_ZOOM:Float = 0.1;
	public static inline var MAX_ZOOM:Float = 3;
	public static inline var MAX_EVENT_OPTIONS:Int = 8;
	public static inline var TIMELINE_RIGHT_MARGIN:Float = 90;

	/** Workspace id of the global scripts; a marker id is the workspace id of its stack. */
	public static inline var GLOBAL_WORKSPACE:String = "";

	/** The editor currently on screen, so `closeIfOpen()` can find it. */
	public static var instance(default, null):BlockCodeEditorSubstate;

	// --- Cameras ---
	var camEditor:FlxCamera;
	var camHUD:FlxCamera;
	var camSidebar:FlxCamera;

	// --- Workspace ---
	var dimBackdrop:FlxSprite;
	var workspaceBg:FlxSprite;
	var gridBG:FlxSprite;
	var blockContainer:FlxTypedGroup<Block>;

	/** Which workspace (see `GLOBAL_WORKSPACE`) every block belongs to. */
	var blockWorkspace:Map<Block, String> = new Map();

	// --- Sidebar ---
	var categoryButtons:FlxTypedGroup<FlxButton>;
	var blockButtons:FlxTypedGroup<FlxButton>;
	var blockButtonMap:Map<FlxButton, BlockData> = new Map();
	var scrollTrack:FlxSprite;
	var scrollThumb:FlxSprite;
	var categories:Array<BlockCategory> = [];
	var categoryYPositions:Map<String, Float> = new Map();
	var categoryHeaders:Array<FlxText> = [];
	var totalSidebarHeight:Float = 0;

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
	var undoButton:FlxButton;
	var redoButton:FlxButton;
	var testButton:FlxButton;
	var closeButton:FlxButton;
	var markerButton:FlxButton;
	var barButtons:Array<FlxButton> = [];
	var barHeight:Float = 0;
	var buttonHeight:Float = BASE_BUTTON_HEIGHT;
	var mobileScale:Float = 1;

	var statusBar:FlxSprite;
	var statusText:FlxText;
	var statusHold:Float = 0;
	var blockCountText:FlxText;

	var trashCan:FlxSprite;
	var trashLabel:FlxText;
	var tooltipBox:FlxSprite;
	var tooltipText:FlxText;

	// --- Timeline ---
	var timeline:BlockTimeline;
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

	var isDraggingScroll:Bool = false;
	var scrollDragOffset:Float = 0;
	var sidebarDragLastY:Float = 0;

	var pressHeldTime:Float = 0;
	var pressStartX:Float = 0;
	var pressStartY:Float = 0;
	var pressConsumed:Bool = false;
	var pointerSwallowed:Bool = false;
	var contextMenuX:Float = 0;
	var contextMenuY:Float = 0;
	var contextMenuWidth:Float = 0;
	var contextMenuHeight:Float = 0;
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
		mobileScale = #if android ANDROID_SCALE #else 1 #end;
		buttonHeight = BASE_BUTTON_HEIGHT * mobileScale;
		barHeight = buttonHeight + TOP_BAR_PADDING * 2;

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

		createTopBar();
		createSidebar();
		createStatusBar();
		createTrashCan();
		createTooltip();
		createMarkerButton();
		createTimeline();
		createPanels();

		loadCategories();
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
		super.create();
	}

	override function destroy():Void
	{
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

		camSidebar = new FlxCamera(0, 0, Std.int(SIDEBAR_WIDTH), FlxG.height);
		camSidebar.bgColor.alpha = 0;

		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;

		// Never the default draw target: the song's own sprites have to keep drawing on their cameras.
		FlxG.cameras.add(camEditor, false);
		FlxG.cameras.add(camSidebar, false);
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
		if (camSidebar != null)
		{
			FlxG.cameras.remove(camSidebar, true);
			camSidebar = null;
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

		gridBG = FlxGridOverlay.create(40, 40, FlxG.width * 4, FlxG.height * 4, true, COLOR_GRID_LINE, COLOR_BG);
		if (gridBG != null)
		{
			gridBG.alpha = 0.4;
			gridBG.scrollFactor.set(0.5, 0.5);
			gridBG.screenCenter();
			gridBG.cameras = [camEditor];
			add(gridBG);
		}
	}

	// ============================================================================================
	// Top bar
	// ============================================================================================

	function createTopBar():Void
	{
		topBarBg = new FlxSprite().makeGraphic(FlxG.width, Std.int(barHeight), COLOR_BAR);
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
		undoButton = makeButton('Undo', undo, COLOR_BUTTON);
		redoButton = makeButton('Redo', redo, COLOR_BUTTON);
		testButton = makeButton('Test', testInSong, COLOR_BUTTON_GOOD);
		closeButton = makeButton('Close', exitEditor, COLOR_TRASH);

		layoutTopBar();
	}

	function layoutTopBar():Void
	{
		var raw:Array<FlxButton> = [
			globalTabButton,
			markerTabButton,
			pauseButton,
			liveButton,
			saveButton,
			saveAsButton,
			codeButton,
			filesButton,
			helpButton,
			undoButton,
			redoButton,
			testButton,
			closeButton
		];

		barButtons = [];
		for (button in raw)
		{
			if (button != null)
				barButtons.push(button);
		}

		var padding:Float = TOP_BAR_PADDING * mobileScale;
		var rightLimit:Float = FlxG.width - BLOCK_COUNTER_WIDTH - padding;
		var x:Float = padding;
		var y:Float = padding;

		for (button in barButtons)
		{
			if (x + button.width > rightLimit && x > padding)
			{
				x = padding;
				y += buttonHeight + padding;
			}

			button.setPosition(x, y);
			button.visible = true;
			x += button.width + padding;
		}

		var wanted:Float = y + buttonHeight + padding;
		if (Math.abs(wanted - barHeight) > 0.5)
		{
			barHeight = wanted;
			if (topBarBg != null)
				topBarBg.makeGraphic(FlxG.width, Std.int(barHeight), COLOR_BAR);
		}
	}

	function makeButton(label:String, callback:Void->Void, color:Int):FlxButton
	{
		var button:FlxButton = new FlxButton(0, 0, label, callback);
		button.makeGraphic(Std.int(buttonWidth(label)), Std.int(buttonHeight), color);
		button.visible = false;
		button.cameras = [camHUD];
		styleButtonLabel(button);
		// Buttons are only created here, so this is the one place that has to register them with
		// the substate: without it they exist, get positioned, and are never drawn.
		add(button);

		return button;
	}

	function buttonWidth(label:String):Float
	{
		var text:String = (label == null) ? '' : label;
		var estimated:Float = text.length * (BASE_FONT_SIZE * 0.62) * mobileScale + 22 * mobileScale;
		return Math.max(62 * mobileScale, estimated);
	}

	function styleButtonLabel(button:FlxButton):Void
	{
		if (button == null || button.label == null)
			return;

		button.label.setFormat(Paths.font('vcr.ttf'), Std.int(BASE_FONT_SIZE * mobileScale), FlxColor.WHITE, CENTER);
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

		button.makeGraphic(Std.int(Math.max(1, button.width)), Std.int(Math.max(1, button.height)), color);
		styleButtonLabel(button);
	}

	// ============================================================================================
	// Sidebar
	// ============================================================================================

	function createSidebar():Void
	{
		var strip:FlxSprite = new FlxSprite(0, 0).makeGraphic(Std.int(CATEGORY_STRIP_WIDTH), FlxG.height, COLOR_SIDEBAR_STRIP);
		strip.scrollFactor.set(0, 0);
		strip.cameras = [camSidebar];
		add(strip);

		var sidebarBg:FlxSprite = new FlxSprite(CATEGORY_STRIP_WIDTH,
			0).makeGraphic(Std.int(SIDEBAR_WIDTH - CATEGORY_STRIP_WIDTH), FlxG.height, COLOR_SIDEBAR_BG);
		sidebarBg.scrollFactor.set(0, 0);
		sidebarBg.cameras = [camSidebar];
		add(sidebarBg);

		var separator:FlxSprite = new FlxSprite(SIDEBAR_WIDTH - 1, 0).makeGraphic(1, FlxG.height, COLOR_SEPARATOR);
		separator.scrollFactor.set(0, 0);
		separator.cameras = [camSidebar];
		add(separator);

		categoryButtons = new FlxTypedGroup<FlxButton>();
		add(categoryButtons);

		blockButtons = new FlxTypedGroup<FlxButton>();
		add(blockButtons);

		scrollTrack = new FlxSprite(SIDEBAR_WIDTH - 10, 0).makeGraphic(10, FlxG.height, COLOR_SCROLL_TRACK);
		scrollTrack.scrollFactor.set(0, 0);
		scrollTrack.cameras = [camSidebar];
		add(scrollTrack);

		scrollThumb = new FlxSprite(SIDEBAR_WIDTH - 10, 0).makeGraphic(10, 50, COLOR_SCROLL_THUMB);
		scrollThumb.scrollFactor.set(0, 0);
		scrollThumb.cameras = [camSidebar];
		add(scrollThumb);
	}

	function loadCategories():Void
	{
		BlockLibrary.ensureLoaded();
		categories = BlockLibrary.categories;

		var categorySize:Float = Math.min(50 * mobileScale, CATEGORY_STRIP_WIDTH - 16);
		var categoryX:Float = (CATEGORY_STRIP_WIDTH - categorySize) * 0.5;
		var categoryY:Float = 20;
		var blockListX:Float = 80;
		var blockListY:Float = 20;
		var blockButtonWidth:Float = SIDEBAR_WIDTH - blockListX - 14;

		for (category in categories)
		{
			if (category == null)
				continue;

			var button:FlxButton = new FlxButton(categoryX, categoryY, '', function()
			{
				scrollToCategory(category.name);
			});
			button.makeGraphic(Std.int(categorySize), Std.int(categorySize), category.color);
			button.text = category.icon;
			button.cameras = [camSidebar];
			button.scrollFactor.set(0, 0);
			button.label.setFormat(Paths.font('vcr.ttf'), Std.int(24 * mobileScale), FlxColor.WHITE, CENTER);
			button.label.fieldWidth = Std.int(categorySize);
			for (point in button.labelOffsets)
			{
				if (point != null)
					point.set(point.x, (categorySize - button.label.height) * 0.5);
			}
			categoryButtons.add(button);

			categoryY += categorySize + 10 * mobileScale;

			categoryYPositions.set(category.name, blockListY);

			var header:FlxText = new FlxText(blockListX, blockListY, 0, category.name, Std.int(16 * mobileScale));
			header.setFormat(Paths.font('vcr.ttf'), Std.int(16 * mobileScale), category.color, LEFT);
			header.cameras = [camSidebar];
			add(header);
			categoryHeaders.push(header);
			blockListY += 30 * mobileScale;

			if (category.blocks == null)
				continue;

			for (block in category.blocks)
			{
				if (block == null)
					continue;

				var blockButton:FlxButton = new FlxButton(blockListX, blockListY, block.label, function()
				{
					addBlock(block);
				});
				blockButton.makeGraphic(Std.int(blockButtonWidth), Std.int(buttonHeight), block.color);
				blockButton.cameras = [camSidebar];
				blockButton.label.setFormat(Paths.font('vcr.ttf'), Std.int(BASE_FONT_SIZE * mobileScale), FlxColor.WHITE, CENTER);
				blockButton.label.fieldWidth = Std.int(blockButtonWidth);

				var offset:Float = (buttonHeight - blockButton.label.height) * 0.5;
				if (offset < 0)
					offset = 0;
				for (point in blockButton.labelOffsets)
				{
					if (point != null)
						point.set(point.x, offset);
				}

				blockButtonMap.set(blockButton, block);
				blockButtons.add(blockButton);
				blockListY += buttonHeight + 6 * mobileScale;
			}

			blockListY += 20 * mobileScale;
		}

		totalSidebarHeight = blockListY;

		// An external block config may have added a category the sidebar scroll maths never saw.
		camSidebar.scroll.y = 0;
	}

	/** Throws the sidebar buttons and headers away and builds them again from the library. */
	function rebuildSidebar():Void
	{
		for (button in categoryButtons.members.copy())
		{
			if (button == null)
				continue;
			categoryButtons.remove(button, true);
			button.destroy();
		}

		for (button in blockButtons.members.copy())
		{
			if (button == null)
				continue;
			blockButtons.remove(button, true);
			button.destroy();
		}

		for (header in categoryHeaders)
		{
			if (header == null)
				continue;
			remove(header);
			header.destroy();
		}

		categoryHeaders = [];
		blockButtonMap = new Map();
		categoryYPositions = new Map();
		totalSidebarHeight = 0;

		loadCategories();
	}

	/** The context menu's "reload blocks": picks up block configs a mod added while the song runs. */
	function reloadBlockLibrary():Void
	{
		BlockLibrary.reload();
		rebuildSidebar();
		setStatus('Block library reloaded - ' + BlockLibrary.allBlocks().length + ' blocks');
		playSound('confirmMenu');
	}

	function scrollToCategory(categoryName:String):Void
	{
		if (!categoryYPositions.exists(categoryName))
			return;

		var targetY:Float = categoryYPositions.get(categoryName);
		FlxTween.cancelTweensOf(camSidebar.scroll);
		FlxTween.tween(camSidebar.scroll, {y: targetY - 20}, 0.5, {ease: FlxEase.quartOut});
		setStatus('Jumped to ' + categoryName);
		playSound('scrollMenu');
	}

	// ============================================================================================
	// Status bar, block counter, trash, tooltip
	// ============================================================================================

	function createStatusBar():Void
	{
		statusBar = new FlxSprite(0, FlxG.height - STATUS_HEIGHT).makeGraphic(FlxG.width, Std.int(STATUS_HEIGHT), COLOR_STATUS_BAR);
		statusBar.scrollFactor.set(0, 0);
		statusBar.cameras = [camHUD];
		add(statusBar);

		statusText = new FlxText(10, FlxG.height - STATUS_HEIGHT + 6, FlxG.width - 20,
			'Ready - Drag to Move Blocks, Space+Drag to Pan, E/Q or Ctrl+Scroll to Zoom', 16);
		statusText.setFormat(Paths.font('vcr.ttf'), 16, COLOR_STATUS_TEXT);
		statusText.scrollFactor.set(0, 0);
		statusText.cameras = [camHUD];
		add(statusText);

		blockCountText = new FlxText(FlxG.width - BLOCK_COUNTER_WIDTH + 6, 10, BLOCK_COUNTER_WIDTH - 16, 'Blocks: 0', 20);
		blockCountText.setFormat(Paths.font('vcr.ttf'), 20, COLOR_BLOCK_COUNT, RIGHT);
		blockCountText.scrollFactor.set(0, 0);
		blockCountText.cameras = [camHUD];
		add(blockCountText);
	}

	function createTrashCan():Void
	{
		trashCan = new FlxSprite(FlxG.width - 80, FlxG.height - 100).makeGraphic(60, 60, COLOR_TRASH);
		trashCan.scrollFactor.set(0, 0);
		trashCan.cameras = [camHUD];
		add(trashCan);

		trashLabel = new FlxText(trashCan.x, trashCan.y + 24, 60, 'TRASH', 12);
		trashLabel.setFormat(Paths.font('vcr.ttf'), 12, FlxColor.WHITE, CENTER);
		trashLabel.scrollFactor.set(0, 0);
		trashLabel.cameras = [camHUD];
		add(trashLabel);
	}

	function createTooltip():Void
	{
		tooltipBox = new FlxSprite().makeGraphic(300, 50, COLOR_TOOLTIP_BG);
		tooltipBox.scrollFactor.set(0, 0);
		tooltipBox.cameras = [camHUD];
		tooltipBox.visible = false;
		add(tooltipBox);

		tooltipText = new FlxText(0, 0, 290, '', 14);
		tooltipText.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE);
		tooltipText.scrollFactor.set(0, 0);
		tooltipText.cameras = [camHUD];
		tooltipText.visible = false;
		add(tooltipText);
	}

	function setStatus(message:String):Void
	{
		statusHold = STATUS_HOLD;
		if (statusText != null)
			statusText.text = message;
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

		statusText.text = contextHint();
	}

	function contextHint():String
	{
		if (isDragging)
			return 'Drop on the trash or over the sidebar to delete - snapping distance is 30px';

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

	// ============================================================================================
	// Timeline and markers
	// ============================================================================================

	function createTimeline():Void
	{
		var x:Float = SIDEBAR_WIDTH;
		var width:Float = Math.max(160, (FlxG.width - 90) - x);
		var height:Float = TIMELINE_HEIGHT;
		var y:Float = FlxG.height - STATUS_HEIGHT - height;

		timeline = new BlockTimeline(x, y, width, height, camHUD);
		timeline.onSeek = onTimelineSeek;
		timeline.onMarkerSelected = onMarkerSelected;
		timeline.onMarkerMoved = onMarkerMoved;
		timeline.onMarkerRemove = onMarkerRemove;
		add(timeline);
	}

	function createMarkerButton():Void
	{
		markerButton = makeButton('+ marker', function()
		{
			addMarkerAtCurrentStep();
		}, COLOR_BUTTON_ACTIVE);
		markerButton.setPosition(FlxG.width
			- TIMELINE_RIGHT_MARGIN
			- markerButton.width,
			FlxG.height
			- STATUS_HEIGHT
			- TIMELINE_HEIGHT
			- markerButton.height
			- 4);
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

	function createPanels():Void
	{
		// These panels bring their own camera along and add it to `FlxG.cameras` while they are open,
		// so they end up above `camHUD` and must keep their `cameras` untouched.
		savePanel = new BlockSavePanel(FlxG.width);
		savePanel.codeProvider = currentLua;
		savePanel.onSaved = onPanelSaved;
		savePanel.onClosed = onPanelClosed;
		add(savePanel);

		// This one keeps a camera the caller assigned, so the editor's own HUD camera is used.
		codePanel = new BlockCodePanel(FlxG.width, FlxG.height);
		codePanel.cameras = [camHUD];
		add(codePanel);

		fileBrowser = new BlockFileBrowser(FlxG.width, FlxG.height);
		add(fileBrowser);

		helpOverlay = new BlockHelpOverlay(FlxG.width, FlxG.height);
		helpOverlay.cameras = [camHUD];
		add(helpOverlay);

		contextMenuWidth = 220 * mobileScale;
		contextMenuHeight = 300 * mobileScale;
		contextMenu = new BlockContextMenu(contextMenuWidth, contextMenuHeight);
		contextMenu.cameras = [camHUD];
		add(contextMenu);

		virtualKeyboard = new BlockVirtualKeyboard(camHUD);
		virtualKeyboard.onKey = onVirtualKey;
		virtualKeyboard.onClose = onVirtualKeyboardClosed;
		add(virtualKeyboard);

		prompt = new PromptBox(mobileScale);
		prompt.cameras = [camHUD];
		add(prompt);
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
		layoutTopBar();
	}

	// ============================================================================================
	// Blocks
	// ============================================================================================

	function addBlock(data:BlockData):Void
	{
		if (data == null || blockContainer == null)
			return;

		pushUndo();

		var spawnX:Float = camEditor.scroll.x + 380 + lastSpawnPos.x;
		var spawnY:Float = camEditor.scroll.y + 220 + lastSpawnPos.y;
		if (spawnY < barHeight + 20)
			spawnY = barHeight + 20;

		var workspace:String = activeWorkspaceId();
		var block:Block = new Block(spawnX, spawnY, data);
		block.cameras = [camEditor];
		block.scrollFactor.set(1, 1);
		blockContainer.add(block);
		assignWorkspace(block, workspace);

		lastSpawnPos.x = (lastSpawnPos.x + 30) % 120;
		lastSpawnPos.y = (lastSpawnPos.y + 20) % 120;

		markDirty();
		updateWorkspaceVisibility();
		refreshBlockCount();
		setStatus('Added ' + data.label);
		playSound('scrollMenu');
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
		updateSidebarScroll(elapsed);

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

	/** True while another layer owns the pointer: prompt, panel, keyboard, context menu. */
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
			return new FlxPoint(cam.scroll.x + touch.screenX / cam.zoom, cam.scroll.y + touch.screenY / cam.zoom);

		return FlxG.mouse.getWorldPosition(cam);
	}

	function isPointerOverScreenSprite(sprite:FlxSprite):Bool
	{
		if (sprite == null)
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
		if (timeline == null)
			return false;

		var x:Float = getPointerScreenX();
		var y:Float = getPointerScreenY();
		var top:Float = FlxG.height - STATUS_HEIGHT - TIMELINE_HEIGHT;
		return (x >= SIDEBAR_WIDTH && x <= FlxG.width - TIMELINE_RIGHT_MARGIN && y >= top && y <= FlxG.height - STATUS_HEIGHT);
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
		return getPointerScreenY() >= FlxG.height - STATUS_HEIGHT;
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
		if (isPointerOverMarkerButton())
			return false;
		if (isPointerOverScreenSprite(trashCan))
			return false;

		return getPointerScreenX() >= SIDEBAR_WIDTH;
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

			if (isPointerJustPressed() && screenX >= SIDEBAR_WIDTH && !isPointerOverTopBar() && !isPointerOverTimeline())
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
			if (touch.justPressed && !isDragging && !pendingPan && touch.screenX >= SIDEBAR_WIDTH && !isPointerOverTimeline() && !isPointerOverTopBar()
				&& !isPointerOverMarkerButton())
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

		var screenPos:FlxPoint = dropped.getScreenPosition(null, camEditor);
		var overSidebar:Bool = screenPos.x < SIDEBAR_WIDTH;
		screenPos.put();

		if (overSidebar)
		{
			// Dropped over the sidebar: shrink away like in the standalone editor.
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
	// Sidebar scrolling and tooltips
	// ============================================================================================

	function updateSidebarScroll(elapsed:Float):Void
	{
		if (blockButtons == null || camSidebar == null)
			return;

		var maxHeight:Float = totalSidebarHeight - FlxG.height;
		if (maxHeight < 0)
			maxHeight = 0;

		var pointerX:Float = getPointerScreenX();
		var pointerY:Float = getPointerScreenY();
		var justPressed:Bool = isPointerJustPressed();
		var justReleased:Bool = isPointerJustReleased();
		var pressed:Bool = isPointerPressed();
		var blocked:Bool = pointerBlocked();

		if (justPressed && !blocked)
		{
			if (isPointerOverScreenSprite(scrollThumb))
			{
				isDraggingScroll = true;
				scrollDragOffset = pointerY - scrollThumb.y;
				sidebarDragLastY = pointerY;
			}
			else if (pointerX < SIDEBAR_WIDTH)
			{
				sidebarDragLastY = pointerY;
			}
		}

		if (justReleased)
			isDraggingScroll = false;

		if (isDraggingScroll && maxHeight > 0 && pressed)
		{
			var trackHeight:Float = FlxG.height - scrollThumb.height;
			var percent:Float = (trackHeight <= 0) ? 0 : (pointerY - scrollDragOffset) / trackHeight;
			camSidebar.scroll.y = FlxMath.bound(percent, 0, 1) * maxHeight;
		}
		else if (pointerX < SIDEBAR_WIDTH && !blocked)
		{
			if (FlxG.mouse.wheel != 0)
			{
				camSidebar.scroll.y -= FlxG.mouse.wheel * 40;
				camSidebar.scroll.y = FlxMath.bound(camSidebar.scroll.y, 0, maxHeight);
			}

			var touch:FlxTouch = getPrimaryTouch();
			if (touch != null && touch.pressed)
			{
				camSidebar.scroll.y += sidebarDragLastY - pointerY;
				camSidebar.scroll.y = FlxMath.bound(camSidebar.scroll.y, 0, maxHeight);
				sidebarDragLastY = pointerY;
			}
		}
		else if (!blocked && FlxG.mouse.wheel != 0 && !isPointerOverTimeline())
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

		if (maxHeight > 0)
			scrollThumb.y = (camSidebar.scroll.y / maxHeight) * (FlxG.height - scrollThumb.height);
		else
			scrollThumb.y = 0;
	}

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

		if (FlxG.mouse.screenX < SIDEBAR_WIDTH)
		{
			for (button in blockButtons)
			{
				if (button == null)
					continue;

				if (button.status == FlxButtonState.HIGHLIGHT)
				{
					var data:BlockData = blockButtonMap.get(button);
					if (data != null && data.description != null)
						description = data.description;
					break;
				}
			}
		}
		else
		{
			var worldPos:FlxPoint = FlxG.mouse.getWorldPosition(camEditor);
			var block:Block = findBlockAt(worldPos.x, worldPos.y);
			if (block != null && block.blockData != null && block.blockData.description != null)
				description = block.blockData.description;
		}

		showTooltip(description);
	}

	function showTooltip(text:String):Void
	{
		if (text == null || text.length == 0)
		{
			tooltipBox.visible = false;
			tooltipText.visible = false;
			return;
		}

		tooltipBox.visible = true;
		tooltipText.visible = true;
		tooltipText.text = text;

		var x:Float = FlxG.mouse.screenX + 15;
		var y:Float = FlxG.mouse.screenY + 15;
		if (x + 300 > FlxG.width)
			x = FlxG.width - 310;
		if (y + 50 > FlxG.height)
			y = FlxG.height - 60;

		tooltipBox.setPosition(x, y);
		tooltipText.setPosition(x + 5, y + 5);
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
		contextMenuX = FlxMath.bound(getPointerScreenX(), 8, Math.max(8, FlxG.width - contextMenuWidth - 8));
		contextMenuY = getPointerScreenY();
		if (contextMenuY + contextMenuHeight > FlxG.height - STATUS_HEIGHT)
			contextMenuY = FlxG.height - STATUS_HEIGHT - contextMenuHeight;
		if (contextMenuY < barHeight + 4)
			contextMenuY = barHeight + 4;

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

		var x:Float = field.bg.x - camera.scroll.x;
		var y:Float = field.bg.y - camera.scroll.y;
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
		editorTouchPad = new FlxTouchPad('FULL', 'A_B_X_Y');
		add(editorTouchPad);
		editorTouchPad.cameras = [camHUD];
	}
	#end
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
	var uiScale:Float = 1;
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
		var rowHeight:Float = 48 * uiScale;
		var width:Float = Math.min(FlxG.width - 60 * uiScale, 520 * uiScale);
		var height:Float = HEADER_HEIGHT * uiScale + (list.length + 1) * rowHeight;
		var boxX:Float = (FlxG.width - width) * 0.5;
		var boxY:Float = (FlxG.height - height) * 0.5;
		if (boxY < 0)
			boxY = 0;

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
