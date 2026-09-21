package editors.blockcode;

import editors.blockcode.BlockTypes;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.input.touch.FlxTouch;
import flixel.text.FlxText;
import openfl.display.BitmapData;

/** One BPM change of the song: the step and millisecond it switches to `bpm`. */
private typedef TimelineChange =
{
	var stepTime:Int;
	var songTime:Float;
	var stepCrochet:Float;
	var bpm:Float;
};

/**
 * Song timeline strip of the block-code editor: an mm:ss / step ruler, a draggable
 * playhead and the markers whose block stacks fire at that moment.
 *
 * Times are milliseconds in the same unit the caller feeds into `setCurrentTime()`
 * and receives back from `onSeek()`, so a `PlayState` can hand it
 * `Conductor.songPosition` and seek `FlxG.sound.music.time` with the result.
 *
 * Everything is drawn with plain `FlxSprite`s that are kept inside the rect given to
 * the constructor, so no camera mask is involved: the children are simply limited to
 * `cam`, which therefore has to be a camera the caller draws.
 */
class BlockTimeline extends FlxGroup
{
	public static inline var DEFAULT_SECONDS_ON_SCREEN:Float = 30;
	public static inline var DEFAULT_BPM:Float = 120;
	public static inline var DEFAULT_LENGTH_MS:Float = 180000;
	public static inline var LONG_PRESS_TIME:Float = 0.5;

	public static inline var COLOR_BG:Int = 0xFF16161E;
	public static inline var COLOR_ELAPSED:Int = 0xFF24283B;
	public static inline var COLOR_RULER:Int = 0xFF414868;
	public static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_PLAYHEAD:Int = 0xFFE0AF68;
	public static inline var COLOR_MARKER:Int = 0xFF9F6BFF;

	static inline var PRESS_NONE:Int = 0;
	static inline var PRESS_MARKER:Int = 1;
	static inline var PRESS_SEEK:Int = 2;

	static inline var MIN_SECONDS_ON_SCREEN:Float = 0.25;
	static inline var MAX_SECONDS_ON_SCREEN:Float = 3600;
	static inline var MIN_STEP_PX:Float = 8;
	static inline var MIN_BEAT_PX:Float = 8;
	static inline var MIN_SECTION_PX:Float = 8;
	static inline var MIN_SECOND_PX:Float = 8;
	static inline var MIN_LABEL_PX:Float = 46;
	static inline var FOLLOW_MARGIN:Float = 0.12;
	static inline var DRAG_SLOP_PX:Float = 3;
	static inline var PAN_FRACTION:Float = 0.6;
	static inline var PLAYHEAD_WIDTH:Int = 2;
	static inline var HANDLE_SIZE:Int = 9;
	static inline var MAX_LINES:Int = 512;
	static inline var MAX_RULER_LABELS:Int = 40;
	static inline var MAX_DIAMOND_CACHE:Int = 48;

