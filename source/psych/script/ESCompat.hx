package psych.script;

import backend.Highscore;
import backend.MusicBeatState;
import backend.Paths;
import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.addons.display.FlxBackdrop;
import flixel.addons.effects.FlxTrail;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.ui.FlxBar;
import flixel.util.FlxAxes;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import openfl.Lib;
import openfl.filters.BitmapFilter;
import openfl.filters.ShaderFilter;
import openfl.utils.Assets as OpenFlAssets;
import psych.script.FunkinLua;
import states.LoadingState;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if (!flash && sys)
import flixel.addons.display.FlxRuntimeShader;
#end

/**
 * Typewriter state of a single Lua text (`setTextSpeed`).
 */
class ESTyping
{
	public var speed:Float = 0;
	public var full:String = '';
	public var index:Int = 0;
	public var timer:FlxTimer = null;

	public function new()
	{
	}

	public function stop():Void
	{
		if (timer != null)
		{
			timer.cancel();
			timer.destroy();
			timer = null;
		}
	}
}

/**
 * Song of the freeplay list, mirrors what FreeplayState builds out of WeekData.
 */
class ESFreeplaySong
{
	public var songName:String = '';
	public var week:Int = 0;
	public var folder:String = '';
	public var difficulties:String = null;

	public function new(songName:String, week:Int, folder:String, ?difficulties:String)
	{
		this.songName = songName;
		this.week = week;
		this.folder = folder;
		this.difficulties = difficulties;
	}
}

/**
 * Per script state of the ES compatibility layer.
 */
class ESState
{
	/** Steps already fired by stepEvent() */
	public var firedSteps:Map<Int, Bool> = new Map<Int, Bool>();

	/** makeShader() tags */
	public var shaders:Map<String, Dynamic> = new Map<String, Dynamic>();

	/** makeHealthBar() tags */
	public var healthBars:Map<String, FlxBar> = new Map<String, FlxBar>();

	/** makeVideoSprite() tags */
	public var videos:Map<String, FlxSprite> = new Map<String, FlxSprite>();

	/** makeTrailSpirit() tags */
	public var trails:Map<String, FlxTrail> = new Map<String, FlxTrail>();

	/** setTextSpeed() typewriters */
	public var typing:Map<String, ESTyping> = new Map<String, ESTyping>();

	/** Original singDuration of every character touched by setLongSing() */
	public var originalSingDuration:Map<String, Float> = new Map<String, Float>();

	/** MoveCamOnAnim() rules per character index */
	public var camRules:Map<Int, Map<String, Array<Float>>> = new Map<Int, Map<String, Array<Float>>>();

	/** Last animation each MoveCamOnAnim() character was seen playing, per character index */
	public var camRuleAnims:Map<Int, String> = new Map<Int, String>();

	/** Characters created with makeChar(), used to emulate onPlayAnim() */
	public var characters:Map<String, Character> = new Map<String, Character>();

	/** Last animation name seen by the onPlayAnim() emulation, per character tag */
	public var lastAnims:Map<String, String> = new Map<String, String>();

	public function new()
	{
	}

	public function destroy():Void
	{
		for (tag => typingState in typing)
			typingState.stop();
		typing.clear();

		for (tag => trail in trails)
			trail.destroy();
		trails.clear();

		shaders.clear();
		healthBars.clear();
		videos.clear();
		camRules.clear();
		camRuleAnims.clear();
		characters.clear();
		lastAnims.clear();
	}
}

/**
 * Compatibility layer for the "Engine Custom ES" Lua dialect.
 *
 * Registered at the end of the FunkinLua constructor, it only adds callbacks, so scripts
 * written for Psych keep behaving exactly as before. Functions that also exist in Psych
 * (`setProperty`, `doTween*`, ...) are not re-registered, the ES aliases simply reuse them.
 */
class ESCompat
{
	static var states:Map<FunkinLua, ESState> = new Map<FunkinLua, ESState>();
	static var freeplaySongs:Array<ESFreeplaySong> = null;

	public static function getState(funk:FunkinLua):ESState
	{
		var state:ESState = states.get(funk);
		if (state == null)
		{
			state = new ESState();
			states.set(funk, state);
		}
		return state;
	}

	public static function cleanup(funk:FunkinLua):Void
	{
		var state:ESState = states.get(funk);
		if (state == null)
			return;

		state.destroy();
		states.remove(funk);
	}

	// ------------------------------------------------------------------------
	// Registration
	// ------------------------------------------------------------------------

	public static function register(funk:FunkinLua):Void
	{
		if (funk == null)
			return;

		var state:ESState = getState(funk);

		#if (!flash && sys)
		var display = Lib.application.window.display;
		if (display != null)
		{
			funk.set('monitorWidth', display.bounds.width);
			funk.set('monitorHeight', display.bounds.height);
		}
		#end

		registerAliases(funk, state);
		registerObjects(funk, state);
		registerShaders(funk, state);
		registerTexts(funk, state);
		registerNotes(funk, state);
		registerMenus(funk, state);
		registerWindow(funk);
	}

