package backend;

import openfl.display.BitmapData;
import openfl.display3D.textures.TextureBase;

/** CPU pixels for consumers such as Animate's copyPixels/draw baker. */
@:access(openfl.display.BitmapData)
@:access(openfl.display3D.Context3D)
class BitmapReadback
{
	/** Returns the source if readable, otherwise a new bitmap owned by the caller. */
	public static function readable(source:BitmapData):BitmapData
	{
		if (source == null || source.width <= 0 || source.height <= 0)
			throw 'Cannot read pixels from a missing or disposed bitmap';
		if (source.readable && source.image != null)
			return source;

		var stage = openfl.Lib.current == null ? null : openfl.Lib.current.stage;
		var context = stage == null ? null : stage.context3D;
		if (context == null || context.gl == null)
			throw 'Reading GPU bitmap pixels requires an active OpenGL context';

		var gl = context.gl;
		var previousTarget = context.__state.renderToTexture;
		var previousDepthStencil = context.__state.renderToTextureDepthStencil;
		var previousAntiAlias = context.__state.renderToTextureAntiAlias;
		var previousSurface = context.__state.renderToTextureSurfaceSelector;
		var target = new BitmapData(source.width, source.height, true, 0);
		var pixels = target.image;
		// GL readPixels guarantees RGBA, even when OpenFL uploads BGRA textures.
		pixels.format = RGBA32;
		pixels.premultiplied = true;
		var texture:TextureBase = null;
		var restore = function()
		{
			if (previousTarget != null)
				context.setRenderToTexture(previousTarget, previousDepthStencil, previousAntiAlias, previousSurface);
			else
				context.setRenderToBackBuffer();
			context.__flushGLFramebuffer();
			context.__flushGLViewport();
			if (texture != null)
				texture.dispose();
			target.dispose();
		};
		try
		{
			// Compressed textures cannot be framebuffer attachments. Draw into an
			// ordinary RGBA target first; OpenFL's texture projection puts row 0 at y=0.
			target.readable = false;
			texture = target.getTexture(context);
			target.draw(source);
			context.setRenderToTexture(texture);
			context.__flushGLFramebuffer();
			if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE)
				throw 'GPU bitmap readback framebuffer is incomplete';
			gl.readPixels(0, 0, source.width, source.height, gl.RGBA, gl.UNSIGNED_BYTE, pixels.buffer.data);
			var error = gl.getError();
			if (error != 0)
				throw 'GPU bitmap readback failed: GL error $error';
		}
		catch (error:Dynamic)
		{
			restore();
			throw error;
		}
		restore();
		return BitmapData.fromImage(pixels);
	}
}
