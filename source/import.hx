#if !macro
// Core paths and file system
import backend.Paths;

#if sys
import sys.*;
import sys.io.*;
#elseif js
import js.html.*;
#end

// Backend game data types
import backend.songs.Section.SwagSection;
import backend.songs.Song.SwagSong;
import backend.game.WeekData.WeekFile;

#if desktop
import backend.Discord.DiscordClient;
#end

// Backend modules
import backend.*;
import backend.songs.*;
import backend.obj.*;
import backend.game.*;
import backend.player.*;

// Game modules
import shaders.*;
import obj.*;
import psych.obj.*;
import states.game.PlayState;
import states.*;
import states.menu.*;
import substates.*;
import substates.game.*;
import script.*;
import script.hscript.*;

// Android-specific imports (only on Android platform)
#if android
import android.backend.*;
import android.*;
import android.flixel.*;
#end

// Flixel core
import flixel.system.FlxSound;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.util.FlxDestroyUtil;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.addons.transition.FlxTransitionableState;
#end

using StringTools;
