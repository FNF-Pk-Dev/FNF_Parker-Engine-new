# AGENTS.md — Parker Engine

Guide for AI coding agents working on **Friday Night Funkin': Parker Engine**, a Haxe/HaxeFlixel rhythm-game engine forked from Psych Engine.

## 1. What this project is

| | |
|---|---|
| Product | Friday Night Funkin': Parker Engine (`Project.xml`) |
| Version | `0.2.8` (Project.xml) — `gitVersion.txt` still says `0.6.3` (stale, upstream leftover) |
| App identity | package/file `com.laoan.pkengine`, company `Ajwwk`, executable `Pk Engine` |
| Language | Haxe (CI and the reference dev machine use **4.3.7**) |
| Stack | HaxeFlixel + OpenFL + Lime, `hscript`/`hscript-iris`, `flxanimate`, `flixel-ui`, `flxgif`, `hxvlc`, `linc_luajit`, `pyscript`, `faxe`, `discord_rpc`, `haxe-crypto` (the `.lscript` Luau runtime is built in, no `lscript` haxelib any more) |
| Targets | Windows (primary), Android, HTML5; `linux`/`mac`/`switch` code paths exist |
| Entry point | `source/Main.hx` → `FNFGame` (`flixel.FlxGame` subclass) → `StartupState` |

Fork-specific features you will not find in upstream Psych Engine:

- `source/modchart/` — Schmovin'/Andromeda-style **note modifier stack**: `ModManager` (registry + `EventTimeline`), 15 built-in modifiers (`modifiers/`), events (`events/`), and `HScriptModifier` so scripts can define their own.
- `source/options/` — Psych-0.7-style **option menu framework** (`BaseOptionsMenu`, `Option`, `OptionsState`, `*SubState` pages) alongside the older inline options code.
- `source/script/` — HScript is first-class (`FunkinHScript`, `HScriptUtil`, `OScriptState`), next to LScript (`.lscript`, its own Luau runtime in `FunkinLScript.hx` on `llua`) and Python; `FNFGame.switchState()` can replace a built-in state with a script.
- PowerPuff-Girl themed loading/idle/intro screen and transitions (`backend/PowerPuffGirl.hx`, `PowerPuffTrail.hx`, `PowerPuffTransition.hx`, `obj/PowerPuffGirl.hx`), driven by data in `assets/preload/images/loading/loading.json`.
- Custom screen transitions: `backend/CustomFadeTransition.hx`, `backend/CustomTilesTransition.hx` (sparrow `ui/diaTrans`) instead of stock `FlxTransitionSprite`.
- `backend/ChartParser.hx` — builds charts out of image tiles (`data/<song>/<song>_sectionN.png`); currently only referenced from a commented-out line in PlayState.
- `backend/UIAnim.hx` — the shared UI tween helper (`flyInX`/`flyInY`, `popIn`/`popText`, `breathe`, `beatBump`, `selectItem`, `syncConductor`). Every helper is a no-op while `ClientPrefs.uiAnimations` is off. See §5 for the menu beat-sync caveat it exists to fix.
- `backend/FlxCompat.hx` — flixel 5.x/6.x compatibility shim; `source/flixel/`, `source/openfl/` shadow haxelib classes on the classpath.
- Android extras in `source/android/`: touch controls/virtual pads, hitbox skins, `StorageUtil` (scoped storage), `Hardware` (JNI), `CopyState` (first-run asset provisioning).
- `source/psych/` re-homes Psych classes under `psych.*` — including the legacy 132 KB `psych/script/FunkinLua.hx` and `CallbackHandler.hx` (declares `package;`, i.e. compiled into the root package).

## 2. Toolchain and build

```bash
# One-time dependency install (manifest: hmm.json)
haxelib install hmm && haxelib run hmm install

# Build / run
haxelib run lime build windows            # Windows release
haxelib run lime build windows -debug     # Windows debug
haxelib run lime test    windows          # build + launch
haxelib run lime build android -final     # Android release (needs JDK 17 + NDK)
haxelib run lime build html5
```

Convenience wrappers that also open the output folder: `art/build_x64.bat`, `art/build_x64-debug.bat`, `art/build_x32.bat`, `art/build_html.bat`, `art/build_html-debug.bat`, `art/test_x64-debug.bat`.

Output directories (set by `BUILD_DIR` in `Project.xml`):

- Windows: `export/release/windows/bin/` (debug: `export/debug/…`, 32-bit: `export/32bit/…`)
- Android: `export/release/android/bin/app/build/outputs/apk/release/` (unsigned/debug runs land under `.../apk/debug/`)
- HTML5: `export/release/html5/bin/`

CI (`.github/workflows/`): `main.yml` builds Android on `ubuntu-24.04` with Haxe 4.3.7, NDK r27c, JDK 17 and installs each haxelib from git; `mainpc.yml` builds Windows on `windows-latest`. These files list the exact working dependency set — use them as the reference when a local lib version misbehaves.

