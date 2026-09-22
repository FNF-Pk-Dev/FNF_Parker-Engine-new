package editors.blockcode;

import editors.blockcode.BlockTypes.BlockData;
import editors.blockcode.BlockTypes.ParamType;
import flixel.input.keyboard.FlxKey;
import flixel.input.touch.FlxTouch;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

/**
 * The draggable block sprite of the block-code editor together with its inline `InputField`s.
 *
 * The body is rasterised straight into `pixels` as a puzzle piece:
 *
 * - a rounded silhouette (`6 * BlockLayout.blockScale()` corners) with a 1px darker outline and a
 *   soft drop shadow (`shadow`: a second sprite sharing this graphic, tinted black at 35% alpha
 *   and offset by `3 * BlockLayout.scale`);
 * - a bevel of `Math.max(4, 4 * blockScale())` pixels — lighter along the top/left, darker along
 *   the bottom/right of the block colour — so a chain reads as stacked plastic bricks;
 * - a tongue on the top edge and a matching groove on the bottom edge at the same `x`, so a
 *   stacked chain interlocks visually (the groove of the upper block sits right above the tongue
 *   of the lower one);
 * - reporters are pills with fully rounded ends, a smaller height and no tongue/groove;
 * - hat blocks (`BlockLibrary.isHat`) draw a curved dome instead of a tongue.
 *
 * Every metric comes from `BlockLayout`, so the same code renders a comfortable block on a
 * 1280x720 window and on a 2340x1080 phone in either orientation: `update()` re-runs
 * `recalculateSize()` as soon as the viewport metrics changed.
 */
class Block extends FlxSprite
{
	/**
	 * Called when a text parameter is tapped: the substate opens the soft
	 * keyboard (or its inline editor) for that field.
	 */
	public static var requestTextEdit:InputField->Void = null;

	/** Called when a CODE parameter is tapped: the substate opens the multiline panel. */
	public static var requestCodeEdit:InputField->Void = null;

	/** Called after any inline value changed, so the substate can mark the project dirty. */
	public static var onAnyValueChanged:Void->Void = null;

	/**
	 * True while an external editor (the native soft keyboard or the on-screen keyboard) owns the
	 * focused field. The legacy physical-key typing inside `InputField` must stay out of the way
	 * then, otherwise every keystroke would be inserted twice.
	 */
	public static var externalEditorActive:Bool = false;

	// Dark theme palette, shared with every other block-editor surface.
	static inline var COLOR_TEXT:Int = 0xFFC0CAF5;
	static inline var COLOR_SOCKET:Int = 0xFF101014;
	static inline var COLOR_SHADOW:Int = 0xFF000000;
	static inline var COLOR_LABEL_OUTLINE:Int = 0xCC000000;

	static inline var SHADOW_ALPHA:Float = 0.35;
	static inline var HOVER_SCALE:Float = 1.05;
	static inline var HOVER_LERP:Float = 8;
	static inline var OUTLINE_DARKEN:Float = 0.62;
	static inline var BEVEL_DARKEN:Float = 0.34;
	static inline var BEVEL_LIGHTEN:Float = 0.18;

	/** Smallest block width, before the label and the inputs have their say. */
	static inline var MIN_BLOCK_WIDTH:Float = 150;

	/** Input boxes never get narrower than this, whatever the viewport reports. */
	static inline var MIN_INPUT_WIDTH:Float = 78;

	/** Widest row of inputs before the next parameter wraps onto a second row. */
	static inline var MAX_CONTENT_ROW:Float = 720;

	public var blockData:BlockData;
	public var isTemplate:Bool;

	// Visual elements
	public var label:FlxText;
	public var icon:FlxText;
	public var inputFields:Array<InputField> = [];

	/** Drop shadow, drawn under the body. Shares this sprite's graphic, tinted black. */
	public var shadow:FlxSprite;

	/** True for event blocks, which start a `function` in the generated script. */
	public var isHatBlock(default, null):Bool = false;

	/**
	 * Set by the substate while a dragged block is snapping onto this one; draws a bright rim and a
	 * soft glow into the body until it is cleared again.
	 */
	public var snapHintActive(default, set):Bool = false;

	// Snapping logic
	public var nextBlock:Block = null;
	public var prevBlock:Block = null;
	public var isSnapped:Bool = false;
	public var isDragging:Bool = false;

	// Reporter logic
	public var isReporter:Bool = false;

	/** Input this reporter is plugged into, when it is not stacked on a block. */
	public var parentInput:InputField = null;

	// Animation
	public var targetScale:Float = 1.0;

	// Dimensions, recomputed by `layoutInputs()`
	var minWidth:Float = MIN_BLOCK_WIDTH;
	var minHeight:Float = 46;

	// Input layout, relative to the block origin
	var inputOffsetX:Array<Float> = [];
	var inputOffsetY:Array<Float> = [];

	// Geometry, all derived from BlockLayout by `refreshMetrics()`
	var blockScale:Float = 1;
	var cornerRadius:Float = 6;
	var hatRadius:Float = 16;
	var bevel:Int = 4;
	var studX:Float = 26;
	var studWidth:Float = 20;
	var studHeight:Int = 5;
	var edgeGap:Float = 12;
	var rowGap:Float = 4;
	var bottomPadding:Float = 8;
	var shadowOffset:Float = 3;
	var bodyColor:Int = 0xFF3D59A1;
	var outlineColor:Int = 0xFF000000;
	var darkColor:Int = 0;
	var lightColor:Int = 0xFFFFFFFF;

	// Text placement, relative to the block origin
	var labelOffsetX:Float = 0;
	var labelOffsetY:Float = 0;
	var iconOffsetX:Float = 0;
	var iconOffsetY:Float = 0;
	var contentStartX:Float = 0;

	var recalculating:Bool = false;
	var layoutReady:Bool = false;
	var lastLayoutRevision:Float = -1;
	var pointerPoint:FlxPoint = new FlxPoint(0, 0);

	public function new(x:Float, y:Float, data:BlockData, isTemplate:Bool = false)
	{
		super(x, y);

		this.blockData = data;
		this.isTemplate = isTemplate;
		this.isReporter = (data != null && data.isReporter == true);
		this.isHatBlock = (data != null && BlockLibrary.isHat(data.type));

		refreshMetrics();

		label = new FlxText(x, y, 0, (data == null) ? '' : data.label, BlockLayout.font('body'));
		icon = new FlxText(x, y, 0, categoryIcon((data == null) ? '' : data.category), BlockLayout.font('title'));

		shadow = new FlxSprite(x + shadowOffset, y + shadowOffset);
		shadow.alpha = SHADOW_ALPHA;
		shadow.color = COLOR_SHADOW;

		applyTextFormats();

		if (data != null && data.parameters != null)
		{
			for (param in data.parameters)
			{
				var height:Float = inputHeight();
				var input = new InputField(0, 0, inputWidth(param.type), height, param.defaultValue, param.type, param.name);
				input.parentBlock = this;
				inputFields.push(input);
			}
		}

		recalculateSize();

		// Spawn animation
		scale.set(0, 0);
		FlxTween.tween(this.scale, {x: 1, y: 1}, 0.3, {ease: FlxEase.backOut});
		alpha = 0;
		FlxTween.tween(this, {alpha: 1}, 0.2);
	}

