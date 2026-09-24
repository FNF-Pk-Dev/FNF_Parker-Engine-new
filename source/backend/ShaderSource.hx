package backend;

/** Keeps unversioned desktop shaders on their existing implicit GLSL 1.10 dialect. */
class ShaderSource
{
	public static function withDesktopVersion(source:String):String
	{
		if (source == null)
		{
			return source;
		}

		// A version mentioned only in a comment is not a version directive.
		var code = ~/\/\*[\s\S]*?\*\/|\/\/[^\r\n]*/g.replace(source, "");
		if (~/^[ \t]*#[ \t]*version\b/m.match(code))
		{
			return source;
		}

		// Keep compiler diagnostics relative to the original shader source.
		return "#version 110\n#line 1\n" + source;
	}
}
