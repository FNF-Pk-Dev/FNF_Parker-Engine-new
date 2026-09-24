function onMoveCamera(focus)
	if getVar('goodapple') == true then
		return
	end

	if focus == 'dad' then
		set('defaultCamZoom', 0.70)
		doTweenAngle('camGameAngle', 'camGame', 4, 1.2, 'quadOut')

	elseif focus == 'boyfriend' then
		set('defaultCamZoom', 0.56)

		doTweenAngle('camGameAngle', 'camGame', -4, 1.2, 'quadOut')

	else
		doTweenAngle('camGameAngle', 'camGame', 0, 1.2, 'quadOut')
	end
end
