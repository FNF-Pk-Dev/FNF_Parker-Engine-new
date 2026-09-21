package editors.blockcode;

import editors.blockcode.BlockTypes.BlockData;
import editors.blockcode.BlockTypes.ParamType;
import flixel.input.keyboard.FlxKey;
import flixel.input.touch.FlxTouch;
import openfl.geom.Rectangle;

/**
 * The draggable block sprite of the block-code editor together with its inline
 * `InputField`s.
 *
 * Layout, colours and the pill/bevel graphics mirror the legacy
 * `editors.BlockCodeEditorState` implementation, but every visual is driven by
 * the `BlockData` it is handed, so blocks coming from an external JSON/Lua
 * config render through the same code path as the built-in library.
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

	// Geometry, matching the legacy block/input metrics.
	static inline var MIN_WIDTH:Float = 150;
	static inline var MIN_HEIGHT:Float = 50;
	static inline var MIN_REPORTER_HEIGHT:Float = 40;
	static inline var LABEL_OFFSET_X:Float = 50;
	static inline var LABEL_OFFSET_Y:Float = 15;
	static inline var LABEL_OFFSET_Y_REPORTER:Float = 10;
	static inline var ICON_OFFSET_X:Float = 15;
	static inline var ICON_OFFSET_Y:Float = 12;
	static inline var ICON_OFFSET_Y_REPORTER:Float = 8;
	static inline var CONTENT_START_X:Float = 60;
	static inline var CONTENT_PADDING_RIGHT:Float = 12;
	static inline var INPUT_COLUMN_GAP:Float = 10;
	static inline var INPUT_ROW_GAP:Float = 6;
	static inline var INPUT_HEIGHT:Float = 30;
	static inline var INPUT_WIDTH:Float = 80;
	static inline var CODE_INPUT_WIDTH:Float = 180;
	static inline var COLOR_INPUT_WIDTH:Float = 96;
	static inline var SELECT_INPUT_WIDTH:Float = 110;

	/** Inputs wrap onto another row once a row grows past this width. */
	static inline var CONTENT_ROW_WIDTH:Float = 560;

	static inline var BEVEL_THICKNESS:Float = 4;
	static inline var NOTCH_OFFSET_X:Float = 20;
	static inline var NOTCH_WIDTH:Float = 20;
	static inline var NOTCH_COLOR:Int = 0xFF101014;
	static inline var HOVER_SCALE:Float = 1.05;
	static inline var HOVER_LERP:Float = 8;

	public var blockData:BlockData;
	public var isTemplate:Bool;

	// Visual elements
	public var label:FlxText;
	public var icon:FlxText;
	public var inputFields:Array<InputField> = [];

	// Snapping logic
	public var nextBlock:Block = null;
	public var prevBlock:Block = null;
	public var isSnapped:Bool = false;
	public var isDragging:Bool = false;

	// Reporter logic
	public var isReporter:Bool = false;

	/** Input this reporter is plugged into, when it is not stacked on a block. */
	public var parentInput:InputField = null;

	// Dimensions
	var minWidth:Float = MIN_WIDTH;
	var minHeight:Float = MIN_HEIGHT;

	// Animation
	public var targetScale:Float = 1.0;

	// Input layout, relative to the block origin
	var inputOffsetX:Array<Float> = [];
	var inputOffsetY:Array<Float> = [];
	var recalculating:Bool = false;

	public function new(x:Float, y:Float, data:BlockData, isTemplate:Bool = false)
	{
		super(x, y);

		this.blockData = data;
		this.isTemplate = isTemplate;
		this.isReporter = (data.isReporter == true);

		label = new FlxText(x + LABEL_OFFSET_X, y + LABEL_OFFSET_Y, 0, data.label, 16);
		label.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, 0x33000000);
		label.borderSize = 1.5;

		icon = new FlxText(x + ICON_OFFSET_X, y + ICON_OFFSET_Y, 0, categoryIcon(data.category), 20);
		icon.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, 0x33000000);
		icon.borderSize = 1.5;

		if (data.parameters != null)
		{
			for (param in data.parameters)
			{
				var input = new InputField(0, 0, defaultInputWidth(param.type), INPUT_HEIGHT, param.defaultValue, param.type, param.name);
				input.parentBlock = this;
				inputFields.push(input);
			}
		}

		if (isReporter)
			minHeight = MIN_REPORTER_HEIGHT;

		recalculateSize();

		// Spawn animation
		scale.set(0, 0);
		FlxTween.tween(this.scale, {x: 1, y: 1}, 0.3, {ease: FlxEase.backOut});
		alpha = 0;
		FlxTween.tween(this, {alpha: 1}, 0.2);
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

	static function defaultInputWidth(type:ParamType):Float
	{
		if (type == ParamType.CODE)
			return CODE_INPUT_WIDTH;
		if (type == ParamType.COLOR)
			return COLOR_INPUT_WIDTH;
		if (type == ParamType.SELECT)
			return SELECT_INPUT_WIDTH;
		return INPUT_WIDTH;
	}

	/** Resizes the block to its label plus every input, wrapping them onto extra rows when needed. */
	public function recalculateSize():Void
	{
		if (recalculating)
			return;

		recalculating = true;
		layoutInputs();
		redrawBlock();
		recalculating = false;

		if (parentInput != null && parentInput.parentBlock != null && parentInput.parentBlock != this)
			parentInput.parentBlock.recalculateSize();
	}

	function layoutInputs():Void
	{
		var startX:Float = label.width + CONTENT_START_X;
		var startY:Float = isReporter ? 5 : 10;
		var bottomPadding:Float = isReporter ? 5 : 10;
		var floorWidth:Float = isReporter ? 0 : MIN_WIDTH;
		var floorHeight:Float = isReporter ? MIN_REPORTER_HEIGHT : MIN_HEIGHT;

		inputOffsetX = [];
		inputOffsetY = [];

		var cursorX:Float = startX;
		var rowY:Float = startY;
		var rowHeight:Float = 0;
		var maxRight:Float = startX;
		var placed:Int = 0;

		for (input in inputFields)
		{
			var inputWidth:Float = defaultInputWidth(input.type);
			if (input.attachedBlock != null)
				inputWidth = Math.max(inputWidth, input.attachedBlock.width);

			input.width = inputWidth;

			if (placed > 0 && cursorX + inputWidth + CONTENT_PADDING_RIGHT > CONTENT_ROW_WIDTH)
			{
				rowY += rowHeight + INPUT_ROW_GAP;
				cursorX = startX;
				rowHeight = 0;
			}

			inputOffsetX.push(cursorX);
			inputOffsetY.push(rowY);

			cursorX += inputWidth + INPUT_COLUMN_GAP;
			maxRight = Math.max(maxRight, cursorX - INPUT_COLUMN_GAP);
			rowHeight = Math.max(rowHeight, input.height);
			placed++;
		}

		var contentBottom:Float = (placed > 0) ? rowY + rowHeight + bottomPadding : floorHeight;
		minHeight = Math.max(floorHeight, contentBottom);
		minWidth = Math.max(floorWidth, maxRight + CONTENT_PADDING_RIGHT);

		if (inputFields.length == 0)
			minWidth = Math.max(floorWidth, label.width + 70);
	}

	/** Paints the block body: pill for reporters, bevel + bump/notch for stack blocks. */
	public function redrawBlock():Void
	{
		var w:Int = Std.int(Math.max(minWidth, MIN_WIDTH));
		var h:Int = Std.int(Math.max(minHeight, isReporter ? MIN_REPORTER_HEIGHT : MIN_HEIGHT));

		makeGraphic(w, h, FlxColor.TRANSPARENT);

		var bodyColor:Int = blockData.color;
		if ((bodyColor & 0xFF000000) == 0)
			bodyColor |= 0xFF000000;

		var color:FlxColor = FlxColor.fromInt(bodyColor);
		var darkColor:Int = color.getDarkened(0.4);
		var lightColor:Int = color.getLightened(0.15);

		var pixels = this.pixels;
		pixels.lock();

		if (isReporter)
		{
			pixels.fillRect(new Rectangle(0, 0, w, h), color);
			pixels.fillRect(new Rectangle(2, 0, w - 4, 2), lightColor); // Top
			pixels.fillRect(new Rectangle(2, h - 2, w - 4, 2), darkColor); // Bottom
			pixels.fillRect(new Rectangle(0, 2, 2, h - 4), lightColor); // Left
			pixels.fillRect(new Rectangle(w - 2, 2, 2, h - 4), darkColor); // Right
		}
		else
		{
			pixels.fillRect(new Rectangle(0, 0, w, h), color);

			// 3D bevel
			pixels.fillRect(new Rectangle(0, 0, w, BEVEL_THICKNESS), lightColor); // Top highlight
			pixels.fillRect(new Rectangle(0, h - BEVEL_THICKNESS, w, BEVEL_THICKNESS), darkColor); // Bottom shadow
			pixels.fillRect(new Rectangle(0, 0, BEVEL_THICKNESS, h), lightColor); // Left highlight
			pixels.fillRect(new Rectangle(w - BEVEL_THICKNESS, 0, BEVEL_THICKNESS, h), darkColor); // Right shadow

			// Top bump (light) and bottom notch (socket)
			pixels.fillRect(new Rectangle(NOTCH_OFFSET_X, 0, NOTCH_WIDTH, BEVEL_THICKNESS), color);
			pixels.fillRect(new Rectangle(NOTCH_OFFSET_X, h - BEVEL_THICKNESS, NOTCH_WIDTH, BEVEL_THICKNESS), NOTCH_COLOR);
		}

		pixels.unlock();

		this.width = w;
		this.height = h;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

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
		label.x = x + LABEL_OFFSET_X;
		label.y = y + (isReporter ? LABEL_OFFSET_Y_REPORTER : LABEL_OFFSET_Y);
		icon.x = x + ICON_OFFSET_X;
		icon.y = y + (isReporter ? ICON_OFFSET_Y_REPORTER : ICON_OFFSET_Y);

		// Update inputs
		for (i in 0...inputFields.length)
		{
			var input = inputFields[i];
			if (i < inputOffsetX.length)
				input.updatePosition(x + inputOffsetX[i], y + inputOffsetY[i]);
			input.update(elapsed);
		}

		// Hover animation
		if (!isDragging)
		{
			targetScale = (isMouseOver(camera) && parentInput == null && prevBlock == null) ? HOVER_SCALE : 1.0;
			scale.x = FlxMath.lerp(scale.x, targetScale, elapsed * HOVER_LERP);
			scale.y = FlxMath.lerp(scale.y, targetScale, elapsed * HOVER_LERP);
		}
	}

	override public function draw():Void
	{
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

		var mouse = FlxG.mouse.getWorldPosition(cam);
		return (mouse.x >= x && mouse.x <= x + width && mouse.y >= y && mouse.y <= y + height);
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
}

