package obj;

#if MODS_ALLOWED
import sys.FileSystem;
import sys.io.File;
#end
import backend.DataType;
import backend.songs.Section.SwagSection;
import animateatlas.AtlasFrameMaker;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.effects.FlxTrail;
import flixel.animation.FlxBaseAnimation;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame.FlxFrameAngle;
import flixel.math.FlxRect;
import flixel.tweens.FlxTween;
import flixel.util.FlxSort;
import openfl.utils.Assets;
import openfl.utils.AssetType;
import haxe.Json;
import haxe.format.JsonParser;

using StringTools;

typedef CharacterFile =
{
	var animations:Array<AnimArray>;
	var image:String;
	var scale:Float;
	var sing_duration:Float;
	var healthicon:String;

	var position:Array<Float>;
	var camera_position:Array<Float>;
	var dataType:String;

	var flip_x:Bool;
	var flip_y:Bool;
	var no_antialiasing:Bool;
	var healthbar_colors:Array<Int>;
	var vocals_file:String;

	// Optional per-axis transform keys of the "Engine Custom ES" character format. Stock Psych
	// characters never write them, so they are null unless a mod asks for them.
	var scale_x:Null<Float>;
	var scale_y:Null<Float>;
	var skew_x:Null<Float>;
	var skew_y:Null<Float>;
	var angle:Null<Float>;
}

typedef AnimArray =
{
	var anim:String;
	var name:String;
	var fps:Int;
	var loop:Bool;
	var indices:Array<Int>;
	var offsets:Array<Int>;
}

class Character extends FlxSprite
{
	public var animOffsets:Map<String, Array<Dynamic>>;
	public var debugMode:Bool = false;

	public var isPlayer:Bool = false;
	public var curCharacter:String = DEFAULT_CHARACTER;

	public var colorTween:FlxTween;
	public var holdTimer:Float = 0;
	public var heyTimer:Float = 0;
	public var specialAnim:Bool = false;
	public var animationNotes:Array<Dynamic> = [];
	public var stunned:Bool = false;
	public var singDuration:Float = 4; // Multiplier of how long a character holds the sing pose
	public var idleSuffix:String = '';
	public var danceIdle:Bool = false; // Character use "danceLeft" and "danceRight" instead of "idle"
	public var skipDance:Bool = false;

	public var voicelining:Bool = false;

	public var healthIcon:String = 'face';
	public var animationsArray:Array<AnimArray> = [];

	public var positionArray:Array<Float> = [0, 0];
	public var cameraPosition:Array<Float> = [0, 0];

	public var hasMissAnimations:Bool = false;

	// Used on Character Editor
	public var imageFile:String = '';
	public var jsonScale:Float = 1;
	public var jsonScaleX:Float = 1;
	public var jsonScaleY:Float = 1;
	public var jsonSkewX:Float = 0;
	public var jsonSkewY:Float = 0;
	public var jsonAngle:Float = 0;
	public var noAntialiasing:Bool = false;
	public var originalFlipX:Bool = false;

	var animateAtlas:AtlasFrameMaker;

	public var healthColorArray:Array<Int> = [255, 0, 0];
	public var dataType:DataType;
	public var vocalsFile:String = '';

	public static var DEFAULT_CHARACTER:String = 'bf'; // In case a character is missing, it will use BF on its place

