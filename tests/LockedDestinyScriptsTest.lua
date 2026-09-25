-- Run from the repository root: lua tests/LockedDestinyScriptsTest.lua
-- Executes the shipped Lua callbacks against a small host, without launching the game.
local root = 'mod_patches/LockedDestiny/'

local function near(actual, expected)
	assert(math.abs(actual - expected) < 0.00001, tostring(actual)..' ~= '..tostring(expected))
end

local function host(path)
	local h = {properties = {}, vars = {}, timers = {}, keys = {}, sounds = {}, soundPlays = 0, files = {}, haxe = {}, step = -1, opens = 0, restarts = 0}
	local e = setmetatable({Function_Stop = 'FUNC_STOP', defaultBoyfriendX = 780, defaultBoyfriendY = 60}, {__index = _G})
	e.get = function(key) return h.properties[key] end
	e.set = function(key, value) h.properties[key] = value end
	e.getVar = function(key)
		-- The native Convert.anon_function bridge turns null callback results into 0.
		-- Lua treats 0 as true; do not make missing flags behave like nil in this host.
		local value = h.vars[key]
		if value == nil then return 0 end
		return value
	end
	e.setVar = function(key, value) h.vars[key] = value end
	e.stepEvent = function(step, callback)
		if type(step) == 'table' then
			for _, value in ipairs(step) do
				if value == h.step then callback() return end
			end
		elseif step == h.step then callback() end
	end
	e.runTimer = function(tag, duration) h.timers[tag] = duration end
	e.cancelTimer = function(tag) h.timers[tag] = nil end
	e.doTweenX = function(tag, object, value) e.set(object..'.x', value) end
	e.doTweenY = function(tag, object, value) e.set(object..'.y', value) end
	e.doTweenAlpha = function(tag, object, value) e.set(object..'.alpha', value) end
	e.doTweenZoom = function(tag, object, value) e.set(object..'.zoom', value) end
	e.getColorFromHex = function(value) return tonumber(value, 16) end
	e.doTweenColor = function(tag, object, value) e.set(object..'.color', e.getColorFromHex(value)) end
	e.callOnLuas = function() end
	e.cancelTween = function() end
	e.makeLuaSprite = function(tag, image, x, y)
		e.set(tag..'.x', x)
		e.set(tag..'.y', y)
	end
	e.makeAnimatedLuaSprite = e.makeLuaSprite
	e.luaSpriteExists = function(tag) return e.get(tag..'.x') ~= nil end
	e.checkFileExists = function(path) return h.files[path] == true end
	e.makeLuaText = function(tag, text) e.set(tag..'.text', text) end
	e.setText = function(tag, text) e.set(tag..'.text', text) end
	e.setTextSpeed = function(tag, value) e.set(tag..'.speed', value) end
	e.setTextFont = function(tag, value) e.set(tag..'.font', value) end
	for _, name in ipairs({'makeGraphic', 'add', 'setObjectCamera', 'addAnimationByPrefix', 'addOffset', 'makeColorBox',
		'scaleObject', 'setCam', 'addAnim', 'setTextSize', 'setTextWidth', 'setTextBorder', 'setTextAlign', 'setTextGradient', 'setTextColor'}) do
		e[name] = function() end
	end
	e.playAnim = function(tag, name) e.set(tag..'.anim', name) end
	e.getGraphicMidpointX = function() return 900 end
	e.getGraphicMidpointY = function() return 650 end
	e.getPropertyFromClass = function(class, field)
		assert(class ~= 'Conductor', 'Unqualified Conductor class is not available in Parker')
		if class == 'backend.songs.Conductor' then return 123456 end
		if field == 'camera.zoom' then return 0.7 end
		if class == 'backend.ClientPrefs' and field == 'pauseMusic' then return h.pauseMusic or 'Tea Time' end
	end
	e.setPropertyFromClass = function(class, field, value)
		assert(class ~= 'Conductor' and value ~= nil)
		e.set(class..'.'..field, value)
	end
	e.runHaxeCode = function(code) table.insert(h.haxe, code) end
	e.openCustomSubstate = function(name, pauseGame)
		assert(name == 'death' and not pauseGame)
		h.opens = h.opens + 1
	end
	e.playSound = function(name, volume, tag)
		h.sounds[tag or name] = name
		h.soundPlays = h.soundPlays + 1
	end
	e.stopSound = function(tag) h.sounds[tag] = nil end
	e.playMusic = function(name) h.music = name end
	e.keyboardJustPressed = function(key) return h.keys[key] == true end
	e.restartSong = function() h.restarts = h.restarts + 1 end
	assert(loadfile(root..path, 't', e))()
	return e, h
end

