package;

import flixel.FlxGame;

/**
 * Extended FlxGame class that supports scripted state overrides.
 * Allows mod authors to replace built-in states with HScript implementations
 * (states/globals/<StateName>.hx), Lua ones (states/<StateName>.lua) or LScript
 * ones (states/<StateName>.lscript).
 */
class FNFGame extends FlxGame
{
	static var modsListLoaded:Bool = false;
	static var bootInitDone:Bool = false;

	/**
	 * TitleState.create() owns the engine's boot init (controls, save slot, prefs, global
	 * mods). When a script overrides the very first state, that create() never runs, so
	 * the same init has to happen here first — otherwise things like PlayerSettings.player1
	 * are null inside the scripted state.
	 */
	static function ensureBootInit():Void
	{
		if (bootInitDone)
			return;
		bootInitDone = true;

		backend.player.PlayerSettings.init();
		flixel.FlxG.save.bind('funkin', CoolUtil.getSavePath());
		ClientPrefs.loadPrefs();
		Paths.pushGlobalMods();
		#if android
		// TitleState.create() normally loads the mobile pads; the touch controls need them
		android.backend.MobileData.init();
		#end
	}

	public override function switchState():Void
	{
		#if MODS_ALLOWED
		// The mod list is normally loaded by TitleState/MainMenuState, which is too late for
		// the very first scripted-state check, so make sure it happens before that instead.
		if (!modsListLoaded)
		{
			modsListLoaded = true;
			backend.game.WeekData.loadTheFirstEnabledMod();
			ensureBootInit();
		}
		#end

		// Check if the next state can be overridden by a script
		if (_nextState is MusicBeatState)
		{
			final state:MusicBeatState = cast _nextState;
			if (state.canBeScripted)
			{
				final simpleName = Type.getClassName(Type.getClass(_nextState)).split(".").pop();

				// Try to find an HScript override for this state, it wins over Lua and LScript
				var hscriptPath:String = null;
				for (extn in HScriptUtil.extns)
				{
					final scriptPath = Paths.modFolders('states/globals/$simpleName.$extn');
					if (Paths.exists(scriptPath))
					{
						hscriptPath = scriptPath;
						break;
					}
				}

				if (hscriptPath != null)
				{
					_nextState = OScriptState.fromFile(hscriptPath);
				}
				#if (LUA_ALLOWED && MODS_ALLOWED)
				else
				{
					// Same mod-aware lookup LuaSState itself uses to load the script
					final luaPath = Paths.modFolders('states/$simpleName.lua');
					if (Paths.exists(luaPath))
					{
						_nextState = new psych.script.FunkinLua.LuaSState(simpleName);
					}
					else
					{
						// LScript loses against both HScript and Lua
						final lscriptPath = Paths.modFolders('states/$simpleName.lscript');
						if (Paths.exists(lscriptPath))
						{
							_nextState = new LScriptSState(simpleName);
						}
					}
				}
				#end
			}
		}

		super.switchState();
	}
}
