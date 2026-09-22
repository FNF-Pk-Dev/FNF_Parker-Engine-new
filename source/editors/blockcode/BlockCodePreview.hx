package editors.blockcode;

import flixel.group.FlxGroup;
import flixel.input.touch.FlxTouch;
import flixel.util.FlxSpriteUtil;

/**
 * Docked **Live Lua** preview of the block-code editor: a compact panel that shows the Lua the
 * blocks on screen compile to, right next to the blocks themselves.
 *
 * This is the reading half of the editor - `BlockCodePanel` is where the code is edited - so the
 * panel only ever renders. It takes the text from `setCode()`, the current step from
 * `setCurrentStep()` and a one line message from `setStatus()`, and never changes any of them.
 *
 * ## Shape
 *
 * A `FlxGroup` of flat sprites and `FlxText`s that live entirely inside the rect the caller passes
 * (`x`, `y`, `w`, `h`) and are drawn on the given camera. The rect is in the camera's view space -
 * the same convention `BlockSavePanel` and `BlockHelpOverlay` use - so the children carry
 * `scrollFactor 0` and the pointer is read with `getScreenPosition(cam)`.
 *
 * Everything inside the rect comes from {@link BlockLayout}: fonts, row height, touch targets,
 * gutter and scrollbar width. That is what makes it fit a 1280x720 desktop window, a phone in
 * landscape, a phone in portrait and a tablet alike. `resize()` re-lays it out on demand, and
 * `update()` re-lays it out whenever `BlockLayout.ensure()` reports a new viewport.
 *
 * ## Reading
 *
 * Code is drawn one line at a time, with a thin line-number gutter on the left and a scrollbar on
 * the right. Only the lines inside the view are laid out and every line is cut to the columns that
 * fit, so text never spills out of the panel or touches its border. Colours follow the editor's
 * theme: comments dim, keywords purple, strings green, numbers orange, calls blue.
 *
 * `setCurrentStep()` is the live part: a line guarded by `if curStep == <step> then` is marked with
 * a left accent bar and scrolled into view - unless the user scrolled the panel themselves in the
 * last couple of seconds, because the song must not yank the view away from someone reading.
 *
 * Dragging (touch or mouse) and the mouse wheel scroll the code, clamped to the content.
 */
class BlockCodePreview extends FlxGroup
{
	// --- Theme ---------------------------------------------------------------------------------
	static inline var COLOR_PANEL:Int = 0xDD16161E;
	static inline var COLOR_BORDER:Int = 0xFF414868;
	static inline var COLOR_SHADOW:Int = 0xFF000000;
	static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	static inline var COLOR_DIM:Int = 0xFF6E7891;
	static inline var COLOR_COMMENT:Int = 0xFF565F89;
	static inline var COLOR_LINE_NUMBER:Int = 0xFF565F89;
	static inline var COLOR_KEYWORD:Int = 0xFFBB9AF7;
	static inline var COLOR_STRING:Int = 0xFF9ECE6A;
	static inline var COLOR_NUMBER:Int = 0xFFFF9E64;
	static inline var COLOR_BUILTIN:Int = 0xFF7AA2F7;
	static inline var COLOR_ACCENT:Int = 0xFF3D59A1;
	static inline var COLOR_MARK:Int = 0xFFE0AF68;
	static inline var COLOR_GUTTER_BG:Int = 0xFF0F0F14;
	static inline var COLOR_TRACK:Int = 0xFF24283B;
	static inline var COLOR_THUMB:Int = 0xFF565F89;
	static inline var COLOR_BUTTON_TEXT:Int = 0xFFFFFFFF;

	static inline var TITLE:String = 'Live Lua';
	static inline var CLOSE_LABEL:String = 'X';
	static inline var EXPAND_LABEL:String = 'EXPAND';
	static inline var SHORT_EXPAND_LABEL:String = '>_';
	static inline var EMPTY_HINT:String = 'add a block to see the code';

	// --- Metrics -------------------------------------------------------------------------------
	static inline var MIN_WIDTH:Float = 200;
	static inline var MIN_HEIGHT:Float = 120;
	static inline var LINE_HEIGHT:Float = 1.35;
	static inline var WHEEL_LINES:Float = 3;
	static inline var SHADOW_ALPHA:Float = 0.35;
	static inline var SHADOW_OFFSET:Float = 3;
	static inline var FOLLOW_COOLDOWN:Float = 3;
	static inline var GUTTER_ALPHA:Float = 0.6;
	static inline var TRACK_ALPHA:Float = 0.55;

	// --- Budgets -------------------------------------------------------------------------------

	/** One line never uses more segment sprites than this; the rest is merged into one tail. */
	static inline var MAX_SEGMENTS_PER_LINE:Int = 20;

	/** Hard ceiling on the shared segment pool, so a pathological script cannot spawn thousands. */
	static inline var MAX_SEGMENT_SPRITES:Int = 420;

	/** Lines kept in the layout cache before it is dropped wholesale. */
	static inline var MAX_LINE_CACHE:Int = 600;

	// --- Drag modes ----------------------------------------------------------------------------
	static inline var DRAG_NONE:Int = 0;
	static inline var DRAG_CODE:Int = 1;
	static inline var DRAG_BAR:Int = 2;

	// --- Token kinds ---------------------------------------------------------------------------
	static inline var TOK_OTHER:Int = 0;
	static inline var TOK_COMMENT:Int = 1;
	static inline var TOK_STRING:Int = 2;
	static inline var TOK_NUMBER:Int = 3;
	static inline var TOK_KEYWORD:Int = 4;
	static inline var TOK_BUILTIN:Int = 5;

	/** Lua keywords the generator emits, coloured as keywords. */
	static final KEYWORDS:Array<String> = [
		'function',
		'if',
		'then',
		'else',
		'elseif',
		'end',
		'while',
		'do',
		'break',
		'local',
		'return',
		'for',
		'in'
	];

	// --- Public API ----------------------------------------------------------------------------

	/** Header button "expand": the caller opens the full `BlockCodePanel` from here. */
	public var onExpand:Void->Void = null;

	/** Header button "close": the caller decides what closing means (hiding the dock, usually). */
	public var onClose:Void->Void = null;

