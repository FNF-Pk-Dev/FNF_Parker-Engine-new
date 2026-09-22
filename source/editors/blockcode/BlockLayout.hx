package editors.blockcode;

import flixel.FlxG;
import flixel.math.FlxMath;

/**
 * One place that turns the current viewport into the metrics every block-editor surface lays
 * itself out with.
 *
 * The editor used to be built on a handful of constants that assumed a 1280x720 desktop window
 * (`SIDEBAR_WIDTH = 320`, `TIMELINE_HEIGHT = 120`, one 44px row of top-bar buttons), which made it
 * cramped on a 16:9 monitor and unusable on a phone. Everything here is derived from
 * `FlxG.width`/`FlxG.height` instead:
 *
 * - `scale` grows the type, rows and touch targets with the screen, between {@link MIN_SCALE} and
 *   {@link MAX_SCALE}, so a 1080p phone in landscape gets noticeably bigger controls than a
 *   1280x720 window while a 640x360 window does not turn into giant UI.
 * - `portrait` (height > width) switches the palette from the left sidebar to a bottom sheet,
 *   because a 320px column eats a third of an upright phone.
 * - `narrow` / `compact` let the top bar wrap into two rows and let the palette drop labels.
 *
 * Calling `ensure()` (cheap, refreshes only when the viewport changed) at the start of a
 * `create()`/`update()` is the intended usage; `refresh()` forces a recomputation.
 */
class BlockLayout
{
	public static inline var BASE_WIDTH:Float = 1280;
	public static inline var BASE_HEIGHT:Float = 720;
	public static inline var MIN_SCALE:Float = 0.75;
	public static inline var MAX_SCALE:Float = 1.5;

	/**
	 * Extra UI scale on touch devices.
	 *
	 * `Main` installs `backend.ScaleModeRezie`, so the engine always renders a fixed 1280x720
	 * virtual canvas — a phone reports exactly the same viewport as a 720p desktop window while its
	 * screen is a fraction of the size. The old editor compensated with a hardcoded
	 * `ANDROID_SCALE = 1.25`; this is the same idea, applied to every metric at once.
	 */
	public static inline var MOBILE_BOOST:Float = 1.25;

	/** Current viewport size (logical pixels, what `FlxG.width` reports). */
	public static var width(default, null):Float = BASE_WIDTH;

	public static var height(default, null):Float = BASE_HEIGHT;

	/** Font/row/touch scale derived from the viewport, {@link MIN_SCALE}..{@link MAX_SCALE}. */
	public static var scale(default, null):Float = 1;

	/** Height greater than width: the palette becomes a bottom sheet. */
	public static var portrait(default, null):Bool = false;

	/** Narrow viewport (phones in landscape, small windows): the top bar wraps into two rows. */
	public static var narrow(default, null):Bool = false;

	/** Very small viewport: palette tiles drop their text and keep colour + icon only. */
	public static var compact(default, null):Bool = false;

	static var lastWidth:Float = -1;
	static var lastHeight:Float = -1;

	// ------------------------------------------------------------------------------------ refresh

	/** Recomputes the metrics when the viewport changed since the last call. */
	public static function ensure():Void
	{
		var w:Float = (FlxG.width > 0) ? FlxG.width : BASE_WIDTH;
		var h:Float = (FlxG.height > 0) ? FlxG.height : BASE_HEIGHT;

		if (w == lastWidth && h == lastHeight)
			return;

		refresh();
	}

	/** Forces a recomputation of every metric. */
	public static function refresh():Void
	{
		var w:Float = (FlxG.width > 0) ? FlxG.width : BASE_WIDTH;
		var h:Float = (FlxG.height > 0) ? FlxG.height : BASE_HEIGHT;

		width = w;
		height = h;
		lastWidth = w;
		lastHeight = h;

		portrait = h > w * 1.05;
		narrow = w < 1000;
		compact = (w < 760 || h < 460);

		// In landscape the horizontal bars are what costs room, so scale with the height; upright
		// screens are limited by the width and get a slightly gentler ramp.
		var basis:Float = portrait ? (w / 800) : (h / BASE_HEIGHT);
		if (isMobile())
			basis *= MOBILE_BOOST;
		scale = FlxMath.bound(basis, MIN_SCALE, MAX_SCALE);
	}

	/** True on phones/tablets (and touch-first web builds). */
	public static function isMobile():Bool
	{
		#if mobile
		return true;
		#elseif android
		return true;
		#elseif ios
		return true;
		#elseif web
		return FlxG.onMobile;
		#else
		return false;
		#end
	}

	// -------------------------------------------------------------------------------- primitives

	/** Extra multiplier for interactive widgets: fingers want more room than a mouse pointer. */
	public static function touchScale():Float
	{
		return isMobile() ? 1.15 : 1;
	}

	/** Smallest comfortable hit area (logical px) for the current device. */
	public static function touchSize():Float
	{
		return isMobile() ? 46 : 34;
	}

	/** Margin from the screen edges, used by bars and panels. */
	public static function inset():Float
	{
		return Math.max(6, 8 * scale);
	}

	/** Font size for a role: 'tiny' | 'small' | 'body' | 'title' | 'huge'. */
	public static function font(role:String = 'body'):Int
	{
		var base:Int = switch (role)
		{
			case 'tiny': 11;
			case 'small': 13;
			case 'title': 18;
			case 'huge': 22;
			default: 15;
		};

		return Std.int(Math.max(9, Math.round(base * scale)));
	}

	/** Spacing for a role: 'tight' | 'normal' | 'loose'. */
	public static function spacing(role:String = 'normal'):Float
	{
		var base:Float = switch (role)
		{
			case 'tight': 4;
			case 'loose': 14;
			default: 8;
		};

		return base * scale;
	}

