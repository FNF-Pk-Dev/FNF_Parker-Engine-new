package backend;

import backend.songs.Conductor.BPMChangeEvent;
import flixel.FlxG;
import flixel.FlxSubState;
import flixel.FlxBasic;
import flixel.FlxSprite;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if android
import flixel.input.actions.FlxActionInput;
import android.FlxTouchPad;
#end

class MusicBeatSubstate extends FlxSubState
{
	public function new()
	{
		super();
	}

	private var lastBeat:Float = 0;
	private var lastStep:Float = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;
	private var controls(get, never):Controls;

	inline function get_controls():Controls
		return PlayerSettings.player1.controls;

	public var scripted:Bool = false;
	public var scriptName:String = 'Placeholder';
	public var script:OScriptState;

	public function setUpScript(s:String = 'Placeholder')
	{
		scripted = true;
		scriptName = s;

		var scriptFile = HScript.getPath('substates/menu/$scriptName');

		if (FileSystem.exists(scriptFile))
		{
			script = OScriptState.fromFile(scriptFile);
			trace('$scriptName script [$scriptFile] found!');
		}
		else
		{
			trace('$scriptName script [$scriptFile] is null!');
		}

		setOnScript('add', this.add);
		setOnScript('close', close);
		setOnScript('this', this);
		callOnScript('onCreate', []);
	}

	inline function isHardcodedState() return (script != null && !script.customMenu) || (script == null);

	inline function setOnScript(name:String, value:Dynamic)
	{
		if (script != null) script.set(name, value);
	}

	public function callOnScript(name:String, vars:Array<Any>, ignoreStops:Bool = false)
	{
		var returnVal:Dynamic = GlobalScript.Function_Continue;
		if (script != null)
		{
			var ret:Dynamic = script.call(name, vars);
			if (ret == GlobalScript.Function_Halt)
			{
				ret = returnVal;
				if (!ignoreStops) return returnVal;
			};

			if (ret != GlobalScript.Function_Continue && ret != null) returnVal = ret;

			if (returnVal == null) returnVal = GlobalScript.Function_Continue;
		}
		return returnVal;
	}

	#if android
	var _touchpad:FlxTouchPad;
	var trackedinputsUI:Array<FlxActionInput> = [];
	var trackedinputsNOTES:Array<FlxActionInput> = [];
	#end
	
	#if android
	public function addTouchPad(?DPad:String, ?Action:String) {
		_touchpad = new FlxTouchPad(DPad, Action);
		add(_touchpad);
		controls.setTouchPadUI(_touchpad, DPad, Action);
		trackedinputsUI = controls.trackedinputsUI;
		controls.trackedinputsUI = [];
	}
	#end

	#if android
	public function removeVirtualPad() {
		controls.removeFlxInput(trackedinputsUI);
		remove(_touchpad);
	}
	#end

	#if android
		public function addPadCamera() {
		var camcontrol = new flixel.FlxCamera();
		camcontrol.bgColor.alpha = 0;
		FlxG.cameras.add(camcontrol, false);
		_touchpad.cameras = [camcontrol];
	}
	#end
	
	override function destroy() {
		#if android
		if (_touchpad != null){
		if (trackedinputsUI != [])
		controls.removeFlxInput(trackedinputsUI);
	    }
		#end

		callOnScript('onDestroy', []);
		super.destroy();
	}

	override function update(elapsed:Float)
	{
		//everyStep();
		var oldStep:Int = curStep;

		updateCurStep();
		updateBeat();

		if (oldStep != curStep && curStep > 0)
			stepHit();


		super.update(elapsed);
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

	public function stepHit():Void
	{
		if (curStep % 4 == 0)
			beatHit();
	}

	public function beatHit():Void
	{
		//do literally nothing dumbass
	}
}
