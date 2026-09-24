package backend;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;

/** Patches the compile boundary without vendoring or modifying the installed OpenFL library. */
class ShaderVersionMacro
{
	public static function install():Void
	{
		if (Context.defined("desktop") && !Context.defined("display"))
		{
			Compiler.addGlobalMetadata("openfl.display.Shader", "@:build(backend.ShaderVersionMacro.build())", false, true, false);
		}
	}

	public static function build():Array<Field>
	{
		var fields = Context.getBuildFields();
		for (field in fields)
		{
			if (field.name == "__createGLShader")
			{
				switch (field.kind)
				{
					case FFun(fn):
						var original = fn.expr;
						fn.expr = macro
							{
								// Desktop builds may also use GLES (ANGLE); do not give those GLSL 110.
								@:privateAccess if (__context.__context.type == lime.graphics.RenderContextType.OPENGL)
								{
									source = backend.ShaderSource.withDesktopVersion(source);
								}
								$original;
							};
						return fields;
					default:
				}
			}
		}
		Context.error("OpenFL Shader.__createGLShader changed; review the shader version patch.", Context.currentPos());
		return fields;
	}
}
#end
