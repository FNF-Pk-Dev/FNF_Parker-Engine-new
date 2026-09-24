--HEALTBAR
local damage = 0.015

function onLoad()
setVar('barAlpha', 0)

makeLuaSprite('dadBarBG', 'healthBar', 220, 650, 1, 1)
setCam('dadBarBG', 'hud')
scale('dadBarBG', 0.55, 1)

makeLuaSprite('bfBarBG', 'healthBar', 720, 650, 1, 1)
setCam('bfBarBG', 'hud')
set('bfBarBG.flipX', true)
scale('bfBarBG', 0.55, 1)

makeHealthBar('dadHealth', -120, 1)
setHealthBarColors('dadHealth', 'af3535', '611515')
scale('dadHealth', 0.55, 1.3)

makeHealthBar('bfHealth', 380, 1)
setHealthBarColors('bfHealth', '56764e', 'abed9b')
scale('bfHealth', 0.55, 1.3)

set('healthBar.alpha', 0)
set('healthBarBG.alpha', 0)

addArray({
'dadBarBG',
'dadHealth',
'bfBarBG',
'bfHealth'}, true)
end

function onUpdatePost()
local alpha = getVar('barAlpha') or 0
if alpha <= 0.01 then
alpha = 0
end

set('iconP1.alpha', alpha)
set('iconP2.alpha', alpha)
set('dadBarBG.alpha', alpha)
set('bfBarBG.alpha', alpha)
set('dadHealth.alpha', alpha)
set('bfHealth.alpha', alpha)

set('iconP1.x', 1060)
set('iconP1.y', 584)

set('iconP2.x', 70)
set('iconP2.y', 580)
end

--NOTES

function onCreate()
	-- Opponent
	setVarArray({'noteOffset0', 'noteOffset1', 'noteOffset2', 'noteOffset3'}, 0)

	-- Player
	setVarArray({'noteOffset4', 'noteOffset5', 'noteOffset6', 'noteOffset7'}, 0)
end


function onUpdate(elapsed)

	-- Opponent
	setVar('noteOffset0', lerp(getVar('noteOffset0'), 0, elapsed * 8))
	setVar('noteOffset1', lerp(getVar('noteOffset1'), 0, elapsed * 8))
	setVar('noteOffset2', lerp(getVar('noteOffset2'), 0, elapsed * 8))
	setVar('noteOffset3', lerp(getVar('noteOffset3'), 0, elapsed * 8))

	setNoteY(0, getVar('noteOffset0'))
	setNoteY(1, getVar('noteOffset1'))
	setNoteY(2, getVar('noteOffset2'))
	setNoteY(3, getVar('noteOffset3'))


	-- Player
	setVar('noteOffset4', lerp(getVar('noteOffset4'), 0, elapsed * 8))
	setVar('noteOffset5', lerp(getVar('noteOffset5'), 0, elapsed * 8))
	setVar('noteOffset6', lerp(getVar('noteOffset6'), 0, elapsed * 8))
	setVar('noteOffset7', lerp(getVar('noteOffset7'), 0, elapsed * 8))

	setNoteY(4, getVar('noteOffset4'))
	setNoteY(5, getVar('noteOffset5'))
	setNoteY(6, getVar('noteOffset6'))
	setNoteY(7, getVar('noteOffset7'))

end


function opponentNoteHit(id, noteData, noteType, isSustainNote)
	local minHealth = 0.05

	local newHealth = get('health') - damage

	if newHealth < minHealth then
		newHealth = minHealth
	end

	set('health', newHealth)

	if noteData == 0 then
		setVar('noteOffset0', -20)
	end

	if noteData == 1 then
		setVar('noteOffset1', -20)
	end

	if noteData == 2 then
		setVar('noteOffset2', -20)
	end

	if noteData == 3 then
		setVar('noteOffset3', -20)
	end

end

function goodNoteHit(id, noteData, noteType, isSustainNote)

	if noteData == 0 then
		setVar('noteOffset4', -20)
	end

	if noteData == 1 then
		setVar('noteOffset5', -20)
	end

	if noteData == 2 then
		setVar('noteOffset6', -20)
	end

	if noteData == 3 then
		setVar('noteOffset7', -20)
	end

end

function onEventSet()
--HEALTBAR
stepEvent({288, 1248, 1960}, function()
	doTweenFloatArray('barFade', {'barAlpha'}, {1}, 1, 'sineOut')
end)

stepEvent(800, function()
damage = 0.024
end)

stepEvent({1184, 1811, 2081}, function()
	doTweenFloatArray('barFade', {'barAlpha'}, {0}, 1, 'sineOut')
end)

stepEvent(1312, function()
damage = 0.026
end)

stepEvent({1567, 2080}, function()
damage = 0.035
end)

stepEvent(1788, function()
damage = 0.015
end)

--NOTES
stepEvent(1568, function()
strumTweenX('moveNote', 'opponent', -600, 0.8, 'quartOut')

noteTweenX('left1', 4, 40, 0.8, 'ExpoOut')
noteTweenX('left2', 5, 200, 0.8, 'ExpoOut')

noteTweenX('right1', 6, 970, 0.8, 'ExpoOut')
noteTweenX('right2', 7, 1120, 0.8, 'ExpoOut')
end)

stepEvent(1760, function()
noteTweenX('op1', 0, 89, 0.8, 'quartOut')
noteTweenX('op2', 1, 201, 0.8, 'quartOut')
noteTweenX('op3', 2, 314, 0.8, 'quartOut')
noteTweenX('op4', 3, 427, 0.8, 'quartOut')

noteTweenX('pl1', 4, 732, 0.8, 'quartOut')
noteTweenX('pl2', 5, 844, 0.8, 'quartOut')
noteTweenX('pl3', 6, 957, 0.8, 'quartOut')
noteTweenX('pl4', 7, 1069, 0.8, 'quartOut')
end)

stepEvent({1812, 2082}, function()
strumTweenAlpha('opponentFade', 'opponent', 0, 1, 'linear')
end)

stepEvent(1961, function()
strumTweenAlpha('opponentFade', 'opponent', 0.75, 1, 'linear')
end)

stepEvent(2485, function()
strumTweenAlpha('playerFade', 'player', 0, 1.7, 'linear')
end)
end
