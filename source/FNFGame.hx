package;

import flixel.FlxGame;

/**
 * Extended FlxGame class that supports scripted state overrides.
 * Allows mod authors to replace built-in states with HScript implementations.
 */
class FNFGame extends FlxGame {
    public override function switchState():Void {
        // Check if the next state can be overridden by a script
        if (_nextState is MusicBeatState) {
            final state:MusicBeatState = cast _nextState;
            if (state.canBeScripted) {
                final simpleName = Type.getClassName(Type.getClass(_nextState)).split(".").pop();
                
                // Try to find a script override for this state
                for (extn in HScriptUtil.extns) {
                    final scriptPath = Paths.modFolders('states/globals/$simpleName.$extn');
                    if (Paths.exists(scriptPath)) {
                        _nextState = OScriptState.fromFile(scriptPath);
                        break;
                    }
                }
            }
        }
        
        super.switchState();
    }
}