	/** Shorthand aliases for existing Psych callbacks. */
	static function registerAliases(funk:FunkinLua, state:ESState):Void
	{
		funk.set('set', function(variable:String, value:Dynamic):Bool
		{
			if (variable == null)
				return warn(funk, 'set', 'Property name is missing!');

			return setPropertySafe(funk, variable, value);
		});

		funk.set('get', function(variable:String):Dynamic
		{
			if (variable == null)
			{
				warn(funk, 'get', 'Property name is missing!');
				return null;
			}

			return getPropertySafe(funk, variable);
		});

		funk.set('add', function(tag:String, ?front:Bool = false):Void
		{
			addObject(funk, tag, front);
		});

		funk.set('remove', function(tag:String):Void
		{
			removeObject(funk, tag);
		});

		funk.set('scale', function(tag:String, x:Float, y:Float, ?updateHitbox:Bool = true):Void
		{
			var spr:FlxSprite = getSpriteSafe(funk, tag);
			if (spr == null)
				return;

			spr.scale.set(x, y);
			if (updateHitbox)
				spr.updateHitbox();
		});

		funk.set('addAnim', function(tag:String, name:String, prefix:String, ?framerate:Int = 24, ?loop:Bool = true):Void
		{
			var spr:FlxSprite = getSpriteSafe(funk, tag);
			if (spr == null || name == null || prefix == null)
				return;

			spr.animation.addByPrefix(name, prefix, framerate, loop);
			if (spr.animation.curAnim == null)
				spr.animation.play(name, true);
		});

		funk.set('setCam', function(tag:String, camera:String = ''):Bool
		{
			var spr:FlxSprite = getSpriteSafe(funk, tag);
			if (spr == null)
				return false;

			spr.cameras = [FunkinLua.cameraFromString(camera)];
			return true;
		});

		funk.set('setOrder', function(tag:String, position:Int):Void
		{
			var obj:FlxBasic = getBasicSafe(funk, tag);
			var state2:FlxState = funk.getTargetState();
			if (obj == null || state2 == null)
				return;

			if (state2.members.contains(obj))
				state2.remove(obj, true);
			state2.insert(Std.int(Math.max(0, Math.min(position, state2.members.length))), obj);
		});

		funk.set('getOrder', function(tag:String):Int
		{
			var obj:FlxBasic = getBasicSafe(funk, tag);
			var state2:FlxState = funk.getTargetState();
			if (obj == null || state2 == null)
				return -1;

			return state2.members.indexOf(obj);
		});

		funk.set('setVelocity', function(tag:String, x:Float, y:Float):Void
		{
			var spr:FlxSprite = getSpriteSafe(funk, tag);
			if (spr == null)
				return;

			spr.velocity.set(x, y);
		});

		funk.set('doTweenScale', function(tag:String, obj:String, x:Float, y:Float, duration:Float, ?ease:String):Void
		{
			var target:Dynamic = FunkinLua.getObjectDirectly(obj);
			if (target == null || target.scale == null)
			{
				warn(funk, 'doTweenScale', 'Couldn\'t find object: $obj');
				return;
			}

			cancelTweenOf(funk, tag);
			// ES dialect: scaling keeps the sprite's visual center instead of its top-left
			var lastW:Float = target.width;
			var lastH:Float = target.height;
			var tween:FlxTween = FlxTween.tween(target.scale, {x: x, y: y}, duration, {
				ease: FunkinLua.getFlxEaseByString(ease),
				onUpdate: function(_)
				{
					var newW:Float = target.width;
					var newH:Float = target.height;
					target.x += (lastW - newW) / 2;
					target.y += (lastH - newH) / 2;
					lastW = newW;
					lastH = newH;
				}
			});
			registerTween(funk, tag, tween);
		});

		funk.set('setArray', function(properties:Dynamic, values:Dynamic):Void
		{
			var props:Array<Dynamic> = toArray(properties);
			var vals:Array<Dynamic> = toArray(values);
			var broadcast:Bool = vals.length != props.length;

			for (i in 0...props.length)
			{
				var value:Dynamic = broadcast ? (vals.length > 0 ? vals[0] : null) : vals[i];
				setPropertySafe(funk, Std.string(props[i]), value);
			}
		});

		funk.set('addArray', function(tags:Dynamic, ?front:Bool = false):Void
		{
			for (tag in toArray(tags))
				addObject(funk, Std.string(tag), front);
		});

		funk.set('getAnimName', function(tag:String):String
		{
			var spr:FlxSprite = getSpriteSafe(funk, tag);
			if (spr == null || spr.animation.curAnim == null)
				return '';

			return spr.animation.curAnim.name;
		});

		funk.set('scroll', function(tag:String, scrollX:Float, scrollY:Float):Void
		{
			var spr:FlxSprite = getSpriteSafe(funk, tag);
			if (spr == null)
				return;

			spr.scrollFactor.set(scrollX, scrollY);
		});

		// Every Lua script runs in its own state here, so a lerp() helper another script of
		// the song defined globally would be nil in this one. ES scripts assume it exists.
		funk.set('lerp', function(a:Float, b:Float, t:Float):Float
		{
			return FlxMath.lerp(a, b, t);
		});

		// ES registers ease names as plain globals, so scripts pass them unquoted
		// (e.g. doTweenY('t', 'obj', 0, 1, QuadOut)). Without these the identifier is nil
		// and the tween silently falls back to linear.
		for (easeName in [
			'linear',
			'quadIn',
			'quadOut',
			'quadInOut',
			'quartIn',
			'quartOut',
			'quartInOut',
			'quintIn',
			'quintOut',
			'quintInOut',
			'sineIn',
			'sineOut',
			'sineInOut',
			'expoIn',
			'expoOut',
			'expoInOut',
			'circIn',
			'circOut',
			'circInOut',
			'cubeIn',
			'cubeOut',
			'cubeInOut',
			'backIn',
			'backOut',
			'backInOut',
			'elasticIn',
			'elasticOut',
			'elasticInOut',
			'bounceIn',
			'bounceOut',
			'bounceInOut'
		])
		{
			funk.set(easeName, easeName);
			funk.set(easeName.charAt(0).toUpperCase() + easeName.substr(1), easeName);
		}
	}

