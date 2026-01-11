# Friday Night Funkin' - Parker Engine

## 项目概述

**Parker Engine** 是基于 Psych Engine 开发的一个 Friday Night Funkin' (FNF) 游戏引擎分支。该引擎比原版 FNF 更加灵活和可扩展，支持模组加载、多脚本语言、关卡编辑器等功能。

### 核心信息

| 属性 | 值 |
|------|-----|
| 项目类型 | Haxe 游戏引擎 (2D) |
| 主语言 | Haxe |
| 游戏框架 | HaxeFlixel + OpenFL + Lime |
| 版本 | 0.2.8 |
| 包名 | com.laoan.pkengine |
| 目标平台 | Windows, Android, HTML5, Linux, macOS, Switch |

## 技术栈

### 核心依赖

```json
{
  "lime": "8.0.2",
  "openfl": "9.2.2",
  "flixel": "latest (5.x/6.x)",
  "flixel-addons": "3.0.2",
  "flixel-ui": "latest"
}
```

### 脚本支持

- **HScript** - Haxe 脚本
- **Lua (linc_luajit)** - Lua 脚本
- **Python (hxpy)** - Python 脚本

### 扩展功能

- **hxCodec/hxvlc** - 视频播放
- **discord_rpc** - Discord RPC 集成
- **flxgif** - GIF 动画支持

## 项目结构

```
source/
├── Main.hx                 # 程序入口点
├── StartupState.hx         # 启动状态
├── FNFGame.hx              # 扩展 FlxGame，支持脚本状态覆盖
├── import.hx               # 全局导入 (使用 using 语法扩展)
│
├── backend/                # 核心后端模块
│   ├── FlxCompat.hx        # Flixel 5.x/6.x 兼容层
│   ├── ClientPrefs.hx      # 客户端偏好设置
│   ├── Paths.hx            # 资源路径管理
│   ├── Highscore.hx        # 最高分系统
│   ├── MusicBeatState.hx   # 音乐节拍状态基类
│   ├── Discord.hx          # Discord RPC 集成
│   ├── FlxUIDropDownMenuCustom.hx  # 自定义下拉菜单
│   ├── game/               # 游戏系统
│   │   └── Achievements.hx # 成就系统
│   ├── songs/              # 歌曲系统
│   │   └── Song.hx
│   ├── obj/                # 对象系统
│   └── player/             # 玩家控制系统
│       └── Controls.hx
│
├── states/                 # 游戏状态
│   ├── TitleState.hx       # 标题画面
│   ├── LoadingState.hx     # 加载画面
│   ├── game/
│   │   └── PlayState.hx    # 主要游戏状态
│   └── menu/
│       ├── MainMenuState.hx    # 主菜单
│       ├── StoryMenuState.hx   # 故事模式菜单
│       ├── FreeplayState.hx    # 自由模式
│       ├── CreditsState.hx     # 制作人员名单
│       └── ModsMenuState.hx    # 模组菜单
│
├── substates/              # 子状态
├── cutscenes/              # 过场动画
├── editors/                # 编辑器
│   ├── ChartEditor.hx      # 谱面编辑器
│   └── MenuCharacterEditor.hx
├── modchart/               # Mod 图表系统
│   ├── ModManager.hx       # Mod 管理器
│   ├── Modifier.hx         # 修饰器基类
│   └── events/             # 自定义事件
├── script/                 # 脚本系统
│   ├── hscript/            # HScript 实现
│   ├── FunkinHScript.hx    # FNF HScript 包装
│   ├── FunkinLScript.hx    # Lua 脚本
│   └── FunkinPython.hx     # Python 脚本
├── shaders/                # 着色器
├── android/                # Android 特定代码
│   └── backend/
│       ├── AndroidBackHandler.hx
│       └── SUtil.hx
└── flixel/                 # 自定义 Flixel 组件
    └── addons/ui/
        └── FlxInputText.hx

assets/                     # 游戏资源
├── preload/                # 预加载资源
│   ├── images/
│   ├── music/
│   ├── sounds/
│   ├── characters/
│   ├── stages/
│   ├── data/
│   └── weeks/
├── shared/                 # 共享资源
├── songs/                  # 歌曲资源
├── fonts/                  # 字体
└── videos/                 # 视频

example_mods/               # 示例模组结构
├── pack.json               # 模组配置
├── characters/
├── custom_events/
├── custom_notetypes/
├── data/
├── scripts/
├── shaders/
├── images/
├── music/
├── sounds/
├── videos/
├── stages/
├── weeks/
└── global.hx               # 全局脚本

export/                     # 构建输出
├── debug/
└── release/
```

## 构建与运行

### 环境要求

- **Haxe** 4.2.0+ (推荐最新版本)
- **JDK 8** (Android 构建)
- **Android Studio + NDK r15c** (Android)

### 安装依赖

```bash
# 安装 Haxe 和 HMM
haxelib install hmm
haxelib run hmm install

# Android 特定依赖
haxelib git extension-androidtools https://github.com/FNF-Pk-Dev/extension-androidtools.git
haxelib git hxCodec https://github.com/FNF-Pk-Dev/hxCodec.git
haxelib git linc_luajit https://github.com/mcagabe19/linc_luajit-legacy.git
```

### 构建命令

