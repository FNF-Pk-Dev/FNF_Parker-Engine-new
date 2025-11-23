package editors;

import flixel.FlxG;
import flixel.FlxBasic;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.addons.display.FlxGridOverlay;
import flixel.util.FlxColor;
import flixel.math.FlxPoint;
import flixel.math.FlxMath;
import flixel.util.FlxTimer;
import flixel.util.FlxSave;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import haxe.Json;
import flixel.input.keyboard.FlxKey;
import openfl.display.BlendMode;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

#if desktop
import backend.Discord.DiscordClient;
#end

using StringTools;

import backend.Paths;

#if sys
import sys.FileSystem;
import sys.io.File;
import states.game.PlayState;
import backend.songs.Song;
import states.LoadingState;
#end

class BlockCodeEditorState extends MusicBeatState
{
	var camEditor:FlxCamera;
	var camHUD:FlxCamera;
	var camSidebar:FlxCamera;

	// Workspace
	var workspace:FlxSprite;
	var blockContainer:FlxTypedGroup<Block>;
	
	// UI Elements
	var sidebar:FlxSprite;
	var categoryButtons:FlxTypedGroup<FlxButton>;
	var blockButtons:FlxTypedGroup<FlxButton>;
	var statusText:FlxText;
	var blockCountText:FlxText;
	
	var trashCan:FlxSprite;
	var tooltipBox:FlxSprite;
	var tooltipText:FlxText;
	var blockButtonMap:Map<FlxButton, BlockData> = new Map();
	
	// Data
	var categories:Array<BlockCategory> = [];
	var currentCategory:String = "Events";
	
	// Interaction
	var draggingBlock:Block = null;
	var dragOffset:FlxPoint = FlxPoint.get();
	var isDragging:Bool = false;
	var isPanning:Bool = false;
	var panStart:FlxPoint = FlxPoint.get();
	var zoomLevel:Float = 1;
	var lastSpawnPos:FlxPoint = new FlxPoint(0, 0);
	
	// File
	var _file:FileReference;
	var _save:FlxSave;

	// Sidebar State
	var categoryYPositions:Map<String, Float> = new Map();
	var totalSidebarHeight:Float = 0;
	var scrollThumb:FlxSprite;
	var isDraggingScroll:Bool = false;
	var scrollDragOffset:Float = 0;

	override function create()
	{
		#if desktop
		DiscordClient.changePresence("Block Code Editor", null);
		#end

		// 1. Setup Cameras
		camEditor = new FlxCamera();
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		
		camSidebar = new FlxCamera(0, 0, 320, FlxG.height);
		camSidebar.bgColor.alpha = 0; // Transparent, handled by sprite
		
		FlxG.cameras.reset(camEditor);
		FlxG.cameras.add(camSidebar, false); // Sidebar Middle
		FlxG.cameras.add(camHUD, false); // HUD Top
		
		FlxG.cameras.setDefaultDrawTarget(camEditor, true);
		
		// Reset camera position and zoom
		camEditor.scroll.set(0, 0);
		camEditor.zoom = 1;
		zoomLevel = 1;
		lastSpawnPos.set(0, 0);

		// 2. Backgrounds (Scratch-like Light Theme)
		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFFF0F2F5); // Light Gray
		bg.scrollFactor.set();
		add(bg);

		// Infinite Grid (Subtle)
		var gridBG:FlxSprite = FlxGridOverlay.create(40, 40, FlxG.width * 4, FlxG.height * 4, true, 0xFFE5E5E5, 0xFFF0F2F5);
		gridBG.scrollFactor.set(0.5, 0.5);
		gridBG.screenCenter();
		add(gridBG);

		// 3. Block Container
		blockContainer = new FlxTypedGroup<Block>();
		add(blockContainer);

		// 4. UI Layer (HUD)
		createCustomUI();

		// 5. Initialize Data
		initCategories();
		
		// 6. Load Cache
		_save = new FlxSave();
		_save.bind("blockEditorCache", "parker-engine");
		loadCache();
		
		#if sys
		PlayState.isBlockTest = false;
		#end