	/** Sprites, characters, videos and health bars created by the ES dialect. */
	static function registerObjects(funk:FunkinLua, state:ESState):Void
	{
		funk.set('ColorBox', function(tag:String, color:String, x:Float = 0, y:Float = 0, width:Float = 0, height:Float = 0):Void
		{
			makeColorBox(funk, tag, color, x, y, width, height);
		});

		// ES argument order: makeColorBox(tag, x, y, width, height, color)
		funk.set('makeColorBox', function(tag:String, x:Float = 0, y:Float = 0, width:Float = 0, height:Float = 0, color:String = '000000'):Void
		{
			makeColorBox(funk, tag, color, x, y, width, height);
		});

		funk.set('BGSprite', function(tag:String, image:String, x:Float = 0, y:Float = 0, ?scrollX:Float = 1, ?scrollY:Float = 1):Void
		{
			if (tag == null || image == null)
				return;

			tag = tag.replace('.', '');
			var spr:BGSprite = new BGSprite(image, x, y, scrollX, scrollY);
			if (funk.menuMode)
				// ES menu states have no camera movement; BG sprites are plain screen-space
				// decorations, so the half-screen menu camera scroll must not displace them
				spr.scrollFactor.set(0, 0);
			FunkinLua.setESObject(tag, spr);
		});

		funk.set('FlxBackdrop', function(tag:String, image:String, x:Float = 0, y:Float = 0, ?axis:String = 'X'):Void
		{
			if (tag == null || image == null)
				return;

			tag = tag.replace('.', '');
			var backdrop:FlxBackdrop = new FlxBackdrop(Paths.image(image), axisFromString(axis));
			backdrop.x = x;
			backdrop.y = y;
			if (funk.menuMode)
				backdrop.scrollFactor.set(0, 0);
			FunkinLua.setESObject(tag, backdrop);
		});

		funk.set('makeChar', function(tag:String, character:String, x:Float = 0, y:Float = 0, ?isPlayer:Bool = false):Void
		{
			if (tag == null || character == null)
				return;

			if (funk.menuMode || PlayState.instance == null)
			{
				warn(funk, 'makeChar', 'Characters are only available while a song is playing!');
				return;
			}

			tag = tag.replace('.', '');
			var char:Character = new Character(x, y, character, isPlayer);
			state.characters.set(tag, char);
			FunkinLua.setESObject(tag, char);
		});

		funk.set('setLongSing', function(characters:String, value:Bool = true):Void
		{
			if (characters == null)
				return;

			for (name in characters.split(','))
			{
				var char:Character = findCharacter(funk, name);
				if (char == null)
				{
					warn(funk, 'setLongSing', 'Couldn\'t find character: $name');
					continue;
				}

				if (!state.originalSingDuration.exists(char.curCharacter))
					state.originalSingDuration.set(char.curCharacter, char.singDuration);

				var original:Null<Float> = state.originalSingDuration.get(char.curCharacter);
				char.singDuration = value ? 9999 : (original != null ? original : 4);
			}
		});

		funk.set('MoveCamOnAnim', function(charIdx:Int, anim:String, x:Float = 0, y:Float = 0):Void
		{
			var playState:PlayState = PlayState.instance;
			if (playState == null || funk.menuMode || anim == null)
				return;

			var rules:Map<String, Array<Float>> = state.camRules.get(charIdx);
			if (rules == null)
			{
				rules = new Map<String, Array<Float>>();
				state.camRules.set(charIdx, rules);
			}
			rules.set(anim, [x, y]);
		});

		funk.set('makeHealthBar', function(tag:String, x:Float = 0, y:Float = 0):Void
		{
			var playState:PlayState = PlayState.instance;
			if (tag == null || playState == null || funk.menuMode)
				return;

			tag = tag.replace('.', '');
			var ref:FlxBar = playState.healthBar;
			var width:Int = ref != null ? Std.int(ref.width) : 600;
			var height:Int = ref != null ? Std.int(ref.height) : 20;
			var isOpponent:Bool = tag.toLowerCase().indexOf('dad') > -1 || tag.toLowerCase().indexOf('opponent') > -1;

			// ES positions custom bars relative to the engine's own health bar
			var barX:Float = (ref != null ? ref.x : (FlxG.width - width) / 2) + x;
			var barY:Float = (ref != null ? ref.y : 0) + y;

			var bar:FlxBar = new FlxBar(barX, barY, isOpponent ? RIGHT_TO_LEFT : LEFT_TO_RIGHT, width, height, playState, 'health', 0, 2);
			bar.createFilledBar(0xFFFF0000, 0xFF00FF00);
			bar.scrollFactor.set();
			if (playState.camHUD != null)
				bar.cameras = [playState.camHUD];
			bar.visible = true;

			state.healthBars.set(tag, bar);
			FunkinLua.setESObject(tag, bar);
		});

		funk.set('makeVideoSprite',
			function(tag:String, path:String, x:Float = 0, y:Float = 0, ?width:Float = 0, ?height:Float = 0, ?options:String = null):Void
			{
				if (tag == null || path == null)
					return;

				#if VIDEOS_ALLOWED
				if (funk.menuMode || PlayState.instance == null)
				{
					warn(funk, 'makeVideoSprite', 'Videos are only available while a song is playing!');
					return;
				}

				tag = tag.replace('.', '');
				var optionsArray:Array<String> = [];
				if (options != null && options.length > 0)
					optionsArray.push(options.toLowerCase() == 'looping' ? PsychVideoSprite.looping : options);

				var video:ModchartVideoSprite = new ModchartVideoSprite(false);
				if (!video.load(Paths.video(path), optionsArray))
				{
					warn(funk, 'makeVideoSprite', 'Video file not found: ' + path);
					video.destroy();
					return;
				}

				video.x = x;
				video.y = y;
				if (width > 0 && height > 0)
				{
					video.addCallback('onFormat', function()
					{
						video.setGraphicSize(Std.int(width), Std.int(height));
						video.updateHitbox();
					});
				}

				state.videos.set(tag, video);
				FunkinLua.setESObject(tag, video);
				#else
				warn(funk, 'makeVideoSprite', 'Videos are not supported on this platform!');
				#end
			});

		funk.set('videoPlay', function(tag:String):Void
		{
			var video:FlxSprite = state.videos.get(tag);
			if (video == null)
			{
				warn(funk, 'videoPlay', 'Couldn\'t find video: $tag');
				return;
			}

			#if VIDEOS_ALLOWED
			var videoSprite:PsychVideoSprite = cast video;
			videoSprite.play();
			#end
		});

		funk.set('makeTrailSpirit', function(tag:String, target:String, ?color:String = 'FFFFFF'):Void
		{
			if (tag == null || target == null)
				return;

			if (funk.menuMode || PlayState.instance == null)
			{
				warn(funk, 'makeTrailSpirit', 'Trails are only available while a song is playing!');
				return;
			}

			var targetSprite:FlxSprite = getSpriteSafe(funk, target);
			if (targetSprite == null)
				return;

			tag = tag.replace('.', '');
			var trail:FlxTrail = new FlxTrail(targetSprite, null, 10, 3, 0.2, 0.05);
			state.trails.set(tag, trail);
			FunkinLua.setESObject(tag, trail);
		});

		funk.set('trailDirection', function(tag:String, direction:String):Void
		{
			var trail:FlxTrail = state.trails.get(tag);
			if (trail == null || direction == null)
				return;

			switch (direction.toLowerCase().trim())
			{
				case 'x':
					trail.xEnabled = true;
					trail.yEnabled = false;
				case 'y':
					trail.xEnabled = false;
					trail.yEnabled = true;
				case 'none' | 'static':
					trail.xEnabled = false;
					trail.yEnabled = false;
				default: // 'follow'
					trail.xEnabled = true;
					trail.yEnabled = true;
			}
		});

		funk.set('trailSpeed', function(tag:String, speed:Float):Void
		{
			// FlxTrail has no speed setting, the trail follows the target's own movement
			var trail:FlxTrail = state.trails.get(tag);
			if (trail == null)
				return;

			@:privateAccess trail._difference = Math.max(0.001, speed / 1000);
		});

		funk.set('trailDelay', function(tag:String, delay:Float):Void
		{
			var trail:FlxTrail = state.trails.get(tag);
			if (trail == null)
				return;

			trail.delay = Std.int(Math.max(1, Math.round(delay * 60)));
		});

		funk.set('trailAlpha', function(tag:String, alpha:Float):Void
		{
			var trail:FlxTrail = state.trails.get(tag);
			if (trail == null)
				return;

			@:privateAccess trail._transp = alpha;
		});

		funk.set('trailLife', function(tag:String, life:Float):Void
		{
			var trail:FlxTrail = state.trails.get(tag);
			if (trail == null)
				return;

			// The trail lasts (length * delay) frames, keep the delay we were given
			var delay:Float = Math.max(1, trail.delay) / 60;
			var wanted:Int = Std.int(Math.max(1, Math.round(life / delay)));
			@:privateAccess trail.increaseLength(wanted - trail._trailLength);
		});
	}

	/** Runtime shaders, ES stores them by their own tag instead of by sprite. */
	static function registerShaders(funk:FunkinLua, state:ESState):Void
	{
		#if (!flash && sys)
		funk.set('makeShader', function(tag:String, name:String):Bool
		{
			if (tag == null || name == null)
				return warn(funk, 'makeShader', 'Missing shader tag/name!');

			if (!ClientPrefs.shaders)
				return false;

			var sources:Array<String> = loadShaderSources(name);
			if (sources == null)
				return warn(funk, 'makeShader', 'Missing shader $name .frag AND .vert files!');

			var shader:FlxRuntimeShader = new FlxRuntimeShader(sources[0], sources[1]);
			state.shaders.set(tag, shader);

			// Let the regular setSpriteShader()/initLuaShader() find it too
			var playState:PlayState = PlayState.instance;
			if (playState != null && !playState.runtimeShaders.exists(name))
				playState.runtimeShaders.set(name, sources);
			return true;
		});

		funk.set('setCameraShader', function(camera:String, shaders:Dynamic):Bool
		{
			var cam:FlxCamera = FunkinLua.cameraFromString(camera);
			if (cam == null)
				return warn(funk, 'setCameraShader', 'Couldn\'t find camera: $camera');

			var filters:Array<BitmapFilter> = [];
			for (tag in toArray(shaders))
			{
				var shader:Dynamic = state.shaders.get(Std.string(tag));
				if (shader == null)
				{
					warn(funk, 'setCameraShader', 'Couldn\'t find shader: ' + tag);
					continue;
				}
				filters.push(new ShaderFilter(cast shader));
			}

			cam.setFilters(filters);
			return true;
		});
		#end

		funk.set('doTweenFloatArray', function(tag:String, names:Dynamic, values:Dynamic, duration:Float, ?ease:String):Void
		{
			var vars:Array<Dynamic> = toArray(names);
			var targets:Array<Dynamic> = toArray(values);
			if (tag == null || vars.length < 1 || targets.length < 1)
				return;

			if (targets.length != vars.length && targets.length == 1)
			{
				var single:Dynamic = targets[0];
				targets = [for (i in 0...vars.length) single];
			}

			var from:Array<Float> = [];
			for (i in 0...vars.length)
				from.push(toFloat(getVarValue(Std.string(vars[i]))));

			cancelTweenOf(funk, tag);
			var tween:FlxTween = FlxTween.num(0, 1, duration, {
				ease: FunkinLua.getFlxEaseByString(ease),
				onUpdate: function(twn:FlxTween)
				{
					var varsMap:Map<String, Dynamic> = FunkinLua.getVariablesMap();
					for (i in 0...vars.length)
					{
						var start:Float = from[i];
						var end:Float = toFloat(targets[i]);
						varsMap.set(Std.string(vars[i]), start + (end - start) * twn.percent);
					}
				}
			});
			registerTween(funk, tag, tween);
		});

		funk.set('setVarArray', function(names:Dynamic, values:Dynamic):Void
		{
			var vars:Array<Dynamic> = toArray(names);
			var vals:Array<Dynamic> = toArray(values);
			var broadcast:Bool = vals.length != vars.length;
			var varsMap:Map<String, Dynamic> = FunkinLua.getVariablesMap();

			for (i in 0...vars.length)
			{
				var name:String = Std.string(vars[i]);
				var value:Dynamic = broadcast ? (vals.length > 0 ? vals[0] : null) : vals[i];
				varsMap.set(name, value);
				funk.set(name, value);
			}
		});
	}