/**
 * One inline parameter widget of a `Block`.
 *
 * Values are edited either from the substate (soft keyboard: `appendText`,
 * `backspace`, `setValue`) or, on desktop, from the keyboard through
 * `update()`. SELECT cycles its options and BOOL toggles on tap.
 */
class InputField
{
	// Same colours as the legacy editor state's COLOR_INPUT_* constants.
	static inline var COLOR_INPUT_BG:Int = 0xFF0F0F14;
	static inline var COLOR_INPUT_TEXT:Int = 0xFFC0CAF5;
	static inline var COLOR_INPUT_PLACEHOLDER:Int = 0xFF565F89;
	static inline var COLOR_INPUT_FOCUS:Int = 0xFFE0AF68;

	static inline var FONT_SIZE:Int = 14;
	static inline var CODE_FONT_SIZE:Int = 11;
	static inline var TEXT_PADDING_X:Float = 2;
	static inline var TEXT_PADDING_Y:Float = 4;
	static inline var CODE_PADDING_X:Float = 4;
	static inline var CODE_PADDING_Y:Float = 3;
	static inline var BLINK_RATE:Float = 1.0;
	static inline var FOCUS_ALPHA:Float = 0.8;

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
	var cursorTimer:Float = 0;
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

		bg = new FlxSprite(x, y).makeGraphic(Std.int(w), Std.int(h), COLOR_INPUT_BG);
		bgWidth = Std.int(w);
		bgHeight = Std.int(h);

