package editors.blockcode;

import editors.blockcode.BlockTypes;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.input.touch.FlxTouch;
import flixel.text.FlxText;
import openfl.display.BitmapData;
import openfl.geom.Matrix;
import openfl.media.Sound;

/** One BPM change of the song: the step and millisecond it switches to `bpm`. */
private typedef TimelineChange =
{
	var stepTime:Int;
	var songTime:Float;
	var stepCrochet:Float;
	var bpm:Float;
};

/**
 * An opaque readout floating over the strip: a 1px border, a filled body and the text.
 * The text is inset from the border on every side, so a label can never touch the frame.
 */
private class TimelineChip
{
	public var border:FlxSprite;
	public var bg:FlxSprite;
	public var text:FlxText;

	/** Text currently rendered; kept so an unchanged label never re-renders the font. */
	public var label:String = '';

	public var width:Float = 0;
	public var height:Float = 0;

	public function new(border:FlxSprite, bg:FlxSprite, text:FlxText)
	{
		this.border = border;
		this.bg = bg;
		this.text = text;
	}

	public function setText(value:String):Void
	{
		if (value == null)
			value = '';

		if (label == value)
			return;

		label = value;
		text.text = value;
	}

	public function setColors(borderColor:Int, bodyColor:Int):Void
	{
		border.color = borderColor;
		bg.color = bodyColor;
	}

	public function setFontSize(value:Int):Void
	{
		var size:Int = value < 6 ? 6 : value;
		if (text.size == size)
			return;

		text.size = size;
		label = '';
	}

	public function hide():Void
	{
		border.visible = false;
		bg.visible = false;
		text.visible = false;
	}

	public function place(x:Float, y:Float, w:Float, h:Float, textX:Float, textY:Float):Void
	{
		width = w;
		height = h;

		border.visible = true;
		border.x = Math.round(x);
		border.y = Math.round(y);
		border.scale.x = Math.max(1, w);
		border.scale.y = Math.max(1, h);

		bg.visible = true;
		bg.x = Math.round(x) + 1;
		bg.y = Math.round(y) + 1;
		bg.scale.x = Math.max(1, w - 2);
		bg.scale.y = Math.max(1, h - 2);

		text.visible = true;
		text.x = Math.round(textX);
		text.y = Math.round(textY);
	}
}

/**
 * Song timeline strip of the block-code editor: an adaptive mm:ss / step ruler, a draggable
 * playhead and the markers whose block stacks fire at that moment.
 *
 * Times are milliseconds in the same unit the caller feeds into `setCurrentTime()`
 * and receives back from `onSeek()`, so a `PlayState` can hand it
 * `Conductor.songPosition` and seek `FlxG.sound.music.time` with the result.
 *
 * The strip is laid out entirely from {@link BlockLayout}: every band, radius, handle and font
 * derives from the viewport, the ruler picks a label interval that cannot overlap, and the
 * zoom buttons exist because a phone has no mouse wheel. The given rect is never left:
 *
 * ```
 * +-----------------------------------------------------------------+
 * |  [Step… ]              [12:00.000]              [view 30s] [+][-]|  chip band
 * |-----------------------------------------------------------------|  ruler: ticks + labels
 * |          *              *        *                              |  lane: markers
 * +-----------------------------------------------------------------+
 * ```
 *
 * Everything is drawn with plain `FlxSprite`s that are kept inside the rect given to
 * the constructor, so no camera mask is involved: the children are simply limited to
 * `cam`, which therefore has to be a camera the caller draws.
 *
 * Removal of a marker is a right click on desktop or a double tap on a marker anywhere;
 * a long press arms free (off-grid) dragging instead, per the responsive rework.
 */
class BlockTimeline extends FlxGroup
{
	public static inline var DEFAULT_SECONDS_ON_SCREEN:Float = 30;
	public static inline var DEFAULT_BPM:Float = 120;
	public static inline var DEFAULT_LENGTH_MS:Float = 180000;
	public static inline var LONG_PRESS_TIME:Float = 0.5;
	public static inline var DOUBLE_TAP_TIME:Float = 0.34;

	public static inline var COLOR_BG:Int = 0xFF16161E;
	public static inline var COLOR_ELAPSED:Int = 0xFF24283B;
	public static inline var COLOR_RULER:Int = 0xFF414868;
	public static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_PLAYHEAD:Int = 0xFFE0AF68;
	public static inline var COLOR_MARKER:Int = 0xFF9F6BFF;

	/** Palette-derived colours added by the responsive rework (frame, banding, chips, buttons). */
	public static inline var COLOR_FRAME:Int = 0xFF414868;

	public static inline var COLOR_BAND:Int = 0xFF1F2333;
	public static inline var COLOR_CHIP_BORDER:Int = 0xFF414868;
	public static inline var COLOR_CHIP_BG:Int = 0xFF1F2333;
	public static inline var COLOR_BUTTON_DOWN_BORDER:Int = 0xFF3D59A1;
	public static inline var COLOR_BUTTON_DOWN_BG:Int = 0xFF2A3555;
	public static inline var COLOR_ACCENT:Int = 0xFF3D59A1;

	static inline var PRESS_NONE:Int = 0;
	static inline var PRESS_MARKER:Int = 1;
	static inline var PRESS_SEEK:Int = 2;
	static inline var PRESS_BUTTON:Int = 3;

	static inline var BUTTON_NONE:Int = -1;
	static inline var BUTTON_PLUS:Int = 0;
	static inline var BUTTON_MINUS:Int = 1;

	/** No pointer id: the gesture belongs to the mouse. */
	static inline var NO_POINTER:Int = -1;

	static inline var MIN_SECONDS_ON_SCREEN:Float = 0.25;
	static inline var MAX_SECONDS_ON_SCREEN:Float = 3600;

	/** The two pixel paddings the spec asks for: 2px inside the frame, 1px inside a chip. */
	static inline var INSET_PX:Float = 2;

	static inline var ZOOM_FACTOR:Float = 0.72;
	static inline var MIN_STEP_PX:Float = 6;
	static inline var MIN_LABEL_PX:Float = 64;
	static inline var MIN_MINOR_PX:Float = 7;
	static inline var MIN_BAND_PX:Float = 26;
	static inline var PORTRAIT_MIN_LABEL:Float = 4;
	static inline var FOLLOW_MARGIN:Float = 0.12;
	static inline var DRAG_SLOP_PX:Float = 3;
	static inline var PAN_FRACTION:Float = 0.6;
	static inline var BUTTON_FIRST_REPEAT:Float = 0.36;
	static inline var BUTTON_REPEAT_RATE:Float = 0.17;
	static inline var CHIP_REFRESH:Float = 0.05;
	static inline var CHIP_GAP_RATIO:Float = 0.72;
	static inline var RANGE_CHIP_MAX_RATIO:Float = 0.4;

	static inline var MAX_LINES:Int = 640;
	static inline var MAX_RULER_LABELS:Int = 48;
	static inline var MAX_CIRCLE_CACHE:Int = 64;
	static inline var MAX_TICK_LOOPS:Int = 1024;
	static inline var KEY_SELECTED:Int = 1 << 24;
	static inline var KEY_LOCKED:Int = 1 << 25;
	static inline var KEY_SIZE_SHIFT:Int = 26;

	/** Cell sizes of the mark raster: zooming out moves to the next element of this ladder. */
	static var LABEL_LADDER:Array<Float> = [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600];

	/** Milliseconds the user asked to seek to (ruler / empty strip drag). */
	public var onSeek:Float->Void;

	/** Marker the user tapped. */
	public var onMarkerSelected:String->Void;

	/** Marker whose step changed while dragging. */
	public var onMarkerMoved:String->Void;

	/** Marker the user wants removed (right click or double tap). */
	public var onMarkerRemove:String->Void;

	public var markers(default, null):Array<TimelineMarker> = [];
	public var selectedId(default, null):String = '';

	var cam:FlxCamera;

	var rectX:Float = 0;
	var rectY:Float = 0;
	var rectW:Float = 1;
	var rectH:Float = 1;

	/** Area inside the 1-2px frame plus the 2px padding: nothing here touches the edge. */
	var contentX:Float = 0;

	var contentY:Float = 0;
	var contentW:Float = 1;
	var contentH:Float = 1;

