package animateatlas;

import flixel.util.FlxDestroyUtil;
import openfl.geom.Rectangle;
import flixel.math.FlxRect;
import openfl.Assets;
import haxe.Json;
import openfl.display.BitmapData;
import animateatlas.JSONData.AtlasData;
import animateatlas.JSONData.AnimationData;
import animateatlas.displayobject.SpriteAnimationLibrary;
import animateatlas.displayobject.SpriteMovieClip;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFramesCollection;
import flixel.graphics.frames.FlxFrame;
import flixel.util.FlxColor;

using StringTools;

class AtlasFrameMaker extends FlxFramesCollection
{
	/** Translation introduced solely to fit negative symbol coordinates into the baked canvas. */
	public var symbolX:Float = 0;

	public var symbolY:Float = 0;
	public var pivotX:Float = 0;
	public var pivotY:Float = 0;

	public function new(graphic:FlxGraphic)
	{
		super(graphic, FlxFrameCollectionType.IMAGE);
	}

	// public static var widthoffset:Int = 0;
	// public static var heightoffset:Int = 0;
	// public static var excludeArray:Array<String>;

	/** Largest allowed size of one side of a baked atlas page, in pixels. */
	public static var MAX_PAGE:Int = 4096;

	// An atlas is immutable and every character instance would bake the exact same frames again,
	// so baked collections are shared through this cache
	static var bakeCache:Map<String, FlxFramesCollection> = [];