local e, h = host('data/NeurosesH-mix/Fly.lua')
local p = h.properties
p['dad.x'], p['dad.y'], p['dadGroup.x'], p['dadGroup.y'] = 0, -20, 100, 100
p['dad.positionArray[0]'], p['dad.positionArray[1]'] = -100, -120
p['SBFG.y'], p['ShadowSBF.y'] = -20, 435
e.onCreatePost()
e.onUpdate(1)
near(p['dad.y'], -20 + math.sin(1) * 35)
for _, step in ipairs({1569, 1760, 1800}) do
	h.step = step
	e.onEventSet()
end
near(p['dad.x'], 160)
near(p['dad.y'], 300)
-- New guitar instance, followed by the cached SBF that still holds the split-screen position.
p['dad.x'], p['dad.y'] = 150, 280
p['dad.positionArray[0]'], p['dad.positionArray[1]'] = 50, 180
e.onEvent('Change Character', '1', 'SBFneurosesRGuitar')
e.onUpdate(0.5)
near(p['dad.y'], 280 + math.sin(0.5) * 35)
p['dad.x'], p['dad.y'] = 160, 330
p['dad.positionArray[0]'], p['dad.positionArray[1]'] = -100, -120
e.onEvent('Change Character', 'dad', 'SBFneurosesR')
near(p['dad.x'], 0)
near(p['dad.y'], -20 + math.sin(0.5) * 35)
e.onUpdate(0.1)
near(p['dad.y'], -20 + math.sin(0.6) * 35)
near(p['ShadowSBF.y'], 435 - math.sin(0.6) * 35)
assert(next(h.timers) == nil, 'Character rebasing must not depend on a timer')

e, h = host('data/NeurosesH-mix/Functions.lua')
p = h.properties
p['boyfriend.curCharacter'] = 'BFneurosesR'
local cachedBoyfriends = {}
local defaultColors = {
	color = 0xFFFFFF,
	['colorTransform.redMultiplier'] = 1, ['colorTransform.greenMultiplier'] = 1, ['colorTransform.blueMultiplier'] = 1,
	['colorTransform.redOffset'] = 0, ['colorTransform.greenOffset'] = 0, ['colorTransform.blueOffset'] = 0,
	shader = 'sceneColorShader'
}
local function changeBoyfriend(name)
	local outgoing = {}
	for field in pairs(defaultColors) do outgoing[field] = p['boyfriend.'..field] end
	cachedBoyfriends[p['boyfriend.curCharacter']] = outgoing
	local incoming = cachedBoyfriends[name] or defaultColors
	for field, value in pairs(incoming) do p['boyfriend.'..field] = value end
	p['boyfriend.curCharacter'] = name
	if e.onEvent then e.onEvent('Change Character', '0', name) end
end
e.onCreate()
if e.onEvent then e.onEvent('Change Character', '0', 'BFneurosesR') end
assert(p['boyfriend.colorTransform.redOffset'] == 255 and p['boyfriend.colorTransform.redMultiplier'] == 0,
	'The opening goodapple silhouette must stay intact')
h.step = 288
e.onEventSet()
changeBoyfriend('BFneurosesR2')
h.step = 1560
e.onEventSet()
assert(p['boyfriend.color'] == 0, 'The transition must still turn BF into a black silhouette')
-- PlayState advances songPosition and dispatches chart events before the next step callback.
-- The 117600 ms swap therefore precedes the step-1568 color reset on the following update.
changeBoyfriend('BFneurosesCR')
h.step = 1568
e.onEventSet()
h.step = 1569
e.onEventSet()
changeBoyfriend('BFneurosesRP')
changeBoyfriend('BFneurosesR')
-- The ending brings the cached BF2 back at 155958.75 ms, just before step 2080.
changeBoyfriend('BFneurosesR2')
assert(p['boyfriend.color'] == 0xFFFFFF, 'Returning BF must not retain the earlier black transition tint')
for field, value in pairs(defaultColors) do
	assert(p['boyfriend.'..field] == value, 'BF color reset must clear RGB transforms and preserve the scene shader: '..field)
end
h.step = 2080
e.onEventSet()
assert(p['dad.color'] == 0 and p['boyfriend.color'] == 0xFFFFFF, 'The ending must darken only the opponent')
changeBoyfriend('BFneurosesR3')
assert(p['dad.color'] == 0 and p['boyfriend.color'] == 0xFFFFFF, 'The sad BF swap must preserve the opponent fade')

