package backend;

import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.display.Graphics;
import openfl.geom.Matrix;

class PowerPuffGirl extends FlxSpriteGroup
{
	// Character type constants
	public static inline var BUBBLES:Int = 0;
	public static inline var BLOSSOM:Int = 1;
	public static inline var BUTTERCUP:Int = 2;

	// Colors
	public static var COLOR_BLOSSOM:Int = 0xFFec64ae;
	public static var COLOR_BUBBLES:Int = 0xFF53a7e7;
	public static var COLOR_BUTTERCUP:Int = 0xFF63c253;
	public static var SKIN_COLOR:Int = 0xFFf4cfb4;
	public static var HAIR_BLOSSOM:Int = 0xFFf66718;
	public static var HAIR_BUBBLES:Int = 0xFFfcdb04;
	public static var HAIR_BUTTERCUP:Int = 0xFF000000;
	public static var BLACK:Int = 0xFF000000;
	public static var WHITE:Int = 0xFFFFFFFF;

	// Dimensions (Reference from CSS)
	// Width: 225px
	// Height: width + width * 0.3 = 292.5px
	public static var REF_WIDTH:Float = 225;
	public static var REF_HEIGHT:Float = 292.5;
	
	public var characterType:Int;
	public var trail:PowerPuffTrail;

	public function new(x:Float, y:Float, type:Int, scale:Float = 1.0)
	{
		super(x, y);
		this.characterType = type;

		var mainColor:Int = COLOR_BLOSSOM;
		var hairColor:Int = HAIR_BLOSSOM;
		var typeStr:String = "blossom";

		switch (type)
		{
			case BUBBLES:
				mainColor = COLOR_BUBBLES;
				hairColor = HAIR_BUBBLES;
				typeStr = "bubbles";
			case BUTTERCUP:
				mainColor = COLOR_BUTTERCUP;
				hairColor = HAIR_BUTTERCUP;
				typeStr = "buttercup";
			default: // BLOSSOM
				mainColor = COLOR_BLOSSOM;
				hairColor = HAIR_BLOSSOM;
				typeStr = "blossom";
		}

		// Create trail first (behind everything)
		trail = new PowerPuffTrail(REF_WIDTH * 0.6, REF_HEIGHT * 2, type);
		trail.x = REF_WIDTH * 0.2;
		trail.y = REF_HEIGHT * 0.45;
		add(trail);

		// 1. Back Hair (Ponytails for Bubbles, etc)
		createBackHair(typeStr, hairColor);

		// 2. Legs
		createLegs();

		// 3. Body
		createBody(mainColor);

		// 4. Arms
		createArms(typeStr, SKIN_COLOR);

		// 5. Head Container
		createHead(typeStr, hairColor, SKIN_COLOR, mainColor);
		
		// Apply scale
		this.scale.set(scale, scale);
		
		// Float Animation
		doFloatAnimation();
	}

	public function setBaseY(y:Float):Void
	{
		// Compatibility function - not needed for this version
	}

	function createSpriteFromDrawing(width:Float, height:Float, drawFunction:Graphics->Void):FlxSprite
	{
		var s = new Sprite();
		drawFunction(s.graphics);
		
		var b = new BitmapData(Math.ceil(width), Math.ceil(height), true, 0x00000000);
		b.draw(s);
		
		var spr = new FlxSprite(0, 0);
		spr.loadGraphic(b);
		spr.antialiasing = true;
		return spr;
	}

	function createHead(type:String, hairColor:Int, skinColor:Int, mainColor:Int):Void
	{
		var headSize:Float = REF_WIDTH; // Head is roughly full width
		var headHeight:Float = REF_HEIGHT * 0.65;
		
		// Head Shape (Circleish)
		var head = createSpriteFromDrawing(headSize + 10, headHeight + 10, function(g:Graphics) {
			g.lineStyle(3, BLACK);
			g.beginFill(skinColor);
			g.drawEllipse(3, 3, headSize, headHeight); // Padding for border
			g.endFill();
		});
		head.x = 0;
		head.y = 0;
		add(head);

		// Hair (Front)
		var hair = createFrontHair(type, hairColor, headSize, headHeight * 0.4); // Hair is top 40%
		hair.x = head.x;
		hair.y = head.y; // Relative to head top
		add(hair);

		// Eyes
		createEyes(headSize, headHeight, mainColor);

		// Mouth
		var mouth = createSpriteFromDrawing(30, 20, function(g:Graphics) {
			g.lineStyle(3, BLACK);
			// Semi-circle mouth
			g.moveTo(0, 10);
			g.curveTo(15, 25, 30, 10);
		});
		mouth.x = (headSize - 30) / 2;
		mouth.y = headHeight * 0.8;
		add(mouth);
	}