	/** Typewriter texts and gradients. */
	static function registerTexts(funk:FunkinLua, state:ESState):Void
	{
		funk.set('setText', function(tag:String, text:String):Bool
		{
			var obj:FlxText = getTextSafe(funk, tag);
			if (obj == null)
				return false;

			var typingState:ESTyping = state.typing.get(tag);
			if (typingState != null && typingState.speed > 0 && text != null && text.length > 1)
			{
				startTyping(funk, state, tag, obj, text, typingState.speed);
				return true;
			}

			obj.text = text;
			return true;
		});

		funk.set('setTextAlign', function(tag:String, alignment:String = 'left'):Bool
		{
			var obj:FlxText = getTextSafe(funk, tag);
			if (obj == null)
				return false;

			obj.alignment = LEFT;
			switch (alignment.trim().toLowerCase())
			{
				case 'right':
					obj.alignment = RIGHT;
				case 'center':
					obj.alignment = CENTER;
			}
			return true;
		});

		funk.set('setTextSpeed', function(tag:String, speed:Float):Void
		{
			if (tag == null)
				return;

			var typingState:ESTyping = state.typing.get(tag);
			if (typingState == null)
			{
				typingState = new ESTyping();
				state.typing.set(tag, typingState);
			}

			typingState.speed = speed;
			if (speed <= 0)
				typingState.stop();
		});

		funk.set('setTextGradient', function(tag:String, color1:String, color2:String = null, angle:Float = 0):Void
		{
			var obj:FlxText = getTextSafe(funk, tag);
			if (obj == null || color1 == null)
				return;

			// FlxText has no gradient support, approximate it with the top color
			obj.color = FlxColor.fromString('#' + color1.replace('#', '').replace('0x', ''));
		});
	}

	/** Notes and strums of the strumline. */
	static function registerNotes(funk:FunkinLua, state:ESState):Void
	{
		funk.set('setNoteY', function(note:Int, y:Float):Void
		{
			var strum:StrumNote = getStrum(funk, note);
			if (strum != null)
				strum.y = y;
		});

		funk.set('setNoteAngle', function(note:Int, angle:Float):Void
		{
			var strum:StrumNote = getStrum(funk, note);
			if (strum != null)
				strum.angle = angle;
		});

		funk.set('setStrumY', function(group:String, y:Float):Void
		{
			for (strum in getStrums(funk, group))
				strum.y = y;
		});

		funk.set('setStrumPos', function(group:String, x:Float, y:Float):Void
		{
			for (strum in getStrums(funk, group))
				strum.setPosition(x, y);
		});

		funk.set('setStrumAlpha', function(group:String, alpha:Float):Void
		{
			for (strum in getStrums(funk, group))
				strum.alpha = alpha;
		});

		funk.set('strumTweenX', function(tag:String, group:String, x:Float, duration:Float, ?ease:String):Void
		{
			var strums:Array<StrumNote> = getStrums(funk, group);
			if (strums.length < 1 || tag == null)
				return;

			cancelTweenOf(funk, tag);
			var tween:FlxTween = null;
			for (strum in strums)
			{
				var t:FlxTween = FlxTween.tween(strum, {x: x}, duration, {ease: FunkinLua.getFlxEaseByString(ease)});
				if (tween == null)
					tween = t;
			}
			registerTween(funk, tag, tween);
		});

		funk.set('strumTweenAlpha', function(tag:String, group:String, alpha:Float, duration:Float, ?ease:String):Void
		{
			var strums:Array<StrumNote> = getStrums(funk, group);
			if (strums.length < 1 || tag == null)
				return;

			cancelTweenOf(funk, tag);
			var tween:FlxTween = null;
			for (strum in strums)
			{
				var t:FlxTween = FlxTween.tween(strum, {alpha: alpha}, duration, {ease: FunkinLua.getFlxEaseByString(ease)});
				if (tween == null)
					tween = t;
			}
			registerTween(funk, tag, tween);
		});

		funk.set('stepEvent', function(stepOrTable:Dynamic, ?func:Dynamic):Void
		{
			var steps:Array<Int> = toIntArray(stepOrTable);
			if (steps.length < 1 || func == null)
				return;

			var current:Int = funk.lastEventSetStep;
			for (step in steps)
			{
				if (state.firedSteps.exists(step))
					continue;

				if (current < step)
					continue;

				state.firedSteps.set(step, true);
				callLuaFunction(funk, func, []);
				return; // the callback was consumed
			}

			// Nothing fired, drop the Lua function reference so it doesn't pile up
			disposeLuaFunction(func);
		});
	}

	/** Custom menu states, freeplay helpers and menu music. */
	static function registerMenus(funk:FunkinLua, state:ESState):Void
	{
		funk.set('switchLuaMenu', function(name:String):Bool
		{
			if (name == null || name.length < 1)
				return warn(funk, 'switchLuaMenu', 'Missing state name!');

			if (name.endsWith('.lua'))
				name = name.substr(0, name.length - 4);

			var nextState:LuaSState = new LuaSState(name);
			MusicBeatState.switchState(nextState);
			return true;
		});

		funk.set('switchSourceMenu', function(name:String):Bool
		{
			if (name == null || name.length < 1)
				return warn(funk, 'switchSourceMenu', 'Missing state name!');

			var stateClass:Class<Dynamic> = null;
			for (candidate in [
				'options.$name',
				'states.menu.$name',
				'states.$name',
				'substates.$name',
				'substates.game.$name',
				'$name'
			])
			{
				stateClass = Type.resolveClass(candidate);
				if (stateClass != null)
					break;
			}

			if (stateClass == null)
				return warn(funk, 'switchSourceMenu', 'Unknown state: ' + name);

			var nextState:FlxState = null;
			try
			{
				nextState = cast Type.createInstance(stateClass, []);
			}
			catch (e:Dynamic)
			{
				return warn(funk, 'switchSourceMenu', 'Couldn\'t create $name: ' + e);
			}

			if (nextState == null)
				return warn(funk, 'switchSourceMenu', 'Couldn\'t create state: ' + name);

			MusicBeatState.switchState(nextState);
			return true;
		});

		funk.set('playMenuMusic', function(name:String, ?volume:Float = 1, ?loop:Bool = true):Void
		{
			if (name == null)
				return;

			FlxG.sound.playMusic(Paths.music(name), volume, loop);
		});

		funk.set('preloadSound', function(name:String):Void
		{
			if (name != null)
				Paths.sound(name);
		});

		funk.set('getFreeplaySongCount', function():Int
		{
			return getFreeplaySongs().length;
		});

		funk.set('getFreeplaySongName', function(index:Int):String
		{
			var song:ESFreeplaySong = getFreeplaySong(index);
			return song != null ? song.songName : null;
		});

		funk.set('getFreeplaySongDisplay', function(index:Int):String
		{
			// Psych songs have no separate display name
			var song:ESFreeplaySong = getFreeplaySong(index);
			return song != null ? song.songName : null;
		});

		funk.set('getFreeplayDiffCount', function(index:Int):Int
		{
			var song:ESFreeplaySong = getFreeplaySong(index);
			return song != null ? getSongDifficulties(song).length : 0;
		});

		funk.set('getFreeplayDiffName', function(index:Int, difficulty:Int):String
		{
			var song:ESFreeplaySong = getFreeplaySong(index);
			if (song == null)
				return null;

			var diffs:Array<String> = getSongDifficulties(song);
			if (diffs.length < 1)
				return null;

			if (difficulty < 0)
				difficulty = 0;
			if (difficulty >= diffs.length)
				difficulty = diffs.length - 1;
			return diffs[difficulty];
		});

		funk.set('startFreeplaySongIndex', function(index:Int, ?difficulty:Int = 0):Bool
		{
			return startFreeplaySong(funk, index, difficulty);
		});
	}