	/** Time-mapped area (chips, ruler, lane) — the right column is kept for the zoom buttons. */
	var trackX:Float = 0;

	var trackW:Float = 1;

	/** Vertical bands: chip readouts / ruler / marker lane. */
	var chipBandH:Float = 0;

	var chipH:Float = 0;
	var timeTop:Float = 0;
	var timeBottom:Float = 0;
	var timeH:Float = 0;
	var rulerH:Float = 0;
	var laneY:Float = 0;
	var laneH:Float = 0;
	var tickH:Float = 0;
	var rulerLabelH:Float = 0;

	var zoomColX:Float = 0;
	var zoomBtnW:Float = 0;
	var zoomBtnH:Float = 0;
	var zoomPlusY:Float = 0;
	var zoomMinusY:Float = 0;

	var frameW:Float = 1;
	var gap:Float = 3;
	var scaleF:Float = 1;
	var touch:Float = 34;
	var markerRadius:Float = 9;
	var playheadW:Float = 2;
	var handleW:Float = 34;
	var handleH:Float = 8;
	var showHandle:Bool = true;
	var showRulerLabels:Bool = true;

	var chipFontSize:Int = 13;
	var rulerFontSize:Int = 13;
	var buttonFontSize:Int = 18;

	/** Signature of the viewport the current metrics were built for. */
	var metricKey:String = '';

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

	/** Ruler resolution and raster density, recomputed per refresh. */
	var labelEvery:Float = 1;

	var labelPrecision:Int = 0;
	var stepPx:Float = 0;
	var sectionPx:Float = 0;

	var frame:FlxSprite;
	var bg:FlxSprite;
	var elapsed:FlxSprite;
	var timeTopLine:FlxSprite;
	var laneLine:FlxSprite;
	var layerGrid:FlxGroup;
	var layerRulerText:FlxGroup;
	var layerMarkers:FlxGroup;
	var layerMarkerText:FlxGroup;
	var layerPlayhead:FlxGroup;
	var layerInfo:FlxGroup;

	var playheadLine:FlxSprite;
	var playheadHandle:FlxSprite;
	var markerChip:TimelineChip;
	var chipInfo:TimelineChip;
	var chipRange:TimelineChip;
	var chipTime:TimelineChip;
	var chipPlus:TimelineChip;
	var chipMinus:TimelineChip;

	/** 1x1 white bitmap every rectangle sprite is scaled from, so metrics never rebuild graphics. */
	var rectBd:BitmapData;

	var handleBd:BitmapData;
	var handleBdW:Int = 0;
	var handleBdH:Int = 0;

	var lines:Array<FlxSprite> = [];
	var lineCursor:Int = 0;
	var rulerLabels:Array<FlxText> = [];
	var labelCursor:Int = 0;
	var circleCache:Map<Int, BitmapData> = new Map();
	var circleCacheCount:Int = 0;
	var markerSprites:Map<String, FlxSprite> = new Map();
	var markerCenters:Map<String, Float> = new Map();
	var markerPool:Array<FlxSprite> = [];

	var soundCache:Map<String, Sound> = new Map();
	var failedSounds:Map<String, Bool> = new Map();

	var pressKind:Int = PRESS_NONE;
	var pressMarkerId:String = '';
	var pressButton:Int = BUTTON_NONE;
	var pressFree:Bool = false;
	var pressHeld:Float = 0;
	var pressMoved:Bool = false;
	var buttonHold:Float = 0;
	var buttonRepeats:Int = 0;
	var pressOffsetX:Float = 0;
	var lastSeekMs:Float = -1;
	var grabbingPlayhead:Bool = false;
	var pointerId:Int = NO_POINTER;
	var pointerX:Float = 0;
	var pointerY:Float = 0;
	var pointer:FlxPoint = FlxPoint.get();

	/** Markers the user dragged off the step grid: their cached ms is authoritative. */
	var freeTimeIds:Map<String, Bool> = new Map();

	var gestureClock:Float = 0;
	var lastTapTime:Float = -1;
	var lastTapId:String = '';

	/** ms the chip readouts were last built for, so millisecond text is not re-rendered at 60 Hz. */
	var chipMs:Float = 0;

	var chipStep:Int = 0;
	var chipBpm:Float = DEFAULT_BPM;
	var chipTimer:Float = CHIP_REFRESH;

	/** Text fallbacks of the two corner chips, rebuilt together with the throttled clock. */
	var chipInfoOptions:Array<String> = [];

	var chipRangeOptions:Array<String> = [];