Version pins are loose in practice: `Project.xml` asks for `openfl 9.2.2` / `lime 7.7.0`, while `hmm.json` pins `lime 8.0.2` / `openfl 9.2.2`, and the reference machine runs lime 8.1.3 / openfl 9.3.4. Lime only warns about this (`Warning: Ignoring unknown fps=""` is also harmless), so do not "fix" the pins without being asked.

## 3. Repository map

```
source/                     single classpath entry (<classpath name="source" />)
  Main.hx                   app entry; FPS counter, crash handler, global mod script, Android back button
  FNFGame.hx                FlxGame subclass; scripted state override hook
  StartupState.hx           first state; hands off to states.TitleState
  import.hx                 GLOBAL IMPORTS — every file gets backend.*, obj.*, states.*, script.*, flixel core
  backend/                  engine core: Paths, ClientPrefs, CoolUtil, MusicBeatState/Substate,
                            Discord, Highscore, transitions, FlxCompat, ChartParser, Snd
    game/                   WeekData, StageData, Achievements, MenuCharacter, PhillyGlow, stages/
    obj/                    CheckboxThingie, FPSCounter, TypedAlphabet
    player/                 Controls (Action enum), PlayerSettings
    songs/                  Conductor, Section (SwagSection), Song (SwagSong)
  states/                   TitleState, LoadingState, FlashingState, OutdatedState, LatencyState
    game/PlayState.hx       MAIN GAMEPLAY — 6.3k lines; everything gameplay happens here
    menu/                   MainMenu, Freeplay, StoryMenu, ModsMenu, AchievementsMenu, Credits
  substates/                PauseSubState, ResetScoreSubState, ButtonRemapSubstate, game/GameOver*
  obj/                      Note, Character, Boyfriend, HealthIcon, StrumNote, Alphabet, NoteSplash,
                            BGSprite, AttachedSprite/Text, VideoSprite, KeystrokesUI, PowerPuffGirl
  script/                   FunkinHScript/LScript/Python, GlobalScript, Interact, Macro/MacroPro,
                            LScriptSState, ScriptDebugOverlay (on-screen script errors)
                            FunkinHScript.hx also holds the HScript engine: HScript, Script,
                            IFunkinScript, ScriptType and InterpPro
    hscript/                HScript/Script/IFunkinScript/ScriptType/InterpPro typedef aliases
                            (→ script.FunkinHScript), HScriptUtil (global script API),
                            OScriptState, MacroState
  psych/                    Psych-derived classes (FunkinLua, CallbackHandler, psych/cutscenes, psych/obj)
  modchart/                 ModManager, ModchartComposed (layer composition with FlxTween),
                            Modifier/NoteModifier/SubModifier/HScriptModifier,
                            Modcharts, EventTimeline, events/, modifiers/
  options/                  BaseOptionsMenu, Option, OptionsState, Gameplay/Graphics/Visuals/Controls/
                            Notes/NoteOffset sub-states
  editors/                  MasterEditorMenu, ChartingState (3.4k lines), CharacterEditorState,
                            WeekEditorState, DialogueEditorState, BlockCodeEditorState, EditorLua
    blockcode/              the block-code editor as a SUBSTATE that runs on top of a live PlayState:
                            BlockCodeEditorSubstate (workspace/sidebar/snapping/pan/zoom),
                            Block (draggable block + InputField), BlockLibrary (block catalogue),
                            BlockConfigLoader (external JSON/Lua block configs), BlockSerializer
                            (tree <-> JSON + FlxSave cache), BlockLuaGenerator, BlockLuaImporter,
                            BlockFileIO (where the .lua is written), BlockScriptRuntime (hot reload
                            inside the running song), BlockTimeline (step/beat/second ruler with
                            drag-to-seek markers), BlockSoftKeyboard + BlockVirtualKeyboard (text
                            entry incl. Android IME), BlockSavePanel/BlockCodePanel/BlockFileBrowser/
                            BlockHelpOverlay/BlockContextMenu (panels), BlockTypes (data contract)
  cutscenes/                CutsceneHandler, DialogueBox
  shaders/                  RuntimeShader, ColorSwap, WiggleEffect, BlendModeEffect, CoolShader, OverlayShader
  android/                  Android-only code (touch controls, storage, hitbox skins, macros)
  animateatlas/             Adobe Animate atlas runtime (AtlasFrameMaker used by obj/Character)
  cpp/, linc/, lib/, openfl/, flixel/, math/, discord_rpc/   platform glue + vendored overrides
assets/                     preload/ (data, images, characters, stages, weeks, music, sounds, fonts)
                            shared/, songs/<song>/, week2…week7/, videos/, fonts/, secrets/, exclude/
example_mods/               the mod template; Project.xml renames it to "mods/" in the build
moblie/                     (sic) Android on-screen control layouts, packaged as assets/moblie
art/                        build .bat helpers + icons/preloader art
docs/                       GitHub Pages site (docs/index.html, styles.css, modTemplate.zip)
```

Two items in the repo that are **not** part of the engine:

- `source/twitch-powerpuffgirls-main/` — a vendored standalone Web-Components + Vite/pnpm project (its own `AGENTS.md`, committed `node_modules/`). Not referenced by any Haxe file and not compiled; it is the art prototype for the PowerPuff loading screen. Ignore it unless the task is explicitly about it.
- `NightmareVision-dev` — a dangling symlink to `C:/Users/34275/Documents/NightmareVision-dev`. Recursive tools that follow symlinks will error on it; `.promptx/` is likewise unrelated tooling state.