	/** Window helpers. The transparent-window and taskbar ones need the Windows API. */
	static function registerWindow(funk:FunkinLua):Void
	{
		funk.set('isFullscreen', function(?value:Bool):Bool
		{
			#if (!flash && sys)
			var window = Lib.application.window;
			if (window == null)
				return false;

			if (value != null)
				window.fullscreen = value;
			return window.fullscreen;
			#else
			return false;
			#end
		});

		funk.set('setWindowScale', function(width:Float, ?height:Float = 0):Void
		{
			#if (!flash && sys)
			var window = Lib.application.window;
			if (window == null)
				return;

			var newWidth:Int = Std.int(width);
			var newHeight:Int = Std.int(height > 0 ? height : (width * 9 / 16));
			if (newWidth < 1 || newHeight < 1)
			{
				warn(funk, 'setWindowScale', 'Invalid window size: ${newWidth}x${newHeight}');
				return;
			}

			window.resize(newWidth, newHeight);
			#else
			warn(funk, 'setWindowScale', 'Window control is not supported on this platform!');
			#end
		});

		funk.set('doBorderless', function():Void
		{
			#if (!flash && sys)
			var window = Lib.application.window;
			if (window != null)
				window.borderless = true;
			#else
			warn(funk, 'doBorderless', 'Window control is not supported on this platform!');
			#end
		});

		funk.set('removeBorderless', function():Void
		{
			#if (!flash && sys)
			var window = Lib.application.window;
			if (window != null)
				window.borderless = false;
			#else
			warn(funk, 'removeBorderless', 'Window control is not supported on this platform!');
			#end
		});

		// These need the Windows WS_EX_LAYERED/Shell_TrayWnd APIs, so they only do anything on
		// a Windows desktop build (see cpp.CPPWindows), the rest gets a warning instead.
		funk.set('doTransWindow', function():Void
		{
			setWindowTransparent(funk, 'doTransWindow', true);
		});

		funk.set('removeTransWindow', function():Void
		{
			setWindowTransparent(funk, 'removeTransWindow', false);
		});

		funk.set('HideTaskBar', function():Void
		{
			setTaskBarVisible(funk, 'HideTaskBar', false);
		});

		funk.set('RestoreTaskBar', function():Void
		{
			setTaskBarVisible(funk, 'RestoreTaskBar', true);
		});

		funk.set('SystemClose', function():Void
		{
			#if sys
			Sys.exit(0);
			#else
			warn(funk, 'SystemClose', 'SystemClose is only available on desktop!');
			#end
		});
	}

	/** ES `doTransWindow()`/`removeTransWindow()`: layered window, black is the transparent color. */
	static function setWindowTransparent(funk:FunkinLua, func:String, enable:Bool):Void
	{
		#if (cpp && windows)
		cpp.CPPInterface.setWindowTransparent(enable);
		#else
		warn(funk, func, 'Transparent windows are Windows only, $func() is ignored.');
		#end
	}

	/** ES `HideTaskBar()`/`RestoreTaskBar()`. */
	static function setTaskBarVisible(funk:FunkinLua, func:String, visible:Bool):Void
	{
		#if (cpp && windows)
		cpp.CPPInterface.setTaskBarVisible(visible);
		#else
		warn(funk, func, 'The taskbar is Windows only, $func() is ignored.');
		#end
	}

	// ------------------------------------------------------------------------
	// Shared helpers
	// ------------------------------------------------------------------------

	/** ES dialect: setHealthBarColors(barTag, leftHex, rightHex) */
	public static function setHealthBarColors(funk:FunkinLua, tag:String, leftHex:String, rightHex:String):Void
	{
		var state:ESState = states.get(funk);
		if (state == null)
			return;

		var bar:FlxBar = state.healthBars.get(tag);
		if (bar == null)
		{
			warn(funk, 'setHealthBarColors', 'Couldn\'t find health bar: $tag');
			return;
		}

		bar.createFilledBar(parseColor(leftHex), parseColor(rightHex));
		bar.updateBar();
	}

	static function parseColor(color:String):FlxColor
	{
		if (color == null || color.length < 1)
			return FlxColor.WHITE;

		if (!color.startsWith('0x'))
			color = '0xff' + color.replace('#', '');

		var parsed:Null<Int> = Std.parseInt(color);
		return parsed == null ? FlxColor.WHITE : parsed;
	}

	/**
	 * Per frame housekeeping, called before every Lua `onUpdate` of this script.
	 * Emulates the ES `onPlayAnim` callback and re-anchors the camera for MoveCamOnAnim().
	 */
	public static function tick(funk:FunkinLua):Void
	{
		var state:ESState = states.get(funk);
		var playState:PlayState = PlayState.instance;
		if (state == null || playState == null || funk.menuMode)
			return;

		// onPlayAnim(tag, anim) fires whenever a character starts another animation
		checkPlayAnim(funk, state, playState, 'boyfriend', playState.boyfriend);
		checkPlayAnim(funk, state, playState, 'dad', playState.dad);
		checkPlayAnim(funk, state, playState, 'gf', playState.gf);

		for (tag => char in state.characters)
			checkPlayAnim(funk, state, playState, tag, char);

		// A character that switches to a registered animation takes the camera with it,
		// so the last one to change animation owns it
		var indices:Array<Int> = [for (charIdx in state.camRules.keys()) charIdx];
		indices.sort(function(a:Int, b:Int):Int return a - b);
		for (charIdx in indices)
		{
			var rules:Map<String, Array<Float>> = state.camRules.get(charIdx);
			var char:Character = getCharacterByIdx(playState, charIdx);
			if (rules == null || char == null || char.animation.curAnim == null)
				continue;

			var anim:String = char.animation.curAnim.name;
			if (state.camRuleAnims.get(charIdx) == anim)
				continue;

			state.camRuleAnims.set(charIdx, anim);

			var rule:Array<Float> = rules.get(anim);
			if (rule == null)
				continue;

			// "Camera Follow Pos" rides own the camera while they last
			if (playState.isCameraOnForcedPos)
				continue;

			anchorCamera(playState, charIdx, char);
			playState.camFollow.x += rule[0];
			playState.camFollow.y += rule[1];
		}
	}

	/**
	 * Moves `camFollow` onto a character the same way `PlayState.moveCamera()` does,
	 * including the character's own camera position and the stage's camera offsets.
	 */
	static function anchorCamera(playState:PlayState, charIdx:Int, char:Character):Void
	{
		var camFollow:FlxPoint = playState.camFollow;
		if (camFollow == null)
			return;

		var midpoint:FlxPoint = char.getMidpoint();
		var camPos:Array<Float> = char.cameraPosition;

		switch (charIdx)
		{
			case 0:
				camFollow.set(midpoint.x + 150, midpoint.y - 100);
				camFollow.x += getAxis(camPos, 0) + getAxis(playState.opponentCameraOffset, 0);
				camFollow.y += getAxis(camPos, 1) + getAxis(playState.opponentCameraOffset, 1);
			case 1:
				camFollow.set(midpoint.x - 100, midpoint.y - 100);
				camFollow.x -= getAxis(camPos, 0) - getAxis(playState.boyfriendCameraOffset, 0);
				camFollow.y += getAxis(camPos, 1) + getAxis(playState.boyfriendCameraOffset, 1);
			case 2:
				camFollow.set(midpoint.x, midpoint.y);
				camFollow.x += getAxis(camPos, 0) + getAxis(playState.girlfriendCameraOffset, 0);
				camFollow.y += getAxis(camPos, 1) + getAxis(playState.girlfriendCameraOffset, 1);
		}
	}

