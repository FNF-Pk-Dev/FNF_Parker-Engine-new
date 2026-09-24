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

### Verifying a change when `lime build` is unavailable

On some machines `haxelib run lime build windows` fails before compiling anything with
`Error: Could not find haxelib "hxcpp-debug-server"` — that haxelib is registered as a **dev path**
pointing at a VSCode extension directory that may no longer exist. It is unrelated to the engine and must
not be worked around by editing `.haxelib` or the project files.

Two working fallbacks, in order of strength:

```bash
# 1. Typecheck / codegen only (fast, ~60-90 s, respects every define). Also the quickest
#    way to check a compile error after an edit.
haxe export/release/windows/haxe/debug.hxml

# 2. A real compile + link: strip the -D no-compilation flag that the generated hxml carries,
#    then build. Incremental, so repeat builds are fast.
sed '/^-D no-compilation$/d' export/release/windows/haxe/debug.hxml > /tmp/real_debug.hxml
haxe "$(cygpath -w /tmp/real_debug.hxml)"     # look for "Link: ApplicationMain-debug.exe"
```

`configure` regenerates `export/release/windows/haxe/debug.hxml` and restores `-D no-compilation`, so the
stripped copy has to be recreated after that. The linked binary lands at
`export/release/windows/obj/ApplicationMain-debug.exe`; if that file's mtime did not move, you only
typechecked and did **not** link. A build that dies with `fatal error C1083: ... Permission denied` on
`*.obj` usually means orphaned `cl.exe` processes from an interrupted build still hold the files — wait for
them to exit rather than deleting the `obj/` tree.

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
  psych/                    Psych-derived classes (FunkinLua, CallbackHandler, psych/cutscenes,
                            psych/obj, psych/script/GhostTrailSpirit — the ES ghost trail)
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

### The sustain end cap's `flipY`

The `holdend` artwork carries its rounded cap along the **bottom** of its frame (`NOTE_assets.png`:
`red hold end` is 51x64 with a flat top and an arc that narrows to 13 px on the last row; `hold piece` is a
plain 51x44 rectangle). Only the last piece of a chain keeps the `holdend` animation; every earlier piece is
switched to `hold`. So the cap ends up at the far end of the tail only when the frame's bottom is the end
away from the arrow.

`Note`'s constructor used to answer that once, from the direction the note was built in
(`if (ClientPrefs.downScroll) flipY = true;`). That is wrong the moment something moves the tail after
construction — the `reverse` modchart modifier mirrors the whole chain to the other end of the screen
(`modifiers/ReverseModifier.hx`) while `flipY` stays as built, so the cap pointed back at the arrow.

`Note.update()` now derives it from the live layout instead:

```haxe
if (isSustainNote && ClientPrefs.sustainEndCap && prevNote != null && prevNote != this)
	flipY = prevNote.y > y;
```

"the tail leaves this piece going up" is exactly the question the cap has to answer, and the previous
piece's y answers it for downscroll, upscroll, a mid-song scroll flip and a mirrored modchart alike.
`ClientPrefs.sustainEndCap` (Visuals & UI, default on) is the escape hatch, and like `sustainTrail` it is
independent of the modchart toggle. Flipping happens around the centred origin (`updateHitbox()` calls
`centerOrigin()`), so changing it mid-flight never shifts the piece sideways or vertically.

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

**ES camera model.** `MoveCamOnAnim(charIdx, anim, x, y)` (`ESCompat.hx:539`) is transition-anchored, not a persistent offset: a rule fires only on the frame a character *switches* to the registered anim (`camRuleAnims`, `ESCompat.hx:144`), and firing it re-anchors `camFollow` onto that character's Psych anchor — `anchorCamera()` (`ESCompat.hx:1446`) repeats `PlayState.moveCamera()`'s `getMidpoint()` formulas including the character's `cameraPosition` and the stage's `opponentCameraOffset`/`boyfriendCameraOffset`/`girlfriendCameraOffset` — and then adds the `(x, y)` nudge. The last character to change animation owns the camera, and rules are skipped while `isCameraOnForcedPos` ("Camera Follow Pos" events) holds the camera. The old delta/`applyCamOffset` model is gone: re-registering the anim a character is already playing no longer moves anything. The event's **empty-values branch therefore re-anchors on the spot**: it clears `isCameraOnForcedPos` and calls `moveCameraSection()` (`PlayState.hx:3839`) in the same frame, because ES does. Without that call the camera — and the zoom `onMoveCamera` scripts apply — stays on the pre-forced target for up to a whole section (see §11).

