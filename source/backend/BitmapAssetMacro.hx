package backend;

#if macro
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;

/** Keep CPU-readable library UI art even when Lime strips all project PNG assets. */
class BitmapAssetMacro
{
	public static function install():Void
	{
		Compiler.addGlobalMetadata('openfl.utils.Assets', '@:build(backend.BitmapAssetMacro.build())', false, true, false);
		var uiRoot = Context.resolvePath('flixel/addons/ui/FlxUIAssets.hx');
		for (_ in 0...4)
			uiRoot = Path.directory(uiRoot);
		embedImages(uiRoot + '/assets/images', 'flixel/flixel-ui/img');
		var flixelRoot = Path.directory(Path.directory(Context.resolvePath('flixel/FlxG.hx')));
		for (name in ['ui/button.png', 'logo/default.png'])
			Context.addResource('readable-bitmap:flixel/images/' + name, sys.io.File.getBytes(flixelRoot + '/assets/images/' + name));
	}

	static function embedImages(directory:String, assetDirectory:String):Void
	{
		for (name in sys.FileSystem.readDirectory(directory))
		{
			var file = directory + '/' + name;
			var id = assetDirectory + '/' + name;
			if (sys.FileSystem.isDirectory(file))
				embedImages(file, id);
			else if (StringTools.endsWith(name.toLowerCase(), '.png'))
				Context.addResource('readable-bitmap:' + id, sys.io.File.getBytes(file));
		}
	}

	public static function build():Array<Field>
	{
		var fields = Context.getBuildFields();
		for (field in fields)
		{
			switch (field.kind)
			{
				case FFun(fn) if (field.name == 'getBitmapData'):
					var original = fn.expr;
					fn.expr = macro
						{
							var compatible = backend.BitmapAssetCompat.getBitmapData(id, useCache);
							if (compatible != null)
								return compatible;
							$original;
						};
				case FFun(fn) if (field.name == 'exists'):
					var original = fn.expr;
					fn.expr = macro
						{
							if ((type == null || type == openfl.utils.AssetType.IMAGE) && backend.BitmapAssetCompat.exists(id))
								return true;
							$original;
						};
				default:
			}
		}
		return fields;
	}
}
#end