	/** Character and stage data may leave these arrays out, in which case they count as zero */
	static function getAxis(values:Array<Float>, index:Int):Float
	{
		return (values == null || values.length <= index) ? 0 : values[index];
	}

	static function checkPlayAnim(funk:FunkinLua, state:ESState, playState:PlayState, tag:String, char:Character):Void
	{
		if (char == null || char.animation.curAnim == null)
			return;

		var anim:String = char.animation.curAnim.name;
		if (state.lastAnims.get(tag) == anim)
			return;

		state.lastAnims.set(tag, anim);
		funk.dispatchCall('onPlayAnim', [tag, anim]);
	}

	/** Runtime shader of an ES `makeShader()` tag, used by setShaderFloat() & co. */
	#if (!flash && sys)
	public static function getShader(funk:FunkinLua, tag:String):FlxRuntimeShader
	{
		var state:ESState = states.get(funk);
		if (state == null || tag == null)
			return null;

		var shader:Dynamic = state.shaders.get(tag);
		if (shader == null)
			return null;

		var runtime:FlxRuntimeShader = cast shader;
		return runtime;
	}
	#else
	public static function getShader(funk:FunkinLua, tag:String):Dynamic
	{
		return null;
	}
	#end

	static function setPropertySafe(funk:FunkinLua, variable:String, value:Dynamic):Bool
	{
		var split:Array<String> = variable.split('.');
		if (split.length > 1)
		{
			var obj:Dynamic = FunkinLua.getPropertyLoopThingWhatever(split);
			if (obj == null)
			{
				warn(funk, 'set', 'Couldn\'t find object: $variable');
				return false;
			}

			try
			{
				FunkinLua.setVarInArray(obj, split[split.length - 1], value);
			}
			catch (e:Dynamic)
			{
				// ES scripts are allowed to write plain script variables; keep them in the
				// script variable map instead of aborting the whole callback on a bad field
				FunkinLua.getVariablesMap().set(variable, value);
				warn(funk, 'set', 'Couldn\'t set property: $variable');
			}
			return true;
		}

		try
		{
			FunkinLua.setVarInArray(FunkinLua.getInstance(), variable, value);
		}
		catch (e:Dynamic)
		{
			FunkinLua.getVariablesMap().set(variable, value);
		}
		return true;
	}

	static function getPropertySafe(funk:FunkinLua, variable:String):Dynamic
	{
		var split:Array<String> = variable.split('.');
		if (split.length > 1)
		{
			var obj:Dynamic = FunkinLua.getPropertyLoopThingWhatever(split);
			if (obj == null)
				return null;

			return FunkinLua.getVarInArray(obj, split[split.length - 1]);
		}

		return FunkinLua.getVarInArray(FunkinLua.getInstance(), variable);
	}

	static function addObject(funk:FunkinLua, tag:String, ?front:Bool = false):Void
	{
		if (tag == null)
		{
			warn(funk, 'add', 'Missing object tag!');
			return;
		}

		if (funk.spriteMap().exists(tag))
		{
			var spr:ModchartSprite = funk.spriteMap().get(tag);
			if (spr.wasAdded)
				return;

			addBasic(funk, spr, front);
			spr.wasAdded = true;
			return;
		}

		if (funk.textMap().exists(tag))
		{
			var text:ModchartText = funk.textMap().get(tag);
			if (text.wasAdded)
				return;

			addBasic(funk, text, front);
			text.wasAdded = true;
			return;
		}

		var obj:Dynamic = getESObject(funk, tag);
		if (obj != null && Std.isOfType(obj, FlxBasic))
		{
			addBasic(funk, cast obj, front);
			return;
		}

		warn(funk, 'add', 'Couldn\'t find object: $tag');
	}

	static function addBasic(funk:FunkinLua, obj:FlxBasic, front:Bool):Void
	{
		var state:FlxState = funk.getTargetState();
		if (state == null || state.members.indexOf(obj) > -1)
			return;

		if (funk.menuMode || PlayState.instance == null)
		{
			// ES menu states: plain append, creation order = draw order (front is a no-op)
			state.add(obj);
			return;
		}

		var playState:PlayState = PlayState.instance;

		if (front)
		{
			state.add(obj);
			return;
		}

		if (playState.isDead && GameOverSubstate.instance != null)
		{
			GameOverSubstate.instance.insert(GameOverSubstate.instance.members.indexOf(GameOverSubstate.instance.boyfriend), obj);
			return;
		}

		var position:Int = state.members.indexOf(playState.gfGroup);
		if (position < 0)
			position = state.members.length;
		var other:Int = state.members.indexOf(playState.boyfriendGroup);
		if (other > -1 && other < position)
			position = other;
		other = state.members.indexOf(playState.dadGroup);
		if (other > -1 && other < position)
			position = other;
		state.insert(position, obj);
	}

	static function removeObject(funk:FunkinLua, tag:String):Void
	{
		if (tag == null)
			return;

		var obj:Dynamic = null;
		if (funk.spriteMap().exists(tag))
			obj = funk.spriteMap().get(tag);
		else if (funk.textMap().exists(tag))
			obj = funk.textMap().get(tag);
		else
			obj = getESObject(funk, tag);

		if (obj == null || !Std.isOfType(obj, FlxBasic))
		{
			warn(funk, 'remove', 'Couldn\'t find object: $tag');
			return;
		}

		var basic:FlxBasic = cast obj;
		var state:FlxState = funk.getTargetState();
		if (state != null && state.members.indexOf(basic) > -1)
			state.remove(basic, true);

		funk.spriteMap().remove(tag);
		funk.textMap().remove(tag);
		FunkinLua.getVariablesMap().remove(tag);

		var esState:ESState = states.get(funk);
		if (esState != null)
		{
			esState.trails.remove(tag);
			esState.videos.remove(tag);
			esState.healthBars.remove(tag);
		}

		basic.destroy();
	}

	/** Looks up an ES object: Lua sprite, Lua text or anything stored as a variable. */
	static function getESObject(funk:FunkinLua, tag:String):Dynamic
	{
		if (tag == null)
			return null;

		if (funk.spriteMap().exists(tag))
			return funk.spriteMap().get(tag);
		if (funk.textMap().exists(tag))
			return funk.textMap().get(tag);

		var vars:Map<String, Dynamic> = FunkinLua.getVariablesMap();
		if (vars.exists(tag))
			return vars.get(tag);

		return FunkinLua.getObjectDirectly(tag);
	}

	static function getSpriteSafe(funk:FunkinLua, tag:String):FlxSprite
	{
		var obj:Dynamic = getESObject(funk, tag);
		if (obj == null || !Std.isOfType(obj, FlxSprite))
		{
			warn(funk, 'ES', 'Couldn\'t find sprite: $tag');
			return null;
		}
		return cast obj;
	}

	static function getBasicSafe(funk:FunkinLua, tag:String):FlxBasic
	{
		var obj:Dynamic = getESObject(funk, tag);
		if (obj == null || !Std.isOfType(obj, FlxBasic))
			return null;

		return cast obj;
	}

	static function getTextSafe(funk:FunkinLua, tag:String):FlxText
	{
		var obj:Dynamic = getESObject(funk, tag);
		if (obj == null || !Std.isOfType(obj, FlxText))
		{
			warn(funk, 'ES', 'Couldn\'t find text: $tag');
			return null;
		}
		return cast obj;
	}

