@echo off
setlocal

REM 定义缓存文件夹路径
set "CACHE_DIR=%USERPROFILE%\.haxelib\cache"

REM 备份缓存文件夹
set "BACKUP_DIR=%CD%\backup_cache"
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
xcopy /E /I "%CACHE_DIR%" "%BACKUP_DIR%"

REM 清理旧的缓存文件（可选）
REM del /Q /S "%CACHE_DIR%\*.*" > nul 2>&1

echo Cache files have been backed up to %BACKUP_DIR%.

REM 执行 Lime 构建
call lime build windows -D release

pause
endlocal