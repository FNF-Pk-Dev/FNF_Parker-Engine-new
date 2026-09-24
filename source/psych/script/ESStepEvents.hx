package psych.script;

/** All handlers for a due step may run in one dispatch, but never replay on later dispatches. */
class ESStepEvents
{
	var currentStep:Int = -1;
	var dispatchId:Int = 0;
	var firedPasses:Map<Int, Int> = [];

	public function new()
	{
	}

	public function beginDispatch(step:Int):Void
	{
		currentStep = step;
		dispatchId++;
	}

	public function shouldFire(step:Int):Bool
	{
		if (step > currentStep)
			return false;
		var previous = firedPasses.get(step);
		if (previous != null && previous != dispatchId)
			return false;
		firedPasses.set(step, dispatchId);
		return true;
	}
}
