package backend;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;

/** Patch method bodies, preserving sys types and native behavior outside the asset namespace. */
class AssetFilesMacro
{
	public static function install():Void
	{
		if (!Context.defined('ASSET_MODS'))
			return;
		for (name in [
			'sys.FileSystem',
			'sys.io.File',
			'openfl.display.BitmapData',
			'openfl.media.Sound',
			'openfl.text.Font'
		])
			Compiler.addGlobalMetadata(name, '@:build(backend.AssetFilesMacro.build())', false, true, false);
	}

	public static function build():Array<Field>
	{
		var cls = Context.getLocalClass().get();
		var name = cls.pack.concat([cls.name]).join('.');
		var fields = Context.getBuildFields();
		for (field in fields)
		{
			switch (field.kind)
			{
				case FFun(fn) if (fn.expr != null && fn.args.length > 0):
					var argument = macro $i{fn.args[0].name};
					var original = fn.expr;
					var action:Expr = null;
					if (name == 'sys.FileSystem')
					{
						action = switch (field.name)
						{
							case 'exists': macro return backend.AssetFiles.exists(assetPath);
							case 'isDirectory': macro return backend.AssetFiles.isDirectory(assetPath);
							case 'readDirectory': macro return backend.AssetFiles.readDirectory(assetPath);
							case 'stat': macro return backend.AssetFiles.stat(assetPath);
							case 'fullPath', 'absolutePath': macro return assetPath;
							default: null;
						};
					}
					else if (name == 'sys.io.File')
					{
						action = switch (field.name)
						{
							case 'getContent': macro return backend.AssetFiles.getContent(assetPath);
							case 'getBytes': macro return backend.AssetFiles.getBytes(assetPath);
							case 'read': macro $argument = backend.AssetFiles.materialize(assetPath);
							default: null;
						};
					}
					else if (field.name == 'fromFile')
					{
						action = switch (name)
						{
							case 'openfl.display.BitmapData': macro return openfl.display.BitmapData.fromBytes(backend.AssetFiles.getBytes(assetPath));
							case 'openfl.media.Sound': macro return
									openfl.media.Sound.fromAudioBuffer(lime.media.AudioBuffer.fromBytes(backend.AssetFiles.getBytes(assetPath)));
							default: macro $argument = backend.AssetFiles.materialize(assetPath);
						};
					}
					if (action != null)
						fn.expr = macro
							{
								var assetPath = backend.AssetFiles.resolve($argument);
								if (assetPath != null)
									$action;
								$original;
							};
					else if ((name == 'sys.io.File' && ['write', 'append', 'update', 'saveContent', 'saveBytes'].indexOf(field.name) >= 0)
						|| (name == 'sys.FileSystem'
							&& ['createDirectory', 'deleteFile', 'deleteDirectory', 'rename'].indexOf(field.name) >= 0))
					{
						fn.expr = macro
							{
								if (backend.AssetFiles.resolve($argument) != null)
									throw 'Packaged assets are read-only: ' + $argument;
								$original;
							};
					}
				default:
			}
		}
		return fields;
	}
}
#end
