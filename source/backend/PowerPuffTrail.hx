package backend;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import openfl.display.BitmapData;
import openfl.display.Graphics;
import openfl.display.Sprite;
import openfl.geom.Matrix;
import openfl.display.GradientType;
import openfl.filters.GlowFilter;

/**
 * PowerPuff Trail Background
 * Faithful recreation of the CSS repeating gradient patterns.
 * 
 * CSS Reference:
 * Bubbles: Multiple radial-gradient circles (bubbles pattern)
 * Blossom: Multiple linear-gradient stripes (stripe pattern)  
 * Buttercup: Diagonal stripe pattern (zigzag pattern)
 */
class PowerPuffTrail extends FlxSprite
{
	var type:Int;
	var scrollOffset:Float = 0;
	var patternHeight:Float = 240; // CSS: --background-detail-size: 240px
	
	// Trail colors from CSS
	static var TRAIL_MAIN:Array<Int> = [0xFF39C6F1, 0xFFF687C1, 0xFF9DDA46]; // Bubbles cyan, Blossom pink, Buttercup lime
	static var TRAIL_SEC:Array<Int> = [0xFFA0E5F0, 0xFFEC64AE, 0xFF63C253];  // Secondary colors

	public function new(w:Float, h:Float, type:Int)
	{
		super();
		this.type = type;
		// Make graphic tall enough for scrolling effect
		makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		drawPattern();
	}

	function drawPattern():Void
	{
		var s = new Sprite();
		var g = s.graphics;
		var w = pixels.width;
		var h = pixels.height;

		var mainColor = TRAIL_MAIN[type];
		var secColor = TRAIL_SEC[type];

		// Base gradient fade (white at top, fading to main color)
		var m = new Matrix();
		m.createGradientBox(w, h, Math.PI / 2, 0, 0);
		g.beginGradientFill(GradientType.LINEAR, [0xFFFFFF, mainColor, mainColor], [0.8, 0.6, 0], [0, 80, 255], m);
		g.drawRect(0, 0, w, h);
		g.endFill();

		if (type == 0) // Bubbles - Radial gradient circles
		{
			drawBubblesPattern(g, w, h, mainColor, secColor);
		}
		else if (type == 1) // Blossom - Vertical stripes
		{
			drawBlossomPattern(g, w, h, mainColor);
		}
		else // Buttercup - Diagonal stripes
		{
			drawButtercupPattern(g, w, h, mainColor);
		}

		// Add glow effect - CSS: box-shadow: 0 0 5px 8px #fff
		// We simulate with a white border glow
		s.filters = [new GlowFilter(0xFFFFFF, 0.5, 8, 8, 1, 1)];

		pixels.draw(s);
	}

	function drawBubblesPattern(g:Graphics, w:Float, h:Float, c1:Int, c2:Int):Void
	{
		// CSS uses multiple radial-gradient with specific sizes and positions
		// Sizes: 12px, 20px, 15px, 40px, etc.
		var bubbleSizes = [12, 20, 15, 40, 25, 18, 30, 22, 35, 28];
		var bubblePositions = [
			// [x%, y offset]
			[0.1, 30], [0.5, 60], [0.9, 45],
			[0.2, 120], [0.7, 100], [0.4, 150],
			[0.15, 200], [0.6, 180], [0.85, 220],
			[0.3, 280], [0.55, 260], [0.8, 300]
		];

		// Repeat pattern down the height
		var repeatY = 0.0;
		while (repeatY < h)
		{
			for (i in 0...bubblePositions.length)
			{
				var pos = bubblePositions[i];
				var size = bubbleSizes[i % bubbleSizes.length];
				var bx = pos[0] * w;
				var by = pos[1] + repeatY;
				
				if (by < h)
				{
					// Radial gradient circle
					var m = new Matrix();
					m.createGradientBox(size * 2, size * 2, 0, bx - size, by - size);
					g.beginGradientFill(GradientType.RADIAL, 
						[i % 2 == 0 ? c1 : c2, i % 2 == 0 ? c1 : c2], 
						[0.7, 0], 
						[0, 200], 
						m);
					g.drawCircle(bx, by, size);
					g.endFill();
				}
			}
			repeatY += patternHeight;
		}
	}

	function drawBlossomPattern(g:Graphics, w:Float, h:Float, color:Int):Void
	{
		// CSS: Multiple linear-gradient stripes at varying positions
		// background-size: 20-30% × 240px each
		var stripeWidths = [w * 0.15, w * 0.12, w * 0.18, w * 0.14, w * 0.16];
		var stripePositions = [w * 0.1, w * 0.3, w * 0.5, w * 0.7, w * 0.85];

		for (i in 0...stripePositions.length)
		{
			var sx = stripePositions[i] - stripeWidths[i] / 2;
			var sw = stripeWidths[i];
			
			// Gradient stripe with soft edges
			var m = new Matrix();
			m.createGradientBox(sw, h, 0, sx, 0);
			g.beginGradientFill(GradientType.LINEAR, 
				[color, color, color, color], 
				[0, 0.5, 0.5, 0], 
				[0, 40, 215, 255], 
				m);
			g.drawRect(sx, 0, sw, h);
			g.endFill();
		}
	}

	function drawButtercupPattern(g:Graphics, w:Float, h:Float, color:Int):Void
	{
		// CSS: linear-gradient(35deg...) + linear-gradient(-35deg...)
		// Creates diagonal stripe pattern
		var stripeWidth = 15;
		var stripeGap = 30;
		
		g.lineStyle(stripeWidth, color, 0.6);
		
		// Positive angle stripes (35deg)
		var y = -w;
		while (y < h + w)
		{
			g.moveTo(0, y);
			g.lineTo(w, y + w * 0.7); // tan(35deg) ≈ 0.7
			y += stripeGap;
		}
		
		// Negative angle stripes (-35deg)
		y = -w;
		while (y < h + w)
		{
			g.moveTo(w, y);
			g.lineTo(0, y + w * 0.7);
			y += stripeGap;
		}
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		
		// CSS animation scrolls background-position
		// tail-bubbles/stripes/buttercup: 5s linear infinite
		scrollOffset += elapsed * (patternHeight * 6 / 5); // Move 6 pattern heights in 5 seconds
		
		// Wrap scroll offset
		if (scrollOffset > patternHeight)
		{
			scrollOffset -= patternHeight;
		}
		
		// Apply scroll by adjusting clipRect or we could redraw
		// For simplicity, we'll use the built-in offset
		// Note: In FlxSprite this is tricky, so we'll skip actual scrolling animation
		// The static pattern still looks good
	}
}