	/**

		* Creates Frames from TextureAtlas(very early and broken ok) Originally made for FNF HD by Smokey and Rozebud
		*
		* @param   key                 The file path.
		* @param   _excludeArray       Use this to only create selected animations. Keep null to create all of them.
		*
	 */
	public static function construct(key:String, ?_excludeArray:Array<String> = null, ?noAntialiasing:Bool = false):FlxFramesCollection
	{
		// widthoffset = _widthoffset;
		// heightoffset = _heightoffset;

		var frameCollection:FlxFramesCollection;
		var frameArray:Array<Array<FlxFrame>> = [];

		// Adobe Animate 2019+ exports the atlas as spritemap1.json/spritemap1.png instead of
		// spritemap.json/spritemap.png; the data format is identical, so accept both names
		var spritemapKey:String = 'spritemap';
		if (!Paths.fileExists('images/$key/spritemap.json', TEXT) && Paths.fileExists('images/$key/spritemap1.json', TEXT))
		{
			spritemapKey = 'spritemap1';
		}

		// Animations asked for one by one are baked on their own: they would receive a collection
		// which also holds all the animations they explicitly left out
		var bakeAll:Bool = (_excludeArray == null);

		// allowGPU must be false: GPU-cached graphics have their CPU pixel data
		// stripped (Paths.cacheBitmap), which makes copyPixels()/draw() bake
		// every frame as a plain white rectangle
		var graphic:FlxGraphic = Paths.image('$key/$spritemapKey', null, false);

		// The sheet is looked up through the mod folders and another mod may replace it, so the frames
		// are cached under the path the sheet was really loaded from
		var cacheKey:String = (graphic == null || graphic.key == null) ? '$key/$spritemapKey' : graphic.key;
		if (noAntialiasing == true)
			cacheKey += '_noaa';

		if (bakeAll)
		{
			// A cached collection is only still usable while the graphics it was baked into are alive
			var cached:FlxFramesCollection = bakeCache.get(cacheKey);
			if (cached != null && cached.parent != null && cached.numFrames > 0 && !cached.frames[0].parent.isDestroyed)
				return cached;
		}

		var animationPath:String = 'images/$key/Animation.json';
		var spritemapPath:String = 'images/$key/$spritemapKey.json';
		var animationText:String = Paths.getTextFromFile(animationPath);
		var spritemapText:String = Paths.getTextFromFile(spritemapPath);

		if (animationText == null || spritemapText == null || graphic == null)
			throw 'Missing or invalid Animate atlas data for images/$key (Animation.json / $spritemapKey.json)';

		// Adobe Animate 2019+ writes Animation.json with short key names (AN/SD/MD);
		// normalize those into the long-key format the library expects
		var rawAnimation:Dynamic = Json.parse(animationText.replace("\uFEFF", ""));
		var shortFormat:Bool = ShortKeyConverter.isShortFormat(rawAnimation);
		var animationData:AnimationData = shortFormat ? ShortKeyConverter.normalize(rawAnimation) : (cast rawAnimation : AnimationData);
		var atlasData:AtlasData = Json.parse(spritemapText.replace("\uFEFF", ""));

		if (animationData == null || atlasData == null)
			throw 'Missing or invalid Animate atlas data for images/$key (Animation.json / $spritemapKey.json)';

		// allowGPU=false prefers PNG, but a stripped APK may only contain ASTC.
		// Read its pixels once for the CPU baker without replacing the cached GPU texture.
		var pixels = BitmapReadback.readable(graphic.bitmap);
		var shotsByAnimation:Map<String, Array<{bitmap:BitmapData, originX:Float, originY:Float}>> = [];
		try
		{
			var ss:SpriteAnimationLibrary = new SpriteAnimationLibrary(animationData, atlasData, pixels);
			var t:SpriteMovieClip = ss.createAnimation(noAntialiasing);
			var labels:Array<String> = t.getFrameLabels();
			if (_excludeArray == null)
			{
				_excludeArray = labels;
				// Short-key atlases usually store each animation in a dictionary symbol.
				if (_excludeArray.length == 0 && shortFormat)
					_excludeArray = getMainTimelineSymbols(animationData, ss);
			}

			// Labels may occur on multiple layers; never pack already disposed shots twice.
			var uniqueAnimations:Array<String> = [];
			for (x in _excludeArray)
			{
				if (uniqueAnimations.indexOf(x) == -1)
					uniqueAnimations.push(x);
			}
			_excludeArray = uniqueAnimations;
			trace('Creating: ' + _excludeArray);

			// Keep tight shots until the character-wide logical canvas is known.
			for (x in _excludeArray)
			{
				if (labels.indexOf(x) == -1 && ss.hasAnimation(x))
					shotsByAnimation.set(x, getSymbolFramesArray(ss.createAnimation(noAntialiasing, x), x));
				else
					shotsByAnimation.set(x, getFramesArray(t, x));
			}
		}
		catch (error:Dynamic)
		{
			if (pixels != graphic.bitmap)
				pixels.dispose();
			for (shots in shotsByAnimation)
				for (shot in shots)
					shot.bitmap.dispose();
			throw 'Cannot bake Animate atlas images/$key: ' + Std.string(error);
		}
		if (pixels != graphic.bitmap)
			pixels.dispose();

		// flixel derives a sprite's origin from the first frame's sourceSize and keeps it for every
		// other frame, so one canvas per animation made the sprite jump on every animation change
		// (and shifted the flipX/scale pivot). Every shot of the character therefore shares the union
		// of all shots as its logical canvas, at its true position inside symbol space.
		var minX:Float = 0;
		var minY:Float = 0;
		var maxX:Float = 1;
		var maxY:Float = 1;
		for (shots in shotsByAnimation)
		{
			for (shot in shots)
			{
				minX = Math.min(minX, shot.originX);
				minY = Math.min(minY, shot.originY);
				maxX = Math.max(maxX, shot.originX + shot.bitmap.width);
				maxY = Math.max(maxY, shot.originY + shot.bitmap.height);
			}
		}

		var canvasW:Int = Std.int(Math.max(1, Math.ceil(maxX - minX)));
		var canvasH:Int = Std.int(Math.max(1, Math.ceil(maxY - minY)));

		for (x in _excludeArray)
		{
			frameArray.push(buildPagedFrames(x, shotsByAnimation.get(x), minX, minY, canvasW, canvasH));
		}

		var baked = new AtlasFrameMaker(graphic);
		baked.symbolX = minX;
		baked.symbolY = minY;
		// FlxAnimate uses the stage instance's transformation point, not the canvas centre.
		var stageInstance:Dynamic = shortFormat ? rawAnimation.AN.STI : null;
		if (stageInstance != null && stageInstance.SI != null && stageInstance.SI.TRP != null)
		{
			baked.pivotX = stageInstance.SI.TRP.x;
			baked.pivotY = stageInstance.SI.TRP.y;
		}
		frameCollection = baked;
		for (x in frameArray)
		{
			for (y in x)
			{
				frameCollection.pushFrame(y);
			}
		}

		if (bakeAll)
			bakeCache.set(cacheKey, frameCollection);

		return frameCollection;
	}