	function set_snapHintActive(value:Bool):Bool
	{
		if (snapHintActive == value)
			return value;

		snapHintActive = value;

		if (layoutReady)
			redrawBlock();

		return value;
	}

	static function categoryIcon(category:String):String
	{
		switch (category)
		{
			case "Events":
				return "⚡";
			case "Control":
				return "🔄";
			case "Objects", "Looks":
				return "👁️";
			case "Audio", "Sound":
				return "🎵";
			case "Tween", "Motion":
				return "✨";
			case "Game":
				return "🎮";
			case "Operators":
				return "➕";
			case "Sensing":
				return "🔍";
			default:
				return "★";
		}
	}

	// ----------------------------------------------------------------------------------- metrics

	/** Floor height of a stack block: a full touch target with room for the tongue. */
	public static function stackMinHeight():Float
	{
		return Math.max(BlockLayout.touchSize() + 6, 46 * BlockLayout.scale);
	}

	/** Floor height of a reporter: as tall as the input box it plugs into, so it sits flush. */
	public static function reporterMinHeight():Float
	{
		return Math.max(BlockLayout.touchSize() - 6, 32 * BlockLayout.scale);
	}

	/** Height of an inline input box. */
	public static function inputHeight():Float
	{
		return Math.max(32, BlockLayout.touchSize() - 8);
	}

	/** Height of the input boxes *inside* a reporter: small enough to keep the pill compact. */
	public static function reporterInputHeight():Float
	{
		return Math.max(24, inputHeight() - 8);
	}

	/** Width of an inline input box for a parameter type. */
	public static function inputWidth(type:ParamType):Float
	{
		var minimum:Float = Math.max(MIN_INPUT_WIDTH, 84 * BlockLayout.scale);
		var scaleFactor:Float = BlockLayout.blockScale();

		if (type == ParamType.CODE)
			return Math.max(minimum * 1.4, 180 * scaleFactor);
		if (type == ParamType.COLOR)
			return Math.max(minimum, 96 * scaleFactor);
		if (type == ParamType.SELECT)
			return Math.max(minimum, 110 * scaleFactor);

		return minimum;
	}

	/** Where the inline parameters wrap: the workspace, capped so a block never spans a phone screen. */
	public static function maxContentRow():Float
	{
		var area = BlockLayout.workspace();
		var limit:Float = Math.min(area.w - 32 * BlockLayout.scale, MAX_CONTENT_ROW * BlockLayout.scale);

		return Math.max(280 * BlockLayout.scale, limit);
	}

	/** Recomputes every size, colour and padding from the current `BlockLayout` metrics. */
	function refreshMetrics():Void
	{
		blockScale = BlockLayout.blockScale();
		cornerRadius = Math.max(4, Math.round(6 * blockScale));
		hatRadius = Math.max(10, Math.round(18 * blockScale));
		bevel = Std.int(Math.max(4, Math.round(4 * blockScale)));
		studWidth = Math.max(14, Math.round(20 * blockScale));
		studHeight = Std.int(Math.max(4, Math.round(5 * blockScale)));
		studX = Math.round(26 * blockScale);
		edgeGap = Math.max(8, Math.round(12 * BlockLayout.scale));
		rowGap = BlockLayout.spacing('tight');
		bottomPadding = Math.max(studHeight + 4, Math.round(8 * blockScale));
		shadowOffset = Math.max(2, Math.round(3 * BlockLayout.scale));

		var raw:Int = (blockData == null) ? 0xFF3D59A1 : blockData.color;
		if ((raw & 0xFF000000) == 0)
			raw |= 0xFF000000;

		bodyColor = raw;

		var colour:FlxColor = FlxColor.fromInt(raw);
		darkColor = colour.getDarkened(BEVEL_DARKEN);
		lightColor = colour.getLightened(BEVEL_LIGHTEN);
		outlineColor = colour.getDarkened(OUTLINE_DARKEN);
	}

	/** Applies the responsive type sizes to the label and the category glyph. */
	function applyTextFormats():Void
	{
		if (label != null)
		{
			var labelSize:Int = BlockLayout.font('body');
			label.setFormat(Paths.font("vcr.ttf"), labelSize, COLOR_TEXT, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, COLOR_LABEL_OUTLINE);
			label.borderSize = Math.max(1, Math.round(labelSize * 0.1));
		}

		if (icon != null)
		{
			var iconSize:Int = BlockLayout.font('title');
			icon.setFormat(Paths.font("vcr.ttf"), iconSize, COLOR_TEXT, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, COLOR_LABEL_OUTLINE);
			icon.borderSize = Math.max(1, Math.round(iconSize * 0.1));
		}
	}

	// ------------------------------------------------------------------------------------ layout

	/** Resizes the block to its label plus every input, wrapping them onto extra rows when needed. */
	public function recalculateSize():Void
	{
		if (recalculating)
			return;

		recalculating = true;

		refreshMetrics();
		applyTextFormats();
		layoutInputs();
		redrawBlock();

		lastLayoutRevision = layoutRevision();
		recalculating = false;

		if (parentInput != null && parentInput.parentBlock != null && parentInput.parentBlock != this)
			parentInput.parentBlock.recalculateSize();
	}

