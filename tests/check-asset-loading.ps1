$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('parker-assets-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$testRoot/backend", "$testRoot/lime/utils", "$testRoot/lime/system", "$testRoot/openfl/text", "$testRoot/openfl/utils" | Out-Null
foreach ($name in @('ASTCData', 'AssetFiles', 'AssetFilesMacro')) {
    Copy-Item -LiteralPath "$repoRoot/source/backend/$name.hx" -Destination "$testRoot/backend/$name.hx"
}
Copy-Item -LiteralPath "$PSScriptRoot/AssetLoadingTest.hx" -Destination $testRoot
# Exercise production sys hooks against a packaged-resource backend without a GPU or APK.
@'
package lime.utils;
class Assets {
    public static var libraries:Map<String, TestLibrary> = [
        'default' => new TestLibrary(['assets/mods/demo/pack.json', 'assets/native.txt',
            'assets/mods/demo/data/NeurosesH-mix/neurosesh-mix-safe.json',
            'assets/mods/demo/data/NeurosesH-mix/neurosesh-mix-canon.json',
            'assets/mods/demo/Case.txt', 'assets/mods/demo/case.txt',
            'assets/mods/demo/fonts/other.ttf', 'assets/mods/demo/fonts/info.otf', 'assets/mods/demo/fonts/binary.ttf']),
        'shared' => new TestLibrary(['assets/shared/data/test.txt', 'assets/shared/fonts/library.ttf'])
    ];
    public static function getBytes(id:String):haxe.io.Bytes {
        return switch (id) {
            case 'assets/mods/demo/pack.json': haxe.io.Bytes.ofString('{"name":"demo"}');
            case 'shared:assets/shared/data/test.txt': haxe.io.Bytes.ofString('library');
            case 'assets/native.txt': sys.io.File.getBytes('native-test.txt');
            case 'assets/mods/demo/data/NeurosesH-mix/neurosesh-mix-safe.json': haxe.io.Bytes.ofString('safe chart');
            case 'assets/mods/demo/data/NeurosesH-mix/neurosesh-mix-canon.json': haxe.io.Bytes.ofString('canon chart');
            case 'assets/mods/demo/Case.txt': haxe.io.Bytes.ofString('upper');
            case 'assets/mods/demo/case.txt': haxe.io.Bytes.ofString('lower');
            case 'assets/mods/demo/fonts/binary.ttf': haxe.io.Bytes.ofString('Binary Font');
            // Generated FONT classes are not Bytes: reproduce Lime's getBytes failure.
            case 'assets/mods/demo/fonts/other.ttf', 'assets/mods/demo/fonts/info.otf', 'shared:assets/shared/fonts/library.ttf':
                throw 'Invalid Cast: Font to Bytes';
            default: throw 'Wrong asset ID: ' + id;
        };
    }
}
class TestLibrary {
    var ids:Array<String>;
    public function new(ids:Array<String>) { this.ids = ids; }
    public function list(type:Dynamic):Array<String> { return ids; }
}
'@ | Set-Content -LiteralPath "$testRoot/lime/utils/Assets.hx" -Encoding utf8
@'
package lime.system;
class System {
    public static var applicationStorageDirectory:String = Sys.getCwd() + '/storage/';
}
'@ | Set-Content -LiteralPath "$testRoot/lime/system/System.hx" -Encoding utf8
@'
package openfl.text;
class Font {
    public static var nativeLoadCount:Int = 0;
    public static var lastNativePath:String;
    public var fontName:String;
    public function new(name:String) { fontName = name; }
    public static function fromFile(path:String):Font {
        nativeLoadCount++;
        lastNativePath = path;
        return new Font(sys.io.File.getBytes(path).toString());
    }
}
'@ | Set-Content -LiteralPath "$testRoot/openfl/text/Font.hx" -Encoding utf8
@'
package openfl.utils;
enum abstract AssetType(String) {
    var FONT = "FONT";
}
'@ | Set-Content -LiteralPath "$testRoot/openfl/utils/AssetType.hx" -Encoding utf8
@'
package openfl.utils;
class Assets {
    static var fonts:Map<String, openfl.text.Font> = [
        'assets/mods/demo/fonts/other.ttf' => new openfl.text.Font('Unityped Regular'),
        'assets/mods/demo/fonts/info.otf' => new openfl.text.Font('Info Font'),
        'shared:assets/shared/fonts/library.ttf' => new openfl.text.Font('Library Font')
    ];
    public static function exists(id:String, type:AssetType):Bool {
        return type == FONT && fonts.exists(id);
    }
    public static function getFont(id:String):openfl.text.Font {
        return fonts.get(id);
    }
}
'@ | Set-Content -LiteralPath "$testRoot/openfl/utils/Assets.hx" -Encoding utf8
Push-Location $testRoot
try {
    & haxe -cp $testRoot -D ASSET_MODS --macro 'backend.AssetFilesMacro.install()' -main AssetLoadingTest -neko asset-tests.n
    $result = $LASTEXITCODE
    if ($result -eq 0) {
        & neko asset-tests.n
        $result = $LASTEXITCODE
    }
} finally {
    Pop-Location
}
exit $result
