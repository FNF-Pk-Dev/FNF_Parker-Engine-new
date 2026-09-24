# Locked Destiny / NeurosesH-mix 修复文件

`LockedDestiny/` 是覆盖补丁，不含原 mod 的图片、音乐和视频。将文件合并到已有的 `mods/LockedDestiny/`；需要同时使用包含本次引擎修改的新程序。

本机已安装位置为 `export/release/windows/bin/mods/LockedDestiny/`。此处保留可提交的补丁，因为 `export/` 是被 Git 忽略的构建目录。

- `scripts/NeurosesCharacters.lua`：仅在 `tvN` 舞台启用。在 `onUpdatePost` 同步 BF/SBF 与各自影子的动画和帧，保留影子的翻转、变形、位置和透明度；独立的吉他叠层 `SBFG` 也跟随 dad。影子不再由 `PlayState` 或 `ESCompat` 自动驱动。
- Animate 角色的绘制原点、负坐标由引擎统一处理。镜头使用原版 Character 包装对象的 `(x, y)` 锚点，不叠加烘焙画布或动作尺寸；切换动作和缩放不会改变此锚点。普通 Sparrow 角色仍使用原有中点。`cameraZoom.lua` 在开场剪影期间让谱面控制缩放。
- `states/MainMenuState.lua`：选中背景、选中文字和未选中文字统一使用实际创建的三组选项，修复 `selectedOp3`、`selected3`、`noSelected*` 对象不存在的报错。
- `characters/SBFneurosesR.json`、`SBFneurosesRG.json`：恢复原版动画 offset，覆盖旧补丁的手工补偿，避免与引擎修正重复叠加。必须和新版引擎一起更新。
- `Functions.lua` 与 `NeurosesCharacters.lua`：初始即隐藏特效；`goodapple` 开启期间隐藏整个中央角色组，切换角色也不会漏出。第 288 步关闭效果后显示，后续透明度仍由谱面控制。
- `tvN.lua`：后段红色隧道、分屏、黄色背景及黑幕放在电视/中央角色之上、主角之下，防止旧舞台穿透后段场景。
- 引擎允许同一步内所有 `stepEvent` 回调执行，第 1567 步能同时开启镜头摇晃和关闭花屏；`videoPlay` 可播放舞台脚本创建的视频，修复后段爆炸视频的跨脚本调用。
- `Fly.lua`：切换对手当帧按舞台位置加角色 JSON 偏移恢复坐标，避免复用角色时保留分屏/吉他段的位置，也避免延迟计时器采到旧漂浮基准；影子基准不重复累加。
- `AutoText.lua`：明确使用 `SBF.ttf` 和 `corrup.otf`，引擎注册实际字体后再交给文字渲染器；死亡时停止打字、缩放及淡入淡出。引擎同时兼容单值和双轴 `doTweenScale`，让转场文字在 0.2 秒内从 29 倍缩回正常大小，隧道缩放也能执行。
- `scripts/NeurosesCharacters.lua`：图标保留抗锯齿，去掉引擎额外加入的每拍旋转。像素图标变体由引擎正确识别，避免平滑采样使像素边缘模糊。
- `data/NeurosesH-mix/customDeath.lua` 和 `data/raices/customDeath.lua`：使用有效的 Conductor 类路径，死亡时暂停歌曲及人声、阻止游戏输入，保留自定义动画和重试/退出流程。引擎尊重 Lua 的 `Function_Stop`，不再用默认死亡界面覆盖它。
- `scripts/NeurosesIntro.lua`：沿用谱面 1650 ms 的 `Play Video` 事件，在视频末尾淡出。视频名区分大小写，使用 `IntroN`。

视频现在固定使用 `camVideo`，并能直接控制整个视频对象的透明度：

```lua
doTweenAlpha('introFade', 'IntroN', 0, 0.5, 'linear')
```

```haxe
var introN = PlayState.instance.variables.get('IntroN');
if (introN != null)
{
	FlxTween.tween(introN, {alpha: 0}, 0.5);
}
```

自然结束或跳过时会释放视频名称、取消视频对象 Tween，避免再次进入歌曲时留下旧引用。修改 `camVideo.alpha` 也会作用于视频画面。

在仓库根目录执行 `lua tests/LockedDestinyScriptsTest.lua`，可检查角色切换、字幕关闭及两首歌的死亡重试/退出回调；这个离线检查不启动游戏，也不代替运行画面的最终对照。运行画面由用户试玩确认。