## 4. Code style (enforced by `hxformat.json`)

- **Tabs only**, never spaces.
- Braces on their own line for `if`/`else`/`for`/`while`/`do`/`try`/`catch`; `return` body stays on the same line.
- Imports are sorted by the formatter (`sortImports: true`).

```haxe
if (condition)
{
	doSomething();
}
else
{
	doOther();
}
```

Check or apply formatting with the installed `formatter` haxelib:

```bash
haxelib run formatter --check -s source/
haxelib run formatter -s source/backend/ClientPrefs.hx
```

Import order (see `source/import.hx` for the canonical example): package → conditional (`#if desktop` / `#if android`) → project (`backend.*`, `states.*`, `obj.*`, `script.*`) → `flixel.*` → `openfl.*`/`lime.*` → Haxe stdlib → `using StringTools;`.

Naming: classes `PascalCase`, fields/functions `camelCase`, constants `UPPER_SNAKE`. Class fields and function parameters/returns get explicit types (`public var songSpeed:Float = 1;`); obvious locals can infer. Match the surrounding file — the codebase mixes `public static function` and `static public function`, and `override function` vs `override public function`.

**Do not add imports for `backend.*`, `obj.*`, `states.*`, `script.*`, `shaders.*` or common `flixel.*` classes** — `source/import.hx` already imports them project-wide; adding them again is noise (and can produce duplicate-import warnings). Only add imports for things not covered there.

## 5. How the game boots and runs

`Main` (a `Sprite`) creates `FNFGame(width=1280, height=720, initState: StartupState, 60 fps)`; on Android it may insert `CopyState` when first-run assets still need copying, and it re-binds the working directory to storage. `StartupState` forwards to `states.TitleState`. Crash reports (`#if CRASH_HANDLER`) are written to `./crash/PkEngine_<date>.txt`.

State base classes (`backend/`):

- `MusicBeatState extends flixel.addons.ui.FlxUIState` — step/beat/section hooks, static `switchState(next)`, Android touch-pad helpers. Its constructor arg `canBeScripted` (default `true`) enables script overrides; `MusicBeatSubstate extends FlxSubState` is the substate twin.
- Override `create()` / `update(elapsed)` / `stepHit()` / `beatHit()` / `sectionHit()` and always call `super`.
- Timing comes from `backend/songs/Conductor.hx`; `PlayState` drives `curStep`/`curBeat`/`curDecStep`.
- **Outside `PlayState` nothing advances `Conductor.songPosition`**, so a menu state's `curStep` never changes and its `stepHit()`/`beatHit()` never fire. Any beat-driven menu animation must first point the conductor at the menu track by calling `UIAnim.syncConductor()` at the top of `update()` (it only writes while `FlxG.sound.music.playing`). Do **not** move this into `MusicBeatState.update()`: `PlayState` self-manages `songPosition` (`songPosition += elapsed * 1000 * playbackRate`) and `setSongTime()`, and a base-class write would break both.

`PlayState` owns: `instance:PlayState`, `modManager:ModManager` (created when `ClientPrefs.getGameplaySetting('modchart')` is on), the four script registries (`luaArray`, `lscriptArray`, `pscriptArray`, `hscriptArray`), and every gameplay callback dispatch through `callOnScripts(event, args…)` / `callOnLuas(…)`.

`ModManager` lives in `source/modchart/ModManager.hx` — it is a *modchart modifier* manager, **not** a mod-folder manager. Mod folders are handled by `backend/Paths.hx`, `backend/game/WeekData.hx` and `states/menu/ModsMenuState.hx`.

### The modchart composes with `FlxTween` — never assign `x`/`y`/`scale`/`angle` yourself

The modifier stack is only *one* of the layers that move an arrow. Before `ModchartComposed` existed, `PlayState`
re-assigned `strum.x = pos.x; strum.y = pos.y;` (and the note equivalent) every frame from
`ModManager.getPos()`, whose base is the fixed formula `getBaseX(data, player)` / `50 + diff`. That erased
whatever a running `FlxTween` had just written, so enabling the modchart killed `noteTweenX` and any
`FlxTween.tween(strum, {x: …})` — arrows could only be moved through modchart values.

The fix is a composition layer (`source/modchart/ModchartComposed.hx`, implemented by `obj/Note.hx` and
`obj/StrumNote.hx`): before writing, the applier compares what it wrote last frame with the object's current
value, carries the difference into an `external` accumulator, and writes `modchart layer + external layer`
(position and `angle` additively, `scale` as a ratio). So a tween keeps running *and* the modchart keeps
driving the object, and a modchart value that changes mid-tween still layers on top of the tween's target.

Rules this creates:

- `ModManager.applyPosition()`, `applyScale()` and `applyAngle()` are the **only** functions allowed to write
  `x`, `y`, `scale` or `angle` on a `Note`/`StrumNote`. A modifier that assigns them directly makes the
  modchart and a tween fight again — add to the `pos` vector in `getPos()` instead, which needs no change.
