-- Example external block config for the Parker Engine block-code editor.
--
-- Drop a file like this in `mods/<your mod>/blockcode/blocks.lua` (or in
-- `mods/<your mod>/blockcode/blocks/*.lua`) and its blocks appear in the editor
-- without recompiling the engine. `blocks.json` in the same folders works too and
-- both formats can be mixed.
--
-- The editor reads this file as TEXT: only `registerCategory` and `registerBlock`
-- calls are used, and nothing else in the file runs at load time. Values must be
-- literals (strings, numbers, true/false, tables); expressions such as `1 + 2` or
-- string concatenation are not understood and are skipped.

registerCategory{ name = "Lua Demo", color = 0xFF44AA88, icon = "~" }

-- Statement block: the `lua` field is the code that gets written out.
-- $1, $2... are replaced by the block's inputs in order; ${name} also works,
-- e.g. "debugPrint(${text})".
registerBlock{
	type = "demo.say",
	label = "say",
	description = "Prints a line in the debug console (F3 / script overlay).",
	category = "Lua Demo",
	lua = "debugPrint($1)",
	parameters = {
		{ name = "text", type = "string", defaultValue = "hello from a mod" }
	}
}

-- A reporter, so it can be dropped into the white input slot of another block.
registerBlock{
	type = "demo.fullHealth",
	label = "is full health",
	isReporter = true,
	description = "True while the player is at full health.",
	lua = "(getProperty('health') >= 2)",
	parameters = {}
}

-- A hat: the blocks placed under it become the body of the function.
registerBlock{
	type = "demo.onBeat",
	label = "when a beat drops",
	isHat = true,
	hatLua = "function onBeatHit()"
}

-- A dropdown (select) parameter, a bool and a raw code parameter.
registerBlock{
	type = "demo.shake",
	label = "shake camera",
	description = "Shakes the chosen camera for a moment.",
	lua = "cameraShake($1, $2, $3)",
	parameters = {
		{ name = "cam", type = "select", defaultValue = "game", options = { "game", "hud" } },
		{ name = "strength", type = "number", defaultValue = 0.05 },
		{ name = "duration", type = "number", defaultValue = 0.5 }
	}
}

registerBlock{
	type = "demo.raw",
	label = "run raw lua",
	description = "Runs whatever Lua you type inside the block.",
	lua = "$1",
	parameters = {
		{ name = "code", type = "code", defaultValue = "-- your code here" }
	}
}

-- Positional form with a table of fields; the table may be omitted entirely.
registerBlock("demo.tick", {
	label = "on every frame",
	category = "Lua Demo",
	lua = "-- frame tick"
})