		FlxG.mouse.visible = true;
		super.create();
	}

	function createCustomUI()
	{
		// Sidebar Background (White)
		var catStrip = new FlxSprite(0, 0).makeGraphic(70, FlxG.height, 0xFFF9F9F9);
		catStrip.cameras = [camSidebar];
		catStrip.scrollFactor.set(0, 0);
		add(catStrip);
		
		var sidebarBg = new FlxSprite(70, 0).makeGraphic(250, FlxG.height, 0xFFFFFFFF);
		sidebarBg.cameras = [camSidebar];
		sidebarBg.scrollFactor.set(0, 0);
		add(sidebarBg);
		
		var sep = new FlxSprite(319, 0).makeGraphic(1, FlxG.height, 0xFFE0E0E0);
		sep.cameras = [camSidebar];
		sep.scrollFactor.set(0, 0);
		add(sep);

		// Category Buttons Container
		categoryButtons = new FlxTypedGroup<FlxButton>();
		add(categoryButtons);

		// Block Buttons Container
		blockButtons = new FlxTypedGroup<FlxButton>();
		add(blockButtons);

		// Status Bar
		var statusBar = new FlxSprite(0, FlxG.height - 30).makeGraphic(FlxG.width, 30, 0xFF4C97FF);
		statusBar.cameras = [camHUD];
		add(statusBar);

		statusText = new FlxText(10, FlxG.height - 25, FlxG.width - 20, "Ready - Space+Drag to Pan, E/Q or Ctrl+Scroll to Zoom", 16);
		statusText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE);
		statusText.cameras = [camHUD];
		add(statusText);

		// Block Count
		blockCountText = new FlxText(FlxG.width - 150, 10, 140, "Blocks: 0", 20);
		blockCountText.setFormat(Paths.font("vcr.ttf"), 20, 0xFF333333, RIGHT);
		blockCountText.cameras = [camHUD];
		add(blockCountText);

		// Action Buttons
		createActionButtons();
		
		// Scrollbar
		setupScrollbar();
		
		// Trash Can
		trashCan = new FlxSprite(FlxG.width - 80, FlxG.height - 100);
		// Simple Trash Icon (Red Box for now if no asset)
		trashCan.makeGraphic(60, 60, 0xFFFF4444);
		var trashLabel = new FlxText(0, 0, 60, "TRASH", 12);
		trashLabel.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.WHITE, CENTER);
		trashLabel.y = 24;
		trashCan.pixels.draw(trashLabel.pixels, new openfl.geom.Matrix(1, 0, 0, 1, 0, 24));
		trashCan.cameras = [camHUD];
		add(trashCan);
		
		// Tooltip
		tooltipBox = new FlxSprite().makeGraphic(300, 50, 0xCC000000);
		tooltipBox.cameras = [camHUD];
		tooltipBox.visible = false;
		add(tooltipBox);
		
		tooltipText = new FlxText(0, 0, 290, "", 14);
		tooltipText.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.WHITE);
		tooltipText.cameras = [camHUD];
		tooltipText.visible = false;
		add(tooltipText);
	}

	function createActionButtons()
	{
		var btnY = 10;
		var btnX = FlxG.width - 100;
		
		var playBtn = new FlxButton(btnX, btnY + 30, "Play", function() {
			testScript();
		});
		playBtn.cameras = [camHUD];
		add(playBtn);
		
		var saveBtn = new FlxButton(btnX, btnY + 60, "Save", function() {
			exportLua();
		});
		saveBtn.cameras = [camHUD];
		add(saveBtn);
		
		var exitBtn = new FlxButton(btnX, btnY + 90, "Exit", function() {
			MusicBeatState.switchState(new states.menu.StoryMenuState());
		});
		exitBtn.cameras = [camHUD];
		add(exitBtn);
	}

	function setupScrollbar()
	{
		var barBg = new FlxSprite(310, 0).makeGraphic(10, FlxG.height, 0xFFF0F0F0);
		barBg.cameras = [camSidebar];
		barBg.scrollFactor.set(0, 0);
		add(barBg);
		
		scrollThumb = new FlxSprite(310, 0).makeGraphic(10, 50, 0xFFCCCCCC);
		scrollThumb.cameras = [camSidebar];
		scrollThumb.scrollFactor.set(0, 0);
		add(scrollThumb);
	}

	function initCategories()
	{
		// Define Categories
		categories = [
			{
				name: "Events", color: 0xFFFFBF00, icon: "⚡",
				blocks: [
					{type: "onCreate", label: "onCreate", color: 0xFFFFBF00, category: "Events", description: "Runs when the script starts."},
					{type: "onCreatePost", label: "onCreatePost", color: 0xFFFFBF00, category: "Events", description: "Runs after the game objects are created."},
					{type: "onUpdate", label: "onUpdate", color: 0xFFFFBF00, category: "Events", description: "Runs every frame."},
					{type: "onUpdatePost", label: "onUpdatePost", color: 0xFFFFBF00, category: "Events", description: "Runs every frame after game logic."},
					{type: "onBeatHit", label: "onBeatHit", color: 0xFFFFBF00, category: "Events", description: "Runs every beat of the song."},
					{type: "onStepHit", label: "onStepHit", color: 0xFFFFBF00, category: "Events", description: "Runs every step (1/4 beat) of the song."},
					{type: "onDestroy", label: "onDestroy", color: 0xFFFFBF00, category: "Events", description: "Runs when the script is closed or game ends."},
					{type: "onEvent", label: "onEvent", color: 0xFFFFBF00, category: "Events", description: "Runs when a chart event is triggered.", parameters: [{name: "n", type: "string", defaultValue: "name"}, {name: "v1", type: "string", defaultValue: "val1"}, {name: "v2", type: "string", defaultValue: "val2"}]},
				]
			},
			{
				name: "Control", color: 0xFFFFAB19, icon: "🔄",
				blocks: [
					{type: "if", label: "if", color: 0xFFFFAB19, category: "Control", description: "Runs code inside if the condition is true.", parameters: [{name: "condition", type: "string", defaultValue: "true"}]},
					{type: "elseif", label: "else if", color: 0xFFFFAB19, category: "Control", description: "Runs if previous conditions failed and this one is true.", parameters: [{name: "condition", type: "string", defaultValue: "true"}]},
					{type: "else", label: "else", color: 0xFFFFAB19, category: "Control", description: "Runs if all previous conditions failed."},
					{type: "end", label: "end", color: 0xFFFFAB19, category: "Control", description: "Ends an if statement or function."},
					{type: "wait", label: "wait", color: 0xFFFFAB19, category: "Control", description: "Waits for a number of seconds.", parameters: [{name: "seconds", type: "number", defaultValue: 1.0}]},
					{type: "debugPrint", label: "debugPrint", color: 0xFFFFAB19, category: "Control", description: "Prints text to the debug console.", parameters: [{name: "text", type: "string", defaultValue: "hello"}]},
					{type: "close", label: "close script", color: 0xFFFFAB19, category: "Control", description: "Stops this script."},
				]
			},
			{
				name: "Operators", color: 0xFF59C059, icon: "➕",
				blocks: [
					{type: "add", label: "+", color: 0xFF59C059, category: "Operators", description: "Adds two numbers.", isReporter: true, parameters: [{name: "a", type: "number", defaultValue: 0}, {name: "b", type: "number", defaultValue: 0}]},
					{type: "sub", label: "-", color: 0xFF59C059, category: "Operators", description: "Subtracts two numbers.", isReporter: true, parameters: [{name: "a", type: "number", defaultValue: 0}, {name: "b", type: "number", defaultValue: 0}]},
					{type: "mul", label: "*", color: 0xFF59C059, category: "Operators", description: "Multiplies two numbers.", isReporter: true, parameters: [{name: "a", type: "number", defaultValue: 0}, {name: "b", type: "number", defaultValue: 0}]},
					{type: "div", label: "/", color: 0xFF59C059, category: "Operators", description: "Divides two numbers.", isReporter: true, parameters: [{name: "a", type: "number", defaultValue: 0}, {name: "b", type: "number", defaultValue: 0}]},
					{type: "eq", label: "=", color: 0xFF59C059, category: "Operators", description: "Checks if two values are equal.", isReporter: true, parameters: [{name: "a", type: "string", defaultValue: ""}, {name: "b", type: "string", defaultValue: ""}]},
					{type: "gt", label: ">", color: 0xFF59C059, category: "Operators", description: "Checks if first number is greater than second.", isReporter: true, parameters: [{name: "a", type: "number", defaultValue: 0}, {name: "b", type: "number", defaultValue: 0}]},
					{type: "lt", label: "<", color: 0xFF59C059, category: "Operators", description: "Checks if first number is less than second.", isReporter: true, parameters: [{name: "a", type: "number", defaultValue: 0}, {name: "b", type: "number", defaultValue: 0}]},
					{type: "and", label: "and", color: 0xFF59C059, category: "Operators", description: "Returns true if both are true.", isReporter: true, parameters: [{name: "a", type: "string", defaultValue: "true"}, {name: "b", type: "string", defaultValue: "true"}]},
					{type: "or", label: "or", color: 0xFF59C059, category: "Operators", description: "Returns true if at least one is true.", isReporter: true, parameters: [{name: "a", type: "string", defaultValue: "true"}, {name: "b", type: "string", defaultValue: "true"}]},
					{type: "not", label: "not", color: 0xFF59C059, category: "Operators", description: "Inverts true/false.", isReporter: true, parameters: [{name: "a", type: "string", defaultValue: "true"}]},
					{type: "join", label: "join", color: 0xFF59C059, category: "Operators", description: "Joins two strings together.", isReporter: true, parameters: [{name: "a", type: "string", defaultValue: "hello"}, {name: "b", type: "string", defaultValue: "world"}]},
				]
			},
			{
				name: "Sensing", color: 0xFF4CBFE6, icon: "🔍",
				blocks: [
					{type: "keyJustPressed", label: "keyJustPressed", color: 0xFF4CBFE6, category: "Sensing", description: "True if key was just pressed this frame.", isReporter: true, parameters: [{name: "key", type: "string", defaultValue: "space"}]},
					{type: "keyPressed", label: "keyPressed", color: 0xFF4CBFE6, category: "Sensing", description: "True if key is currently held down.", isReporter: true, parameters: [{name: "key", type: "string", defaultValue: "space"}]},
					{type: "curStep", label: "curStep", color: 0xFF4CBFE6, category: "Sensing", description: "Current step of the song.", isReporter: true},
					{type: "curBeat", label: "curBeat", color: 0xFF4CBFE6, category: "Sensing", description: "Current beat of the song.", isReporter: true},
					{type: "songPosition", label: "songPosition", color: 0xFF4CBFE6, category: "Sensing", description: "Current position in milliseconds.", isReporter: true},
					{type: "health", label: "health", color: 0xFF4CBFE6, category: "Sensing", description: "Current health (0-2).", isReporter: true},
					{type: "getPixelColor", label: "getPixelColor", color: 0xFF4CBFE6, category: "Sensing", description: "Gets color of a pixel on an object.", isReporter: true, parameters: [{name: "obj", type: "string", defaultValue: "boyfriend"}, {name: "x", type: "number", defaultValue: 0}, {name: "y", type: "number", defaultValue: 0}]},
				]
			},
			{
				name: "Looks", color: 0xFF9966FF, icon: "👁️",
				blocks: [
					{type: "setProperty", label: "setProperty", color: 0xFF9966FF, category: "Looks", description: "Sets a property of an object.", parameters: [{name: "tag", type: "string", defaultValue: "tag"}, {name: "val", type: "string", defaultValue: "value"}]},
					{type: "getProperty", label: "getProperty", color: 0xFF9966FF, category: "Looks", description: "Gets a property of an object.", isReporter: true, parameters: [{name: "tag", type: "string", defaultValue: "tag"}]},
					{type: "makeLuaSprite", label: "makeLuaSprite", color: 0xFF9966FF, category: "Looks", description: "Creates a new sprite.", parameters: [{name: "tag", type: "string", defaultValue: "sprite"}, {name: "image", type: "string", defaultValue: "image"}, {name: "x", type: "number", defaultValue: 0}, {name: "y", type: "number", defaultValue: 0}]},
					{type: "makeAnimatedLuaSprite", label: "makeAnimatedLuaSprite", color: 0xFF9966FF, category: "Looks", description: "Creates a new animated sprite.", parameters: [{name: "tag", type: "string", defaultValue: "sprite"}, {name: "image", type: "string", defaultValue: "image"}, {name: "x", type: "number", defaultValue: 0}, {name: "y", type: "number", defaultValue: 0}]},
					{type: "addLuaSprite", label: "addLuaSprite", color: 0xFF9966FF, category: "Looks", description: "Adds the sprite to the scene.", parameters: [{name: "tag", type: "string", defaultValue: "sprite"}, {name: "front", type: "string", defaultValue: "false"}]},
					{type: "scaleObject", label: "scaleObject", color: 0xFF9966FF, category: "Looks", description: "Scales an object.", parameters: [{name: "tag", type: "string", defaultValue: "tag"}, {name: "x", type: "number", defaultValue: 1}, {name: "y", type: "number", defaultValue: 1}]},
					{type: "setObjectCamera", label: "setObjectCamera", color: 0xFF9966FF, category: "Looks", description: "Sets which camera an object uses.", parameters: [{name: "tag", type: "string", defaultValue: "tag"}, {name: "cam", type: "string", defaultValue: "hud"}]},
					{type: "screenCenter", label: "screenCenter", color: 0xFF9966FF, category: "Looks", description: "Centers an object on screen.", parameters: [{name: "tag", type: "string", defaultValue: "tag"}]},
				]
			},
			{
				name: "Sound", color: 0xFFCF63CF, icon: "🎵",
				blocks: [
					{type: "playSound", label: "playSound", color: 0xFFCF63CF, category: "Sound", description: "Plays a sound effect.", parameters: [{name: "sound", type: "string", defaultValue: "scrollMenu"}, {name: "vol", type: "number", defaultValue: 1.0}]},
					{type: "playMusic", label: "playMusic", color: 0xFFCF63CF, category: "Sound", description: "Plays background music.", parameters: [{name: "sound", type: "string", defaultValue: "music"}, {name: "vol", type: "number", defaultValue: 1.0}, {name: "loop", type: "string", defaultValue: "true"}]},
					{type: "pauseSound", label: "pauseSound", color: 0xFFCF63CF, category: "Sound", description: "Pauses a sound.", parameters: [{name: "sound", type: "string", defaultValue: "sound"}]},
					{type: "stopSound", label: "stopSound", color: 0xFFCF63CF, category: "Sound", description: "Stops a sound.", parameters: [{name: "sound", type: "string", defaultValue: "sound"}]},
				]
			},
			{
				name: "Motion", color: 0xFF4C97FF, icon: "✨",
				blocks: [
					{type: "doTweenX", label: "doTweenX", color: 0xFF4C97FF, category: "Motion", description: "Tweens the X position.", parameters: [{name: "tag", type: "string", defaultValue: "tag"}, {name: "obj", type: "string", defaultValue: "obj"}, {name: "val", type: "number", defaultValue: 100}, {name: "dur", type: "number", defaultValue: 1}, {name: "ease", type: "string", defaultValue: "linear"}]},
					{type: "doTweenY", label: "doTweenY", color: 0xFF4C97FF, category: "Motion", description: "Tweens the Y position.", parameters: [{name: "tag", type: "string", defaultValue: "tag"}, {name: "obj", type: "string", defaultValue: "obj"}, {name: "val", type: "number", defaultValue: 100}, {name: "dur", type: "number", defaultValue: 1}, {name: "ease", type: "string", defaultValue: "linear"}]},
					{type: "doTweenAlpha", label: "doTweenAlpha", color: 0xFF4C97FF, category: "Motion", description: "Tweens the Alpha (opacity).", parameters: [{name: "tag", type: "string", defaultValue: "tag"}, {name: "obj", type: "string", defaultValue: "obj"}, {name: "val", type: "number", defaultValue: 1}, {name: "dur", type: "number", defaultValue: 1}, {name: "ease", type: "string", defaultValue: "linear"}]},
					{type: "doTweenZoom", label: "doTweenZoom", color: 0xFF4C97FF, category: "Motion", description: "Tweens the Camera Zoom.", parameters: [{name: "tag", type: "string", defaultValue: "tag"}, {name: "cam", type: "string", defaultValue: "game"}, {name: "val", type: "number", defaultValue: 1}, {name: "dur", type: "number", defaultValue: 1}, {name: "ease", type: "string", defaultValue: "linear"}]},
				]
			},
			{
				name: "Game", color: 0xFF59C059, icon: "🎮",
				blocks: [
					{type: "setHealth", label: "setHealth", color: 0xFF59C059, category: "Game", description: "Sets the player health.", parameters: [{name: "val", type: "number", defaultValue: 1.0}]},
					{type: "addHealth", label: "addHealth", color: 0xFF59C059, category: "Game", description: "Adds to the player health.", parameters: [{name: "val", type: "number", defaultValue: 0.1}]},
					{type: "cameraShake", label: "cameraShake", color: 0xFF59C059, category: "Game", description: "Shakes the camera.", parameters: [{name: "cam", type: "string", defaultValue: "game"}, {name: "int", type: "number", defaultValue: 0.05}, {name: "dur", type: "number", defaultValue: 0.5}]},
					{type: "cameraFlash", label: "cameraFlash", color: 0xFF59C059, category: "Game", description: "Flashes the camera with a color.", parameters: [{name: "cam", type: "string", defaultValue: "game"}, {name: "col", type: "string", defaultValue: "FFFFFF"}, {name: "dur", type: "number", defaultValue: 0.5}]},
					{type: "cameraFade", label: "cameraFade", color: 0xFF59C059, category: "Game", description: "Fades the camera to a color.", parameters: [{name: "cam", type: "string", defaultValue: "game"}, {name: "col", type: "string", defaultValue: "000000"}, {name: "dur", type: "number", defaultValue: 0.5}]},
				]
			}
		];

		// Build UI
		var catX = 10;
		var catY = 20;
		var blockListX = 80;
		var blockListY = 20.0;
		
		for (cat in categories)
		{
			// 1. Category Icon (Left Strip)
			var btn = new FlxButton(catX, catY, "", function() scrollToCategory(cat.name));
			btn.makeGraphic(50, 50, cat.color);
			btn.text = cat.icon;
			btn.label.size = 24;
			btn.cameras = [camSidebar];
			btn.scrollFactor.set(0, 0); // Fixed position, no scrolling
			categoryButtons.add(btn);
			add(btn);
			
			catY += 60;
			
			// 2. Block List
			categoryYPositions.set(cat.name, blockListY);
			
			var header = new FlxText(blockListX, blockListY, 0, cat.name, 16);
			header.setFormat(Paths.font("vcr.ttf"), 16, cat.color, LEFT);
			header.cameras = [camSidebar];
			header.scrollFactor.set(1, 1);
			add(header);
			blockListY += 30;
			
			for (block in cat.blocks)
			{
				var bBtn = new FlxButton(blockListX, blockListY, block.label, function() {
					addBlock(block);
				});
				bBtn.makeGraphic(220, 30, block.color);
				bBtn.label.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.WHITE, CENTER);
				bBtn.cameras = [camSidebar];
				bBtn.scrollFactor.set(1, 1);
				// Store data for tooltip
				// We can't easily store extra data on FlxButton without extending it or using a map.
				// Let's use a map for tooltips based on button.
				blockButtonMap.set(bBtn, block);
				
				blockButtons.add(bBtn);
				add(bBtn);
				blockListY += 40;
			}
			blockListY += 20;
		}
		totalSidebarHeight = blockListY;
	}


	function scrollToCategory(catName:String)
	{
		if (categoryYPositions.exists(catName)) {
			var targetY = categoryYPositions.get(catName);
			FlxTween.cancelTweensOf(camSidebar.scroll);
			FlxTween.tween(camSidebar.scroll, {y: targetY - 20}, 0.5, {ease: FlxEase.quartOut});
			setStatus("Jumped to " + catName);
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}
	}
	function addBlock(data:BlockData)
	{
		var block = new Block(camEditor.scroll.x + 400, camEditor.scroll.y + 300, data);
		blockContainer.add(block);
		updateBlockCount();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function updateBlockCount()
	{
		if (blockCountText != null)
			blockCountText.text = "Blocks: " + blockContainer.length;
	}

	function setStatus(msg:String)
	{
		if (statusText != null)
			statusText.text = msg;
	}
    


	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		handleInput(elapsed);
		handleMouseDrag();
		handleTooltips();
		
		var maxH = totalSidebarHeight - FlxG.height;
		if (maxH < 0) maxH = 0;

		// Scrollbar Dragging
		if (FlxG.mouse.justPressed) {
			if (FlxG.mouse.overlaps(scrollThumb, camSidebar)) {
				isDraggingScroll = true;
				scrollDragOffset = FlxG.mouse.screenY - scrollThumb.y;
			}
		}
		
		if (FlxG.mouse.justReleased) {
			isDraggingScroll = false;
		}
		
		if (isDraggingScroll && maxH > 0) {
			var thumbY = FlxG.mouse.screenY - scrollDragOffset;
			var trackHeight = FlxG.height - scrollThumb.height;
			var pct = thumbY / trackHeight;
			pct = FlxMath.bound(pct, 0, 1);
			
			camSidebar.scroll.y = pct * maxH;
		}
		else if (FlxG.mouse.screenX < 320) {
			// Mouse Wheel Scroll
			if (FlxG.mouse.wheel != 0) {
				camSidebar.scroll.y -= FlxG.mouse.wheel * 40;
				if (camSidebar.scroll.y < 0) camSidebar.scroll.y = 0;
				if (camSidebar.scroll.y > maxH) camSidebar.scroll.y = maxH;
			}
		} else {
			// Editor Scroll
			if (FlxG.mouse.wheel != 0) {
				if (FlxG.keys.pressed.CONTROL) {
					// Zoom
					zoomLevel += FlxG.mouse.wheel * 0.1;
					zoomLevel = FlxMath.bound(zoomLevel, 0.1, 3.0);
					camEditor.zoom = zoomLevel;
					setStatus("Zoom: " + Math.round(zoomLevel * 100) + "%");
				} else {
					// Scroll Y
					camEditor.scroll.y -= (FlxG.mouse.wheel * 40) / zoomLevel;
				}
			}
		}
		
		// Update Scroll Thumb (Visual Only)
		if (maxH > 0) {
			var pct = camSidebar.scroll.y / maxH;
			scrollThumb.y = pct * (FlxG.height - scrollThumb.height);
		} else {
			scrollThumb.y = 0;
		}
	}

	function handleTooltips()
	{
		var hoveredDesc:String = "";
		
		// Check Sidebar Buttons
		if (FlxG.mouse.screenX < 320) {
			for (btn in blockButtons) {
				if (btn.status == FlxButton.HIGHLIGHT) {
					var data = blockButtonMap.get(btn);
					if (data != null && data.description != null) {
						hoveredDesc = data.description;
					}
					break;
				}
			}
		} 
		// Check Workspace Blocks
		else {
			var mouseWorld = FlxG.mouse.getWorldPosition(camEditor);
			for (block in blockContainer.members) {
				if (block.isMouseOver(camEditor)) {
					if (block.blockData.description != null) {
						hoveredDesc = block.blockData.description;
					}
					break;
				}
			}
		}
		
		if (hoveredDesc != "") {
			tooltipBox.visible = true;
			tooltipText.visible = true;
			tooltipText.text = hoveredDesc;
			
			// Position tooltip near mouse but keep on screen
			var tx = FlxG.mouse.screenX + 15;
			var ty = FlxG.mouse.screenY + 15;
			
			if (tx + 300 > FlxG.width) tx = FlxG.width - 310;
			if (ty + 50 > FlxG.height) ty = FlxG.height - 60;
			
			tooltipBox.x = tx;
			tooltipBox.y = ty;
			tooltipText.x = tx + 5;
			tooltipText.y = ty + 5;
		} else {
			tooltipBox.visible = false;
			tooltipText.visible = false;
		}
	}

	function handleInput(elapsed:Float)
	{
		// Check if any input field is focused
		var inputFocused = false;
		for (block in blockContainer.members) {
			for (input in block.inputFields) {
				if (input.isFocused) {
					inputFocused = true;
					break;
				}
			}
		}

		if (inputFocused) return; // Disable shortcuts if typing

		// Shortcuts
		if (FlxG.keys.justPressed.ESCAPE)
			MusicBeatState.switchState(new states.menu.StoryMenuState());

		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S)
		{
			saveCache();
			setStatus("Saved to cache!");
			FlxG.sound.play(Paths.sound('confirmMenu'));
		}

		// Camera Controls (Character Editor style)
		if (FlxG.keys.pressed.E) {
			zoomLevel += elapsed * zoomLevel;
			if(zoomLevel > 3) zoomLevel = 3;
			camEditor.zoom = zoomLevel;
		}
		if (FlxG.keys.pressed.Q) {
			zoomLevel -= elapsed * zoomLevel;
			if(zoomLevel < 0.1) zoomLevel = 0.1;
			camEditor.zoom = zoomLevel;
		}
		
		var moveSpeed = 500.0;
		if (FlxG.keys.pressed.SHIFT) moveSpeed *= 2;
		
		if (FlxG.keys.pressed.I || FlxG.keys.pressed.UP) camEditor.scroll.y -= moveSpeed * elapsed;
		if (FlxG.keys.pressed.K || FlxG.keys.pressed.DOWN) camEditor.scroll.y += moveSpeed * elapsed;
		if (FlxG.keys.pressed.J || FlxG.keys.pressed.LEFT) camEditor.scroll.x -= moveSpeed * elapsed;
		if (FlxG.keys.pressed.L || FlxG.keys.pressed.RIGHT) camEditor.scroll.x += moveSpeed * elapsed;

		// Panning (Space + Drag)
		if (FlxG.keys.pressed.SPACE)
		{
			if (FlxG.mouse.justPressed)
			{
				isPanning = true;
				panStart.set(FlxG.mouse.screenX, FlxG.mouse.screenY);
			}
			
			if (isPanning && FlxG.mouse.pressed)
			{
				var dx = panStart.x - FlxG.mouse.screenX;
				var dy = panStart.y - FlxG.mouse.screenY;
				
				camEditor.scroll.x += dx / zoomLevel;
				camEditor.scroll.y += dy / zoomLevel;
				
				panStart.set(FlxG.mouse.screenX, FlxG.mouse.screenY);
			}
		}
		else
		{
			isPanning = false;
		}
	}

	function handleMouseDrag()
	{
		if (isPanning) return;

		var mouse = FlxG.mouse;
		var worldMouse = mouse.getWorldPosition(camEditor);

		if (mouse.justPressed)
		{
			var i = blockContainer.members.length - 1;
			while (i >= 0)
			{
				var block = blockContainer.members[i];
				var clickedInput = false;
				for (input in block.inputFields) {
					// Check input bounds in world space
					if (worldMouse.x >= input.bg.x && worldMouse.x <= input.bg.x + input.width &&
						worldMouse.y >= input.bg.y && worldMouse.y <= input.bg.y + input.height) {
						clickedInput = true;
						break;
					}
				}
				
				if (!clickedInput && block != null && block.isMouseOver(camEditor))
				{
					draggingBlock = block;
					
					// Switch to HUD for dragging over sidebar
					var screenPos = block.getScreenPosition(camEditor);
					draggingBlock.cameras = [camHUD];
					draggingBlock.x = screenPos.x;
					draggingBlock.y = screenPos.y;
					draggingBlock.scale.set(zoomLevel, zoomLevel);
					
					dragOffset.set(FlxG.mouse.screenX - draggingBlock.x, FlxG.mouse.screenY - draggingBlock.y);
					isDragging = true;
					
					blockContainer.remove(block, true);
					blockContainer.add(block);
					
					// Detach from input if attached
					if (block.parentInput != null) {
						var oldParent = block.parentInput.parentBlock;
						block.parentInput.attachedBlock = null;
						block.parentInput = null;
						if (oldParent != null) oldParent.recalculateSize();
					}
					
					// Detach from previous block if snapped
					if (block.prevBlock != null) {
						block.prevBlock.nextBlock = null;
						block.prevBlock = null;
						block.isSnapped = false;
					}
					break;
				}
				i--;
			}
		}

		if (isDragging && draggingBlock != null)
		{
			draggingBlock.x = FlxG.mouse.screenX - dragOffset.x;
			draggingBlock.y = FlxG.mouse.screenY - dragOffset.y;
			
			// Trash Can Highlight
			if (FlxG.mouse.overlaps(trashCan, camHUD)) {
				trashCan.scale.set(1.2, 1.2);
				draggingBlock.alpha = 0.5;
			} else {
				trashCan.scale.set(1.0, 1.0);
				draggingBlock.alpha = 1.0;
			}
			
			if (draggingBlock.isReporter) {
				checkInputSnapping(draggingBlock);
			} else {
				checkSnapping(draggingBlock);
			}
		}

		if (mouse.justReleased)
		{
			if (isDragging && draggingBlock != null)
			{
				// Check Trash Can
				if (FlxG.mouse.overlaps(trashCan, camHUD)) {
					blockContainer.remove(draggingBlock, true);
					draggingBlock.destroy();
					updateBlockCount();
					setStatus("Deleted block");
					FlxG.sound.play(Paths.sound('cancelMenu'));
					trashCan.scale.set(1.0, 1.0);
					isDragging = false;
					draggingBlock = null;
					return;
				}
				
				// Restore to Editor
				var mouseWorld = FlxG.mouse.getWorldPosition(camEditor);
				draggingBlock.x = mouseWorld.x - (dragOffset.x / zoomLevel);
				draggingBlock.y = mouseWorld.y - (dragOffset.y / zoomLevel);
				
				draggingBlock.cameras = [camEditor];
				draggingBlock.scale.set(1, 1);
				draggingBlock.alpha = 1.0;
				
				if (draggingBlock.isReporter) {
					applyInputSnapping(draggingBlock);
				} else {
					applySnapping(draggingBlock);
				}
				
				var screenPos = draggingBlock.getScreenPosition(camEditor);
				if (screenPos.x < 320) {
					FlxTween.tween(draggingBlock.scale, {x: 0, y: 0}, 0.2, {ease: FlxEase.backIn, onComplete: function(t) {
						blockContainer.remove(draggingBlock, true);
						draggingBlock.destroy();
						updateBlockCount();
					}});
					setStatus("Deleted block");
					FlxG.sound.play(Paths.sound('cancelMenu'));
				}
			}
			isDragging = false;
			draggingBlock = null;
		}
	}

	function checkSnapping(current:Block)
	{
		var snapDist = 30.0;
		// We need to check distance in World Space?
		// draggingBlock is in HUD space (screen), others are in World space.
		// We can't easily check snapping while dragging across cameras without conversion.
		// For now, skip visual snapping feedback during drag if it's too complex, or convert.
		// Let's skip visual snapping for now to be safe, or implement simple distance check using converted coords.
	}
	
	function checkInputSnapping(current:Block) {
		// Visual feedback
	}

	function applySnapping(current:Block)
	{
		var snapDist = 30.0;
		for (other in blockContainer.members)
		{
			if (other == current || other == null || other.isReporter) continue;
			
			var targetY = other.y + other.height;
			var dist = new FlxPoint(current.x, current.y).distanceTo(new FlxPoint(other.x, targetY));
			
			if (dist < snapDist)
			{
				current.x = other.x;
				current.y = targetY;
				
				other.nextBlock = current;
				current.prevBlock = other;
				current.isSnapped = true;
				setStatus("Snapped!");
				FlxG.sound.play(Paths.sound('scrollMenu'));
				return;
			}
		}
		current.isSnapped = false;
	}
	
	function applyInputSnapping(current:Block)
	{
		var snapDist = 30.0;
		for (other in blockContainer.members)
		{
			if (other == current || other == null) continue;
			
			for (input in other.inputFields) {
				if (input.attachedBlock != null) continue; // Already has block
				
				var dist = new FlxPoint(current.x, current.y).distanceTo(new FlxPoint(input.bg.x, input.bg.y));
				if (dist < snapDist) {
					input.attachedBlock = current;
					current.parentInput = input;
					current.x = input.bg.x;
					current.y = input.bg.y;
					other.recalculateSize();
					setStatus("Attached to input!");
					FlxG.sound.play(Paths.sound('scrollMenu'));
					return;
				}
			}
		}
	}

	// --- Code Generation ---
	
	function generateLuaCode():String {
		var code = "-- Generated by Scratch Mod Editor\n\n";
		for (block in blockContainer.members) {
			if (block.prevBlock == null && block.parentInput == null) { // Only roots
				var curr = block;
				// Check if it's a Hat block (Event)
				var isHat = ["onCreate", "onCreatePost", "onUpdate", "onUpdatePost", "onBeatHit", "onStepHit", "onDestroy", "onEvent"].contains(curr.blockData.type);
				
				while (curr != null) {
					code += generateBlockCode(curr) + "\n";
					curr = curr.nextBlock;
				}
				
				if (isHat) code += "end\n\n";
			}
		}
		return code;
	}
	
	function generateBlockCode(block:Block):String {
		var params = block.inputFields;
		var p = function(i:Int, def:Dynamic):Dynamic {
			if (params.length > i) {
				if (params[i].attachedBlock != null) {
					return generateBlockCode(params[i].attachedBlock);
				}
				return params[i].value;
			}
			return def;
		};
		
		// Helper to quote string if it's not a number or boolean or variable
		var q = function(val:Dynamic):String {
			var s = Std.string(val);
			// If it looks like a function call (contains parens) or number, don't quote
			if (s.indexOf("(") != -1 || Std.parseFloat(s) != Math.NaN || s == "true" || s == "false") return s;
			return "'" + s + "'";
		};
		
		// Helper for raw value (for numbers/bools)
		var v = function(val:Dynamic):String {
			return Std.string(val);
		};
		
		switch(block.blockData.type) {
			case "onCreate": return "function onCreate()";
			case "onCreatePost": return "function onCreatePost()";
			case "onUpdate": return "function onUpdate(elapsed)";
			case "onUpdatePost": return "function onUpdatePost(elapsed)";
			case "onBeatHit": return "function onBeatHit()";
			case "onStepHit": return "function onStepHit()";
			case "onDestroy": return "function onDestroy()";
			case "onEvent": return "function onEvent(n, v1, v2)";
			
			case "if": return "if " + v(p(0, "true")) + " then";
			case "elseif": return "elseif " + v(p(0, "true")) + " then";
			case "else": return "else";
			case "end": return "end";
			case "wait": return "runTimer('timer', " + v(p(0, 1)) + ")";
			case "debugPrint": return "debugPrint(" + q(p(0, "hello")) + ")";
			case "close": return "close(true)";
			
			// Operators
			case "add": return "(" + v(p(0,0)) + " + " + v(p(1,0)) + ")";
			case "sub": return "(" + v(p(0,0)) + " - " + v(p(1,0)) + ")";
			case "mul": return "(" + v(p(0,0)) + " * " + v(p(1,0)) + ")";
			case "div": return "(" + v(p(0,0)) + " / " + v(p(1,0)) + ")";
			case "eq": return "(" + v(p(0,0)) + " == " + v(p(1,0)) + ")";
			case "gt": return "(" + v(p(0,0)) + " > " + v(p(1,0)) + ")";
			case "lt": return "(" + v(p(0,0)) + " < " + v(p(1,0)) + ")";
			case "and": return "(" + v(p(0,"true")) + " and " + v(p(1,"true")) + ")";
			case "or": return "(" + v(p(0,"true")) + " or " + v(p(1,"true")) + ")";
			case "not": return "(not " + v(p(0,"true")) + ")";
			case "join": return "(" + q(p(0,"a")) + " .. " + q(p(1,"b")) + ")";
			
			// Sensing
			case "keyJustPressed": return "keyJustPressed(" + q(p(0,"space")) + ")";
			case "keyPressed": return "keyPressed(" + q(p(0,"space")) + ")";
			case "curStep": return "curStep";
			case "curBeat": return "curBeat";
			case "songPosition": return "getSongPosition()";
			case "health": return "getProperty('health')";
			case "getPixelColor": return "getPixelColor(" + q(p(0,"obj")) + ", " + v(p(1,0)) + ", " + v(p(2,0)) + ")";
			
			case "setProperty": return "setProperty(" + q(p(0, "tag")) + ", " + v(p(1, "val")) + ")";
			case "getProperty": return "getProperty(" + q(p(0, "tag")) + ")";
			case "makeLuaSprite": return "makeLuaSprite(" + q(p(0, "spr")) + ", " + q(p(1, "img")) + ", " + v(p(2, 0)) + ", " + v(p(3, 0)) + ")";
			case "makeAnimatedLuaSprite": return "makeAnimatedLuaSprite(" + q(p(0, "spr")) + ", " + q(p(1, "img")) + ", " + v(p(2, 0)) + ", " + v(p(3, 0)) + ")";
			case "addLuaSprite": return "addLuaSprite(" + q(p(0, "spr")) + ", " + v(p(1, "false")) + ")";
			case "scaleObject": return "scaleObject(" + q(p(0, "tag")) + ", " + v(p(1, 1)) + ", " + v(p(2, 1)) + ")";
			case "setObjectCamera": return "setObjectCamera(" + q(p(0, "tag")) + ", " + q(p(1, "hud")) + ")";
			case "screenCenter": return "screenCenter(" + q(p(0, "tag")) + ")";
			
			case "playSound": return "playSound(" + q(p(0, "snd")) + ", " + v(p(1, 1)) + ")";
			case "playMusic": return "playMusic(" + q(p(0, "snd")) + ", " + v(p(1, 1)) + ", " + v(p(2, "true")) + ")";
			case "pauseSound": return "pauseSound(" + q(p(0, "snd")) + ")";
			case "stopSound": return "stopSound(" + q(p(0, "snd")) + ")";
			
			case "doTweenX": return "doTweenX(" + q(p(0, "tag")) + ", " + q(p(1, "obj")) + ", " + v(p(2, 100)) + ", " + v(p(3, 1)) + ", " + q(p(4, "linear")) + ")";
			case "doTweenY": return "doTweenY(" + q(p(0, "tag")) + ", " + q(p(1, "obj")) + ", " + v(p(2, 100)) + ", " + v(p(3, 1)) + ", " + q(p(4, "linear")) + ")";
			case "doTweenAlpha": return "doTweenAlpha(" + q(p(0, "tag")) + ", " + q(p(1, "obj")) + ", " + v(p(2, 1)) + ", " + v(p(3, 1)) + ", " + q(p(4, "linear")) + ")";
			case "doTweenZoom": return "doTweenZoom(" + q(p(0, "tag")) + ", " + q(p(1, "game")) + ", " + v(p(2, 1)) + ", " + v(p(3, 1)) + ", " + q(p(4, "linear")) + ")";
			
			case "setHealth": return "setProperty('health', " + v(p(0, 1)) + ")";
			case "addHealth": return "addHealth(" + v(p(0, 0.1)) + ")";
			case "cameraShake": return "cameraShake(" + q(p(0, "game")) + ", " + v(p(1, 0.05)) + ", " + v(p(2, 0.5)) + ")";
			case "cameraFlash": return "cameraFlash(" + q(p(0, "game")) + ", " + q(p(1, "FFFFFF")) + ", " + v(p(2, 0.5)) + ")";
			case "cameraFade": return "cameraFade(" + q(p(0, "game")) + ", " + q(p(1, "000000")) + ", " + v(p(2, 0.5)) + ")";
			
			default: return "-- " + block.blockData.label;
		}
	}

	// --- File I/O ---

	function saveProject()
	{
		var data = [];
		for (block in blockContainer.members) {
			if (block.prevBlock == null && block.parentInput == null) {
				data.push(serializeBlock(block));
			}
		}
		
		var json = Json.stringify(data, null, "\t");
		
		_file = new FileReference();
		_file.addEventListener(Event.COMPLETE, onSaveComplete);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file.save(json, "script_project.json");
	}
	
	function onSaveComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		setStatus("Project saved successfully!");
		FlxG.sound.play(Paths.sound('confirmMenu'));
	}
	
	function onSaveError(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		setStatus("Error saving project.");
		FlxG.sound.play(Paths.sound('cancelMenu'));
	}
	
	function loadProject()
	{
		_file = new FileReference();
		_file.addEventListener(Event.SELECT, onSelectLoad);
		_file.browse();
	}
	
	function onSelectLoad(_):Void
	{
		_file.removeEventListener(Event.SELECT, onSelectLoad);
		_file.addEventListener(Event.COMPLETE, onLoadComplete);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file.load();
	}
	
	function onLoadComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onLoadComplete);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		
		try {
			var jsonString = _file.data.toString();
			var data:Array<Dynamic> = Json.parse(jsonString);
			
			// Clear existing
			blockContainer.clear();
			updateBlockCount();
			
			// Reconstruct
			if (data != null) {
				for (bData in data) {
					reconstructBlock(bData);
				}
			}
			
			setStatus("Project loaded!");
			FlxG.sound.play(Paths.sound('confirmMenu'));
		} catch(e:Dynamic) {
			setStatus("Error parsing project file.");
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
	}
	
	function onLoadError(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onLoadComplete);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		setStatus("Error loading file.");
		FlxG.sound.play(Paths.sound('cancelMenu'));
	}
	
	function serializeBlock(block:Block):Dynamic
	{
		var obj:Dynamic = {
			type: block.blockData.type,
			x: block.x,
			y: block.y,
			inputs: [],
			next: null
		};
		
		for (input in block.inputFields) {
			if (input.attachedBlock != null) {
				obj.inputs.push({
					index: block.inputFields.indexOf(input),
					value: serializeBlock(input.attachedBlock) // Recursive for reporters
				});
			} else {
				obj.inputs.push({
					index: block.inputFields.indexOf(input),
					value: input.value
				});
			}
		}
		
		if (block.nextBlock != null) {
			obj.next = serializeBlock(block.nextBlock);
		}
		
		return obj;
	}
	
	function reconstructBlock(data:Dynamic, parentInput:InputField = null):Block
	{
		var def = getBlockDef(data.type);
		if (def == null) return null;
		
		var block = new Block(data.x, data.y, def);
		blockContainer.add(block);
		
		// Handle Inputs
		if (data.inputs != null) {
			var inputs:Array<Dynamic> = data.inputs;
			for (inpData in inputs) {
				var idx:Int = inpData.index;
				if (idx < block.inputFields.length) {
					var input = block.inputFields[idx];
					if (Std.is(inpData.value, Float) || Std.is(inpData.value, String) || Std.is(inpData.value, Bool)) {
						input.value = inpData.value;
						input.text.text = Std.string(input.value);
					} else {
						// It's a block object
						var subBlock = reconstructBlock(inpData.value, input);
					}
				}
			}
		}
		
		// Attach to parent input
		if (parentInput != null) {
			parentInput.attachedBlock = block;
			block.parentInput = parentInput;
			block.x = parentInput.bg.x;
			block.y = parentInput.bg.y;
			// Recalculate size handled by update or manual call?
			// We should probably call recalculateSize at the end of chain
		}
		
		// Handle Next Block
		if (data.next != null) {
			var nextB = reconstructBlock(data.next);
			if (nextB != null) {
				block.nextBlock = nextB;
				nextB.prevBlock = block;
				nextB.isSnapped = true;
				nextB.x = block.x;
				nextB.y = block.y + block.height;
			}
		}
		
		block.recalculateSize();
		return block;
	}
	
	function getBlockDef(type:String):BlockData
	{
		for (cat in categories) {
			for (b in cat.blocks) {
				if (b.type == type) return b;
			}
		}
		return null;
	}

	// --- Cache (Keep existing for quick save) ---
	function saveCache()
	{
		var data = [];
		for (block in blockContainer.members) {
			if (block.prevBlock == null && block.parentInput == null) {
				data.push(serializeBlock(block));
			}
		}
		_save.data.blocks = data;
		_save.flush();
	}

	function loadCache()
	{
		if (_save.data.blocks != null) {
			var data:Array<Dynamic> = _save.data.blocks;
			for (bData in data) {
				reconstructBlock(bData);
			}
		}
	}
	
	function exportLua()
	{
		var code = generateLuaCode();
		_file = new FileReference();
		_file.addEventListener(Event.COMPLETE, onSaveComplete);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file.save(code, "script.lua");
	}

	function testScript() {
		#if sys
		var code = generateLuaCode();
		var path = "mods/data/testScript.lua";
		if (!FileSystem.exists("mods/data")) FileSystem.createDirectory("mods/data");
		File.saveContent(path, code);
		
		PlayState.isBlockTest = true;
		PlayState.blockScriptPath = path;
		
		// Load a default song or current
		if (PlayState.SONG == null) 
			PlayState.SONG = Song.loadFromJson('tutorial', 'tutorial'); // Use tutorial as default
			
		LoadingState.loadAndSwitchState(new PlayState());
		#end
	}
	

}
// --- APPENDED TYPES ---
enum abstract ParamType(String) from String to String {
	var STRING = "string";
	var NUMBER = "number";
	var BOOL = "bool";
}

