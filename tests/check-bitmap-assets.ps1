$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('parker-bitmap-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$testRoot/backend", "$testRoot/openfl/utils", "$testRoot/openfl/display", "$testRoot/lime/utils" | Out-Null
foreach ($name in @('BitmapAssetCompat', 'BitmapAssetMacro')) {
    Copy-Item -LiteralPath "$repoRoot/source/backend/$name.hx" -Destination "$testRoot/backend/$name.hx"
}
# Retain the real compiler resource hook, with a decoder/cache double and a manifest whose PNGs were stripped.
@'
package openfl.utils;
class Assets {
    public static var cache = new TestCache();
    public static function exists(id:String, type:AssetType = null):Bool { return false; }
    public static function getBitmapData(id:String, useCache:Bool = true):openfl.display.BitmapData { return null; }
}
class TestCache {
    public var enabled:Bool = true;
    var bitmaps:Map<String, openfl.display.BitmapData> = [];
    public function new() {}
    public function hasBitmapData(id:String):Bool { return bitmaps.exists(id); }
    public function getBitmapData(id:String):openfl.display.BitmapData { return bitmaps.get(id); }
    public function setBitmapData(id:String, bitmap:openfl.display.BitmapData):Void { bitmaps.set(id, bitmap); }
}
'@ | Set-Content -LiteralPath "$testRoot/openfl/utils/Assets.hx" -Encoding utf8
@'
package openfl.utils;
enum abstract AssetType(String) { var IMAGE = 'IMAGE'; var TEXT = 'TEXT'; }
'@ | Set-Content -LiteralPath "$testRoot/openfl/utils/AssetType.hx" -Encoding utf8
@'
package openfl.display;
class BitmapData {
    public var width:Int = 16;
    public var height:Int = 16;
    public var readable:Bool;
    public function new(readable:Bool) { this.readable = readable; }
    public static function fromBytes(bytes:haxe.io.Bytes):BitmapData {
        if (bytes.sub(0, 8).toHex() != '89504e470d0a1a0a') throw 'Expected original PNG bytes';
        return new BitmapData(true);
    }
}
'@ | Set-Content -LiteralPath "$testRoot/openfl/display/BitmapData.hx" -Encoding utf8
@'
package lime.utils;
class Assets {
    public static function exists(id:String, type:openfl.utils.AssetType = null):Bool { return id == 'assets/test.astc.ktx' && type == null; }
    public static function getBytes(id:String):haxe.io.Bytes { return haxe.io.Bytes.ofString('compressed'); }
}
'@ | Set-Content -LiteralPath "$testRoot/lime/utils/Assets.hx" -Encoding utf8
@'
package backend;
class ASTCBitmapData {
    public static function supported():Bool { return true; }
    public static function fromBytes(bytes:haxe.io.Bytes):openfl.display.BitmapData { return new openfl.display.BitmapData(false); }
}
'@ | Set-Content -LiteralPath "$testRoot/backend/ASTCBitmapData.hx" -Encoding utf8
@'
import openfl.utils.Assets;
class BitmapAssetTest {
    static function main() {
        var arrow = 'flixel/flixel-ui/img/tooltip_arrow.png';
        if (!Assets.exists(arrow, IMAGE)) throw 'Stripped tooltip not discoverable';
        if (Assets.exists(arrow, TEXT)) throw 'Image reported as text';
        var bitmap = Assets.getBitmapData(arrow);
        if (bitmap == null || !bitmap.readable) throw 'Tooltip/nine-slice needs readable pixels';
        if (Assets.getBitmapData(arrow) != bitmap) throw 'Bitmap cache bypassed';
        if (Assets.getBitmapData(arrow, false) == bitmap) throw 'useCache=false ignored';
        bitmap.width = 0;
        if (Assets.getBitmapData(arrow).width == 0) throw 'Disposed cache entry reused';
        if (!Assets.getBitmapData('default:' + arrow).readable) throw 'Default library alias';
        if (!Assets.exists('assets/test.png', IMAGE)) throw 'Compressed PNG alias';
        if (Assets.getBitmapData('assets/test.png').readable) throw 'ASTC path did not use GPU loader';
        if (Assets.getBitmapData('missing.png') != null) throw 'Missing image changed behavior';
        trace('PASS: real OpenFL asset hook, readable UI resources, ASTC aliases and cache');
    }
}
'@ | Set-Content -LiteralPath "$testRoot/BitmapAssetTest.hx" -Encoding utf8
$flixelPaths = & haxelib path flixel
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve flixel' }
$uiPaths = & haxelib path flixel-ui
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve flixel-ui' }
$haxeArgs = @()
foreach ($libraryPath in @($flixelPaths) + @($uiPaths)) {
    if ($libraryPath -match 'flixel[^/\\]*[/\\][^/\\]*[/\\]?$' -and (Test-Path -LiteralPath $libraryPath -PathType Container)) {
        $haxeArgs += @('-cp', $libraryPath)
    }
}
$haxeArgs += @('-cp', $testRoot, '--macro', 'backend.BitmapAssetMacro.install()', '-main', 'BitmapAssetTest', '--interp')
& haxe @haxeArgs
exit $LASTEXITCODE