	// --- Rect and metrics ----------------------------------------------------------------------
	var rectX:Float = 0;
	var rectY:Float = 0;
	var rectW:Float = MIN_WIDTH;
	var rectH:Float = MIN_HEIGHT;

	var pad:Float = 6;
	var inner:Float = 3;
	var headerH:Float = 46;
	var footerH:Float = 22;
	var codeX:Float = 0;
	var codeY:Float = 0;
	var codeW:Float = 1;
	var codeH:Float = 1;
	var textX:Float = 0;
	var textW:Float = 1;
	var trackX:Float = 0;
	var gutterW:Float = 24;
	var gutterGap:Float = 4;
	var scrollbarW:Float = 12;
	var rowH:Float = 18;
	var textOffsetY:Float = 2;
	var maxCols:Int = 20;
	var rowCount:Int = 1;
	var fontSize:Int = 13;
	var tinySize:Int = 11;
	var titleSize:Int = 15;
	var charW:Float = 8;
	var btnSize:Float = 34;
	var btnY:Float = 0;
	var expandX:Float = 0;
	var expandW:Float = 0;
	var closeX:Float = 0;
	var closeW:Float = 0;
	var titleX:Float = 0;
	var titleW:Float = 0;
	var statusX:Float = 0;
	var statusW:Float = 0;
	var expandLabel:String = EXPAND_LABEL;

	var panelW:Int = -1;
	var panelH:Int = -1;
	var panelRadius:Int = -1;

	// --- Content -------------------------------------------------------------------------------
	var code:String = '';
	var lines:Array<String> = [''];
	var lineCount:Int = 1;
	var stepLines:Map<Int, Int> = new Map();
	var currentStep:Int = -1;
	var stepLine:Int = -1;
	var status:String = '';
	var cachePrefix:String = '';
	var lineCache:Map<String, PreviewLine> = new Map();
	var lineCacheCount:Int = 0;

	// --- View state ----------------------------------------------------------------------------
	var scroll:Float = 0;
	var maxScroll:Float = 0;
	var thumbH:Float = 0;
	var manualScroll:Float = 0;
	var openState:Bool = true;
	var renderDirty:Bool = true;

	// --- Metrics snapshot of the last layout ----------------------------------------------------
	var lastWidth:Float = -1;
	var lastHeight:Float = -1;
	var lastScale:Float = -1;

	// --- Sprites -------------------------------------------------------------------------------
	var layerBack:FlxGroup = null;
	var layerCode:FlxGroup = null;
	var layerFront:FlxGroup = null;

	var shadow:FlxSprite = null;
	var panel:FlxSprite = null;
	var headerLine:FlxSprite = null;
	var footerLine:FlxSprite = null;
	var gutterBg:FlxSprite = null;
	var gutterSep:FlxSprite = null;
	var stepBar:FlxSprite = null;
	var scrollTrack:FlxSprite = null;
	var scrollThumb:FlxSprite = null;
	var expandBg:FlxSprite = null;
	var closeBg:FlxSprite = null;
	var expandText:FlxText = null;
	var closeText:FlxText = null;
	var titleText:FlxText = null;
	var statusText:FlxText = null;
	var footerText:FlxText = null;
	var measure:FlxText = null;
	var numberSprites:Array<FlxText> = [];
	var segmentSprites:Array<FlxText> = [];
	var segmentCursor:Int = 0;

	// --- Pointer --------------------------------------------------------------------------------
	var cam:FlxCamera = null;
	var ptrPoint:FlxPoint = null;
	var ptrX:Float = 0;
	var ptrY:Float = 0;
	var ptrPressed:Bool = false;
	var ptrJustPressed:Bool = false;
	var ptrJustReleased:Bool = false;
	var dragMode:Int = DRAG_NONE;
	var dragLastY:Float = 0;
	var activeTouchID:Int = -1;

	/**
	 * Builds the preview inside a `w` x `h` rect at `x`, `y`, drawn on `cam`. The rect is clamped to
	 * {@link MIN_WIDTH} / {@link MIN_HEIGHT} so a caller that docks it into a sliver still gets a
	 * usable panel.
	 *
	 * The panel starts **open** (`visible`): it is meant to sit next to the blocks while the user
	 * works, so a caller only has to `add()` it - `close()` hides it and `open()` brings it back.
	 */
	public function new(x:Float, y:Float, w:Float, h:Float, cam:FlxCamera)
	{
		super();

		this.cam = cam;
		ptrPoint = FlxPoint.get();

		BlockLayout.ensure();

		rectX = Math.floor(x);
		rectY = Math.floor(y);
		rectW = Math.max(MIN_WIDTH, w);
		rectH = Math.max(MIN_HEIGHT, h);

		if (cam != null)
			cameras = [cam];

		measure = new FlxText(0, 0, 0, '', BlockLayout.font('small'));
		measure.setFormat(Paths.font('vcr.ttf'), BlockLayout.font('small'), FlxColor.WHITE, FlxTextAlign.LEFT);
		measure.scrollFactor.set(0, 0);

		build();
		applyLayout();
		refreshVisible();

		visible = true;
	}

	/** The generated Lua to show. `null` is treated as an empty script. */
	public function setCode(code:String):Void
	{
		var value:String = (code != null) ? code : '';
		if (value == this.code)
			return;

		this.code = value;
		splitLines();
		indexSteps();
		clampScroll();
		refreshFooterText();
		renderDirty = true;

		// The step hint survives a code change: the new text is searched again and, when it holds the
		// current step, that line is brought back into view.
		followStepLine();
	}

	/**
	 * Tells the preview where the song is. When the code has a `curStep == <step>` guard for this
	 * step, that line gets a left accent bar and is scrolled into view; the step is remembered either
	 * way, so `setCode()` can apply it again later.
	 */
	public function setCurrentStep(step:Int):Void
	{
		var value:Int = (step < 0) ? -1 : step;
		if (value == currentStep)
			return;

		currentStep = value;
		refreshStepLine();
		refreshFooterText();
		renderDirty = true;

		followStepLine();
	}

	/** One line of context for the header, e.g. `saved to global.lua`. Long text is truncated. */
	public function setStatus(text:String):Void
	{
		var value:String = (text != null) ? text : '';
		if (value == status)
			return;

		status = value;
		refreshHeaderTexts();
	}

