package backend;

import flixel.FlxG;
import flixel.addons.ui.FlxUIState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxState;
import flixel.FlxCamera;

#if sys
import sys.FileSystem;
#end

#if android
import flixel.input.actions.FlxActionInput;
import android.AndroidControls.AndroidControls;
import android.FlxTouchPad;
import android.FlxJoyStick;
#end

/**
 * Base state class that provides beat/step synchronization with the music.
 * All game states should extend this class to have access to music timing events.
 */
class MusicBeatState extends FlxUIState {
    // Beat/Step tracking
    private var curSection:Int = 0;
    private var stepsToDo:Int = 0;
    private var curStep:Int = 0;
    private var curBeat:Int = 0;
    private var curDecStep:Float = 0;
    private var curDecBeat:Float = 0;
    
    // Camera for beat-synced effects
    public static var camBeat:FlxCamera;
    
    // Script variables storage
    public var variables:Map<String, Dynamic> = new Map();
    
    // Scripting support
    public var canBeScripted(get, default):Bool = false;
    public var scripted:Bool = false;
    public var scriptName:String = 'Placeholder';
    public var script:OScriptState;
    
    // Controls accessor
    private var controls(get, never):Controls;
    
    inline function get_canBeScripted():Bool return canBeScripted;
    inline function get_controls():Controls return backend.player.PlayerSettings.player1.controls;
    
    public function new(canBeScripted:Bool = true) {
        super();
        this.canBeScripted = canBeScripted;
    }
    
    /**
     * Set a variable on the attached script
     */
    inline function setOnScript(name:String, value:Dynamic):Void {
        if (script != null) script.set(name, value);
    }
    
    /**
     * Call a function on the attached script
     * @param name Function name to call
     * @param vars Arguments to pass
     * @param ignoreStops If true, continue even if script returns halt
     * @return The return value from the script function
     */
    public function callOnScript(name:String, vars:Array<Any>, ignoreStops:Bool = false):Dynamic {
        if (script == null) return GlobalScript.Function_Continue;
        
        final ret = script.call(name, vars);
        
        if (ret == GlobalScript.Function_Halt && !ignoreStops) {
            return GlobalScript.Function_Continue;
        }
        
        return (ret != GlobalScript.Function_Continue && ret != null) ? ret : GlobalScript.Function_Continue;
    }
    
    inline function isHardcodedState():Bool {
        return script == null || !script.customMenu;
    }
    
    /**
     * Initialize script for this state
     * @param s Script name to load
     */
    public function setUpScript(s:String = 'Placeholder'):Void {
        scripted = true;
        scriptName = s;
        
        #if sys
        final scriptFile = HScript.getPath('scripts/menus/$scriptName');
        if (FileSystem.exists(scriptFile)) {
            script = OScriptState.fromFile(scriptFile);
        }
        #end
        
        callOnScript('onCreate', []);
    }

	   // Android touch controls
	   #if android
	   public var _touchpad:FlxTouchPad;
	   public var _joyStick:FlxJoyStick;
	   public var androidc:AndroidControls;
	   public var trackedinputsUI:Array<FlxActionInput> = [];
	   public var trackedinputsNOTES:Array<FlxActionInput> = [];
	   
	   public function addTouchPad(?DPad:String, ?Action:String):Void {
	       _touchpad = new FlxTouchPad(DPad, Action);
	       add(_touchpad);
	       controls.setTouchPadUI(_touchpad, DPad, Action);
	       trackedinputsUI = controls.trackedinputsUI;
	       controls.trackedinputsUI = [];
	   }
	   
	   public function addJoyStick(x:Float = 0, y:Float = 0, radius:Float = 0, ease:Float = 0.25):Void {
	       _joyStick = new FlxJoyStick(x, y, radius, ease);
	       add(_joyStick);
	   }
	   
	   public function removeTouchPad():Void {
	       controls.removeFlxInput(trackedinputsUI);
	       remove(_touchpad);
	   }
	   
	   public function addAndroidControls():Void {
	       androidc = new AndroidControls();
	       
	       switch (androidc.mode) {
	           case VIRTUALPAD_RIGHT | VIRTUALPAD_LEFT | VIRTUALPAD_CUSTOM:
	               controls.setTouchPadNOTES(androidc.vpad, "FULL", "NONE");
	           case DUO:
	               controls.setTouchPadNOTES(androidc.vpad, "DUO", "NONE");
	           case HITBOX:
	               switch (ClientPrefs.hitboxmode) {
	                   case 'New': controls.setNewHitBox(androidc.newhbox);
	                   case 'Gradient': controls.setGradientHitBox(androidc.ghbox);
	                   case 'Old': controls.setOldHitBox(androidc.oldhbox);
	                   default: controls.setHitBox(androidc.hbox);
	               }
	           default:
	       }
	       
	       trackedinputsNOTES = controls.trackedinputsNOTES;
	       trackedinputsUI = controls.trackedinputsUI;
	       controls.trackedinputsNOTES = [];
	       controls.trackedinputsUI = [];
	       
	       final camcontrol = new FlxCamera();
	       FlxG.cameras.add(camcontrol, false);
	       camcontrol.bgColor.alpha = 0;
	       androidc.cameras = [camcontrol];
	       androidc.visible = false;
	       add(androidc);
	   }
	   
