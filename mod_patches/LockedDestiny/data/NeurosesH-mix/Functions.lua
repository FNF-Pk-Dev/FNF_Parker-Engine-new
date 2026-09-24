local crackLoop = false

local camMoveUp = false
local camUpTime = 0
local camUpDuration = 3.2

local camUpStartX = 0
local camUpStartY = 0
local camUpDistance = 2590

local function setZoom(value)
	set('defaultCamZoom', value)
	doTweenZoom('gameZoom', 'camGame', value, 1.1, 'quartOut')
end

local function hideNotes()
	set('ratingX', 4890)
	set('ratingY', 300)
	set('numScoreX', 4890)
	set('numScoreY', 300)
end

local function showNotes()
	set('ratingX', 55)
	set('ratingY', 105)
	set('numScoreX', 55)
	set('numScoreY', 105)
end

local function resetCharactersColor()
	set('boyfriend.colorTransform.redOffset', 0)
	set('boyfriend.colorTransform.greenOffset', 0)
	set('boyfriend.colorTransform.blueOffset', 0)
	set('boyfriend.colorTransform.redMultiplier', 1)
	set('boyfriend.colorTransform.greenMultiplier', 1)
	set('boyfriend.colorTransform.blueMultiplier', 1)

	set('dad.colorTransform.redOffset', 0)
	set('dad.colorTransform.greenOffset', 0)
	set('dad.colorTransform.blueOffset', 0)
	set('dad.colorTransform.redMultiplier', 1)
	set('dad.colorTransform.greenMultiplier', 1)
	set('dad.colorTransform.blueMultiplier', 1)
end

function onCreate()
	set('boyfriend.colorTransform.redOffset', 255)
	set('boyfriend.colorTransform.greenOffset', 255)
	set('boyfriend.colorTransform.blueOffset', 255)
	set('boyfriend.colorTransform.redMultiplier', 0)
	set('boyfriend.colorTransform.greenMultiplier', 0)
	set('boyfriend.colorTransform.blueMultiplier', 0)

	set('dad.colorTransform.redOffset', 255)
	set('dad.colorTransform.greenOffset', 255)
	set('dad.colorTransform.blueOffset', 255)
	set('dad.colorTransform.redMultiplier', 0)
	set('dad.colorTransform.greenMultiplier', 0)
	set('dad.colorTransform.blueMultiplier', 0)

	set('void.alpha', 1)
	set('Blacklay.alpha', 1)
	set('boyfriend.alpha', 0)

	set('par.alpha', 0)
	set('TVG.alpha', 0)
	set('sky.alpha', 0)
	set('m6.alpha', 0)
	set('m5.alpha', 0)
	set('m4.alpha', 0)
	set('m3.alpha', 0)
	set('m2.alpha', 0)
	set('m.alpha', 0)
	set('p.alpha', 0)
	set('crack.alpha', 0)
	set('crack2.alpha', 0)
	set('eyes.alpha', 0)
	set('eyes2.alpha', 0)
	set('ShadowBF2.alpha', 0)
	set('SBFG.alpha', 0)
	set('effRed.alpha', 0)
	set('faces.alpha', 0)
	set('bgs.alpha', 0)
	set('effYell.alpha', 0)
	set('floor2.alpha', 0)
	set('light.alpha', 0)
	set('ex.alpha', 0)
	set('sno.alpha', 0)
	set('line.alpha', 0)
	set('void2.alpha', 0)
	set('smoke.alpha', 0)
	set('end.alpha', 0)
	set('ov.alpha', 0)
	set('redlay.alpha', 0)
	set('spikes.alpha', 0)
	set('Border.alpha', 0)
	set('fadeEnd.alpha', 0)
	set('eyesBoom.alpha', 0)
	set('eyesBoom2.alpha', 0)
	set('gf.visible', false)
	set('TV.visible', false)
	set('TVS.visible', false)
	set('ShadowBF.visible', false)
	set('ShadowBF2.visible', false)
	set('ShadowSBF.visible', false)
	setVar('goodapple', true)

end

