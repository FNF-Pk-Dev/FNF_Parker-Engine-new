package states.menu;

#if desktop
import backend.Discord.DiscordClient;
#end
import openfl.text.TextField;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.display.FlxGridOverlay;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import lime.utils.Assets;
import flixel.FlxSubState;
import backend.game.Achievements;

using StringTools;

class AchievementsMenuState extends MusicBeatState
{
	#if ACHIEVEMENTS_ALLOWED
	var options:Array<String> = [];
	private var grpOptions:FlxTypedGroup<Alphabet>;

	private static var curSelected:Int = 0;

	private var achievementArray:Array<AttachedAchievement> = [];
	private var achievementIndex:Array<Int> = [];
	private var descText:FlxText;

	override function create()
	{
		#if desktop
		DiscordClient.changePresence("Achievements Menu", null);
		#end

		var menuBG:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuBGBlue'));
		menuBG.setGraphicSize(Std.int(menuBG.width * 1.1));
		menuBG.updateHitbox();
		menuBG.screenCenter();
		menuBG.antialiasing = ClientPrefs.globalAntialiasing;
		add(menuBG);

		grpOptions = new FlxTypedGroup<Alphabet>();
		add(grpOptions);

		Achievements.loadAchievements();
		for (i in 0...Achievements.achievementsStuff.length)
		{
			if (!Achievements.achievementsStuff[i][3] || Achievements.achievementsMap.exists(Achievements.achievementsStuff[i][2]))
			{
				options.push(Achievements.achievementsStuff[i]);
				achievementIndex.push(i);
			}
		}

		for (i in 0...options.length)
		{
			var achieveName:String = Achievements.achievementsStuff[achievementIndex[i]][2];
			var optionText:Alphabet = new Alphabet(280, 300,
				Achievements.isAchievementUnlocked(achieveName) ? Achievements.achievementsStuff[achievementIndex[i]][0] : '?', false);
			optionText.isMenuItem = true;
			optionText.targetY = i - curSelected;
			optionText.snapToPosition();
			grpOptions.add(optionText);

			var icon:AttachedAchievement = new AttachedAchievement(optionText.x - 105, optionText.y, achieveName);
			icon.sprTracker = optionText;
			achievementArray.push(icon);
			add(icon);
		}

		descText = new FlxText(150, 600, 980, "", 32);
		descText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descText.scrollFactor.set();
		descText.borderSize = 2.4;
		add(descText);
		changeSelection();

		// Entrance: the list and its icons fade in, one entry at a time. The entries
		// position themselves (`isMenuItem` lerps their x), so `fromX` hands `flyInX`
		// each sprite's own x and only alpha animates. `restAlpha` lands the fade
		// directly on the idle/selected dimming, so no settle pass is needed afterwards.
		UIAnim.flyInX(grpOptions.members, i -> grpOptions.members[Std.int(i)].x, 0.05, 0.6, null, i -> i == curSelected ? 1 : 0.6);
		UIAnim.flyInX(achievementArray, i -> achievementArray[Std.int(i)].x, 0.05, 0.6, null, i -> i == curSelected ? 1 : 0.6);

		#if android
		addTouchPad("UP_DOWN", "A_B");
		#end

		super.create();
	}

	/** Idle/selected alphas of the list and its icons; re-run when the entrance faded them up. */
	function updateSelectionAlpha()
	{
		var bullShit:Int = 0;

		for (item in grpOptions.members)
		{
			item.targetY = bullShit - curSelected;
			bullShit++;

			UIAnim.selectItem(item, item.targetY == 0);
			// Nothing tweens x here, so the list keeps drifting in x as it scrolls
			item.changeX = true;
		}

		// `AttachedAchievement` copies the position only, not the alpha
		for (i in 0...achievementArray.length)
		{
			UIAnim.selectItem(achievementArray[i], i == curSelected);
		}
	}

	override function update(elapsed:Float)
	{
		UIAnim.syncConductor();

		super.update(elapsed);

		if (controls.UI_UP_P)
		{
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P)
		{
			changeSelection(1);
		}

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new MainMenuState());
		}
	}

	function changeSelection(change:Int = 0)
	{
		curSelected += change;
		if (curSelected < 0)
			curSelected = options.length - 1;
		if (curSelected >= options.length)
			curSelected = 0;

		updateSelectionAlpha();

		descText.text = Achievements.achievementsStuff[achievementIndex[curSelected]][1];
		UIAnim.popText(descText, 0, 0.2);
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}
	#end
}
