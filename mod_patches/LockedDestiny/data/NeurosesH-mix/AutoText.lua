local floatTime = 0
local baseY = 318

local textDuration = 2.2
local fadeDuration = 0.5

local canTypeSound = false
local textVisible = false
local disabled = false

function onLoad()
	makeColorBox('TXscreen', -1050, -750, 1, 1, '000000')
	scaleObject('TXscreen', 9.9, 9.9)
	setCam('TXscreen', 'other')
	set('TXscreen.alpha', 0)
	add('TXscreen', false)

	makeLuaText('TX', '', 170, 318, baseY, 600)
	setCam('TX', 'other')
	setTextFont('TX', 'SBF.ttf')
	setTextSize('TX', 64)
	setTextWidth('TX', 900)
	setTextBorder('TX', '000000', 2.3)
	setTextAlign('TX', 'center')
	setTextSpeed('TX', 0.05)
	setTextGradient('TX', 'FFFFFF', '7E7CB1', 90)
	set('TX.alpha', 0)
	add('TX', false)

	makeLuaText('TX2', '', 170, 321, baseY, 600)
	setCam('TX2', 'hud')
	setTextFont('TX2', 'corrup.otf')
	setTextSize('TX2', 64)
	setTextWidth('TX2', 900)
	setTextBorder('TX2', '000000', 2.3)
	setTextAlign('TX2', 'center')
	setTextSpeed('TX2', 0.05)
	setTextColor('TX2', 'FF0000')
	setText('TX2', "I WON'T ALLOW IT.")
	set('TX2.alpha', 0)
	add('TX2', false)

	set('TX2.scale.x', 29)
	set('TX2.scale.y', 29)
end

-- TEXTO
local function showText(text)
	canTypeSound = true
	textVisible = true
	setText('TX', text)
	doTweenAlpha('bgAppear','TXscreen',0.17,fadeDuration,'quadOut')
	doTweenAlpha('txtAppear','TX',1,fadeDuration,'quadOut')
	runTimer('hideText', textDuration)
end

function onEventSet()
	if getVar('autoTextDisabled') then return end
	stepEvent(255, function()
		showText("Can you handle this?")
	end)

	stepEvent(546, function()
		showText("I'm better.")
	end)

	stepEvent(836, function()
		showText("Not again.")
	end)

	stepEvent(928, function()
		showText("Ignore it.")
	end)

	stepEvent(1281, function()
		showText("This isn't my doing.")
	end)

	stepEvent(1440, function()
		showText("Focus on our battle.")
	end)

	stepEvent(1560, function()
		set('TX2.alpha', 1)
		doTweenScale('txtGrow','TX2',1,0.2,'cubeOut')
	end)

	stepEvent(1568, function()
		set('TX2.alpha', 0)
	end)

	stepEvent(1784, function()
		showText("I've got it.")
	end)
end

-- TYPING
function onTyping(tag)
	if tag ~= 'TX' or not canTypeSound then
		return
	end

	playSound('TxtSoundN', 0.24)
	set('TX.scale.x', 1.08)
	set('TX.scale.y', 1.08)
	doTweenX('txtScaleX','TX.scale',1,0.12,'quadOut')
	doTweenY('txtScaleY','TX.scale',1,0.12,'quadOut')
end

-- TIMER
function onTimerCompleted(tag)
	if tag ~= 'hideText' then
		return
	end

	canTypeSound = false
	textVisible = false
	doTweenAlpha('bgHide','TXscreen',0,fadeDuration,'quadOut')
	doTweenAlpha('txtHide','TX',0,fadeDuration,'quadOut')
end

-- FLOAT
function onUpdate(elapsed)
	if getVar('autoTextDisabled') then
		if not disabled then
			disabled = true
			canTypeSound = false
			textVisible = false
			cancelTimer('hideText')
			setTextSpeed('TX', 0)
			setTextSpeed('TX2', 0)
			for _, tag in ipairs({'bgAppear', 'txtAppear', 'bgHide', 'txtHide', 'txtGrow', 'txtScaleX', 'txtScaleY'}) do
				cancelTween(tag)
			end
			for _, tag in ipairs({'TXscreen', 'TX', 'TX2'}) do
				set(tag..'.alpha', 0)
			end
		end
		return
	end
	if not textVisible then
		return
	end

	floatTime = floatTime + elapsed * 2
	set('TX.y',baseY + math.sin(floatTime) * 6)
end
