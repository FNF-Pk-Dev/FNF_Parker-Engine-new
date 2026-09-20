package obj;

import backend.ClientPrefs;
import backend.Paths;
import flixel.group.FlxSpriteGroup;
import flxanimate.FlxAnimate;

class PowerPuffGirl extends FlxSpriteGroup
{
	public static inline var INTRO_PATH:String = "ui/ppg_loading_intro";
	public static inline var IDLE_PATH:String = "ui/ppg_loading_idle";
	public static inline var OUTRO_PATH:String = "ui/ppg_loading_outro";

	var intro:FlxAnimate;
	var idle:FlxAnimate;
	var outro:FlxAnimate;
	var activeAnim:FlxAnimate;

	public function new(x:Float = 0, y:Float = 0)
	{
		super(x, y);

		intro = createAnim(INTRO_PATH);
		idle = createAnim(IDLE_PATH);
		outro = createAnim(OUTRO_PATH);

		add(intro);
		add(idle);
		add(outro);

		setActive(intro);
	}

	function createAnim(path:String):FlxAnimate
	{
		var atlasPath = Paths.getPreloadPath('images/$path');
		var anim = new FlxAnimate(0, 0, atlasPath);
		anim.showPivot = false;
		anim.antialiasing = ClientPrefs.globalAntialiasing;
		anim.scrollFactor.set();
		anim.visible = false;
		return anim;
	}

	function setActive(target:FlxAnimate):Void
	{
		if (intro != null)
		{
			intro.visible = false;
			intro.anim.pause();
		}
		if (idle != null)
		{
			idle.visible = false;
			idle.anim.pause();
		}
		if (outro != null)
		{
			outro.visible = false;
			outro.anim.pause();
		}
		activeAnim = target;
		if (activeAnim != null)
			activeAnim.visible = true;
	}

	public function playIntro(?onComplete:Void->Void):Void
	{
		setActive(intro);
		intro.anim.onComplete = function()
		{
			if (onComplete != null)
				onComplete();
		};
		intro.anim.curInstance.symbol.loop = flxanimate.data.AnimationData.Loop.PlayOnce;
		intro.anim.play(intro.anim.metadata.name, true);
	}

	public function playIdle():Void
	{
		setActive(idle);
		idle.anim.onComplete = null;
		idle.anim.curInstance.symbol.loop = flxanimate.data.AnimationData.Loop.Loop;
		idle.anim.play(idle.anim.metadata.name, true);
	}

	public function playOutro(?onComplete:Void->Void):Void
	{
		setActive(outro);
		outro.anim.onComplete = function()
		{
			if (onComplete != null)
				onComplete();
		};
		outro.anim.curInstance.symbol.loop = flxanimate.data.AnimationData.Loop.PlayOnce;
		outro.anim.play(outro.anim.metadata.name, true);
	}
}
