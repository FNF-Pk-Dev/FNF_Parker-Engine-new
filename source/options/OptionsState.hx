package options;

#if desktop
import backend.Discord.DiscordClient;
#end
import flash.text.TextField;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.display.FlxGridOverlay;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import lime.utils.Assets;
import flixel.FlxSubState;
import flash.text.TextField;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxSave;
import haxe.Json;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer;
import flixel.input.keyboard.FlxKey;
import flixel.graphics.FlxGraphic;
import flixel.addons.display.FlxBackdrop;
import backend.player.Controls;

using StringTools;

class OptionsState extends MusicBeatState
{
	var options:Array<String> = ['Note Colors', 'Controls', 'Graphics', 'Visuals and UI', 'Gameplay'];
	var HUDwrinText:FlxText;
	private var grpOptions:FlxTypedGroup<Alphabet>;
	private static var curSelected:Int = 0;
	public static var menuBG:FlxSprite;

	function openSelectedSubstate(label:String) {
		switch(label) {
			case 'Note Colors':
				#if android
				removeTouchPad();
				#end
				openSubState(new options.NotesSubState());
			case 'Controls':
				#if android
				removeTouchPad();
				#end
				openSubState(new options.ControlsSubState());
			case 'Graphics':
				#if android
				removeTouchPad();
				#end
				openSubState(new options.GraphicsSettingsSubState());
			case 'Visuals and UI':
				#if android
				removeTouchPad();
				#end
				openSubState(new options.VisualsUISubState());
			case 'Gameplay':
				#if android
				removeTouchPad();
				#end
				openSubState(new options.GameplaySettingsSubState());
				//放心吧 ，没用了
			case 'Adjust Delay':
				LoadingState.loadAndSwitchState(new options.NoteOffsetState());
		}
	}

	// var selectorLeft:Alphabet;
	// var selectorRight:Alphabet;
	var velocityBackground:FlxBackdrop;

	override function create() {
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		#if desktop
		DiscordClient.changePresence("Options Menu", null);
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFFea71fd;
		bg.updateHitbox();

		bg.screenCenter();
		bg.antialiasing = ClientPrefs.globalAntialiasing;
		add(bg);

		velocityBackground = new FlxBackdrop(FlxGridOverlay.createGrid(30, 30, 60, 60, true, 0x3B161932, 0x0));
		velocityBackground.velocity.set(FlxG.random.bool(50) ? 90 : -90, FlxG.random.bool(50) ? 90 : -90);
		velocityBackground.antialiasing = ClientPrefs.globalAntialiasing;
		velocityBackground.alpha = 0;
		FlxTween.tween(velocityBackground, {alpha: 1}, 0.5, {ease: FlxEase.quadOut});
		add(velocityBackground);

		grpOptions = new FlxTypedGroup<Alphabet>();
		add(grpOptions);

		for (i in 0...options.length)
		{
			var optionText:Alphabet = new Alphabet(90, 320, options[i], true);
			optionText.isMenuItem = true;

			optionText.targetY = i - curSelected;
			var maxWidth = 980;
			if (optionText.width > maxWidth)
			{
				optionText.scaleX = maxWidth / optionText.width;
			}
			optionText.snapToPosition();
			grpOptions.add(optionText);

			// Entrance Animation: Slide in from left
			optionText.x = -1000;
			FlxTween.tween(optionText, {x: 90}, 0.5 + (i * 0.1), {ease: FlxEase.elasticOut, startDelay: 0.2});
		}

		// selectorLeft = new Alphabet(0, 0, '>', true);
		// add(selectorLeft);
		// selectorRight = new Alphabet(0, 0, '<', true);
		// add(selectorRight);

		changeSelection();
		ClientPrefs.saveSettings();

		#if android
		var tipText:FlxText = new FlxText(10, 12, 0, 'Press X to Go In Android Controls Menu', 16);
		tipText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		tipText.borderSize = 2;
		tipText.scrollFactor.set();
		add(tipText);
		var tipText:FlxText = new FlxText(10, 32, 0, 'Press Y to Go In Hitbox Settings Menu', 16);
		tipText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		tipText.borderSize = 2;
		tipText.scrollFactor.set();
		add(tipText);
		#end

		HUDwrinText = new FlxText(10, 32, 0, 'Press Go In Visuals and UI Menu Change it inside to camHUD', 36);
		HUDwrinText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		HUDwrinText.borderSize = 2;
		HUDwrinText.scrollFactor.set();
		HUDwrinText.alpha = 0.001;
		add(HUDwrinText);

		changeSelection();
		ClientPrefs.saveSettings();

		#if android
		addTouchPad("UP_DOWN", "A_B_X_Y");
		#end

		super.create();
	}

	override function closeSubState() {
		super.closeSubState();
		ClientPrefs.saveSettings();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (controls.UI_UP_P) {
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P) {
			changeSelection(1);
		}

		if (controls.BACK) {
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(substates.PauseSubState.options ? new PlayState() : new MainMenuState());
		}

		#if android
		if (_touchpad.buttonX.justPressed) {
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
			MusicBeatState.switchState(new android.AndroidControlsMenu());
		}
		if (_touchpad.buttonY.justPressed) {
			removeTouchPad();
			openSubState(new android.HitboxSettingsSubState());
		}
		#end

		if (controls.ACCEPT) {
			openSelectedSubstate(options[curSelected]);
		}
	}
	
	function changeSelection(change:Int = 0) {
		curSelected += change;
		if (curSelected < 0)
			curSelected = options.length - 1;
		if (curSelected >= options.length)
			curSelected = 0;

		var bullShit:Int = 0;

		for (item in grpOptions.members) {
			item.targetY = bullShit - curSelected;
			bullShit++;

			item.alpha = 0.6;
			// item.setGraphicSize(Std.int(item.width * 0.8));

			if (item.targetY == 0)
			{
				item.alpha = 1;
				// item.setGraphicSize(Std.int(item.width));
			}

			item.alpha = 0.6;
			if (item.targetY == 0) {
				item.alpha = 1;
				// selectorLeft.x = item.x - 63;
				// selectorLeft.y = item.y;
				// selectorRight.x = item.x + item.width + 15;
				// selectorRight.y = item.y;
				
				// Dynamic selection effect
				FlxTween.cancelTweensOf(item);
				FlxTween.tween(item, {x: 120, alpha: 1}, 0.2, {ease: FlxEase.quadOut});
			} else {
				FlxTween.cancelTweensOf(item);
				FlxTween.tween(item, {x: 90, alpha: 0.6}, 0.2, {ease: FlxEase.quadOut});
			}
		}
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}
}
