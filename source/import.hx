#if !macro
// Package imports
import backend.Paths;
// Conditional imports - sys
#if sys
import sys.*;
import sys.io.*;
#elseif js
import js.html.*;
#end
// Conditional imports - desktop
#if desktop
import backend.Discord.DiscordClient;
#end
// Conditional imports - android
#if android
import android.backend.*;
import android.*;
import android.flixel.*;
#end
// Project imports - backend
import backend.*;
import backend.game.*;
import backend.game.WeekData.WeekFile;
import backend.obj.*;
import backend.player.*;
import backend.songs.*;
import backend.songs.Section.SwagSection;
import backend.songs.Song.SwagSong;
// Project imports - android
import android.backend.SUtil;
// Project imports - other
import shaders.*;
import obj.*;
import psych.obj.*;
import script.*;
import script.hscript.*;
import modchart.*;
// Project imports - states
import states.*;
import states.game.PlayState;
import states.menu.*;
import substates.*;
import substates.game.*;
// Flixel imports
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.system.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import flixel.util.FlxTimer;
#end

using StringTools;
