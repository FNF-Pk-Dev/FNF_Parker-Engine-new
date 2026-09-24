-- This stage owns its shadows. Copy AFTER the live characters update so a
-- repeated note, held note or idle restart is reflected on the same frame.
local enabled = false
local lastCharacters = {}
local atlasCharacters = {
	SBFneurosesR = true,
	SBFneurosesRGuitar = true,
	BFneurosesR = true,
	BFneurosesR2 = true,
	BFneurosesR3 = true,
	BFneurosesRP = true,
	BFneurosesCR = true
}
local singAnimations = {
	idle = true, singLEFT = true, singDOWN = true,
	singUP = true, singRIGHT = true
}

local function copyAnimation(source, target, extraAnimation)
	local anim = getAnimName(source)
	if not anim then return end
	local targetAnim = anim:gsub('miss$', '')
	if not singAnimations[targetAnim] and targetAnim ~= extraAnimation then return end
	local frame = getProperty(source..'.animation.curAnim.curFrame')
	if frame == nil then return end
	if getAnimName(target) ~= targetAnim then
		playAnim(target, targetAnim, true)
	end
	if getAnimName(target) ~= targetAnim then return end
	local count = getProperty(target..'.animation.curAnim.numFrames')
	if count and count > 0 then
		setProperty(target..'.animation.curAnim.curFrame', math.min(frame, count - 1))
	end
end

local function updateCameraBounds(tag)
	local character = getProperty(tag..'.curCharacter')
	if lastCharacters[tag] == character then return end
	lastCharacters[tag] = character
	if not atlasCharacters[character] then return end
	-- The baked atlas canvas contains padding for every pose. It is not the
	-- character's camera hitbox. Keep the rendering origin/scale untouched.
	local width = getProperty(tag..'.frame.frame.width')
	local height = getProperty(tag..'.frame.frame.height')
	if width and height and width > 0 and height > 0 then
		setProperty(tag..'.width', width * math.abs(getProperty(tag..'.scale.x')))
		setProperty(tag..'.height', height * math.abs(getProperty(tag..'.scale.y')))
	end
end

function onLoad()
	enabled = curStage == 'tvN'
	if not enabled then return end
	for _, tag in ipairs({'ShadowBF', 'ShadowBF2', 'ShadowSBF', 'SBFG'}) do
		setProperty(tag..'.active', false)
	end
	updateCameraBounds('dad')
	updateCameraBounds('boyfriend')
	if not getProperty('isCameraOnForcedPos') then
		triggerEvent('Camera Follow Pos', '', '')
	end
end

function onEvent(name, value1, value2)
	if enabled and name == 'Change Character' then
		updateCameraBounds('dad')
		updateCameraBounds('boyfriend')
	end
end

function onUpdatePost(elapsed)
	if not enabled then return end
	copyAnimation('boyfriend', 'ShadowBF')
	copyAnimation('boyfriend', 'ShadowBF2', 'anim')
	copyAnimation('dad', 'ShadowSBF')
	copyAnimation('dad', 'SBFG')
end
