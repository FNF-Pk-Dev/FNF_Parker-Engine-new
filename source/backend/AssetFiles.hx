package backend;

#if (ASSET_MODS && sys && !macro)
import haxe.io.Bytes;
import haxe.io.Path;
import lime.utils.Assets;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/** Read-only virtual filesystem for packaged assets. Other paths keep native sys semantics. */
@:access(lime.utils.Assets)
class AssetFiles
{
	static var files:Map<String, String>;
	static var directories:Map<String, Array<String>>;
	static var foldedPaths:Map<String, String>;
	static var bypass = new sys.thread.Tls<Bool>();
	static var extracted:Map<String, String> = [];
	static var indexedLibraries:Int = -1;

	public static function resolve(path:String):Null<String>
	{
		if (path == null || bypass.value == true)
			return null;
		var normalized = Path.normalize(path.replace('\\', '/'));
		var cwd = Path.addTrailingSlash(Path.normalize(Sys.getCwd()));
		if (normalized.startsWith(cwd))
			normalized = normalized.substr(cwd.length);
		var colon = normalized.indexOf(':assets/');
		if (colon >= 0)
			normalized = normalized.substr(colon + 1);
		if (normalized == 'mods' || normalized.startsWith('mods/'))
			normalized = 'assets/' + normalized;
		return normalized == 'assets' || normalized.startsWith('assets/') ? normalized : null;
	}

	static function nativeAccess<T>(action:Void->T):T
	{
		var previous = bypass.value;
		bypass.value = true;
		try
		{
			var result = action();
			bypass.value = previous;
			return result;
		}
		catch (error:Dynamic)
		{
			bypass.value = previous;
			throw error;
		}
	}

	static function ensureIndex():Void
	{
		var libraries = [for (name in Assets.libraries.keys()) name];
		if (files != null && indexedLibraries == libraries.length)
			return;
		var nextFiles:Map<String, String> = [];
		var nextDirectories:Map<String, Array<String>> = [];
		var ids:Array<String> = [];
		for (name in libraries)
		{
			var entries = nativeAccess(() -> Assets.libraries.get(name).list(null));
			if (entries != null)
				for (id in entries)
					ids.push(name == 'default' || id.indexOf(':') >= 0 ? id : name + ':' + id);
		}
		for (id in ids)
		{
			var key = resolve(id);
			if (key == null)
				continue;
			// Prefer a library-qualified ID over an ambiguous unqualified ID.
			if (!nextFiles.exists(key) || id.indexOf(':') >= 0)
				nextFiles.set(key, id);
			var child = key;
			while (child.indexOf('/') >= 0)
			{
				var parent = Path.directory(child);
				var entries = nextDirectories.get(parent);
				if (entries == null)
				{
					entries = [];
					nextDirectories.set(parent, entries);
				}
				var name = child.substr(parent.length + 1);
				if (!entries.contains(name))
					entries.push(name);
				child = parent;
			}
		}
		files = nextFiles;
		directories = nextDirectories;
		foldedPaths = [];
		for (keys in [files.keys(), directories.keys()])
		{
			for (key in keys)
			{
				var lower = key.toLowerCase();
				// Ambiguous names still require exact casing; never pick a random asset.
				if (foldedPaths.exists(lower) && foldedPaths.get(lower) != key)
					foldedPaths.set(lower, null);
				else
					foldedPaths.set(lower, key);
			}
		}
		indexedLibraries = libraries.length;
	}

	/** Song keys are lowercase, but Windows-authored mods may contain mixed-case directories. */
	static function matchingPath(path:String):String
	{
		ensureIndex();
		if (files.exists(path) || directories.exists(path))
			return path;
		var matched = foldedPaths.get(path.toLowerCase());
		return matched != null ? matched : path;
	}

	public static function exists(path:String):Bool
	{
		path = matchingPath(path);
		return files.exists(path) || directories.exists(path);
	}

	public static function isDirectory(path:String):Bool
	{
		path = matchingPath(path);
		return directories.exists(path);
	}

	public static function readDirectory(path:String):Array<String>
	{
		path = matchingPath(path);
		var entries = directories.get(path);
		if (entries == null)
			throw 'Asset directory does not exist: $path';
		return entries.copy();
	}

	public static function getBytes(path:String):Bytes
	{
		var id = getAssetID(path);
		if (id == null)
			throw 'Asset file does not exist: $path';
		var bytes = nativeAccess(() -> Assets.getBytes(id));
		if (bytes == null)
			throw 'Asset is not loaded: $id';
		return bytes;
	}

	/** Resolve the owning library too; typed assets must use their typed loader. */
	public static function getAssetID(path:String):Null<String>
	{
		path = matchingPath(path);
		return files.get(path);
	}

	public static function getContent(path:String):String
	{
		return getBytes(path).toString();
	}

	/** Only APIs that require a native filename (video/fonts/FileInput) need extraction. */
	public static function materialize(path:String):String
	{
		var key = resolve(path);
		if (key == null)
			return path;
		if (extracted.exists(key))
			return extracted.get(key);
		var bytes = getBytes(key);
		var root = lime.system.System.applicationStorageDirectory;
		if (root == null || root.length == 0)
			throw 'No writable application storage for $key';

		var directory = Path.join([root, 'asset-cache']);
		var target = Path.join([directory, haxe.crypto.Sha256.make(bytes).toHex() + '.' + Path.extension(key)]);
		nativeAccess(() ->
		{
			FileSystem.createDirectory(directory);
			if (!FileSystem.exists(target))
				File.saveBytes(target, bytes);
			return true;
		});
		extracted.set(key, target);
		return target;
	}

	public static function stat(path:String):sys.FileStat
	{
		if (!exists(path))
			throw 'Asset does not exist: $path';
		var time = Date.fromTime(0);
		return {
			gid: 0,
			uid: 0,
			atime: time,

			mtime: time,
			ctime: time,
			dev: 0,
			ino: 0,
			nlink: 1,
			rdev: 0,
			size: isDirectory(path) ? 0 : getBytes(path).length,
			mode: isDirectory(path) ? 0x416D : 0x8124
		};
	}
}
#end