	/** Moves and resizes the panel. Everything is re-laid out; the scroll position is kept. */
	public function resize(x:Float, y:Float, w:Float, h:Float):Void
	{
		var nx:Float = Math.floor(x);
		var ny:Float = Math.floor(y);
		var nw:Float = Math.max(MIN_WIDTH, w);
		var nh:Float = Math.max(MIN_HEIGHT, h);

		if (nx == rectX && ny == rectY && nw == rectW && nh == rectH)
			return;

		rectX = nx;
		rectY = ny;
		rectW = nw;
		rectH = nh;

		applyLayout();
		refreshVisible();
	}

	/** True while the panel is drawn. */
	public function isOpen():Bool
	{
		return openState;
	}

	/** Shows the panel and scrolls the current step back into view. Safe to call when open. */
	public function open():Void
	{
		openState = true;
		visible = true;
		activeTouchID = -1;
		dragMode = DRAG_NONE;
		renderDirty = true;

		followStepLine();
	}

	/**
	 * Hides the panel. Does **not** call `onClose`: that callback belongs to the header button, so a
	 * caller reacting to it can call this without looping.
	 */
	public function close():Void
	{
		if (!openState)
			return;

		openState = false;
		visible = false;
		dragMode = DRAG_NONE;
		activeTouchID = -1;
	}

	override public function update(elapsed:Float):Void
	{
		if (!openState)
			return;

		super.update(elapsed);

		// The viewport may have changed under us: a rotated phone, a resized window, a new target.
		BlockLayout.ensure();
		if (metricsChanged())
		{
			applyLayout();
			refreshVisible();
		}

		if (manualScroll > 0)
			manualScroll -= elapsed;

		pollPointer();
		handlePointer();

		if (renderDirty)
		{
			renderDirty = false;
			refreshVisible();
		}
	}

	override public function destroy():Void
	{
		onExpand = null;
		onClose = null;

		lineCache = new Map();
		stepLines = new Map();
		lines = [];
		numberSprites = [];
		segmentSprites = [];

		measure = FlxDestroyUtil.destroy(measure);

		if (ptrPoint != null)
		{
			ptrPoint.put();
			ptrPoint = null;
		}

		super.destroy();
	}

	// --- Construction --------------------------------------------------------------------------

	function build():Void
	{
		layerBack = addLayer();
		layerCode = addLayer();
		layerFront = addLayer();

		shadow = new FlxSprite(0, 0);
		register(shadow);
		shadow.alpha = SHADOW_ALPHA;
		layerBack.add(shadow);

		panel = new FlxSprite(0, 0);
		register(panel);
		layerBack.add(panel);

		gutterBg = makeBar(COLOR_GUTTER_BG, GUTTER_ALPHA);
		gutterSep = makeBar(COLOR_BORDER, 0.7);
		headerLine = makeBar(COLOR_BORDER, 0.8);
		footerLine = makeBar(COLOR_BORDER, 0.8);
		layerBack.add(gutterBg);
		layerBack.add(gutterSep);
		layerBack.add(headerLine);
		layerBack.add(footerLine);

		stepBar = makeBar(COLOR_MARK, 1);
		layerCode.add(stepBar);

		scrollTrack = makeBar(COLOR_TRACK, TRACK_ALPHA);
		scrollThumb = makeBar(COLOR_THUMB, 0.9);
		layerFront.add(scrollTrack);
		layerFront.add(scrollThumb);

		expandBg = makeBar(COLOR_ACCENT, 1);
		closeBg = makeBar(COLOR_BORDER, 1);
		layerFront.add(expandBg);
		layerFront.add(closeBg);

		titleText = makeLabel(BlockLayout.font('body'), COLOR_TEXT, FlxTextAlign.LEFT, 0, TITLE);
		statusText = makeLabel(BlockLayout.font('tiny'), COLOR_DIM, FlxTextAlign.LEFT);
		footerText = makeLabel(BlockLayout.font('tiny'), COLOR_COMMENT, FlxTextAlign.LEFT);
		expandText = makeLabel(BlockLayout.font('small'), COLOR_BUTTON_TEXT, FlxTextAlign.CENTER, 0, EXPAND_LABEL);
		closeText = makeLabel(BlockLayout.font('small'), COLOR_BUTTON_TEXT, FlxTextAlign.CENTER, 0, CLOSE_LABEL);

		layerFront.add(titleText);
		layerFront.add(statusText);
		layerFront.add(footerText);
		layerFront.add(expandText);
		layerFront.add(closeText);
	}

	function addLayer():FlxGroup
	{
		var layer:FlxGroup = new FlxGroup();
		if (cam != null)
			layer.cameras = [cam];
		add(layer);
		return layer;
	}