	/** Second steps the ruler labels cycle through when the strip is zoomed out. */
	static var LABEL_SECONDS:Array<Int> = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600];

	/** Milliseconds the user asked to seek to (ruler / empty strip drag). */
	public var onSeek:Float->Void;

	/** Marker the user tapped. */
	public var onMarkerSelected:String->Void;

	/** Marker whose step changed while dragging. */
	public var onMarkerMoved:String->Void;

	/** Marker the user wants removed (long press or right click). */
	public var onMarkerRemove:String->Void;

	public var markers(default, null):Array<TimelineMarker> = [];
	public var selectedId(default, null):String = "";

	var cam:FlxCamera;

	var rectX:Float = 0;
	var rectY:Float = 0;
	var rectW:Float = 1;
	var rectH:Float = 1;

	var rulerH:Int = 0;
	var infoH:Int = 0;
	var laneY:Float = 0;
	var laneH:Int = 0;
	var rulerFontSize:Int = 10;
	var infoFontSize:Int = 10;
	var markerSize:Int = 11;
	var showRulerLabels:Bool = true;
	var showInfoLabel:Bool = true;

	var secondsOnScreen:Float = DEFAULT_SECONDS_ON_SCREEN;
	var viewStartMs:Float = 0;

	var lengthMs:Float = DEFAULT_LENGTH_MS;
	var trackBpm:Float = DEFAULT_BPM;
	var trackCrochet:Float = (60 / DEFAULT_BPM) * 1000;
	var trackStepCrochet:Float = (60 / DEFAULT_BPM) * 1000 / 4;
	var parsedChanges:Array<TimelineChange> = [];
	var changeList:Array<TimelineChange> = [];

	var currentMs:Float = 0;

	var dirtyRuler:Bool = true;
	var dirtyMarkers:Bool = true;

	var elapsed:FlxSprite;
	var layerGrid:FlxGroup;
	var layerRulerText:FlxGroup;
	var layerMarkers:FlxGroup;
	var layerMarkerText:FlxGroup;
	var layerPlayhead:FlxGroup;
	var layerInfo:FlxGroup;

	var playheadLine:FlxSprite;
	var playheadHandle:FlxSprite;
	var infoText:FlxText;
	var bpmText:FlxText;

	var gridBd:BitmapData;
	var lines:Array<FlxSprite> = [];
	var lineCursor:Int = 0;
	var rulerLabels:Array<FlxText> = [];
	var labelCursor:Int = 0;
	var diamondCache:Map<Int, BitmapData> = new Map();
	var diamondCacheCount:Int = 0;
	var markerSprites:Map<String, FlxSprite> = new Map();
	var markerLabels:Map<String, FlxText> = new Map();

	/**
	 * Recycled marker sprites / labels. Keeping them alive also keeps the shared
	 * diamond graphics of `diamondCache` from being disposed.
	 */
	var markerPool:Array<FlxSprite> = [];

	var labelPool:Array<FlxText> = [];
	var freeTimeIds:Map<String, Bool> = new Map();

	var pressKind:Int = PRESS_NONE;
	var pressMarkerId:String = "";
	var pressHeld:Float = 0;
	var pressMoved:Bool = false;
	var pressRemoveSent:Bool = false;
	var pressOffsetX:Float = 0;
	var lastSeekMs:Float = -1;

	var pointer:FlxPoint = FlxPoint.get();

	public function new(x:Float, y:Float, w:Float, h:Float, cam:FlxCamera)
	{
		super();

		rectX = Math.floor(x);
		rectY = Math.floor(y);
		rectW = Math.max(1, Math.floor(w));
		rectH = Math.max(1, Math.floor(h));
		this.cam = cam;

		computeLayout();
		buildSprites();
		rebuildChanges();
	}

	// ---------------------------------------------------------------------------------------
	// Public API
	// ---------------------------------------------------------------------------------------

	/** Song length / base BPM the strip falls back to before any chart data is known. */
	public function setSongInfo(lengthMs:Float, bpm:Float, stepCrochet:Float, crochet:Float):Void
	{
		if (lengthMs > 0)
			this.lengthMs = lengthMs;
		if (bpm > 0)
			trackBpm = bpm;

		if (crochet > 0)
			trackCrochet = crochet;
		else if (bpm > 0)
			trackCrochet = (60 / bpm) * 1000;

		if (stepCrochet > 0)
			trackStepCrochet = stepCrochet;
		else if (trackCrochet > 0)
			trackStepCrochet = trackCrochet / 4;

		rebuildChanges();
		syncMarkerTimes();
		clampView();
		markViewDirty();
	}

	/**
	 * BPM changes of the song, in `Conductor.BPMChangeEvent` shape
	 * (`stepTime`, `songTime`, optional `stepCrochet` / `bpm`). Entries are read
	 * defensively, so a plain `Array<Dynamic>` from a chart is fine.
	 */
	public function setBPMChanges(changes:Array<Dynamic>):Void
	{
		parsedChanges = [];
		if (changes != null)
		{
			for (entry in changes)
			{
				if (entry == null)
					continue;
				var change:Null<TimelineChange> = parseChange(entry);
				if (change == null)
					continue;
				parsedChanges.push(change);
			}
		}

		parsedChanges.sort(function(a:TimelineChange, b:TimelineChange):Int
		{
			if (a.stepTime == b.stepTime)
			{
				if (a.songTime < b.songTime)
					return -1;
				if (a.songTime > b.songTime)
					return 1;
				return 0;
			}
			return a.stepTime < b.stepTime ? -1 : 1;
		});

		rebuildChanges();
		syncMarkerTimes();
		clampView();
		markViewDirty();
	}

	/** Milliseconds the given step starts at, following the BPM change list. */
	public function stepToMs(step:Int):Float
	{
		var change:TimelineChange = changeAtStep(step);
		var crochet:Float = change.stepCrochet > 0 ? change.stepCrochet : trackStepCrochet;
		return change.songTime + (step - change.stepTime) * crochet;
	}

	/** (Fractional) step the given millisecond falls on, following the BPM change list. */
	public function msToStep(ms:Float):Float
	{
		var change:TimelineChange = changeAtMs(ms);
		var crochet:Float = change.stepCrochet > 0 ? change.stepCrochet : trackStepCrochet;
		if (crochet <= 0)
			return 0;
		return change.stepTime + (ms - change.songTime) / crochet;
	}

	/** Playhead position, in song milliseconds. Follows the song and pages the view. */
	public function setCurrentTime(ms:Float):Void
	{
		if (ms < 0)
			ms = 0;

		currentMs = ms;

		var x:Float = msToX(ms);
		if (x < rectX + rectW * FOLLOW_MARGIN || x > rectX + rectW * (1 - FOLLOW_MARGIN))
			setViewStart(ms - visibleMs() * FOLLOW_MARGIN);
	}

	/** Adds a marker, or updates the fields of the marker that already uses `m.id`. */
	public function addMarker(m:TimelineMarker):Void
	{
		if (m == null)
			return;

		var existing:TimelineMarker = getMarker(m.id);
		if (existing == null)
		{
			if (m.time <= 0 && m.step > 0)
				m.time = stepToMs(m.step);
			markers.push(m);
			markers.sort(compareMarkers);
		}
		else
		{
			existing.step = m.step;
			existing.time = m.time;
			existing.name = m.name;
			if (m.eventName != null)
				existing.eventName = m.eventName;
			if (m.color != null)
				existing.color = m.color;
			existing.locked = m.locked;
			markers.sort(compareMarkers);
		}

		markDirty();
	}

	/** Removes a marker and its cached sprites. */
	public function removeMarker(id:String):Void
	{
		for (i in 0...markers.length)
		{
			var m:TimelineMarker = markers[i];
			if (m == null || m.id != id)
				continue;
			markers.splice(i, 1);
			break;
		}

		freeTimeIds.remove(id);
		if (selectedId == id)
			selectedId = "";

		markDirty();
	}

	public function getMarker(id:String):Null<TimelineMarker>
	{
		if (id == null)
			return null;
		for (m in markers)
		{
			if (m != null && m.id == id)
				return m;
		}
		return null;
	}

	/**
	 * Highlights a marker. Does not raise `onMarkerSelected`; taps do, so a caller
	 * listening to that callback can call this back without looping.
	 */
	public function selectMarker(id:String):Void
	{
		var next:String = id == null ? "" : id;
		if (next.length > 0 && getMarker(next) == null)
			next = "";
		if (selectedId == next)
			return;
		selectedId = next;
		dirtyMarkers = true;
	}

	/** Seconds of song visible at once. Keeps the current position at the same spot. */
	public function setZoom(secondsOnScreen:Float):Void
	{
		var fraction:Float = visibleMs() > 0 ? clampF((currentMs - viewStartMs) / visibleMs(), 0, 1) : 0.5;
		applyZoom(secondsOnScreen, currentMs, fraction);
	}

	/** Forces a full redraw of the ruler and the markers. */
	public function markDirty():Void
	{
		dirtyRuler = true;
		dirtyMarkers = true;
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		handleInput(elapsed);

		if (dirtyRuler)
			refreshRuler();
		if (dirtyMarkers)
			refreshMarkers();

		updatePlayhead();
		updateInfoText();
	}

	override public function destroy():Void
	{
		onSeek = null;
		onMarkerSelected = null;
		onMarkerMoved = null;
		onMarkerRemove = null;

		lines = [];
		rulerLabels = [];
		markerSprites = new Map();
		markerLabels = new Map();
		markerPool = [];
		labelPool = [];
		diamondCache = new Map();
		diamondCacheCount = 0;
		freeTimeIds = new Map();
		parsedChanges = [];
		changeList = [];

		if (pointer != null)
		{
			pointer.put();
			pointer = null;
		}

		super.destroy();
	}

	// ---------------------------------------------------------------------------------------
	// Construction
	// ---------------------------------------------------------------------------------------

	function computeLayout():Void
	{
		rulerFontSize = clampI(Std.int(rectH * 0.2), 8, 12);
		infoFontSize = clampI(Std.int(rectH * 0.2), 8, 14);

		markerSize = clampI(Std.int(rectH * 0.34), 9, 15);
		if (markerSize % 2 == 0)
			markerSize++;

		rulerH = clampI(Std.int(rectH * 0.34), rulerFontSize + 5, Std.int(rectH));
		infoH = clampI(Std.int(rectH * 0.26), infoFontSize + 5, Std.int(rectH));

		if (rulerH + infoH > rectH)
		{
			infoH = Std.int(Math.max(0, rectH - rulerH));
			if (rulerH + infoH > rectH)
				rulerH = Std.int(Math.max(0, rectH - infoH));
		}

		laneY = rectY + rulerH;
		laneH = Std.int(Math.max(0, rectH - rulerH - infoH));

		showRulerLabels = rulerH >= rulerFontSize + 2;
		showInfoLabel = infoH >= infoFontSize + 2;
	}

	function buildSprites():Void
	{
		var bg:FlxSprite = new FlxSprite(rectX, rectY);
		bg.makeGraphic(Std.int(rectW), Std.int(rectH), COLOR_BG);
		addChild(bg);

		elapsed = new FlxSprite(rectX, rectY);
		elapsed.makeGraphic(Std.int(rectW), Std.int(rectH), COLOR_ELAPSED);
		elapsed.origin.set(0, 0);
		addChild(elapsed);

		layerGrid = addLayer();
		layerRulerText = addLayer();
		layerMarkers = addLayer();
		layerMarkerText = addLayer();
		layerPlayhead = addLayer();
		layerInfo = addLayer();

		gridBd = new BitmapData(1, Std.int(rectH), true, 0xFFFFFFFF);

		playheadLine = new FlxSprite(rectX, rectY);
		playheadLine.makeGraphic(PLAYHEAD_WIDTH, Std.int(rectH), COLOR_PLAYHEAD);
		playheadLine.origin.set(0, 0);
		applyCamera(playheadLine);
		layerPlayhead.add(playheadLine);

		playheadHandle = new FlxSprite(rectX, rectY);
		playheadHandle.loadGraphic(buildDiamond(HANDLE_SIZE, COLOR_PLAYHEAD, COLOR_BG));
		applyCamera(playheadHandle);
		layerPlayhead.add(playheadHandle);

		infoText = makeLabel(infoFontSize);
		layerInfo.add(infoText);
		bpmText = makeLabel(infoFontSize);
		layerInfo.add(bpmText);
	}

	function addLayer():FlxGroup
	{
		var layer:FlxGroup = new FlxGroup();
		add(layer);
		return layer;
	}

	function addChild(sprite:FlxSprite):FlxSprite
	{
		applyCamera(sprite);
		add(sprite);
		return sprite;
	}

	function applyCamera(sprite:FlxSprite):Void
	{
		if (cam != null)
			sprite.cameras = [cam];
	}

	function makeLabel(size:Int):FlxText
	{
		var label:FlxText = new FlxText(0, 0, 0, "", size);
		label.setFormat(Paths.font("vcr.ttf"), size, COLOR_TEXT, LEFT, FlxTextBorderStyle.OUTLINE, COLOR_BG);
		label.borderSize = 1.2;
		label.wordWrap = false;
		applyCamera(label);
		return label;
	}

	// ---------------------------------------------------------------------------------------
	// Song data
	// ---------------------------------------------------------------------------------------

	function parseChange(entry:Dynamic):Null<TimelineChange>
	{
		var stepTime:Float = readNumber(entry, "stepTime", Math.NaN);
		var songTime:Float = readNumber(entry, "songTime", Math.NaN);
		if (Math.isNaN(stepTime) || Math.isNaN(songTime))
			return null;

		var crochetStep:Float = readNumber(entry, "stepCrochet", Math.NaN);
		var entryBpm:Float = readNumber(entry, "bpm", 0);
		if (Math.isNaN(crochetStep))
			crochetStep = entryBpm > 0 ? (60 / entryBpm) * 1000 / 4 : 0;
		if (entryBpm <= 0 && crochetStep > 0)
			entryBpm = 60000 / (crochetStep * 4);

		var step:Int = Std.int(stepTime);
		if (step < 0)
			step = 0;

		return {
			stepTime: step,
			songTime: songTime,
			stepCrochet: crochetStep,
			bpm: entryBpm
		};
	}

	static function readNumber(source:Dynamic, field:String, fallback:Float):Float
	{
		var value:Dynamic = Reflect.field(source, field);
		return Std.isOfType(value, Float) ? (cast value : Float) : fallback;
	}

	function rebuildChanges():Void
	{
		changeList = [];
		if (parsedChanges.length == 0 || parsedChanges[0].stepTime > 0)
			changeList.push({
				stepTime: 0,
				songTime: 0,
				stepCrochet: trackStepCrochet,
				bpm: trackBpm
			});
		for (change in parsedChanges)
			changeList.push(change);
	}

	function changeAtStep(step:Float):TimelineChange
	{
		var found:TimelineChange = null;
		for (change in changeList)
		{
			if (change.stepTime <= step)
				found = change;
			else
				break;
		}
		return found != null ? found : baseChange();
	}

	function changeAtMs(ms:Float):TimelineChange
	{
		var found:TimelineChange = null;
		for (change in changeList)
		{
			if (change.songTime <= ms)
				found = change;
			else
				break;
		}
		if (found != null)
			return found;
		return changeList.length > 0 ? changeList[0] : baseChange();
	}

	function baseChange():TimelineChange
	{
		return {
			stepTime: 0,
			songTime: 0,
			stepCrochet: trackStepCrochet,
			bpm: trackBpm
		};
	}

	function stepCrochetAt(ms:Float):Float
	{
		var change:TimelineChange = changeAtMs(ms);
		return change.stepCrochet > 0 ? change.stepCrochet : trackStepCrochet;
	}

	function bpmAt(ms:Float):Float
	{
		var change:TimelineChange = changeAtMs(ms);
		return change.bpm > 0 ? change.bpm : trackBpm;
	}

	/** Re-derives the cached millisecond of every marker that is not held off-grid. */
	function syncMarkerTimes():Void
	{
		for (m in markers)
		{
			if (m == null || freeTimeIds.exists(m.id))
				continue;
			if (m.step <= 0 && m.time <= 0)
				continue;
			m.time = stepToMs(m.step);
		}
		dirtyMarkers = true;
	}

	static function compareMarkers(a:TimelineMarker, b:TimelineMarker):Int
	{
		if (a == null || b == null)
			return 0;
		if (a.time < b.time)
			return -1;
		if (a.time > b.time)
			return 1;
		return 0;
	}

	// ---------------------------------------------------------------------------------------
	// View / ruler maths
	// ---------------------------------------------------------------------------------------

	inline function visibleMs():Float
	{
		return secondsOnScreen * 1000;
	}

	inline function msPerPixel():Float
	{
		return visibleMs() / rectW;
	}

	function msToX(ms:Float):Float
	{
		return rectX + (ms - viewStartMs) / msPerPixel();
	}

	function msAt(x:Float):Float
	{
		return viewStartMs + (x - rectX) * msPerPixel();
	}

	function clampView():Void
	{
		var maxStart:Float = Math.max(0, Math.max(lengthMs, currentMs) - visibleMs());
		viewStartMs = clampF(viewStartMs, 0, maxStart);
	}

	function setViewStart(value:Float):Void
	{
		var before:Float = viewStartMs;
		viewStartMs = value;
		clampView();
		if (Math.abs(viewStartMs - before) > 0.01)
			markViewDirty();
	}

	function applyZoom(newSeconds:Float, anchorMs:Float, anchorFraction:Float):Void
	{
		var value:Float = clampF(newSeconds, MIN_SECONDS_ON_SCREEN, MAX_SECONDS_ON_SCREEN);
		if (Math.abs(value - secondsOnScreen) < 0.0001)
			return;

		secondsOnScreen = value;
		viewStartMs = anchorMs - visibleMs() * clampF(anchorFraction, 0, 1);
		clampView();
		markViewDirty();
	}

	function markViewDirty():Void
	{
		dirtyRuler = true;
		dirtyMarkers = true;
	}

	// ---------------------------------------------------------------------------------------
	// Drawing
	// ---------------------------------------------------------------------------------------

	function refreshRuler():Void
	{
		dirtyRuler = false;
		lineCursor = 0;
		labelCursor = 0;

		drawStepRaster();
		drawSecondTicks();

		for (i in lineCursor...lines.length)
			lines[i].visible = false;
		for (i in labelCursor...rulerLabels.length)
			rulerLabels[i].visible = false;
	}

	function drawStepRaster():Void
	{
		var firstStep:Float = msToStep(viewStartMs);
		var lastStep:Float = msToStep(viewStartMs + visibleMs());
		var stepPx:Float = Math.max(0.0001, stepCrochetAt(viewStartMs) / msPerPixel());

		if (stepPx * 16 >= MIN_SECTION_PX)
		{
			var from:Int = Std.int(Math.floor(firstStep / 16));
			var to:Int = Std.int(Math.ceil(lastStep / 16));
			for (section in from...(to + 1))
			{
				if (section < 0)
					continue;
				addLine(msToX(stepToMs(section * 16)), rectY, rectH, 2, COLOR_RULER, 0.55);
			}
		}

		if (stepPx * 4 >= MIN_BEAT_PX)
		{
			var from:Int = Std.int(Math.floor(firstStep / 4));
			var to:Int = Std.int(Math.ceil(lastStep / 4));
			for (beat in from...(to + 1))
			{
				if (beat < 0 || beat % 4 == 0)
					continue;
				addLine(msToX(stepToMs(beat * 4)), rectY, rectH, 1, COLOR_RULER, 0.32);
			}
		}

		if (stepPx >= MIN_STEP_PX)
		{
			var from:Int = Std.int(Math.ceil(firstStep));
			var to:Int = Std.int(Math.floor(lastStep));
			for (step in from...(to + 1))
			{
				if (step < 0 || step % 4 == 0)
					continue;
				addLine(msToX(stepToMs(step)), rectY, rectH, 1, COLOR_RULER, 0.14);
			}
		}
	}

	function drawSecondTicks():Void
	{
		var pxPerSecond:Float = 1000 / msPerPixel();
		var interval:Int = labelInterval(pxPerSecond);
		var firstSecond:Int = Std.int(Math.floor(viewStartMs / 1000));
		var lastSecond:Int = Std.int(Math.ceil((viewStartMs + visibleMs()) / 1000));
		var tickH:Float = clampF(rulerH * 0.28, 3, 7);
		var tickY:Float = rectY + rulerH - tickH;
		var showMinor:Bool = pxPerSecond >= MIN_SECOND_PX;

		for (second in firstSecond...(lastSecond + 1))
		{
			if (second < 0)
				continue;

			var x:Float = msToX(second * 1000.0);
			if (x < rectX - 1 || x > rectX + rectW + 1)
				continue;

			var major:Bool = (second % interval == 0);
			if (!major && !showMinor)
				continue;

			addLine(x, tickY, tickH, major ? 2 : 1, COLOR_RULER, major ? 1 : 0.6);

			if (major && showRulerLabels)
				addRulerLabel(formatTime(second * 1000.0, false), x + 3);
		}
	}

	static function labelInterval(pxPerSecond:Float):Int
	{
		for (seconds in LABEL_SECONDS)
		{
			if (seconds * pxPerSecond >= MIN_LABEL_PX)
				return seconds;
		}
		return LABEL_SECONDS[LABEL_SECONDS.length - 1];
	}

	function addRulerLabel(text:String, x:Float):Void
	{
		if (labelCursor >= MAX_RULER_LABELS)
			return;

		var width:Float = estimateTextWidth(text, rulerFontSize);
		if (x + width > rectX + rectW - 2)
			return;

		while (rulerLabels.length <= labelCursor)
		{
			var fresh:FlxText = makeLabel(rulerFontSize);
			rulerLabels.push(fresh);
			layerRulerText.add(fresh);
		}

		var label:FlxText = rulerLabels[labelCursor];
		labelCursor++;

		setLabelText(label, text);
		label.x = clampF(x, rectX + 2, Math.max(rectX + 2, rectX + rectW - 2 - width));
		label.y = clampF(rectY + 2, rectY, Math.max(rectY, rectY + rulerH - rulerFontSize * 1.3));
		label.visible = true;
	}

	function addLine(x:Float, y:Float, h:Float, w:Float, color:Int, alpha:Float):Void
	{
		if (h <= 0 || w <= 0)
			return;

		if (w > rectW)
			w = rectW;
		if (h > rectH)
			h = rectH;
		x = clampF(x, rectX, rectX + rectW - w);
		y = clampF(y, rectY, rectY + rectH - h);

		var sprite:FlxSprite = null;
		if (lineCursor < MAX_LINES)
		{
			while (lines.length <= lineCursor)
				lines.push(createLineSprite());
			sprite = lines[lineCursor];
		}
		lineCursor++;

		if (sprite == null)
			return;

		sprite.visible = true;
		sprite.x = Math.round(x);
		sprite.y = Math.round(y);
		sprite.scale.x = w;
		sprite.scale.y = h / rectH;
		sprite.color = color;
		sprite.alpha = alpha;
	}

	function createLineSprite():FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite(rectX, rectY);
		sprite.loadGraphic(gridBd);
		sprite.origin.set(0, 0);
		if (cam != null)
			sprite.cameras = [cam];
		layerGrid.add(sprite);
		return sprite;
	}

	function refreshMarkers():Void
	{
		dirtyMarkers = false;

		var live:Map<String, Bool> = new Map();
		for (m in markers)
		{
			if (m != null)
				live.set(m.id, true);
		}

		pruneSprites(live);

		var centerY:Float = markerCenterY();
		for (m in markers)
		{
			if (m == null)
				continue;
			layoutMarker(m, centerY);
		}
	}

	function pruneSprites(live:Map<String, Bool>):Void
	{
		var stale:Array<String> = [];
		for (id in markerSprites.keys())
		{
			if (!live.exists(id))
				stale.push(id);
		}
		for (id in stale)
		{
			var sprite:FlxSprite = markerSprites.get(id);
			markerSprites.remove(id);
			if (sprite != null)
			{
				sprite.visible = false;
				markerPool.push(sprite);
			}
		}

		stale = [];
		for (id in markerLabels.keys())
		{
			if (!live.exists(id))
				stale.push(id);
		}
		for (id in stale)
		{
			var label:FlxText = markerLabels.get(id);
			markerLabels.remove(id);
			if (label != null)
			{
				label.visible = false;
				labelPool.push(label);
			}
		}
	}

	function layoutMarker(m:TimelineMarker, centerY:Float):Void
	{
		var sprite:FlxSprite = getMarkerSprite(m.id);
		var color:Int = m.color != null ? m.color : COLOR_MARKER;
		var selected:Bool = (m.id == selectedId);

		sprite.loadGraphic(diamondFor(color, selected));
		sprite.x = clampF(markerX(m) - markerSize * 0.5, rectX, rectX + rectW - markerSize);
		sprite.y = centerY - markerSize * 0.5;

		var inView:Bool = m.time >= viewStartMs - markerSize && m.time <= viewStartMs + visibleMs() + markerSize;
		sprite.visible = inView;

		var label:FlxText = getMarkerLabel(m.id);
		if (!inView)
		{
			label.visible = false;
			return;
		}

		var text:String = (m.name != null && m.name.length > 0) ? m.name : ('Step ' + m.step);
		setLabelText(label, text);

		var width:Float = label.width;
		if (width > rectW - 4)
		{
			label.visible = false;
			return;
		}

		label.visible = true;
		var rightX:Float = sprite.x + markerSize + 3;
		var labelX:Float = rightX;
		if (labelX + width > rectX + rectW - 2)
			labelX = sprite.x - 3 - width;
		label.x = clampF(labelX, rectX + 2, Math.max(rectX + 2, rectX + rectW - 2 - width));
		label.y = clampF(centerY - rulerFontSize * 0.65, rectY, Math.max(rectY, rectY + rectH - rulerFontSize * 1.3));
	}

	function getMarkerSprite(id:String):FlxSprite
	{
		var sprite:FlxSprite = markerSprites.get(id);
		if (sprite != null)
			return sprite;

		if (markerPool.length > 0)
		{
			sprite = markerPool.pop();
		}
		else
		{
			sprite = new FlxSprite();
			applyCamera(sprite);
			layerMarkers.add(sprite);
		}

		markerSprites.set(id, sprite);
		return sprite;
	}

	function getMarkerLabel(id:String):FlxText
	{
		var label:FlxText = markerLabels.get(id);
		if (label != null)
			return label;

		if (labelPool.length > 0)
		{
			label = labelPool.pop();
		}
		else
		{
			label = makeLabel(rulerFontSize);
			layerMarkerText.add(label);
		}

		label.visible = false;
		markerLabels.set(id, label);
		return label;
	}

	function diamondFor(color:Int, selected:Bool):BitmapData
	{
		var key:Int = (color & 0xFFFFFF) | (selected ? 0x1000000 : 0);
		var found:BitmapData = diamondCache.get(key);
		if (found != null)
			return found;

		var built:BitmapData = buildDiamond(markerSize, color, selected ? COLOR_TEXT : COLOR_BG);
		if (diamondCacheCount < MAX_DIAMOND_CACHE)
		{
			diamondCache.set(key, built);
			diamondCacheCount++;
		}
		return built;
	}

	function buildDiamond(size:Int, fill:Int, outline:Int):BitmapData
	{
		if (size < 3)
			size = 3;
		if (size % 2 == 0)
			size++;

		var bitmap:BitmapData = new BitmapData(size, size, true, 0);
		var half:Int = Std.int((size - 1) / 2);
		for (row in 0...size)
		{
			var distance:Int = row <= half ? row : size - 1 - row;
			var run:Int = distance * 2 + 1;
			var start:Int = half - distance;
			for (column in 0...run)
			{
				var edge:Bool = (column == 0 || column == run - 1);
				bitmap.setPixel32(start + column, row, edge ? outline : fill);
			}
		}
		return bitmap;
	}

	function updatePlayhead():Void
	{
		var x:Float = clampF(msToX(currentMs), rectX, rectX + rectW);

		playheadLine.x = clampF(x, rectX, rectX + rectW - PLAYHEAD_WIDTH);
		playheadHandle.visible = rectH >= HANDLE_SIZE + 2;
		playheadHandle.x = clampF(x - HANDLE_SIZE * 0.5, rectX, rectX + rectW - HANDLE_SIZE);
		playheadHandle.y = clampF(rectY, rectY, rectY + rectH - HANDLE_SIZE);

		var filled:Float = x - rectX;
		elapsed.visible = filled > 0.5;
		elapsed.scale.x = filled <= 0.5 ? 0.001 : clampF(filled / rectW, 0.001, 1);
	}

	function updateInfoText():Void
	{
		if (!showInfoLabel)
		{
			infoText.visible = false;
			bpmText.visible = false;
			return;
		}

		var bandY:Float = rectY + rectH - infoH;
		var textY:Float = clampF(bandY + (infoH - infoFontSize) * 0.5, bandY, Math.max(bandY, rectY + rectH - infoFontSize * 1.3));

		var bpmLabel:String = 'BPM ' + formatBpm(bpmAt(currentMs));
		var bpmWidth:Float = estimateTextWidth(bpmLabel, infoFontSize);
		var bpmX:Float = rectX + rectW;
		if (bpmWidth <= rectW - 8 && rectX + rectW - 4 - bpmWidth >= rectX + 4)
		{
			bpmX = rectX + rectW - 4 - bpmWidth;
			setLabelText(bpmText, bpmLabel);
			bpmText.x = bpmX;
			bpmText.y = textY;
			bpmText.visible = true;
		}
		else
		{
			bpmText.visible = false;
		}

		var step:Int = Std.int(Math.round(msToStep(currentMs)));
		if (step < 0)
			step = 0;
		var beat:Int = Std.int(Math.floor(step / 4));
		var clock:String = formatTime(currentMs, true);
		var room:Float = bpmX - rectX - 12;

		var full:String = 'Step $step   Beat $beat   $clock';
		var short:String = 'Step $step   $clock';
		var shown:String = null;
		if (estimateTextWidth(full, infoFontSize) <= room)
			shown = full;
		else if (estimateTextWidth(short, infoFontSize) <= room)
			shown = short;
		else if (estimateTextWidth(clock, infoFontSize) <= room)
			shown = clock;

		if (shown == null)
		{
			infoText.visible = false;
			return;
		}

		setLabelText(infoText, shown);
		infoText.x = rectX + 4;
		infoText.y = textY;
		infoText.visible = true;
	}

	function setLabelText(label:FlxText, text:String):Void
	{
		if (label.text != text)
			label.text = text;
	}

	// ---------------------------------------------------------------------------------------
	// Input
	// ---------------------------------------------------------------------------------------

	function handleInput(elapsed:Float):Void
	{
		var touch:FlxTouch = getPrimaryTouch();
		var justPressed:Bool = (touch != null) ? touch.justPressed : FlxG.mouse.justPressed;
		var held:Bool = (touch != null) ? touch.pressed : FlxG.mouse.pressed;
		var rightPressed:Bool = (touch == null) && FlxG.mouse.justPressedRight;

		var world:FlxPoint = getPointerWorld();
		var px:Float = world.x;
		var py:Float = world.y;
		var over:Bool = px >= rectX && px <= rectX + rectW && py >= rectY && py <= rectY + rectH;

		if (over && touch == null && FlxG.mouse.wheel != 0)
			zoomByWheel(px);

		if (justPressed)
			beginPress(px, py, over);
		else if (rightPressed && over)
			requestRemovalAt(px, py);

		if (pressKind == PRESS_NONE)
			return;

		if (held)
			continuePress(px, py, elapsed);
		else
			endPress();
	}

	function getPrimaryTouch():FlxTouch
	{
		for (touch in FlxG.touches.list)
		{
			if (touch != null)
				return touch;
		}
		return null;
	}

	function getPointerWorld():FlxPoint
	{
		var camera:FlxCamera = cam != null ? cam : FlxG.camera;
		var touch:FlxTouch = getPrimaryTouch();
		if (touch != null)
			return touch.getWorldPosition(camera, pointer);
		return FlxG.mouse.getWorldPosition(camera, pointer);
	}

	function beginPress(px:Float, py:Float, over:Bool):Void
	{
		pressKind = PRESS_NONE;
		pressMarkerId = "";
		pressHeld = 0;
		pressMoved = false;
		pressRemoveSent = false;
		lastSeekMs = -1;

		if (!over)
			return;

		var marker:TimelineMarker = markerAt(px, py);
		if (marker != null)
		{
			pressKind = PRESS_MARKER;
			pressMarkerId = marker.id;
			pressOffsetX = px - markerX(marker);
			selectMarker(marker.id);
			if (onMarkerSelected != null)
				onMarkerSelected(marker.id);
			playSound('scrollMenu');
			return;
		}

		pressKind = PRESS_SEEK;
		requestSeek(msAt(px));
	}

	function continuePress(px:Float, py:Float, elapsed:Float):Void
	{
		if (px < rectX || px > rectX + rectW)
			panView(px, elapsed);

		if (pressKind == PRESS_MARKER)
		{
			var marker:TimelineMarker = getMarker(pressMarkerId);
			if (marker == null)
			{
				endPress();
				return;
			}

			if (!pressMoved && Math.abs(px - (markerX(marker) + pressOffsetX)) > DRAG_SLOP_PX)
				pressMoved = true;

			if (pressMoved)
			{
				dragMarkerTo(marker, msAt(px - pressOffsetX));
				return;
			}

			pressHeld += elapsed;
			if (pressHeld >= LONG_PRESS_TIME && !pressRemoveSent)
			{
				pressRemoveSent = true;
				if (onMarkerRemove != null)
					onMarkerRemove(marker.id);
				playSound('cancelMenu');
			}
		}
		else if (pressKind == PRESS_SEEK)
		{
			requestSeek(msAt(px));
		}
	}

	function endPress():Void
	{
		pressKind = PRESS_NONE;
		pressMarkerId = "";
		pressHeld = 0;
		pressMoved = false;
	}

	function dragMarkerTo(marker:TimelineMarker, targetMs:Float):Void
	{
		if (targetMs < 0)
			targetMs = 0;

		var newStep:Int = Std.int(Math.round(msToStep(targetMs)));
		if (newStep < 0)
			newStep = 0;

		var newTime:Float;
		if (FlxG.keys.pressed.SHIFT)
		{
			newTime = targetMs;
			freeTimeIds.set(marker.id, true);
		}
		else
		{
			newTime = stepToMs(newStep);
			freeTimeIds.remove(marker.id);
		}

		if (marker.step == newStep && Math.abs(marker.time - newTime) < 0.5)
			return;

		marker.step = newStep;
		marker.time = newTime;
		dirtyMarkers = true;

		if (onMarkerMoved != null)
			onMarkerMoved(marker.id);
	}

	function requestSeek(ms:Float):Void
	{
		var target:Float = clampF(ms, 0, Math.max(lengthMs, currentMs));
		if (Math.abs(target - lastSeekMs) < 0.5)
			return;

		lastSeekMs = target;
		currentMs = target;
		if (onSeek != null)
			onSeek(target);
	}

	function requestRemovalAt(px:Float, py:Float):Void
	{
		var marker:TimelineMarker = markerAt(px, py);
		if (marker == null)
			return;
		if (onMarkerRemove != null)
			onMarkerRemove(marker.id);
		playSound('cancelMenu');
	}

	function panView(px:Float, elapsed:Float):Void
	{
		var shift:Float = 0;
		if (px > rectX + rectW)
			shift = visibleMs() * PAN_FRACTION * elapsed;
		else if (px < rectX)
			shift = -visibleMs() * PAN_FRACTION * elapsed;

		if (shift == 0)
			return;
		setViewStart(viewStartMs + shift);
	}

	function zoomByWheel(px:Float):Void
	{
		var wheel:Int = FlxG.mouse.wheel;
		if (wheel == 0)
			return;

		var anchorMs:Float = msAt(px);
		var fraction:Float = clampF((px - rectX) / rectW, 0, 1);
		applyZoom(secondsOnScreen * Math.pow(0.88, wheel), anchorMs, fraction);
	}

	function markerAt(px:Float, py:Float):Null<TimelineMarker>
	{
		var radius:Float = markerSize * 0.5 + 3;
		var centerY:Float = markerCenterY();

		for (i in 0...markers.length)
		{
			var marker:TimelineMarker = markers[markers.length - 1 - i];
			if (marker == null)
				continue;
			if (Math.abs(px - markerX(marker)) <= radius && Math.abs(py - centerY) <= radius)
				return marker;
		}
		return null;
	}

	function markerX(marker:TimelineMarker):Float
	{
		return msToX(marker.time);
	}

	function markerCenterY():Float
	{
		return clampF(laneY + laneH * 0.5, rectY + markerSize * 0.5, rectY + rectH - markerSize * 0.5);
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
	// Small helpers
	// ---------------------------------------------------------------------------------------

	static function formatTime(ms:Float, withMillis:Bool):String
	{
		if (ms < 0)
			ms = 0;

		var total:Int = Std.int(Math.floor(ms));
		var minutes:Int = Std.int(total / 60000);
		var seconds:Int = Std.int((total % 60000) / 1000);
		var millis:Int = total % 1000;

		var text:String = (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
		if (withMillis)
			text += "." + StringTools.lpad(Std.string(millis), "0", 3);
		return text;
	}

	static function formatBpm(bpm:Float):String
	{
		var rounded:Float = Math.round(bpm * 10) / 10;
		if (rounded == Math.round(rounded))
			return Std.string(Std.int(rounded));
		return Std.string(rounded);
	}

	/** Widest the given text can render, used instead of measuring (which re-renders fonts). */
	static function estimateTextWidth(text:String, size:Int):Float
	{
		if (text == null)
			return 0;
		return text.length * size * 0.72 + 2;
	}

	static inline function clampF(value:Float, low:Float, high:Float):Float
	{
		if (high < low)
			high = low;
		if (value < low)
			return low;
		return value > high ? high : value;
	}

	static inline function clampI(value:Int, low:Int, high:Int):Int
	{
		if (high < low)
			high = low;
		if (value < low)
			return low;
		return value > high ? high : value;
	}
}