	function layoutInputs():Void
	{
		inputOffsetX = [];
		inputOffsetY = [];

		var pad:Float = horizontalPadding();
		var bottom:Float = bottomPadding;
		if (isReporter)
		{
			bottom = Math.max(3, Math.round(4 * blockScale));
			pad = Math.max(pad, Math.round(reporterMinHeight() * 0.45));
		}

		var floorHeight:Float = isReporter ? reporterMinHeight() : stackMinHeight();
		var floorWidth:Float = isReporter ? 0 : MIN_BLOCK_WIDTH * blockScale;
		var iconWidth:Float = (icon != null) ? Math.max(icon.width, Math.ceil(BlockLayout.font('title') * 0.55)) : 0;
		var labelWidth:Float = (label != null) ? Math.max(label.width, 0) : 0;

		iconOffsetX = pad;
		labelOffsetX = iconOffsetX + iconWidth + Math.round(pad * 0.6);
		contentStartX = labelOffsetX + labelWidth + pad;

		var topPad:Float = contentTop();
		var maxRow:Float = maxContentRow();
		var cursorX:Float = contentStartX;
		var rowY:Float = topPad;
		var rowHeight:Float = 0;
		var firstRowHeight:Float = 0;
		var maxRight:Float = contentStartX;
		var placed:Int = 0;

		for (input in inputFields)
		{
			var slotWidth:Float = inputWidth(input.type);
			var slotHeight:Float = 0;

			if (isReporter)
				input.setBaseHeight(reporterInputHeight());

			if (input.attachedBlock != null)
			{
				slotWidth = Math.max(slotWidth, input.attachedBlock.width + pad * 0.5);
				slotHeight = input.attachedBlock.height + rowGap;
			}

			input.width = slotWidth;
			slotHeight = Math.max(slotHeight, input.height);

			if (placed > 0 && cursorX + slotWidth + pad > maxRow)
			{
				rowY += rowHeight + rowGap;
				cursorX = contentStartX;
				rowHeight = 0;
			}

			inputOffsetX.push(cursorX);
			inputOffsetY.push(rowY);

			cursorX += slotWidth + rowGap * 2;
			maxRight = Math.max(maxRight, cursorX - rowGap * 2);
			rowHeight = Math.max(rowHeight, slotHeight);

			if (placed == 0)
				firstRowHeight = rowHeight;

			placed++;
		}

		var contentBottom:Float = (placed > 0) ? rowY + rowHeight + bottom : 0;
		minHeight = Math.max(floorHeight, contentBottom);
		minWidth = Math.max(floorWidth, maxRight + pad);

		if (placed == 0)
			minWidth = Math.max(floorWidth, labelOffsetX + labelWidth + pad);

		// Centre the inline row inside the block: a hat keeps most of the slack under its dome.
		var slack:Float = (placed > 0) ? Math.max(0, minHeight - contentBottom) : 0;
		var shift:Float = (placed > 0) ? slack * (isHatBlock ? 0.85 : 0.5) : 0;

		if (shift > 0)
		{
			for (i in 0...inputOffsetY.length)
				inputOffsetY[i] += shift;
		}

		// The label and the category glyph sit on the first input row, like the first line of code.
		var bandTop:Float;
		var bandHeight:Float;

		if (placed > 0)
		{
			bandTop = inputOffsetY[0];
			bandHeight = firstRowHeight;
		}
		else
		{
			bandTop = isHatBlock ? Math.round(hatRadius * 0.85) : 0;
			bandHeight = Math.max(BlockLayout.font('body'), minHeight - bandTop - (isHatBlock ? bottom : 0));
		}

		var labelHeight:Float = (label != null) ? label.height : BlockLayout.font('body');
		var iconHeight:Float = (icon != null) ? icon.height : BlockLayout.font('title');
		var maxLabelTop:Float = Math.max(2, minHeight - bottom - labelHeight);
		var maxIconTop:Float = Math.max(2, minHeight - bottom - iconHeight);

		labelOffsetY = Math.round(FlxMath.bound(bandTop + (bandHeight - labelHeight) * 0.5, 2, maxLabelTop));
		iconOffsetY = Math.round(FlxMath.bound(bandTop + (bandHeight - iconHeight) * 0.5, 2, maxIconTop));
	}

	function horizontalPadding():Float
	{
		return Math.max(6, Math.round(isReporter ? edgeGap * 0.7 : edgeGap));
	}

	function contentTop():Float
	{
		if (isHatBlock)
			return Math.round(hatRadius * 0.6);
		if (isReporter)
			return Math.max(3, Math.round(4 * blockScale));

		return Math.round(rowGap * 1.5);
	}

	/** A value that changes whenever BlockLayout reports new metrics. */
	function layoutRevision():Float
	{
		return BlockLayout.scale * 1000
			+ BlockLayout.blockScale() * 100
			+ (BlockLayout.portrait ? 1 : 0)
			+ (BlockLayout.isMobile() ? 2 : 0);
	}

	// ----------------------------------------------------------------------------------- painting

	/** Paints the block body: pill for reporters, bevel + tongue/groove for stack blocks. */
	public function redrawBlock():Void
	{
		refreshMetrics();
		applyTextFormats();

		var w:Int = Std.int(Math.max(1, Math.ceil(minWidth)));
		var h:Int = Std.int(Math.max(1, Math.ceil(minHeight)));

		// `Unique` matters: without it `FlxG.bitmap` hands out one shared graphic per size/colour, so
		// every equally sized block would overwrite the others' pixels.
		makeGraphic(w, h, FlxColor.TRANSPARENT, true);

		var pixels:BitmapData = this.pixels;
		if (pixels != null)
		{
			pixels.lock();

			if (isReporter)
				paintReporter(pixels, w, h);
			else
				paintStackBlock(pixels, w, h);

			if (snapHintActive)
				paintSnapHint(pixels, w, h);

			pixels.unlock();
		}

		this.width = w;
		this.height = h;

		if (shadow != null)
		{
			shadow.loadGraphicFromSprite(this);
			shadow.dirty = true;
			shadow.alpha = SHADOW_ALPHA;
			shadow.color = COLOR_SHADOW;
		}

		layoutReady = true;
	}

	function paintStackBlock(pixels:BitmapData, w:Int, h:Int):Void
	{
		var top:Float = topRadiusFor(h);
		var bottom:Float = Math.min(cornerRadius, h * 0.5);
		var innerTop:Float = Math.max(2, top - 1);
		var innerBottom:Float = Math.max(2, bottom - 1);

		// 1px darker outline around the whole silhouette.
		BlockPaint.fillRoundRectComplex(pixels, 0, 0, w, h, top, top, bottom, bottom, outlineColor, true);

		// Bevel: dark base, a lit band on the top/left, the block colour in the middle.
		BlockPaint.fillRoundRectComplex(pixels, 1, 1, w - 2, h - 2, innerTop, innerTop, innerBottom, innerBottom, darkColor);
		BlockPaint.fillRoundRectComplex(pixels, 1, 1, w - 1 - bevel, h - 1 - bevel, innerTop, innerTop, innerBottom, innerBottom, lightColor);
		BlockPaint.fillRoundRectComplex(pixels, 1 + bevel, 1 + bevel, w - 2 - 2 * bevel, h - 2 - 2 * bevel, innerTop, innerTop, innerBottom, innerBottom,
			bodyColor);

		if (!isHatBlock)
			paintStud(pixels, w);

		paintSocket(pixels, w, h);
	}

	function paintReporter(pixels:BitmapData, w:Int, h:Int):Void
	{
		var radius:Float = h * 0.5;
		var inner:Float = Math.max(1, radius - 1);
		var cap:Float = Math.max(1, radius - bevel);
		var bodyX:Float = 1 + bevel;
		var bodyY:Float = 1 + bevel;
		var bodyW:Float = w - 2 - 2 * bevel;
		var bodyH:Float = h - 2 - 2 * bevel;

		BlockPaint.fillRoundRectComplex(pixels, 0, 0, w, h, radius, radius, radius, radius, outlineColor, true);
		BlockPaint.fillRoundRectComplex(pixels, 1, 1, w - 2, h - 2, inner, inner, inner, inner, darkColor);
		BlockPaint.fillRoundRectComplex(pixels, 1, 1, w - 1 - bevel, h - 1 - bevel, inner, inner, inner, inner, lightColor);
		BlockPaint.fillRoundRectComplex(pixels, bodyX, bodyY, bodyW, bodyH, cap, cap, cap, cap, bodyColor);
	}

	/** The raised tongue on the top edge. `socketLeft` keeps it aligned with the groove below. */
	function paintStud(pixels:BitmapData, w:Int):Void
	{
		var x:Int = socketLeft(w);
		var tabWidth:Int = socketWidth(w, x);
		if (tabWidth < 6 || studHeight < 2)
			return;

		var y:Int = 1;

		pixels.fillRect(new Rectangle(x, y, tabWidth, studHeight), bodyColor);
		pixels.fillRect(new Rectangle(x, y, tabWidth, 1), lightColor);
		pixels.fillRect(new Rectangle(x, y + studHeight - 1, tabWidth, 1), darkColor);
		pixels.fillRect(new Rectangle(x - 1, y, 1, studHeight), outlineColor);
		pixels.fillRect(new Rectangle(x + tabWidth, y, 1, studHeight), outlineColor);
	}