The two numbers those scripts `set()`/`doTweenZoom()` by name are **declared PlayState fields**, not free script variables: `camFollowLerp` (`PlayState.hx:174`, used by the follow lerp at `PlayState.hx:2948`) — `set('camFollowLerp', 9999)` snaps the camera on a scene cut, `2.4` restores it — and `defaultCamHUDZoom` (`PlayState.hx:258`, used by the HUD zoom lerp at `PlayState.hx:3132`, only while `camZooming`). They have to stay declared: `ESCompat.setPropertySafe()` (`ESCompat.hx:1552`) catches hxcpp's `Invalid field` throw and parks the value in the script variable map, so an undeclared name looks like a successful `set()` that moves nothing (see §11).

`doTweenZoom(tag, 'DefaultCamZoom'|'DefaultCamHUDZoom', value, duration, ease)` reaches the field through `tryTweenZoomVariable()` (`FunkinLua.hx:4619`), which runs a `FlxTween.num` that writes the Float directly; the generic path would hand `VarTween` the resolved Float and throw `The object does not have the property "zoom"` (see §11). `FunkinLua.call()` also runs `ESCompat.tick()` *before* its function-exists early return (`FunkinLua.hx:4902`), so a script with no `onUpdate` still gets the `onPlayAnim` emulation and its camera rules.

**ES spawn and layout defaults.** `makeChar()` (`ESCompat.hx:491`) also applies the character's own JSON `position` vector on top of the `(x, y)` it was handed (`char.x/y += positionArray[0/1]`, `ESCompat.hx:507`) — the same two lines as `PlayState.startCharacterPos()` (`PlayState.hx:1631`) — so leaving them out displaces every ES-spawned character by exactly its own position. `makeHealthBar()` (`ESCompat.hx:554`) offsets its y from `esHealthBarY()` (`ESCompat.hx:1344`, `(downScroll ? 0.1 : 0.9) * FlxG.height + 4`), which is ES's own bar y and **not** this engine's `PlayState.healthBar.y`, which sits at 0.11/0.89 of the height (`PlayState.hx:1127`), and always builds `RIGHT_TO_LEFT` because ES clones its own bar for every custom one — the tag is not consulted for a direction. The ES character format is read too: `CharacterFile` (`Character.hx:45`) honours `scale_x`/`scale_y` (an **absolute** per-axis scale, not a multiplier of `scale`, which is what a shadow character needs), `skew_x`/`skew_y` (degrees, CSS-convention shear, applied by a `drawComplex()` override at `Character.hx:338` that also forces `isSimpleRender()` false, `Character.hx:320`) and `angle` (`jsonAngle`); a character JSON with no skew takes the stock path byte-identically.

**ES `makeChar()` shadows copy frames.** `dadCopyFrames`, `bfCopyFrames`, `gfCopyFrames` and `extraCopyFrames` are declared `PlayState` Bools (`PlayState.hx:162`) because ES scripts `set()` them — the original build's field table carries the four names next to `characterBopper`, and only the first two have a consumer here. **`bfCopyFrames` defaults to `true`**, the other three to `false`: ES dialects only ask for the dad side explicitly (Locked Destiny's `set('dadCopyFrames', true)`), yet their player-side shadows still follow BF, and `set('bfCopyFrames', false)` is the way to opt out. While one is on, every `makeChar()` character on that side mirrors the source character's animation *and* `curAnim.curFrame`: `copyCharacterFrames()` (`ESCompat.hx:1498`), called from `tick()` (`ESCompat.hx:1400`) right after the `onPlayAnim` emulation. Only the anim name and the frame are copied — never `flipX`/offset/position, since the shadows are squashed/sheared floor variants that have to keep their own transform — and an anim the shadow's JSON does not carry is skipped silently (SBFG is a guitar variant of SBF), not treated as an error.

**ES shader tags are a namespace of their own.** `makeShader(tag, name)` (`ESCompat.hx:741`) stores the shader under its **tag** in `ESState.shaders` (`ESCompat.hx:117`, written at `ESCompat.hx:754`) — and, as a safety net for scripts that pass the file name instead, also seeds `PlayState.runtimeShaders` with the sources under `name` (`ESCompat.hx:758`) — while Psych's `setSpriteShader(obj, shader)` (`FunkinLua.hx:396`) only understands a shader **file name**, looked up in `PlayState.runtimeShaders` and `loadShaderSources()`. `ESCompat` therefore overrides `setSpriteShader` (`ESCompat.hx:788`, `#if MODS_ALLOWED`) to resolve the ES tag first and fall back to the file-name path on a miss; without it, every ES-tagged sprite shader (bloom, colour grading, wave, …) silently never attaches even though `setCameraShader`/`setShaderFloat` accept the tag. `loadShaderSources()` lives in `ESCompat.hx:2066` — the override resolves objects exactly like Psych's version instead of re-implementing that part.

