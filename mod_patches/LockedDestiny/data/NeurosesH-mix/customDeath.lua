--SCRIPT BY RORUTOP

local Assets = {
	character = {
		name = 'BOYFRIEND_DEAD',
		idle = 'BF dies',
		loop = 'BF Dead Loop',
		confirm = 'BF Dead confirm'
	},

	sounds = {
		loss = 'fnf_loss_sfx',
		music = 'gameOver',
		confirm = 'gameOverEnd'
	}
}

local debounce = {}

local freezedPos = 0
local vol = 0.8

local deathCamX = 0
local deathCamY = 0
local deathCamZoom = 1

local onLoop = false
local isConFirm = false
local isExit = false

local notesStopped = false

function lerp(a, b, t) return a * (1 - t) + b * t
end

function createBox(name, x, y, width, height, color, alpha, cam)
	makeLuaSprite(name, '', x, y)
	makeGraphic(name, width, height, color)
	set(name .. '.alpha', alpha)
	add(name, true)
	setObjectCamera(name, cam)
end

function unsetShader()
	runHaxeCode([[
		game.camGame.setFilters([]);
		game.camHUD.setFilters([]);
		game.camOther.setFilters([]);]])
end

function onCreatePost()
	setPropertyFromClass('flixel.FlxG','save.data.isFuckingDead',false)
end

function stopOpponentNotes()
	if notesStopped then
		return
	end

	notesStopped = true

	runHaxeCode([[
		for (note in game.notes)
		{
			if (note != null && !note.mustPress)
			{
				note.active = false;
				note.visible = false;
				note.ignoreNote = true;
				note.wasGoodHit = true;
			}
		}
	]])
end

function lockDeathCamera()
	set('camFollow.x', deathCamX)
	set('camFollow.y', deathCamY)
	set('camFollowPos.x', deathCamX)
	set('camFollowPos.y', deathCamY)
	setPropertyFromClass('flixel.FlxG','camera.zoom',deathCamZoom)
	set('camGame.angle', 0)
end

function onGameOver()
	if not debounce.alreadyded then
		setVar('autoTextDisabled', true)
		freezedPos = getPropertyFromClass('backend.songs.Conductor','songPosition')
		debounce.alreadyded = true
		setPropertyFromClass('flixel.FlxG','save.data.isFuckingDead',true)
		setVar('canCustomPause', false)
		set('canPause', false)
		set('canReset', false)
		set('inCutscene', true)
		set('boyfriend.stunned', true)
		-- Keep the custom state's sprites/timers running, but stop the song clock and vocals.
		runHaxeCode([[
			if (FlxG.sound.music != null) FlxG.sound.music.pause();
			if (game.vocals != null) game.vocals.pause();
			if (game.opponentVocals != null) game.opponentVocals.pause();
		]])
		if luaSpriteExists('video') then set('video.alpha', 0)
		end

		stopOpponentNotes()
		openCustomSubstate('death', false)
		set('paused', true)
	end

	return Function_Stop
end

function onPause()
	if debounce.alreadyded then return Function_Stop
	end

end

function onUpdatePost()
	if not debounce.alreadyded then return
	end

	stopOpponentNotes()
	setPropertyFromClass('backend.songs.Conductor','songPosition',freezedPos)
	lockDeathCamera()
	set('camHUD.alpha', 0)
	set('vocals.volume', 0)

	if not isExit then
		set('camOther.alpha', vol)
	else
		set('camOther.alpha', 1)
	end

end

local timer = {confirm = {time = 0, max = 2.7, fadingdelaymax = 0.7}}