	/** The groove carved into the bottom edge, straight above the tongue of the next block. */
	function paintSocket(pixels:BitmapData, w:Int, h:Int):Void
	{
		var x:Int = socketLeft(w);
		var tabWidth:Int = socketWidth(w, x);
		if (tabWidth < 6 || h < studHeight + cornerRadius + 2)
			return;

		var y:Int = h - 1 - studHeight;
		var radius:Float = studHeight * 0.5;

		BlockPaint.fillRoundRectComplex(pixels, x - 1, y - 1, tabWidth + 2, studHeight + 2, radius, radius, 0, 0, outlineColor);
		BlockPaint.fillRoundRectComplex(pixels, x, y, tabWidth, studHeight + 1, radius, radius, 0, 0, COLOR_SOCKET);
	}

	/** Bright 2px rim plus a soft glow, painted into the body while a dragged block snaps here. */
	function paintSnapHint(pixels:BitmapData, w:Int, h:Int):Void
	{
		var top:Float = topRadiusFor(h);
		var bottom:Float = isReporter ? h * 0.5 : Math.min(cornerRadius, h * 0.5);

		BlockPaint.strokeRoundRectComplex(pixels, 0, 0, w, h, top, top, bottom, bottom, Math.max(4, bevel + 2), COLOR_TEXT, 0.28);
		BlockPaint.strokeRoundRectComplex(pixels, 0, 0, w, h, top, top, bottom, bottom, 2, COLOR_TEXT);
	}

	function topRadiusFor(h:Float):Float
	{
		if (!isHatBlock)
			return Math.min(cornerRadius, h * 0.5);

		return Math.min(hatRadius, h * 0.45);
	}

	/** Left edge of the tongue/groove: a fixed offset so blocks of different widths still interlock. */
	function socketLeft(w:Int):Int
	{
		var wanted:Float = Math.min(studX, w - studWidth - cornerRadius - 2);

		return Std.int(Math.max(cornerRadius + 2, wanted));
	}

	function socketWidth(w:Int, x:Int):Int
	{
		return Std.int(Math.min(studWidth, w - x - 2));
	}

	// ------------------------------------------------------------------------- drag / hover / input

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		BlockLayout.ensure();

		if (!layoutReady || layoutRevision() != lastLayoutRevision)
			recalculateSize();

		// Follow logic
		if (parentInput != null)
		{
			this.x = parentInput.bg.x;
			this.y = parentInput.bg.y + (parentInput.height - height) / 2;
		}
		else if (prevBlock != null && isSnapped)
		{
			this.x = prevBlock.x;
			this.y = prevBlock.y + prevBlock.height;
		}

		// Update visuals position
		if (label != null)
		{
			label.x = x + labelOffsetX;
			label.y = y + labelOffsetY;
		}

		if (icon != null)
		{
			icon.x = x + iconOffsetX;
			icon.y = y + iconOffsetY;
		}

		// Update inputs
		for (i in 0...inputFields.length)
		{
			var input = inputFields[i];
			if (i < inputOffsetX.length)
				input.updatePosition(x + inputOffsetX[i], y + inputOffsetY[i]);
			input.update(elapsed);
		}

		updateShadow();

		// Hover animation
		if (!isDragging)
		{
			targetScale = (isMouseOver(camera) && parentInput == null && prevBlock == null) ? HOVER_SCALE : 1.0;
			scale.x = FlxMath.lerp(scale.x, targetScale, elapsed * HOVER_LERP);
			scale.y = FlxMath.lerp(scale.y, targetScale, elapsed * HOVER_LERP);
		}
	}

	function updateShadow():Void
	{
		if (shadow == null)
			return;

		shadow.setPosition(x + shadowOffset, y + shadowOffset);
		shadow.scale.copyFrom(scale);
		shadow.alpha = SHADOW_ALPHA * alpha;
		shadow.visible = visible && alpha > 0.01;
	}

	override public function draw():Void
	{
		if (shadow != null && shadow.visible)
		{
			shadow.scrollFactor.copyFrom(scrollFactor);
			shadow.cameras = cameras;
			shadow.draw();
		}

		super.draw();

		if (icon != null && icon.visible)
		{
			icon.scrollFactor.copyFrom(scrollFactor);
			icon.cameras = cameras;
			icon.draw();
		}

		if (label != null && label.visible)
		{
			label.scrollFactor.copyFrom(scrollFactor);
			label.cameras = cameras;
			label.draw();
		}

		for (input in inputFields)
		{
			if (input.bg != null)
			{
				input.bg.scrollFactor.copyFrom(scrollFactor);
				input.bg.cameras = cameras;
			}
			if (input.text != null)
			{
				input.text.scrollFactor.copyFrom(scrollFactor);
				input.text.cameras = cameras;
			}
			if (input.placeholderText != null)
			{
				input.placeholderText.scrollFactor.copyFrom(scrollFactor);
				input.placeholderText.cameras = cameras;
			}
			input.draw();
		}
	}

	public function isMouseOver(cam:FlxCamera = null):Bool
	{
		if (cam == null)
			cam = camera;
		if (cam == null)
			cam = FlxG.camera;
		if (cam == null)
			return false;

		readPointer(cam);

		var scaledWidth:Float = width * Math.abs(scale.x);
		var scaledHeight:Float = height * Math.abs(scale.y);
		var left:Float = x + (width - scaledWidth) * 0.5;
		var top:Float = y + (height - scaledHeight) * 0.5;

		return (pointerPoint.x >= left
			&& pointerPoint.x <= left + scaledWidth
			&& pointerPoint.y >= top
			&& pointerPoint.y <= top + scaledHeight);
	}

	/** Touch first, mouse second; writes the world position into `pointerPoint`. */
	function readPointer(cam:FlxCamera):Void
	{
		#if mobile
		for (touch in FlxG.touches.list)
		{
			if (touch == null || !touch.pressed)
				continue;

			touch.getWorldPosition(cam, pointerPoint);
			return;
		}
		#end

		FlxG.mouse.getWorldPosition(cam, pointerPoint);
	}

	/**
	 * Screen position of the block's top left corner.
	 *
	 * Declared with the base signature so it stays a valid override; call it as
	 * `getScreenPosition(cam)` — Haxe skips the optional `result` argument.
	 */
	override public function getScreenPosition(?result:FlxPoint = null, ?camera:FlxCamera = null):FlxPoint
	{
		if (camera == null)
			camera = this.camera;
		if (camera == null)
			camera = FlxG.camera;

		if (result == null)
			result = FlxPoint.get();

		result.set(x, y);
		if (camera != null)
			result.subtract(camera.scroll.x * scrollFactor.x, camera.scroll.y * scrollFactor.y);

		return result;
	}

	/**
	 * World position of the joint this block offers to the next one in the stack: the centre of the
	 * bottom groove, so a dragged block can be pulled onto it and an insertion mark can be drawn
	 * there. Reporters have no groove and report their bottom left corner instead.
	 *
	 * The caller owns the returned point and has to `put()` it back.
	 */
	public function connectionPoint():FlxPoint
	{
		var point:FlxPoint = FlxPoint.get();
		var socketMiddle:Float = isReporter ? 0 : studX + studWidth * 0.5;

		point.set(x + socketMiddle * scale.x, y + height * scale.y);

		return point;
	}

	/**
	 * Rect of the inline input box at `index`, in the same world coordinates the substate already
	 * uses to hit-test inputs (`InputField.bg` and its `width`/`height`), so a drop preview lines up
	 * with what a tap would select. Returns an empty rect when there is no such input.
	 */
	public function inputSlot(index:Int):
		{
			x:Float,
			y:Float,
			w:Float,
			h:Float
		}
	{
		if (index < 0 || index >= inputFields.length || index >= inputOffsetX.length)
			return {
				x: x,
				y: y,
				w: 0,
				h: 0
			};

		var input = inputFields[index];

		return {
			x: x + inputOffsetX[index],
			y: y + inputOffsetY[index],
			w: input.width,
			h: input.height
		};
	}

	override public function destroy():Void
	{
		if (shadow != null)
		{
			FlxDestroyUtil.destroy(shadow);
			shadow = null;
		}

		super.destroy();
	}
}

