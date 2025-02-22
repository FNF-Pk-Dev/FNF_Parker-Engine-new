package modchart;

import flixel.math.FlxAngle;
import modchart.*;
import modchart.events.CallbackEvent;

class Modcharts {
    static function numericForInterval(start, end, interval, func){
        var index = start;
        while(index < end){
            func(index);
            index += interval;
        }
    }

    static var songs = ["fresh"];
	public static function isModcharted(songName:String){
		if (songs.contains(songName.toLowerCase()))
            return true;

        // add other conditionals if needed
        
        //return true; // turns modchart system on for all songs, only use for like.. debugging
        return false;
    }
    
    public static function loadModchart(modManager:ModManager, songName:String){
                if(ClientPrefs.middleScroll){
                    modManager.setValue("opponentSwap", 0.5);
                    modManager.setValue("alpha", 1, 1);
                }
        trace('${songName} modchart loaded!');
    }
}