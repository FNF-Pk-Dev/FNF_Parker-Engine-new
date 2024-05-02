package hscript;

import Type;
import flixel.FlxBasic;
import haxe.CallStack;
import hscript.Expr;
import hscript.Interp;
import hscript.Parser;
import openfl.Lib;

class Script extends FlxBasic
{
	public var hscript:Interp;

	public var interacter:Interact;
	public var variables(get, null):Map<String, Dynamic>;

	public override function new()
	{
		super();
		hscript = new Interp();
		interacter = new Interact(this);

		
		set("import", function(path:String, ?as:Null<String>)
		{
			try
			{
				if (path == null || path == "")
				{
					error("Path Not Specified!", '${name}:${getCurLine() != null ? Std.string(getCurLine()) : ''}: Import Error!');
					return;
				}

				var clas = Type.resolveClass(path);

				if (clas == null)
				{
					error('Class Not Found!\nPath: ${path}', '${name}:${getCurLine() != null ? Std.string(getCurLine()) : ''}: Import Error!');
					return;
				}

				var stringName:String = "";

				if (as != null)
					stringName = as;
				else
				{
					var arr = Std.string(clas).split(".");
					stringName = arr[arr.length - 1];
				}

				@:privateAccess
				if (!variables.exists(stringName) && !hscript.locals.exists(stringName))
				{
					set(stringName, clas);

					if (interacter.presetVars != [])
						interacter.presetVars.push(stringName);
				}
				else
				{
					error('$stringName is alreadly a variable in the script, please change the variable to a different name!',
						'${name}:${getCurLine() != null ? Std.string(getCurLine()) : ''}: Import Error!');
				}
			}
			catch (e)
			{
				error('${e}', '${name}:${getCurLine() != null ? Std.string(getCurLine()) : ''}: Import Error!');
			}
		});
	}

	public function runScript(script:String)
	{
		var parser = new hscript.Parser();

		try
		{
			var ast = parser.parseString(script);

			hscript.execute(ast);
		}
		catch (e)
		{
			Lib.application.window.alert(e.message, "HSCRIPT ERROR!1111");
		}
	}
	
	public function setVariable(name:String, val:Dynamic)
	{
		hscript.variables.set(name, val);
	}

	public function getVariable(name:String):Dynamic
	{
		return hscript.variables.get(name);
	}

	public function executeFunc(funcName:String, ?args:Array<Any>):Dynamic
	{
		if (hscript == null)
			return null;

		if (hscript.variables.exists(funcName))
		{
			var func = hscript.variables.get(funcName);
			if (args == null)
			{
				var result = null;
				try
				{
					result = func();
				}
				catch (e)
				{
					trace('$e');
				}
				return result;
			}
			else
			{
				var result = null;
				try
				{
					result = Reflect.callMethod(null, func, args);
				}
				catch (e)
				{
					trace('$e');
				}
				return result;
			}
		}
		return null;
	}

	public override function destroy()
	{
		super.destroy();
		hscript = null;
	}
}