- `ModManager.composeExternals = false` restores the old absolutely-owning behaviour for scripts that really
  want to own the transform (teleports, custom paths); flip it back to `true` afterwards.
- `syncComposition(obj)` adopts the current transform as a new baseline (after a teleport or a reset) and
  `resetComposition()` clears the bookkeeping for one object or all of them (song restart, `destroy()`).
- `AlphaModifier` needs no such care: it drives the `ColorSwap` shader uniform, which *multiplies* `alpha`.
- `PlayState` gates the whole application on `songIsModcharted`
  (`ClientPrefs.getGameplaySetting('modchart', true)`), so a tween on an arrow works today either way — the
  composition layer is what makes it work *with* the modchart on.

### Sustains, the modchart's scale modifier, and `defScale`

`ScaleModifier.shouldExecute()` returns `true` unconditionally, so it is **always** in `activeMods` and runs
every frame even on a chart that sets no modchart values at all. For a sustain piece it restores
`scale.y = defScale.y` (`modifiers/ScaleModifier.hx`), which means `defScale` — not `scale` — is what
decides how long a held note draws.

That is why `source/obj/Note.hx` must record the **piece's own stretched** scale as its natural one
(`prevNote.defScale.copyFrom(prevNote.scale)`), not the neighbouring note's un-stretched scale: the old
`copyFrom(scale)` handed the modifier one unstretched frame height, it shrank every piece back to
`frameHeight`, and the trail broke into one chunk per step. `ClientPrefs.sustainTrail` (Visuals & UI,
default on) selects between the two — on keeps the trail continuous, off restores the chunked look. The
same bookkeeping is repeated in `resizeByRatio()` and `reloadNote()`; skip either and a mid-song speed
change or a note-type reload is undone on the next frame.

`ClientPrefs` gates are independent of the modchart toggle: `sustainTrail` works with the modchart on or off.

### Where a note splash actually goes

`NoteSplash.setupNoteSplash()`'s `x`/`y` is the point the burst is **centred** on, and it aligns that
centre per frame from the frame's real content rect (`frame.offset + frame.frame/2`, i.e. the negated
`frameX`/`frameY` plus the atlas trim), because the shipped splash art sits well off its own declared
canvas centre. Callers therefore pass the receptor's own midpoint
(`strum.getMidpoint()` — see `PlayState.spawnNoteSplashOnNote` / `spawnNoteSplashOnOpponentNote` and the
twin in `EditorPlayState`), **not** its `x`/`y`. Do not "simplify" this back to `frameWidth/2`
centring, and do not pass `strum.x`/`strum.y` again: that reintroduces a ~13 px offset that also jumps
between the two splash animations.

## 6. Assets and paths

Never hardcode `"assets/..."`. Always go through `Paths` (`source/backend/Paths.hx`):

```haxe
Paths.image('menuBG');                        // -> FlxGraphic (mod-aware)
Paths.sound('scroll');                        // -> Sound
Paths.music('freakyMenu');
Paths.inst(songName, difficulty);             // songs/<song>/Inst-<diff>.ogg, then Inst.ogg
Paths.voices(songName, difficulty);           // same for Voices
Paths.font('vcr.ttf');
Paths.video('cutscene');
Paths.getSparrowAtlas('characters/BOYFRIEND');
Paths.getPackerAtlas('alphabet'); Paths.getJSONAtlas('gfDanceTitle');
Paths.getShader('myShader.frag', 'myShader.vert');
Paths.json('data/' + song + '/' + song);      // JSON text (charts, stage data, week data…)
Paths.txt(...); Paths.xml(...); Paths.lua(...);
Paths.getContent(path);                       // raw text from an explicit path
Paths.modFolders('data/' + song + '/script.hx');  // mod-aware lookup for a relative path
Paths.mods('scripts/');                       // <game dir>/mods/scripts/
Paths.exists(path);
Paths.clearStoredMemory(); Paths.clearUnusedMemory();   // memory hygiene between states
```

Resolution rules worth remembering:

- Sound/video extensions come from `Paths.SOUND_EXT` (`ogg`, or `mp3` on web) and `Paths.VIDEO_EXT` (`mp4`). `Paths.returnSound` validates the `OggS` header and throws a descriptive error on bad files.
- `Paths.json/txt/xml` resolve through the **level library** first (`currentLevel`, set by `LoadingState`), then `shared`, then `assets/preload/…`; that is why default charts live in `assets/preload/data/<song>/<song>.json` while week-specific assets can live in `assets/weekN/…`. Libraries are declared in `Project.xml` (`shared`, `songs`, `videos`, `week2`…`week7`).
- `Paths.modFolders(key)` checks the active mod (`Paths.currentModDirectory`) → every global mod → the shared `mods/` root. It returns a path that may not exist; guard with `Paths.exists`/`FileSystem.exists`.
- Song names go through `Paths.formatToSongPath()` (lowercase, spaces → dashes, punctuation stripped).