	/** A flat rectangle sprite: one shared 1x1 white bitmap, scaled to the rect it is placed in. */
	function makeBar(color:Int, alpha:Float):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.WHITE);
		sprite.color = color;
		sprite.alpha = alpha;
		sprite.origin.set(0, 0);
		register(sprite);
		return sprite;
	}

	/** Positions a {@link makeBar} rect: `w` x `h` whole pixels with its top left corner at `x`, `y`. */
	static function setBar(sprite:FlxSprite, x:Float, y:Float, w:Float, h:Float):Void
	{
		if (sprite == null)
			return;

		sprite.scale.set(Math.max(1, Math.round(w)), Math.max(1, Math.round(h)));
		sprite.x = Math.round(x);
		sprite.y = Math.round(y);
	}

	function makeLabel(size:Int, color:Int, align:FlxTextAlign, fieldWidth:Float = 0, text:String = ''):FlxText
	{
		var label:FlxText = new FlxText(0, 0, fieldWidth, text, size);
		label.setFormat(Paths.font('vcr.ttf'), size, color, align);
		label.origin.set(0, 0);
		register(label);
		return label;
	}

	function register(sprite:FlxSprite):Void
	{
		if (sprite == null)
			return;

		sprite.scrollFactor.set(0, 0);
		if (cam != null)
			sprite.cameras = [cam];
	}

	/** Draws the rounded panel and its shadow, but only when the pixel size actually changed. */
	function buildPanel(w:Int, h:Int, radius:Int):Void
	{
		if (w == panelW && h == panelH && radius == panelRadius)
			return;

		panelW = w;
		panelH = h;
		panelRadius = radius;

		shadow.makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(shadow, 0, 0, w, h, radius, radius, COLOR_SHADOW);
		shadow.origin.set(0, 0);

		// The 0.5 inset centres the 1px stroke on the very edge of the bitmap instead of half
		// outside it, which is what keeps the border a crisp single pixel.
		panel.makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(panel, 0.5, 0.5, w - 1, h - 1, radius, radius, COLOR_PANEL, {thickness: 1, color: COLOR_BORDER});
		panel.origin.set(0, 0);
	}

	// --- Layout --------------------------------------------------------------------------------

	function metricsChanged():Bool
	{
		if (BlockLayout.width == lastWidth && BlockLayout.height == lastHeight && BlockLayout.scale == lastScale)
			return false;

		return true;
	}

	/** Recomputes every metric from {@link BlockLayout} and places all furniture. */
	function applyLayout():Void
	{
		pad = Math.max(6, Math.round(BlockLayout.spacing('normal') * 0.75));
		inner = Math.max(3, Math.round(pad * 0.5));
		fontSize = BlockLayout.font('small');
		tinySize = BlockLayout.font('tiny');
		titleSize = BlockLayout.font('body');
		charW = Math.max(4, measureText('MMMMMMMMMM', fontSize) / 10);
		rowH = Math.max(fontSize + 4, Math.round(fontSize * LINE_HEIGHT));
		textOffsetY = Math.max(0, Math.round((rowH - fontSize) * 0.5) - 1);
		btnSize = Math.max(BlockLayout.touchSize(), Math.round(BlockLayout.statusHeight()));
		headerH = btnSize + pad * 2;
		footerH = Math.max(Math.round(tinySize * 1.8) + 4, Math.round(BlockLayout.statusHeight() * 0.8));
		scrollbarW = Math.max(10, Math.round((BlockLayout.isMobile() ? 16 : 12) * BlockLayout.scale));
		gutterGap = Math.max(4, Math.round(BlockLayout.spacing('tight') * 0.8));
		gutterW = Math.max(Math.round(BlockLayout.touchSize() * 0.5), Math.round(charW * (digitCount(lineCount) + 1) + pad));

		var gap:Float = Math.max(4, Math.round(BlockLayout.spacing('tight') * 0.8));

		// Header: two buttons pinned to the right, title and status sharing what is left. A dock this
		// narrow cannot carry the word EXPAND, so the button falls back to a glyph.
		closeW = btnSize;
		expandLabel = EXPAND_LABEL;
		expandW = Math.max(btnSize, Math.round(BlockLayout.buttonWidth(expandLabel)));
		if (expandW + closeW + gap * 4 + pad * 2 + charW * 5 > rectW)
		{
			expandLabel = SHORT_EXPAND_LABEL;
			expandW = btnSize;
		}

		btnY = rectY + pad;
		closeX = rectX + rectW - pad - closeW;
		expandX = closeX - gap - expandW;

		titleX = rectX + pad;
		var wantedTitle:Float = Math.round(measureText(TITLE, titleSize)) + 2;
		titleW = Math.max(0, Math.min(wantedTitle, expandX - gap * 2 - titleX));
		statusX = titleX + titleW + gap;
		statusW = Math.max(0, expandX - gap - statusX);

		// Code area: header band on top, footer band at the bottom, gutter on the left, scrollbar on
		// the right. Nothing here is closer than `inner` to the rounded border.
		var bodyTop:Float = rectY + headerH;
		var bodyBottom:Float = rectY + rectH - footerH;
		codeX = rectX + inner;
		codeY = bodyTop + inner;
		codeH = Math.max(rowH, bodyBottom - inner - codeY);
		trackX = rectX + rectW - inner - scrollbarW;
		textX = codeX + gutterW + gutterGap;
		textW = Math.max(charW * 4, trackX - gutterGap - textX);
		maxCols = Std.int(Math.max(4, textW / charW));
		rowCount = Std.int(Math.ceil(codeH / rowH)) + 1;

		// Cached line layouts depend on the column budget and on the measured character width.
		cachePrefix = Std.int(charW * 100) + ':' + maxCols + '|';
		lineCache = new Map();
		lineCacheCount = 0;

		buildPanel(Std.int(Math.max(1, Math.round(rectW))), Std.int(Math.max(1, Math.round(rectH))), Std.int(Math.max(2, Math.round(6 * BlockLayout.scale))));

		placeWidgets();
		ensureRowPool(rowCount);
		clampScroll();
		refreshHeaderTexts();
		refreshFooterText();

		renderDirty = true;

		lastWidth = BlockLayout.width;
		lastHeight = BlockLayout.height;
		lastScale = BlockLayout.scale;
	}

	function placeWidgets():Void
	{
		var offset:Float = Math.max(2, Math.round(SHADOW_OFFSET * BlockLayout.scale));
		shadow.x = Math.round(rectX + offset);
		shadow.y = Math.round(rectY + offset);
		panel.x = Math.round(rectX);
		panel.y = Math.round(rectY);

		setBar(headerLine, rectX + inner, rectY + headerH, rectW - inner * 2, 1);
		setBar(footerLine, rectX + inner, rectY + rectH - footerH, rectW - inner * 2, 1);
		setBar(gutterBg, codeX, codeY, gutterW, codeH);
		setBar(gutterSep, codeX + gutterW, codeY, 1, codeH);
		setBar(scrollTrack, trackX, codeY, scrollbarW, codeH);

		setBar(expandBg, expandX, btnY, expandW, btnSize);
		setBar(closeBg, closeX, btnY, closeW, btnSize);

		placeButtonLabel(expandText, expandLabel, expandX, expandW);
		placeButtonLabel(closeText, CLOSE_LABEL, closeX, closeW);

		titleText.size = titleSize;
		titleText.x = Math.round(titleX);
		titleText.y = Math.round(btnY + (btnSize - titleSize) * 0.5);

		statusText.size = tinySize;
		statusText.x = Math.round(statusX);
		statusText.y = Math.round(btnY + (btnSize - tinySize) * 0.5);

		footerText.size = tinySize;
		footerText.x = Math.round(rectX + inner + pad);
		footerText.y = Math.round(rectY + rectH - footerH + (footerH - tinySize) * 0.5) - 1;

		// The gutter is a fixed width box the number is right aligned in, so it ends next to the code.
		var numberBox:Float = Math.max(8, gutterW);
		for (number in numberSprites)
		{
			if (number.size != fontSize)
				number.size = fontSize;
			if (number.fieldWidth != numberBox)
			{
				number.fieldWidth = numberBox;
				number.wordWrap = false;
				number.alignment = FlxTextAlign.RIGHT;
			}
			number.x = Math.round(codeX);
		}

		for (segment in segmentSprites)
		{
			if (segment.size != fontSize)
				segment.size = fontSize;
		}
	}

	function placeButtonLabel(label:FlxText, text:String, x:Float, w:Float):Void
	{
		if (label == null)
			return;

		var box:Float = Math.max(8, w);
		if (label.fieldWidth != box)
		{
			label.fieldWidth = box;
			// A fixed field width implies wrapping in flixel; a button label must stay on one line.
			label.wordWrap = false;
			label.alignment = FlxTextAlign.CENTER;
		}

		if (label.text != text)
			label.text = text;

		label.x = Math.round(x);
		label.y = Math.round(btnY + (btnSize - label.size) * 0.5);
	}

	/** Grows the line-number pool so every visible row has one. */
	function ensureRowPool(count:Int):Void
	{
		while (numberSprites.length < count)
		{
			var number:FlxText = makeLabel(fontSize, COLOR_LINE_NUMBER, FlxTextAlign.RIGHT, Math.max(8, gutterW));
			number.x = Math.round(codeX);
			layerCode.add(number);
			numberSprites.push(number);
		}
	}

	function refreshHeaderTexts():Void
	{
		if (titleText != null)
		{
			// The title shares the band with two buttons, so on a narrow dock it is cut like the status
			// rather than allowed to run under the expand button.
			var headline:String = fitToWidth(TITLE, titleW, titleSize);
			if (titleText.text != headline)
				titleText.text = headline;

			titleText.visible = headline.length > 0 && titleW >= charW * 3;
		}

		if (statusText == null)
			return;

		var shown:String = fitToWidth(status, statusW, tinySize);
		if (statusText.text != shown)
			statusText.text = shown;

		statusText.visible = shown.length > 0 && statusW >= charW * 3;
	}

	function refreshFooterText():Void
	{
		if (footerText == null)
			return;

		var hasCode:Bool = hasRealCode();
		var shown:String;
		if (hasCode)
		{
			shown = lineCount + ((lineCount == 1) ? ' line' : ' lines');
			if (currentStep >= 0)
				shown += '   step ' + currentStep;
		}
		else
			shown = EMPTY_HINT;

		// The footer is a single line inside the panel: cut it instead of letting it touch the border.
		shown = fitToWidth(shown, Math.max(0, rectW - (inner + pad) * 2), tinySize);

		if (footerText.text != shown)
			footerText.text = shown;

		var color:Int = hasCode ? COLOR_TEXT : COLOR_COMMENT;
		if (footerText.color != color)
			footerText.color = color;
	}

	/** True when the script holds anything but blank lines and comments. */
	function hasRealCode():Bool
	{
		for (line in lines)
		{
			var trimmed:String = StringTools.trim(line);
			if (trimmed.length > 0 && !trimmed.startsWith('--'))
				return true;
		}

		return false;
	}

	// --- Content -------------------------------------------------------------------------------

	function splitLines():Void
	{
		var raw:Array<String> = code.split('\n');
		var out:Array<String> = [];

		for (line in raw)
			out.push(StringTools.replace(line, '\r', ''));

		// The generator always closes with a newline; the trailing empty entry is not a line.
		if (out.length > 1 && out[out.length - 1].length == 0)
			out.pop();

		if (out.length == 0)
			out.push('');

		lines = out;
		lineCount = lines.length;

		// A script that grew past a power of ten needs a wider gutter; re-laying out is the honest
		// way to get there, since the gutter width feeds the column budget and the row offsets.
		var wanted:Float = Math.max(Math.round(BlockLayout.touchSize() * 0.5), Math.round(charW * (digitCount(lineCount) + 1) + pad));
		if (wanted != gutterW)
			applyLayout();
	}

	/** Maps every `curStep == N` guard in the code to the line that carries it. */
	function indexSteps():Void
	{
		stepLines = new Map();

		for (i in 0...lines.length)
		{
			var step:Int = stepInLine(lines[i]);
			if (step >= 0 && !stepLines.exists(step))
				stepLines.set(step, i);
		}

		refreshStepLine();
	}

	function refreshStepLine():Void
	{
		var line:Int = -1;

		if (currentStep >= 0)
		{
			var found:Null<Int> = stepLines.get(currentStep);
			if (found != null)
				line = found;
		}

		stepLine = line;
	}

	/** Scrolls the step's line into view, unless the song would interrupt someone reading. */
	function followStepLine():Void
	{
		if (stepLine < 0 || manualScroll > 0)
			return;

		var top:Float = stepLine * rowH - scroll;
		if (top >= 0 && top + rowH <= codeH)
			return;

		var third:Float = Math.max(rowH, Math.floor(codeH / (rowH * 3)) * rowH);
		setScroll(snapScroll(stepLine * rowH - third));
	}

	// --- Rendering -----------------------------------------------------------------------------

	/** Lays out every line that is inside the view and hides the sprites that are not. */
	function refreshVisible():Void
	{
		if (lines == null || lines.length == 0)
			return;

		segmentCursor = 0;

		var first:Int = Std.int(Math.floor(scroll / rowH));
		if (first < 0)
			first = 0;

		for (slot in 0...numberSprites.length)
		{
			var index:Int = first + slot;
			var y:Float = codeY + index * rowH - scroll;

			// Partial rows are dropped rather than clipped: text must never leave the code area.
			if (index >= lineCount || y + rowH <= codeY || y >= codeY + codeH)
			{
				numberSprites[slot].visible = false;
				continue;
			}

			renderRow(slot, index, y);
		}

		var i:Int = segmentCursor;
		while (i < segmentSprites.length)
		{
			segmentSprites[i].visible = false;
			i++;
		}

		refreshStepBar();
		refreshScrollbar();
	}

	function renderRow(slot:Int, index:Int, y:Float):Void
	{
		var number:FlxText = numberSprites[slot];
		number.visible = true;
		number.x = Math.round(codeX);
		number.y = Math.round(y + textOffsetY);

		var label:String = Std.string(index + 1);
		if (number.text != label)
			number.text = label;

		var color:Int = (index == stepLine) ? COLOR_MARK : COLOR_LINE_NUMBER;
		if (number.color != color)
			number.color = color;

		var layout:PreviewLine = layoutFor(lines[index]);
		for (segment in layout.segments)
		{
			var sprite:FlxText = takeSegment();
			if (sprite == null)
				break;

			sprite.visible = true;
			sprite.x = Math.round(textX + segment.x);
			sprite.y = Math.round(y + textOffsetY);

			if (sprite.text != segment.text)
				sprite.text = segment.text;
			if (sprite.color != segment.color)
				sprite.color = segment.color;
		}
	}

	/** The next free segment sprite, created on demand and never past {@link MAX_SEGMENT_SPRITES}. */
	function takeSegment():FlxText
	{
		if (segmentCursor >= MAX_SEGMENT_SPRITES)
			return null;

		while (segmentSprites.length <= segmentCursor)
		{
			var sprite:FlxText = makeLabel(fontSize, COLOR_TEXT, FlxTextAlign.LEFT);
			layerCode.add(sprite);
			segmentSprites.push(sprite);
		}

		var sprite:FlxText = segmentSprites[segmentCursor];
		segmentCursor++;
		return sprite;
	}

	/** The laid out form of `line`: its coloured runs and where each one starts. Cached per text. */
	function layoutFor(line:String):PreviewLine
	{
		var value:String = (line != null) ? line : '';
		var key:String = cachePrefix + value;

		var cached:PreviewLine = lineCache.get(key);
		if (cached != null)
			return cached;

		if (lineCacheCount >= MAX_LINE_CACHE)
		{
			lineCache = new Map();
			lineCacheCount = 0;
		}

		var built:PreviewLine = buildLine(value);
		lineCache.set(key, built);
		lineCacheCount++;

		return built;
	}

	function buildLine(line:String):PreviewLine
	{
		var kinds:Array<Int> = [];
		var texts:Array<String> = [];
		tokenize(line, kinds, texts);

		var segments:Array<PreviewSegment> = [];
		var chars:Int = 0;
		var x:Float = 0;
		var i:Int = 0;

		while (i < kinds.length)
		{
			if (chars >= maxCols)
				break;

			var kind:Int = kinds[i];
			var text:String = texts[i];
			i++;

			// Neighbouring runs of the same colour are one segment: `, ` and `)` are both default.
			while (i < kinds.length && kinds[i] == kind)
			{
				text += texts[i];
				i++;
			}

			var room:Int = maxCols - chars;
			if (text.length > room)
				text = text.substr(0, room);
			if (text.length == 0)
				break;

			segments.push({color: colorFor(kind), text: text, x: x});
			chars += text.length;
			x += measureText(text, fontSize);
		}

		if (segments.length == 0)
			segments.push({color: COLOR_TEXT, text: '', x: 0});
		else if (segments.length > MAX_SEGMENTS_PER_LINE)
			segments = mergeTail(segments, MAX_SEGMENTS_PER_LINE - 1);

		return {segments: segments};
	}

	/** Collapses everything from `keep` on into a single default coloured segment. */
	static function mergeTail(segments:Array<PreviewSegment>, keep:Int):Array<PreviewSegment>
	{
		var out:Array<PreviewSegment> = [];

		for (i in 0...keep)
			out.push(segments[i]);

		var buffer:StringBuf = new StringBuf();
		for (i in keep...segments.length)
			buffer.add(segments[i].text);

		out.push({color: COLOR_TEXT, text: buffer.toString(), x: segments[keep].x});

		return out;
	}

	/**
	 * Splits one line into coloured runs: comments, strings, numbers, keywords, calls (a name
	 * directly followed by `(`) and everything else. The kind decides the colour, the generator
	 * decides the text.
	 */
	function tokenize(line:String, kinds:Array<Int>, texts:Array<String>):Void
	{
		var n:Int = line.length;
		var i:Int = 0;

		while (i < n)
		{
			var c:String = line.charAt(i);

			if (c == '-' && i + 1 < n && line.charAt(i + 1) == '-')
			{
				emit(kinds, texts, TOK_COMMENT, line.substr(i));
				return;
			}

			if (c == '\'' || c == '"')
			{
				var end:Int = i + 1;
				while (end < n)
				{
					var q:String = line.charAt(end);
					if (q == '\\')
					{
						end += 2;
						continue;
					}

					end++;
					if (q == c)
						break;
				}

				var stop:Int = (end > n) ? n : end;
				emit(kinds, texts, TOK_STRING, line.substring(i, stop));
				i = stop;
				continue;
			}

			if (isDigit(c))
			{
				var end:Int = i + 1;
				if (c == '0' && end < n && (line.charAt(end) == 'x' || line.charAt(end) == 'X'))
				{
					end++;
					while (end < n && isHexDigit(line.charAt(end)))
						end++;
				}
				else
				{
					while (end < n && (isDigit(line.charAt(end)) || line.charAt(end) == '.'))
						end++;
				}

				emit(kinds, texts, TOK_NUMBER, line.substring(i, end));
				i = end;
				continue;
			}

			if (isIdentStart(c))
			{
				var end:Int = i + 1;
				while (end < n && isIdentChar(line.charAt(end)))
					end++;

				var word:String = line.substring(i, end);
				var kind:Int = TOK_OTHER;

				if (isKeyword(word))
					kind = TOK_KEYWORD;
				else if (callFollows(line, end))
					kind = TOK_BUILTIN;

				emit(kinds, texts, kind, word);
				i = end;
				continue;
			}

			var end:Int = i + 1;
			while (end < n && isOtherChar(line, end))
				end++;

			emit(kinds, texts, TOK_OTHER, line.substring(i, end));
			i = end;
		}
	}

	static function emit(kinds:Array<Int>, texts:Array<String>, kind:Int, text:String):Void
	{
		if (text == null || text.length == 0)
			return;

		var last:Int = kinds.length - 1;
		if (last >= 0 && kinds[last] == kind)
		{
			texts[last] += text;
			return;
		}

		kinds.push(kind);
		texts.push(text);
	}

	static function colorFor(kind:Int):Int
	{
		return switch (kind)
		{
			case TOK_COMMENT: COLOR_COMMENT;
			case TOK_KEYWORD: COLOR_KEYWORD;
			case TOK_STRING: COLOR_STRING;
			case TOK_NUMBER: COLOR_NUMBER;
			case TOK_BUILTIN: COLOR_BUILTIN;
			default: COLOR_TEXT;
		}
	}

	static function isKeyword(word:String):Bool
	{
		return KEYWORDS.indexOf(word) >= 0;
	}

	static function isDigit(c:String):Bool
	{
		return c >= '0' && c <= '9';
	}

	static function isHexDigit(c:String):Bool
	{
		if (isDigit(c))
			return true;

		var lower:String = c.toLowerCase();
		return lower >= 'a' && lower <= 'f';
	}

	static function isIdentStart(c:String):Bool
	{
		var lower:String = c.toLowerCase();
		return (lower >= 'a' && lower <= 'z') || c == '_';
	}

	static function isIdentChar(c:String):Bool
	{
		return isIdentStart(c) || isDigit(c);
	}

	/** True while the character at `index` belongs to a run of operators, spaces and punctuation. */
	static function isOtherChar(line:String, index:Int):Bool
	{
		var c:String = line.charAt(index);
		if (c == '-' && index + 1 < line.length && line.charAt(index + 1) == '-')
			return false;

		return c != '\'' && c != '"' && !isDigit(c) && !isIdentStart(c);
	}

	/** True when the next non-space character after an identifier opens a call. */
	static function callFollows(line:String, index:Int):Bool
	{
		var i:Int = index;
		while (i < line.length && (line.charAt(i) == ' ' || line.charAt(i) == '\t'))
			i++;

		return i < line.length && line.charAt(i) == '(';
	}

	/** The step of the first `curStep == N` guard in a line, or -1 when the line has none. */
	static function stepInLine(line:String):Int
	{
		if (line == null)
			return -1;

		var from:Int = line.indexOf('curStep');
		while (from != -1)
		{
			var i:Int = from + 7;
			var n:Int = line.length;

			while (i < n && line.charAt(i) == ' ')
				i++;

			if (i + 1 < n && line.charAt(i) == '=' && line.charAt(i + 1) == '=')
			{
				i += 2;
				while (i < n && line.charAt(i) == ' ')
					i++;

				var start:Int = i;
				while (i < n && isDigit(line.charAt(i)))
					i++;

				if (i > start)
				{
					var value:Null<Int> = Std.parseInt(line.substring(start, i));
					if (value != null)
						return value;
				}
			}

			from = line.indexOf('curStep', from + 1);
		}

		return -1;
	}

	function refreshStepBar():Void
	{
		if (stepBar == null)
			return;

		if (stepLine < 0)
		{
			stepBar.visible = false;
			return;
		}

		var y:Float = codeY + stepLine * rowH - scroll;
		var top:Float = Math.max(codeY, y);
		var bottom:Float = Math.min(codeY + codeH, y + rowH);

		if (bottom - top < 2)
		{
			stepBar.visible = false;
			return;
		}

		stepBar.visible = true;
		setBar(stepBar, codeX, top, Math.max(2, Math.round(3 * BlockLayout.scale)), bottom - top);
	}

	function refreshScrollbar():Void
	{
		if (scrollTrack == null || scrollThumb == null)
			return;

		if (maxScroll <= 0.5)
		{
			scrollTrack.visible = false;
			scrollThumb.visible = false;
			thumbH = 0;
			return;
		}

		var contentH:Float = lineCount * rowH;
		thumbH = Math.max(BlockLayout.touchSize() * 0.6, codeH * (codeH / contentH));
		if (thumbH > codeH)
			thumbH = codeH;

		var thumbY:Float = codeY + (scroll / maxScroll) * (codeH - thumbH);

		scrollTrack.visible = true;
		scrollThumb.visible = true;
		setBar(scrollThumb, trackX, thumbY, scrollbarW, thumbH);
	}

	// --- Scrolling -----------------------------------------------------------------------------

	function scrollBy(delta:Float):Void
	{
		setScroll(scroll + delta);
	}

	function setScroll(value:Float):Void
	{
		var next:Float = value;
		if (next < 0)
			next = 0;
		if (next > maxScroll)
			next = maxScroll;

		if (Math.abs(next - scroll) < 0.01)
			return;

		scroll = next;
		renderDirty = true;
	}

	/** Rounds a scroll offset to a whole line, so no row is ever cut in half. */
	function snapScroll(value:Float):Float
	{
		if (rowH <= 0)
			return 0;

		return Math.round(value / rowH) * rowH;
	}

	function clampScroll():Void
	{
		maxScroll = Math.max(0, lineCount * rowH - codeH);
		if (scroll > maxScroll)
			scroll = maxScroll;
		if (scroll < 0)
			scroll = 0;
	}

	/** Moves the scroll so the thumb follows `y` (a point on the track). */
	function scrollToTrack(y:Float):Void
	{
		if (maxScroll <= 0 || thumbH <= 0)
			return;

		var span:Float = Math.max(1, codeH - thumbH);
		var fraction:Float = (y - codeY - thumbH * 0.5) / span;
		if (fraction < 0)
			fraction = 0;
		if (fraction > 1)
			fraction = 1;

		setScroll(fraction * maxScroll);
	}

	// --- Input ---------------------------------------------------------------------------------

	function pollPointer():Void
	{
		ptrPressed = false;
		ptrJustPressed = false;
		ptrJustReleased = false;

		var camera:FlxCamera = activeCamera();
		if (camera == null)
			return;

		#if FLX_TOUCH
		if (pollTouch(camera))
			return;
		#end

		if (FlxG.mouse == null)
			return;

		var pos:FlxPoint = FlxG.mouse.getScreenPosition(camera, ptrPoint);
		ptrX = pos.x;
		ptrY = pos.y;
		ptrPressed = FlxG.mouse.pressed;
		ptrJustPressed = FlxG.mouse.justPressed;
		ptrJustReleased = FlxG.mouse.justReleased;
	}

	#if FLX_TOUCH
	/** Touch first: a finger claims the panel until it is lifted, only then the mouse is read. */
	function pollTouch(camera:FlxCamera):Bool
	{
		if (FlxG.touches == null)
			return false;

		if (activeTouchID >= 0)
		{
			for (touch in FlxG.touches.list)
			{
				if (touch == null || touch.touchPointID != activeTouchID)
					continue;

				readTouch(camera, touch);
				ptrJustPressed = false;
				if (!ptrPressed)
					activeTouchID = -1;

				return true;
			}

			activeTouchID = -1;
			return false;
		}

		for (touch in FlxG.touches.list)
		{
			if (touch == null || !touch.justPressed)
				continue;

			activeTouchID = touch.touchPointID;
			readTouch(camera, touch);
			ptrJustPressed = true;
			return true;
		}

		return false;
	}

	function readTouch(camera:FlxCamera, touch:FlxTouch):Void
	{
		var pos:FlxPoint = touch.getScreenPosition(camera, ptrPoint);
		ptrX = pos.x;
		ptrY = pos.y;
		ptrPressed = touch.pressed;
		ptrJustReleased = touch.justReleased;
	}
	#end

	function handlePointer():Void
	{
		if (ptrJustPressed)
			beginPress();
		else if (ptrPressed)
			continuePress();
		else if (ptrJustReleased)
			endPress();

		if (FlxG.mouse != null && FlxG.mouse.wheel != 0 && dragMode == DRAG_NONE && overPanel())
		{
			// One notch is one gesture on every platform: some report `1`, some `120`, some `3` for a
			// fast spin, and none of those should fling the view to an end.
			var steps:Int = Std.int(FlxMath.bound(FlxG.mouse.wheel, -1, 1));
			manualScroll = FOLLOW_COOLDOWN;
			setScroll(snapScroll(scroll - steps * rowH * WHEEL_LINES));
		}
	}

	function beginPress():Void
	{
		dragMode = DRAG_NONE;

		if (!overPanel())
			return;

		if (hit(closeX, btnY, closeW, btnSize))
		{
			playSound('cancelMenu');
			close();
			if (onClose != null)
				onClose();
			return;
		}

		if (hit(expandX, btnY, expandW, btnSize))
		{
			playSound('confirmMenu');
			if (onExpand != null)
				onExpand();
			return;
		}

		if (hit(trackX, codeY, scrollbarW, codeH))
		{
			dragMode = DRAG_BAR;
			manualScroll = FOLLOW_COOLDOWN;
			scrollToTrack(ptrY);
			return;
		}

		if (overCode())
		{
			dragMode = DRAG_CODE;
			dragLastY = ptrY;
			manualScroll = FOLLOW_COOLDOWN;
		}
	}

	function continuePress():Void
	{
		if (dragMode == DRAG_CODE)
		{
			manualScroll = FOLLOW_COOLDOWN;
			scrollBy(dragLastY - ptrY);
			dragLastY = ptrY;
			return;
		}

		if (dragMode == DRAG_BAR)
		{
			manualScroll = FOLLOW_COOLDOWN;
			scrollToTrack(ptrY);
		}
	}

	function endPress():Void
	{
		if (dragMode == DRAG_CODE)
			setScroll(snapScroll(scroll));

		dragMode = DRAG_NONE;
	}

	// --- Helpers -------------------------------------------------------------------------------

	/** The camera the panel is drawn on: the one it was built for, else the group's, else the game's. */
	function activeCamera():FlxCamera
	{
		if (cam != null)
			return cam;

		var list:Array<FlxCamera> = cameras;
		if (list != null && list.length > 0 && list[0] != null)
			return list[0];

		return FlxG.camera;
	}

	function hit(x:Float, y:Float, w:Float, h:Float):Bool
	{
		return ptrX >= x && ptrX <= x + w && ptrY >= y && ptrY <= y + h;
	}

	function overPanel():Bool
	{
		return hit(rectX, rectY, rectW, rectH);
	}

	function overCode():Bool
	{
		return hit(codeX, codeY, Math.max(1, trackX - codeX), codeH);
	}

	/** Width of `text` in the given size, measured with the one shared measuring text. */
	function measureText(text:String, size:Int):Float
	{
		if (measure == null || text == null)
			return 0;

		if (measure.size != size)
			measure.setFormat(Paths.font('vcr.ttf'), size, FlxColor.WHITE, FlxTextAlign.LEFT);

		if (measure.text != text)
			measure.text = text;

		// Reading `width` regenerates the text field, which is what keeps the measurement exact.
		return measure.width;
	}

	/** Shortens `text` with an ellipsis until it fits `maxWidth`. */
	function fitToWidth(text:String, maxWidth:Float, size:Int):String
	{
		var value:String = (text != null) ? text : '';
		if (value.length == 0 || maxWidth <= 0)
			return '';
		if (measureText(value, size) <= maxWidth)
			return value;

		var low:Int = 1;
		var high:Int = value.length;
		var best:Int = 0;

		while (low <= high)
		{
			var mid:Int = Std.int((low + high) * 0.5);
			if (measureText(value.substr(0, mid) + '...', size) <= maxWidth)
			{
				best = mid;
				low = mid + 1;
			}
			else
				high = mid - 1;
		}

		if (best <= 0)
			return '';
		if (best >= value.length)
			return value;

		return value.substr(0, best) + '...';
	}

	static function digitCount(value:Int):Int
	{
		var digits:Int = 1;
		var left:Int = (value < 0) ? -value : value;

		while (left >= 10)
		{
			left = Std.int(left / 10);
			digits++;
		}

		return digits;
	}

	static function playSound(name:String):Void
	{
		if (FlxG.sound == null)
			return;

		var sound = Paths.sound(name);
		if (sound == null)
			return;

		try
		{
			FlxG.sound.play(sound);
		}
		catch (e:Dynamic)
		{
			// A missing click must never break the preview.
		}
	}
}

/** One coloured run of a code line: what to draw, in which colour and where it starts. */
private typedef PreviewSegment =
{
	var color:Int;
	var text:String;
	var x:Float;
}

/** A line ready to draw: its coloured runs, already cut to the columns that fit. */
private typedef PreviewLine =
{
	var segments:Array<PreviewSegment>;
}
