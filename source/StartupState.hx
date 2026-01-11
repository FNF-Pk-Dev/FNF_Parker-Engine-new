package;

import flixel.FlxState;
import flixel.addons.transition.FlxTransitionableState;

/**
 * Initial startup state that handles transitions to the main game state.
 * This is a minimal bootstrapping state that skips transitions and immediately
 * switches to the configured next state (default: TitleState).
 */
class StartupState extends MusicBeatState {
    /** The state to transition to after startup */
    public static var nextState:Class<FlxState> = states.TitleState;
    
    override function create() {
        // Skip transitions for initial load
        FlxTransitionableState.skipNextTransIn = true;
        FlxTransitionableState.skipNextTransOut = true;

        #if android
		FlxG.android.preventDefaultKeys = [BACK];
		#end
        
        // Immediately transition to the next state
        MusicBeatState.switchState(Type.createInstance(nextState, []));
        
        super.create();
    }
}
