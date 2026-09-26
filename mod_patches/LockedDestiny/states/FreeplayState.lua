local songs = {}
local curSong = 1
local curDiff = 1
local totalSongs = 0

local lineH = 644
local firstY = 120
local listStartY = 120

local scrollY = 0
local targetScrollY = 0
local scrollLerp = 0.2

local beatTimer = 0
local beatLength = 0.5


-- evitar que el menu siga leyendo inputs dentro de la canción
local inFreeplayMenu = true

-- Crear lista y textos
function reloadFreeplayList()
	for _, entry in ipairs(songs) do
		removeLuaText(entry.tag, true)
		removeLuaSprite('songPreview_'..entry.index, true)
	end
	songs = {}
	totalSongs = 0
	local sourceCount = getFreeplaySongCount() or 0

	for i = 0, sourceCount - 1 do
		-- Keep the engine index: starting a song still uses the unfiltered list.
		if getFreeplaySongWeek(i) == 'week2' then
			local sName = getFreeplaySongName(i)
			local sDisplay = getFreeplaySongDisplay(i) or sName
			local diffCount = getFreeplayDiffCount(i)

			local tag = 'songItem_'..i
			local baseY = listStartY + lineH * #songs

			-- Texto canción
			makeLuaText(tag, sDisplay, 0, 100, baseY)
			setTextSize(tag, 28)
			setTextAlignment(tag, 'LEFT')

			if setObjectCamera then
				setObjectCamera(tag, 'hud')
			end

			addLuaText(tag)

			-- dificultades
			local diffs = {}

			for d = 0, diffCount - 1 do
				diffs[#diffs + 1] = getFreeplayDiffName(i, d) or ('diff'..d)
			end

			songs[#songs + 1] = {
				index = i,
				tag = tag,
				name = sName,
				displayName = sDisplay,
				diffs = diffs,
				baseY = baseY
			}
		end
	end

	totalSongs = #songs
	if totalSongs <= 0 then return end

	--Images
	local previews = {raices = 'Mini1', ['neurosesh-mix'] = 'Mini6'}
	for i, entry in ipairs(songs) do
		local image = previews[entry.name:lower()]
		if image then
			local tag = 'songPreview_'..entry.index
			makeLuaSprite(tag, 'Menu/Menu3/SongsMini/'..image, -580, -350 + lineH * (i - 1))
			scale(tag, 0.9, 0.9)
			add(tag, false)
			set(tag..'.color', getColorFromHex('000000'))
			doTweenColor('restoreColor_'..entry.index, tag, 'FFFFFF', 1, 'quadOut')
		end
	end

	-- Overlay
makeLuaSprite('Overlay', 'Menu/Menu3/Overlay', -71, 400)
scale('Overlay', 1, 1)
setCam('Overlay', 'camHUD')
setBlendMode('Overlay', 'MULTIPLY')
screenCenter('Overlay')
add('Overlay', false)

FlxBackdrop('OvBar', 'Menu/Menu3/OvBar', 220, 900, 'X')
setVelocity('OvBar', 45, 0)
setCam('OvBar', 'camHUD')
scale('OvBar', 1, 1)
add('OvBar')

FlxBackdrop('OvBar2', 'Menu/Menu3/OvBar', 220, -400, 'X')
setVelocity('OvBar2', 45, 0)
set('OvBar2.flipY', true)
setCam('OvBar2', 'camHUD')
scale('OvBar2', 1, 1)
add('OvBar2')

doTweenY('OvBarEnter', 'OvBar', 510, 1.5, 'quartOut')
doTweenY('OvBar2Enter', 'OvBar2', 0, 1.5, 'quartOut')

makeLuaSprite('diffBG', 'Menu/Menu3/DiffBG', 1700, 300)
scale('diffBG', 1, 1)
setCam('diffBG', 'camHUD')
add('diffBG', false)

makeLuaSprite('diff1', 'Menu/Menu3/Diffi', 1800, 308)
addAnim('diff1', 'Anim', 'Dif20', 24, true)
playAnim('diff1', 'Anim', true)
scale('diff1', 1, 1)
setCam('diff1', 'camHUD')
add('diff1', false)

makeLuaSprite('diff2', 'Menu/Menu3/Diffi', 1800, 308)
addAnim('diff2', 'Anim', 'Dif0', 24, true)
playAnim('diff2', 'Anim', true)
scale('diff2', 1, 1)
setCam('diff2', 'camHUD')
add('diff2', false)

makeLuaSprite('SBG', 'Menu/Menu3/SongBG', 312, 1200)
scale('SBG', 1, 1)
setCam('SBG', 'camHUD')
add('SBG', false)

makeLuaSprite('SBG2', 'Menu/Menu3/SongBG2', 312, 1200)
scale('SBG2', 1, 1)
setCam('SBG2', 'camHUD')
setBlendMode('SBG2', 'ADD')
add('SBG2', false)

makeLuaSprite('Song1', 'Menu/Menu3/songlist/ra', 465, 1300)
scale('Song1', 0.95, 0.95)
setCam('Song1', 'camHUD')
add('Song1', false)

makeLuaSprite('Song6', 'Menu/Menu3/songlist/neu', 465, 1300)
scale('Song6', 0.95, 0.95)
setCam('Song6', 'camHUD')
add('Song6', false)


doTweenY('SBGEnter', 'SBG', 520, 1.2, 'quartOut')
doTweenY('SBG2Enter', 'SBG2', 520, 1.2, 'quartOut')
doTweenY('Song1Enter', 'Song1', 536, 1.2, 'quartOut')
doTweenY('Song6Enter', 'Song6', 536, 1.2, 'quartOut')

doTweenX('diffBGEnter', 'diffBG', 935, 1.2, 'quartOut')
doTweenX('diff1Enter', 'diff1', 1055, 1.2, 'quartOut')
doTweenX('diff2Enter', 'diff2', 1055, 1.2, 'quartOut')


	-- mostrar solo la primera
	setProperty('diff1.visible', true)
	setProperty('diff2.visible', false)

	focusSong(1, true)
end

function onCreate()
	reloadFreeplayList()

	this:addTouchPad("LEFT_RIGHT", "A_B")
	this:addPadCamera();

	local bpm = 17

	beatLength = 39 / bpm
end

-- Aplicar scroll
local function applyScroll()
	for _, entry in ipairs(songs) do
		setProperty(entry.tag .. '.y', entry.baseY - scrollY)
	end
end

-- Actualizar selección
function focusSong(newIndex, instant)
	if totalSongs <= 0 then return end

	curSong = newIndex

	if curSong < 1 then
		curSong = totalSongs
	end

	if curSong > totalSongs then
		curSong = 1
	end

	-- colores
	for i, entry in ipairs(songs) do
		local tag = entry.tag

		if i == curSong then
			setTextBorder(tag, 2, 'FFFF00')
			setTextColor(tag, 'FFFFFF')
		else
			setTextBorder(tag, 0, '000000')
			setTextColor(tag, 'AAAAAA')
		end
	end

	-- validar dificultad
	local entry = songs[curSong]
	local maxDiffs = #entry.diffs

	if maxDiffs < 1 then
		curDiff = 1
	else
		if curDiff < 1 then
			curDiff = 1
		end

		if curDiff > maxDiffs then
			curDiff = maxDiffs
		end
	end

	-- mostrar Songs solo en canciones elegidas
	set('Song1.visible', false)
	set('Song6.visible', false)
	doTweenColor('SBG2Color', 'SBG2', 'CC0044', 0.8, 'quadOut')

if entry.name:lower() == 'raices' then
	set('Song1.visible', true)
	doTweenColor('SBG2Color', 'SBG2', '3DD435', 0.8, 'quadOut')
end

if entry.name:lower() == 'neurosesh-mix' then
	set('Song6.visible', true)
	doTweenColor('SBG2Color', 'SBG2', 'CC00FF', 0.8, 'quadOut')
end
	-- mostrar dificultad visual
	if curDiff == 1 then
		setProperty('diff1.visible', true)
		setProperty('diff2.visible', false)
	else
		setProperty('diff1.visible', false)
		setProperty('diff2.visible', true)
	end

	-- scroll
	local desiredScroll = entry.baseY - firstY
	targetScrollY = desiredScroll

	if instant then
		scrollY = targetScrollY
		applyScroll()
	end

	if camFollowPos then
		camFollowPos(0, targetScrollY)
	end
end

function diffBounce()

	doTweenX('diffBGPush', 'diffBG', 900, 0.06, 'quadOut')
	doTweenX('diff1Push', 'diff1', 1020, 0.06, 'quadOut')
	doTweenX('diff2Push', 'diff2', 1020, 0.06, 'quadOut')

	runTimer('diffBounceBack', 0.06)
end

function songBounce()

	cancelTween('SBGScaleX')
	cancelTween('SBGScaleY')

	cancelTween('SBG2ScaleX')
	cancelTween('SBG2ScaleY')

	cancelTween('Song1ScaleX')
	cancelTween('Song1ScaleY')

	cancelTween('Song2ScaleX')
	cancelTween('Song2ScaleY')

	cancelTween('Song3ScaleX')
	cancelTween('Song3ScaleY')

	cancelTween('Song6ScaleX')
	cancelTween('Song6ScaleY')

	doTweenX('SBGScaleX', 'SBG.scale', 1.06, 0.07, 'quadOut')
	doTweenY('SBGScaleY', 'SBG.scale', 1.06, 0.07, 'quadOut')

	doTweenX('SBG2ScaleX', 'SBG2.scale', 1.06, 0.07, 'quadOut')
	doTweenY('SBG2ScaleY', 'SBG2.scale',  1.06, 0.07, 'quadOut')

	doTweenX('Song1ScaleX', 'Song1.scale', 1.00, 0.07, 'quadOut')
	doTweenY('Song1ScaleY', 'Song1.scale', 1.00, 0.07, 'quadOut')

	doTweenX('Song2ScaleX', 'Song2.scale', 1.00, 0.07, 'quadOut')
	doTweenY('Song2ScaleY', 'Song2.scale', 1.00, 0.07, 'quadOut')

	doTweenX('Song3ScaleX', 'Song3.scale', 1.00, 0.07, 'quadOut')
	doTweenY('Song3ScaleY', 'Song3.scale', 1.00, 0.07, 'quadOut')

	doTweenX('Song6ScaleX', 'Song6.scale', 1.00, 0.07, 'quadOut')
	doTweenY('Song6ScaleY', 'Song6.scale', 1.00, 0.07, 'quadOut')

	runTimer('songBounceBack', 0.07)
end

function onTimerCompleted(tag)

	if tag == 'diffBounceBack' then

		-- volver con rebote
		doTweenX('diffBGBack', 'diffBG', 935, 0.16, 'backOut')
		doTweenX('diff1Back', 'diff1', 1055, 0.16, 'backOut')
		doTweenX('diff2Back', 'diff2', 1055, 0.16, 'backOut')
	end

	if tag == 'songBounceBack' then

		doTweenX('SBGBackX', 'SBG.scale', 1, 0.16, 'backOut')
		doTweenY('SBGBackY', 'SBG.scale', 1, 0.16, 'backOut')

		doTweenX('SBG2BackX', 'SBG2.scale', 1, 0.16, 'backOut')
		doTweenY('SBG2BackY', 'SBG2.scale', 1, 0.16, 'backOut')

		doTweenX('Song1BackX', 'Song1.scale', 0.95, 0.16, 'backOut')
		doTweenY('Song1BackY', 'Song1.scale', 0.95, 0.16, 'backOut')

		doTweenX('Song2BackX', 'Song2.scale', 0.95, 0.16, 'backOut')
		doTweenY('Song2BackY', 'Song2.scale', 0.95, 0.16, 'backOut')

		doTweenX('Song3BackX', 'Song3.scale', 0.95, 0.16, 'backOut')
		doTweenY('Song3BackY', 'Song3.scale', 0.95, 0.16, 'backOut')

		doTweenX('Song6BackX', 'Song6.scale', 0.95, 0.16, 'backOut')
		doTweenY('Song6BackY', 'Song6.scale', 0.95, 0.16, 'backOut')
	end

	if tag == 'exitMenu' then
		switchLuaMenu('MainMenuState')
	end
end

local floatTime = 0
local canFloat = false

function onTweenCompleted(tag)

	if tag == 'Song6Enter' then
		canFloat = true
	end
end

function onUpdate(elapsed)

	if not canFloat then
		return
	end

	floatTime = floatTime + elapsed

	-- todos sincronizados
	local wave = math.sin(floatTime * 1.2) * 8

	setProperty('SBG.y', 520 + wave)
	setProperty('SBG2.y', 520 + wave)
	setProperty('Song1.y', 536 + wave)
	setProperty('Song2.y', 536 + wave)
	setProperty('Song3.y', 536 + wave)
	setProperty('Song6.y', 536 + wave)

	beatTimer = beatTimer + elapsed

	if beatTimer >= beatLength then
		beatTimer = beatTimer - beatLength

		setProperty('camGame.zoom', 1.03)

		doTweenZoom('menuZoom', 'camGame', 1, 0.15, 'quadOut')
	end
end

function onUpdateOptions(elapsed)

	-- impedir inputs fuera del freeplay
	if not inFreeplayMenu then
		return
	end

	if totalSongs <= 0 then return end

	-- scroll suave
	scrollY = scrollY + (targetScrollY - scrollY) * scrollLerp
	applyScroll()

	local entry = songs[curSong]
	local maxDiffs = #entry.diffs

	if maxDiffs < 1 then
		maxDiffs = 1
	end

	-- CAMBIAR DIFICULTAD
	if this.controls.UI_LEFT_P then
		curDiff = curDiff - 1

			diffBounce()

		if curDiff < 1 then
			curDiff = maxDiffs
		end

		if curDiff == 1 then
			setProperty('diff1.visible', true)
			setProperty('diff2.visible', false)
		else
			setProperty('diff1.visible', false)
			setProperty('diff2.visible', true)
		end
	end

	if this.controls.UI_RIGHT_P then
		curDiff = curDiff + 1

			diffBounce()

		if curDiff > maxDiffs then
			curDiff = 1
		end

		if curDiff == 1 then
			setProperty('diff1.visible', true)
			setProperty('diff2.visible', false)
		else
			setProperty('diff1.visible', false)
			setProperty('diff2.visible', true)
		end
	end

	-- CAMBIAR CANCIÓN
	if this.controls.UI_UP_P then
		focusSong(curSong - 1, false)
		playSound('scrollMenu2')
		songBounce()
	end

	if this.controls.UI_DOWN_P then
		focusSong(curSong + 1, false)
		playSound('scrollMenu2')
		songBounce()
	end

	-- aceptar
	if keyJustPressed('accept') then
		entry = songs[curSong]
		local haxeIndex = entry.index
		local diffIndex = curDiff - 1
		-- Stay interactive when a chart cannot load, and never send a song launch back to the menu.
		if startFreeplaySongIndex(haxeIndex, diffIndex) ~= true then return end
		inFreeplayMenu = false

		doTweenY('OvBarExit', 'OvBar', 900, 0.6, 'quartIn')
		doTweenY('OvBar2Exit', 'OvBar2', -400, 0.6, 'quartIn')

		doTweenY('SBGExit', 'SBG', 1200, 0.6, 'quartIn')
		doTweenY('SBG2Exit', 'SBG2', 1200, 0.6, 'quartIn')
		doTweenY('Song1Exit', 'Song1', 1300, 0.6, 'quartIn')
		doTweenY('Song2Exit', 'Song2', 1300, 0.6, 'quartIn')
		doTweenY('Song3Exit', 'Song3', 1300, 0.6, 'quartIn')
		doTweenY('Song6Exit', 'Song6', 1300, 0.6, 'quartIn')

		doTweenX('diffBGExit', 'diffBG', 1700, 0.6, 'quartIn')
		doTweenX('diff1Exit', 'diff1', 1800, 0.6, 'quartIn')
		doTweenX('diff2Exit', 'diff2', 1800, 0.6, 'quartIn')
		playSound('confirmMenu')

		debugPrint('FREEPLAY LUA -> index='..haxeIndex..' diff='..diffIndex)
		return
	end

	-- volver
	if keyJustPressed('back') then
		inFreeplayMenu = false
		switchLuaMenu('MainMenuState')

		doTweenY('OvBarExit', 'OvBar', 900, 0.6, 'quartIn')
		doTweenY('OvBar2Exit', 'OvBar2', -400, 0.6, 'quartIn')

		doTweenY('SBGExit', 'SBG', 1200, 0.6, 'quartIn')
		doTweenY('SBG2Exit', 'SBG2', 1200, 0.6, 'quartIn')
		doTweenY('Song1Exit', 'Song1', 1300, 0.6, 'quartIn')
		doTweenY('Song2Exit', 'Song2', 1300, 0.6, 'quartIn')
		doTweenY('Song3Exit', 'Song3', 1300, 0.6, 'quartIn')
		doTweenY('Song6Exit', 'Song6', 1300, 0.6, 'quartIn')

		doTweenX('diffBGExit', 'diffBG', 1700, 0.6, 'quartIn')
		doTweenX('diff1Exit', 'diff1', 1800, 0.6, 'quartIn')
		doTweenX('diff2Exit', 'diff2', 1800, 0.6, 'quartIn')
		playSound('cancelMenu')

		runTimer('exitMenu', 0.95)
	end

end

function onBeatHit()

	triggerEvent('Add Camera Zoom', 0.015, 0.03)

end
