package backend;

import haxe.io.Bytes;
import haxe.io.BytesInput;

/** KTX 1 / raw ASTC, restricted to a single 2D image. Data stays compressed. */
class ASTCData
{
	public var width:Int;
	public var height:Int;
	public var format:Int;
	public var offset:Int;
	public var length:Int;

	static final BLOCKS = [
		[4, 4], [5, 4], [5, 5], [6, 5], [6, 6], [8, 5], [8, 6], [8, 8], [10, 5], [10, 6], [10, 8], [10, 10], [12, 10], [12, 12]];

	public function new(bytes:Bytes)
	{
		if (bytes == null || bytes.length < 16)
			throw 'Truncated ASTC header';
		var block = -1;
		if (bytes.getInt32(0) == 0x5CA1AB13)
		{
			for (i in 0...BLOCKS.length)
				if (bytes.get(4) == BLOCKS[i][0] && bytes.get(5) == BLOCKS[i][1])
					block = i;
			if (bytes.get(6) != 1 || u24(bytes, 13) != 1)
				throw 'Only 2D ASTC textures are supported';
			width = u24(bytes, 7);
			height = u24(bytes, 10);
			format = 0x93B0 + block;
			offset = 16;
			length = bytes.length - offset;
		}
		else
		{
			var signature = Bytes.ofHex('ab4b5458203131bb0d0a1a0a');
			if (bytes.length < 68 || bytes.sub(0, 12).compare(signature) != 0)
				throw 'Expected a KTX 1 ASTC texture';
			var input = new BytesInput(bytes);
			input.position = 12;
			var endian = input.readInt32();
			if (endian != 0x04030201 && endian != 0x01020304)
				throw 'Invalid KTX endianness';
			input.bigEndian = endian == 0x01020304;
			var type = input.readInt32();
			var typeSize = input.readInt32();
			var glFormat = input.readInt32();
			format = input.readInt32();
			var baseFormat = input.readInt32();
			width = input.readInt32();
			height = input.readInt32();
			var depth = input.readInt32();
			var arrays = input.readInt32();
			var faces = input.readInt32();
			var mips = input.readInt32();
			var metadata = input.readInt32();
			block = format - 0x93B0;
			if (type != 0 || typeSize != 1 || glFormat != 0 || baseFormat != 0x1908 || depth != 0 || arrays != 0 || faces != 1 || mips < 0 || mips > 32)
				throw 'Unsupported KTX layout (expected linear RGBA ASTC, single 2D image)';
			if (metadata < 0 || metadata > bytes.length - 68 || metadata % 4 != 0)
				throw 'Invalid KTX metadata length';
			// OpenFL uses top-left UVs. Reject explicitly inverted images rather than silently flipping atlases.
			var end = 64 + metadata;
			while (input.position < end)
			{
				if (end - input.position < 4)
					throw 'Truncated KTX metadata';
				var size = input.readInt32();
				if (size <= 0 || size > end - input.position)
					throw 'Invalid KTX metadata entry';
				var entry = input.readString(size);
				if (StringTools.startsWith(entry, 'KTXorientation' + String.fromCharCode(0))
					&& (entry.indexOf('S=l') >= 0 || entry.indexOf('T=u') >= 0))
					throw 'Export KTX with orientation S=r,T=d';
				input.position += (4 - size % 4) % 4;
				if (input.position > end)
					throw 'Invalid KTX metadata padding';
			}
			length = input.readInt32();
			offset = input.position;
		}
		if (block < 0 || block >= BLOCKS.length || width <= 0 || height <= 0)
			throw 'Invalid ASTC dimensions or block format';
		var expected:Float = Math.ceil(width / BLOCKS[block][0]) * Math.ceil(height / BLOCKS[block][1]) * 16;
		if (length <= 0 || length != expected || length > bytes.length - offset)
			throw 'Truncated or invalid ASTC block data';
	}

	static inline function u24(bytes:Bytes, offset:Int):Int
	{
		return bytes.get(offset) | (bytes.get(offset + 1) << 8) | (bytes.get(offset + 2) << 16);
	}
}