		text = new FlxText(x + TEXT_PADDING_X, y + TEXT_PADDING_Y, Math.max(w - TEXT_PADDING_X * 2, 16), "", FONT_SIZE);
		text.setFormat(Paths.font("vcr.ttf"), FONT_SIZE, COLOR_INPUT_TEXT, CENTER);

		placeholderText = new FlxText(x + TEXT_PADDING_X, y + TEXT_PADDING_Y, Math.max(w - TEXT_PADDING_X * 2, 16), placeholder, FONT_SIZE);
		placeholderText.setFormat(Paths.font("vcr.ttf"), FONT_SIZE, COLOR_INPUT_PLACEHOLDER, CENTER);
		placeholderText.visible = false;

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

	public function updatePosition(x:Float, y:Float):Void
	{
		bg.x = x;
		bg.y = y;

		text.x = x + (multiline ? CODE_PADDING_X : TEXT_PADDING_X);
		text.y = y + (multiline ? CODE_PADDING_Y : TEXT_PADDING_Y);
		placeholderText.x = x + TEXT_PADDING_X;
		placeholderText.y = y + TEXT_PADDING_Y;
	}

	public function update(elapsed:Float):Void
	{
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
		if (!bg.visible)
			return;

		bg.draw();

		if (placeholderText.visible)
			placeholderText.draw();
		else
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
		bg.color = COLOR_INPUT_FOCUS;

		if (pushKeyboard)
			requestEditor();
	}

