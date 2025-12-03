# Friday Night Funkin' - Parker Engine (WIP)

Parker Engine from Psych Engine

The original production.
This engine is much more
extensible than the original engine.

## Where is the download?
Now it is an unknown state, so it can only be downloaded now Actions inside.
Of course, in the Actions Update.
(Although imperfect, it is extremely unstable.)

So let's wait for the release honestly.(Unless you're still here Actions It left me speechless)

## Installation:
You must have [the most up-to-date version of Haxe](https://haxe.org/download/), seriously, stop using 4.2.0, it misses some stuff.

open up a Command Prompt/PowerShell or Terminal, type `haxelib install hmm`

after it finishes, simply type `haxelib run hmm install` in order to install all the needed libraries for *Parker Engine!*

## Customization:

if you wish to disable things like *Lua Scripts* or *Video Cutscenes*, you can read over to `Project.xml`

inside `Project.xml`, you will find several variables to customize Psych Engine to your liking

to start you off, disabling Videos should be simple, simply Delete the line `"VIDEOS_ALLOWED"` or comment it out by wrapping the line in XML-like comments, like this `<!-- YOUR_LINE_HERE -->`

same goes for *Lua Scripts*, comment out or delete the line with `LUA_ALLOWED`, this and other customization options are all available within the `Project.xml` file

6. Open project in command line `cd (path to fnf source)`
And run command `lime build android -final`
Apk will be generated in this path (path to source)\export\release\android\bin\app\build\outputs\apk\debug
## Credits
* Ajwwk - HotFix Psych Engine Bug and Paker Engine Owner

## particular thanks
* luuan - Hscript
* qqqeb(tchcfhvgd) - Video Mp4 (hxCodec)
`Now it has been replaced by hxvlc`
* asdfghjkl - ModChart Lua code
## Psych Engine Original Credits:
* Shadow Mario - Programmer
* RiverOaken - Artist
* Yoshubs - Assistant Programmer

* bbpanzu - Ex-Programmer
* Yoshubs - New Input System
* SqirraRNG - Crash Handler and Base code for Chart Editor's Waveform
* KadeDev - Fixed some cool stuff on Chart Editor and other PRs
* iFlicky - Composer of Psync and Tea Time, also made the Dialogue Sounds
* PolybiusProxy - .MP4 Video Loader Library (hxCodec)
* Keoiki - Note Splash Animations
* Smokey - Sprite Atlas Support
* Nebula the Zorua - LUA JIT Fork and some Lua reworks
_____________________________________