function onEventSet()
	stepEvent(0, function()
	set('par.alpha', 0)
	set('TVG.alpha', 0)
	set('sky.alpha', 0)
	set('m6.alpha', 0)
	set('m5.alpha', 0)
	set('m4.alpha', 0)
	set('m3.alpha', 0)
	set('m2.alpha', 0)
	set('m.alpha', 0)
	set('p.alpha', 0)
	set('crack.alpha', 0)
	set('crack2.alpha', 0)
	set('eyes.alpha', 0)
	set('eyes2.alpha', 0)
	set('ShadowBF2.alpha', 0)
	set('SBFG.alpha', 0)
	set('effRed.alpha', 0)
	set('faces.alpha', 0)
	set('bgs.alpha', 0)
	set('effYell.alpha', 0)
	set('floor2.alpha', 0)
	set('light.alpha', 0)
	set('ex.alpha', 0)
	set('sno.alpha', 0)
	set('line.alpha', 0)
	set('void2.alpha', 0)
	set('smoke.alpha', 0)
	set('end.alpha', 0)
	set('ov.alpha', 0)
	set('redlay.alpha', 0)
	set('spikes.alpha', 0)
	set('Border.alpha', 0)
	set('fadeEnd.alpha', 0)
	set('eyesBoom.alpha', 0)
	set('eyesBoom2.alpha', 0)
	crackLoop = false
	callOnLuas('disableEyesBoom')
	cancelTween('crackIn')
	cancelTween('crackOut')
	cancelTween('crack2In')
	cancelTween('crack2Out')
	end)

	stepEvent(11, function()
		strumTweenAlpha('NotesFade', 'all', 0, 0.2)
		hideNotes()
	end)

	stepEvent(15, function()
		set('NONOTES.alpha', 0)
	end)

	stepEvent(32, function()
		strumTweenAlpha('NotesFade', 'all', 0.75, 4)
	end)

	stepEvent(144, function()
		doTweenZoom('gameZoom', 'camGame', 1, 1.2, 'quartOut')
		set('defaultCamZoom', 1)

		doTweenAlpha('BlacklayGone','Blacklay',0,1,'linear')
	end)

	stepEvent(160, function()
		doTweenZoom('gameZoom', 'camGame', 0.85, 1.2, 'quartOut')
		set('defaultCamZoom', 0.85)
	end)

	stepEvent(176, function()
		set('defaultCamZoom', 0.85)
	end)

	stepEvent(188, function()
		doTweenZoom('gameZoom', 'camGame', 0.56, 1.2, 'quartOut')
		set('defaultCamZoom', 0.56)

		doTweenAlpha('bfFadeIn','boyfriend',1,0.5,'linear')
	end)

	stepEvent(256, function()
		doTweenZoom('gameZoom', 'camGame', 0.45, 1.1, 'quartOut')
		set('defaultCamZoom', 0.45)

		doTweenAngle('camGameAngle','camGame',0,1.2,'quadOut')
	end)

	stepEvent(288, function()
		resetCharactersColor()
		setVar('goodapple', false)
		set('gf.visible', true)
		set('TV.visible', true)
		set('TVS.visible', true)
		set('ShadowBF.visible', true)
		set('ShadowBF2.visible', true)
		set('ShadowSBF.visible', true)

		set('Blacklay.alpha', 0)
		set('void.alpha', 0)
		set('par.alpha', 0.25)
		set('TVG.alpha', 1)

		showNotes()
	end)

	stepEvent({411, 539, 667, 795, 924, 1307}, function()
		doTweenAlpha('TVSGone','TVS',1,0.5,'sineOut')
		doTweenAlpha('TVGGone','TVG',0.45,0.5,'sineOut')
	end)

	stepEvent({418, 544, 672, 800, 929, 1314}, function()
		doTweenAlpha('TVSGone','TVS',0.04,0.8,'sineOut')
		doTweenAlpha('TVGGone','TVG',1,0.8,'sineOut')
	end)

	stepEvent(506, function()
		doTweenZoom('gameZoom', 'camGame', 0.45, 1.1, 'quartOut')
		set('defaultCamZoom', 0.45)

		doTweenAngle('camGameAngle','camGame',0,1.2,'quadOut')
	end)

	stepEvent(544, function()
		doTweenZoom('gameZoom', 'camGame', 0.70, 1.1, 'quartOut')
		set('defaultCamZoom', 0.70)
	end)

	stepEvent(732, function()
		doTweenZoom('gameZoom', 'camGame', 0.83, 1.2, 'quartOut')
		set('defaultCamZoom', 0.83)
	end)

	stepEvent({288, 366, 448, 532, 626, 702}, function()
		doTweenAlpha('SBFG','SBFG',1,1.3,'linear')
	end)

	stepEvent({346, 430, 512, 586, 686, 772}, function()
		doTweenAlpha('SBFG','SBFG',0,1.3,'linear')
	end)

	stepEvent(800, function()
		set('ShadowBF.alpha', 0)
		set('ShadowBF2.alpha', 0.18)

		callOnLuas('enableEyesBoom')

		doTweenAlpha('eyesAppear', 'eyes', 1, 0.25, 'sineOut')
		doTweenAlpha('eyes2Appear', 'eyes2', 1, 0.25, 'sineOut')

		set('crack.alpha', 0)
		set('crack2.alpha', 0)

		objectPlayAnimation('crack', 'Anim', false)
		objectPlayAnimation('crack2', 'Anim', false)

		crackLoop = true
		crackFadeIn()
	end)

	stepEvent(1178, function()
		crackLoop = false

		callOnLuas('disableEyesBoom')

		cancelTween('crackIn')
		cancelTween('crackOut')
		cancelTween('crack2In')
		cancelTween('crack2Out')

		doTweenAlpha('crackGone', 'crack', 0, 1, 'sineOut')
		doTweenAlpha('crack2Gone', 'crack2', 0, 1, 'sineOut')

		doTweenAlpha('eyesAppear', 'eyes', 0, 1, 'sineOut')
		doTweenAlpha('eyes2Appear', 'eyes2', 0, 1, 'sineOut')
	end)

	stepEvent(1184, function()
		doTweenAlpha('Blacklay', 'Blacklay', 1, 1.5, 'linear')
		doTweenAlpha('par', 'par', 0, 2, 'linear')
		doTweenAlpha('TVG', 'TVG', 0, 2, 'linear')

		doTweenZoom('gameZoom', 'camGame', 0.45, 1.1, 'quartOut')
		set('defaultCamZoom', 0.45)

		doTweenAngle('camGameAngle','camGame',0,1.2,'quadOut')
	end)

	stepEvent(1205, function()
		set('par.alpha', 0.25)
		set('crack.alpha', 0)
		set('crack2.alpha', 0)

		objectPlayAnimation('crack', 'Anim', false)
		objectPlayAnimation('crack2', 'Anim', false)

		crackLoop = true
		crackFadeIn()
	end)

	stepEvent(1216, function()
		doTweenZoom('gameZoom', 'camGame', 0.38, 1.2, 'quartOut')
		set('defaultCamZoom', 0.38)
	end)

	stepEvent(1217, function()
		set('void.alpha', 1)
		doTweenAlpha('BlacklayGone','Blacklay',0,0.7,'linear')
	end)

	stepEvent(1248, function()
		set('defaultCamZoom', 0.56)
		doTweenAngle('camGameAngle', 'camGame', -4, 1.2, 'quadOut')

		triggerEvent('Change Character','1','SBFneurosesR')
		triggerEvent('Change Character','0','BFneurosesR2')
		doTweenScale('spikesScale','spikes',1.15,19,'linear')

		doTweenAlpha('spikesFade','spikes',1,5.5,'linear')
		doTweenAlpha('redlay','redlay',0.77,19,'linear')

		set('Blacklay.alpha', 0)
		set('void.alpha', 0)
		set('par.alpha', 0.25)
		set('TVG.alpha', 1)

		showNotes()

		callOnLuas('enableEyesBoom')

		set('eyes.alpha', 1)
		set('eyes2.alpha', 1)
	end)

	stepEvent(1552, function()
		doTweenAlpha('redlay', 'redlay', 0.40, 0.2, 'linear')
		doTweenAlpha('spikes', 'spikes', 0, 0.2, 'linear')

		doTweenZoom('gameZoom', 'camGame', 0.45, 1.1, 'quartOut')
		set('defaultCamZoom', 0.45)

		doTweenAngle('camGameAngle','camGame',0,1.2,'quadOut')
	end)

	stepEvent(1560, function()
		hideNotes()

		doTweenZoom('gameZoom','camGame',0.08,0.7,'linear')

		set('defaultCamZoom', 0.08)

		set('boyfriend.color', getColorFromHex('000000'))
		set('dad.color', getColorFromHex('000000'))

		set('void2.alpha', 1)
		set('TVG.alpha', 0)
		set('camFollowLerp', 9999)
	end)

	stepEvent(1568, function()
		callOnLuas('disableEyesBoom')

		set('boyfriend.color', getColorFromHex('FFFFFF'))
		set('dad.alpha', 0)
		set('boyfriend.alpha', 0)

		doTweenAlpha('void2', 'void2', 0, 1, 'linear')
		doTweenAlpha('spikes', 'spikes', 1, 1, 'linear')
		doTweenAlpha('eyes', 'eyes', 0, 1, 'linear')
		doTweenAlpha('eyes2', 'eyes2', 0, 1, 'linear')
		doTweenAlpha('redlay', 'redlay', 0.77, 1, 'linear')
		doTweenAlpha('effRed', 'effRed', 1, 1, 'linear')
		doTweenAlpha('TVG', 'TVG', 1, 1, 'linear')
		doTweenAlpha('faces', 'faces', 1, 1, 'linear')

		doTweenZoom('gameZoom','camGame',0.56,2,'quartOut')
		set('defaultCamZoom', 0.56)
	end)

	stepEvent(1569, function()
		doTweenAlpha('boyfriend','boyfriend',1,1,'linear')
		set('camFollowLerp', 3)
		set('dad.color', getColorFromHex('FFFFFF'))
	end)

	stepEvent(1584, function()
		doTweenZoom('cam1','camGame',1.2,20,'linear')
		set('defaultCamZoom', 1.2)
	end)

	stepEvent(1760, function()
		doTweenAlpha('bgs', 'bgs', 1, 1, 'linear')
		doTweenAlpha('line', 'line', 1, 1, 'linear')

		doTweenX('movebgsX', 'bgs', -200, 1, 'quartOut')
		doTweenX('movelineX', 'line', 500, 1, 'quartOut')

		cancelTween('cam1')

		doTweenZoom('gameZoom','camGame',0.82,1,'quartOut')
		set('defaultCamZoom', 0.82)
		doTweenAlpha('spikes', 'spikes', 0.45, 0.7, 'linear')
	end)

	stepEvent(1808, function()
		set('Blacklay.alpha', 0)

		doTweenAlpha('boyfriend', 'boyfriend', 0, 0.7, 'linear')
		doTweenAlpha('effRed', 'effRed', 0, 0.7, 'linear')
		doTweenAlpha('faces', 'faces', 0, 0.7, 'linear')

		doTweenColor('bgsBlack','bgs','000000',0.7,'linear')

		doTweenAlpha('line', 'line', 0, 0.7, 'linear')
		doTweenAlpha('spikes', 'spikes', 0, 0.7, 'linear')
		doTweenAlpha('TVG', 'TVG', 0, 0.7, 'linear')
		doTweenAlpha('redlay', 'redlay', 0, 0.7, 'linear')

		set('gf.alpha', 0)
		set('TV.alpha', 0)
		set('wall.alpha', 0)
		set('photos.alpha', 0)
		set('photos2.alpha', 0)
		set('floor.alpha', 0)
		set('cam.alpha', 0)
		set('shadowBF.alpha', 0)
		set('ShadowSBF.alpha', 0)
		set('par.alpha', 0)

		crackLoop = false

		callOnLuas('disableEyesBoom')

		cancelTween('crackIn')
		cancelTween('crackOut')
		cancelTween('crack2In')
		cancelTween('crack2Out')

		set('crack.alpha', 0)
		set('crack2.alpha', 0)
	end)

	stepEvent(1824, function()
		doTweenZoom('gameZoom','camGame',0.63,1,'quartOut')

		set('defaultCamZoom', 0.63)

		videoPlay('ex')
		set('ex.alpha', 1)

		doTweenAlpha('effYell', 'effYell', 1, 0.4, 'linear')
		doTweenAlpha('light', 'light', 0.86, 0.4, 'linear')

		objectPlayAnimation('light', 'Anim', true)
		set('bgs.alpha', 0)
	end)

	stepEvent(1840, function()
		doTweenAlpha('ex', 'ex', 0, 1, 'linear')
		set('camFollowLerp', 1.5)
	end)

	stepEvent(1864, function()
		doTweenZoom('gameZoom','camGame',0.75,1,'quartOut')
		set('defaultCamZoom', 0.75)
	end)

	stepEvent(1888, function()
		doTweenZoom('gameZoom','camGame',0.55,1,'quartOut')
		set('defaultCamZoom', 0.55)
	end)

	stepEvent(1860, function()
		set('boyfriend.alpha', 1)
		set('floor2.alpha', 1)
		set('boyfriend.y', 1300)
		set('boyfriend.x', -144)
	end)

	stepEvent(1864, function()
		doTweenY('bfY','boyfriend',655,1.3,'quartOut')
		doTweenY('floY','floor2',1120,1.3,'quartOut')
	end)

	stepEvent(1918, function()
		doTweenZoom('gameZoom','camGame',0.35,1.5,'quartOut')
		set('defaultCamZoom', 0.35)
	end)

	stepEvent(1951, function()
		set('camFollowLerp', 2.2)
		doTweenAlpha('light', 'light', 0, 0.5, 'linear')
	end)

	stepEvent(1964, function()
		set('camFollowLerp', 9999)

		set('camGame.angle', 4)
		set('camGame.zoom', 0.70)
		set('defaultCamZoom', 0.70)

		set('ex.alpha', 0)
		set('effYell.alpha', 0)

		doTweenAlpha('TVG', 'TVG', 1, 0.3, 'linear')
		doTweenAlpha('redlay', 'redlay', 0.40, 0.3, 'linear')

		set('gf.alpha', 1)
		set('TV.alpha', 1)
		set('wall.alpha', 1)
		set('photos.alpha', 1)
		set('photos2.alpha', 1)
		set('floor.alpha', 1)
		set('cam.alpha', 1)

		set('ShadowBF2.alpha', 0)
		set('ShadowBF.alpha', 0.18)
		set('ShadowSBF.alpha', 0.18)

		set('par.alpha', 0.25)

		showNotes()
		callOnLuas('enableEyesBoom')
		doTweenAlpha('eyesAppear', 'eyes', 1, 0.25, 'sineOut')
		doTweenAlpha('eyes2Appear', 'eyes2', 1, 0.25, 'sineOut')

		set('crack.alpha', 1)
		set('crack2.alpha', 1)
		objectPlayAnimation('crack', 'Anim', false)
		objectPlayAnimation('crack2', 'Anim', false)
		crackLoop = true
		crackFadeIn()
	end)

	stepEvent(1966, function()
		set('camFollowLerp', 2.4)
	end)

	stepEvent(2048, function()
		doTweenZoom('gameZoom','camGame',0.45,1.1,'quartOut')
		set('defaultCamZoom', 0.45)
		doTweenAngle('camGameAngle','camGame',0,1.2,'quadOut')
	end)

	stepEvent(2080, function()
		crackLoop = false

		cancelTween('crackIn')
		cancelTween('crackOut')
		cancelTween('crack2In')
		cancelTween('crack2Out')

		set('sky.alpha', 1)
		set('m6.alpha', 1)
		set('m5.alpha', 1)
		set('m4.alpha', 1)
		set('m3.alpha', 1)
		set('m2.alpha', 1)
		set('m.alpha', 1)
		set('p.alpha', 1)

		doTweenAlpha('crack2', 'crack2', 0, 2, 'linear')
		doTweenAlpha('crack', 'crack', 0, 2, 'linear')

		callOnLuas('disableEyesBoom')

		doTweenAlpha('eyes', 'eyes', 0, 2, 'linear')
		doTweenAlpha('eyes2', 'eyes2', 0, 2, 'linear')

		doTweenColor('dadBlack', 'dad', '000000', 2, 'linear')

		doTweenAlpha('gf', 'gf', 0, 2, 'linear')
		doTweenAlpha('TV', 'TV', 0, 2, 'linear')
		doTweenAlpha('wall', 'wall', 0, 2, 'linear')
		doTweenAlpha('photos', 'photos', 0, 2, 'linear')
		doTweenAlpha('photos2', 'photos2', 0, 2, 'linear')
		doTweenAlpha('floor', 'floor', 0, 2, 'linear')
		doTweenAlpha('cam', 'cam', 0, 2, 'linear')

		doTweenAlpha('shadow1', 'ShadowBF', 0, 2, 'linear')
		doTweenAlpha('shadow3', 'ShadowBF2', 0, 2, 'linear')
		doTweenAlpha('shadow2', 'ShadowSBF', 0, 2, 'linear')

		doTweenAlpha('par', 'par', 0, 2, 'linear')
		doTweenAlpha('TVG', 'TVG', 0, 2, 'linear')
		doTweenAlpha('TVS', 'TVS', 0, 2, 'linear')
		doTweenAlpha('redlay', 'redlay', 0, 2, 'linear')
		doTweenAlpha('BorderGone','Border',0,1.5,'sineOut')
		doTweenAlpha('sno', 'sno', 0.50, 1, 'linear')
		doTweenAlpha('ov', 'ov', 1, 1, 'linear')
		doTweenAlpha('smoke', 'smoke', 1, 1, 'linear')
		doTweenZoom('gameZoom','camGame',1,3,'quartOut')
		set('defaultCamZoom', 1)
	end)

	stepEvent(2082, function()
		cancelTween('BorderGone')
		doTweenAlpha('BorderGone','Border',0,1.5,'sineOut')
	end)

	stepEvent(2128, function()
		hideNotes()
	end)

	stepEvent(2287, function()
		set('camFollowLerp', 1.7)
		set('dad.alpha', 0)
	end)

	stepEvent(2288, function()
		doTweenZoom('gameZoom','camGame',0.62,1.7,'quartOut')
		set('defaultCamZoom', 0.62)
	end)

	stepEvent(2485, function()
		set('camZooming', false)
	end)

	stepEvent(2511, function()
		set('camFollowLerp', 2.4)
	end)

	stepEvent(2514, function()
		doTweenAlpha('ov', 'ov', 0, 3, 'linear')
		doTweenAlpha('sno', 'sno', 0, 2.2, 'linear')

		camUpStartX = get('camFollow.x')
		camUpStartY = get('camFollow.y')

		camUpTime = 0
		camMoveUp = true
	end)

	stepEvent(2532, function()
		set('end.alpha', 1)
		objectPlayAnimation('end', 'Anim', false)
	end)

	stepEvent(2564, function()
		doTweenAlpha('darkenEnd','fadeEnd',1,1.5,'linear')
	end)
