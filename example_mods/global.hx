import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
//import openfl.Lib;
import openfl.events.Event;
import flixel.math.FlxMath;
import openfl.system.System;

var useFps = Main.fpsVar.visible;
Main.fpsVar.visible = true;

var updateFpsText = true;
var currentIndex:Int = 0; // Tracks current heart (0 to 5)
var MAX_INDEX:Int = 5; // Last index (heart5)
var fpsSprite:Sprite = null;
var fpsSprite = new Sprite();
var fpsText = null;

var currentTime = 0;
var delta = 0;
var lastTime = 0;
var fpsCount = [];
var currentCount = 0;
var cacheCount = 0;
var fps = 0;
var memory = 0;
var maxMem = 0;

var uhmUrPcIsDying = false;
var sprite;
if (useFps) {

  // set text as new fps if useFps . . .
  fpsText = new TextField();
  fpsText.defaultTextFormat = new TextFormat('_sans', 14);
  fpsText.width = FlxG.width;
  fpsText.textColor = 0xffffffff;
  fpsText.x = 10;
  fpsText.y = 2.5;
  //add(fpsText);
  //game.modchartTexts.set('fpsText', fpsText);
  FlxG.mouse.visible = true;
  

  // . . . then remove main fps stuff and add the new one
  Main.fpsVar.parent.removeChild(Main.fpsVar);
  fpsSprite.addChild(fpsText);
  FlxG.game.addChild(fpsSprite);

}
var ColorArray:Array<Int> = [
		0x9400D3,
		0x4B0082,
		0x0000FF,
		0x00FF00,
		0xFFFF00,
		0xFF7F00,
		0xFF0000
];

var currentColor = 0;	
var skippedFrames = 0;
function onUpdate(event) {

if (ClientPrefs.rainbowFPS)
		{
			if (skippedFrames >= 6)
			{
				if (currentColor >= ColorArray.length)
					currentColor = 0;
				fpsText.textColor = ColorArray[currentColor];
				currentColor++;
				skippedFrames = 0;
			}
			else
			{
				skippedFrames++;
			}
		}
		else
		{
			textColor = 0xFFFFFFFF;
		}
  
  // main elapsed/delta/dt logic
  currentTime = Lib.getTimer();
  delta = (currentTime - lastTime) / 1000;
  lastTime = currentTime;

  // framerate and memory logic
  fpsCount.push(lastTime);
  while (fpsCount[0] < lastTime - 1000) {fpsCount.shift();}
  currentCount = fpsCount.length;
  fps = Math.ceil((currentCount + cacheCount) / 2);
  cacheCount = currentCount;
  memory = Math.abs(FlxMath.roundDecimal(System.totalMemory / 1000000, 1));
  if (memory > maxMem) {maxMem = memory;}

  // if useFps, update the fps text and its color
  if (useFps) {
    fpsText.text = 'FPS: ' + fps + '\nMemory: ' + memory + ' MB\nMax Memory: ' + maxMem + ' MB';
    uhmUrPcIsDying = fps < ClientPrefs.framerate / 2 || memory > 3000;
    fpsText.textColor = uhmUrPcIsDying ? 0xffff0000 : 0xffffffff;
  }

  // call update function!!!
  //game.callOnLuas('onUpdateEvent', [delta, fps, memory, maxMem]);

}

// add new update func!!!
FlxG.stage.addEventListener('enterFrame', onUpdate);

// set stuff back
