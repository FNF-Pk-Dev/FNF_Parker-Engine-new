package;

import flixel.FlxCamera;
import flixel.FlxSprite;

class CustomTilesTransition extends MusicBeatSubstate {
    public static var finishCallback:Void->Void;
    public static var nextCamera:FlxCamera;
    var isTransIn:Bool = false;
    var transit:FlxSprite;

    public function new(isTransIn:Bool) {
        this.isTransIn = isTransIn;
        super();
        
        transit = new FlxSprite();
        transit.frames = Paths.getSparrowAtlas('ui/diaTrans');
        transit.animation.addByPrefix('transIn', 'transIn', 40, false);
        transit.animation.addByPrefix('transOut', 'transOut', 40, false);
        transit.scrollFactor.set();
        add(transit);

        if (isTransIn) {
            transit.animation.play('transOut');
            transit.animation.finishCallback = opSS;
        } else {
            transit.animation.play('transIn');
            transit.animation.finishCallback = clSS;
        }

        if (nextCamera != null) {
            transit.cameras = [nextCamera];
        }
        nextCamera = null;
    }

    function clSS(huh:String) {
        if(finishCallback != null) {
            finishCallback();
        }
    }

    function opSS(huh:String) {
        close();
    }
    
    override function update(elapsed:Float) {

        super.update(elapsed);
    }
}