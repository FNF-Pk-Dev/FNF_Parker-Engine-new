package script;

import flixel.FlxBasic;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

class FunkinHScript extends FlxBasic
{
	public var scripts:Array<HScript> = [];

	// public function addScript(tag:Null<String>):HScript
	// {
	// 	// var script:HScript = HScriptUtil.getBasicScript();
	// 	// HScriptUtil.setUpFlixelScript(script);
	// 	// HScriptUtil.setUpFNFScript(script);

	// 	@:privateAccess
	// 	script._group = this;

	// 	if (tag != null)
	// 	{
	// 		script.set("name", tag);
	// 		script.name = tag;
	// 	}
	// 	else
	// 	{
	// 		var i:Int = 0;
	// 		for (script in scripts)
	// 		{
	// 			if (script == null)
	// 				continue;

	// 			if (script.name.toLowerCase().contains("_hscript"))
	// 				i++;
	// 		}

	// 		script.set("name", '_hscript$i');
	// 		script.name = '_hscript$i';
	// 	}
	// 	trace('999');

	// 	for (func in onAddScript)
	// 	{
	// 		if (func == null)
	// 			continue;
	// 		func(script);
	// 	}

	// 	scripts.push(script);

	// 	return script;
	// }

	public function executeAllFunc(name:String, ?args:Array<Any>):Array<Dynamic>
	{
		var returns:Array<Dynamic> = [];

		for (_ in scripts)
		{
			if (_ == null)
				continue;

			try {
				returns.push(_.executeFunc(name, args));
			} catch(e:Dynamic) {
				trace('Error executing $name: $e');
				returns.push(null);
			}
		}

		return returns;
	}

	public function error(msg:String, ?code:String = "error"):Void
	{
		for (_ in scripts)
		{
			if (_ == null)
				continue;

			_.error(msg, code);
		}
	}


	public function initScript(name:String, folder:String)
	{
		if (this == null)
			return;

		var hx:Null<String> = null;

		for (extn in HScriptUtil.extns)
		{
			var path:String = Paths.modFolders(folder + "/" + name);
			if (FileSystem.exists(path))
			{
				try {
					hx = File.getContent(path);
					break;
				} catch(e:Dynamic) {
					trace('Failed to load script: $e');
				}
			}
		}

		if (hx == null) {
			trace('Script $name not found in $folder');
			return;
		}

	
	}

	public function setAll(name:String, val:Dynamic)
	{
		for (_ in scripts)
		{
			if (_ == null)
				continue;

			_.set(name, val);
		}
	}

	public function getAll(name:String):Array<Dynamic>
	{
		var returns:Array<Dynamic> = [];

		for (_ in scripts)
		{
			if (_ == null)
				continue;

			returns.push(_.get(name));
		}

		return returns;
	}

	public function getScriptByTag(tag:String):Null<HScript>
	{
		for (_ in scripts)
		{
			if (_ == null)
				continue;

			if (_.name != null && _.name == tag)
				return _;
		}

		return null;
	}

	
}
