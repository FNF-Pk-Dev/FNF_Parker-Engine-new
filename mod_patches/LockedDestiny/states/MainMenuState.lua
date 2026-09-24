local curIndex = 0
local accepted = false

function onCreate():Void
    luaDebugMode = true
playMenuMusic('freakyMenu2', 1, true)

makeLuaSprite('Effectred', 'Menu/Menu2/Effectred', 50, -445)
addAnim('Effectred', 'Anim', 'menuEffect20', 24, true)
scale('Effectred', 3, 3)
setBlendMode('Effectred', 'SCREEN')
add('Effectred')

makeLuaSprite('Effectcode', 'Menu/Menu2/EffectCode', -1280, -365)
addAnim('Effectcode', 'Anim', 'EffectC0', 24, true)
scale('Effectcode', 3.5, 3.5)
set('Effectcode.antialiasing', false);
add('Effectcode')

makeLuaSprite('Effectgreen', 'Menu/Menu2/GreenL', -1280, -445)
addAnim('Effectgreen', 'Anim', 'Effectgreen0', 24, true)
setBlendMode('Effectgreen', 'SCREEN')
scale('Effectgreen', 3, 3)
set('Effectgreen.alpha', 0.8)
add('Effectgreen')

FlxBackdrop('cosos1', 'Menu/Menu2/cosos', -750, -110, 'Y')
setVelocity('cosos1', 0, -70)
scale('cosos1', 2, 2)
set('cosos1.antialiasing', false);
setBlendMode('cosos1', 'MULTIPLY')
add('cosos1', false)
set('cosos1.alpha', 0)

FlxBackdrop('cosos2', 'Menu/Menu2/coso2', 220, -110, 'Y')
setVelocity('cosos2', 0, 70)
scale('cosos2', 1.5, 1.5)
setBlendMode('cosos2', 'MULTIPLY')
add('cosos2')
set('cosos2.alpha', 0)

BGSprite('Chained', 'Menu/Menu2/chainedmenu', 450, 60)
scale('Chained', 0.87, 0.87)
add('Chained')
set('Chained.color', getColorFromHex('000000'))
doTweenX('Chained', 'Chained', get('Chained.x') + 230, 1.4, 'expoInOut')

BGSprite('Spirit', 'Menu/Menu2/spi', 140, -210)
scale('Spirit', 0.81, 0.81)
add('Spirit')
set('Spirit.color', getColorFromHex('000000'))
doTweenX('Spirit', 'Spirit', get('Spirit.x') -230, 1.4, 'expoInOut')

BGSprite('BG', 'Menu/Menu2/BGMenu', -129, -50, 0, 0)
add('BG')

doTweenY('BG', 'BG', -1050, 1.5, 'expoInOut')

runTimer('ColorOG', 0.5)

runTimer('showthings', 0.65)

----Not Selected Options BG----
BGSprite('selected', 'Menu/Menu2/select', 415, 900, 0, 0)
add('selected')

BGSprite('selected2', 'Menu/Menu2/select', 415, 900, 0, 0)
add('selected2')

BGSprite('selected4', 'Menu/Menu2/select', 415, 900, 0, 0)
add('selected4')

----Not Selected Options----
BGSprite('noSelectedOp', 'Menu/Menu2/mainmenu0', 400, 900, 0, 0)
add('noSelectedOp')

BGSprite('noSelectedOp2', 'Menu/Menu2/mainmenu1', 445, 900, 0, 0)
add('noSelectedOp2')

BGSprite('noSelectedOp4', 'Menu/Menu2/mainmenu3', 400, 900, 0, 0)
add('noSelectedOp4')

----Selected Options----
BGSprite('selectedOp', 'Menu/Menu2/mainselected0', 400, 900, 0, 0)
add('selectedOp')

BGSprite('selectedOp2', 'Menu/Menu2/mainselected1', 445, 900, 0, 0)
add('selectedOp2')

BGSprite('selectedOp4', 'Menu/Menu2/mainselected3', 400, 900, 0, 0)
add('selectedOp4')