	@:noCompletion static function getFramesArray(t:SpriteMovieClip, animation:String):Array<{bitmap:BitmapData, originX:Float, originY:Float}>
	{
		t.currentLabel = animation;
		var shots:Array<{bitmap:BitmapData, originX:Float, originY:Float}> = [];
		var prevFrame:Int = -1;

		for (i in t.getFrame(animation)...t.numFrames)
		{
			// currentFrame is set absolutely, so nested movieclips must be advanced by hand
			if (prevFrame < 0)
			{
				t.stepNested(i);
			}
			else
			{
				t.stepNested(i - prevFrame);
			}
			prevFrame = i;
			t.currentFrame = i;
			if (t.currentLabel != animation)
				break;

			var shot = renderFrame(t);
			if (shot == null)
				continue;

			shots.push(shot);
		}

		return shots;
	}

	// Bakes every frame of a single dictionary symbol (short-key atlases store each
	// animation as its own symbol instead of using main timeline frame labels)
	@:noCompletion static function getSymbolFramesArray(t:SpriteMovieClip, animation:String):Array<{bitmap:BitmapData, originX:Float, originY:Float}>
	{
		var shots:Array<{bitmap:BitmapData, originX:Float, originY:Float}> = [];

		t.currentFrame = 0;
		for (i in 0...t.numFrames)
		{
			if (i > 0)
			{
				t.stepFrames(1); // advance nested movieclips as well, frame-accurate
			}

			var shot = renderFrame(t);
			if (shot == null)
				continue;

			shots.push(shot);
		}

		return shots;
	}

	/**
	 * Renders the current state of a movie clip into its own tight bitmap. Animate bounds can start
	 * at negative coordinates; the shot keeps that position as its origin so the compositing step
	 * can place it inside the shared canvas instead of clipping the art.
	 */
	@:noCompletion static function renderFrame(t:SpriteMovieClip):{bitmap:BitmapData, originX:Float, originY:Float}
	{
		var sizeInfo:Rectangle = t.getBounds(t);
		var originX:Float = Math.floor(sizeInfo.x);
		var originY:Float = Math.floor(sizeInfo.y);
		var canvasW:Int = Std.int(Math.max(1, Math.ceil(sizeInfo.x + sizeInfo.width) - originX));
		var canvasH:Int = Std.int(Math.max(1, Math.ceil(sizeInfo.y + sizeInfo.height) - originY));
		var canvas:BitmapData = new BitmapData(canvasW, canvasH, true, 0);
		var drawMatrix:openfl.geom.Matrix = new openfl.geom.Matrix();
		drawMatrix.translate(-originX, -originY);
		canvas.draw(t, drawMatrix, null, null, null, true);

		return {bitmap: canvas, originX: originX, originY: originY};
	}

