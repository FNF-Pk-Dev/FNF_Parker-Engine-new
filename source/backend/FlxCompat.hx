package backend;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;

/**
 * Flixel版本兼容层
 * 支持 flixel 5.x 和 6.x 的API差异
 * 
 * 使用方法:
 * - FlxCompat.defaultCameras - 获取默认相机列表
 * - FlxCompat.angleBetween(p1, p2) - 计算两点角度
 */
class FlxCompat
{
	/**
	 * 检测是否为Flixel 6.x
	 * 6.0版本中 FlxCamera.defaultCameras 变更为 FlxG.cameras.defaultCameras
	 */
	public static var isV6(get, never):Bool;
	
	static function get_isV6():Bool
	{
		#if !flixel_5
		return true; // 默认6.x
		#else
		return false;
		#end
	}

	/**
	 * 获取默认相机列表
	 * 5.x: FlxCamera.defaultCameras
	 * 6.x: FlxG.cameras.list 默认包含默认相机
	 */
	public static var defaultCameras(get, never):Array<FlxCamera>;
	
	static function get_defaultCameras():Array<FlxCamera>
	{
		#if (flixel >= "6.0.0")
		// 6.x 使用 FlxG.cameras.list 获取所有相机，包含默认相机
		return FlxG.cameras.list;
		#else
		return FlxCamera.defaultCameras;
		#end
	}

	/**
	 * 计算两点之间的角度(度)
	 * 5.x: FlxPoint.angleBetween()
	 * 6.x: 已移除，使用 Math.atan2() 替代
	 * @param p1 起点
	 * @param p2 终点
	 * @return 角度(-180到180)
	 */
	public static function angleBetween(p1:FlxPoint, p2:FlxPoint):Float
	{
		#if (flixel >= "6.0.0")
		return Math.atan2(p2.y - p1.y, p2.x - p1.x) * 180 / Math.PI;
		#else
		return p1.angleBetween(p2);
		#end
	}

	/**
	 * 计算两点之间的角度(弧度)
	 * @param p1 起点
	 * @param p2 终点
	 * @return 角度(-π到π)
	 */
	public static function angleBetweenRadians(p1:FlxPoint, p2:FlxPoint):Float
	{
		#if (flixel >= "6.0.0")
		return Math.atan2(p2.y - p1.y, p2.x - p1.x);
		#else
		return p1.angleBetween(p2) * Math.PI / 180;
		#end
	}

	/**
	 * 创建带边框的矩形图形(用于FlxInputText等)
	 * 5.x: 支持 SHADOW_XY borderStyle
	 * 6.x: 可能需要手动实现
	 */
	public static function makeBorderGraphic(sprite:flixel.FlxSprite, width:Int, height:Int, 
		borderColor:FlxColor, borderSize:Int, caretColor:FlxColor, caretWidth:Int, caretHeight:Int,
		borderStyle:String = "NONE"):Void
	{
		#if (flixel >= "6.0.0")
		// 6.x 不支持 SHADOW_XY，手动实现
		switch (borderStyle)
		{
			case "NONE":
				sprite.makeGraphic(width, height, caretColor);
				
			case "SHADOW":
				var cw = width + borderSize;
				var ch = height + borderSize;
				sprite.makeGraphic(cw, ch, FlxColor.TRANSPARENT);
				// 绘制阴影
				var shadowRect = new flash.geom.Rectangle(borderSize, borderSize, width, height);
				sprite.pixels.fillRect(shadowRect, borderColor);
				// 绘制主体
				var mainRect = new flash.geom.Rectangle(0, 0, width, height);
				sprite.pixels.fillRect(mainRect, caretColor);
				
			case "OUTLINE_FAST", "OUTLINE":
				var cw = width + borderSize * 2;
				var ch = height + borderSize * 2;
				sprite.makeGraphic(cw, ch, borderColor);
				var innerRect = new flash.geom.Rectangle(borderSize, borderSize, width, height);
				sprite.pixels.fillRect(innerRect, caretColor);
				
			default:
				sprite.makeGraphic(width, height, caretColor);
		}
		#else
		// 5.x 使用原生方法
		// 这里不做处理，让原生代码处理
		#end
	}
}
