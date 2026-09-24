local flying = true

local radius = 35
local speed = 1
local angle = 0

local dadBaseY = 0
local sbfgBaseY = nil
local shadowBaseY = nil

local dadOffsetY = 0
local sbfgOffsetY = 0
local shadowOffsetY = 0

function refreshBases()
	dadBaseY = get('dad.y')
	if sbfgBaseY == nil then
		sbfgBaseY = get('SBFG.y')
		shadowBaseY = get('ShadowSBF.y')
	end
end

function onCreatePost()
	refreshBases()
end

function onUpdate(elapsed)
	if not flying then
		return
	end

	angle = angle + elapsed * speed

	local fly = math.sin(angle) * radius

	set('dad.y', dadBaseY + dadOffsetY + fly)
	set('SBFG.y', sbfgBaseY + sbfgOffsetY + fly)
	set('ShadowSBF.y', shadowBaseY + shadowOffsetY - fly)
end

function onEvent(name, value1, value2)
	if name == 'Change Character' and value1 == '1' then
		runTimer('refreshDadBase', 0.01)
	end
end

function onTimerCompleted(tag)
	if tag == 'refreshDadBase' then
		refreshBases()
	end
end

function onEventSet()
	stepEvent(1569, function()
		flying = false
		set('dad.y', 300)
		set('dad.x', -800)
	end)

	stepEvent(1760, function()
		flying = false
		doTweenAlpha('dadAlpha','dad',1,1,'linear')
		doTweenX('moveDadX','dad',160,1,'quartOut')
	end)

	stepEvent(1800, function()
		angle = 0
		refreshBases()
		flying = true
	end)

end
