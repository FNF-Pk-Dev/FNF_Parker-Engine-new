$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('parker-animate-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$testRoot/backend" | Out-Null
Copy-Item -LiteralPath "$repoRoot/source/animateatlas" -Destination $testRoot -Recurse
Copy-Item -LiteralPath "$repoRoot/source/backend/BitmapReadback.hx" -Destination "$testRoot/backend/BitmapReadback.hx"
Copy-Item -LiteralPath "$PSScriptRoot/AnimateAtlasTest.hx" -Destination $testRoot
'import backend.BitmapReadback;' | Set-Content -LiteralPath "$testRoot/import.hx" -Encoding utf8
# Fixture assets only: all rendering, pixel operations and frame packing use the actual libraries.
@'
import flixel.graphics.FlxGraphic;
class Paths {
    public static var graphic:FlxGraphic;
    public static var animation:String;
    public static var atlas:String;
    public static function image(key:String, library:String, allowGPU:Bool):FlxGraphic { return graphic; }
    public static function fileExists(path:String, type:openfl.utils.AssetType):Bool { return true; }
    public static function getTextFromFile(path:String):String {
        return StringTools.endsWith(path, 'Animation.json') ? animation : atlas;
    }
}
'@ | Set-Content -LiteralPath "$testRoot/Paths.hx" -Encoding utf8
& haxe -cp $testRoot -lib flixel -lib openfl -lib lime -D lime-cairo -D lime-native -D lime-opengl -D openfl-native -D FLX_NO_DEBUG -D lime_use_old_deltatime -main AnimateAtlasTest -neko "$testRoot/test.n"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& neko "$testRoot/test.n"
exit $LASTEXITCODE