typedef BlockParameter = {
	var name:String;
	var type:ParamType;
	var defaultValue:Dynamic;
}

typedef BlockData = {
	var type:String;
	var label:String;
	var color:Int;
	var category:String;
	@:optional var parameters:Array<BlockParameter>;
	@:optional var isReporter:Bool;
	@:optional var description:String;
}

typedef BlockCategory = {
	var name:String;
	var color:Int;
	var icon:String;
	var blocks:Array<BlockData>;
}

// --- APPENDED BLOCK CLASS ---
class Block extends FlxSprite
{
	public var blockData:BlockData;
	public var isTemplate:Bool;

	// Visual elements
	public var label:FlxText;
	public var icon:FlxText;
	public var inputFields:Array<InputField> = [];

	// Snapping Logic
	public var nextBlock:Block = null;
	public var prevBlock:Block = null;
	public var isSnapped:Bool = false;
	
	// Reporter Logic
	public var isReporter:Bool = false;
	public var parentInput:InputField = null; // If attached to an input

	// Dimensions
	var minWidth:Float = 150;
	var minHeight:Float = 50;
	
	// Animation
	public var targetScale:Float = 1.0;

	public function new(x:Float, y:Float, data:BlockData, isTemplate:Bool = false)
	{
		super(x, y);
		this.blockData = data;
		this.isTemplate = isTemplate;
		this.isReporter = (data.isReporter == true);

		// Setup Label
		label = new FlxText(x + 50, y + 15, 0, data.label, 16);
		label.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, 0x33000000);
		label.borderSize = 1.5;
		
