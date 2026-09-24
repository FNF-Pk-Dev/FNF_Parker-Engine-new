--OG SCRIPT BY Firek
local canCustomPause = true
local pauseLocked = false
local pauseActive = false
local pauseTrack = 'lullabyPause'

local selectionTable = {
[1] = function()
	closeSubstate();
end,
[2] = function()
	restartSong();
end,
[3] = function()
	if pauseLocked then return end

	pauseLocked = true

	closing = true
	doTweenAlpha('exitFadeIn', 'exitFade', 1, 0.5, 'quadIn')
	runTimer('goFreeplay', 0.55)
end
};

local selectionAnims = {[1] = 'resume', [2] = 'restart', [3] = 'exit'};

local objects = {'blackBG', 'box'};

local selection = 1;

local closing = false;
local opening = true;
--Values for calcs.
local ogLerpVal = 12.8;
local lerpVal = 16;
local resize = 6;
local portraitLerp = 12;

function onPause()
	if getVar('canCustomPause') then
		return Function_Stop;
	end

	return Function_Continue;
end

function onUpdate()
	if keyJustPressed('pause') then
		if not inGameOver and getVar('canCustomPause') then
			openCustomSubstate('lullabyPause', true)
		end
	end
end

function onCustomSubstateCreate(name)
	if name == 'lullabyPause' then
		pauseActive = true
		--BG.

		makeLuaSprite('exitFade', nil)
		makeGraphic('exitFade', screenWidth, screenHeight, '000000')
		setCam('exitFade', 'camOther')
		set('exitFade.alpha', 0)
		add('exitFade', true)

		makeLuaSprite('blackBG', nil);
		makeGraphic('blackBG', screenWidth, screenHeight, '000000');
		setCam('blackBG', 'camOther');
		set('blackBG.alpha', 0);
		add('blackBG');

		makeLuaSprite('left', 'pause/Pbg', -600, -95);
		scaleObject('left', 0.6, 0.6);
		add('left');
		setCam('left', 'camOther');

		--Box.
		makeLuaSprite('box', 'pause/pauseBox', 100, 205);
		addAnim('box', 'resume', 'Presume0', 24, false);
		addAnim('box', 'restart', 'Prestart0', 24, false);
		addAnim('box', 'exit', 'Pexit0', 24, false);
		add('box');
		setCam('box', 'camOther');

		if pauseTrack ~= nil then
			playSound(pauseTrack, 0, 'pauseMusic')
		end
	end
end

function onCreatePost()
	setVar('canCustomPause', true)
	-- The original package does not ship lullabyPause. Keep it when supplied by a mod,
	-- otherwise use the selected engine pause music, including the None setting.
	if not checkFileExists('sounds/lullabyPause.ogg') and not checkFileExists('music/lullabyPause.ogg') then
		local preferred = getPropertyFromClass('backend.ClientPrefs', 'pauseMusic')
		local defaults = {Breakfast = 'breakfast', ['Tea Time'] = 'tea-time', Peace = 'peace'}
		pauseTrack = defaults[preferred] or 'breakfast'
		if preferred == 'None' then pauseTrack = nil end
	end
end

function onTimerCompleted(tag)
if tag == 'goFreeplay' then

	runHaxeCode([[
		FlxG.sound.music.stop();
		game.paused = false;
		FlxG.switchState(new LuaMenuState("FreeplayState"));
	]])

	playMusic('freakyMenu2', 1, true)

end
end

--Emphasis on port.
function onCustomSubstateUpdate(name, elapsed)
	fakeElapsed = boundTo(elapsed, 0, 1);

	if name == 'lullabyPause' then
		if not closing then

			set('blackBG.alpha', math.lerp(get('blackBG.alpha'), 0.6, fakeElapsed * ogLerpVal));

			set('left.x', math.lerp(get('left.x'), -300, fakeElapsed * portraitLerp));
			set('left.alpha', math.lerp(get('left.alpha'), 1, fakeElapsed * portraitLerp));
		else
			set('blackBG.alpha', math.lerp(get('blackBG.alpha'), 0, fakeElapsed * ogLerpVal));

			set('left.x', math.lerp(get('left.x'), -4900, fakeElapsed * portraitLerp / 2.7));
			set('left.alpha', math.lerp(get('left.alpha'), 0, fakeElapsed * portraitLerp));
		end

		if opening then
			lerpVal = lerpVal * 1.05;

			if get('box.scale.x') >= 1.5 then
			lerpVal = ogLerpVal / 1.5;

			resize = 1.4;

			opening = false;
			end

			set('box.scale.x', math.lerp(get('box.scale.x'), resize, fakeElapsed * lerpVal));
			set('box.scale.y', math.lerp(get('box.scale.y'), resize, fakeElapsed * lerpVal * 2));

		else
			if closing then
			set('box.scale.x', math.lerp(get('box.scale.x'), resize, fakeElapsed * lerpVal * 2));
			set('box.scale.y', math.lerp(get('box.scale.y'), resize, fakeElapsed * lerpVal));
			else
			set('box.scale.x', math.lerp(get('box.scale.x'), resize, fakeElapsed * lerpVal));
			set('box.scale.y', math.lerp(get('box.scale.y'), resize, fakeElapsed * lerpVal * 2));

			end

			if get('box.scale.x') <= resize + 0.0125 then
			set('box.scale.x', resize);
			end

			if get('box.scale.y') <= resize + 0.0125 then
			set('box.scale.y', resize);
			end

			if closing then
			lerpVal = lerpVal * 1.05;
			resize = 0;

			if get('box.scale.x') <= 0.5 then
				closeCustomSubstate();

				for i = 1, #objects do
					remove(objects[i], false);
				end
			end
			end
		end

		if getSoundVolume('pauseMusic') < 0.5 then
			setSoundVolume('pauseMusic', getSoundVolume('pauseMusic') + 0.025 * fakeElapsed);
		end

		--Box.
		playAnim('box', selectionAnims[selection], true);

if keyJustPressed('accept') and not pauseLocked then
	selectionTable[selection]();
	playSound('confirmMenu')

elseif keyJustPressed('up') then
	selection = selection - 1;
	playSound('scrollMenu2')

elseif keyJustPressed('down') then
	selection = selection + 1;
	playSound('scrollMenu2')
end

		if selection > 3 then
			selection = 1;
		elseif selection < 1 then
			selection = 3;
		end
	end
end

function onCustomSubstateDestroy(name)
	if name == 'lullabyPause' then
		pauseActive = false
		pauseLocked = false

		closing = false;

		opening = true;

		ogLerpVal = 12.8;
		lerpVal = 16;
		resize = 6;

		stopSound('pauseMusic');
	end
end

function onSoundFinished(tag)
	if tag == 'pauseMusic' and pauseActive and pauseTrack ~= nil then
		playSound(pauseTrack, 1, 'pauseMusic')
	end
end

function closeSubstate() --God damn it.
	closing = true;
end

function math.lerp(a,b,t)
	return(b-a) * t + a;
end

function boundTo(value, min, max)
	return math.max(min, math.min(max, value));
end
