package backend;

import haxe.Resource;
import lime.utils.Assets as LimeAssets;
import openfl.display.BitmapData;
import openfl.utils.Assets;

using StringTools;

/** OpenFL callers (Flixel UI, touch controls, atlases) do not necessarily use Paths.image. */
class BitmapAssetCompat
{
	static var readableAssets:Map<String, Bool> = [
		for (name in Resource.listNames())
			if (name.startsWith('readable-bitmap:')) name.substr(16) => true
	];

	static function readableID(id:String):String
	{
		return id != null && id.startsWith('default:') ? id.substr(8) : id;
	}

	public static function compressedID(id:String):Null<String>
	{
		if (id == null)
			return null;
		var lower = id.toLowerCase();
		if (lower.endsWith('.ktx') || lower.endsWith('.astc'))
			return LimeAssets.exists(id) ? id : null;
		if (!lower.endsWith('.png'))
			return null;
		var base = id.substr(0, id.length - 4);
		for (ext in ['.astc.ktx', '.astc'])
			if (LimeAssets.exists(base + ext))
				return base + ext;
		return null;
	}

	public static function exists(id:String):Bool
	{
		return readableAssets.exists(readableID(id)) || compressedID(id) != null;
	}

	public static function getBitmapData(id:String, useCache:Bool):BitmapData
	{
		var readable = readableID(id);
		var embedded = readableAssets.exists(readable);
		var compressed = embedded ? null : compressedID(id);
		if (!embedded && compressed == null)
			return null;
		var cache = Assets.cache;
		if (useCache && cache.enabled && cache.hasBitmapData(id))
		{
			var bitmap = cache.getBitmapData(id);
			if (bitmap != null && bitmap.width > 0 && bitmap.height > 0)
				return bitmap;
		}
		// Library controls use copyPixels/getPixel: they need genuine PNG pixels, not a GPU-only texture.
		var bitmap:BitmapData = null;
		if (embedded)
			bitmap = BitmapData.fromBytes(Resource.getBytes('readable-bitmap:' + readable));
		else
		{
			if (!ASTCBitmapData.supported() && LimeAssets.exists(id, IMAGE))
				return null;
			bitmap = ASTCBitmapData.fromBytes(LimeAssets.getBytes(compressed));
		}
		if (bitmap != null && useCache && cache.enabled)
			cache.setBitmapData(id, bitmap);
		return bitmap;
	}
}
