local eyesBoomEnabled = false

local eyesBaseX = -700
local eyesBaseY = 20

local eyes2BaseX = 1360
local eyes2BaseY = 20

local eyesUpdateTimer = 0
local eyesUpdateRate = 0.05

function onCreatePost()
	--set("scoreTxt.visible", false)
	set('camZooming', true)

	set('gf.scrollFactor.x', 0.85)
	set('gf.scrollFactor.y', 0.85)
	set('gf.alpha', 0.9)

	set('introSoundsSuffix', '-soul')
	set('daInvWindow.alpha', 0)

	setLongSing('dad, boyfriend, SBFG, ShadowSBF, ShadowBF', false)
end

function onCreate()
	-- BACKGROUND
	makeLuaSprite('sky', 'NeurosesH-Mix/Sky', -680, -600, 0.1, 0.7)
	addAnim('sky', 'Anim', 'sk0', 27, true)
	scaleObject('sky', 5.5, 5.5)
	add('sky', false)
	set('sky.alpha', 0)

	makeLuaSprite('m6', 'NeurosesH-Mix/m6', -440, -60, 0.5, 0.5)
	scaleObject('m6', 0.65, 0.65)
	add('m6', false)
	set('m6.alpha', 0)

	makeLuaSprite('m5', 'NeurosesH-Mix/m5', -840, -260, 0.62, 0.62)
	scaleObject('m5', 0.65, 0.65)
	add('m5', false)
	set('m5.alpha', 0)

	makeLuaSprite('m4', 'NeurosesH-Mix/m4', 840, 20, 0.79, 0.68)
	scaleObject('m4', 0.55, 0.55)
	add('m4', false)
	set('m4.alpha', 0)

	makeLuaSprite('m3', 'NeurosesH-Mix/m3', -350, 20, 0.73, 0.63)
	scaleObject('m3', 0.55, 0.55)
	add('m3', false)
	set('m3.alpha', 0)

	makeLuaSprite('m2', 'NeurosesH-Mix/m2', 900, -140, 0.8, 0.9)
	scaleObject('m2', 0.55, 0.55)
	add('m2', false)
	set('m2.alpha', 0)

	makeLuaSprite('m', 'NeurosesH-Mix/m', -650, -140, 0.8, 0.7)
	scaleObject('m', 0.55, 0.55)
	add('m', false)
	set('m.alpha', 0)

	makeLuaSprite('p', 'NeurosesH-Mix/p', 420, 658)
	scaleObject('p', 1, 1.3)
	add('p', false)
	set('p.alpha', 0)

	makeLuaSprite('wall', 'NeurosesH-Mix/bg', -1000, -670, 0.8, 0.8)
	scaleObject('wall', 0.9, 0.9)
	add('wall', false)

	-- CRACKS
	makeLuaSprite('crack', 'NeurosesH-Mix/cracks', -840, -520, 0.8, 0.8)
	addAnim('crack', 'Anim', 'cracks10', 17, false)
	set('crack.alpha', 0)
	setBlendMode('crack', 'ADD')
	add('crack', false)

	makeLuaSprite('crack2', 'NeurosesH-Mix/cracks', 1210, -450, 0.85, 0.85)
	addAnim('crack2', 'Anim', 'cracks20', 17, false)
	set('crack2.alpha', 0)
	setBlendMode('crack2', 'ADD')
	add('crack2', false)

	-- PHOTOS
	makeLuaSprite('photos', 'NeurosesH-Mix/photos', -700, 20, 0.8, 0.8)
	scaleObject('photos', 0.6, 0.8)
	add('photos', false)

	makeLuaSprite('photos2', 'NeurosesH-Mix/photos', 1360, 20, 0.8, 0.8)
	scaleObject('photos2', 0.6, 0.8)
	set('photos2.flipX', true)
	add('photos2', false)

	-- EYES
	makeLuaSprite('eyes', 'NeurosesH-Mix/eyesp', -700, 20, 0.8, 0.8)
	scaleObject('eyes', 0.6, 0.8)
	set('eyes.alpha', 0)
	add('eyes', false)

	makeLuaSprite('eyes2', 'NeurosesH-Mix/eyesp', 1360, 20, 0.8, 0.8)
	scaleObject('eyes2', 0.6, 0.8)
	set('eyes2.flipX', true)
	set('eyes2.alpha', 0)
	add('eyes2', false)

	-- FLOOR
	makeLuaSprite('floor', 'NeurosesH-Mix/floor', -870, -200, 0.87, 0.87)
	scaleObject('floor', 0.8, 0.6)
	setBlendMode('floor', 'ADD')
	add('floor', false)

	-- TV
	makeLuaSprite('TV', 'NeurosesH-Mix/TV', 80, -300, 0.85, 0.85)
	addAnim('TV', 'Anim', 'TV0', 24, true)
	scaleObject('TV', 2.1, 2.1)
	add('TV', false)

	makeLuaSprite('TVS', 'NeurosesH-Mix/TVS', 80, -300, 0.85, 0.85)
	addAnim('TVS', 'Anim', 'TV20', 24, true)
	scaleObject('TVS', 2.1, 2.1)
	set('TVS.alpha', 0.04)
	add('TVS', false)
	setOrder('gfGroup', getOrder('TVS') - 0)

	-- CAMERA
	makeLuaSprite('cam', 'NeurosesH-Mix/camera', 470, 680, 0.95, 0.95)
	scaleObject('cam', 0.8, 0.8)
	add('cam', false)

	-- SHADOW CHARACTERS
	makeChar('ShadowSBF', 'SBFneurosesRSH', -20, 315, false)
	add('ShadowSBF', false)
	set('ShadowSBF.alpha', 0.18)

	makeChar('ShadowBF', 'BFneurosesRSH', 780, 65, true)
	add('ShadowBF', false)
	set('ShadowBF.alpha', 0.18)

	makeChar('ShadowBF2', 'BFneurosesR2SH', 780, 65, true)
	add('ShadowBF2', false)
	set('ShadowBF2.alpha', 0)

	makeChar('SBFG', 'SBFneurosesRG', 100, 100, false)
	set('SBFG.alpha', 0)
	add('SBFG', true)

	-- PARTICLES VIDEO
	makeVideoSprite('par','particlesN',-1335,-1520,4380,2920,'looping')
	videoPlay('par')
	setBlendMode('par', 'ADD')
	set('par.alpha', 0.25)
	add('par', true)

	-- RED EFFECT
	makeLuaSprite('effRed', 'NeurosesH-Mix/EffectN1', -680, -500, 0.8, 0.8)
	addAnim('effRed', 'Anim', 'eff0', 24, true)
	scaleObject('effRed', 5.5, 5.5)
	set('effRed.antialiasing', false)
	add('effRed', false)
	set('effRed.alpha', 0)

	-- FACES
	makeLuaSprite('faces', 'NeurosesH-Mix/Faces', -400, -220, 0.8, 0.8)
	scaleObject('faces', 0.5, 0.5)
	add('faces', false)
	set('faces.alpha', 0)

	makeLuaSprite('bgs', 'NeurosesH-Mix/bgS', -1400, 20, 0.8, 0.8)
	scaleObject('bgs', 1.2, 1.2)
	add('bgs', false)
	set('bgs.alpha', 0)

	-- YELLOW VIDEO
	makeVideoSprite('effYell','BGNeu',-1630,-1450,4760,4100,'looping')
	videoPlay('effYell')
	add('effYell', false)
	set('effYell.alpha', 0)

	-- PLATFORM
	makeLuaSprite('floor2', 'NeurosesH-Mix/platform', 267, 1625)
	scaleObject('floor2', 1, 1)
	add('floor2', false)
	set('floor2.alpha', 0)

	-- LIGHT
	makeLuaSprite('light', 'NeurosesH-Mix/Light', -1290, -630, 0.0, 0.0)
	addAnim('light', 'Anim', 'li0', 24, true)
	scaleObject('light', 7.5, 7.5)
	setBlendMode('light', 'ADD')
	add('light', true)
	set('light.alpha', 0)

	-- EXPLOSION VIDEO
	makeVideoSprite('ex','Explosion',-1295,-420,4080,2120,'looping')
	setBlendMode('ex', 'SCREEN')
	add('ex', true)
	set('ex.alpha', 0)

	-- SNOW
	makeLuaSprite('sno', 'NeurosesH-Mix/snow', -680, -500, 0.8, 0.8)
	addAnim('sno', 'Anim', 'sn0', 24, true)
	setBlendMode('sno', 'ADD')
	scaleObject('sno', 5.5, 5.5)
	add('sno', true)
	set('sno.alpha', 0)

	-- LINE
	makeLuaSprite('line', 'NeurosesH-Mix/line', -700, 20, 0.8, 0.8)
	scaleObject('line', 1.2, 1.2)
	add('line', true)
	set('line.alpha', 0)

	-- VOID
	makeColorBox('void2', -5050, -2999, 1, 1, 'FF0000')
	scaleObject('void2', 9.9, 9.9)
	set('void2.alpha', 0)
	add('void2', false)

	makeColorBox('void', -1050, -750, 1, 1, '000000')
	scaleObject('void', 9.9, 9.9)
	set('void.alpha', 0)
	add('void', false)

	-- SMOKE
	makeLuaSprite('smoke', 'NeurosesH-Mix/Smoke', -680, 220)
	addAnim('smoke', 'Anim', 'sm0', 24, true)
	setBlendMode('smoke', 'SCREEN')
	scaleObject('smoke', 4.5, 4.1)
	add('smoke', true)
	set('smoke.alpha', 0)

	-- END
	makeLuaSprite('end', 'NeurosesH-Mix/End', -205, -50)
	addAnim('end', 'Anim', 'ani0', 24, false)
	scaleObject('end', 0.6, 0.6)
	setCam('end', 'hud')
	add('end', false)
	set('end.alpha', 0)

	-- OVERLAY
	makeLuaSprite('ov', 'NeurosesH-Mix/Ov', 0, 0)
	setCam('ov', 'hud')
	scaleObject('ov', 0.8, 0.8)
	add('ov', false)
	set('ov.alpha', 0)

	-- RED LAYER
	makeColorBox('redlay', -830, -550, 1, 1, 'FF166C')
	scaleObject('redlay', 9.9, 9.9)
	set('redlay.alpha', 0)
	setBlendMode('redlay', 'MULTIPLY')
	add('redlay', true)

	-- TV GLOW
	makeLuaSprite('TVG', 'NeurosesH-Mix/TVG', -935, -520, 0.85, 0.85)
	scaleObject('TVG', 0.9, 0.9)
	setBlendMode('TVG', 'ADD')
	add('TVG', true)

	-- BLACK LAYER
	makeColorBox('Blacklay', -1050, -750, 1, 1, '000000')
	scaleObject('Blacklay', 9.9, 9.9)
	set('Blacklay.alpha', 0)
	add('Blacklay', true)

	-- SPIKES
	makeLuaSprite('spikes', 'NeurosesH-Mix/spikes', -1175, -660)
	scaleObject('spikes', 2.3, 2.3)
	setCam('spikes', 'hud')
	setBlendMode('spikes', 'MULTIPLY')
	set('spikes.alpha', 0)
	add('spikes', true)

	-- NO NOTES
	makeLuaSprite('NONOTES', 'NeurosesH-Mix/DIENOTES', -1175, -350)
	scaleObject('NONOTES', 2.3, 2.3)
	setCam('NONOTES', 'other')
	add('NONOTES', false)

	-- BORDER
	makeLuaSprite('Border', 'NeurosesH-Mix/EffectScreen', -30, 30)
	addAnim('Border', 'Anim', 'bor0', 24, true)
	setBlendMode('Border', 'ADD')
	scaleObject('Border', 2.1, 1.8)
	setCam('Border', 'hud')
	set('Border.alpha', 0)
	add('Border', false)

	-- FADE
	makeLuaSprite('fadeEnd', '', 0, 0)
	makeGraphic('fadeEnd', screenWidth, screenHeight, '000000')
	setCam('fadeEnd', 'hud')
	add('fadeEnd', true)
	set('fadeEnd.alpha', 0)

	makeLuaSprite('eyesBoom','NeurosesH-Mix/eyesp',eyesBaseX - 5,eyesBaseY + 5)
	scaleObject('eyesBoom', 0.6, 0.8)
	set('eyesBoom.alpha', 0)
	set('eyesBoom.active', false)
	setBlendMode('eyesBoom', 'ADD')
	add('eyesBoom', false)

	makeLuaSprite('eyesBoom2','NeurosesH-Mix/eyesp',eyes2BaseX - 5,eyes2BaseY + 5)
	scaleObject('eyesBoom2', 0.6, 0.8)
	set('eyesBoom2.flipX', true)
	set('eyesBoom2.alpha', 0)
	set('eyesBoom2.active', false)
	setBlendMode('eyesBoom2', 'ADD')
	add('eyesBoom2', false)
