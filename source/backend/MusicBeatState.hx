package backend;

import backend.songs.Conductor.BPMChangeEvent;
import flixel.FlxG;
import flixel.addons.ui.FlxUIState;
import flixel.math.FlxRect;
import flixel.util.FlxTimer;
import flixel.addons.transition.FlxTransitionableState;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import flixel.util.FlxGradient;
import flixel.FlxState;
import flixel.FlxCamera;
import flixel.FlxBasic;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if android
import flixel.input.actions.FlxActionInput;
import android.AndroidControls.AndroidControls;
import android.FlxVirtualPad;
import android.FlxJoyStick;
#end

class MusicBeatState extends FlxUIState
{
	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;
	private var controls(get, never):Controls;

	public static var camBeat:FlxCamera;
	
	public var variables:Map<String, Dynamic> = new Map();

	public var canBeScripted(get, default):Bool = false;
    function get_canBeScripted() return canBeScripted;
    public function new(canBeScripted:Bool = true){
        super();
        this.canBeScripted = canBeScripted;
    }

	public var scripted:Bool = false;
	public var scriptName:String = 'Placeholder';
	public var script:OScriptState;

	inline function setOnScript(name:String, value:Dynamic) //depreciate this soon because the macro does this now? macro still needs more work i think though
	{
		if (script != null) script.set(name, value);
	}

