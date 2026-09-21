package script.hscript;

/**
	The HScript engine now lives in `script.FunkinHScript`; these aliases keep the old
	`script.hscript.*` module paths (and `import script.hscript.HScript;`) working.
**/
typedef HScript = script.FunkinHScript.HScript;

typedef Script = script.FunkinHScript.Script;
typedef IFunkinScript = script.FunkinHScript.IFunkinScript;
typedef ScriptType = script.FunkinHScript.ScriptType;