	public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false)
	{
		super(x, y);

		#if (haxe >= "4.0.0")
		animOffsets = new Map();
		#else
		animOffsets = new Map<String, Array<Dynamic>>();
		#end
		curCharacter = character;
		this.isPlayer = isPlayer;
		antialiasing = ClientPrefs.globalAntialiasing;
		var library:String = null;
		switch (curCharacter)
		{
			// case 'your character name in case you want to hardcode them instead':

			default:
				var characterPath:String = 'characters/' + curCharacter + '.json';

				#if MODS_ALLOWED
				var path:String = Paths.modFolders(characterPath);
				if (!FileSystem.exists(path))
				{
					path = SUtil.getPath() + Paths.getPreloadPath(characterPath);
				}

				if (!FileSystem.exists(path))
				#else
				var path:String = Paths.getPreloadPath(characterPath);
				if (!Assets.exists(path))
				#end
				{
					path = SUtil.getPath()
						+ Paths.getPreloadPath('characters/' + DEFAULT_CHARACTER +
							'.json'); // If a character couldn't be found, change him to BF just to prevent a crash
				}

				#if MODS_ALLOWED
				var rawJson = File.getContent(path);
				#else
				var rawJson = Assets.getText(path);
				#end

				var json:CharacterFile = cast Json.parse(rawJson);

				// sparrow
				// packer
				// texture

				imageFile = json.image;
				if (json.dataType != null)
					dataType = DataType.createByName(json.dataType.toUpperCase());
				else
					dataType = SPARROW;

				// Auto-detect Adobe Animate texture atlases (flxanimate): if the image path is a
				// folder with Animation.json + spritemap(1).json, read it as TEXTURE even when the
				// character JSON doesn't declare a dataType
				if (dataType == SPARROW
					&& imageFile != null
					&& Paths.fileExists('images/$imageFile/Animation.json', TEXT)
					&& (Paths.fileExists('images/$imageFile/spritemap.json', TEXT)
						|| Paths.fileExists('images/$imageFile/spritemap1.json', TEXT)))
				{
					dataType = TEXTURE;
				}

				if (imageFile != null && dataType != null)
				{
					switch (dataType)
					{
						case TEXTURE:
							// Adobe Animate texture atlas (flxanimate): images/<imageFile>/Animation.json + spritemap.png/.json
							frames = AtlasFrameMaker.construct(imageFile, null, json.no_antialiasing == true);
						default:
							frames = Paths.getAtlasFromData(imageFile, dataType);
					}
				}

				if (json.scale != 1)
					jsonScale = json.scale;

				if (json.scale_x != null || json.scale_y != null)
				{
					// ES per-axis scale: an explicit scale_x/scale_y is the ABSOLUTE axis scale,
					// not a multiplier of `scale` (a shadow character has to land on the footprint
					// of its real counterpart at its own scale_x, not at scale_x * scale).
					jsonScaleX = (json.scale_x != null ? json.scale_x : jsonScale);
					jsonScaleY = (json.scale_y != null ? json.scale_y : jsonScale);
					// setGraphicSize + updateHitbox keep width/height/offset/origin coherent for the
					// engine's offset math, so the non-uniform case goes through them as well
					setGraphicSize(Std.int(width * jsonScaleX), Std.int(height * jsonScaleY));
					updateHitbox();
				}
				else if (jsonScale != 1)
				{
					setGraphicSize(Std.int(width * jsonScale));
					updateHitbox();
				}

				if (json.skew_x != null)
					jsonSkewX = json.skew_x;
				if (json.skew_y != null)
					jsonSkewY = json.skew_y;

				if (json.angle != null && json.angle != 0)
				{
					jsonAngle = json.angle;
					angle = jsonAngle;
				}

				positionArray = json.position;
				cameraPosition = json.camera_position;

				healthIcon = json.healthicon;
				singDuration = json.sing_duration;
				flipX = !!json.flip_x;
				flipY = !!json.flip_y;
				if (json.no_antialiasing)
				{
					antialiasing = false;
					noAntialiasing = true;
				}

				if (json.healthbar_colors != null && json.healthbar_colors.length > 2)
					healthColorArray = json.healthbar_colors;

				if (json.vocals_file != null && json.vocals_file.length > 0)
					vocalsFile = json.vocals_file;

				antialiasing = !noAntialiasing;
				if (!ClientPrefs.globalAntialiasing)
					antialiasing = false;

				animationsArray = json.animations;
				if (animationsArray != null && animationsArray.length > 0)
				{
					for (anim in animationsArray)
					{
						var animAnim:String = '' + anim.anim;
						var animName:String = '' + anim.name;
						var animFps:Int = anim.fps;
						var animLoop:Bool = !!anim.loop; // Bruh
						var animIndices:Array<Int> = anim.indices;
						if (animIndices != null && animIndices.length > 0)
						{
							animation.addByIndices(animAnim, (dataType == TEXTURE) ? animName + '_' : animName, animIndices, "", animFps, animLoop);
						}
						else
						{
							// TEXTURE (Adobe Animate) atlases bake their frames as symbol_i, so the
							// separator keeps animations whose symbol names prefix each other apart
							animation.addByPrefix(animAnim, (dataType == TEXTURE) ? animName + '_' : animName, animFps, animLoop);
						}

						if (anim.offsets != null && anim.offsets.length > 1)
						{
							addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
						}
					}
				}
				else
				{
					quickAnimAdd('idle', 'BF idle dance');
				}
				// trace('Loaded file to character ' + curCharacter);
		}
		originalFlipX = flipX;

		if (animOffsets.exists('singLEFTmiss') || animOffsets.exists('singDOWNmiss') || animOffsets.exists('singUPmiss') || animOffsets.exists('singRIGHTmiss'))
			hasMissAnimations = true;
		recalculateDanceIdle();
		dance();

		if (isPlayer)
		{
			flipX = !flipX;

			/*// Doesn't flip for BF, since his are already in the right place???
				if (!curCharacter.startsWith('bf'))
				{
					// var animArray
					if(animation.getByName('singLEFT') != null && animation.getByName('singRIGHT') != null)
					{
						var oldRight = animation.getByName('singRIGHT').frames;
						animation.getByName('singRIGHT').frames = animation.getByName('singLEFT').frames;
						animation.getByName('singLEFT').frames = oldRight;
					}

					// IF THEY HAVE MISS ANIMATIONS??
					if (animation.getByName('singLEFTmiss') != null && animation.getByName('singRIGHTmiss') != null)
					{
						var oldMiss = animation.getByName('singRIGHTmiss').frames;
						animation.getByName('singRIGHTmiss').frames = animation.getByName('singLEFTmiss').frames;
						animation.getByName('singLEFTmiss').frames = oldMiss;
					}
			}*/
		}

		switch (curCharacter)
		{
			case 'pico-speaker':
				skipDance = true;
				loadMappedAnims();
				playAnim("shoot1");
		}
	}

	override public function graphicLoaded():Void
	{
		super.graphicLoaded();
		animateAtlas = Std.isOfType(frames, AtlasFrameMaker) ? cast frames : null;
		if (animateAtlas != null)
			origin.set(animateAtlas.pivotX, animateAtlas.pivotY);
	}

	override public function updateHitbox():Void
	{
		super.updateHitbox();
		if (animateAtlas != null)
			origin.set(animateAtlas.pivotX, animateAtlas.pivotY);
	}

	override public function getMidpoint(?point:FlxPoint):FlxPoint
	{
		if (animateAtlas == null)
			return super.getMidpoint(point);
		if (point == null)
			point = FlxPoint.get();
		// Psych/ES draws FlxAnimate through a separate atlas. Its Character wrapper has no
		// graphic or hitbox, so camera_position is authored relative to (x, y). Neither
		// the atlas's rendered pose nor our storage canvas belongs in that camera anchor.
		// Keep the real drawing bounds in getScreenBounds() for culling instead.
		return point.set(x, y);
	}

	/**
	 * A skewed character has to render through the complex (matrix) path even where the sprite
	 * would otherwise qualify for `drawSimple()`, which cannot shear at all.
	 */
	override public function isSimpleRender(?camera:FlxCamera):Bool
	{
		if (animateAtlas != null || jsonSkewX != 0 || jsonSkewY != 0)
			return false;

		return super.isSimpleRender(camera);
	}

	/**
	 * HaxeFlixel has no skew, so `jsonSkewX`/`jsonSkewY` are applied as a shear on top of the matrix
	 * `FlxSprite.drawComplex()` builds. The shear is premultiplied between the scale and the rotation,
	 * which puts it in the same origin-pivot space as those two and leaves the pivot itself untouched;
	 * it is a full affine product (translation column included) so it also stays right for trimmed or
	 * rotated atlas frames, where `a`/`b`/`c`/`d` are not a plain scale. `skewX` shears x by y and
	 * `skewY` shears y by x (the CSS convention).
	 *
	 * Everything after the shear mirrors `flixel.FlxSprite.drawComplex()` unchanged.
	 */
	override function drawComplex(camera:FlxCamera):Void
	{
		if (animateAtlas == null && jsonSkewX == 0 && jsonSkewY == 0)
		{
			super.drawComplex(camera);
			return;
		}

		prepareCharacterMatrix(camera);
		camera.drawPixels(_frame, framePixels, _matrix, colorTransform, blend, antialiasing, shader);
	}

	function prepareCharacterMatrix(camera:FlxCamera):Void
	{
		if (animateAtlas == null)
			_frame.prepareMatrix(_matrix, FlxFrameAngle.ANGLE_0, checkFlipX(), checkFlipY());
		else
		{
			_frame.prepareMatrix(_matrix, FlxFrameAngle.ANGLE_0, false, false);
			_matrix.translate(animateAtlas.symbolX, animateAtlas.symbolY);
			if (checkFlipX())
			{
				_matrix.a = -_matrix.a;
				_matrix.c = -_matrix.c;
				_matrix.tx = frame.frame.width * Math.abs(scale.x) - _matrix.tx;
			}
			if (checkFlipY())
			{
				_matrix.b = -_matrix.b;
				_matrix.d = -_matrix.d;
				_matrix.ty = frame.frame.height * Math.abs(scale.y) - _matrix.ty;
			}
		}
		_matrix.translate(-origin.x, -origin.y);
		_matrix.scale(scale.x, scale.y);

		var shearX:Float = Math.tan(jsonSkewX * Math.PI / 180);
		var shearY:Float = Math.tan(jsonSkewY * Math.PI / 180);
		var a:Float = _matrix.a;
		var b:Float = _matrix.b;
		var c:Float = _matrix.c;
		var d:Float = _matrix.d;
		var tx:Float = _matrix.tx;
		var ty:Float = _matrix.ty;
		_matrix.a = a + shearX * b;
		_matrix.c = c + shearX * d;
		_matrix.b = b + shearY * a;
		_matrix.d = d + shearY * c;
		_matrix.tx = tx + shearX * ty;
		_matrix.ty = ty + shearY * tx;

		if (bakedRotationAngle <= 0)
		{
			updateTrig();

			if (angle != 0)
				_matrix.rotateWithTrig(_cosAngle, _sinAngle);
		}

		getScreenPosition(_point, camera).subtractPoint(offset);
		_point.add(origin.x, origin.y);
		_matrix.translate(_point.x, _point.y);

		if (isPixelPerfectRender(camera))
		{
			_matrix.tx = Math.floor(_matrix.tx);
			_matrix.ty = Math.floor(_matrix.ty);
		}
	}

	override public function getScreenBounds(?newRect:FlxRect, ?camera:FlxCamera):FlxRect
	{
		if (animateAtlas == null || _frame == null)
			return super.getScreenBounds(newRect, camera);
		if (newRect == null)
			newRect = FlxRect.get();
		if (camera == null)
			camera = FlxG.camera;
		prepareCharacterMatrix(camera);
		var w:Float = _frame.frame.width;
		var h:Float = _frame.frame.height;
		var left = Math.min(0, _matrix.a * w) + Math.min(0, _matrix.c * h) + _matrix.tx;
		var top = Math.min(0, _matrix.b * w) + Math.min(0, _matrix.d * h) + _matrix.ty;
		return newRect.set(left, top, Math.abs(_matrix.a * w) + Math.abs(_matrix.c * h), Math.abs(_matrix.b * w) + Math.abs(_matrix.d * h));
	}

	override function update(elapsed:Float)
	{
		if (!debugMode && animation.curAnim != null)
		{
			if (heyTimer > 0)
			{
				heyTimer -= elapsed * PlayState.instance.playbackRate;
				if (heyTimer <= 0)
				{
					if (specialAnim && animation.curAnim.name == 'hey' || animation.curAnim.name == 'cheer')
					{
						specialAnim = false;
						dance();
					}
					heyTimer = 0;
				}
			}
			else if (specialAnim && animation.curAnim.finished)
			{
				specialAnim = false;
				dance();
			}

			switch (curCharacter)
			{
				case 'pico-speaker':
					if (animationNotes.length > 0 && Conductor.songPosition > animationNotes[0][0])
					{
						var noteData:Int = 1;
						if (animationNotes[0][1] > 2)
							noteData = 3;

						noteData += FlxG.random.int(0, 1);
						playAnim('shoot' + noteData, true);
						animationNotes.shift();
					}
					if (animation.curAnim.finished)
						playAnim(animation.curAnim.name, false, false, animation.curAnim.frames.length - 3);
			}

			if (animation.curAnim.name.startsWith('sing'))
			{
				holdTimer += elapsed;
			}

			if (holdTimer >= Conductor.stepCrochet * ((isPlayer ? 0.0025 : 0.0011) / (FlxG.sound.music != null ? FlxG.sound.music.pitch : 1)) * singDuration)
			{
				dance();
				holdTimer = 0;
			}

			if (animation.curAnim.finished && animation.getByName(animation.curAnim.name + '-loop') != null)
			{
				playAnim(animation.curAnim.name + '-loop');
			}
		}
		super.update(elapsed);
	}

	public var danced:Bool = false;

	/**
	 * FOR GF DANCING SHIT
	 */
	public function dance()
	{
		if (!debugMode && !skipDance && !specialAnim && !voicelining)
		{
			if (danceIdle)
			{
				danced = !danced;

				if (danced)
					playAnim('danceRight' + idleSuffix);
				else
					playAnim('danceLeft' + idleSuffix);
			}
			else if (animation.getByName('idle' + idleSuffix) != null)
			{
				playAnim('idle' + idleSuffix);
			}
		}
	}

	public function playAnim(AnimName:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void
	{
		specialAnim = false;
		animation.play(AnimName, Force, Reversed, Frame);
		holdTimer = 0;

		var daOffset = animOffsets.get(AnimName);
		if (animOffsets.exists(AnimName))
		{
			offset.set(daOffset[0], daOffset[1]);
		}
		else
			offset.set(0, 0);

		if (curCharacter.startsWith('gf'))
		{
			if (AnimName == 'singLEFT')
			{
				danced = true;
			}
			else if (AnimName == 'singRIGHT')
			{
				danced = false;
			}

			if (AnimName == 'singUP' || AnimName == 'singDOWN')
			{
				danced = !danced;
			}
		}
	}

	function loadMappedAnims():Void
	{
		var noteData:Array<SwagSection> = Song.loadFromJson('picospeaker', Paths.formatToSongPath(PlayState.SONG.song)).notes;
		for (section in noteData)
		{
			for (songNotes in section.sectionNotes)
			{
				animationNotes.push(songNotes);
			}
		}
		states.game.stages.TankmenBG.animationNotes = animationNotes;
		animationNotes.sort(sortAnims);
	}

	function sortAnims(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
	}

	public var danceEveryNumBeats:Int = 2;

	private var settingCharacterUp:Bool = true;

	public function recalculateDanceIdle()
	{
		var lastDanceIdle:Bool = danceIdle;
		danceIdle = (animation.getByName('danceLeft' + idleSuffix) != null && animation.getByName('danceRight' + idleSuffix) != null);

		if (settingCharacterUp)
		{
			danceEveryNumBeats = (danceIdle ? 1 : 2);
		}
		else if (lastDanceIdle != danceIdle)
		{
			var calc:Float = danceEveryNumBeats;
			if (danceIdle)
				calc /= 2;
			else
				calc *= 2;

			danceEveryNumBeats = Math.round(Math.max(calc, 1));
		}
		settingCharacterUp = false;
	}

	public function addOffset(name:String, x:Float = 0, y:Float = 0)
	{
		animOffsets[name] = [x, y];
	}

	public function quickAnimAdd(name:String, anim:String)
	{
		animation.addByPrefix(name, anim, 24, false);
	}
}
