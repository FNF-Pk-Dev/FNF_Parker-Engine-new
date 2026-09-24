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
- `Fly.lua`：切换角色时不再将已经叠加的漂浮量重复记入影子和吉他角色的基准位置。
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

运行画面的最终对照由用户试玩确认。
