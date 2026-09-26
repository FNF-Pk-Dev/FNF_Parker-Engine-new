-- Run from the repository root: lua tests/LockedDestinyFreeplayTest.lua
local function host(source)
	local h = {source = source, props = {}, texts = {}, sprites = {}, keys = {}, timers = {}, attempts = 0}
	local e = setmetatable({this = {controls = {}}}, {__index = _G})
	e.set = function(key, value) h.props[key] = value end
	e.setProperty = e.set
	e.getFreeplaySongCount = function() return #h.source end
	e.getFreeplaySongWeek = function(i) return h.source[i + 1].week end
	e.getFreeplaySongName = function(i) return h.source[i + 1].name end
	e.getFreeplaySongDisplay = e.getFreeplaySongName
	e.getFreeplayDiffCount = function(i) return #h.source[i + 1].diffs end
	e.getFreeplayDiffName = function(i, d) return h.source[i + 1].diffs[d + 1] end
	e.makeLuaText = function(tag, text, width, x, y)
		h.texts[tag] = text
		e.set(tag..'.y', y)
	end
	e.removeLuaText = function(tag) h.texts[tag] = nil end
	e.makeLuaSprite = function(tag, image, x, y)
		h.sprites[tag] = image
		e.set(tag..'.y', y)
	end
	e.removeLuaSprite = function(tag) h.sprites[tag] = nil end
	e.FlxBackdrop = e.makeLuaSprite
	e.getColorFromHex = function(color) return tonumber(color, 16) end
	e.keyJustPressed = function(key) return h.keys[key] == true end
	e.startFreeplaySongIndex = function(index, diff)
		h.attempts = h.attempts + 1
		if h.failLoad then return false end
		h.started = {index, diff}
		return true
	end
	e.runTimer = function(tag) h.timers[tag] = true end
	for _, name in ipairs({'setTextSize', 'setTextAlignment', 'setObjectCamera', 'addLuaText',
		'scale', 'add', 'setCam', 'setBlendMode', 'screenCenter', 'setVelocity', 'addAnim',
		'playAnim', 'doTweenY', 'doTweenX', 'doTweenColor', 'setTextBorder', 'setTextColor',
		'cancelTween', 'playSound', 'debugPrint'}) do
		e[name] = function() end
	end
	assert(loadfile('mod_patches/LockedDestiny/states/FreeplayState.lua', 't', e))()
	return e, h
end

local source = {
	{name = 'raices', week = 'week1', diffs = {'safe', 'canon'}},
	{name = 'neurosesh-mix', week = 'week2', diffs = {'safe', 'canon'}},
	{name = 'extra', week = 'week3', diffs = {'normal'}}
}
local e, h = host(source)
e.reloadFreeplayList()
assert(h.texts.songItem_0 == nil and h.texts.songItem_2 == nil, 'Other weeks leaked into the list')
assert(h.texts.songItem_1 == 'neurosesh-mix', 'Missing week2 song')
assert(h.props['songItem_1.y'] == 120, 'Filtered list has a gap at the top')
assert(h.props['Song6.visible'] == true and h.props['Song1.visible'] == false, 'Wrong selected cover')
assert(h.sprites.songPreview_1 == 'Menu/Menu3/SongsMini/Mini6', 'Wrong preview')
assert(h.props['songPreview_1.y'] == -350, 'Preview still uses the unfiltered position')
e.this.controls.UI_DOWN_P = true
e.onUpdateOptions(0)
e.this.controls.UI_DOWN_P = false
assert(h.props['Song6.visible'] == true, 'Single song did not wrap')
e.this.controls.UI_RIGHT_P = true
e.onUpdateOptions(0)
e.this.controls.UI_RIGHT_P = false
h.keys.accept = true
e.onUpdateOptions(0)
assert(h.started[1] == 1 and h.started[2] == 1, 'Launch lost the source index or difficulty')
assert(not h.timers.exitMenu, 'Successful song launch schedules a return to MainMenu')

-- Several non-contiguous source indices still produce adjacent rows and launch correctly.
local multiple = {source[1], source[2], source[3], {name = 'second', week = 'week2', diffs = {'hard'}}}
e, h = host(multiple)
e.reloadFreeplayList()
assert(h.props['songItem_3.y'] - h.props['songItem_1.y'] == 644, 'Filtered rows are not adjacent')
e.focusSong(2, true)
h.keys.accept = true
e.onUpdateOptions(0)
assert(h.started[1] == 3 and h.started[2] == 0, 'Second filtered song starts the wrong chart')

-- Failed loads leave the controls live so another difficulty or retry can work.
e, h = host(source)
e.reloadFreeplayList()
h.failLoad = true
h.keys.accept = true
e.onUpdateOptions(0)
assert(h.started == nil and not h.timers.exitMenu, 'Failed load exits the menu')
h.failLoad = false
e.onUpdateOptions(0)
assert(h.attempts == 2 and h.started[1] == 1, 'Failed load leaves the menu locked')

-- A direction and accept in the same frame must use the newly selected entry.
e, h = host(multiple)
e.reloadFreeplayList()
e.this.controls.UI_DOWN_P = true
h.keys.accept = true
e.onUpdateOptions(0)
assert(h.started[1] == 3, 'Same-frame selection launches the previous entry')

-- A missing/hidden week2 must not fall back to a song from another week.
e, h = host({source[1]})
e.reloadFreeplayList()
h.keys.accept = true
e.onUpdateOptions(0)
assert(next(h.texts) == nil and h.started == nil, 'Empty filter started another week')

print('PASS: week2-only freeplay, cover selection, contiguous rows and original launch indices')