	function createFrontHair(type:String, color:Int, w:Float, h:Float):FlxSprite
	{
		return createSpriteFromDrawing(w + 10, h + 10, function(g:Graphics) {
			g.beginFill(color);
			
			if (type == "blossom") {
				// Polygon points from CSS
				var pts = [
					{x:0.0, y:1.0}, {x:0.0, y:0.0}, {x:1.0, y:0.0}, {x:1.0, y:1.0},
					{x:0.85, y:1.0}, {x:0.75, y:0.6}, {x:0.75, y:1.0}, {x:0.60, y:1.0},
					{x:0.50, y:0.45}, {x:0.40, y:1.0}, {x:0.25, y:1.0}, {x:0.25, y:0.60},
					{x:0.15, y:1.0}
				];
				drawPolygon(g, w, h * 1.75, pts);
			} else if (type == "buttercup") {
				var pts = [
					{x:0.0, y:0.0}, {x:1.0, y:0.0}, {x:1.0, y:1.0},
					{x:0.53, y:1.0}, {x:0.50, y:0.45}, {x:0.47, y:1.0}, {x:0.0, y:1.0}
				];
				drawPolygon(g, w, h * 1.75, pts);
			} else { // bubbles
				// Two ellipses
				g.drawEllipse(w * 0.15 - (w*0.8)/2, -h*0.5, w*0.8, h*2.5);
				g.drawEllipse(w * 0.85 - (w*0.8)/2, -h*0.5, w*0.8, h*2.5);
			}
			g.endFill();
		});
	}

	function createEyes(headW:Float, headH:Float, mainColor:Int):Void
	{
		var eyeW = headW * 1.2 * 0.45; // Approx individual eye width
		var eyeH = headW * 0.6; // Height
		
		var makeEye = function(isLeft:Bool) {
			var s = createSpriteFromDrawing(eyeW + 6, eyeH + 6, function(g:Graphics) {
				// Sclera
				g.lineStyle(3, BLACK);
				g.beginFill(WHITE);
				g.drawEllipse(3, 3, eyeW, eyeH);
				g.endFill();
				
				// Iris (Powerpuff color)
				var irisW = eyeW * 0.9;
				var irisH = eyeH * 0.85;
				
				g.lineStyle(0, 0, 0);
				g.beginFill(mainColor);
				g.drawEllipse(3 + (eyeW - irisW)/2 - (eyeW*0.15 * (isLeft ? -1 : 1)), 3 + (eyeH - irisH)/2, irisW, irisH);
				g.endFill();
				
				// Pupil
				var pupilW = irisW * 0.87;
				var pupilH = irisH * 0.82;
				g.beginFill(BLACK);
				g.drawEllipse(3 + (eyeW - pupilW)/2 - (eyeW*0.15 * (isLeft ? -1 : 1)), 3 + (eyeH - pupilH)/2, pupilW, pupilH);
				g.endFill();
				
				// Shine
				g.beginFill(WHITE);
				g.drawEllipse(3 + (eyeW - pupilW)/2 + pupilW*0.5, 3 + (eyeH - pupilH)/2, pupilW*0.4, pupilH*0.4);
				g.endFill();
			});
			return s;
		};

		var leftEye = makeEye(true);
		var rightEye = makeEye(false);
		
		leftEye.x = headW * 0.1;
		leftEye.y = headH * 0.2;
		
		rightEye.x = headW * 0.5;
		rightEye.y = headH * 0.2;

		add(leftEye);
		add(rightEye);
	}
	
