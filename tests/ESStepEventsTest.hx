import psych.script.ESStepEvents;

class ESStepEventsTest
{
	static function expect(value:Bool, message:String):Void
	{
		if (!value)
			throw message;
	}

	static function main():Void
	{
		var timeline = new ESStepEvents();
		timeline.beginDispatch(1560);
		expect(timeline.shouldFire(1560), "glitch starts");
		expect(!timeline.shouldFire(1567), "future event must wait");
		timeline.beginDispatch(1567);
		expect(timeline.shouldFire(1567), "camera rotation starts");
		expect(timeline.shouldFire(1567), "same-step glitch reset must also run");
		expect(!timeline.shouldFire(1560), "past event must not replay");
		timeline.beginDispatch(1567);
		expect(!timeline.shouldFire(1567), "duplicate dispatch must not replay");
		timeline.beginDispatch(1585);
		expect(timeline.shouldFire(1584), "skipped step must catch up");
		expect(timeline.shouldFire(1584), "all skipped-step handlers must run");
		timeline.beginDispatch(1500);
		expect(!timeline.shouldFire(1567), "backward seek must not run a future event");
		timeline.beginDispatch(1585);
		expect(!timeline.shouldFire(1584), "backward seek must not replay consumed events");
		var restarted = new ESStepEvents();
		restarted.beginDispatch(1567);
		expect(restarted.shouldFire(1567), "new song instance must reset the timeline");
		Sys.println("PASS: ES same-step callbacks, skipped steps, duplicate dispatches and restart");
	}
}
