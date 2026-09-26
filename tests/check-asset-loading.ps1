$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('parker-assets-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$testRoot/backend", "$testRoot/lime/utils", "$testRoot/lime/system" | Out-Null
foreach ($name in @('ASTCData', 'AssetFiles', 'AssetFilesMacro')) {
    Copy-Item -LiteralPath "$repoRoot/source/backend/$name.hx" -Destination "$testRoot/backend/$name.hx"
}
Copy-Item -LiteralPath "$PSScriptRoot/AssetLoadingTest.hx" -Destination $testRoot
# Exercise production sys hooks against a packaged-resource backend without a GPU or APK.
@'
package lime.utils;
class Assets {
    public static var libraries:Map<String, TestLibrary> = [
        'default' => new TestLibrary(['assets/mods/demo/pack.json', 'assets/native.txt']),
        'shared' => new TestLibrary(['assets/shared/data/test.txt'])
    ];
    public static function getBytes(id:String):haxe.io.Bytes {
        return switch (id) {
            case 'assets/mods/demo/pack.json': haxe.io.Bytes.ofString('{"name":"demo"}');
            case 'shared:assets/shared/data/test.txt': haxe.io.Bytes.ofString('library');
            case 'assets/native.txt': sys.io.File.getBytes('native-test.txt');
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