	function createBody(color:Int):Void
	{
		var bodyW = REF_WIDTH * 0.3;
		var bodyH = REF_HEIGHT * 0.2;
		
		var body = createSpriteFromDrawing(bodyW + 6, bodyH + 6, function(g:Graphics) {
			// clip-path: polygon(8% 0, 92% 0, 100% 100%, 0 100%);
			var pts = [
				{x:0.08, y:0.0}, {x:0.92, y:0.0}, {x:1.0, y:1.0}, {x:0.0, y:1.0}
			];
			
			g.beginFill(color);
			drawPolygon(g, bodyW, bodyH, pts);
			g.endFill();
			
			// Black stripe
			g.beginFill(BLACK);
			g.drawRect(0, bodyH * 0.28, bodyW + 10, bodyH * (0.71 - 0.28));
			g.endFill();
		});
		
		body.x = (REF_WIDTH - bodyW) / 2;
		body.y = REF_HEIGHT * 0.60;
		add(body);
	}
	
	function createLegs():Void
	{
		// Simple white legs w/ black shoes
		var legW = REF_WIDTH * 0.1;
		var legH = REF_HEIGHT * 0.2;
		
		var makeLeg = function() {
			return createSpriteFromDrawing(legW, legH, function(g:Graphics) {
				g.beginFill(WHITE); // Tights
				g.drawRect(0, 0, legW, legH);
				g.endFill();
				g.beginFill(BLACK); // Shoe
				g.drawRoundRect(0, legH*0.7, legW, legH*0.3, 10, 10);
				g.endFill();
			});
		};
		
		var l = makeLeg();
		l.x = REF_WIDTH * 0.38;
		l.y = REF_HEIGHT * 0.75;
		add(l);
		
		var r = makeLeg();
		r.x = REF_WIDTH * 0.52;
		r.y = REF_HEIGHT * 0.75;
		add(r);
	}
	
	function createArms(type:String, skin:Int):Void
	{
		var makeArm = function() {
			return createSpriteFromDrawing(30, 80, function(g:Graphics) {
				g.lineStyle(3, BLACK);
				g.beginFill(skin);
				g.drawRoundRect(0, 0, 25, 70, 20, 20);
				g.endFill();
			});
		};
		
		var leftArm = makeArm();
		leftArm.x = 20;
		leftArm.y = REF_HEIGHT * 0.6;
		leftArm.angle = 15;
		add(leftArm);
		
		var rightArm = makeArm();
		rightArm.x = REF_WIDTH - 50;
		rightArm.y = REF_HEIGHT * 0.6;
		rightArm.angle = -15;
		add(rightArm);
	}
	
	function createBackHair(type:String, color:Int):Void
	{
		if (type == "bubbles") {
			// Pigtails
			var makeTail = function() {
				return createSpriteFromDrawing(60, 60, function(g:Graphics) {
					g.lineStyle(3, BLACK);
					g.beginFill(color);
					g.drawCircle(30,30,25);
					g.endFill();
				});
			};
			var l = makeTail();
			l.x = -20; l.y = 50;
			add(l);
			var r = makeTail();
			r.x = REF_WIDTH - 40; r.y = 50;
			add(r);
		}
		else if (type == "blossom") {
			// Bow
			var makeBow = function() {
				return createSpriteFromDrawing(250, 150, function(g:Graphics) {
					g.lineStyle(3, BLACK);
					g.beginFill(0xFFf13a1b); // Red bow
					g.drawRoundRect(0, 0, 225, 100, 20, 20); 
					g.endFill();
				});
			};
			var bow = makeBow();
			bow.y = -50;
			add(bow);
		}
	}

	function drawPolygon(g:Graphics, w:Float, h:Float, points:Array<{x:Float, y:Float}>):Void
	{
		if (points.length == 0) return;
		g.moveTo(points[0].x * w, points[0].y * h);
		for (i in 1...points.length) {
			g.lineTo(points[i].x * w, points[i].y * h);
		}
		g.lineTo(points[0].x * w, points[0].y * h);
	}
	
	function doFloatAnimation():Void
	{
		FlxTween.tween(this, {y: y - 10}, 1.5, {type: PINGPONG, ease: FlxEase.sineInOut});
	}
}