-- Not Selected BG Tween
doTweenY('selectedY', 'selected', 200, 1.5, 'expoInOut')
doTweenY('selected2Y', 'selected2', 315, 1.5, 'expoInOut')
doTweenY('selected4Y', 'selected4', 439, 1.5, 'expoInOut')

-- Not Selected Options Tween
doTweenY('noSel1', 'noSelectedOp', 195, 1.5, 'expoInOut')
doTweenY('noSel2', 'noSelectedOp2', 310, 1.5, 'expoInOut')
doTweenY('noSel4', 'noSelectedOp4', 433, 1.5, 'expoInOut')

-- Selected Options Tween
doTweenY('selOp1', 'selectedOp', 195, 1.5, 'expoInOut')
doTweenY('selOp2', 'selectedOp2', 310, 1.5, 'expoInOut')
doTweenY('selOp4', 'selectedOp4', 433, 1.5, 'expoInOut')

ColorBox('white', 'FFFFFF', 0, 0, 0, 0)
setBlendMode('white', 'add')
set('white.alpha', 0)
add('white')

makeLuaSprite('blackTop', nil, -700, -900)
makeGraphic('blackTop', 1380, 400, '000000')
add('blackTop', true)

makeLuaSprite('blackBottom', nil, -700, 420)
makeGraphic('blackBottom', 1380, 400, '000000')
add('blackBottom', true)

updateSelection()
end

function updateSelection()
	-- Only these three rows are created above; the removed third artwork has no sprite.
	for index, suffix in ipairs({'', '2', '4'}) do
		local selected = index == curIndex + 1
		set('selectedOp'..suffix..'.visible', selected)
		set('selected'..suffix..'.visible', selected)
		set('noSelectedOp'..suffix..'.visible', not selected)
	end
	playSound('scrollMenu2')
end

function onUpdateOptions(elapsed)

if accepted then
    return
end


if keyJustPressed('up') then
    curIndex = curIndex - 1
    if curIndex < 0 then curIndex = 2 end
    updateSelection()
end


if keyJustPressed('down') then
    curIndex = curIndex + 1
    if curIndex > 2 then curIndex = 0 end
    updateSelection()
end


if keyJustPressed('accept') then

    accepted = true

    if curIndex == 0 then
        runTimer('changeToStory', 1.2)
    end

    if curIndex == 1 then
        runTimer('changeToCredits', 1.2)
    end

    if curIndex == 2 then
        runTimer('changeToOptions', 1.2)
    end

    set('white.alpha', 0.2)
    doTweenAlpha('whitefade', 'white', 0, 1, 'linear')

    doTweenY('blackTopClose', 'blackTop', -400, 1.2, 'quartInOut')
    doTweenY('blackBottomClose', 'blackBottom', 0, 1.2, 'quartInOut')

    playSound('confirmMenu')

end


if keyJustPressed('back') then

    accepted = true

    doTweenY('blackTopClose', 'blackTop', -400, 0.6, 'quartInOut')
    doTweenY('blackBottomClose', 'blackBottom', 0, 0.6, 'quartInOut')

    runTimer('backToTitle', 0.55)

    playSound('cancelMenu')

end
end

function onTimerCompleted(tag)
if tag == 'backToTitle' then
    switchLuaMenu('TitleState')
end

if tag == 'ColorOG' then
doTweenColor('chainedColor', 'Chained', 'FFFFFF', 1.4, 'linear')
doTweenColor('spiritColor', 'Spirit', 'FFFFFF', 1.4, 'linear')
end

if tag == 'showthings' then
doTweenAlpha('cosos1', 'cosos1', 1, 0.6, 'linear')
doTweenAlpha('cosos2', 'cosos2', 1, 0.6, 'linear')
end

if tag == 'changeToStory' then
--switchSourceMenu('StoryMenuState')
switchLuaMenu('FreeplayState')
end
if tag == 'changeToCredits' then
--switchSourceMenu('FreeplayState')
switchLuaMenu('CreditsState')
end
if tag == 'changeToOptions' then
switchSourceMenu('OptionsState')
end
end
