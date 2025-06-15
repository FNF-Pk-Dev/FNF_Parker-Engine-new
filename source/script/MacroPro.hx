package script;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.Tools;
using Lambda;
#end

class MacroPro
{

	/**
	 * enforces the use of haxe 4.3 cuz i use alot of its null coalescents lol
	 */
	public macro static function haxeVersionEnforcement()
	{
		#if (haxe_ver < "4.3.4")
		Context.fatalError('use haxe 4.3.4 or newer thx', (macro null).pos);
		#end

		return macro $v{0};
	}

	/**
	 * returns the current Date as a string during compilation.
	 */
	public static macro function getDate()
	{
		return macro $v{Date.now().toString()};
	}

	/**
	 * forces the compiler to include a class even if the dce kills it
	 */
	public static macro function include(path:Expr)
	{
		haxe.macro.Compiler.include(path.toString());
		return macro $v{0};
	}

	/**
	 * ONLY USE FOR ABSTRACTED CLASSES THAT ARE JUST VARS does nothing for anything else 
	 * Builds a anon strcture from static uppercase inline variables in an abstract type.
	 * ripped from FlxMacroUtil but modified to fit my needs
	 * https://code.haxe.org/category/macros/combine-objects.html
	 * https://github.com/HaxeFlixel/flixel/blob/master/flixel/system/macros/FlxMacroUtil.hx
	 */
	public static macro function buildAbstract(typePath:Expr, ?exclude:Array<String>)
	{
		var type = Context.getType(typePath.toString());
		var expressions:Array<ObjectField> = [];

		if (exclude == null)
			exclude = ["NONE"];

		switch (type.follow())
		{
			case TAbstract(_.get() => ab, _):
				for (f in ab.impl.get().statics.get())
				{
					switch (f.kind)
					{
						case FVar(AccInline, _):
							switch (f.expr().expr)
							{
								case TCast(Context.getTypedExpr(_) => expr, _):
									if (f.name.toUpperCase() == f.name && exclude.indexOf(f.name) == -1) // uppercase?
									{
										expressions.push({field: f.name, expr: expr});
									}

								default:
							}

						default:
					}
				}
			default:
		}

		var finalResult = {expr: EObjectDecl(expressions), pos: Context.currentPos()};
		return macro $b{[macro $finalResult]};
	}

	public static macro function buildFlxSprite():Array<haxe.macro.Expr.Field>
	{
		var fields:Array<haxe.macro.Expr.Field> = Context.getBuildFields();

		var position = Context.currentPos();

		fields.push(
			{
				name: "loadFromSheet",
				access: [haxe.macro.Expr.Access.APublic],
				kind: FFun(
					{
						args: [
							{name: 'path', type: (macro :String)},
							{name: 'animName', type: (macro :String)},
							{name: 'fps', type: (macro :Int), value: macro $v{24}}
						],
						expr: macro
						{
							this.frames = funkin.Paths.getSparrowAtlas(path);
							this.animation.addByPrefix(animName, animName, fps);
							this.animation.play(animName);
							if (this.animation.curAnim == null || this.animation.curAnim.numFrames == 1)
							{
								this.active = false;
							}
							
							return this;
						}
					}),
				pos: position,
			});

		fields.push({
			doc: "shortcut to loading the frames of a sparrow atlas",
			name: "loadSparrowFrames",
			access: [haxe.macro.Expr.Access.APublic],
			kind: FFun({
				args: [
					{name: 'path', type: (macro :String)},
					{name: 'library', opt: true, type: (macro :String)}
				],
				expr: macro
				{
					this.frames = funkin.Paths.getSparrowAtlas(path, library);
					return this;
				}
			}),
			pos: position,
		});

		fields.push({
			doc: "Convenient function to set the scale and call updatehitbox on a sprite",
			name: "setGraphicScale",
			access: [haxe.macro.Expr.Access.APublic],
			kind: FFun({
				args: [
					{name: 'scaleX', type: (macro :Float)},
					{name: 'scaleY', opt: true, type: (macro :Float)},
					{name: 'shouldUpdateHitbox', type: (macro :Bool), opt: true}
				],
				expr: macro
				{
					if (scaleY == null) scaleY = scaleX;
					if (shouldUpdateHitbox == null) shouldUpdateHitbox = true;

					this.scale.set(scaleX, scaleY);
					if (shouldUpdateHitbox)
						this.updateHitbox();
				}
			}),
			pos: position,
		});

		fields.push({
			doc: "Convenient function to set the size and call updatehitbox on a sprite",
			name: "updateGraphicSize",
			access: [haxe.macro.Expr.Access.APublic],
			kind: FFun({
				args: [
					{name: 'width', type: (macro :Float)},
					{name: 'height', opt: true, type: (macro :Float)},
					{name: 'shouldUpdateHitbox', type: (macro :Bool), opt: true}
				],
				expr: macro
				{
					if (height == null) height = 0;
					if (shouldUpdateHitbox == null) shouldUpdateHitbox = true;

					this.setGraphicSize(width, height);
					if (shouldUpdateHitbox)
						this.updateHitbox();
				}
			}),
			pos: position,
		});

		fields.push({
			doc: "creates a 1x1 graphic scaled to the size set",
			name: "makeScaledGraphic",
			access: [haxe.macro.Expr.Access.APublic],
			kind: FFun({
				args: [
					{name: 'width', type: (macro :Float)},
					{name: 'height', type: (macro :Float)},
					{name: "color", opt: true, type: (macro :Int)},
					{name: 'unique', opt: true, type: (macro :Bool)},
					{name: 'key', opt: true, type: (macro :String)}
				],
				expr: macro
				{
					this.makeGraphic(1, 1, color, unique, key);
					this.scale.set(width, height);
					this.updateHitbox();
					return this;
				}
			}),
			pos: position,
		});

		fields.push({
			doc: "centers the sprite onto a FlxObject",
			name: "centerOnObject",
			access: [haxe.macro.Expr.Access.APublic],
			kind: FFun({
				args: [
					{name: 'object', type: (macro :flixel.FlxObject)},
					{name: 'axes', opt: true, type: (macro :flixel.util.FlxAxes)}
				],
				expr: macro
				{
					if (axes == null) axes = flixel.util.FlxAxes.XY;
					if (axes.x)
						this.x = object.x + (object.width - this.width) / 2;
					if (axes.y)
						this.y = object.y + (object.height - this.height) / 2;
					return this;
				}
			}),
			pos: position,
		});

		return fields;
	}

	// this is from base game i wanted smth like this since forever
	public static macro function buildFlxBasic():Array<haxe.macro.Expr.Field>
	{
		var fields:Array<haxe.macro.Expr.Field> = Context.getBuildFields();

		fields.push({
			name: "zIndex",
			access: [haxe.macro.Expr.Access.APublic],
			kind: FVar(macro :Int, macro $v{0}),
			pos: Context.currentPos(),
		});

		return fields;
	}
}