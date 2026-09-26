local credits = {}

local curCredit = 1
local totalCredits = 0

-- CONFI
local lineH = 145

local firstY = 170
local listStartY = 170

local creditX = 100

local scrollY = 0
local targetScrollY = 0
local scrollLerp = 0.2

local roleOffset = 48
local roleWidth = 550

-- LIGHT
local lightAlpha = 0
local lightDirection = 1

local lightMinAlpha = 0.25
local lightMaxAlpha = 0.65
local lightSpeed = 0.15

-- PARTICLES
local particleID = 0
local particleTimer = 0

local particleSpawnTime = 0.35

-- OBJECT
local randomOb = 0


local function spawnAmbientParticle()

    particleID = particleID + 1

    local tag = 'ambientParticle'..particleID

    local x = math.random(0, 1600)
    local y = math.random(-100, -20)

    makeLuaSprite(tag,'Menu/Menu4/white',x,y)

    local size = math.random(6, 12) / 100
    scale(tag,size,size)
    set(tag..'.alpha',math.random(40, 55) / 100)
    setCam(tag,'hud')
    add(tag,true)

    local fallTime = math.random(6, 10)
    doTweenY('particleFall'..particleID,tag,1000,fallTime,'linear')
    doTweenAlpha('particleFade'..particleID,tag,0,fallTime,'linear')

end

-- CREDITS
local creditList = {
    {name = 'PhantomFear',role = 'Creator of OG FNF Corruption'},
    {name = 'Melo',role = 'Director, Artist and Creator of the mod'},
    {name = 'EmptySouls',role = 'Coder and creator of the Engine Custom ES engine, Original engine Psych engine'},
    {name = 'AlterDZ',role = 'BFtv Neuroses Sprite Artist'},
    {name = 'Caidito',role = 'Coder and Artist on the HUD for Chainfall and Neuroses'},
    {name = 'Zhadnii',role = 'Music'},
    {name = 'OD4768',role = 'Music (also helped with the menu music)'},
    {name = 'H06',role = 'Music'},
    {name = 'VX',role = 'Helped with some visual effects'},
    {name = 'Raimbowcore',role = 'Helped with Raices charting'}

}

-- SPECIAL THANKS
local specialThanks = {
    'KG',
    'Rooxtsw',
    'Tuki (Azure)',
    'Nerozes',
    'Clzxy',
    'ADEstilo',
    'KKiche',
    'Kazzi',
    'KakarotZilla',
    'Mayxp<3',
    'You'
}

function onCreate()

    -- RANDOM
    math.randomseed(
        os.time() +
        math.floor(os.clock() * 100000)
    )

    randomOb =
        math.random(1,3)


    makeLuaSprite('St','Menu/Menu4/Street',-120,150)
    scale('St',0.8,0.8)
    add('St')


    -- OBJECTS

    makeLuaSprite('ob','Menu/Menu4/Ob1',80,120)
    scale('ob',0.8,0.8)
    add('ob')
    set('ob.alpha',0)

    makeLuaSprite('ob2','Menu/Menu4/Ob2',120,150)
    scale('ob2',0.8,0.8)
    add('ob2')
    set('ob2.alpha',0)

    makeLuaSprite('ob3','Menu/Menu4/Ob3',70,160)
    scale('ob3',0.8,0.8)
    add('ob3')
    set('ob3.alpha',0)

    if randomOb == 1 then

        set('ob.alpha',1)

    elseif randomOb == 2 then

        set('ob2.alpha',1)

    elseif randomOb == 3 then

        set('ob3.alpha',1)

    end


    makeLuaSprite('li','Menu/Menu4/light',-219,-360)
    scale('li',0.8,1)
    setBlendMode('li','ADD')
    add('li')

    lightAlpha = 0
    set('li.alpha',lightAlpha)

    makeLuaText('creditsTitle','CREDITS',0,creditX,70)
    setTextSize('creditsTitle',70)
    setTextFont('creditsTitle','other')
    setTextAlignment('creditsTitle','LEFT')

    if setObjectCamera then
        setObjectCamera('creditsTitle','hud')
    end

    addLuaText('creditsTitle')

    local index = 0

    for i, data in ipairs(creditList) do
        index = index + 1
        createCredit(index,data.name,data.role,true)
    end

    local specialTitleIndex =
        index + 1

    local specialTitleY =
        listStartY +
        lineH * (specialTitleIndex - 1) + 40

    makeLuaText('specialThanksTitle','SPECIAL THANKS',0,creditX,specialTitleY)
    setTextSize('specialThanksTitle',70)
    setTextFont('specialThanksTitle','other')
    setTextAlignment('specialThanksTitle','LEFT')

    if setObjectCamera then
        setObjectCamera('specialThanksTitle','hud')
    end

    addLuaText('specialThanksTitle')

    index =
        specialTitleIndex + 1

    for i, name in ipairs(specialThanks) do
        createCredit(index,name,nil,false)
        index = index + 1

    end

    totalCredits =
        #credits

    focusCredit(1,true)
    
    this:addTouchPad("UP_DOWN", "A_B")