function onCustomSubstateCreate(tag)
	if tag ~= 'death' then return
	end

	setPropertyFromClass('flixel.FlxG','save.data.setFollowBool',false)

	set('boyfriend.visible',false)
	createBox('gameoverblackbox',defaultBoyfriendX - 1500,defaultBoyfriendY - 1000,3000,3000,'000000',0,'camGame')
	set('gameoverblackbox.alpha', 1)

	makeAnimatedLuaSprite('dead','characters/' .. Assets.character.name,defaultBoyfriendX - 20,defaultBoyfriendY + 350)
	addAnimationByPrefix('dead','idle',Assets.character.idle,24,false)
	addAnimationByPrefix('dead','loop',Assets.character.loop,24,false)
	addAnimationByPrefix('dead','confirm',Assets.character.confirm,24,false)
	addOffset('dead','loop',0,-6)
	addOffset('dead','confirm',0,58)
	playAnim('dead','idle',true)
	add('dead',true)

	deathCamX = getGraphicMidpointX('dead')
	deathCamY = getGraphicMidpointY('dead')
	deathCamZoom = getPropertyFromClass('flixel.FlxG','camera.zoom')
	lockDeathCamera()

	createBox('gameoverfadingblackbox',defaultBoyfriendX - 1500,defaultBoyfriendY - 1000,3000,3000,'000000',0,'camGame')

	playSound(Assets.sounds.loss,1,'losssfx')
	soundCallBack('losssfx', function()
			if onLoop then return
			end
			onLoop = true
			playAnim('dead','loop',true)
			playSound(Assets.sounds.music,1,'gameoverSound')
		end)

	unsetShader()
end

function onCustomSubstateUpdate(tag, elapsed)
	if tag ~= 'death' then return
	end

	lockDeathCamera()

	if keyboardJustPressed('ENTER') or keyboardJustPressed('ESCAPE') or keyboardJustPressed('BACKSPACE') then
		if not onLoop then
			stopSound('losssfx')
			onLoop = true

			if keyboardJustPressed('ENTER') then
				stopSound('gameoverSound')
				playSound(Assets.sounds.confirm,1,'gameoverEndSound')
				playAnim('dead','confirm',true)
				isConFirm = true
				debounce.confirm = true

			else

				playAnim('dead','loop',true)
				playSound(Assets.sounds.music,1,'gameoverSound')
			end

		elseif not debounce.confirm then
			if keyboardJustPressed('ENTER') then
				stopSound('gameoverSound')
				playSound(Assets.sounds.confirm,1,'gameoverEndSound')
				playAnim('dead','confirm',true)
				isConFirm = true
				debounce.confirm = true

			elseif keyboardJustPressed('ESCAPE') or keyboardJustPressed('BACKSPACE') then
				isExit = true
				stopSound('gameoverSound')
				doTweenAlpha('gameoverExitFade','gameoverfadingblackbox',1,0.5,'quadIn')
				runTimer('goCustomFreeplay',0.55)
				debounce.confirm = true
			end
		end
	end

	if onLoop and not isConFirm and not isExit then
		if get('dead.animation.curAnim.finished') then
		playAnim('dead','loop',true)
		end

	end

	if isConFirm then
		timer.confirm.time =
			timer.confirm.time + elapsed
		if timer.confirm.time >= timer.confirm.max then
		restartSong()
		end

		if timer.confirm.time >= timer.confirm.fadingdelaymax
		and not debounce.fading then
		doTweenAlpha('fadedsdsdssdd','gameoverfadingblackbox',1,2)
		debounce.fading = true
		end

	end

	vol = lerp(vol,0,elapsed * 4)

	if not isExit then
	setPropertyFromClass('flixel.FlxG','sound.music.volume',vol)
	set('camOther.alpha',vol)

	else

	set('camOther.alpha',1)

	end

	set('camHUD.alpha',vol)
	setPropertyFromClass('backend.songs.Conductor','songPosition',freezedPos)
end

function onTimerCompleted(tag)
	if tag == 'goCustomFreeplay' then
		runHaxeCode([[
			FlxG.sound.music.stop();

			game.paused = false;

			FlxG.switchState(
				new LuaMenuState("FreeplayState")
			);
		]])
		playMusic('freakyMenu2',1,true)
	end
end

local soundtbl = {}

function soundCallBack(name, func)
	table.insert(soundtbl, {name,func})
end

function onSoundFinished(tag)
	for i, v in ipairs(soundtbl) do

		if tag == v[1] then
			v[2]()
		end
	end
end