`makeTrailSpirit()` (`ESCompat.hx:644`) is a real ghost trail, not a `FlxTrail` mapping (`FlxTrail` is no longer imported or reachable from ES at all): `source/psych/script/GhostTrailSpirit.hx` — a `FlxGroup` of pooled, inert `TrailGhost` sprites — snapshots the target's frame, offset and transform onto a ghost every `trailDelay` seconds, keeps it for `trailLife` seconds at an alpha fading linearly from `trailAlpha`, and drifts it at `trailSpeed` px/s: `trailDirection('follow')` chases the target, a compass name drifts that way, anything else leaves the ghost in place. `trailActive` stops the spawning (live ghosts still fade out) and `clearTrail` kills them immediately. Targets resolve through `getTrailTarget()` (`ESCompat.hx:1754`), so the character aliases (`dad`, `opponent`, …) work as well as tagged sprites.

`makeLuaText()` now has a dual signature (`ESCompat.hx:888`): six arguments mean ES's `(tag, text, size, x, y, width)` — `size` sets the text's size, `width` its creation box — while five arguments keep Psych's `(tag, text, width, x, y)` untouched. ES texts remember their box in `ESState.textBoxes`, and `anchorText()` (`ESCompat.hx:1919`) re-anchors a `CENTER`-aligned text inside it after `setText()`/`setTextWidth()`, so growing the wrap width no longer drags the text across the screen. `setTextGradient(tag, color1, color2, angle)` (`ESCompat.hx:980`, 90° = top to bottom) paints the ramp over the font box with a runtime shader (`TEXT_GRADIENT_FRAG`, `ESCompat.hx:1998`) and falls back to the flat `color1` when `ClientPrefs.shaders` is off or the renderer never registered the uniforms. Typing speed (`setTextSpeed`) is seconds per character, as in ES.

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
- **Add a character** — `characters/<name>.json` plus `images/characters/<name>.png` atlases; scripts via `characters/<name>.<ext>`. Stock Psych keys plus the optional ES-format ones `scale_x`/`scale_y` (absolute per-axis scale), `skew_x`/`skew_y` (degrees) and `angle` — see §8 and `source/obj/Character.hx`.
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
- **A note's `flipY` is not safe to decide once in the constructor** when a modchart can move the note afterwards. `Note.update()` re-derives the sustain end cap's `flipY` from `prevNote.y > y` (see §5, "The sustain end cap's `flipY`"); keep positional state that a modifier can invalidate out of the constructor, or a `reverse`/scroll-flip modchart will leave the rendering mirrored.
- **A splash's `x`/`y` is its centre, and callers must pass the receptor's midpoint.** `NoteSplash.setupNoteSplash()` aligns from the frame's real content rect because the shipped splash art is far off its own declared canvas centre; handing it `strum.x`/`strum.y` (the receptor's top-left) offsets the burst by up to ~13 px and makes it jump between the two animations. See §5, "Where a note splash actually goes".
- **Sustain length is driven by `defScale`, not `scale`.** `ScaleModifier` runs unconditionally and restores `scale.y = defScale.y` on every hold piece, so anything that stretches a sustain (`Note.hx`'s constructor, `resizeByRatio()`, `reloadNote()`) has to update `defScale` too or the trail breaks into chunks under the modchart. See §5, "Sustains, the modchart's scale modifier, and `defScale`".
- **Never use `Reflect.setField` to stash state on an engine object.** On hxcpp it is not a permissive dynamic write: `Reflect.field(o, name)` returns `null` for a field the class does not declare, but `Reflect.setField(o, name, v)` **throws** `Invalid field: <name>` (via `o.__SetField(...)`, `std/cpp/_std/Reflect.hx`). A read-then-write memo therefore looks safe in review and crashes at runtime the first time it takes the write branch. Reproduced standalone: `READ missing -> null` / `WRITE missing -> THREW: Invalid field:nope`. Declare the field on the class, or keep the state in a static `Map`. This is what broke `UIAnim.popText` — it threw `Invalid field:uiAnimRestX` from `StoryMenuState.create()` / `FreeplayState.create()` the first time either menu opened.

- **ES camera tuning goes through declared `PlayState` fields, never a `VarTween` on a resolved Float.** `doTweenZoom(tag, 'DefaultCamZoom'|'DefaultCamHUDZoom', …)` must keep taking `tryTweenZoomVariable()`'s numeric path (`FunkinLua.hx:4619`): a `VarTween` built on the resolved `defaultCamZoom` value would throw `The object does not have the property "zoom"` uncaught, mid-frame. Likewise `camFollowLerp` (`PlayState.hx:174`) and `defaultCamHUDZoom` (`PlayState.hx:258`) must stay declared fields on `PlayState`, because `ESCompat.setPropertySafe()` (`ESCompat.hx:1552`) catches hxcpp's `Invalid field` throw and parks the write in the script variable map — an undeclared ES `set()` looks like it succeeded and changes nothing. The same trap applies to the four `*CopyFrames` flags (`PlayState.hx:162`): a mod's `set('dadCopyFrames', true)` into a script variable instead of the field would leave the shadow characters static with no error.
- **An ES-spawned object must get the offsets the engine itself would apply.** `makeChar()` has to keep adding the character's own `positionArray` (`ESCompat.hx:507`, the twin of `PlayState.startCharacterPos()`), or every ES-spawned character sits displaced by its JSON `position`; `makeHealthBar()` likewise anchors on `esHealthBarY()` instead of `PlayState.healthBar.y` and always fills right-to-left whatever its tag says (ES clones its own bar; the direction is not derived from a `dad`-ish name). See §8, "ES spawn and layout defaults".
- **The ES "Camera Follow Pos" reset must re-anchor on the spot.** Its empty-values branch clears `isCameraOnForcedPos` and calls `moveCameraSection()` (`PlayState.hx:3839`) in the same frame because the original ES build does; removing that call reintroduces a one-section lag in which `camFollow`, and the zoom `onMoveCamera` scripts apply, stay parked on the pre-forced target. See §8, "ES camera model".
- **ES shader tags and Psych shader file names are two namespaces, and `setSpriteShader` is the bridge.** ES `makeShader(tag, name)` keys `ESState.shaders` by tag (`ESCompat.hx:754`), Psych's own `setSpriteShader` (`FunkinLua.hx:396`) resolves a file name in `PlayState.runtimeShaders`/`loadShaderSources()` only — so `ESCompat`'s override (`ESCompat.hx:788`) has to keep trying the tag first and falling back to the file-name path second. Drop the override and every ES-tagged sprite shader goes silently unset (the tag-addressed `setCameraShader`/`setShaderFloat` paths keep working, which is what makes it look like a mod bug rather than a missing feature). See §8, "ES shader tags are a namespace of their own".
- **Never read a sprite's `animation.curAnim` or `frames` through a `Dynamic` reference.** On hxcpp both come back `null` for sprites that are visibly animating: `spr.animation.curAnim` and `spr.frames` are `(get, set)` properties (and `frames` is private on `FlxSprite`), and the reflective path does not invoke those getters — while `spr.animation.getByName('idle')` and `spr.numFrames`, which are plain method calls, answer correctly. A "shadow characters never animate" `noanim` diagnosis built on `Dynamic` access was therefore an artifact, twice, and the code it "justified" was chasing a bug that did not exist. Cast to `FlxSprite` (or the concrete class) first and touch them typed.

## 12. Workflow for this repository

- **Commit and push when a task is finished.** The remote is `origin` = `https://github.com/FNF-Pk-Dev/FNF_Parker-Engine-new.git`, branch `main`. After finishing a task, commit the work with a message that explains *why* the change is needed (not just what moved), then `git push origin main`.
- **Update this file in the same commit** whenever a change alters something documented here — a new module, a new preference, a new invariant, a changed build/verify step. Add the guidance where a reader would look for it (the relevant §), not in a changelog at the bottom.
- **Never commit local scratch or secrets.** `.promptx/` and `.github/py.py` are ignored on purpose — `py.py` has a plaintext API token in it. Stage files explicitly rather than `git add -A`, and keep `export/` (build output) out of commits.
- **Report honestly when a change could not be verified.** `lime build` may be unavailable (§2); a typecheck is not a link, and neither is a playtest. Say which of the three you actually did.
- **Be careful with `git checkout`/`git stash` on files you have edited.** Both discard working-tree changes irreversibly; check for a backup (or commit first) before using them to compare against `HEAD`.

## 13. Where to look first

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
| Shared menu/HUD tween helpers (`uiAnimations`, menu beat sync) | `source/backend/UIAnim.hx` |
| Sustain trail rendering / `defScale` bookkeeping | `source/obj/Note.hx` (§5), `source/modchart/modifiers/ScaleModifier.hx` |
| Note splash placement | `source/obj/NoteSplash.hx` (§5), `PlayState.spawnNoteSplashOnNote` |
| HScript API surface | `source/script/hscript/HScriptUtil.hx` |
| HScript engine core (HScript/Script/ScriptType/InterpPro + default vars) | `source/script/FunkinHScript.hx` |
| Legacy `script.hscript.*` HScript paths (typedef aliases) | `source/script/hscript/HScript.hx`, `InterpPro.hx` |
| Lua runtime + custom menu states (`LuaSState`) | `source/psych/script/FunkinLua.hx` |
| Live proxy tables for Lua values (Lua's `this`) | `source/psych/script/LuaProxy.hx` |
| "Engine Custom ES" Lua dialect (extra callbacks, ES ghost trail, menu-mode registries) | `source/psych/script/ESCompat.hx`, `GhostTrailSpirit.hx` |
| ES character JSON keys (`scale_x`/`scale_y`, `skew_x`/`skew_y`, `angle`) | `source/obj/Character.hx` (§8) |
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