`ClientPrefs` (`source/backend/ClientPrefs.hx`) holds all saved settings as plain `public static var` fields plus a `gameplaySettings:Map<String, Dynamic>` read via `ClientPrefs.getGameplaySetting(name, default)`. It is saved by `saveSettings()` and restored by `loadPrefs()` against `FlxG.save.bind('funkin', CoolUtil.getSavePath())` (bound in `states/TitleState.hx`; keybinds live in a second `controls_v2` save as `customControls`). There is **no** `getPref`/`savePrefs` helper: to add a setting, add the field, write it in `saveSettings()`, read it in `loadPrefs()` with a null guard, and surface it in the relevant `source/options/` sub-state.

## 7. Mods

- `example_mods/` is the shipped template and is renamed to `mods/` by the build (`<assets path='example_mods' rename='mods'/>`, `MODS_ALLOWED` only). The runtime `mods/` folder does not exist in the source tree — create it next to the executable when testing.
- Load order and enable flags live in **`modsList.txt`** (game-dir root, written by `ModsMenuState`), one `folderName|0|1` per line. `Paths.getGlobalMods()` / `pushGlobalMods()` additionally require the mod's `pack.json` to set `runsGlobally: true`. `Paths.getModDirectories()` lists candidates, skipping `Paths.ignoreModFolders` (`characters`, `data`, `songs`, `images`, `scripts`, `stages`, `weeks`, …).
- `pack.json` keys actually read by the code: `name`, `description`, `color` (needs `length > 2`), `restart`, `runsGlobally`. `discordRPC` / `iconFramerate` are legacy and unused; there is **no** API-version field or check.
- Mod folder layout mirrors `assets/`: `characters/ custom_events/ custom_notetypes/ data/ fonts/ images/ music/ scripts/ shaders/ songs/ sounds/ stages/ videos/ weeks/` plus a root `global.hx` that `Main` loads as the `GLOBAL` script.
- A song lives in `mods/<mod>/data/<mod-formatted song>/` (chart JSON, `events.json`, scripts) with audio in `mods/<mod>/songs/<song>/Inst.ogg` + `Voices.ogg`. `Song.loadFromJson` checks mods before `assets/preload/data/…`.

## 8. Scripting

Extensions recognized by `HScriptUtil.extns`: **`.hx`, `.hscript`, `.hsc`, `.hxs`**; Lua is `.lua` (`psych/script/FunkinLua.hx`), lscript is `.lscript` (`FunkinLScript`, `#if LUA_ALLOWED`), Python is `.py` (`FunkinPython`, `#if PYTHON_ALLOWED`). `.lscript` is a **self-contained Luau runtime** (`llua` + `source/script/`): neither `Project.xml` nor `hmm.json` lists the `lscript` haxelib any more, so do not add it back and do not `import lscript.*`.

Where scripts are auto-discovered (`states/game/PlayState.hx`):

| Location | Loaded by |
|---|---|
| `scripts/` (mods → `assets/scripts/`), deep-search | `loadGlobalScripts()` / `initScripts()` |
| `data/<formatted song>/` (mods and assets) | `loadSongScripts()` / `initScripts()` |
| `characters/<name>.<ext>` | `initCharScript(name)` |
| `stages/<stage>.<ext>` | stage scripts at song load |
| `custom_events/<event>.<ext>`, `custom_notetypes/<type>.<ext>` | event/notetype registration |
| `mods/<mod>/global.<ext>` | `Main` (`GLOBAL`) |
| `states/globals/<StateName>.<ext>` | `FNFGame.switchState()` → `OScriptState` (wins over the Lua/LScript overrides) |
| `states/<StateName>.lua` | `FNFGame.switchState()` → `LuaSState` (`#if LUA_ALLOWED && MODS_ALLOWED`, wins over LScript) |
| `states/<StateName>.lscript` | `FNFGame.switchState()` → `script.LScriptSState` |
| `scripts/menus/<StateName>.<ext>` | `MusicBeatState.setUpScript()` |

Callbacks are dispatched by name; the important ones: `onCreate`, `onCreatePost`, `onUpdate`, `onUpdatePost`, `onStepHit`, `onBeatHit`, `onSectionHit`, `onSongStart`, `onCountdownTick`, `onStartCountdown`, `onEndSong`, `onGameOver`, `onPause`, `onResume`, `onDestroy`, `onEvent`, `eventEarlyTrigger`, `onSpawnNote`, `goodNoteHit`, `opponentNoteHit`, `noteMiss`, `noteMissPress`, `onUpdateScore`, `onRecalculateRating`, `popUpScore`, `onMoveCamera`, and for modcharts `preModifierRegister`, `postModifierRegister`, `generateModchart`. Return `script.GlobalScript.Function_Stop` (`'FUNC_STOP'`) to stop the chain, `Function_Continue` / `Function_Halt` for the other policies.