	// ---------------------------------------------------------------------------------- geometry

	/** The left palette column is only used in landscape; upright screens get the bottom sheet. */
	public static function sidebarVisible():Bool
	{
		return !portrait;
	}

	/** Palette column width in landscape (0 when {@link sidebarVisible} is false). */
	public static function sidebarWidth():Float
	{
		if (!sidebarVisible())
			return 0;

		var wanted:Float = FlxMath.bound(width * 0.26, 200 * scale, 380 * scale);
		return Math.min(wanted, width * 0.42);
	}

	/** The narrow strip of category buttons at the far left. */
	public static function categoryStripWidth():Float
	{
		return Math.max(44, (isMobile() ? 58 : 70) * scale);
	}

	/** Height of the bottom palette sheet on upright screens (0 in landscape). */
	public static function paletteSheetHeight():Float
	{
		if (!portrait)
			return 0;

		return FlxMath.bound(height * 0.44, 240 * scale, height * 0.62);
	}

	/** Top bar button size; labels get a little more room than the glyph-only minimum. */
	public static function buttonHeight():Float
	{
		return Math.max(touchSize() * 0.9, 38 * scale);
	}

	public static function buttonWidth(?label:String):Float
	{
		var text:String = (label == null) ? '' : label;
		var estimated:Float = text.length * (font('body') * 0.62) + 20 * scale;

		return Math.max(58 * scale, estimated);
	}

	/** Rows the top bar needs for its buttons. */
	public static function topBarRows():Int
	{
		return (narrow || portrait) ? 2 : 1;
	}

	public static function topBarHeight(?rows:Int = 0):Float
	{
		var count:Int = (rows > 0) ? rows : topBarRows();

		return count * buttonHeight() + (count + 1) * spacing('tight');
	}

	public static function statusHeight():Float
	{
		return Math.max(24, 28 * scale);
	}

	public static function timelineHeight():Float
	{
		var wanted:Float = portrait ? 100 * scale : 118 * scale;

		return FlxMath.bound(wanted, portrait ? 78 : 92, portrait ? 132 : 180);
	}

	/** Space reserved on the right of the timeline for the trash can (landscape only). */
	public static function timelineRightMargin():Float
	{
		if (portrait)
			return inset();

		return Math.max(72, 86 * scale);
	}

	/** Area the block workspace may use. */
	public static function workspace():
		{
			x:Float,
			y:Float,
			w:Float,
			h:Float
		}
	{
		var x:Float = sidebarVisible() ? sidebarWidth() : 0;
		var y:Float = topBarHeight() + spacing('tight');
		var bottom:Float = height - statusHeight() - timelineHeight();

		if (portrait)
			bottom -= paletteSheetHeight();

		return {
			x: x,
			y: y,
			w: Math.max(120, width - x),
			h: Math.max(120, bottom - y)
		};
	}

	/** Timeline strip, sitting directly above the status bar — and above the palette sheet upright. */
	public static function timelineRect():
		{
			x:Float,
			y:Float,
			w:Float,
			h:Float
		}
	{
		var h:Float = timelineHeight();
		var below:Float = statusHeight() + (portrait ? paletteSheetHeight() : 0);
		var y:Float = height - below - h;
		var x:Float = sidebarVisible() ? sidebarWidth() + spacing('tight') : inset();
		var right:Float = portrait ? inset() : timelineRightMargin();

		return {
			x: x,
			y: y,
			w: Math.max(160, width - x - right),
			h: h
		};
	}

	/** Bottom palette sheet on upright screens (empty rect in landscape). */
	public static function paletteRect():
		{
			x:Float,
			y:Float,
			w:Float,
			h:Float
		}
	{
		var h:Float = paletteSheetHeight();
		var y:Float = height - statusHeight() - h;

		return {
			x: 0,
			y: y,
			w: width,
			h: h
		};
	}

	/** Width of the block list inside the palette (column or sheet, whichever is in use). */
	public static function paletteListWidth():Float
	{
		if (sidebarVisible())
			return Math.max(120, sidebarWidth() - categoryStripWidth());

		return Math.max(140, width - spacing('tight') * 2);
	}

	/** Palette tile height: roomy enough to read a block name and hit it with a thumb. */
	public static function paletteRowHeight():Float
	{
		var wanted:Float = (compact ? 40 : 46) * scale;

		return FlxMath.bound(wanted, 38, 74);
	}

	/** Size for panel overlays (save settings, code, files, help, context menu). */
	public static function panelSize(?maxW:Float = 0, ?maxH:Float = 0):{w:Float, h:Float}
	{
		var w:Float = FlxMath.bound(width * 0.92, 380, Math.max(380, width - inset() * 2));
		var h:Float = FlxMath.bound(height * 0.88, 300, Math.max(300, height - inset() * 2));

		if (maxW > 0)
			w = Math.min(w, maxW);
		if (maxH > 0)
			h = Math.min(h, maxH);

		return {w: w, h: h};
	}

	/** Where the block sprites themselves are drawn: phones get slightly bigger blocks. */
	public static function blockScale():Float
	{
		var wanted:Float = 1 + (scale - 1) * 0.6;

		return FlxMath.bound(wanted, 0.85, 1.3);
	}

	/** Human readable form of the current metrics, handy for the status bar when debugging. */
	public static function describe():String
	{
		return Std.int(width)
			+ 'x'
			+ Std.int(height)
			+ '  scale '
			+ (Math.round(scale * 100) / 100)
			+ (portrait ? '  portrait' : '  landscape');
	}
}