		// Setup Icon
		var iconStr = "";
		switch(data.category) {
			case "Events": iconStr = "⚡";
			case "Control": iconStr = "🔄";
			case "Objects", "Looks": iconStr = "👁️";
			case "Audio", "Sound": iconStr = "🎵";
			case "Tween", "Motion": iconStr = "✨";
			case "Game": iconStr = "🎮";
			case "Operators": iconStr = "➕";
			case "Sensing": iconStr = "🔍";
			default: iconStr = "★";
		}
		
		icon = new FlxText(x + 15, y + 12, 0, iconStr, 20);
		icon.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, 0x33000000);
		icon.borderSize = 1.5;

		// Create Input Fields
		if (data.parameters != null)
		{
			var currentX = x + label.width + 60;
			for (param in data.parameters)
			{
				var input = new InputField(currentX, y + 10, 80, 30, param.defaultValue, param.type, param.name);
				input.parentBlock = this;
				inputFields.push(input);
				currentX += 90;
			}
			minWidth = currentX - x + 20;
		}
		else
		{
			minWidth = label.width + 70;
		}
		
		if (isReporter) {
			minHeight = 40;
			label.y = y + 10;
			icon.y = y + 8;
		}

		redrawBlock();
		
		// Spawn Animation
		scale.set(0, 0);
		FlxTween.tween(this.scale, {x: 1, y: 1}, 0.3, {ease: FlxEase.backOut});
		alpha = 0;
		FlxTween.tween(this, {alpha: 1}, 0.2);
	}
	
	public function recalculateSize()
	{
		var currentX = label.width + 60; // Start after label + padding
		
		for (input in inputFields)
		{
			if (input.attachedBlock != null) {
				input.width = Math.max(80, input.attachedBlock.width);
			} else {
				input.width = 80;
			}
			
			// Update input visual size
			input.bg.setGraphicSize(Std.int(input.width), Std.int(input.height));
			input.bg.updateHitbox();
			
			currentX += input.width + 10;
		}
		
		minWidth = currentX + 10;
		redrawBlock();
		
		// Propagate up
		if (parentInput != null && parentInput.parentBlock != null) {
			parentInput.parentBlock.recalculateSize();
		}
	}

	public function redrawBlock()
	{
		var w = Std.int(Math.max(minWidth, width));
		var h = Std.int(minHeight);
		
		// Re-create graphic to ensure clean slate
		makeGraphic(w, h, FlxColor.TRANSPARENT);
		
		var color = FlxColor.fromInt(blockData.color);
		var darkColor = color.getDarkened(0.3);
		var lightColor = color.getLightened(0.3);
		
		var pixels = this.pixels;
		pixels.lock();
		
		// Draw Main Body
		var rect = new Rectangle(0, 0, w, h);
		
		if (isReporter) {
			// Pill shape (Rounded Rect approximation)
			// Main body
			pixels.fillRect(new Rectangle(2, 2, w - 4, h - 4), color);
			
			// Borders (Bevel)
			pixels.fillRect(new Rectangle(2, 0, w - 4, 2), lightColor); // Top
			pixels.fillRect(new Rectangle(2, h - 2, w - 4, 2), darkColor); // Bottom
			pixels.fillRect(new Rectangle(0, 2, 2, h - 4), lightColor); // Left
			pixels.fillRect(new Rectangle(w - 2, 2, 2, h - 4), darkColor); // Right
		}
		else {
			// Standard Block
			pixels.fillRect(rect, color);
			
			// 3D Bevel
			pixels.fillRect(new Rectangle(0, 0, w, 4), lightColor); // Top Highlight
			pixels.fillRect(new Rectangle(0, h - 4, w, 4), darkColor); // Bottom Shadow
			pixels.fillRect(new Rectangle(0, 0, 4, h), lightColor); // Left Highlight
			pixels.fillRect(new Rectangle(w - 4, 0, 4, h), darkColor); // Right Shadow
			
			// Notch Visuals
			// Top Bump (Light)
			pixels.fillRect(new Rectangle(20, 0, 20, 4), color); 
			// Bottom Notch (Dark - Socket)
			pixels.fillRect(new Rectangle(20, h - 4, 20, 4), 0xFF000000); // Black hole
		}
		
		pixels.unlock();
		this.width = w;
		this.height = h;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		// Follow Logic
		if (parentInput != null) {
			// Follow Input Field
			this.x = parentInput.bg.x;
			this.y = parentInput.bg.y + (parentInput.height - height) / 2; // Center vertically
		}
		else if (prevBlock != null && isSnapped)
		{
			this.x = prevBlock.x;
			this.y = prevBlock.y + prevBlock.height;
		}

		// Update Visuals Position
		label.x = x + 50;
		label.y = y + (isReporter ? 10 : 15);
		icon.x = x + 15;
		icon.y = y + (isReporter ? 8 : 12);
		
		// Update Inputs
		var currentX = x + label.width + 60;
		for (input in inputFields)
		{
			var inputY = y + (isReporter ? 5 : 10);
			input.updatePosition(currentX, inputY);
			input.update(elapsed);
			currentX += input.width + 10;
		}
		
		// Hover Animation
		if (isMouseOver(camera) && parentInput == null && prevBlock == null) { 
			if (scale.x < 1.05) {
				scale.x += elapsed * 0.5;
				scale.y += elapsed * 0.5;
			}
		} else {
			if (scale.x > 1.0) {
				scale.x -= elapsed * 0.5;
				scale.y -= elapsed * 0.5;
			}
		}
	}
	
	override public function draw()
	{
		super.draw();
		
		// Sync and draw children
		if (icon != null && icon.visible) {
			icon.scrollFactor.copyFrom(scrollFactor);
			icon.cameras = cameras;
			icon.draw();
		}
		
		if (label != null && label.visible) {
			label.scrollFactor.copyFrom(scrollFactor);
			label.cameras = cameras;
			label.draw();
		}
		
		for (input in inputFields) {
			if (input.bg != null) {
				input.bg.scrollFactor.copyFrom(scrollFactor);
				input.bg.cameras = cameras;
			}
			if (input.text != null) {
				input.text.scrollFactor.copyFrom(scrollFactor);
				input.text.cameras = cameras;
			}
			input.draw();
		}
	}
	
	public function isMouseOver(cam:FlxCamera = null):Bool {
        if (cam == null) cam = camera;
        if (cam == null) cam = FlxG.camera;
		var mouse = FlxG.mouse.getWorldPosition(cam);
		return (mouse.x >= x && mouse.x <= x + width && mouse.y >= y && mouse.y <= y + height);
	}
}

