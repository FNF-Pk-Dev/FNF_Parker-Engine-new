$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = [IO.File]::ReadAllText((Join-Path $repoRoot 'source/android/StorageUtil.hx'))
$start = $source.IndexOf('public static function getStorageDirectory(')
$end = $source.IndexOf('public static function saveContent(', $start)
if ($start -lt 0 -or $end -le $start) { throw 'Could not isolate getStorageDirectory.' }
$method = $source.Substring($start, $end - $start)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('parker-storage-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$fixture = @'
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
class StorageDirectoryTest
{
	public static var rootDir:String = Sys.getCwd() + '/private/';
__METHOD__
	static function check(ok:Bool, message:String):Void
	{
		if (!ok) throw message;
	}
	static function main():Void
	{
		#if ASSET_MODS
		check(!FileSystem.exists(rootDir), 'Fixture must start without the private directory');
		check(getStorageDirectory() == rootDir, 'Packaged mode selected external storage');
		check(FileSystem.isDirectory(rootDir), 'Private directory was not created');
		check(!FileSystem.exists(rootDir + 'storagetype.txt'), 'Packaged mode wrote a legacy storage preference');
		File.saveContent(rootDir + 'storagetype.txt', 'EXTERNAL');
		check(getStorageDirectory(true) == rootDir, 'Old EXTERNAL preference changed packaged storage');
		check(File.getContent(rootDir + 'storagetype.txt') == 'EXTERNAL', 'Old preference was overwritten');
		Sys.setCwd(getStorageDirectory());
		File.saveContent('modsList.txt', 'demo|1');
		check(File.getContent('modsList.txt') == 'demo|1', 'Startup working directory is not writable');
		#else
		FileSystem.createDirectory(rootDir);
		check(getStorageDirectory() == '/external/', 'Legacy mode no longer uses selected external storage');
		check(File.getContent(rootDir + 'storagetype.txt') == 'EXTERNAL', 'Legacy first-run default changed');
		check(getStorageDirectory(true) == '/forced/', 'Legacy forced-path behavior changed');
		#end
		trace('PASS: mobile storage selection and startup directory');
	}
}
class StorageType
{
	public static function fromStr(value:String):String { return '/external'; }
	public static function fromStrForce(value:String):String { return '/forced'; }
}
'@
[IO.File]::WriteAllText((Join-Path $testRoot 'StorageDirectoryTest.hx'), $fixture.Replace('__METHOD__', $method))
foreach ($mode in @('packaged', 'legacy')) {
    $runRoot = Join-Path $testRoot $mode
    New-Item -ItemType Directory -Path $runRoot | Out-Null
    Push-Location $runRoot
    try {
        $haxeArgs = @('-cp', $testRoot, '-D', 'android', '-main', 'StorageDirectoryTest', '--interp')
        if ($mode -eq 'packaged') { $haxeArgs += @('-D', 'ASSET_MODS') }
        & haxe @haxeArgs
        if ($LASTEXITCODE -ne 0) { throw "Storage test failed: $mode" }
    } finally {
        Pop-Location
    }
}
