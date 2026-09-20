package animateatlas;

import animateatlas.JSONData.AnimationData;

/**
 * Converts Adobe Animate 2019+ short-key Animation.json data (AN / SD / MD)
 * into the long-key format (ANIMATION / SYMBOL_DICTIONARY / metadata) that
 * SpriteAnimationLibrary understands. Key meanings follow flxanimate's
 * flxanimate/data/AnimationData.hx abstracts.
 */
class ShortKeyConverter
{
	public static function isShortFormat(data:Dynamic):Bool
	{
		return data != null && (Reflect.hasField(data, 'AN') || Reflect.hasField(data, 'SD'));
	}

	public static function normalize(data:Dynamic):AnimationData
	{
		var result:Dynamic = {};

		if (data.AN != null)
			result.ANIMATION = convertSymbol(data.AN);
		else
			result.ANIMATION = {SYMBOL_name: '', TIMELINE: {LAYERS: []}};

		var symbols:Array<Dynamic> = [];
		if (data.SD != null && data.SD.S != null)
		{
			for (symbol in (data.SD.S : Array<Dynamic>))
				symbols.push(convertSymbol(symbol));
		}
		result.SYMBOL_DICTIONARY = {Symbols: symbols};

		if (data.MD != null && data.MD.FRT != null)
			result.metadata = {framerate: data.MD.FRT};

		return result;
	}

	static function convertSymbol(symbol:Dynamic):Dynamic
	{
		var converted:Dynamic = {SYMBOL_name: symbol.SN};
		if (symbol.N != null)
			converted.name = symbol.N;

		var layers:Array<Dynamic> = [];
		if (symbol.TL != null && symbol.TL.L != null)
		{
			for (layer in (symbol.TL.L : Array<Dynamic>))
				layers.push(convertLayer(layer));
		}
		converted.TIMELINE = {LAYERS: layers};
		return converted;
	}

	static function convertLayer(layer:Dynamic):Dynamic
	{
		var frames:Array<Dynamic> = [];
		if (layer.FR != null)
		{
			for (frame in (layer.FR : Array<Dynamic>))
				frames.push(convertFrame(frame));
		}
		return {Layer_name: layer.LN, Frames: frames};
	}

	static function convertFrame(frame:Dynamic):Dynamic
	{
		var elements:Array<Dynamic> = [];
		if (frame.E != null)
		{
			for (element in (frame.E : Array<Dynamic>))
				elements.push(convertElement(element));
		}

		var converted:Dynamic = {index: frame.I, duration: frame.DU == null ? 1 : frame.DU, elements: elements};
		if (frame.N != null)
			converted.name = frame.N;
		return converted;
	}

	static function convertElement(element:Dynamic):Dynamic
	{
		if (element.SI != null)
			return {SYMBOL_Instance: convertSymbolInstance(element.SI)};

		if (element.ASI != null)
		{
			var sprite:Dynamic = {name: element.ASI.N, Position: {x: 0, y: 0}};
			if (element.ASI.M3D != null)
				sprite.Matrix3D = convertMatrix(element.ASI.M3D);
			return {ATLAS_SPRITE_instance: sprite};
		}

		return
		{
		};
	}

	static function convertSymbolInstance(instance:Dynamic):Dynamic
	{
		var converted:Dynamic = {
			SYMBOL_name: instance.SN,
			Instance_Name: instance.IN == null ? '' : instance.IN,
			symbolType: convertSymbolType(instance.ST),
			firstFrame: instance.FF == null ? 0 : instance.FF,
			Matrix3D: convertMatrix(instance.M3D)
		};

		if (instance.TRP != null)
			converted.transformationPoint = {x: instance.TRP.x, y: instance.TRP.y};
		else
			converted.transformationPoint = {x: 0, y: 0};

		if (instance.LP != null)
			converted.loop = convertLoop(instance.LP);
		if (instance.C != null)
			converted.color = convertColor(instance.C);
		if (instance.F != null)
			converted.filters = convertFilters(instance.F);

		return converted;
	}

	static function convertSymbolType(type:String):String
	{
		return switch (type)
		{
			case 'G': 'graphic';
			case 'MC': 'movieclip';
			case 'B': 'button';
			default: type;
		}
	}

	static function convertLoop(loop:String):String
	{
		return switch (loop)
		{
			case 'LP': 'loop';
			case 'PO': 'playonce';
			case 'SF': 'singleframe';
			default: loop;
		}
	}

	static function convertMatrix(matrix:Dynamic):Dynamic
	{
		if ((matrix is Array))
		{
			var values:Array<Float> = matrix;
			if (values.length >= 16)
			{
				return {
					m00: values[0],
					m01: values[1],
					m02: values[2],
					m03: values[3],
					m10: values[4],
					m11: values[5],
					m12: values[6],
					m13: values[7],
					m20: values[8],
					m21: values[9],
					m22: values[10],
					m23: values[11],
					m30: values[12],
					m31: values[13],
					m32: values[14],
					m33: values[15]
				};
			}
		}
		else if (matrix != null)
			return matrix;

		return {
			m00: 1,
			m01: 0,
			m02: 0,
			m03: 0,
			m10: 0,
			m11: 1,
			m12: 0,
			m13: 0,
			m20: 0,
			m21: 0,
			m22: 1,
			m23: 0,
			m30: 0,
			m31: 0,
			m32: 0,
			m33: 1
		};
	}

	static function convertColor(color:Dynamic):Dynamic
	{
		var converted:Dynamic = {mode: convertColorMode(color.M)};
		if (color.RM != null)
			converted.RedMultiplier = color.RM;
		if (color.GM != null)
			converted.greenMultiplier = color.GM;
		if (color.BM != null)
			converted.blueMultiplier = color.BM;
		if (color.AM != null)
			converted.alphaMultiplier = color.AM;
		if (color.RO != null)
			converted.redOffset = color.RO;
		if (color.GO != null)
			converted.greenOffset = color.GO;
		if (color.BO != null)
			converted.blueOffset = color.BO;
		if (color.AO != null)
			converted.AlphaOffset = color.AO;
		// Tint (TC/TM) and Brightness (BRT) have no equivalent in ColorData
		return converted;
	}

	static function convertColorMode(mode:String):String
	{
		return switch (mode)
		{
			case 'T': 'Tint';
			case 'CA': 'Alpha';
			case 'CBRT': 'Brightness';
			case 'AD': 'Advanced';
			default: mode;
		}
	}

	static function convertFilters(filters:Dynamic):Dynamic
	{
		var converted:Dynamic = {};
		if (filters.BLF != null)
		{
			converted.BlurFilter = {
				blurX: filters.BLF.BLX,
				blurY: filters.BLF.BLY,
				quality: filters.BLF.Q
			};
		}
		if (filters.GF != null)
		{
			converted.GlowFilter = {
				blurX: filters.GF.BLX,
				blurY: filters.GF.BLY,
				color: parseHexColor(filters.GF.C),
				alpha: filters.GF.A,
				quality: filters.GF.Q,
				strength: filters.GF.STR,
				knockout: filters.GF.KK,
				inner: filters.GF.IN
			};
		}
		return converted;
	}

	static function parseHexColor(color:String):Int
	{
		if (color == null)
			return 0;
		if (color.charAt(0) == '#')
			color = color.substr(1);
		var value:Null<Int> = Std.parseInt('0x$color');
		return value == null ? 0 : value;
	}
}