class InputField
{
	public var bg:FlxSprite;
	public var text:FlxText;
	public var width:Float;
	public var height:Float;
	public var value:Dynamic;
	public var type:String;
	public var isFocused:Bool = false;
	public var parentBlock:Block;
	
	// Attachment
	public var attachedBlock:Block = null;
	
	var cursorTimer:Float = 0;
	
	// Placeholder
	public var placeholder:String = "";
	public var placeholderText:FlxText;

	public function new(x:Float, y:Float, w:Float, h:Float, defaultVal:Dynamic, type:String, name:String = "")
	{
		this.width = w;
		this.height = h;
		this.value = defaultVal;
		this.type = type;
		this.placeholder = name;

		bg = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), FlxColor.WHITE);
		
		text = new FlxText(x + 2, y + 4, w - 4, Std.string(value), 14);
		text.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.BLACK, CENTER);
		
		placeholderText = new FlxText(x + 2, y + 4, w - 4, placeholder, 14);
		placeholderText.setFormat(Paths.font("vcr.ttf"), 14, 0xFF888888, CENTER);
		placeholderText.visible = false;
	}

	public function updatePosition(x:Float, y:Float)
	{
		bg.x = x;
		bg.y = y;
		text.x = x + 2;
		text.y = y + 4;
		placeholderText.x = x + 2;
		placeholderText.y = y + 4;
	}

	public function update(elapsed:Float)
	{
		// If has attached block, disable input
		if (attachedBlock != null) {
			bg.visible = false;
			text.visible = false;
			placeholderText.visible = false;
			return;
		} else {
			bg.visible = true;
			text.visible = true;
		}

		if (FlxG.mouse.justPressed)
		{
			var mouse = FlxG.mouse;
            var cam = (bg.cameras != null && bg.cameras.length > 0) ? bg.cameras[0] : FlxG.camera;
            var mPos = FlxG.mouse.getWorldPosition(cam);
            
			if (mPos.x >= bg.x && mPos.x <= bg.x + width &&
				mPos.y >= bg.y && mPos.y <= bg.y + height)
			{
				isFocused = true;
				bg.color = 0xFFFFFF00; // Yellow highlight
			}
			else
			{
				isFocused = false;
				bg.color = FlxColor.WHITE;
			}
		}

		if (isFocused)
		{
			handleInput();
			
			cursorTimer += elapsed;
			bg.alpha = (cursorTimer % 1.0 < 0.5) ? 1.0 : 0.8;
		}
		else
		{
			bg.alpha = 1.0;
		}
		
		// Placeholder logic
		if (text.text == "" && !isFocused) {
			placeholderText.visible = true;
		} else {
			placeholderText.visible = false;
		}
	}

	function handleInput()
	{
		var key = FlxG.keys.firstJustPressed();
		if (key != -1)
		{
			var keyName = FlxKey.toStringMap.get(key);
			
			if (key == FlxKey.BACKSPACE)
			{
				if (text.text.length > 0)
					text.text = text.text.substr(0, text.text.length - 1);
			}
			else if (key == FlxKey.ENTER || key == FlxKey.ESCAPE)
			{
				isFocused = false;
				bg.color = FlxColor.WHITE;
			}
			else if (keyName != null)
			{
				if (type == "number")
				{
					// Allow digits, minus, dot
					if ((key : Int) >= (FlxKey.ZERO : Int) && (key : Int) <= (FlxKey.NINE : Int)) {
						text.text += Std.string((key : Int) - (FlxKey.ZERO : Int));
					}
					else if ((key : Int) >= (FlxKey.NUMPADZERO : Int) && (key : Int) <= (FlxKey.NUMPADNINE : Int)) {
						text.text += Std.string((key : Int) - (FlxKey.NUMPADZERO : Int));
					}
					else if (key == FlxKey.PERIOD || key == FlxKey.NUMPADPERIOD) {
						if (text.text.indexOf(".") == -1) text.text += ".";
					}
					else if (key == FlxKey.MINUS || key == FlxKey.NUMPADMINUS) {
						if (text.text.length == 0) text.text += "-";
					}
				}
				else
				{
					// Basic text input
					var char = keyName;
					if (char.length == 1) {
						// Handle Shift for casing
						if (!FlxG.keys.pressed.SHIFT) {
							char = char.toLowerCase();
						}
						text.text += char;
					}
					else if (key == FlxKey.SPACE) {
						text.text += " ";
					}
					else if (key == FlxKey.MINUS) text.text += "-";
					else if (key == FlxKey.PLUS) text.text += "+";
					else if (key == FlxKey.LBRACKET) text.text += "[";
					else if (key == FlxKey.RBRACKET) text.text += "]";
					else if (key == FlxKey.SEMICOLON) text.text += ";";
					else if (key == FlxKey.QUOTE) text.text += "'";
					else if (key == FlxKey.COMMA) text.text += ",";
					else if (key == FlxKey.PERIOD) text.text += ".";
					else if (key == FlxKey.SLASH) text.text += "/";
					else if (key == FlxKey.BACKSLASH) text.text += "\\";
				}
			}
			
			value = text.text;
		}
	}

	public function draw()
	{
		if (bg.visible) {
			bg.draw();
			if (placeholderText.visible) {
				placeholderText.draw();
			} else {
				text.draw();
			}
		}
	}
}