	public function unfocus():Void
	{
		if (isFocused)
			commit();

		isFocused = false;
		cursorTimer = 0;
		bg.color = COLOR_INPUT_BG;
		bg.alpha = 1.0;
	}

	/** Applies the current text as the value and notifies the owner when it changed. */
	public function commit():Void
	{
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
		if (s == null || s.length == 0)
			return;

		var addition:String = isCode() ? cleanCodeText(s) : sanitize(s);
		if (addition.length == 0)
			return;

		text.text += addition;
		commit();
	}

	public function backspace():Void
	{
		if (text.text.length == 0)
			return;

		text.text = text.text.substr(0, text.text.length - 1);
		commit();
	}

	public function isCode():Bool
	{
		return type == ParamType.CODE;
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

	function refreshDisplay():Void
	{
		if (bg == null || text == null || placeholderText == null)
			return;

		var asText:String = displayText();
		multiline = isCode() && asText.indexOf("\n") >= 0;

		if (text.text != asText)
			text.text = asText;

		if (multiline)
		{
			text.setFormat(Paths.font("vcr.ttf"), CODE_FONT_SIZE, COLOR_INPUT_TEXT, LEFT);
			text.fieldWidth = Math.max(width - CODE_PADDING_X * 2, 32);
			text.x = bg.x + CODE_PADDING_X;
			text.y = bg.y + CODE_PADDING_Y;
		}
		else
		{
			text.setFormat(Paths.font("vcr.ttf"), FONT_SIZE, COLOR_INPUT_TEXT, CENTER);
			text.fieldWidth = Math.max(width - TEXT_PADDING_X * 2, 16);
			text.x = bg.x + TEXT_PADDING_X;
			text.y = bg.y + TEXT_PADDING_Y;
		}

		placeholderText.setFormat(Paths.font("vcr.ttf"), FONT_SIZE, COLOR_INPUT_PLACEHOLDER, CENTER);
		placeholderText.fieldWidth = Math.max(width - TEXT_PADDING_X * 2, 16);
		placeholderText.x = bg.x + TEXT_PADDING_X;
		placeholderText.y = bg.y + TEXT_PADDING_Y;

		height = Math.max(baseHeight, text.height + (multiline ? CODE_PADDING_Y * 2 : TEXT_PADDING_Y));

		var targetWidth:Int = Std.int(Math.max(width, 1));
		var targetHeight:Int = Std.int(Math.max(height, 1));
		if (targetWidth != bgWidth || targetHeight != bgHeight)
		{
			bgWidth = targetWidth;
			bgHeight = targetHeight;
			bg.makeGraphic(targetWidth, targetHeight, COLOR_INPUT_BG);
		}
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
			pointerPoint.set(cam.scroll.x + touch.screenX / cam.zoom, cam.scroll.y + touch.screenY / cam.zoom);
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
			if (touch != null)
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
