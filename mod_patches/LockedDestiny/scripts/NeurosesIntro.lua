-- Play Video is already authored at 1650 ms in events.json. The engine now
-- exposes its group under the event's video name, including its alpha setter.
function onEvent(name, value1, value2)
	if curStage ~= 'tvN' then return end
	if name == 'Play Video' and value1 == 'IntroN' then
		cancelTimer('neurosesIntroFade')
		cancelTween('neurosesIntroAlpha')
		runTimer('neurosesIntroFade', 2.55)
	end
end

function onTimerCompleted(tag)
	if tag == 'neurosesIntroFade' and getProperty('IntroN.alpha') ~= nil then
		-- doTweenAlpha uses FlxTween.tween(video, {alpha: 0}, ...) internally.
		doTweenAlpha('neurosesIntroAlpha', 'IntroN', 0, 0.5, 'linear')
	end
end