	   public function addPadCamera():Void {
	       final camcontrol = new FlxCamera();
	       camcontrol.bgColor.alpha = 0;
	       FlxG.cameras.add(camcontrol, false);
	       _touchpad.cameras = [camcontrol];
	   }
	   #end
	   
	   override function destroy():Void {
	       #if android
	       if (_touchpad != null && trackedinputsUI.length > 0) {
	           controls.removeFlxInput(trackedinputsUI);
	       }
	       if (androidc != null && trackedinputsNOTES != null) {
	           controls.removeFlxInput(trackedinputsNOTES);
	       }
	       #end
	       super.destroy();
	   }
	   
	   override function create():Void {
	       camBeat = FlxG.camera;
	       final skipTransition = FlxTransitionableState.skipNextTransOut;
	       super.create();
	       
	       if (!skipTransition) {
	           openSubState(new CustomTilesTransition(true));
	       }
	       FlxTransitionableState.skipNextTransOut = false;
	   }
	   
	   override function update(elapsed:Float):Void {
	       final oldStep = curStep;
	       
	       updateCurStep();
	       updateBeat();
	       
	       if (oldStep != curStep) {
	           if (curStep > 0) stepHit();
	           
	           if (PlayState.SONG != null) {
	               if (oldStep < curStep)
	                   updateSection();
	               else
	                   rollbackSection();
	           }
	       }
	       
	       // Persist fullscreen setting
	       if (FlxG.save.data != null) {
	           FlxG.save.data.fullscreen = FlxG.fullscreen;
	       }
	       
	       callOnScript('onUpdate', [elapsed]);
	       super.update(elapsed);
	   }
	   
	   private function updateSection():Void {
	       if (stepsToDo < 1) {
	           stepsToDo = Std.int(Math.round(getBeatsOnSection() * 4));
	       }
	       
	       while (curStep >= stepsToDo) {
	           curSection++;
	           stepsToDo += Std.int(Math.round(getBeatsOnSection() * 4));
	           sectionHit();
	       }
	   }
	   
	   private function rollbackSection():Void {
	       if (curStep < 0) return;
	       
	       final lastSection = curSection;
	       curSection = 0;
	       stepsToDo = 0;
	       
	       for (i in 0...PlayState.SONG.notes.length) {
	           if (PlayState.SONG.notes[i] != null) {
	               stepsToDo += Std.int(Math.round(getBeatsOnSection() * 4));
	               if (stepsToDo > curStep) break;
	               curSection++;
	           }
	       }
	       
	       if (curSection > lastSection) sectionHit();
	   }
	   
	   private inline function updateBeat():Void {
	       curBeat = Math.floor(curStep / 4);
	       curDecBeat = curDecStep / 4;
	   }
	   
	   private function updateCurStep():Void {
	       final lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);
	       final stepOffset = ((Conductor.songPosition - ClientPrefs.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
	       curDecStep = lastChange.stepTime + stepOffset;
	       curStep = lastChange.stepTime + Math.floor(stepOffset);
	   }
	   
	   /**
	    * Switch to a new state with custom transition
	    */
	   public static function switchState(nextState:FlxState):Void {
	       if (!FlxTransitionableState.skipNextTransIn) {
	           final leState:MusicBeatState = cast(FlxG.state, MusicBeatState);
	           leState.openSubState(new CustomTilesTransition(false));
	           
	           CustomTilesTransition.finishCallback = (nextState == FlxG.state)
	               ? FlxG.resetState
	               : function() FlxG.switchState(nextState);
	           return;
	       }
	       
	       FlxTransitionableState.skipNextTransIn = false;
	       FlxG.switchState(nextState);
	   }
	   
	   public static inline function resetState():Void {
	       switchState(FlxG.state);
	   }
	   
	   public static inline function getVariables():Dynamic {
	       return getState().variables;
	   }
	   
	   public static inline function getState():MusicBeatState {
	       return cast(FlxG.state, MusicBeatState);
	   }
	   
	   public function stepHit():Void {
	       if (curStep % 4 == 0) beatHit();
	       callOnScript('onStepHit', [curStep]);
	   }
	   
	   public function beatHit():Void {
	       // Override in subclasses for beat-synced behavior
	   }
	   
	   public function sectionHit():Void {
	       // Override in subclasses for section-synced behavior
	   }
	   
	   private inline function getBeatsOnSection():Float {
	       if (PlayState.SONG != null && PlayState.SONG.notes[curSection] != null) {
	           var beats:Null<Float> = PlayState.SONG.notes[curSection].sectionBeats;
	           return (beats != null && beats > 0) ? beats : 4.0;
	       }
	       return 4.0;
	   }
}