	static function makeColorBox(funk:FunkinLua, tag:String, color:String, x:Float, y:Float, width:Float, height:Float):Void
	{
		if (tag == null || color == null)
		{
			warn(funk, 'makeColorBox', 'Missing tag or color!');
			return;
		}

		tag = tag.replace('.', '');
		// ES scripts either pass the real size or 0/1 as a placeholder for "whole screen"
		var boxWidth:Int = (width > 1) ? Std.int(width) : FlxG.width;
		var boxHeight:Int = (height > 1) ? Std.int(height) : FlxG.height;
		var spr:ModchartSprite = new ModchartSprite(x, y);
		if (funk.menuMode && (width <= 1 || height <= 1))
		{
			// ES menu color boxes are screen-space: render at raw coordinates so the
			// half-screen-scrolled menu camera can never uncover parts of the screen
			spr.scrollFactor.set(0, 0);
		}
		spr.makeGraphic(boxWidth, boxHeight, FlxColor.fromString('#' + color.replace('#', '').replace('0x', '')));
		funk.spriteMap().set(tag, spr);
	}

	static function getCharacterByIdx(playState:PlayState, index:Int):Character
	{
		// ES indexes characters as 0 = opponent, 1 = player, 2 = girlfriend
		switch (index)
		{
			case 0:
				return playState.dad;
			case 1:
				return playState.boyfriend;
			case 2:
				return playState.gf;
		}
		return null;
	}

	static function findCharacter(funk:FunkinLua, name:String):Character
	{
		var playState:PlayState = PlayState.instance;
		if (playState == null || funk.menuMode)
			return null;

		switch (name.toLowerCase().trim())
		{
			case 'dad' | 'opponent':
				return playState.dad;
			case 'boyfriend' | 'bf' | 'player':
				return playState.boyfriend;
			case 'gf' | 'girlfriend':
				return playState.gf;
		}

		var obj:Dynamic = getESObject(funk, name.trim());
		if (Std.isOfType(obj, Character))
			return cast obj;

		return null;
	}

	static function getStrum(funk:FunkinLua, note:Int):StrumNote
	{
		var playState:PlayState = PlayState.instance;
		if (playState == null || funk.menuMode || playState.strumLineNotes == null || playState.strumLineNotes.length < 1)
		{
			warn(funk, 'ES', 'Strums only exist while a song is playing!');
			return null;
		}

		if (note < 0)
			note = 0;
		return playState.strumLineNotes.members[note % playState.strumLineNotes.length];
	}

	static function getStrums(funk:FunkinLua, group:String):Array<StrumNote>
	{
		var strums:Array<StrumNote> = [];
		var playState:PlayState = PlayState.instance;
		if (playState == null || funk.menuMode || playState.strumLineNotes == null)
		{
			warn(funk, 'ES', 'Strums only exist while a song is playing!');
			return strums;
		}

		var groupName:String = group == null ? 'all' : group.toLowerCase().trim();
		switch (groupName)
		{
			case 'player' | 'bf' | 'boyfriend':
				for (strum in playState.playerStrums)
					strums.push(strum);
			case 'opponent' | 'dad' | 'enemy':
				for (strum in playState.opponentStrums)
					strums.push(strum);
			default:
				for (strum in playState.strumLineNotes)
					strums.push(strum);
		}
		return strums;
	}

	static function startTyping(funk:FunkinLua, state:ESState, tag:String, obj:FlxText, full:String, speed:Float):Void
	{
		var typingState:ESTyping = state.typing.get(tag);
		if (typingState == null)
		{
			typingState = new ESTyping();
			typingState.speed = speed;
			state.typing.set(tag, typingState);
		}

		typingState.stop();
		typingState.full = full;
		typingState.index = 0;
		obj.text = '';

		typingState.timer = new FlxTimer().start(speed, function(tmr:FlxTimer)
		{
			if (typingState.index >= full.length)
			{
				tmr.cancel();
				return;
			}

			typingState.index++;
			obj.text = full.substr(0, typingState.index);
			funk.dispatchCall('onTyping', [tag]);
		}, 0);
	}

	static function registerTween(funk:FunkinLua, tag:String, tween:FlxTween):Void
	{
		if (tween == null)
			return;

		tween.onComplete = function(twn:FlxTween)
		{
			funk.tweenMap().remove(tag);
			funk.dispatchCall('onTweenCompleted', [tag]);
		};
		funk.tweenMap().set(tag, tween);
	}

	static function cancelTweenOf(funk:FunkinLua, tag:String):Void
	{
		if (tag == null)
			return;

		var tweens:Map<String, FlxTween> = funk.tweenMap();
		if (tweens.exists(tag))
		{
			var tween:FlxTween = tweens.get(tag);
			tween.cancel();
			tween.destroy();
			tweens.remove(tag);
		}
	}

	static function getVarValue(name:String):Dynamic
	{
		var vars:Map<String, Dynamic> = FunkinLua.getVariablesMap();
		if (vars.exists(name))
			return vars.get(name);

		return null;
	}

	static function axisFromString(?axis:String):FlxAxes
	{
		if (axis == null)
			return FlxAxes.XY;

		switch (axis.toLowerCase().trim())
		{
			case 'x':
				return FlxAxes.X;
			case 'y':
				return FlxAxes.Y;
		}
		return FlxAxes.XY;
	}

	static function loadShaderSources(name:String):Array<String>
	{
		#if (!flash && sys)
		var foldersToCheck:Array<String> = [SUtil.getPath() + Paths.getPreloadPath('shaders/')];

		if (Paths.currentModDirectory != null && Paths.currentModDirectory.length > 0)
			foldersToCheck.insert(0, Paths.mods(Paths.currentModDirectory + '/shaders/'));

		for (mod in Paths.getGlobalMods())
			foldersToCheck.insert(0, Paths.mods(mod + '/shaders/'));

		for (folder in foldersToCheck)
		{
			if (!FileSystem.exists(folder))
				continue;

			var frag:String = folder + name + '.frag';
			var vert:String = folder + name + '.vert';
			var found:Bool = false;
			if (FileSystem.exists(frag))
			{
				frag = File.getContent(frag);
				found = true;
			}
			else
				frag = null;

			if (FileSystem.exists(vert))
			{
				vert = File.getContent(vert);
				found = true;
			}
			else
				vert = null;

			if (found)
				return [frag, vert];
		}
		#end
		return null;
	}

	/** Lua tables arrive as arrays or keyed objects, everything else is a single value. */
	static function toArray(value:Dynamic):Array<Dynamic>
	{
		if (value == null)
			return [];

		if (Std.isOfType(value, Array))
			return cast value;

		if (Reflect.isObject(value) && !Std.isOfType(value, String))
		{
			var values:Array<Dynamic> = [];
			for (key in Reflect.fields(value))
				values.push(Reflect.field(value, key));
			return values;
		}

		return [value];
	}

	static function toIntArray(value:Dynamic):Array<Int>
	{
		var ints:Array<Int> = [];
		for (entry in toArray(value))
		{
			var number:Float = toFloat(entry);
			ints.push(Std.int(number));
		}
		return ints;
	}

	static function toFloat(value:Dynamic):Float
	{
		if (value == null)
			return 0;

		if (Std.isOfType(value, Float) || Std.isOfType(value, Int))
			return cast value;

		var parsed:Null<Float> = Std.parseFloat(Std.string(value));
		return parsed == null ? 0 : parsed;
	}

	/** Calls the Lua function given as an argument and releases its reference. */
	static function callLuaFunction(funk:FunkinLua, func:Dynamic, args:Array<Dynamic>):Dynamic
	{
		if (func == null)
			return null;

		#if LUA_ALLOWED
		if (Std.isOfType(func, llua.LuaCallback))
		{
			var callback:llua.LuaCallback = cast func;
			var result:Dynamic = callLuaCallback(callback, args);
			callback.dispose();
			return result;
		}
		#end

		if (Reflect.isFunction(func))
			return Reflect.callMethod(null, func, args);

		warn(funk, 'ES', 'Expected a Lua function!');
		return null;
	}