LScript callbacks additionally have to be listed in `script/FunkinLScript.hx`'s `CALLBACKS`. `call()` looks the name up as a plain global and dispatches it through a **protected llua call** (the same style `FunkinLua` uses): a callback the script did not define is simply absent from its globals and is skipped. There is no `_G` metatable forwarding undefined globals to `script.parent` any more — that forwarding is what used to make dispatching an unimplemented callback kill the process — but `call()` still refuses a name outside `CALLBACKS` and reports it on screen (`ScriptDebugOverlay` outside a song), so extend that list when a new callback is dispatched to lscripts. A Haxe value handed to a script (classes included) becomes a **proxy table** whose reads, writes and method calls go back to Haxe (`luaIndex()`, `luaSetProp()`, `luaInvoke()`, so `spr.x = 1` and `spr:playAnim('idle')` both work), and engine functions are bound through `bind()`, which calls them back through `luaCall()` — that is where their errors are reported instead of unwinding into the VM. `execute()` runs the body protected and then fires `onCreate`; the callback contract (same names, same order, `Function_Stop`/`Function_Continue`/`Function_Halt` returns) is unchanged.

Lua's `this` global gets the same treatment through `setProxy()` and `source/psych/script/LuaProxy.hx` (the bridge above, ported to `FunkinLua`): `this.camGame:flash(...)`, `this.camGame.zoom = 1.2` and `this.boyfriend:playAnim('idle')` reach the live state. Everything else `FunkinLua.set()` binds — PlayState's `camGame`, `camHUD`, `boyfriend`, `strums`, `notes`, … — is still the `Convert.toLua` snapshot, where object fields come out as `nil` and nested writes never land; use `setProxy()` for a global that has to be live. Note that `this.camGame` is only Luau-legal syntax: `this:camGame:flash(...)` is a **parse error** in Lua and Luau alike (`a:b` must be a method call), and no engine change can accept it.