	/**
	 * Packs the tight shots of one animation into shared atlas pages, one `FlxFrame` per shot.
	 * Frames of an Animate symbol have different bounds (the art moves inside the symbol), and
	 * flixel aligns every animation frame through `sourceSize`. Each frame therefore keeps the
	 * character-wide `sourceSize` computed in `construct` and records where its art belongs inside
	 * that logical canvas through `offset` - the trim data sparrow stores in `spriteSourceSize`.
	 *
	 * Shots are laid out on a fixed grid whose cell is the largest shot of the animation, and a page
	 * is only as large as the cells it actually holds.
	 */
	@:noCompletion static function buildPagedFrames(animation:String, shots:Array<{bitmap:BitmapData, originX:Float, originY:Float}>, minX:Float, minY:Float,
			canvasW:Int, canvasH:Int):Array<FlxFrame>
	{
		var daFramez:Array<FlxFrame> = [];
		if (shots == null || shots.length == 0)
			return daFramez;

		var cellW:Int = 1;
		var cellH:Int = 1;
		for (shot in shots)
		{
			cellW = Std.int(Math.max(cellW, shot.bitmap.width));
			cellH = Std.int(Math.max(cellH, shot.bitmap.height));
		}

		if (cellW > MAX_PAGE || cellH > MAX_PAGE)
			trace('$animation has a ${cellW}x${cellH} shot, larger than a ${MAX_PAGE}x${MAX_PAGE} atlas page: it will be cropped');

		var cellSizeW:Int = Std.int(Math.min(cellW, MAX_PAGE));
		var cellSizeH:Int = Std.int(Math.min(cellH, MAX_PAGE));
		var maxCols:Int = Std.int(Math.max(1, MAX_PAGE / cellSizeW));
		var maxRows:Int = Std.int(Math.max(1, MAX_PAGE / cellSizeH));

		var i:Int = 0;
		while (i < shots.length)
		{
			var count:Int = Std.int(Math.min(maxCols * maxRows, shots.length - i));
			var pageW:Int = Std.int(Math.min(maxCols, count)) * cellSizeW;
			var pageH:Int = Std.int(Math.ceil(count / maxCols)) * cellSizeH;
			var page:BitmapData = new BitmapData(pageW, pageH, true, 0);
			// This fresh page has a single owner; cloning doubles peak memory on mobile.
			var pageGraphic:FlxGraphic = FlxGraphic.fromBitmapData(page, false, null, false);

			for (j in 0...count)
			{
				var shot = shots[i + j];
				var cellX:Int = (j % maxCols) * cellSizeW;
				var cellY:Int = Std.int(j / maxCols) * cellSizeH;
				var shotW:Int = Std.int(Math.min(shot.bitmap.width, pageW - cellX));
				var shotH:Int = Std.int(Math.min(shot.bitmap.height, pageH - cellY));

				page.copyPixels(shot.bitmap, new Rectangle(0, 0, shotW, shotH), new openfl.geom.Point(cellX, cellY));
				shot.bitmap.dispose();
				// Build from the same typed coordinates used by copyPixels, before moving on.
				var theFrame = new FlxFrame(pageGraphic);
				theFrame.name = animation + '_' + (i + j);
				theFrame.sourceSize.set(canvasW, canvasH);
				theFrame.frame = new FlxRect(cellX, cellY, shotW, shotH);
				theFrame.offset.set(shot.originX - minX, shot.originY - minY);
				daFramez.push(theFrame);
			}

			i += count;
		}

		return daFramez;
	}

	// Collects the symbols the main timeline places on stage (the actual animations),
	// falling back to every symbol in the dictionary when the main timeline is empty
	@:noCompletion static function getMainTimelineSymbols(animationData:AnimationData, ss:SpriteAnimationLibrary):Array<String>
	{
		var names:Array<String> = [];
		var mainName:String = (animationData.ANIMATION != null) ? animationData.ANIMATION.SYMBOL_name : null;

		if (animationData.ANIMATION != null && animationData.ANIMATION.TIMELINE != null)
		{
			for (layer in animationData.ANIMATION.TIMELINE.LAYERS)
			{
				if (layer.Frames == null)
					continue;
				for (frame in layer.Frames)
				{
					if (frame.elements == null)
						continue;
					for (element in frame.elements)
					{
						var instance = element.SYMBOL_Instance;
						if (instance == null)
							continue;
						var name:String = instance.SYMBOL_name;
						if (name != null
							&& name != mainName
							&& name != SpriteAnimationLibrary.BITMAP_SYMBOL_NAME
							&& names.indexOf(name) == -1
							&& ss.hasAnimation(name))
						{
							names.push(name);
						}
					}
				}
			}
		}

		if (names.length == 0)
		{
			for (name in ss.getAnimationNames())
			{
				if (name != mainName)
					names.push(name);
			}
		}
		return names;
	}
}
