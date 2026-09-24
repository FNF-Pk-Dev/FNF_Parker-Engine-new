# Locked Destiny / NeurosesH-mix 修复文件

`LockedDestiny/` 是覆盖补丁，不含原 mod 的图片、音乐和视频。将文件合并到已有的 `mods/LockedDestiny/`；需要同时使用包含本次引擎修改的新程序。

本机已安装位置为 `export/release/windows/bin/mods/LockedDestiny/`。此处保留可提交的补丁，因为 `export/` 是被 Git 忽略的构建目录。

- `scripts/NeurosesCharacters.lua`：仅在 `tvN` 舞台启用。在 `onUpdatePost` 同步 BF/SBF 与各自影子的动画和帧，保留影子的翻转、变形、位置和透明度；独立的吉他叠层 `SBFG` 也跟随 dad。影子不再由 `PlayState` 或 `ESCompat` 自动驱动。
- 镜头使用初始角色画面的尺寸作为跟随参考，不再使用包含所有姿势留白的大画布。`cameraZoom.lua` 在开场剪影期间让谱面控制缩放。
- `characters/SBFneurosesR.json`、`SBFneurosesRG.json`：补偿 Animate 图集烘焙的画布平移。SBF 的原始边界为 `(-145, -212)`，SBFG 为 `(-148, -225)`，因此将对应量加到各动画 offset；不改变人物逻辑坐标或漂浮轨迹。替换图集后应重新校准这些数值。
- `Functions.lua`：初始即隐藏特效，中央角色、电视和花屏、影子在 `goodapple` 关闭时（第 288 步 / 21.6 秒）才显示。保留后续谱面透明度变化。
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
