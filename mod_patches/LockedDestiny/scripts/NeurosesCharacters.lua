-- This stage owns its shadows. Copy AFTER the live characters update so a
-- repeated note, held note or idle restart is reflected on the same frame.
local enabled = false
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

function onLoad()
	enabled = curStage == 'tvN'
	if not enabled then return end
	setProperty('gfGroup.visible', getVar('goodapple') ~= true)
	for _, tag in ipairs({'ShadowBF', 'ShadowBF2', 'ShadowSBF', 'SBFG'}) do
		setProperty(tag..'.active', false)
	end
	if not getProperty('isCameraOnForcedPos') then
		triggerEvent('Camera Follow Pos', '', '')
	end
end

function onUpdatePost(elapsed)
	if not enabled then return end
	-- Keep the hand-drawn HUD icons smooth and upright, as in this mod's layout.
	-- PlayState adds its own beat tilt before this callback, including after character swaps.
	for _, tag in ipairs({'iconP1', 'iconP2'}) do
		setProperty(tag..'.antialiasing', true)
		setProperty(tag..'.angle', 0)
	end
	-- Gate the group as well: a Change Character event replaces the gf sprite.
	-- Alpha remains under the song's control for its later fades.
	setProperty('gfGroup.visible', getVar('goodapple') ~= true)
	copyAnimation('boyfriend', 'ShadowBF')
	copyAnimation('boyfriend', 'ShadowBF2', 'anim')
	copyAnimation('dad', 'ShadowSBF')
	copyAnimation('dad', 'SBFG')
end