```bash
# Windows 桌面
lime test windows
lime build windows -final

# Android
lime test android
lime build android -final

# HTML5
lime test html5
lime build html5 -final

# Linux
lime test linux
lime build linux -final

# 调试构建
lime test windows -debug
```

### Android 构建 APK 位置

```
export/release/android/bin/app/build/outputs/apk/debug/
```

## 开发约定

### 编码风格

- 使用 **驼峰命名法** (camelCase)
- 类名使用 **帕斯卡命名法** (PascalCase)
- 常量使用 **全大写下划线** (UPPER_SNAKE_CASE)
- 导入使用 `using StringTools` 等扩展方法

### 状态系统

```haxe
// 音乐节拍状态基类
class MusicBeatState extends FlxState {
    // 继承此类的状态会自动同步音乐节拍
}

// 自定义状态切换
FlxG.switchState(new PlayState());
```

### 资源加载

```haxe
// 使用 Paths 类加载资源
var sound = Paths.sound('confirmMenu');
var graphic = Paths.image('characters/bf');
var music = Paths.music('freakyMenu');
```

### 玩家输入

```haxe
// 使用 Controls 类
var controls = new PlayerControls();
// 或使用预定义控制
FlxG.keys.justPressed.UP;
FlxG.keys.pressed.LEFT;
```

## 模组系统

### 模组结构

```
mods/[模组名]/
├── pack.json           # 模组信息
├── images/             # 图片资源
├── music/              # 音乐
├── sounds/             # 音效
├── characters/         # 角色定义
├── stages/             # 舞台
├── songs/              # 歌曲
├── data/               # 数据文件
├── custom_events/      # 自定义事件
├── custom_notetypes/   # 自定义音符类型
├── scripts/            # 脚本 (lua/hx/py)
├── shaders/            # 着色器
└── weeks/              # 周目定义
```

### 启用模组

1. 在 `Project.xml` 中确保启用 `MODS_ALLOWED`
2. 将模组文件夹放入 `mods/` 目录
3. 游戏启动时自动加载

### pack.json 格式

```json
{
    "name": "模组名称",
    "description": "模组描述",
    "version": "1.0.0",
    "author": "作者名",
    "api": 1
}
```

## 兼容性配置

### Flixel 版本

项目支持 **Flixel 5.x** 和 **6.x**，使用条件编译：

```haxe
#if (flixel >= "6.0.0")
    // 6.x 代码
#else
    // 5.x 代码
#end
```

### 平台定义

```haxe
#if desktop      // 桌面平台
#if android      // Android
#if html5        // HTML5
#if mobile       // 移动设备
#if debug        // 调试模式
```

### 功能开关 (Project.xml)

```xml
<!-- 模组系统 -->
<define name="MODS_ALLOWED" if="desktop || android" />

<!-- 脚本支持 -->
<define name="LUA_ALLOWED" if="desktop || android"/>
<define name="PYTHON_ALLOWED" if="desktop || android"/>
<define name="hscriptPos" />

<!-- 视频支持 -->
<define name="VIDEOS_ALLOWED" ... />

<!-- 成就系统 -->
<define name="ACHIEVEMENTS_ALLOWED" />
```

## 常见任务

### 添加新角色

1. 在 `assets/characters/` 添加图片
2. 在 `source/states/game/PlayState.hx` 中注册

### 添加新歌曲

1. 在 `assets/songs/[歌曲名]/` 添加音频
2. 创建 `[歌曲名].json` 谱面文件

### 添加新舞台

1. 在 `assets/stages/` 添加图片
2. 在代码中创建对应的 Stage 类

### 修改 UI 样式

- 编辑 `source/backend/ClientPrefs.hx` 中的设置
- 修改 `source/states/menu/MainMenuState.hx` 等菜单状态

## 关键类说明

| 类 | 说明 |
|-----|------|
| `PlayState` | 主要游戏逻辑状态 |
| `MusicBeatState` | 音乐节拍同步的状态基类 |
| `FlxTransitionableState` | 支持过渡动画的状态 |
| `FlxInputText` | 文本输入组件 (flixel-ui) |
| `FlxUIDropDownMenuCustom` | 自定义下拉菜单 |
| `ModManager` | Mod 图表修改管理器 |
| `HScript` | Haxe 脚本解释器 |

## 调试技巧

### 查看 FPS

在 `ClientPrefs` 中启用 `showFPS`

### 调试追踪

```haxe
#if debug
FlxG.log.add('Debug message');
#end
```

### 崩溃处理

```haxe
#if CRASH_HANDLER
// 崩溃时自动生成报告
#end
```

## 注意事项

1. **Android 权限** - Android 构建需要特定的权限配置
2. **视频格式** - 使用 hxCodec 或 hxvlc 播放 MP4
3. **模组路径** - 模组资源路径需与 `assets/` 结构对应
4. **脚本安全** - Lua/Python 脚本在沙盒中运行
5. **Flixel 版本** - 如果使用 6.x，需注意 API 变更

## 相关链接

- [Friday Night Funkin'](https://www.fridaynightfunkin.com/)
- [Psych Engine](https://github.com/ShadowMario/PsychEngine)
- [HaxeFlixel](https://haxeflixel.com/)
- [Haxe 语言](https://haxe.org/)