/**
 * Raster helpers shared by the block body, its shadow and its inline input boxes.
 *
 * Everything is painted straight into a `BitmapData` instead of going through a `Graphics`
 * rasteriser, so the result is identical on Windows, Android and HTML5 and stays pixel-crisp no
 * matter how much the editor camera is zoomed in. Corners are antialiased by blending the boundary
 * pixels of a row (the destination there is always the transparent area just outside the shape, so
 * a plain source-over blend is exact), and `strength` below 1 gives the soft glow of the snap hint.
 */
class BlockPaint
{
	/** Filled rounded rectangle with one radius for every corner. */
	public static function fillRoundRect(pixels:BitmapData, x:Float, y:Float, w:Float, h:Float, radius:Float, color:Int, antialias:Bool = false,
			strength:Float = 1):Void
	{
		fillRoundRectComplex(pixels, x, y, w, h, radius, radius, radius, radius, color, antialias, strength);
	}

	/** Filled rounded rectangle with a radius per corner, so hat blocks get their curved top. */
	public static function fillRoundRectComplex(pixels:BitmapData, x:Float, y:Float, w:Float, h:Float, topLeft:Float, topRight:Float, bottomRight:Float,
			bottomLeft:Float, color:Int, antialias:Bool = false, strength:Float = 1):Void
	{
		paintShape(pixels, x, y, w, h, topLeft, topRight, bottomRight, bottomLeft, color, antialias, strength, 0);
	}

	/** The rim of a rounded rectangle, `thickness` pixels wide, painted along the same profile. */
	public static function strokeRoundRectComplex(pixels:BitmapData, x:Float, y:Float, w:Float, h:Float, topLeft:Float, topRight:Float, bottomRight:Float,
			bottomLeft:Float, thickness:Float, color:Int, strength:Float = 1):Void
	{
		paintShape(pixels, x, y, w, h, topLeft, topRight, bottomRight, bottomLeft, color, true, strength, Math.max(1, thickness));
	}

	static function paintShape(pixels:BitmapData, x:Float, y:Float, w:Float, h:Float, topLeft:Float, topRight:Float, bottomRight:Float, bottomLeft:Float,
			color:Int, antialias:Bool, strength:Float, rim:Float):Void
	{
		if (pixels == null || w <= 0 || h <= 0 || strength <= 0)
			return;

		var limit:Float = Math.min(w, h) * 0.5;
		var tl:Float = FlxMath.bound(topLeft, 0, limit);
		var tr:Float = FlxMath.bound(topRight, 0, limit);
		var br:Float = FlxMath.bound(bottomRight, 0, limit);
		var bl:Float = FlxMath.bound(bottomLeft, 0, limit);
		var band:Float = (rim > 0) ? Math.min(rim, limit) : 0;
		var firstRow:Int = Std.int(Math.floor(y));
		var lastRow:Int = Std.int(Math.ceil(y + h));

		for (row in firstRow...lastRow)
		{
			var local:Float = (row + 0.5) - y;
			var left:Float = x;
			var right:Float = x + w;

			if (tl > 0 && local < tl)
			{
				var dy:Float = tl - local;
				left += tl - Math.sqrt(tl * tl - dy * dy);
			}
			else if (bl > 0 && local > h - bl)
			{
				var dy:Float = local - (h - bl);
				left += bl - Math.sqrt(bl * bl - dy * dy);
			}

			if (tr > 0 && local < tr)
			{
				var dy:Float = tr - local;
				right -= tr - Math.sqrt(tr * tr - dy * dy);
			}
			else if (br > 0 && local > h - br)
			{
				var dy:Float = local - (h - br);
				right -= br - Math.sqrt(br * br - dy * dy);
			}

			if (band <= 0 || local < band || local > h - band)
			{
				paintSpan(pixels, left, right, row, color, antialias, strength);
				continue;
			}

			paintSpan(pixels, left, left + band, row, color, antialias, strength);
			paintSpan(pixels, right - band, right, row, color, antialias, strength);
		}
	}

	/** Dashed rectangle: the "a value block can be dropped here" socket of an empty input. */
	public static function dashedRoundRect(pixels:BitmapData, x:Float, y:Float, w:Float, h:Float, radius:Float, color:Int):Void
	{
		if (pixels == null || w <= 1 || h <= 1)
			return;

		var inset:Float = FlxMath.bound(radius, 1, Math.min(w, h) * 0.5 - 1);
		var dash:Float = Math.max(3, Math.round(inset));
		var gap:Float = Math.max(3, Math.round(inset));
		var cursor:Float = x + inset;
		var limit:Float = x + w - inset;

		while (cursor < limit)
		{
			var end:Float = Math.min(cursor + dash, limit);
			pixels.fillRect(new Rectangle(Math.round(cursor), Math.round(y), Math.round(end - cursor), 1), color);
			pixels.fillRect(new Rectangle(Math.round(cursor), Math.round(y + h - 1), Math.round(end - cursor), 1), color);
			cursor = end + gap;
		}

		cursor = y + inset;
		limit = y + h - inset;

		while (cursor < limit)
		{
			var end:Float = Math.min(cursor + dash, limit);
			pixels.fillRect(new Rectangle(Math.round(x), Math.round(cursor), 1, Math.round(end - cursor)), color);
			pixels.fillRect(new Rectangle(Math.round(x + w - 1), Math.round(cursor), 1, Math.round(end - cursor)), color);
			cursor = end + gap;
		}
	}

