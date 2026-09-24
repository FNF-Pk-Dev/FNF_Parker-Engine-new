$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('parker-es-steps-' + [Guid]::NewGuid().ToString('N'))
$moduleDir = Join-Path $testRoot 'psych/script'
New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null
# Isolate the pure scheduler from source/import.hx and the game's native dependencies.
Copy-Item -LiteralPath (Join-Path $repoRoot 'source/psych/script/ESStepEvents.hx') -Destination $moduleDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ESStepEventsTest.hx') -Destination $testRoot
& haxe -cp $testRoot -main ESStepEventsTest --interp
exit $LASTEXITCODE
