package backend;

import haxe.io.Bytes;
import openfl.display.BitmapData;
import openfl.display3D.textures.Texture;
import openfl.utils._internal.UInt8Array;

/** Direct GPU upload, compatible with Troll Engine's premultiplied .astc.ktx output. */
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D.textures.TextureBase)
class ASTCBitmapData
{
	static var checkedContext:openfl.display3D.Context3D;
	static var hasASTC:Bool = false;

	public static function supported():Bool
	{
		var stage = openfl.Lib.current == null ? null : openfl.Lib.current.stage;
		var context = stage == null ? null : stage.context3D;
		if (context == null || context.gl == null)
			return false;
		if (checkedContext == context)
			return hasASTC;
		checkedContext = context;
		// Older Lime versions do not register an ASTC extension object; use the driver list.
		var extensions = context.gl.getSupportedExtensions();
		hasASTC = extensions != null
			&& (extensions.indexOf('KHR_texture_compression_astc_ldr') >= 0
				|| extensions.indexOf('GL_KHR_texture_compression_astc_ldr') >= 0
				|| extensions.indexOf('KHR_texture_compression_astc_hdr') >= 0
				|| extensions.indexOf('WEBGL_compressed_texture_astc') >= 0);
		return hasASTC;
	}

	public static function fromBytes(bytes:Bytes):BitmapData
	{
		var data = new ASTCData(bytes);
		if (!supported())
			throw 'This GPU does not support ASTC; keep a same-name PNG fallback';
		var context = openfl.Lib.current.stage.context3D;
		var gl = context.gl;
		#if html5
		gl.getExtension('WEBGL_compressed_texture_astc');
		#end
		if (data.width > gl.getParameter(gl.MAX_TEXTURE_SIZE) || data.height > gl.getParameter(gl.MAX_TEXTURE_SIZE))
			throw 'ASTC image exceeds GPU texture size limit';
		var texture:Texture = null;
		try
		{
			texture = context.createTexture(data.width, data.height, BGRA, false);
			texture.__format = data.format;
			texture.__internalFormat = data.format;
			context.__bindGLTexture2D(texture.__textureID);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
			gl.compressedTexImage2D(texture.__textureTarget, 0, data.format, data.width, data.height, 0, UInt8Array.fromBytes(bytes, data.offset, data.length));
			var error = gl.getError();
			if (error != 0)
				throw 'ASTC upload failed: GL error $error';
			context.__bindGLTexture2D(null);
			return new ASTCTextureBitmap(texture, data.width, data.height);
		}
		catch (error:Dynamic)
		{
			context.__bindGLTexture2D(null);
			if (texture != null)
				texture.dispose();
			throw error;
		}
	}
}

@:access(openfl.display.BitmapData)
@:access(openfl.display3D.textures.TextureBase)
private class ASTCTextureBitmap extends BitmapData
{
	var ownedTexture:Texture;

	public function new(texture:Texture, textureWidth:Int, textureHeight:Int)
	{
		// Avoid allocating a full uncompressed CPU image just to discard it.
		super(0, 0, true, 0);
		width = textureWidth;
		height = textureHeight;
		rect = new openfl.geom.Rectangle(0, 0, width, height);
		__textureWidth = width;
		__textureHeight = height;
		__isValid = true;
		readable = false;
		image = null;
		__texture = texture;
		__textureContext = texture.__textureContext;
		ownedTexture = texture;
	}

	override public function dispose():Void
	{
		if (ownedTexture != null)
		{
			ownedTexture.dispose();
			ownedTexture = null;
		}
		super.dispose();
	}
}