	static function paintSpan(pixels:BitmapData, left:Float, right:Float, row:Int, color:Int, antialias:Bool, strength:Float):Void
	{
		if (right <= left || row < 0 || row >= pixels.height)
			return;

		if (strength >= 1 && !antialias)
		{
			var from:Int = Math.round(left);
			var to:Int = Math.round(right);

			if (to <= from)
				to = from + 1;
			if (from < 0)
				from = 0;
			if (to > pixels.width)
				to = pixels.width;
			if (to > from)
				pixels.fillRect(new Rectangle(from, row, to - from, 1), color);
			return;
		}

		var first:Int = Std.int(Math.floor(left));
		var last:Int = Std.int(Math.floor(right));

		if (first == last)
		{
			blendPixel(pixels, first, row, color, FlxMath.bound((right - left) * strength, 0, 1));
			return;
		}

		var fullFrom:Int = Std.int(Math.ceil(left));
		var fullTo:Int = Std.int(Math.floor(right));

		// The covered interior is bulk-filled; only the two boundary pixels of each row blend, so
		// antialiasing costs two pixels per row instead of a per-pixel loop.
		if (fullTo > fullFrom)
		{
			if (strength >= 1)
			{
				var from:Int = (fullFrom < 0) ? 0 : fullFrom;
				var to:Int = (fullTo > pixels.width) ? pixels.width : fullTo;
				if (to > from)
					pixels.fillRect(new Rectangle(from, row, to - from, 1), color);
			}
			else
			{
				for (px in fullFrom...fullTo)
					blendPixel(pixels, px, row, color, strength);
			}
		}

		blendPixel(pixels, first, row, color, FlxMath.bound((fullFrom - left) * strength, 0, 1));
		blendPixel(pixels, fullTo, row, color, FlxMath.bound((right - fullTo) * strength, 0, 1));
	}

	/** Source-over blend of one pixel; `coverage` is the share of it the shape covers. */
	public static function blendPixel(pixels:BitmapData, x:Int, y:Int, color:Int, coverage:Float):Void
	{
		if (pixels == null || coverage <= 0.002)
			return;
		if (x < 0 || y < 0 || x >= pixels.width || y >= pixels.height)
			return;

		if (coverage >= 0.998)
		{
			pixels.setPixel32(x, y, color);
			return;
		}

		var sourceAlpha:Float = ((color >>> 24) & 0xFF) / 255 * coverage;
		var destination:Int = pixels.getPixel32(x, y);
		var destinationAlpha:Float = ((destination >>> 24) & 0xFF) / 255;
		var outAlpha:Float = sourceAlpha + destinationAlpha * (1 - sourceAlpha);

		if (outAlpha <= 0)
		{
			pixels.setPixel32(x, y, 0);
			return;
		}

		var red:Float = channel(color, 16) * sourceAlpha + channel(destination, 16) * destinationAlpha * (1 - sourceAlpha);
		var green:Float = channel(color, 8) * sourceAlpha + channel(destination, 8) * destinationAlpha * (1 - sourceAlpha);
		var blue:Float = channel(color, 0) * sourceAlpha + channel(destination, 0) * destinationAlpha * (1 - sourceAlpha);

		pixels.setPixel32(x, y,
			(Std.int(FlxMath.bound(outAlpha * 255, 0,
				255)) << 24) | (Std.int(FlxMath.bound(red / outAlpha, 0,
					255)) << 16) | (Std.int(FlxMath.bound(green / outAlpha, 0, 255)) << 8) | Std.int(FlxMath.bound(blue / outAlpha, 0, 255)));
	}

	static inline function channel(color:Int, shift:Int):Float
	{
		return ((color >> shift) & 0xFF);
	}
}

/**
 * One inline parameter widget of a `Block`.
 *
 * Values are edited either from the substate (soft keyboard: `appendText`,
 * `backspace`, `setValue`) or, on desktop, from the keyboard through
 * `update()`. SELECT cycles its options and BOOL toggles on tap.
 *
 * The box itself is a rounded, subtly bevelled widget that gets a blinking focus ring while it is
 * being edited — and, while it is empty, a dashed inset socket that tells a beginner a value block
 * can be dropped there.
 */
class InputField
{
	// Same colours as the legacy editor state's COLOR_INPUT_* constants.
	public static inline var COLOR_INPUT_BG:Int = 0xFF0F0F14;
	public static inline var COLOR_INPUT_BORDER:Int = 0xFF414868;
	public static inline var COLOR_INPUT_TEXT:Int = 0xFFC0CAF5;
	public static inline var COLOR_INPUT_PLACEHOLDER:Int = 0xFF565F89;
	public static inline var COLOR_INPUT_FOCUS:Int = 0xFFE0AF68;
	public static inline var COLOR_INPUT_SLOT:Int = 0xFF565F89;

	static inline var BLINK_RATE:Float = 1.0;
	static inline var FOCUS_ALPHA:Float = 0.6;
	static inline var MIN_BOX_WIDTH:Float = 16;

	public var bg:FlxSprite;
	public var text:FlxText;
	public var placeholderText:FlxText;
	public var width(default, set):Float;
	public var height:Float;

	/** Current parameter value; assigning it refreshes the inline display and the block size. */
	public var value(default, set):Dynamic;

	public var type:ParamType;
	public var isFocused:Bool = false;
	public var parentBlock:Block = null;
	public var attachedBlock:Block = null;
	public var placeholder(default, set):String = "";

	var paramName:String = "";
	var baseHeight:Float = 0;
	var multiline:Bool = false;
	var bgWidth:Int = 0;
	var bgHeight:Int = 0;
	var bgPaintedEmpty:Bool = false;
	var cursorTimer:Float = 0;
	var fontRoleSize:Int = 0;
	var textPaddingX:Float = 6;
	var textPaddingY:Float = 5;
	var boxRadius:Float = 4;
	var pointerPoint:FlxPoint = new FlxPoint(0, 0);

	public function new(x:Float, y:Float, w:Float, h:Float, defaultVal:Dynamic, type:ParamType, name:String = "")
	{
		this.type = type;
		this.value = defaultVal;
		this.placeholder = name;
		this.paramName = name;
		this.baseHeight = h;
		this.width = w;
		this.height = h;

		updateMetrics();

		bg = new FlxSprite(x, y);
		text = new FlxText(x, y, 0, "", fontRoleSize);
		placeholderText = new FlxText(x, y, 0, placeholder, fontRoleSize);

		refreshDisplay();
		updatePosition(x, y);
	}

	function set_width(value:Float):Float
	{
		if (width == value)
			return value;

		width = value;
		refreshDisplay();
		return value;
	}

	function set_value(v:Dynamic):Dynamic
	{
		value = v;
		refreshDisplay();

		if (parentBlock != null)
			parentBlock.recalculateSize();

		return v;
	}

	function set_placeholder(value:String):String
	{
		if (placeholder == value)
			return value;

		placeholder = value;
		if (placeholderText != null)
			placeholderText.text = value;
		return value;
	}

	/** Row height this box was laid out for; `Block` lowers it for the inputs of a reporter. */
	public function setBaseHeight(value:Float):Void
	{
		if (baseHeight == value)
			return;

		baseHeight = value;
		refreshDisplay();
	}

	/** Pulls the responsive type sizes and paddings out of `BlockLayout`. */
	function updateMetrics():Void
	{
		BlockLayout.ensure();

		fontRoleSize = BlockLayout.font('small');
		textPaddingX = Math.max(6, Math.round(6 * BlockLayout.scale));
		textPaddingY = Math.max(4, Math.round(5 * BlockLayout.scale));
		boxRadius = Math.max(3, Math.round(4 * BlockLayout.scale));
	}