	static function disposeLuaFunction(func:Dynamic):Void
	{
		#if LUA_ALLOWED
		if (func != null && Std.isOfType(func, llua.LuaCallback))
		{
			var callback:llua.LuaCallback = cast func;
			callback.dispose();
		}
		#end
	}

	#if LUA_ALLOWED
	/**
	 * llua.LuaCallback.call() checks Lua.isfunction(), whose LUA_TFUNCTION constant can
	 * disagree with the actually linked Luau VM (newer Luau inserts LUA_TINTEGER),
	 * which would make every stored Lua closure silently no-op. This is an
	 * enum-agnostic copy of that method: it asks the VM for the type name instead.
	 */
	static function callLuaCallback(callback:llua.LuaCallback, args:Array<Dynamic>):Dynamic
	{
		var l:llua.State = @:privateAccess callback.l;
		var ref:Dynamic = callback.ref;
		var useGlobalTable:Bool = @:privateAccess callback.useGlobalTable;

		if (useGlobalTable)
		{
			llua.Lua.getglobal(l, "__haxe_func_refs");
			llua.Lua.getfield(l, -1, cast(ref, String));
			llua.Lua.remove(l, -2);
		}
		else
		{
			llua.Lua.rawgeti(l, llua.Lua.LUA_REGISTRYINDEX, cast(ref, Int));
		}

		if (llua.Lua.typename(l, llua.Lua.type(l, -1)) != 'function')
		{
			llua.Lua.pop(l, 1);
			return null;
		}

		if (args == null)
			args = [];
		for (arg in args)
			llua.Convert.toLua(l, arg);

		var status:Int = llua.Lua.pcall(l, args.length, 1, 0);
		if (status != llua.Lua.LUA_OK)
		{
			var err:String = llua.Lua.tostring(l, -1);
			llua.Lua.pop(l, 1);
			trace("Error on callback: " + err);
			return null;
		}

		var result:Dynamic = llua.Convert.fromLua(l, -1);
		llua.Lua.pop(l, 1);
		return result;
	}
	#end

	static function warn(funk:FunkinLua, func:String, message:String):Bool
	{
		funk.luaTrace('$func: $message', false, false, FlxColor.RED);
		return false;
	}

	// ------------------------------------------------------------------------
	// Freeplay data
	// ------------------------------------------------------------------------

	static function getFreeplaySongs():Array<ESFreeplaySong>
	{
		if (freeplaySongs != null)
			return freeplaySongs;

		var songs:Array<ESFreeplaySong> = [];

		// ES dialect: the freeplay list only covers the active mod's own week files;
		// WeekData never loads them anyway when base weeks hog the same names
		var activeMod:String = Paths.currentModDirectory;
		#if MODS_ALLOWED
		if (activeMod != null && activeMod.length > 0)
		{
			var weeksDir:String = Paths.mods(activeMod + '/weeks');
			if (FileSystem.exists(weeksDir))
			{
				var names:Array<String> = [];
				var listPath:String = weeksDir + '/weekList.txt';
				if (FileSystem.exists(listPath))
					names = CoolUtil.coolTextFile(listPath);
				for (file in FileSystem.readDirectory(weeksDir))
				{
					if (!FileSystem.isDirectory(weeksDir + '/' + file) && file.endsWith('.json'))
					{
						var weekName:String = file.substr(0, file.length - 5);
						if (!names.contains(weekName))
							names.push(weekName);
					}
				}

				for (i in 0...names.length)
				{
					var parsed:Dynamic = null;
					try
					{
						parsed = haxe.Json.parse(File.getContent(weeksDir + '/' + names[i] + '.json'));
					}
					catch (e:Dynamic)
					{
						continue;
					}
					if (parsed == null || parsed.songs == null || parsed.hideFreeplay == true)
						continue;

					var startUnlocked:Bool = parsed.startUnlocked != false;
					var weekBefore:String = parsed.weekBefore != null ? Std.string(parsed.weekBefore) : '';
					if (!startUnlocked
						&& weekBefore.length > 0
						&& (!StoryMenuState.weekCompleted.exists(weekBefore) || !StoryMenuState.weekCompleted.get(weekBefore)))
						continue;

					for (song in (parsed.songs : Array<Dynamic>))
						songs.push(new ESFreeplaySong(Std.string(song[0]), i, activeMod, parsed.difficulties));
				}
			}

			freeplaySongs = songs;
			return freeplaySongs;
		}
		#end

		WeekData.reloadWeekFiles(false);

		for (i in 0...WeekData.weeksList.length)
		{
			var weekName:String = WeekData.weeksList[i];
			var leWeek:WeekData = WeekData.weeksLoaded.get(weekName);
			if (leWeek == null || weekIsLocked(weekName))
				continue;

			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs)
			{
				var folder:String = Paths.currentModDirectory;
				if (folder == null)
					folder = '';
				songs.push(new ESFreeplaySong(song[0], i, folder, leWeek.difficulties));
			}
		}

		WeekData.loadTheFirstEnabledMod();
		freeplaySongs = songs;
		return freeplaySongs;
	}

	static function weekIsLocked(name:String):Bool
	{
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		if (leWeek == null)
			return false;

		return (!leWeek.startUnlocked
			&& leWeek.weekBefore.length > 0
			&& (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
	}

	static function getFreeplaySong(index:Int):ESFreeplaySong
	{
		var songs:Array<ESFreeplaySong> = getFreeplaySongs();
		if (index < 0 || index >= songs.length)
			return null;

		return songs[index];
	}

	static function getSongDifficulties(song:ESFreeplaySong):Array<String>
	{
		var diffs:Array<String> = CoolUtil.defaultDifficulties.copy();
		var diffStr:String = song.difficulties;
		if (diffStr == null)
			return diffs;

		diffStr = diffStr.trim();
		if (diffStr.length < 1)
			return diffs;

		var weekDiffs:Array<String> = [];
		for (diff in diffStr.split(','))
		{
			var trimmed:String = diff.trim();
			if (trimmed.length > 0)
				weekDiffs.push(trimmed);
		}

		if (weekDiffs.length > 0 && weekDiffs[0].length > 0)
			return weekDiffs;

		return diffs;
	}

	static function startFreeplaySong(funk:FunkinLua, index:Int, difficulty:Int):Bool
	{
		var song:ESFreeplaySong = getFreeplaySong(index);
		if (song == null)
			return warn(funk, 'startFreeplaySongIndex', 'There is no song #$index!');

		var diffs:Array<String> = getSongDifficulties(song);
		if (difficulty < 0)
			difficulty = 0;
		if (difficulty >= diffs.length)
			difficulty = diffs.length - 1;

		var songLowercase:String = Paths.formatToSongPath(song.songName);
		CoolUtil.difficulties = diffs.copy();

		var poop:String = Highscore.formatSong(songLowercase, difficulty);
		#if MODS_ALLOWED
		var chartExists:Bool = FileSystem.exists(Paths.modsJson(songLowercase + '/' + poop))
			|| FileSystem.exists(Paths.json(songLowercase + '/' + poop));
		#else
		var chartExists:Bool = OpenFlAssets.exists(Paths.json(songLowercase + '/' + poop));
		#end
		if (!chartExists)
			return warn(funk, 'startFreeplaySongIndex', 'Chart file not found: ' + poop + '.json');

		Paths.currentModDirectory = song.folder;
		PlayState.storyWeek = song.week;
		PlayState.SONG = Song.loadFromJson(poop, songLowercase);
		PlayState.isStoryMode = false;
		PlayState.storyDifficulty = difficulty;

		LoadingState.loadAndSwitchState(new PlayState());
		return true;
	}
}