end

-- EYES BOOM
function onBeatHit()
	if eyesBoomEnabled and curBeat % 4 == 0 then
		makeEyesBoom('eyesBoom','eyes',-5,5)
		makeEyesBoom('eyesBoom2','eyes2',-5,5)
	end
end

function makeEyesBoom(tag, original, offsetX, offsetY)
	set(tag..'.active', true)
	set(tag..'.x',get(original..'.x') + offsetX)
	set(tag..'.y',get(original..'.y') + offsetY)
	set(tag..'.scale.x',get(original..'.scale.x'))
	set(tag..'.scale.y',get(original..'.scale.y'))
	set(tag..'.flipX',get(original..'.flipX'))
	set(tag..'.scrollFactor.x',get(original..'.scrollFactor.x'))
	set(tag..'.scrollFactor.y',get(original..'.scrollFactor.y'))
	set(tag..'.alpha', 0)
	doTweenAlpha(tag..'Appear',tag,1,0.08,'sineOut')
	doTweenX(tag..'ScaleX',tag..'.scale',get(original..'.scale.x') + 0.10,0.8,'cubeOut')
	doTweenY(tag..'ScaleY',tag..'.scale',get(original..'.scale.y') + 0.45,0.8,'cubeOut')
	doTweenY(tag..'MoveY',tag,get(tag..'.y') + 65,0.8,'cubeOut')
	doTweenAlpha(tag..'Alpha',tag,0,0.8,'linear')
end

function onTweenCompleted(tag)
	if tag == 'eyesBoomAlpha' then
		set('eyesBoom.alpha', 0)
		set('eyesBoom.active', false)
	end

	if tag == 'eyesBoom2Alpha' then
		set('eyesBoom2.alpha', 0)
		set('eyesBoom2.active', false)
	end
end

function enableEyesBoom()
	eyesBoomEnabled = true
end

function disableEyesBoom()
	eyesBoomEnabled = false
	doTweenAlpha('eyesBoomFade','eyesBoom',0,1,'sineOut')
	doTweenAlpha('eyesBoom2Fade','eyesBoom2',0,1,'sineOut')
end

function onUpdate(elapsed)
	eyesUpdateTimer = eyesUpdateTimer + elapsed
	if eyesUpdateTimer < eyesUpdateRate then
		return
	end

	eyesUpdateTimer = 0
	set('eyes.x',eyesBaseX + getRandomInt(-2, 5))
	set('eyes.y',eyesBaseY + getRandomInt(-2, 2))
	set('eyes2.x',eyes2BaseX + getRandomInt(-2, 5))
	set('eyes2.y',eyes2BaseY + getRandomInt(-2, 2))
end
