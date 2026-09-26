import animateatlas.AtlasFrameMaker;
import backend.BitmapReadback;
import flixel.graphics.FlxGraphic;
import haxe.Json;
import openfl.display.BitmapData;

@:access(animateatlas.AtlasFrameMaker)
@:access(openfl.display3D.Context3D)
class AnimateAtlasTest
{
	static function check(condition:Bool, message:String):Void
	{
		if (!condition)
			throw message;
	}

	static function main():Void
	{
		// Real OpenFL/Lime/Flixel objects, with a small hidden window for GPU readback.
		var app = new openfl.display.Application();
		var window = app.createWindow({
			width: 32,
			height: 32,
			hidden: true,
			context: {type: OPENGL}
		});
		var context = openfl.Lib.current.stage.context3D;
		check(context != null, 'This test requires an OpenGL context');
		checkPages();

		var source = new BitmapData(4, 2, true, 0);
		var colors:Array<UInt> = [
			0xffff0000,
			0xff00ff00,
			0xff0000ff,
			0xffabcdef,
			0x80804020,
			0,
			0xffffffff,
			0xff123456
		];
		for (i in 0...colors.length)
			source.setPixel32(i % 4, Std.int(i / 4), colors[i]);
		check(BitmapReadback.readable(source) == source, 'Readable PNG unnecessarily copied');

		var texture = context.createRectangleTexture(4, 2, BGRA, false);
		texture.uploadFromBitmapData(source);
		var gpu = BitmapData.fromTexture(texture);
		// Preserve a caller's render target and viewport, including when invoked during rendering.
		var previousTarget = context.createRectangleTexture(7, 5, BGRA, true);
		context.setRenderToTexture(previousTarget);
		var cpu = BitmapReadback.readable(gpu);
		check(context.__state.renderToTexture == previousTarget, 'Caller render target lost');
		var viewport:lime.utils.Int32Array = cast context.gl.getParameter(context.gl.VIEWPORT);
		check(viewport[2] == 7 && viewport[3] == 5, 'Caller viewport lost');
		check(cpu != gpu && cpu.readable, 'GPU source did not produce readable pixels');
		check(!gpu.readable && gpu.image == null && gpu.width == 4, 'Shared GPU source changed');
		for (i in 0...colors.length)
			check(cpu.getPixel32(i % 4, Std.int(i / 4)) == colors[i], 'Readback color/alpha/orientation mismatch at pixel ' + i);

		checkAtlas(source, 'cpu-atlas');
		checkAtlas(gpu, 'gpu-atlas');
		check(!gpu.readable && gpu.width == 4, 'Baking disposed the shared GPU source');
		context.setRenderToBackBuffer();
		context.__flushGLFramebuffer();
		cpu.dispose();
		gpu.dispose();
		texture.dispose();
		previousTarget.dispose();
		source.dispose();
		Sys.println('PASS: real GPU readback colors/alpha/orientation, render-target restoration, Animate baking and multi-page frame coordinates');
		window.close();
	}

	static function checkPages():Void
	{
		AtlasFrameMaker.MAX_PAGE = 32;
		var shots = [
			for (i in 0...23)
				{
					bitmap: new BitmapData(8 + i % 5, 10 + i % 2, true, 0xff102030 + i),
					originX: -12.0 + i % 3,
					originY: -7.0 + i % 4
				}
		];
		var frames = AtlasFrameMaker.buildPagedFrames('idle', shots, -12, -7, 24, 28);
		check(frames.length == shots.length, 'Lost packed frames');
		check(frames[0].parent != frames[frames.length - 1].parent, 'Fixture did not span atlas pages');
		for (i in 0...frames.length)
		{
			var frame = frames[i];
			check(frame.name == 'idle_' + i, 'Frame order changed');
			check(frame.sourceSize.x == 24 && frame.sourceSize.y == 28, 'Logical canvas changed');
			check(frame.offset.x == i % 3 && frame.offset.y == i % 4, 'Symbol offset changed');
			check(frame.frame.width == 8 + i % 5 && frame.frame.height == 10 + i % 2, 'Packed bounds changed');
			check(frame.frame.right <= frame.parent.width && frame.frame.bottom <= frame.parent.height, 'Frame outside page');
			check(frame.parent.width <= 32 && frame.parent.height <= 32, 'Page exceeds texture limit');
			check(frame.parent.bitmap.getPixel32(Std.int(frame.frame.x), Std.int(frame.frame.y)) == 0xff102030 + i, 'Packed pixels missing');
			check(shots[i].bitmap.width == 0, 'Temporary shot was not released');
		}
		check(AtlasFrameMaker.buildPagedFrames('empty', [], 0, 0, 1, 1).length == 0, 'Empty animation produced frames');
		var pages = new Map<FlxGraphic, Bool>();
		for (frame in frames)
			pages.set(frame.parent, true);
		for (page in pages.keys())
			page.destroy();
	}

	static function checkAtlas(bitmap:BitmapData, key:String):Void
	{
		Paths.graphic = FlxGraphic.fromBitmapData(bitmap, false, null, false);
		var elements = function(name:String, x:Int, y:Int)
		{
			return [{ATLAS_SPRITE_instance: {name: name, Position: {x: x, y: y}}}];
		};
		Paths.animation = Json.stringify({
			ANIMATION: {
				SYMBOL_name: 'main',
				TIMELINE: {
					LAYERS: [
						{
							Layer_name: 'art',
							Frames: [
								{
									index: 0,
									duration: 1,
									name: 'idle',
									elements: elements('red', -4, -2)
								},
								{index: 1, duration: 1, elements: elements('blue', 2, 1)}
							]
						},
						{
							Layer_name: 'labels',
							Frames: [
								{
									index: 0,
									duration: 2,
									name: 'idle',
									elements: []
								}
							]
						}
					]
				}
			},
			SYMBOL_DICTIONARY: {Symbols: []}
		});
		Paths.atlas = Json.stringify({
			ATLAS: {
				SPRITES: [
					{
						SPRITE: {
							name: 'red',
							x: 0,
							y: 0,
							w: 2,
							h: 2,
							rotated: false
						}
					},
					{
						SPRITE: {
							name: 'blue',
							x: 2,
							y: 0,
							w: 2,
							h: 2,
							rotated: false
						}
					}
				]
			}
		});
		var baked:AtlasFrameMaker = cast AtlasFrameMaker.construct(key, null, true);
		check(baked.numFrames == 2, 'Duplicate layer labels baked twice');
		check(baked.symbolX == -4 && baked.symbolY == -2, 'Negative symbol origin lost');
		check(AtlasFrameMaker.construct(key, null, true) == baked, 'Baked atlas not reused');
		for (i in 0...2)
		{
			var frame = baked.frames[i];
			check(frame.sourceSize.x == 8 && frame.sourceSize.y == 5, 'Character-wide canvas changed');
			check(frame.offset.x == i * 6 && frame.offset.y == i * 3, 'Baked frame moved');
			check(frame.parent.bitmap.getPixel32(Std.int(frame.frame.x), Std.int(frame.frame.y)) == (i == 0 ? 0xffff0000 : 0xff0000ff),
				'Animate baked blank or incorrect pixels from ' + key);
		}
	}
}