end

-- CRACK LOOP
function crackFadeIn()
	if not crackLoop then
		return
	end
	doTweenAlpha('crackIn','crack',1,1.2,'sineInOut')
	doTweenAlpha('crack2In','crack2',1,1.2,'sineInOut')
end

function crackFadeOut()
	if not crackLoop then
		return
	end
	doTweenAlpha('crackOut','crack',0.45,1.2,'sineInOut')
	doTweenAlpha('crack2Out','crack2',0.45,1.2,'sineInOut')
end

function onTweenCompleted(tag)
	if tag == 'crackIn' or tag == 'crack2In' then

		if crackLoop then
			crackFadeOut()
		end

	elseif tag == 'crackOut' or tag == 'crack2Out' then

		if crackLoop then
			crackFadeIn()
		end
	end
end

function onUpdate(elapsed)
	if camMoveUp then
		camUpTime = camUpTime + elapsed

		local t = math.min(camUpTime / camUpDuration, 1)

		t = t * t * (3 - 2 * t)

		local currentX = camUpStartX
		local currentY = camUpStartY - (camUpDistance * t)

		triggerEvent('Camera Follow Pos',tostring(currentX),tostring(currentY))

		if t >= 1 then
			camMoveUp = false
			triggerEvent('Camera Follow Pos',tostring(camUpStartX),tostring(camUpStartY - camUpDistance))
		end
	end
end