end

function createCredit(index,name,role,hasRole)

    local baseY =
        listStartY +
        lineH * (index - 1)

    local nameTag =
        'creditName_'..index

    makeLuaText(nameTag,name,0,creditX,baseY)
    setTextSize(nameTag,54)
    setTextFont(nameTag,'other')
    setTextAlignment(nameTag,'LEFT')

    if setObjectCamera then
        setObjectCamera(nameTag,'hud')
    end

    addLuaText(nameTag)

    local roleTag = nil

    if hasRole and role ~= nil then

        roleTag =
            'creditRole_'..index

        makeLuaText(roleTag,role,0,creditX,baseY + roleOffset)
        setTextSize(roleTag,30)
        setTextFont(roleTag,'info')
        setTextWidth(roleTag,roleWidth)
        setTextAlignment(roleTag,'LEFT')
        setTextColor(roleTag,'AAAAAA')

        if setObjectCamera then
            setObjectCamera(roleTag,'hud')
        end

        addLuaText(roleTag)
    end

    credits[#credits + 1] = { nameTag = nameTag,

        roleTag = roleTag,

        baseY = baseY,

        hasRole = hasRole}
end

local function applyScroll()

    for _, credit in ipairs(credits) do
        set(credit.nameTag..'.y', credit.baseY - scrollY)

        if credit.hasRole then
            set(credit.roleTag..'.y', credit.baseY + roleOffset - scrollY)
        end
    end

    set('creditsTitle.y', 70 - scrollY)

    local specialTitleIndex =
        #creditList + 1

    local specialTitleY =
        listStartY +
        lineH * (specialTitleIndex - 1) + 40

    set('specialThanksTitle.y', specialTitleY - scrollY)
end

function focusCredit(newIndex,instant)

    if totalCredits <= 0 then
        return
    end

    if newIndex < 1 then
        newIndex = 1
    end

    if newIndex > totalCredits then
        newIndex = totalCredits
    end

    curCredit =
        newIndex

    for i, credit in ipairs(credits) do

        if i == curCredit then

            set(credit.nameTag..'.alpha',1)

            if credit.hasRole then
                set(credit.roleTag..'.alpha',1)
            end

        else

            set(credit.nameTag..'.alpha',0.4)

            if credit.hasRole then
                set(credit.roleTag..'.alpha',0)
            end
        end
    end

    local selected =
        credits[curCredit]

    targetScrollY =
        selected.baseY -
        firstY

    if instant then

        scrollY =
            targetScrollY

        applyScroll()
    end
end

function onUpdateOptions(elapsed)

    if totalCredits <= 0 then
        return
    end

    scrollY =
        scrollY +
        (targetScrollY - scrollY) *
        scrollLerp

    applyScroll()


    lightAlpha =
        lightAlpha +
        elapsed *
        lightSpeed *
        lightDirection

    if lightAlpha >= lightMaxAlpha then

        lightAlpha =
            lightMaxAlpha

        lightDirection = -1

    elseif lightAlpha <= lightMinAlpha then

        lightAlpha =
            lightMinAlpha

        lightDirection = 1
    end

    set('li.alpha', lightAlpha)

    particleTimer =
        particleTimer + elapsed

    if particleTimer >= particleSpawnTime then
        particleTimer = 0
        spawnAmbientParticle()
    end


    if this.controls.UI_UP_P then

        if curCredit > 1 then
            focusCredit(curCredit - 1, false)
            playSound('scrollMenu2')
        end
    end


    if this.controls.UI_DOWN_P then
        if curCredit < totalCredits then
            focusCredit(curCredit + 1, false)
            playSound('scrollMenu2')
        end
    end


    if keyJustPressed('back') then
        playSound('cancelMenu')
        switchLuaMenu('MainMenuState')
    end
end

function onTweenCompleted(tag)
    if string.find(tag,'particleFall') then

        local id =
            tag:gsub('particleFall','')

        local sprite =
            'ambientParticle'..id
        removeLuaSprite(sprite, false)
    end
end