	public function callOnScript(name:String, vars:Array<Any>, ignoreStops:Bool = false)
	{
<<<<<<< HEAD
		var returnVal:Dynamic = GlobalScript.Function_Continue;
		if (script != null)
		{
			var ret:Dynamic = script.call(name, vars);
			if (ret == GlobalScript.Function_Halt)
=======
		var returnVal:Dynamic = HScript.Function_Continue;
		if (script != null)
		{
			var ret:Dynamic = script.call(name, vars);
			if (ret == HScript.Function_Halt)
>>>>>>> c97f37f672a5792d4329f81e4d405bc1b37536e1
			{
				ret = returnVal;
				if (!ignoreStops) return returnVal;
			};

<<<<<<< HEAD
			if (ret != GlobalScript.Function_Continue && ret != null) returnVal = ret;

			if (returnVal == null) returnVal = GlobalScript.Function_Continue;
=======
			if (ret != HScript.Function_Continue && ret != null) returnVal = ret;

			if (returnVal == null) returnVal = HScript.Function_Continue;
>>>>>>> c97f37f672a5792d4329f81e4d405bc1b37536e1
		}
		return returnVal;
	}

	inline function isHardcodedState() return (script != null && !script.customMenu) || (script == null);

	public function setUpScript(s:String = 'Placeholder')
	{
		scripted = true;
		scriptName = s;

		var scriptFile = HScript.getPath('scripts/menus/$scriptName');

		if (FileSystem.exists(scriptFile))
		{
			script = OScriptState.fromFile(scriptFile);
			trace('$scriptName script [$scriptFile] found!');
		}
		else
		{
			// trace('$scriptName script [$scriptFile] is null!');
		}

		callOnScript('onCreate', []);
	}

	inline function get_controls():Controls
		return backend.player.PlayerSettings.player1.controls;

	#if android
	public var _virtualpad:FlxVirtualPad;
	public var _joyStick:FlxJoyStick;
	public var androidc:AndroidControls;
	public var trackedinputsUI:Array<FlxActionInput> = [];
	public var trackedinputsNOTES:Array<FlxActionInput> = [];
	#end
	
	#if android
	public function addVirtualPad(?DPad:FlxDPadMode, ?Action:FlxActionMode) {
		_virtualpad = new FlxVirtualPad(DPad, Action, 0.75, ClientPrefs.globalAntialiasing);
		add(_virtualpad);
		controls.setVirtualPadUI(_virtualpad, DPad, Action);
		trackedinputsUI = controls.trackedinputsUI;
		controls.trackedinputsUI = [];
	}
	public function addJoyStick(?XX:Float = 0, ?YY:Float = 0, ?Radius:Float = 0, ?Ease:Float = 0.25) {
		_joyStick = new FlxJoyStick(XX, YY, Radius, Ease);
		add(_joyStick);
	}
	#end

	#if android
	public function removeVirtualPad() {
		controls.removeFlxInput(trackedinputsUI);
		remove(_virtualpad);
	}
	#end

	#if android
	public function addAndroidControls() {
		androidc = new AndroidControls();

		switch (androidc.mode)
		{
			case VIRTUALPAD_RIGHT | VIRTUALPAD_LEFT | VIRTUALPAD_CUSTOM:
				controls.setVirtualPadNOTES(androidc.vpad, FULL, NONE);
			case DUO:
				controls.setVirtualPadNOTES(androidc.vpad, DUO, NONE);
			case HITBOX:
			   if(ClientPrefs.hitboxmode == 'New'){
				controls.setNewHitBox(androidc.newhbox);
				}else{
				controls.setGradientHitBox(androidc.ghbox);
		                }
			default:
		}

		trackedinputsNOTES = controls.trackedinputsNOTES;
		trackedinputsUI = controls.trackedinputsUI;
		controls.trackedinputsNOTES = [];
        controls.trackedinputsUI = [];

		var camcontrol = new flixel.FlxCamera();
		FlxG.cameras.add(camcontrol, false);
		camcontrol.bgColor.alpha = 0;
		androidc.cameras = [camcontrol];

		androidc.visible = false;

		add(androidc);
	}
	#end

	#if android
        public function addPadCamera() {
		var camcontrol = new flixel.FlxCamera();
		camcontrol.bgColor.alpha = 0;
		FlxG.cameras.add(camcontrol, false);
		_virtualpad.cameras = [camcontrol];
	}
	#end
	
	override function destroy() {
		#if android
		if (_virtualpad != null){
		if (trackedinputsUI != [])
		controls.removeFlxInput(trackedinputsUI);
		}

		if (androidc != null){
		if (trackedinputsNOTES != null)
		controls.removeFlxInput(trackedinputsNOTES);
		}
		#end

		super.destroy();
	}

	override function create() {
		camBeat = FlxG.camera;
		var skip:Bool = FlxTransitionableState.skipNextTransOut;
		super.create();

		if(!skip) {
			openSubState(new CustomTilesTransition(true));
		}
		FlxTransitionableState.skipNextTransOut = false;
	}

	override function update(elapsed:Float)
	{
		//everyStep();
		var oldStep:Int = curStep;

		updateCurStep();
		updateBeat();

		if (oldStep != curStep)
		{
			if(curStep > 0)
				stepHit();

			if(PlayState.SONG != null)
			{
				if (oldStep < curStep)
					updateSection();
				else
					rollbackSection();
			}
		}

		if(FlxG.save.data != null) FlxG.save.data.fullscreen = FlxG.fullscreen;

		callOnScript('onUpdate', [elapsed]);

		super.update(elapsed);
	}

	private function updateSection():Void
	{
		if(stepsToDo < 1) stepsToDo = Math.round(getBeatsOnSection() * 4);
		while(curStep >= stepsToDo)
		{
			curSection++;
			var beats:Float = getBeatsOnSection();
			stepsToDo += Math.round(beats * 4);
			sectionHit();
		}
	}

	private function rollbackSection():Void
	{
		if(curStep < 0) return;

		var lastSection:Int = curSection;
		curSection = 0;
		stepsToDo = 0;
		for (i in 0...PlayState.SONG.notes.length)
		{
			if (PlayState.SONG.notes[i] != null)
			{
				stepsToDo += Math.round(getBeatsOnSection() * 4);
				if(stepsToDo > curStep) break;
				
				curSection++;
			}
		}

		if(curSection > lastSection) sectionHit();
	}

	private function updateBeat():Void
	{
		curBeat = Math.floor(curStep / 4);
		curDecBeat = curDecStep/4;
	}

	private function updateCurStep():Void
	{
		var lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);

		var shit = ((Conductor.songPosition - ClientPrefs.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
		curDecStep = lastChange.stepTime + shit;
		curStep = lastChange.stepTime + Math.floor(shit);
	}

	public static function switchState(nextState:FlxState) {
		// Custom made Trans in
		var curState:Dynamic = FlxG.state;
		var leState:MusicBeatState = curState;
		if(!FlxTransitionableState.skipNextTransIn) {
			leState.openSubState(new CustomTilesTransition(false));
			if(nextState == FlxG.state) {
				CustomTilesTransition.finishCallback = function() {
					FlxG.resetState();
				};
				//trace('resetted');
			} else {
				CustomTilesTransition.finishCallback = function() {
					FlxG.switchState(nextState);
				};
				//trace('changed state');
			}
			return;
		}
		FlxTransitionableState.skipNextTransIn = false;
		FlxG.switchState(nextState);
	}

	public static function resetState() {
		MusicBeatState.switchState(FlxG.state);
	}
	
	public static function getVariables():Dynamic {
        return getState().variables;
    }
    
    public static function getState():MusicBeatState {
        var curState:FlxState = FlxG.state;
        var leState:MusicBeatState = cast(curState, MusicBeatState);
        return leState;
    }

	public function stepHit():Void
	{
		if (curStep % 4 == 0)
			beatHit();

		callOnScript('onStepHit', [curStep]);
	}

	public function beatHit():Void
	{
		//trace('Beat: ' + curBeat);
	}

	public function sectionHit():Void
	{
		//trace('Section: ' + curSection + ', Beat: ' + curBeat + ', Step: ' + curStep);
	}

	function getBeatsOnSection()
	{
		var val:Null<Float> = 4;
		if(PlayState.SONG != null && PlayState.SONG.notes[curSection] != null) val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? 4 : val;
	}
}
