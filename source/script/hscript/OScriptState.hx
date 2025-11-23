package script.hscript;

import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

class OScriptState extends MusicBeatState
{
	public var customMenu:Bool = false;
	private var hscript:HScript;

	public static function fromFile(file:String, ?name:String, ?additionalVars:Map<String, Any>)
	{
		if (name == null) name = file;
		var state = new OScriptState();
		state.loadScript(File.getContent(file), name, additionalVars);
		return state;
	}

	public function loadScript(script:String, ?name:String = "Script", ?additionalVars:Map<String, Any>) 
	{
		hscript = new HScript(script, name, additionalVars);
		
		customMenu = hscript.call('customMenu', []);
		
		trace('is [$name] custom? [$customMenu]');
		
		hscript.set("state", this);
		hscript.set("add", add);
		hscript.set("remove", remove);
		hscript.set("insert", insert);
		hscript.set("members", members);
	}

	// 代理HScript的方法
	public function set(name:String, val:Dynamic) {
		hscript.set(name, val);
	}

	public function call(func:String, ?args:Array<Any>):Dynamic {
		return hscript.call(func, args);
	}
}