	public function updatePosition(x:Float, y:Float):Void
	{
		if (bg == null)
			return;

		bg.x = x;
		bg.y = y;

		if (text != null)
		{
			text.x = x + textPaddingX;
			text.y = y + Math.round((height - text.height) * 0.5);
		}

		if (placeholderText != null)
		{
			placeholderText.x = x + textPaddingX;
			placeholderText.y = y + Math.round((height - placeholderText.height) * 0.5);
		}
	}

	public function update(elapsed:Float):Void
	{
		if (bg == null || text == null || placeholderText == null)
			return;

		var previousFontSize:Int = fontRoleSize;
		updateMetrics();

		if (fontRoleSize != previousFontSize)
		{
			refreshDisplay();
			if (parentBlock != null)
				parentBlock.recalculateSize();
		}

		// An attached reporter draws itself where the field would be
		if (attachedBlock != null)
		{
			bg.visible = false;
			text.visible = false;
			placeholderText.visible = false;
			return;
		}

		bg.visible = true;
		text.visible = true;

		// Another module may have written value/text directly (deserialisation)
		if (text.text != displayText())
		{
			refreshDisplay();
			if (parentBlock != null)
				parentBlock.recalculateSize();
		}
		else if (bgPaintedEmpty != isEmptySlot())
		{
			paintBackground();
		}

		if (pointerJustPressed())
		{
			if (pointerOver())
				onTapped();
			#if !mobile
			else if (isFocused)
				unfocus(); // on mobile the substate owns focus, taps land on its keyboard too
			#end
		}

		if (isFocused)
		{
			#if !mobile
			handleKeyInput();
			#end
			cursorTimer += elapsed;
			bg.alpha = (cursorTimer % BLINK_RATE < BLINK_RATE * 0.5) ? 1.0 : FOCUS_ALPHA;
		}
		else
		{
			cursorTimer = 0;
			bg.alpha = 1.0;
		}

		placeholderText.visible = (text.text == "" && !isFocused);
	}

	public function draw():Void
	{
		if (bg == null || !bg.visible)
			return;

		bg.draw();

		if (placeholderText != null && placeholderText.visible)
			placeholderText.draw();
		else if (text != null && text.visible)
			text.draw();
	}

	/** Focuses the field; `pushKeyboard` also asks the substate to open its editor. */
	public function focus(pushKeyboard:Bool = true):Void
	{
		if (parentBlock != null)
		{
			for (other in parentBlock.inputFields)
			{
				if (other != this && other.isFocused)
					other.unfocus();
			}
		}

		isFocused = true;
		cursorTimer = 0;
		paintBackground();

		if (bg != null)
			bg.alpha = 1.0;

		if (pushKeyboard)
			requestEditor();
	}

	public function unfocus():Void
	{
		if (isFocused)
			commit();

		isFocused = false;
		cursorTimer = 0;
		paintBackground();

		if (bg != null)
			bg.alpha = 1.0;
	}

	/** Applies the current text as the value and notifies the owner when it changed. */
	public function commit():Void
	{
		if (text == null)
			return;

		var parsed:Dynamic = parseValue();
		var changed:Bool = !sameValue(parsed, value);

		value = parsed;

		if (changed)
			notifyValueChanged();
	}

	public function setValue(v:Dynamic):Void
	{
		value = v;
		notifyValueChanged();
	}

	/** Appends typed or soft-keyboard text, filtered for the parameter type. */
	public function appendText(s:String):Void
	{
		if (s == null || s.length == 0 || text == null)
			return;

		var addition:String = isCode() ? cleanCodeText(s) : sanitize(s);
		if (addition.length == 0)
			return;

		text.text += addition;
		commit();
	}

	public function backspace():Void
	{
		if (text == null || text.text.length == 0)
			return;

		text.text = text.text.substr(0, text.text.length - 1);
		commit();
	}

	public function isCode():Bool
	{
		return type == ParamType.CODE;
	}

	/** True while the field shows nothing at all: the state that draws the dashed socket. */
	public function isEmptySlot():Bool
	{
		return attachedBlock == null && (text == null || text.text.length == 0);
	}

	function onTapped():Void
	{
		if (type == ParamType.BOOL)
		{
			setValue(!boolValue());
			return;
		}

		if (type == ParamType.SELECT)
		{
			cycleOption();
			return;
		}

		focus(true);
	}

	function cycleOption():Void
	{
		var options = parameterOptions();
		if (options == null || options.length == 0)
			return;

		var index:Int = options.indexOf(Std.string(value));
		index = (index + 1) % options.length;
		setValue(options[index]);
	}

	function parameterOptions():Array<String>
	{
		if (parentBlock == null || parentBlock.blockData == null || parentBlock.blockData.parameters == null)
			return null;

		for (param in parentBlock.blockData.parameters)
		{
			if (param.name == paramName && param.options != null)
				return param.options;
		}

		return null;
	}

	function boolValue():Bool
	{
		if (Std.isOfType(value, Bool))
			return (value : Bool);

		var asText:String = Std.string(value).toLowerCase();
		return (asText == "true" || asText == "1" || asText == "yes");
	}

	function requestEditor():Void
	{
		if (isCode())
		{
			if (Block.requestCodeEdit != null)
				Block.requestCodeEdit(this);
			return;
		}

		if (type == ParamType.BOOL || type == ParamType.SELECT)
			return;

		if (Block.requestTextEdit != null)
			Block.requestTextEdit(this);
	}

	function notifyValueChanged():Void
	{
		if (parentBlock != null)
			parentBlock.recalculateSize();

		if (Block.onAnyValueChanged != null)
			Block.onAnyValueChanged();
	}

	function sameValue(a:Dynamic, b:Dynamic):Bool
	{
		return Std.string(a) == Std.string(b);
	}

	function displayText():String
	{
		return (value == null) ? "" : Std.string(value);
	}

	/** NUMBER becomes a Float, BOOL a Bool, everything else stays text. */
	function parseValue():Dynamic
	{
		if (type == ParamType.BOOL)
			return boolValue();

		if (type == ParamType.NUMBER)
		{
			var parsed = Std.parseFloat(text.text);
			if (text.text.length > 0 && !Math.isNaN(parsed))
				return parsed;
			return text.text;
		}

		return text.text;
	}

	function cleanCodeText(s:String):String
	{
		return s.split("\r").join("");
	}

	function sanitize(s:String):String
	{
		var numeric:Bool = (type == ParamType.NUMBER);
		var hasDot:Bool = (text.text.indexOf(".") != -1);
		var out:String = "";

		for (i in 0...s.length)
		{
			var c:String = s.charAt(i);
			if (c == "\n" || c == "\r")
				continue;

			if (!numeric)
			{
				out += c;
				continue;
			}

			var code:Int = s.charCodeAt(i);
			if (code >= "0".charCodeAt(0) && code <= "9".charCodeAt(0))
			{
				out += c;
			}
			else if (c == "." && !hasDot)
			{
				hasDot = true;
				out += c;
			}
			else if (c == "-" && text.text.length == 0 && out.length == 0)
			{
				out += c;
			}
		}

		return out;
	}