	public function new(x:Float, y:Float, w:Float, h:Float, cam:FlxCamera)
	{
		super();

		rectX = Math.floor(x);
		rectY = Math.floor(y);
		rectW = Math.max(1, Math.floor(w));
		rectH = Math.max(1, Math.floor(h));
		this.cam = cam;

		rectBd = new BitmapData(1, 1, true, 0xFFFFFFFF);

		buildSprites();
		applyMetrics();
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
	 * defensively, so a plain `Array<Dynamic>` from a chart is fine: a broken or
	 * half-filled entry is skipped instead of throwing.
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
		if (!Math.isFinite(ms) || ms < 0)
			return;

		currentMs = ms;

		// A finger owns the position while it scrubs: the song must not page the view back.
		if (pressKind == PRESS_SEEK)
			return;

		var x:Float = msToX(ms);
		if (x < trackX + trackW * FOLLOW_MARGIN || x > trackX + trackW * (1 - FOLLOW_MARGIN))
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

	/** Removes a marker and its cached sprite. */
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
			selectedId = '';

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
		var next:String = id == null ? '' : id;
		if (next.length > 0 && getMarker(next) == null)
			next = '';
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

	/** Seconds currently visible on the strip (added by the responsive rework). */
	public function getSecondsOnScreen():Float
	{
		return secondsOnScreen;
	}

	/** Multiplies the visible range; `factor < 1` zooms in. Anchored on the playhead. */
	public function zoomBy(factor:Float):Void
	{
		if (!Math.isFinite(factor) || factor <= 0)
			return;

		var fraction:Float = visibleMs() > 0 ? clampF((currentMs - viewStartMs) / visibleMs(), 0, 1) : 0.5;
		applyZoom(secondsOnScreen * factor, currentMs, fraction);
	}

	/** Forces a full redraw of the ruler and the markers. */
	public function markDirty():Void
	{
		dirtyRuler = true;
		dirtyMarkers = true;
	}

	/** Repositions the strip; the substate calls this when the viewport changed size. */
	public function resize(x:Float, y:Float, w:Float, h:Float):Void
	{
		rectX = Math.floor(x);
		rectY = Math.floor(y);
		rectW = Math.max(1, Math.floor(w));
		rectH = Math.max(1, Math.floor(h));
		applyMetrics();
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		BlockLayout.ensure();
		if (metricKey != buildMetricKey())
			applyMetrics();

		handleInput(elapsed);

		if (dirtyRuler)
			refreshRuler();
		if (dirtyMarkers)
			refreshMarkers();

		updatePlayhead();
		updateChips(elapsed);
		updateButtons();
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
		markerCenters = new Map();
		markerPool = [];
		circleCache = new Map();
		circleCacheCount = 0;
		freeTimeIds = new Map();
		soundCache = new Map();
		failedSounds = new Map();
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
	// Metrics
	// ---------------------------------------------------------------------------------------

	/** Identity of the viewport + rect the current metrics belong to. */
	function buildMetricKey():String
	{
		return BlockLayout.describe() + '|' + BlockLayout.touchSize() + '|' + rectX + ',' + rectY + ',' + rectW + ',' + rectH;
	}

	/**
	 * Turns the rect the caller gave us into every band, radius and font of the strip.
	 * All of it is derived from {@link BlockLayout}, which is what makes the same code read
	 * well on a 1280x720 window and on a 2340x1080 phone.
	 */
	function applyMetrics():Void
	{
		BlockLayout.ensure();
		metricKey = buildMetricKey();

		scaleF = BlockLayout.scale;
		touch = BlockLayout.touchSize();
		frameW = Math.max(1, Math.round(scaleF));
		gap = Math.max(3, 3 * scaleF);

		contentX = rectX + frameW + INSET_PX;
		contentY = rectY + frameW + INSET_PX;
		contentW = Math.max(24, rectW - (frameW + INSET_PX) * 2);
		contentH = Math.max(24, rectH - (frameW + INSET_PX) * 2);

		rulerFontSize = BlockLayout.font('small');
		chipFontSize = BlockLayout.portrait ? BlockLayout.font('tiny') : BlockLayout.font('small');
		buttonFontSize = BlockLayout.font('title');

		markerRadius = Math.max(7, 9 * scaleF);
		playheadW = clampF(Math.round(3 * scaleF), 2, 4);
		handleW = touch;
		handleH = clampF(Math.round(5 * scaleF), 6, 12);

		// Right column: two thumb-sized zoom buttons, stacked and vertically centred.
		zoomBtnW = Math.min(touch, Math.max(22, contentW * 0.18));
		zoomBtnH = Math.min(touch, Math.max(16, (contentH - gap) * 0.5));
		zoomColX = contentX + contentW - zoomBtnW;
		trackX = contentX;
		trackW = Math.max(48, zoomColX - gap - contentX);

		var columnH:Float = zoomBtnH * 2 + gap;
		var columnTop:Float = contentY + Math.max(0, (contentH - columnH) * 0.5);
		zoomPlusY = columnTop;
		zoomMinusY = columnTop + zoomBtnH + gap;

		// Chip band, ruler and marker lane share the remaining height.
		var chipPadV:Float = Math.max(2, Math.round(3 * scaleF));
		chipH = Math.round(chipFontSize * 1.2) + chipPadV * 2;
		chipBandH = chipH;

		var remaining:Float = Math.max(16, contentH - chipBandH - gap);
		tickH = clampF(6 * scaleF, 4, 10);
		rulerLabelH = Math.round(rulerFontSize * 1.25);

		var markerD:Float = markerRadius * 2;
		var rulerNeed:Float = rulerLabelH + tickH + 3;
		var rulerMax:Float = Math.max(10, remaining - (markerD + gap + 2));
		rulerH = Math.max(8, clampF(remaining * 0.46, Math.min(rulerNeed, rulerMax), rulerMax));

		timeTop = contentY + chipBandH + gap;
		timeBottom = contentY + contentH;
		timeH = Math.max(8, timeBottom - timeTop);
		laneY = timeTop + rulerH;
		laneH = Math.max(6, timeBottom - laneY);

		showHandle = (handleH + 2 <= rulerH);
		showRulerLabels = (rulerLabelH + tickH + 2 <= rulerH);

		if (markerChip != null)
			markerChip.setFontSize(chipFontSize);
		if (chipInfo != null)
			chipInfo.setFontSize(chipFontSize);
		if (chipRange != null)
			chipRange.setFontSize(chipFontSize);
		if (chipTime != null)
			chipTime.setFontSize(chipFontSize);
		if (chipPlus != null)
			chipPlus.setFontSize(buttonFontSize);
		if (chipMinus != null)
			chipMinus.setFontSize(buttonFontSize);

		layoutChrome();
		rebuildHandle();
		markViewDirty();
	}

	/** Places everything that does not depend on the song: frame, fills, separators, buttons. */
	function layoutChrome():Void
	{
		frame.visible = true;
		frame.x = rectX;
		frame.y = rectY;
		frame.scale.x = rectW;
		frame.scale.y = rectH;

		bg.visible = true;
		bg.x = contentX;
		bg.y = contentY;
		bg.scale.x = contentW;
		bg.scale.y = contentH;

		timeTopLine.visible = true;
		timeTopLine.x = contentX;
		timeTopLine.y = timeTop - 1;
		timeTopLine.scale.x = contentW;
		timeTopLine.scale.y = 1;

		laneLine.visible = true;
		laneLine.x = trackX;
		laneLine.y = laneY - 1;
		laneLine.scale.x = trackW;
		laneLine.scale.y = 1;

		elapsed.y = timeTop;
		elapsed.scale.y = timeH;

		playheadLine.y = timeTop;
		playheadLine.scale.y = timeH;
		playheadLine.scale.x = playheadW;

		var padX:Float = Math.max(4, 5 * scaleF);
		placeChip(chipPlus, zoomColX, zoomPlusY, zoomBtnW, zoomBtnH, padX, true);
		placeChip(chipMinus, zoomColX, zoomMinusY, zoomBtnW, zoomBtnH, padX, true);
	}

	function buildSprites():Void
	{
		frame = makeRect(COLOR_FRAME);
		add(frame);

		bg = makeRect(COLOR_BG);
		add(bg);

		elapsed = makeRect(COLOR_ELAPSED, 0.85);
		add(elapsed);

		layerGrid = addLayer();
		layerRulerText = addLayer();
		layerMarkers = addLayer();
		layerMarkerText = addLayer();
		layerPlayhead = addLayer();
		layerInfo = addLayer();

		// Band separators belong with the raster: they follow the same metrics as the grid.
		timeTopLine = makeRect(COLOR_FRAME, 0.45);
		laneLine = makeRect(COLOR_FRAME, 0.4);
		layerGrid.add(timeTopLine);
		layerGrid.add(laneLine);

		playheadLine = makeRect(COLOR_PLAYHEAD, 0.95);
		layerPlayhead.add(playheadLine);

		playheadHandle = new FlxSprite(0, 0);
		playheadHandle.origin.set(0, 0);
		playheadHandle.visible = false;
		applyCamera(playheadHandle);
		layerPlayhead.add(playheadHandle);

		chipInfo = makeChip(layerInfo, chipFontSize);
		chipRange = makeChip(layerInfo, chipFontSize);
		chipTime = makeChip(layerInfo, chipFontSize);
		chipPlus = makeChip(layerInfo, buttonFontSize);
		chipMinus = makeChip(layerInfo, buttonFontSize);
		chipPlus.setText('+');
		chipMinus.setText('-');

		markerChip = makeChip(layerMarkerText, chipFontSize);
	}

	function addLayer():FlxGroup
	{
		var layer:FlxGroup = new FlxGroup();
		add(layer);
		return layer;
	}

	function applyCamera(sprite:FlxSprite):Void
	{
		if (cam != null)
			sprite.cameras = [cam];
	}

	/** A colourable rectangle: the shared 1x1 bitmap scaled to whatever size is needed. */
	function makeRect(color:Int, alpha:Float = 1):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite(0, 0);
		sprite.loadGraphic(rectBd);
		sprite.origin.set(0, 0);
		sprite.color = color;
		sprite.alpha = alpha;
		sprite.visible = false;
		applyCamera(sprite);
		return sprite;
	}

	function makeLabel(size:Int, outlined:Bool = false):FlxText
	{
		var label:FlxText = new FlxText(0, 0, 0, '', size);
		if (outlined)
			label.setFormat(Paths.font('vcr.ttf'), size, COLOR_TEXT, LEFT, FlxTextBorderStyle.OUTLINE, COLOR_BG);
		else
			label.setFormat(Paths.font('vcr.ttf'), size, COLOR_TEXT, LEFT);
		label.borderSize = 1.2;
		label.wordWrap = false;
		label.visible = false;
		applyCamera(label);
		return label;
	}

	function makeChip(layer:FlxGroup, size:Int):TimelineChip
	{
		var border:FlxSprite = makeRect(COLOR_CHIP_BORDER);
		var body:FlxSprite = makeRect(COLOR_CHIP_BG);
		var text:FlxText = makeLabel(size);
		layer.add(border);
		layer.add(body);
		layer.add(text);
		return new TimelineChip(border, body, text);
	}

	/** Places a chip so that neither its text nor its body can touch the chip's frame. */
	function placeChip(chip:TimelineChip, x:Float, y:Float, w:Float, h:Float, padX:Float, centered:Bool = false):Void
	{
		var textX:Float = x + 1 + padX;
		if (centered)
			textX = x + (w - estimateTextWidth(chip.label, chip.text.size)) * 0.5;

		chip.place(x, y, w, h, textX, y + (h - chip.text.size * 1.2) * 0.5);
	}

	function rebuildHandle():Void
	{
		var w:Int = Std.int(Math.max(6, Math.round(handleW)));
		var h:Int = Std.int(Math.max(4, Math.round(handleH)));
		if (handleBd != null && handleBdW == w && handleBdH == h)
			return;

		handleBd = buildHandle(w, h, COLOR_PLAYHEAD);
		handleBdW = w;
		handleBdH = h;
		playheadHandle.loadGraphic(handleBd);
		playheadHandle.origin.set(0, 0);
	}

	// ---------------------------------------------------------------------------------------
	// Song data
	// ---------------------------------------------------------------------------------------

	function parseChange(entry:Dynamic):Null<TimelineChange>
	{
		var stepTime:Float = readNumber(entry, 'stepTime', Math.NaN);
		var songTime:Float = readNumber(entry, 'songTime', Math.NaN);
		if (!Math.isFinite(stepTime) || !Math.isFinite(songTime))
			return null;

		var crochetStep:Float = readNumber(entry, 'stepCrochet', Math.NaN);
		var entryBpm:Float = readNumber(entry, 'bpm', 0);
		if (!Math.isFinite(crochetStep) || crochetStep <= 0)
			crochetStep = entryBpm > 0 ? (60 / entryBpm) * 1000 / 4 : 0;
		if (entryBpm <= 0 && crochetStep > 0)
			entryBpm = 60000 / (crochetStep * 4);

		var step:Int = Math.isFinite(stepTime) ? Std.int(stepTime) : 0;
		if (step < 0)
			step = 0;

		return {
			stepTime: step,
			songTime: Math.isFinite(songTime) ? songTime : 0,
			stepCrochet: Math.isFinite(crochetStep) && crochetStep > 0 ? crochetStep : 0,
			bpm: Math.isFinite(entryBpm) && entryBpm > 0 ? entryBpm : 0};
	}

	/**
	 * Reads a number off a chart entry. `BPMChangeEvent.stepTime` is an `Int`, so an
	 * integer has to be accepted as well as a float; anything else is ignored.
	 */
	static function readNumber(source:Dynamic, field:String, fallback:Float):Float
	{
		if (source == null)
			return fallback;

		var value:Dynamic = Reflect.field(source, field);
		if (value == null)
			return fallback;

		if (Std.isOfType(value, Int))
			return (cast value : Int) + 0.0;

		if (Std.isOfType(value, Float))
		{
			var number:Float = (cast value : Float);
			return Math.isFinite(number) ? number : fallback;
		}

		return fallback;
	}

	function rebuildChanges():Void
	{
		changeList = [];
		if (parsedChanges.length == 0 || parsedChanges[0].stepTime > 0)
			changeList.push(baseChange());
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
		return visibleMs() / Math.max(1, trackW);
	}

	function msToX(ms:Float):Float
	{
		return trackX + (ms - viewStartMs) / msPerPixel();
	}

	function msAt(x:Float):Float
	{
		return viewStartMs + (x - trackX) * msPerPixel();
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
		if (!Math.isFinite(value) || Math.abs(value - secondsOnScreen) < 0.0001)
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

		computeRaster();
		drawBanding();
		drawStepRaster();
		drawTicks();

		for (i in lineCursor...lines.length)
			lines[i].visible = false;
		for (i in labelCursor...rulerLabels.length)
			rulerLabels[i].visible = false;
	}

	/** Step density and the label cell of the current view; both drive what may be drawn. */
	function computeRaster():Void
	{
		var crochet:Float = stepCrochetAt(viewStartMs);
		var perPixel:Float = msPerPixel();
		stepPx = (crochet > 0 && perPixel > 0) ? crochet / perPixel : 0;
		sectionPx = stepPx * 16;
		labelEvery = pickLabelInterval();
		labelPrecision = precisionFor(labelEvery);
	}

	/** Largest label cell (in seconds) that still leaves MIN_LABEL_PX between two labels. */
	function pickLabelInterval():Float
	{
		if (trackW <= 0 || secondsOnScreen <= 0)
			return 1;

		var pxPerSecond:Float = trackW / secondsOnScreen;
		var needed:Float = MIN_LABEL_PX * scaleF;
		var picked:Float = LABEL_LADDER[LABEL_LADDER.length - 1];

		for (seconds in LABEL_LADDER)
		{
			if (seconds * pxPerSecond >= needed)
			{
				picked = seconds;
				break;
			}
		}

		// Portrait labels are as wide as the rule but the window is far shorter: never denser
		// than one label every 4 seconds, which keeps mm:ss readable on a phone.
		if (BlockLayout.portrait && picked < PORTRAIT_MIN_LABEL)
			picked = PORTRAIT_MIN_LABEL;

		return picked;
	}

	static function precisionFor(interval:Float):Int
	{
		if (interval >= 1)
			return 0;
		if (interval >= 0.5)
			return 1;
		if (interval >= 0.1)
			return 2;
		return 3;
	}

	/** Alternating section stripes, drawn only while a section is wide enough to read. */
	function drawBanding():Void
	{
		if (sectionPx < MIN_BAND_PX * scaleF)
			return;

		var firstStep:Float = msToStep(viewStartMs);
		var lastStep:Float = msToStep(viewStartMs + visibleMs());
		if (!Math.isFinite(firstStep) || !Math.isFinite(lastStep))
			return;

		var from:Int = Std.int(Math.floor(firstStep / 16));
		var to:Int = Std.int(Math.ceil(lastStep / 16));
		if (to - from > 256)
			return;

		for (section in (from + 1)...(to + 1))
		{
			if (section <= 0 || section % 2 == 0)
				continue;

			var startMs:Float = stepToMs(section * 16);
			var endMs:Float = stepToMs((section + 1) * 16);
			if (!Math.isFinite(startMs) || !Math.isFinite(endMs) || endMs <= startMs)
				continue;

			addLine(msToX(startMs), timeTop, (endMs - startMs) / msPerPixel(), timeH, COLOR_BAND, 0.55);
		}
	}

	/** Sections, beats and (when there is room) single steps, each at its own weight. */
	function drawStepRaster():Void
	{
		if (stepPx <= 0 || trackW <= 0)
			return;

		var firstStep:Float = msToStep(viewStartMs);
		var lastStep:Float = msToStep(viewStartMs + visibleMs());
		if (!Math.isFinite(firstStep) || !Math.isFinite(lastStep))
			return;

		var threshold:Float = MIN_STEP_PX * scaleF;

		// The finest raster that has room wins: sections always, beats from 9.6px per step,
		// single steps from 6px per step. Nothing is drawn when even a section is too thin.
		if (sectionPx >= threshold)
			drawStepLines(16, 2, 0.5, firstStep, lastStep);
		if (stepPx * 4 >= threshold * 1.6)
			drawStepLines(4, 1, 0.3, firstStep, lastStep);
		if (stepPx >= threshold)
			drawStepLines(1, 1, 0.13, firstStep, lastStep);
	}

	function drawStepLines(every:Int, width:Float, alpha:Float, firstStep:Float, lastStep:Float):Void
	{
		var from:Int = Std.int(Math.floor(firstStep / every));
		var to:Int = Std.int(Math.ceil(lastStep / every));
		if (to < from)
			return;

		// A guard on top of the pixel thresholds: never flood the sprite pool.
		if (to - from > MAX_LINES / 3)
			return;

		for (index in from...(to + 1))
		{
			if (index < 0)
				continue;

			var x:Float = msToX(stepToMs(index * every));
			if (!Math.isFinite(x))
				continue;

			addLine(x - width * 0.5, timeTop, width, timeH, COLOR_RULER, alpha);
		}
	}

	/** Second ticks: majors carry a label, minors sit at a quarter of the label cell. */
	function drawTicks():Void
	{
		var majorMs:Float = labelEvery * 1000;
		if (majorMs <= 0 || msPerPixel() <= 0)
			return;

		var minorMs:Float = majorMs / 4;
		var end:Float = viewStartMs + visibleMs();
		var start:Float = Math.floor(viewStartMs / minorMs) * minorMs;
		var loops:Float = (end - start) / minorMs;
		if (loops > MAX_TICK_LOOPS)
		{
			// Defensive: fall back to majors rather than iterating for thousands of frames.
			minorMs = majorMs;
			start = Math.floor(viewStartMs / majorMs) * majorMs;
		}

		var showMinor:Bool = (minorMs / msPerPixel()) >= (MIN_MINOR_PX * scaleF);
		var tickTop:Float = laneY - tickH;
		var lastLabelRight:Float = -1e9;
		var guard:Int = 0;

		var ms:Float = start;
		while (ms <= end + minorMs && guard < MAX_TICK_LOOPS + 4)
		{
			guard++;

			var index:Float = Math.round(ms / minorMs);
			var major:Bool = Math.abs(index % 4) < 0.0001;

			if (major || showMinor)
			{
				var x:Float = msToX(ms);
				if (Math.isFinite(x) && x >= trackX - 1 && x <= trackX + trackW + 1)
				{
					if (major)
						addLine(x - 1, tickTop, 2, tickH, COLOR_RULER, 1);
					else
						addLine(x, laneY - tickH * 0.62, 1, tickH * 0.62, COLOR_RULER, 0.55);
				}

				if (major && ms >= 0)
					lastLabelRight = addRulerLabel(formatClock(ms, labelPrecision), x, lastLabelRight);
			}

			ms += minorMs;
		}
	}

	/**
	 * Draws one ruler label and returns the right edge of the label row, so the next
	 * label is only placed when the two cannot touch. Returns `null` when there is no
	 * room at all.
	 */
	function addRulerLabel(text:String, tickX:Float, lastRight:Float):Float
	{
		if (!showRulerLabels || labelCursor >= MAX_RULER_LABELS)
			return lastRight;

		var labelGap:Float = Math.max(4, 5 * scaleF);
		var width:Float = estimateTextWidth(text, rulerFontSize);
		var x:Float = tickX + labelGap;
		if (x + width > trackX + trackW - 1 || x < lastRight + labelGap)
			return lastRight;

		while (rulerLabels.length <= labelCursor)
		{
			var fresh:FlxText = makeLabel(rulerFontSize, true);
			rulerLabels.push(fresh);
			layerRulerText.add(fresh);
		}

		var label:FlxText = rulerLabels[labelCursor];
		labelCursor++;

		if (label.text != text)
			label.text = text;

		var labelY:Float = laneY - tickH - rulerLabelH - 1;
		if (labelY < timeTop + 1)
			labelY = timeTop + 1;

		label.x = Math.round(x);
		label.y = Math.round(labelY);
		label.visible = true;

		return x + width;
	}

	/** Pooled rectangle: the pool grows on demand and never exceeds {@link MAX_LINES}. */
	function addLine(x:Float, y:Float, w:Float, h:Float, color:Int, alpha:Float):Void
	{
		if (w <= 0 || h <= 0)
			return;
		if (x >= trackX + trackW || x + w <= trackX)
			return;

		var left:Float = Math.max(x, trackX);
		var right:Float = Math.min(x + w, trackX + trackW);
		if (right - left <= 0)
			return;

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
		sprite.x = left;
		sprite.y = y;
		sprite.scale.x = right - left;
		sprite.scale.y = h;
		sprite.color = color;
		sprite.alpha = alpha;
	}

	function createLineSprite():FlxSprite
	{
		var sprite:FlxSprite = makeRect(COLOR_RULER);
		layerGrid.add(sprite);
		return sprite;
	}

	// ---------------------------------------------------------------------------------------
	// Markers
	// ---------------------------------------------------------------------------------------

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
		markerCenters.clear();

		var laneCenter:Float = laneY + laneH * 0.5;
		var stack:Int = 0;
		var previousX:Float = -1e9;
		var selected:Null<TimelineMarker> = null;

		for (m in markers)
		{
			if (m == null)
				continue;

			var x:Float = msToX(m.time);
			if (!Math.isFinite(x))
				continue;

			// Markers sitting on the same step stack around the lane centre instead of hiding
			// each other; the offset stays inside the lane.
			if (x - previousX < markerRadius * 1.6)
				stack++;
			else
				stack = 0;
			previousX = x;

			var centerY:Float = laneCenter;
			if (stack > 0)
			{
				var ring:Int = Std.int(Math.ceil(stack / 2));
				var direction:Float = (stack % 2 == 1) ? -1 : 1;
				centerY = clampF(laneCenter + direction * ring * markerRadius * 0.55, laneY + markerRadius, laneY + laneH - markerRadius);
			}

			markerCenters.set(m.id, centerY);
			layoutMarker(m, x, centerY);

			if (m.id == selectedId)
				selected = m;
		}

		layoutMarkerChip(selected);
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
			markerCenters.remove(id);
			if (sprite != null)
			{
				sprite.visible = false;
				markerPool.push(sprite);
			}
		}
	}

	function layoutMarker(m:TimelineMarker, x:Float, centerY:Float):Void
	{
		var sprite:FlxSprite = getMarkerSprite(m.id);
		var diameter:Float = markerRadius * 2;
		var inView:Bool = (x + diameter >= trackX - 2) && (x - diameter <= trackX + trackW + 2);

		sprite.visible = inView;
		if (!inView)
			return;

		var color:Int = normalizeColor(m.color != null ? m.color : COLOR_MARKER);
		var selected:Bool = (m.id == selectedId);
		var grabbed:Bool = (pressKind == PRESS_MARKER && pressMarkerId == m.id);
		var bitmap:BitmapData = circleFor(color, selected, m.locked == true);

		if (sprite.graphic == null || sprite.graphic.bitmap != bitmap)
			sprite.loadGraphic(bitmap);
		sprite.origin.set(markerRadius, markerRadius);

		var bump:Float = grabbed ? 1.28 : (selected ? 1.12 : 1);
		sprite.scale.set(bump, bump);
		sprite.x = clampF(x - markerRadius, trackX - markerRadius, trackX + trackW - markerRadius);
		sprite.y = centerY - markerRadius;
	}

	/** Name chip of the selected marker; the only marker text the strip draws. */
	function layoutMarkerChip(selected:Null<TimelineMarker>):Void
	{
		if (markerChip == null)
			return;

		if (selected == null || chipH > laneH || laneH < 10)
		{
			markerChip.hide();
			return;
		}

		var centerY:Float = markerCenterOf(selected);
		var x:Float = msToX(selected.time);
		if (!Math.isFinite(x) || x < trackX - markerRadius * 2 || x > trackX + trackW + markerRadius * 2)
		{
			markerChip.hide();
			return;
		}

		var padX:Float = Math.max(4, 5 * scaleF);
		var name:String = (selected.name != null && selected.name.length > 0) ? selected.name : ('Step ' + selected.step);
		var maxChars:Int = Std.int(Math.max(4, (trackW * 0.42 - 2 - padX * 2) / (chipFontSize * CHIP_GAP_RATIO)));
		markerChip.setText(fitText(name, maxChars));

		var width:Float = chipWidth(markerChip.label, chipFontSize, padX);
		var gapX:Float = Math.max(3, 4 * scaleF);
		var chipX:Float = x + markerRadius + gapX;
		if (chipX + width > trackX + trackW)
			chipX = x - markerRadius - gapX - width;

		chipX = clampF(chipX, trackX, Math.max(trackX, trackX + trackW - width));
		var chipY:Float = clampF(centerY - chipH * 0.5, laneY, Math.max(laneY, laneY + laneH - chipH));

		placeChip(markerChip, chipX, chipY, width, chipH, padX);
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
			sprite = new FlxSprite(0, 0);
			sprite.origin.set(0, 0);
			applyCamera(sprite);
			layerMarkers.add(sprite);
		}

		markerSprites.set(id, sprite);
		return sprite;
	}

	function markerX(marker:TimelineMarker):Float
	{
		return msToX(marker.time);
	}

	function markerCenterOf(marker:TimelineMarker):Float
	{
		if (marker == null)
			return laneY + laneH * 0.5;

		var found:Null<Float> = markerCenters.get(marker.id);
		if (found != null)
			return found;

		return laneY + laneH * 0.5;
	}

	// Cached according to colour, selection state, lock state and diameter.
	function circleFor(color:Int, selected:Bool, locked:Bool):BitmapData
	{
		var size:Int = clampI(Std.int(Math.round(markerRadius * 2)), 6, 60);
		var key:Int = (color & 0xFFFFFF) | (selected ? KEY_SELECTED : 0) | (locked ? KEY_LOCKED : 0) | (size << KEY_SIZE_SHIFT);
		var found:BitmapData = circleCache.get(key);
		if (found != null)
			return found;

		var outline:Int = selected ? COLOR_TEXT : shade(color, 0.4);
		var ring:Float = Math.max(2, Math.round(2 * scaleF));
		var built:BitmapData = buildCircle(size, color, outline, ring, locked);

		if (circleCacheCount < MAX_CIRCLE_CACHE)
		{
			circleCache.set(key, built);
			circleCacheCount++;
		}

		return built;
	}

	/** Supersampled disc: a coloured fill, a `ring` px outline, an optional lock core. */
	static function buildCircle(size:Int, fill:Int, outline:Int, ring:Float, locked:Bool):BitmapData
	{
		var superSample:Int = 3;
		var big:Int = Std.int(Math.max(6, size * superSample));
		var source:BitmapData = new BitmapData(big, big, true, 0);
		var center:Float = (big - 1) * 0.5;
		var outer:Float = big * 0.5;
		var inner:Float = Math.max(0, outer - ring * superSample);
		var core:Float = inner * 0.38;

		for (row in 0...big)
		{
			var dy:Float = row - center;
			for (column in 0...big)
			{
				var dx:Float = column - center;
				var distance:Float = Math.sqrt(dx * dx + dy * dy);
				if (distance > outer)
					continue;

				var pixel:Int = fill;
				if (distance >= inner)
					pixel = outline;
				else if (locked && distance <= core)
					pixel = outline;

				source.setPixel32(column, row, pixel);
			}
		}

		var result:BitmapData = new BitmapData(size, size, true, 0);
		var matrix:Matrix = new Matrix();
		matrix.scale(1 / superSample, 1 / superSample);
		result.draw(source, matrix, null, null, null, true);
		source.dispose();

		return result;
	}

	/** Downward flag that sits on top of the playhead and is as wide as a touch target. */
	static function buildHandle(w:Int, h:Int, color:Int):BitmapData
	{
		var bitmap:BitmapData = new BitmapData(w, h, true, 0);
		var half:Float = (w - 1) * 0.5;

		for (row in 0...h)
		{
			var progress:Float = (h > 1) ? row / (h - 1) : 0;
			var run:Int = Std.int(Math.max(1, Math.round(w * (1 - progress))));
			var start:Int = Std.int(Math.max(0, Math.round(half - (run - 1) * 0.5)));

			for (column in 0...run)
			{
				var x:Int = start + column;
				if (x >= 0 && x < w)
					bitmap.setPixel32(x, row, color);
			}
		}

		var edge:Int = shade(color, 0.35);
		for (column in 0...w)
			bitmap.setPixel32(column, 0, edge);

		return bitmap;
	}

	// ---------------------------------------------------------------------------------------
	// Playhead
	// ---------------------------------------------------------------------------------------

	function updatePlayhead():Void
	{
		var target:Float = msToX(currentMs);
		if (!Math.isFinite(target))
			target = trackX;

		var x:Float = clampF(target, trackX, trackX + trackW);
		playheadLine.visible = true;
		playheadLine.x = clampF(x - playheadW * 0.5, trackX, Math.max(trackX, trackX + trackW - playheadW));
		playheadLine.y = timeTop;
		playheadLine.scale.x = playheadW;
		playheadLine.scale.y = timeH;
		playheadLine.alpha = grabbingPlayhead ? 1 : 0.92;

		playheadHandle.visible = showHandle && handleBd != null;
		if (playheadHandle.visible)
		{
			// Centred on the line, but never pushed under the zoom column or over the border.
			var handleRight:Float = Math.max(contentX + handleW, zoomColX - gap);
			playheadHandle.x = clampF(x - handleW * 0.5, contentX, handleRight - handleW);
			playheadHandle.y = timeTop;
		}

		var filled:Float = Math.max(0, x - contentX);
		elapsed.visible = filled > 0.5;
		elapsed.x = contentX;
		elapsed.y = timeTop;
		elapsed.scale.x = (filled <= 0.5) ? 0.001 : Math.min(filled, contentW);
		elapsed.scale.y = timeH;
	}

	// ---------------------------------------------------------------------------------------
	// Readouts and buttons
	// ---------------------------------------------------------------------------------------

	function updateChips(elapsed:Float):Void
	{
		chipTimer += elapsed;
		if (chipTimer >= CHIP_REFRESH)
		{
			// The millisecond digits are rebuilt on a 20 Hz clock: at 60 Hz every frame would
			// re-render three fonts for a difference nobody can read.
			chipTimer = 0;
			chipMs = currentMs;
			chipStep = Std.int(Math.max(0, Math.round(msToStep(chipMs))));
			chipBpm = bpmAt(chipMs);
			chipInfoOptions = infoVariants();
			chipRangeOptions = rangeVariants();
		}

		layoutChips();
	}

	/**
	 * Corner readout, visible range and the zoom buttons. Every text has shorter fallbacks,
	 * so the strip degrades to a clock instead of drawing text over text.
	 */
	function layoutChips():Void
	{
		var right:Float = zoomColX - gap;
		var width:Float = Math.max(0, right - trackX);
		var padX:Float = Math.max(4, 5 * scaleF);
		var top:Float = contentY + Math.max(0, (chipBandH - chipH) * 0.5);

		if (width < chipFontSize * 4)
		{
			chipInfo.hide();
			chipRange.hide();
			chipTime.hide();
			return;
		}

		var rangeOptions:Array<String> = chipRangeOptions;
		var infoOptions:Array<String> = chipInfoOptions;

		// Priority: the longest readout wins, but it has to leave the visible-range chip its
		// place. If no pair fits at all the range chip is dropped before the readout shrinks,
		// and only when even the plain clock is too wide is everything hidden.
		var infoText:Null<String> = null;
		var infoWidth:Float = 0;
		var rangeText:Null<String> = null;
		var rangeWidth:Float = 0;

		for (rangeCandidate in rangeOptions)
		{
			var rangeCandidateWidth:Float = chipWidth(rangeCandidate, chipFontSize, padX);
			if (rangeCandidateWidth > width * RANGE_CHIP_MAX_RATIO)
				continue;

			for (candidate in infoOptions)
			{
				var candidateWidth:Float = chipWidth(candidate, chipFontSize, padX);
				if (candidateWidth + rangeCandidateWidth + gap * 2 > width)
					continue;

				infoText = candidate;
				infoWidth = candidateWidth;
				rangeText = rangeCandidate;
				rangeWidth = rangeCandidateWidth;
				break;
			}

			if (infoText != null)
				break;
		}

		if (infoText == null)
		{
			for (candidate in infoOptions)
			{
				var candidateWidth:Float = chipWidth(candidate, chipFontSize, padX);
				if (candidateWidth > width)
					continue;

				infoText = candidate;
				infoWidth = candidateWidth;
				break;
			}
		}

		if (infoText == null)
		{
			chipInfo.hide();
			chipRange.hide();
			chipTime.hide();
			return;
		}

		chipInfo.setText(infoText);
		placeChip(chipInfo, trackX, top, infoWidth, chipH, padX);

		if (rangeText != null)
		{
			chipRange.setText(rangeText);
			placeChip(chipRange, right - rangeWidth, top, rangeWidth, chipH, padX);
		}
		else
		{
			chipRange.hide();
		}

		layoutTimeChip(top, trackX + infoWidth + gap, (rangeText != null) ? right - rangeWidth - gap : right, padX);
	}

	/** The time chip follows the playhead but is always pushed clear of its neighbours. */
	function layoutTimeChip(top:Float, leftLimit:Float, rightLimit:Float, padX:Float):Void
	{
		var span:Float = rightLimit - leftLimit;
		if (span < chipFontSize * 3.2)
		{
			chipTime.hide();
			return;
		}

		var precision:Int = 3;
		var text:String = formatClock(chipMs, precision);
		var width:Float = chipWidth(text, chipFontSize, padX);

		if (width > span)
		{
			precision = 0;
			text = formatClock(chipMs, precision);
			width = chipWidth(text, chipFontSize, padX);
		}

		if (width > span)
		{
			chipTime.hide();
			return;
		}

		chipTime.setText(text);

		var playhead:Float = clampF(msToX(currentMs), trackX, trackX + trackW);
		var x:Float = clampF(playhead - width * 0.5, leftLimit, Math.max(leftLimit, rightLimit - width));
		placeChip(chipTime, x, top, width, chipH, padX);
	}

	/** The corner readout, longest form first: the layout picks the first one that fits. */
	function infoVariants():Array<String>
	{
		var beat:Int = Std.int(Math.floor(chipStep / 4));
		var clock:String = formatClock(chipMs, 3);
		var bpm:String = formatBpm(chipBpm);

		var variants:Array<String> = [];
		variants.push('Step ' + chipStep + '  Beat ' + beat + '  ' + clock + '  ' + bpm + ' BPM');
		variants.push('Step ' + chipStep + '  Beat ' + beat + '  ' + clock);
		variants.push('Step ' + chipStep + '  ' + clock + '  ' + bpm + ' BPM');
		variants.push('Step ' + chipStep + '  ' + clock);
		variants.push(clock + '  ' + bpm + ' BPM');
		variants.push(clock);
		return variants;
	}

	/** Visible range, with and without the label that names it. */
	function rangeVariants():Array<String>
	{
		var text:String = formatRangeLabel(secondsOnScreen);
		var variants:Array<String> = [];
		variants.push('view ' + text);
		variants.push(text);
		return variants;
	}

	function updateButtons():Void
	{
		var plusDown:Bool = (pressKind == PRESS_BUTTON && pressButton == BUTTON_PLUS);
		var minusDown:Bool = (pressKind == PRESS_BUTTON && pressButton == BUTTON_MINUS);
		var idleBorder:Int = COLOR_CHIP_BORDER;
		var idleBody:Int = COLOR_CHIP_BG;

		chipPlus.setColors(plusDown ? COLOR_BUTTON_DOWN_BORDER : idleBorder, plusDown ? COLOR_BUTTON_DOWN_BG : idleBody);
		chipMinus.setColors(minusDown ? COLOR_BUTTON_DOWN_BORDER : idleBorder, minusDown ? COLOR_BUTTON_DOWN_BG : idleBody);

		var dim:Float = canZoomIn() ? 1 : 0.4;
		chipPlus.text.alpha = (plusDown || canZoomIn()) ? 1 : 0.4;
		chipPlus.border.alpha = dim;
		chipPlus.bg.alpha = dim;

		dim = canZoomOut() ? 1 : 0.4;
		chipMinus.text.alpha = (minusDown || canZoomOut()) ? 1 : 0.4;
		chipMinus.border.alpha = dim;
		chipMinus.bg.alpha = dim;
	}

	function canZoomIn():Bool
	{
		return secondsOnScreen > MIN_SECONDS_ON_SCREEN * 1.001;
	}

	function canZoomOut():Bool
	{
		return secondsOnScreen < MAX_SECONDS_ON_SCREEN * 0.999;
	}

	// ---------------------------------------------------------------------------------------
	// Input
	// ---------------------------------------------------------------------------------------

	function handleInput(elapsed:Float):Void
	{
		gestureClock += elapsed;

		if (pressKind == PRESS_NONE)
		{
			startPress();
		}
		else if (pointerId != NO_POINTER)
		{
			// The gesture belongs to one touch id, so a second finger can never steal it.
			var touch:FlxTouch = findTouch(pointerId);
			if (touch == null || !touch.pressed)
			{
				endPress();
			}
			else
			{
				readPointer(touch);
				continuePress(elapsed);
			}
		}
		else if (FlxG.mouse == null || !FlxG.mouse.pressed)
		{
			endPress();
		}
		else
		{
			readPointer(null);
			continuePress(elapsed);
		}

		if (pressKind == PRESS_NONE && pointerId == NO_POINTER && FlxG.mouse != null && FlxG.mouse.wheel != 0)
		{
			readPointer(null);
			if (insideStrip(pointerX, pointerY))
				zoomByWheel(pointerX);
		}
	}

	/** Touch first, mouse second: touch screen coordinates are read before the mouse mirror. */
	function startPress():Void
	{
		var touch:FlxTouch = findJustPressedTouch();
		if (touch != null)
		{
			pointerId = touch.touchPointID;
			readPointer(touch);
			if (insideStrip(pointerX, pointerY))
				beginPress();
			else
				pointerId = NO_POINTER;
			return;
		}

		if (FlxG.mouse == null)
			return;

		pointerId = NO_POINTER;
		readPointer(null);

		if (!insideStrip(pointerX, pointerY))
			return;

		if (FlxG.mouse.justPressed)
			beginPress();
		#if FLX_MOUSE_ADVANCED
		else if (FlxG.mouse.justPressedRight)
			requestRemoval();
		#end
	}

	function findJustPressedTouch():FlxTouch
	{
		for (touch in FlxG.touches.list)
		{
			if (touch != null && touch.justPressed)
				return touch;
		}
		return null;
	}

	/** The touch that owns the running gesture; `null` once the finger is gone. */
	function findTouch(id:Int):FlxTouch
	{
		if (id == NO_POINTER)
			return null;

		for (touch in FlxG.touches.list)
		{
			if (touch != null && touch.touchPointID == id)
				return touch;
		}
		return null;
	}

	function readPointer(?touch:FlxTouch):Void
	{
		var camera:FlxCamera = (cam != null) ? cam : FlxG.camera;
		if (pointer == null || camera == null)
			return;

		var point:FlxPoint = null;
		if (touch != null)
			point = touch.getWorldPosition(camera, pointer);
		else if (FlxG.mouse != null)
			point = FlxG.mouse.getWorldPosition(camera, pointer);

		if (point == null)
			return;

		pointerX = point.x;
		pointerY = point.y;
	}

	inline function insideStrip(px:Float, py:Float):Bool
	{
		return px >= rectX && px <= rectX + rectW && py >= rectY && py <= rectY + rectH;
	}

	function beginPress():Void
	{
		pressKind = PRESS_NONE;
		pressMarkerId = '';
		pressButton = BUTTON_NONE;
		pressFree = false;
		pressHeld = 0;
		pressMoved = false;
		buttonHold = 0;
		buttonRepeats = 0;
		lastSeekMs = -1;

		var button:Int = pickButton(pointerX, pointerY);
		if (button != BUTTON_NONE)
		{
			pressKind = PRESS_BUTTON;
			pressButton = button;
			stepZoom();
			playSound('scrollMenu');
			return;
		}

		var marker:TimelineMarker = markerAt(pointerX, pointerY);
		if (marker != null)
		{
			pressKind = PRESS_MARKER;
			pressMarkerId = marker.id;
			pressOffsetX = pointerX - markerX(marker);
			pressFree = shiftHeld();

			var doubleTap:Bool = (lastTapId == marker.id) && (gestureClock - lastTapTime <= DOUBLE_TAP_TIME);
			lastTapId = marker.id;
			lastTapTime = gestureClock;

			selectMarker(marker.id);
			dirtyMarkers = true;

			if (onMarkerSelected != null)
				onMarkerSelected(marker.id);

			if (doubleTap && onMarkerRemove != null)
			{
				playSound('cancelMenu');
				onMarkerRemove(marker.id);
			}
			else
			{
				playSound('scrollMenu');
			}
			return;
		}

		pressKind = PRESS_SEEK;
		grabbingPlayhead = (Math.abs(pointerX - msToX(currentMs)) <= touch * 0.5);
		requestSeek(msAt(pointerX));
	}

	function continuePress(elapsed:Float):Void
	{
		// Dragging off either end of the strip pages the view instead of doing nothing.
		if (pressKind != PRESS_BUTTON && (pointerX < rectX || pointerX > rectX + rectW))
			panView(elapsed);

		if (pressKind == PRESS_BUTTON)
		{
			buttonHold += elapsed;
			var delay:Float = (buttonRepeats == 0) ? BUTTON_FIRST_REPEAT : BUTTON_REPEAT_RATE;
			if (buttonHold >= delay)
			{
				buttonHold = 0;
				buttonRepeats++;
				stepZoom();
			}
			return;
		}

		if (pressKind == PRESS_MARKER)
		{
			var marker:TimelineMarker = getMarker(pressMarkerId);
			if (marker == null)
			{
				endPress();
				return;
			}

			pressHeld += elapsed;

			if (!pressMoved && Math.abs(pointerX - (markerX(marker) + pressOffsetX)) > DRAG_SLOP_PX)
			{
				pressMoved = true;
				dirtyMarkers = true;
			}

			// A long press arms free milliseconds, so a thumb can land off-grid the same way
			// a mouse does with SHIFT.
			if (!pressFree && (shiftHeld() || pressHeld >= LONG_PRESS_TIME))
			{
				pressFree = true;
				playSound('confirmMenu');
			}

			if (pressMoved)
				dragMarkerTo(marker, msAt(pointerX - pressOffsetX), pressFree);
			return;
		}

		if (pressKind == PRESS_SEEK)
			requestSeek(msAt(pointerX));
	}

	function endPress():Void
	{
		if (pressKind == PRESS_MARKER || pressKind == PRESS_BUTTON)
			dirtyMarkers = true;

		pressKind = PRESS_NONE;
		pressMarkerId = '';
		pressButton = BUTTON_NONE;
		pressFree = false;
		pressHeld = 0;
		pressMoved = false;
		buttonHold = 0;
		buttonRepeats = 0;
		grabbingPlayhead = false;
		pointerId = NO_POINTER;
	}

	function shiftHeld():Bool
	{
		return (FlxG.keys != null) && FlxG.keys.pressed.SHIFT;
	}

	function pickButton(px:Float, py:Float):Int
	{
		if (px < zoomColX || px > zoomColX + zoomBtnW)
			return BUTTON_NONE;

		if (py >= zoomPlusY && py <= zoomPlusY + zoomBtnH)
			return BUTTON_PLUS;
		if (py >= zoomMinusY && py <= zoomMinusY + zoomBtnH)
			return BUTTON_MINUS;

		return BUTTON_NONE;
	}

	function stepZoom():Void
	{
		if (pressButton == BUTTON_PLUS)
		{
			if (!canZoomIn())
				return;
			zoomBy(ZOOM_FACTOR);
		}
		else if (pressButton == BUTTON_MINUS)
		{
			if (!canZoomOut())
				return;
			zoomBy(1 / ZOOM_FACTOR);
		}
	}

	function dragMarkerTo(marker:TimelineMarker, targetMs:Float, freeMode:Bool):Void
	{
		if (marker == null || !Math.isFinite(targetMs))
			return;

		if (targetMs < 0)
			targetMs = 0;

		var newStep:Int = Std.int(Math.round(msToStep(targetMs)));
		if (newStep < 0)
			newStep = 0;

		var newTime:Float;
		if (freeMode)
		{
			newTime = targetMs;
			freeTimeIds.set(marker.id, true);
		}
		else
		{
			newTime = stepToMs(newStep);
			freeTimeIds.remove(marker.id);
		}

		if (!Math.isFinite(newTime))
			return;
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
		if (!Math.isFinite(ms))
			return;

		var target:Float = clampF(ms, 0, Math.max(lengthMs, currentMs));
		if (Math.abs(target - lastSeekMs) < 0.5)
			return;

		lastSeekMs = target;
		currentMs = target;
		if (onSeek != null)
			onSeek(target);
	}

	function requestRemoval():Void
	{
		var marker:TimelineMarker = markerAt(pointerX, pointerY);
		if (marker == null)
			return;

		if (onMarkerRemove != null)
			onMarkerRemove(marker.id);
		playSound('cancelMenu');
	}

	function panView(elapsed:Float):Void
	{
		var shift:Float = 0;
		if (pointerX > rectX + rectW)
			shift = visibleMs() * PAN_FRACTION * elapsed;
		else if (pointerX < rectX)
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
		var fraction:Float = clampF((px - trackX) / Math.max(1, trackW), 0, 1);
		applyZoom(secondsOnScreen * Math.pow(0.88, wheel), anchorMs, fraction);
	}

	/** Nearest marker whose touch-sized hit box contains the pointer. */
	function markerAt(px:Float, py:Float):Null<TimelineMarker>
	{
		var half:Float = touch * 0.5;
		var best:TimelineMarker = null;
		var bestDistance:Float = 1e12;

		for (m in markers)
		{
			if (m == null)
				continue;

			var dx:Float = px - markerX(m);
			if (Math.abs(dx) > half)
				continue;

			var dy:Float = py - markerCenterOf(m);
			if (Math.abs(dy) > half)
				continue;

			var distance:Float = dx * dx + dy * dy;
			if (distance < bestDistance)
			{
				bestDistance = distance;
				best = m;
			}
		}

		return best;
	}

	function playSound(key:String):Void
	{
		if (key == null || FlxG.sound == null || failedSounds.exists(key))
			return;

		var sound:Sound = soundCache.get(key);
		if (sound == null)
		{
			try
			{
				sound = Paths.sound(key);
			}
			catch (error:Dynamic)
			{
				sound = null;
			}

			if (sound == null)
			{
				failedSounds.set(key, true);
				return;
			}

			soundCache.set(key, sound);
		}

		FlxG.sound.play(sound);
	}

	// ---------------------------------------------------------------------------------------
	// Small helpers
	// ---------------------------------------------------------------------------------------

	/** `mm:ss` and, when the ruler is zoomed far enough in, `mm:ss.d[d[d]]`. */
	static function formatClock(ms:Float, precision:Int):String
	{
		if (!Math.isFinite(ms) || ms < 0)
			ms = 0;

		var total:Int = Std.int(Math.floor(ms));
		var minutes:Int = Std.int(total / 60000);
		var seconds:Int = Std.int((total % 60000) / 1000);

		var text:String = (minutes < 10 ? '0' : '') + minutes + ':' + (seconds < 10 ? '0' : '') + seconds;
		if (precision <= 0)
			return text;

		var millis:String = StringTools.lpad(Std.string(total % 1000), '0', 3);
		return text + '.' + millis.substr(0, clampI(precision, 1, 3));
	}

	/** Visible range: `12s` / `1.5s` / `1:30`, short enough for any strip. */
	static function formatRangeLabel(seconds:Float):String
	{
		if (!Math.isFinite(seconds) || seconds <= 0)
			return '--';

		if (seconds >= 60)
		{
			var whole:Int = Std.int(Math.round(seconds));
			return Std.int(whole / 60) + ':' + StringTools.lpad(Std.string(whole % 60), '0', 2);
		}

		if (seconds >= 10)
			return Std.string(Std.int(Math.round(seconds))) + 's';
		if (seconds >= 1)
			return Std.string(Math.round(seconds * 10) / 10) + 's';

		return Std.string(Math.round(seconds * 100) / 100) + 's';
	}

	static function formatBpm(bpm:Float):String
	{
		if (!Math.isFinite(bpm))
			return '--';

		var rounded:Float = Math.round(bpm * 10) / 10;
		if (rounded == Math.round(rounded))
			return Std.string(Std.int(rounded));
		return Std.string(rounded);
	}

	static function fitText(text:String, maxChars:Int):String
	{
		if (text == null)
			return '';
		if (maxChars < 4 || text.length <= maxChars)
			return text;

		return text.substr(0, maxChars - 2) + '..';
	}

	/** Widest the given text can render, used instead of measuring (which re-renders fonts). */
	static function estimateTextWidth(text:String, size:Int):Float
	{
		if (text == null)
			return 0;
		return text.length * size * CHIP_GAP_RATIO + 2;
	}

	function chipWidth(text:String, size:Int, padX:Float):Float
	{
		return Math.round(estimateTextWidth(text, size)) + padX * 2 + 2;
	}

	/** Every colour that arrives without an alpha channel is treated as opaque. */
	static function normalizeColor(color:Int):Int
	{
		return ((color >>> 24) == 0) ? (color | 0xFF000000) : color;
	}

	static function shade(color:Int, factor:Float):Int
	{
		var alpha:Int = (color >>> 24) & 0xFF;
		if (alpha == 0)
			alpha = 0xFF;

		var red:Int = clampI(Std.int(((color >> 16) & 0xFF) * factor), 0, 255);
		var green:Int = clampI(Std.int(((color >> 8) & 0xFF) * factor), 0, 255);
		var blue:Int = clampI(Std.int((color & 0xFF) * factor), 0, 255);

		return (alpha << 24) | (red << 16) | (green << 8) | blue;
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