Global variables/functions exposed to HScript come from `script/FunkinHScript.hx` — that module now owns the whole engine (`HScript`, `Script`, `IFunkinScript`, `ScriptType`, `InterpPro`), and `FunkinHScript.setDefaultVars(script)` registers the default API (including `this`, which resolves to the interpreter's parent, else `PlayState.instance`, else `FlxG.state`) while `HScript.setDefaultVars()` just delegates to it, so `script/hscript/HScriptUtil.hx` (`setDefaultVars`) can still extend the list; PlayState then pushes game state (`curStep`, `curBeat`, `bpm`, `boyfriend`, `camGame`, `modManager`, …). `source/script/hscript/HScript.hx` and `InterpPro.hx` are typedef-only alias modules for the old `script.hscript.*` paths. Two-way variable binding is `script/Interact.hx`. `script/Macro.hx` (`addScriptingCallbacks`) is the build macro that injects script hooks into states/objects and honors `@:noScripting`.

### Engine Custom ES dialect

`source/psych/script/ESCompat.hx` is registered at the end of `FunkinLua`'s constructor and adds the ~70 callbacks the "Engine Custom ES" engine provides (`set`/`get`/`add`/`remove`/`scale`/`scroll`/`setCam`/`setOrder`, `setArray`/`addArray`/`setVarArray`, `stepEvent`, `switchLuaMenu`/`switchSourceMenu`, freeplay queries, `makeShader`/`setCameraShader`/`doTweenFloatArray`, `makeChar`/`setLongSing`/`MoveCamOnAnim`/`getAnimName`, `makeHealthBar`, `makeTrailSpirit`, `BGSprite`/`FlxBackdrop`/`ColorBox`, window helpers, strum/note helpers, typewriter texts). It never replaces a Psych callback, so Psych scripts keep their behaviour.

Scripts of custom menu states run inside `LuaSState`, where there is no `PlayState.instance`: `FunkinLua` then keeps sprites/texts/tweens/timers/sounds and variables in its own `menuSprites`/`menuTexts`/`menuTweens`/`menuTimers`/`menuSounds`/`menuVariables` registries (see `FunkinLua.spriteMap()`, `tweenMap()`, `FunkinLua.getVariablesMap()`), adds objects to the `LuaSState` itself and falls back to `backend.player.PlayerSettings.player1.controls` for `keyJustPressed` & co. `LuaSState` dispatches `onUpdateOptions` every frame and `onEventSet(curStep)` every step (which is what drives `stepEvent()`). ES also gets `onTyping(tag)` from the typewriter and an emulated `onPlayAnim(tag, anim)` fired by `ESCompat.tick()` when a character changes animation.

Script errors must still be visible without a PlayState: `source/script/ScriptDebugOverlay.hx` is the shared on-screen overlay the scripted states print on. `LuaSState`, `LScriptSState` and `OScriptState` call `ScriptDebugOverlay.attach(this)` from `create()`, and every message goes through `ScriptDebugOverlay.report(text, color)`, which keeps deferring to `PlayState.addTextToDebug` while a song runs and otherwise prints on the overlay (queued until the state's `create()` when reported from a constructor). The overlay renders on its own `FlxCamera`, which it re-appends as the last entry of `FlxG.cameras.list` so it stays above the state's sprites, substates and any camera a mod script adds; `OScriptState` also calls `ScriptDebugOverlay.hookScriptLog()` after building its script, so Iris messages (which `FunkinHScript.InitLogger()` routes through PlayState) survive outside a song.

## 9. Compile-time defines (`Project.xml`)

```haxe
#if desktop          // Windows / macOS / Linux
#if android          // Android — see also #if mobile
#if web              // HTML5 (also: #if html5)
#if MODS_ALLOWED     // <assets example_mods rename to mods/> + mod lookups in Paths
#if LUA_ALLOWED      // linc_luajit + the built-in lscript (Luau) runtime
#if PYTHON_ALLOWED   // pyscript
#if VIDEOS_ALLOWED   // hxvlc
#if ACHIEVEMENTS_ALLOWED
#if CRASH_HANDLER    // desktop release || android
#if PRELOAD_ALL       // preloads songs/shared/week2…week7 libraries (disabled on web)
#if PSYCH_WATERMARKS  // dev watermarks on the title screen
#if TITLE_SCREEN_EASTER_EGG  // only with officialBuild
#if debug
```

## 10. Common tasks

- **Add a mod song** — create `mods/<mod>/data/<song>/<song>.json` (+ optional `events.json`, scripts) and `mods/<mod>/songs/<song>/Inst.ogg` + `Voices.ogg`; reference the folder from a week JSON or Freeplay.
- **Add a song script** — drop `mods/<mod>/data/<song>/<song>.hx` (or `.lua`/`.lscript`/`.py`) and implement callbacks by name; nothing else to register.
- **Add a custom event / notetype** — create `mods/<mod>/custom_events/<name>.<ext>` or `custom_notetypes/<name>.<ext>`; the script is loaded automatically when the event/type appears.
- **Add a stage** — a `stages/<name>.json` data file (mods or `assets/preload/stages/`) plus images; optionally a `stages/<name>.hx` script.
- **Add a character** — `characters/<name>.json` plus `images/characters/<name>.png` atlases; scripts via `characters/<name>.<ext>`.
- **Add a setting** — see §6 (field + `saveSettings`/`loadPrefs`) and add the UI entry in the matching `source/options/*SubState.hx`.
- **Add a modchart modifier** — implement `modchart/Modifier.hx` (or `NoteModifier`) under `source/modchart/modifiers/` and register it in `ModManager.registerDefaultModifiers()`; scripts can also add modifiers at runtime through `HScriptModifier` / the modchart callbacks. Add to the `pos` vector in `getPos()` and, for anything that is not position, write through `ModManager.applyScale()`/`applyAngle()` — never assign `x`/`y`/`scale`/`angle` on a `Note`/`StrumNote` directly (see §5, it breaks `FlxTween`).
- **Tweak gameplay** — `states/game/PlayState.hx` is the single hub: note spawning, `callOnScripts` hooks, camera, health, score, stage, modchart update (search for `modManager.updateTimeline`).
- **Build Lua effects while the song plays (block editor)** — press **Key 3** (`debug_3`, `NINE`) during a song, or press "Play" in `editors/BlockCodeEditorState.hx` (it sets `PlayState.openBlockEditorOnStart`), to open `editors.blockcode.BlockCodeEditorSubstate` on top of the running `PlayState`. It live-reloads the script it saves through `BlockScriptRuntime`. Timeline markers carry a block stack each; they compile to `if curStep == N then` guards inside `onStepHit` (or to an `onEvent` guard when the marker has an event name). Everything is saved as `.lua` through `BlockFileIO` in one of three exec modes (`song`/`global`/`custom`) with a renameable script name.
- **Add custom blocks for the block editor** — drop `blockcode/blocks.json` or `blockcode/blocks.lua` (plus anything in `blockcode/blocks/`) into a mod folder, or `assets/shared/blockcode/`. JSON and Lua schemas are documented at the top of `source/editors/blockcode/BlockConfigLoader.hx`; `example_mods/blockcode/` holds a working example of both. Blocks are matched to code by the `lua` template (`$1`, `${paramName}`), so no engine change is needed. The editor's file browser shows which files were scanned (`BlockConfigLoader.configSignature()`/`lastErrors()`).

## 11. Pitfalls

- **Tabs, not spaces**; run `haxelib run formatter --check -s source/` before declaring a coding task done.
- Never hardcode asset paths, and never bypass `Paths` for mod-aware lookups.
- `Paths.returnAsset`, `Paths.modsList`, `Paths.currentMods`, `ClientPrefs.getPref`/`savePrefs` **do not exist** in this fork — do not invent them.
- Do not touch `export/` (build output), `docs/` (published site) or vendored `source/lib/` + `source/twitch-powerpuffgirls-main/` unless the task is about them.
- Never add a second root `class Main`: `source/animateatlas/Main.hx` already declares one and is dead demo code — do not copy that pattern.
- New dependencies must be added to **both** `hmm.json` and `Project.xml`, and ideally to `.github/workflows/*.yml` so CI keeps working.
- Guard platform-specific code with the existing defines; do not delete `#if desktop` / `#if android` / `#if CRASH_HANDLER` guards.
- Null-check `FlxG.cameras`, `FlxG.sound`, `FlxG.state` and platforms before use — several states run on all three targets.
- `source/psych/script/FunkinLua.hx` is a legacy monolith still in use; prefer adding features in `source/script/` and keep Lua API changes backward-compatible.
- `mods/` and `modsList.txt` do not exist until the game creates them; always guard filesystem access.
- `source/editors/blockcode/BlockTypes.hx` is the frozen data contract of the whole block editor package (substate, canvas, serializer, generator, importer, config loader all code against it). Append new optional fields; do not rename or remove existing ones without updating every consumer.
- The modchart must never assign `x`/`y`/`scale`/`angle` on a `Note`/`StrumNote` outside `ModManager.applyPosition/applyScale/applyAngle` — that is what used to erase every `FlxTween` on the arrows (see §5, "The modchart composes with `FlxTween`").
- **Never hand a null/absent source to a script loader.** `Paths.getContent()` returns `null` for a missing file, and `LuaL.luau_loadsource()` in the `linc_luau` haxelib ends in `strlen(source)` with no null check (`linc/linc_lua.cpp`, `load_source`), so a null source is a `strlen(nullptr)` — the process dies instantly with no Haxe exception to catch (reproduced: a standalone hxcpp program calling `luau_loadsource(state, "chunk", null)` exits with code 139/SIGSEGV). Check the file exists first, and treat a null/empty chunk as a reported, survivable failure (`FunkinLua` and `FunkinLScript` do this in their constructors now). `llua/LuaRequire.hx` in the fork passes that same possibly-null source for a `require()` of a missing module, so a mod's `require` can still kill the app until the fork guards it.
- `loadGlobalScripts()` in `PlayState` only scans `scripts/` for `.lua`/`.lscript`/`.py` — a mod's HScript global only loads as `mods/<mod>/global.hx` through `Main`.
- The block editor's keybind is `debug_3` (`NINE`), declared in `ClientPrefs.keyBinds` and surfaced in `source/options/ControlsSubState.hx` — add both when adding a new debug key.

## 12. Where to look first

| Need | File |
|---|---|
| App boot, FPS, crash handler, global mod script | `source/Main.hx` |
| Scripted state override hook | `source/FNFGame.hx` |
| Asset/mod path resolution | `source/backend/Paths.hx` |
| Saved settings, keybinds, gameplay settings | `source/backend/ClientPrefs.hx` |
| State base classes, script hooks | `source/backend/MusicBeatState.hx`, `MusicBeatSubstate.hx` |
| Gameplay (largest file) | `source/states/game/PlayState.hx` |
| Song/section data, timing | `source/backend/songs/Song.hx`, `Section.hx`, `Conductor.hx` |
| Week/stage/achievement data | `source/backend/game/WeekData.hx`, `StageData.hx`, `Achievements.hx` |
| Modchart system | `source/modchart/ModManager.hx`, `Modifier.hx`, `Modcharts.hx` |
| Modchart ↔ `FlxTween` composition contract | `source/modchart/ModchartComposed.hx` (impl: `obj/Note.hx`, `obj/StrumNote.hx`) |
| HScript API surface | `source/script/hscript/HScriptUtil.hx` |
| HScript engine core (HScript/Script/ScriptType/InterpPro + default vars) | `source/script/FunkinHScript.hx` |
| Legacy `script.hscript.*` HScript paths (typedef aliases) | `source/script/hscript/HScript.hx`, `InterpPro.hx` |
| Lua runtime + custom menu states (`LuaSState`) | `source/psych/script/FunkinLua.hx` |
| Live proxy tables for Lua values (Lua's `this`) | `source/psych/script/LuaProxy.hx` |
| "Engine Custom ES" Lua dialect (extra callbacks, menu-mode registries) | `source/psych/script/ESCompat.hx` |
| lscript (Luau) runtime + `states/<Name>.lscript` overrides | `source/script/FunkinLScript.hx`, `source/script/LScriptSState.hx` |
| On-screen script errors outside PlayState (`LuaSState`/`LScriptSState`/`OScriptState`) | `source/script/ScriptDebugOverlay.hx` |
| Mods menu / `pack.json` parsing | `source/states/menu/ModsMenuState.hx` |
| Chart editor | `source/editors/ChartingState.hx` |
| Block code editor (standalone state, entry point) | `source/editors/BlockCodeEditorState.hx` |
| Block code editor (real-time substate over PlayState) | `source/editors/blockcode/BlockCodeEditorSubstate.hx` |
| Block catalogue / external block configs | `source/editors/blockcode/BlockLibrary.hx`, `BlockConfigLoader.hx` |
| Blocks <-> JSON cache, Lua codegen, Lua -> blocks | `source/editors/blockcode/BlockSerializer.hx`, `BlockLuaGenerator.hx`, `BlockLuaImporter.hx` |
| Where the generated Lua is saved | `source/editors/blockcode/BlockFileIO.hx` |
| Hot reloading the script inside a running song | `source/editors/blockcode/BlockScriptRuntime.hx` |
| Timeline (step/beat/second ruler, markers, drag to seek) | `source/editors/blockcode/BlockTimeline.hx` |
| Text entry incl. the Android soft keyboard | `source/editors/blockcode/BlockSoftKeyboard.hx`, `BlockVirtualKeyboard.hx` |
| Option menus | `source/options/OptionsState.hx`, `BaseOptionsMenu.hx` |
