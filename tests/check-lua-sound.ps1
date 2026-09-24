param([string]$SourceFile)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $SourceFile) { $SourceFile = Join-Path $repoRoot 'source/psych/script/FunkinLua.hx' }
$sourceText = [IO.File]::ReadAllText($SourceFile)
$start = $sourceText.IndexOf('set("playSound", function(')
$end = $sourceText.IndexOf('set("stopSound", function(', $start)
if ($start -lt 0 -or $end -le $start) { throw 'Could not isolate the production playSound callback.' }
$callback = $sourceText.Substring($start, $end - $start)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('parker-lua-sound-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
# Run the actual callback against a recording sound backend, without audio devices or a game window.
$fixture = @'
import LuaSoundPlaybackTest.Paths;
import LuaSoundPlaybackTest.FlxG;
import LuaSoundPlaybackTest.FlxSound;
import LuaSoundPlaybackTest.FlxColor;
using StringTools;
class LuaSoundCallbacks
{
	public var callbacks:Map<String, Dynamic> = [];
	public var sounds:Map<String, FlxSound> = [];
	public var warnings:Array<String> = [];
	public var finished:Array<String> = [];
	public function new()
	{
__CALLBACK__
	}
	function set(name:String, callback:Dynamic):Void { callbacks.set(name, callback); }
	function getSoundMap():Map<String, FlxSound> { return sounds; }
	function luaTrace(message:String, always:Bool, deprecated:Bool, color:Int):Void { warnings.push(message); }
	function dispatchCall(name:String, args:Array<Dynamic>):Void
	{
		if (name != 'onSoundFinished') throw 'Unexpected callback: ' + name;
		finished.push(args[0]);
	}
}
'@
[IO.File]::WriteAllText((Join-Path $testRoot 'LuaSoundCallbacks.hx'), $fixture.Replace('__CALLBACK__', $callback))
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LuaSoundPlaybackTest.hx') -Destination $testRoot
& haxe -cp $testRoot -main LuaSoundPlaybackTest --interp
exit $LASTEXITCODE
