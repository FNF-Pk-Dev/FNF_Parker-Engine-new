package;
import flixel.util.typeLimit.NextState;
import flixel.FlxGame;
import script.hscript.HScriptUtil.HScriptState;
import psych.script.FunkinLua.LuaSState;

class FNFGame extends FlxGame {
    public override function switchState():Void
    {
        if (_nextState is MusicBeatState) {
            var state:MusicBeatState = cast _nextState;
        if (state.canBeScripted){
            var className = Type.getClassName(Type.getClass(_nextState));
            var simpleName = className.split(".").pop();
                    for (extn in HScriptUtil.extns) {
                        var fileName = 'globals/$simpleName.$extn';
                        if (Paths.exists(Paths.modFolders('states/$fileName'))) {
                            _nextState = new HScriptState(fileName, true);
                            trace(fileName);
                            return super.switchState();
                        }
                    }
            }
        }

        var className = Type.getClassName(Type.getClass(_nextState));
        var simpleName = className.split(".").pop();
        for (extn in HScriptUtil.extns){
        var fileName = 'global/$simpleName.$extn';
        trace(Paths.modFolders('states/$fileName'));}
        return super.switchState();
    }
}