	/** Re-applies the responsive font, the wrapped display and the box size. */
	function refreshDisplay():Void
	{
		if (bg == null || text == null || placeholderText == null)
			return;

		var asText:String = displayText();
		multiline = isCode() && asText.indexOf("\n") >= 0;

		if (text.text != asText)
			text.text = asText;

		var innerWidth:Float = Math.max(width - textPaddingX * 2, MIN_BOX_WIDTH);

		text.setFormat(Paths.font("vcr.ttf"), fontRoleSize, COLOR_INPUT_TEXT, multiline ? FlxTextAlign.LEFT : FlxTextAlign.CENTER);
		text.fieldWidth = innerWidth;

		placeholderText.setFormat(Paths.font("vcr.ttf"), fontRoleSize, COLOR_INPUT_PLACEHOLDER, FlxTextAlign.CENTER);
		placeholderText.fieldWidth = innerWidth;

		// Only genuinely multi-line or wrapped content makes the box taller; a one-line value keeps
		// the row height its author asked for (that is what `BlockSavePanel` relies on).
		var wrapped:Bool = asText.length > 0 && (multiline || text.height > fontRoleSize * 1.7);
		height = Math.max(baseHeight, wrapped ? text.height + textPaddingY * 2 : baseHeight);

		updatePosition(bg.x, bg.y);
		paintBackground();
	}

	/** Repaints the rounded box, its border/focus ring and the dashed empty-slot socket. */
	function paintBackground():Void
	{
		if (bg == null)
			return;

		var w:Int = Std.int(Math.max(1, Math.round(width)));
		var h:Int = Std.int(Math.max(1, Math.round(height)));

		if (w != bgWidth || h != bgHeight)
		{
			bgWidth = w;
			bgHeight = h;
			// Unique: `FlxG.bitmap` would otherwise share one graphic between all equally sized boxes.
			bg.makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		}
		else
		{
			var current:BitmapData = bg.pixels;
			if (current != null)
				current.fillRect(new Rectangle(0, 0, w, h), FlxColor.TRANSPARENT);
		}

		var pixels:BitmapData = bg.pixels;
		if (pixels == null)
			return;

		bgPaintedEmpty = isEmptySlot();

		var radius:Float = FlxMath.bound(boxRadius, 1, h * 0.5 - 1);
		var borderColour:Int = isFocused ? COLOR_INPUT_FOCUS : COLOR_INPUT_BORDER;

		pixels.lock();
		BlockPaint.fillRoundRect(pixels, 0, 0, w, h, radius, borderColour, true);
		BlockPaint.fillRoundRect(pixels, 1, 1, w - 2, h - 2, Math.max(1, radius - 1), COLOR_INPUT_BG);

		// A second 1px ring makes the focus read as a 2px glow around the box.
		if (isFocused)
			BlockPaint.strokeRoundRectComplex(pixels, 1, 1, w - 2, h - 2, radius - 1, radius - 1, radius - 1, radius - 1, 1, COLOR_INPUT_FOCUS);

		// Empty slot: dashed inset so a beginner sees where a value block can be dropped.
		if (bgPaintedEmpty && !isFocused && w > 24 && h > 14)
			BlockPaint.dashedRoundRect(pixels, 3, 3, w - 6, h - 6, radius, COLOR_INPUT_SLOT);

		pixels.unlock();
	}

	function pointerJustPressed():Bool
	{
		if (FlxG.mouse.justPressed)
			return true;

		#if mobile
		var touch:FlxTouch = primaryTouch();
		if (touch != null && touch.justPressed)
			return true;
		#end

		return false;
	}

	function pointerOver():Bool
	{
		var cam:FlxCamera = fieldCamera();
		if (cam == null)
			return false;

		updatePointer(cam);
		return (pointerPoint.x >= bg.x && pointerPoint.x <= bg.x + width && pointerPoint.y >= bg.y && pointerPoint.y <= bg.y + height);
	}

	function updatePointer(cam:FlxCamera):Void
	{
		#if mobile
		var touch:FlxTouch = primaryTouch();
		if (touch != null)
		{
			touch.getWorldPosition(cam, pointerPoint);
			return;
		}
		#end

		FlxG.mouse.getWorldPosition(cam, pointerPoint);
	}

	function fieldCamera():FlxCamera
	{
		if (bg.cameras != null && bg.cameras.length > 0)
			return bg.cameras[0];
		if (bg.camera != null)
			return bg.camera;
		return FlxG.camera;
	}

	#if mobile
	function primaryTouch():FlxTouch
	{
		for (touch in FlxG.touches.list)
		{
			if (touch != null && touch.pressed)
				return touch;
		}
		return null;
	}
	#end

	#if !mobile
	function handleKeyInput():Void
	{
		if (Block.externalEditorActive)
			return;

		var key:FlxKey = FlxG.keys.firstJustPressed();
		if (key == -1)
			return;

		var keyName:Null<String> = FlxKey.toStringMap.get(key);

		if (key == FlxKey.BACKSPACE)
		{
			backspace();
			return;
		}

		if (key == FlxKey.ENTER)
		{
			if (isCode())
				appendText("\n");
			else
				unfocus();
			return;
		}

		if (key == FlxKey.ESCAPE)
		{
			unfocus();
			return;
		}

		if (keyName == null)
			return;

		if (type == ParamType.NUMBER)
		{
			if ((key : Int) >= (FlxKey.ZERO : Int) && (key : Int) <= (FlxKey.NINE : Int))
			{
				appendText(Std.string((key : Int) - (FlxKey.ZERO : Int)));
			}
			else if ((key : Int) >= (FlxKey.NUMPADZERO : Int) && (key : Int) <= (FlxKey.NUMPADNINE : Int))
			{
				appendText(Std.string((key : Int) - (FlxKey.NUMPADZERO : Int)));
			}
			else if (key == FlxKey.PERIOD || key == FlxKey.NUMPADPERIOD)
			{
				if (text.text.indexOf(".") == -1)
					appendText(".");
			}
			else if (key == FlxKey.MINUS || key == FlxKey.NUMPADMINUS)
			{
				if (text.text.length == 0)
					appendText("-");
			}
			return;
		}

		var typed:String = keyName;
		if (typed.length == 1)
		{
			if (!FlxG.keys.pressed.SHIFT)
				typed = typed.toLowerCase();
			appendText(typed);
		}
		else if (key == FlxKey.SPACE)
			appendText(" ");
		else if (key == FlxKey.MINUS)
			appendText("-");
		else if (key == FlxKey.PLUS)
			appendText("+");
		else if (key == FlxKey.LBRACKET)
			appendText("[");
		else if (key == FlxKey.RBRACKET)
			appendText("]");
		else if (key == FlxKey.SEMICOLON)
			appendText(";");
		else if (key == FlxKey.QUOTE)
			appendText("'");
		else if (key == FlxKey.COMMA)
			appendText(",");
		else if (key == FlxKey.PERIOD)
			appendText(".");
		else if (key == FlxKey.SLASH)
			appendText("/");
		else if (key == FlxKey.BACKSLASH)
			appendText("\\");
	}
	#end
}