e, h = host('data/NeurosesH-mix/AutoText.lua')
e.onLoad()
assert(h.properties['TX.font'] == 'SBF.ttf' and h.properties['TX2.font'] == 'corrup.otf')
assert(h.vars.autoTextDisabled == false, 'Entering the song must enable subtitles')
-- An absent flag is returned as 0 by the actual bridge, never a request to hide text.
h.vars.autoTextDisabled = nil
e.onUpdate(0.1)
assert(h.properties['TX.speed'] == 0.05 and h.properties['TX2.speed'] == 0.05, 'Missing flags must not stop typing')
h.step = 255
e.onEventSet()
assert(h.properties['TX.alpha'] == 1 and h.timers.hideText ~= nil)
h.vars.autoTextDisabled = false
h.step = 546
e.onEventSet()
assert(h.properties['TX.text'] == "I'm better.")
h.vars.autoTextDisabled = 0
h.step = 836
e.onEventSet()
assert(h.properties['TX.text'] == 'Not again.', 'Only boolean true may disable subtitles')
h.vars.autoTextDisabled = true
e.onUpdate(0.1)
for _, tag in ipairs({'TXscreen', 'TX', 'TX2'}) do assert(h.properties[tag..'.alpha'] == 0) end
assert(h.properties['TX.speed'] == 0 and h.properties['TX2.speed'] == 0 and h.timers.hideText == nil)
h.step = 1784
e.onEventSet()
assert(h.properties['TX.alpha'] == 0, 'Death must prevent later subtitle events')

e, h = host('data/NeurosesH-mix/AutoText.lua')
h.vars.autoTextDisabled = true
e.onLoad()
h.step = 255
e.onEventSet()
assert(h.vars.autoTextDisabled == false and h.properties['TX.alpha'] == 1, 'A new song must clear the old death flag')

for _, song in ipairs({'NeurosesH-mix', 'raices'}) do
	for _, action in ipairs({'retry', 'exit'}) do
		e, h = host('data/'..song..'/customDeath.lua')
		e.onCreatePost()
		assert(e.onGameOver() == 'FUNC_STOP')
		assert(e.onGameOver() == 'FUNC_STOP' and h.opens == 1)
		assert(h.properties.paused and not h.properties.canPause and not h.properties.canReset)
		assert(h.vars.autoTextDisabled and h.properties.inCutscene)
		e.onCustomSubstateCreate('death')
		assert(h.properties['dead.anim'] == 'idle')
		e.onSoundFinished('losssfx')
		assert(h.properties['dead.anim'] == 'loop' and h.sounds.gameoverSound ~= nil)
		e.onUpdatePost()
		assert(h.properties['backend.songs.Conductor.songPosition'] == 123456)
		h.keys[action == 'retry' and 'ENTER' or 'ESCAPE'] = true
		e.onCustomSubstateUpdate('death', 0.01)
		h.keys = {}
		if action == 'retry' then
			assert(h.properties['dead.anim'] == 'confirm')
			e.onCustomSubstateUpdate('death', 3)
			assert(h.restarts == 1)
		else
			assert(h.timers.goCustomFreeplay == 0.55)
			e.onTimerCompleted('goCustomFreeplay')
			assert(h.music == 'freakyMenu2' and h.haxe[#h.haxe]:find('LuaMenuState', 1, true))
		end
	end
end

e, h = host('scripts/Pause Menu.lua')
e.onCreatePost()
e.onSoundFinished('losssfx')
assert(h.soundPlays == 0, 'Death sounds must not start pause music')
e.onCustomSubstateCreate('lullabyPause')
assert(h.sounds.pauseMusic == 'tea-time', 'Missing custom pause audio must use the selected pause music')
e.onSoundFinished('gameoverSound')
assert(h.soundPlays == 1, 'Unrelated completions must not restart pause music')
e.onSoundFinished('pauseMusic')
assert(h.soundPlays == 2, 'Only the pause track should loop')
e.onCustomSubstateDestroy('lullabyPause')
e.onSoundFinished('pauseMusic')
assert(h.sounds.pauseMusic == nil and h.soundPlays == 2, 'Closing pause must stop its music loop')
for _, folder in ipairs({'sounds', 'music'}) do
	e, h = host('scripts/Pause Menu.lua')
	h.files[folder..'/lullabyPause.ogg'] = true
	e.onCreatePost()
	e.onCustomSubstateCreate('lullabyPause')
	assert(h.sounds.pauseMusic == 'lullabyPause', 'An installed custom pause track takes precedence')
end
e, h = host('scripts/Pause Menu.lua')
h.pauseMusic = 'None'
e.onCreatePost()
e.onCustomSubstateCreate('lullabyPause')
e.onSoundFinished('pauseMusic')
assert(h.soundPlays == 0, 'The None pause music preference must stay silent')
print('PASS: SBF return, cached BF ending colors, subtitle flags, death retry/exit, and isolated pause audio with missing/custom/None tracks')
