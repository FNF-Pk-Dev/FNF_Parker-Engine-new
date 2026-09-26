import backend.ASTCData;
import backend.AssetFiles;
import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

class AssetLoadingTest
{
	static function check(value:Bool, message:String):Void
	{
		if (!value)
			throw message;
	}

	static function reject(action:Void->Void, message:String):Void
	{
		var failed = false;
		try
		{
			action();
		}
		catch (_:Dynamic)
		{
			failed = true;
		}
		check(failed, message);
	}

	static function ktx():Bytes
	{
		var bytes = Bytes.alloc(84);
		bytes.blit(0, Bytes.ofHex('ab4b5458203131bb0d0a1a0a'), 0, 12);
		var fields = [0x04030201, 0, 1, 0, 0x93B4, 0x1908, 6, 6, 0, 0, 1, 1, 0, 16];
		for (i in 0...fields.length)
			bytes.setInt32(12 + i * 4, fields[i]);
		return bytes;
	}

	static function main():Void
	{
		var bytes = ktx();
		var image = new ASTCData(bytes);
		check(image.width == 6 && image.height == 6 && image.offset == 68 && image.length == 16, 'Troll-compatible KTX');
		var big = ktx();
		for (i in 0...14)
		{
			var pos = 12 + i * 4;
			for (j in 0...4)
				big.set(pos + j, bytes.get(pos + 3 - j));
		}
		check(new ASTCData(big).format == 0x93B4, 'Big endian KTX');
		reject(() ->
		{
			new ASTCData(bytes.sub(0, 80));
		}, 'Truncated payload accepted');
		bytes.setInt32(60, 0x7FFFFFFF);
		reject(() ->
		{
			new ASTCData(bytes);
		}, 'Overflow metadata accepted');
		bytes = ktx();
		bytes.setInt32(64, 8);
		reject(() ->
		{
			new ASTCData(bytes);
		}, 'Incorrect ASTC block size accepted');
		bytes = ktx();
		bytes.setInt32(48, 1);
		reject(() ->
		{
			new ASTCData(bytes);
		}, 'Array texture accepted');
		var raw = Bytes.alloc(32);
		raw.setInt32(0, 0x5CA1AB13);
		raw.set(4, 6);
		raw.set(5, 6);
		raw.set(6, 1);
		raw.set(7, 6);
		raw.set(10, 6);
		raw.set(13, 1);
		check(new ASTCData(raw).length == 16, 'Raw ASTC');

		check(FileSystem.exists('mods/demo/pack.json'), 'Legacy mod alias');
		check(FileSystem.isDirectory('assets/mods/demo'), 'Virtual directory');
		check(FileSystem.readDirectory('assets/mods').join(',') == 'demo', 'Direct children only');
		check(File.getContent('mods/demo/pack.json') == '{"name":"demo"}', 'Asset text');
		check(File.getContent(Sys.getCwd() + '/assets/mods/demo/pack.json') == '{"name":"demo"}', 'Absolute asset path');
		check(File.getContent('assets/shared/data/test.txt') == 'library', 'Qualified library lookup');
		check(!FileSystem.exists('assets/mods/missing.json'), 'Missing file');
		reject(() ->
		{
			File.getContent('assets/mods/missing.json');
		}, 'Missing read should fail');
		reject(() ->
		{
			File.saveContent('mods/demo/pack.json', 'bad');
		}, 'Asset write should fail');
		check(AssetFiles.resolve('/unrelated/assets/mods/demo/pack.json') == null, 'External path redirected');
		File.saveContent('native-test.txt', 'native');
		check(File.getContent('native-test.txt') == 'native', 'Native IO regression');
		check(File.getContent('assets/native.txt') == 'native', 'Native backend reentrancy');
		var input = File.read('mods/demo/pack.json');
		check(input.readAll().toString() == '{"name":"demo"}', 'Native FileInput extraction');
		input.close();
		check(FileSystem.stat('mods/demo/pack.json').size == 15, 'Asset stat');
		FileSystem.deleteFile('native-test.txt');
		trace('PASS: ASTC/KTX validation and actual sys macro routing');
	}
}
