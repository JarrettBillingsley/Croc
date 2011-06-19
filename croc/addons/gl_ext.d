module croc.addons.gl_ext;

version(CrocAllAddons)
	version = CrocGlAddon;

version(CrocGlAddon)
{

import derelict.opengl.extension.ext.bindable_uniform;
import derelict.opengl.gl;
import derelict.opengl.glext;
import derelict.opengl.glu;
import derelict.util.exception;

alias derelict.opengl.extension.nv.vertex_program2_option.GL_MAX_PROGRAM_EXEC_INSTRUCTIONS_NV GL_MAX_PROGRAM_EXEC_INSTRUCTIONS_NV;
alias derelict.opengl.extension.nv.vertex_program2_option.GL_MAX_PROGRAM_CALL_DEPTH_NV GL_MAX_PROGRAM_CALL_DEPTH_NV;

import croc.api;
import croc.addons.gl_wrap;

void loadExtensions(CrocThread* t)
{
	newNamespace(t, "ext");
		loadExtensionFlags(t);
	newGlobal(t, "ext");

	// ARB
	if(ARBColorBufferFloat.isEnabled)
	{
		register(t, &wrapGL!(glClampColorARB), "glClampColorARB");

		pushInt(t, GL_RGBA_FLOAT_MODE_ARB); newGlobal(t, "GL_RGBA_FLOAT_MODE_ARB");
		pushInt(t, GL_CLAMP_VERTEX_COLOR_ARB); newGlobal(t, "GL_CLAMP_VERTEX_COLOR_ARB");
		pushInt(t, GL_CLAMP_FRAGMENT_COLOR_ARB); newGlobal(t, "GL_CLAMP_FRAGMENT_COLOR_ARB");
		pushInt(t, GL_CLAMP_READ_COLOR_ARB); newGlobal(t, "GL_CLAMP_READ_COLOR_ARB");
		pushInt(t, GL_FIXED_ONLY_COLOR_ARB); newGlobal(t, "GL_FIXED_ONLY_COLOR_ARB");
	}

	if(ARBDepthTexture.isEnabled)
	{
		pushInt(t, GL_DEPTH_COMPONENT16_ARB); newGlobal(t, "GL_DEPTH_COMPONENT16_ARB");
		pushInt(t, GL_DEPTH_COMPONENT24_ARB); newGlobal(t, "GL_DEPTH_COMPONENT24_ARB");
		pushInt(t, GL_DEPTH_COMPONENT32_ARB); newGlobal(t, "GL_DEPTH_COMPONENT32_ARB");
		pushInt(t, GL_TEXTURE_DEPTH_SIZE_ARB); newGlobal(t, "GL_TEXTURE_DEPTH_SIZE_ARB");
		pushInt(t, GL_DEPTH_TEXTURE_MODE_ARB); newGlobal(t, "GL_DEPTH_TEXTURE_MODE_ARB");
	}

	if(ARBDrawBuffers.isEnabled)
	{
		register(t, &wrapGL!(glDrawBuffersARB), "glDrawBuffersARB");

		pushInt(t, GL_MAX_DRAW_BUFFERS_ARB); newGlobal(t, "GL_MAX_DRAW_BUFFERS_ARB");
		pushInt(t, GL_DRAW_BUFFER0_ARB); newGlobal(t, "GL_DRAW_BUFFER0_ARB");
		pushInt(t, GL_DRAW_BUFFER1_ARB); newGlobal(t, "GL_DRAW_BUFFER1_ARB");
		pushInt(t, GL_DRAW_BUFFER2_ARB); newGlobal(t, "GL_DRAW_BUFFER2_ARB");
		pushInt(t, GL_DRAW_BUFFER3_ARB); newGlobal(t, "GL_DRAW_BUFFER3_ARB");
		pushInt(t, GL_DRAW_BUFFER4_ARB); newGlobal(t, "GL_DRAW_BUFFER4_ARB");
		pushInt(t, GL_DRAW_BUFFER5_ARB); newGlobal(t, "GL_DRAW_BUFFER5_ARB");
		pushInt(t, GL_DRAW_BUFFER6_ARB); newGlobal(t, "GL_DRAW_BUFFER6_ARB");
		pushInt(t, GL_DRAW_BUFFER7_ARB); newGlobal(t, "GL_DRAW_BUFFER7_ARB");
		pushInt(t, GL_DRAW_BUFFER8_ARB); newGlobal(t, "GL_DRAW_BUFFER8_ARB");
		pushInt(t, GL_DRAW_BUFFER9_ARB); newGlobal(t, "GL_DRAW_BUFFER9_ARB");
		pushInt(t, GL_DRAW_BUFFER10_ARB); newGlobal(t, "GL_DRAW_BUFFER10_ARB");
		pushInt(t, GL_DRAW_BUFFER11_ARB); newGlobal(t, "GL_DRAW_BUFFER11_ARB");
		pushInt(t, GL_DRAW_BUFFER12_ARB); newGlobal(t, "GL_DRAW_BUFFER12_ARB");
		pushInt(t, GL_DRAW_BUFFER13_ARB); newGlobal(t, "GL_DRAW_BUFFER13_ARB");
		pushInt(t, GL_DRAW_BUFFER14_ARB); newGlobal(t, "GL_DRAW_BUFFER14_ARB");
		pushInt(t, GL_DRAW_BUFFER15_ARB); newGlobal(t, "GL_DRAW_BUFFER15_ARB");
	}

	if(ARBFragmentProgram.isEnabled)
	{
		pushInt(t, GL_FRAGMENT_PROGRAM_ARB); newGlobal(t, "GL_FRAGMENT_PROGRAM_ARB");
		pushInt(t, GL_PROGRAM_ALU_INSTRUCTIONS_ARB); newGlobal(t, "GL_PROGRAM_ALU_INSTRUCTIONS_ARB");
		pushInt(t, GL_PROGRAM_TEX_INSTRUCTIONS_ARB); newGlobal(t, "GL_PROGRAM_TEX_INSTRUCTIONS_ARB");
		pushInt(t, GL_PROGRAM_TEX_INDIRECTIONS_ARB); newGlobal(t, "GL_PROGRAM_TEX_INDIRECTIONS_ARB");
		pushInt(t, GL_PROGRAM_NATIVE_ALU_INSTRUCTIONS_ARB); newGlobal(t, "GL_PROGRAM_NATIVE_ALU_INSTRUCTIONS_ARB");
		pushInt(t, GL_PROGRAM_NATIVE_TEX_INSTRUCTIONS_ARB); newGlobal(t, "GL_PROGRAM_NATIVE_TEX_INSTRUCTIONS_ARB");
		pushInt(t, GL_PROGRAM_NATIVE_TEX_INDIRECTIONS_ARB); newGlobal(t, "GL_PROGRAM_NATIVE_TEX_INDIRECTIONS_ARB");
		pushInt(t, GL_MAX_PROGRAM_ALU_INSTRUCTIONS_ARB); newGlobal(t, "GL_MAX_PROGRAM_ALU_INSTRUCTIONS_ARB");
		pushInt(t, GL_MAX_PROGRAM_TEX_INSTRUCTIONS_ARB); newGlobal(t, "GL_MAX_PROGRAM_TEX_INSTRUCTIONS_ARB");
		pushInt(t, GL_MAX_PROGRAM_TEX_INDIRECTIONS_ARB); newGlobal(t, "GL_MAX_PROGRAM_TEX_INDIRECTIONS_ARB");
		pushInt(t, GL_MAX_PROGRAM_NATIVE_ALU_INSTRUCTIONS_ARB); newGlobal(t, "GL_MAX_PROGRAM_NATIVE_ALU_INSTRUCTIONS_ARB");
		pushInt(t, GL_MAX_PROGRAM_NATIVE_TEX_INSTRUCTIONS_ARB); newGlobal(t, "GL_MAX_PROGRAM_NATIVE_TEX_INSTRUCTIONS_ARB");
		pushInt(t, GL_MAX_PROGRAM_NATIVE_TEX_INDIRECTIONS_ARB); newGlobal(t, "GL_MAX_PROGRAM_NATIVE_TEX_INDIRECTIONS_ARB");
		pushInt(t, GL_MAX_TEXTURE_COORDS_ARB); newGlobal(t, "GL_MAX_TEXTURE_COORDS_ARB");
		pushInt(t, GL_MAX_TEXTURE_IMAGE_UNITS_ARB); newGlobal(t, "GL_MAX_TEXTURE_IMAGE_UNITS_ARB");
	}

	if(ARBFragmentShader.isEnabled)
	{
		pushInt(t, GL_FRAGMENT_SHADER_ARB); newGlobal(t, "GL_FRAGMENT_SHADER_ARB");
		pushInt(t, GL_MAX_FRAGMENT_UNIFORM_COMPONENTS_ARB); newGlobal(t, "GL_MAX_FRAGMENT_UNIFORM_COMPONENTS_ARB");
		pushInt(t, GL_FRAGMENT_SHADER_DERIVATIVE_HINT_ARB); newGlobal(t, "GL_FRAGMENT_SHADER_DERIVATIVE_HINT_ARB");
	}

	if(ARBHalfFloatPixel.isEnabled)
	{
		pushInt(t, GL_HALF_FLOAT_ARB); newGlobal(t, "GL_HALF_FLOAT_ARB");
	}

	if(ARBMatrixPalette.isEnabled)
	{
		register(t, &wrapGL!(glCurrentPaletteMatrixARB), "glCurrentPaletteMatrixARB");
		register(t, &wrapGL!(glMatrixIndexubvARB), "glMatrixIndexubvARB");
		register(t, &wrapGL!(glMatrixIndexusvARB), "glMatrixIndexusvARB");
		register(t, &wrapGL!(glMatrixIndexuivARB), "glMatrixIndexuivARB");
		register(t, &wrapGL!(glMatrixIndexPointerARB), "glMatrixIndexPointerARB");

		pushInt(t, GL_MATRIX_PALETTE_ARB); newGlobal(t, "GL_MATRIX_PALETTE_ARB");
		pushInt(t, GL_MAX_MATRIX_PALETTE_STACK_DEPTH_ARB); newGlobal(t, "GL_MAX_MATRIX_PALETTE_STACK_DEPTH_ARB");
		pushInt(t, GL_MAX_PALETTE_MATRICES_ARB); newGlobal(t, "GL_MAX_PALETTE_MATRICES_ARB");
		pushInt(t, GL_CURRENT_PALETTE_MATRIX_ARB); newGlobal(t, "GL_CURRENT_PALETTE_MATRIX_ARB");
		pushInt(t, GL_MATRIX_INDEX_ARRAY_ARB); newGlobal(t, "GL_MATRIX_INDEX_ARRAY_ARB");
		pushInt(t, GL_CURRENT_MATRIX_INDEX_ARB); newGlobal(t, "GL_CURRENT_MATRIX_INDEX_ARB");
		pushInt(t, GL_MATRIX_INDEX_ARRAY_SIZE_ARB); newGlobal(t, "GL_MATRIX_INDEX_ARRAY_SIZE_ARB");
		pushInt(t, GL_MATRIX_INDEX_ARRAY_TYPE_ARB); newGlobal(t, "GL_MATRIX_INDEX_ARRAY_TYPE_ARB");
		pushInt(t, GL_MATRIX_INDEX_ARRAY_STRIDE_ARB); newGlobal(t, "GL_MATRIX_INDEX_ARRAY_STRIDE_ARB");
		pushInt(t, GL_MATRIX_INDEX_ARRAY_POINTER_ARB); newGlobal(t, "GL_MATRIX_INDEX_ARRAY_POINTER_ARB");
	}

	if(ARBMultisample.isEnabled)
	{
		register(t, &wrapGL!(glSampleCoverageARB), "glSampleCoverageARB");

		pushInt(t, GL_MULTISAMPLE_ARB); newGlobal(t, "GL_MULTISAMPLE_ARB");
		pushInt(t, GL_SAMPLE_ALPHA_TO_COVERAGE_ARB); newGlobal(t, "GL_SAMPLE_ALPHA_TO_COVERAGE_ARB");
		pushInt(t, GL_SAMPLE_ALPHA_TO_ONE_ARB); newGlobal(t, "GL_SAMPLE_ALPHA_TO_ONE_ARB");
		pushInt(t, GL_SAMPLE_COVERAGE_ARB); newGlobal(t, "GL_SAMPLE_COVERAGE_ARB");
		pushInt(t, GL_SAMPLE_BUFFERS_ARB); newGlobal(t, "GL_SAMPLE_BUFFERS_ARB");
		pushInt(t, GL_SAMPLES_ARB); newGlobal(t, "GL_SAMPLES_ARB");
		pushInt(t, GL_SAMPLE_COVERAGE_VALUE_ARB); newGlobal(t, "GL_SAMPLE_COVERAGE_VALUE_ARB");
		pushInt(t, GL_SAMPLE_COVERAGE_INVERT_ARB); newGlobal(t, "GL_SAMPLE_COVERAGE_INVERT_ARB");
		pushInt(t, GL_MULTISAMPLE_BIT_ARB); newGlobal(t, "GL_MULTISAMPLE_BIT_ARB");
	}

	if(ARBMultitexture.isEnabled)
	{
		register(t, &wrapGL!(glActiveTextureARB), "glActiveTextureARB");
		register(t, &wrapGL!(glClientActiveTextureARB), "glClientActiveTextureARB");
		register(t, &wrapGL!(glMultiTexCoord1dARB), "glMultiTexCoord1dARB");
		register(t, &wrapGL!(glMultiTexCoord1dvARB), "glMultiTexCoord1dvARB");
		register(t, &wrapGL!(glMultiTexCoord1fARB), "glMultiTexCoord1fARB");
		register(t, &wrapGL!(glMultiTexCoord1fvARB), "glMultiTexCoord1fvARB");
		register(t, &wrapGL!(glMultiTexCoord1iARB), "glMultiTexCoord1iARB");
		register(t, &wrapGL!(glMultiTexCoord1ivARB), "glMultiTexCoord1ivARB");
		register(t, &wrapGL!(glMultiTexCoord1sARB), "glMultiTexCoord1sARB");
		register(t, &wrapGL!(glMultiTexCoord1svARB), "glMultiTexCoord1svARB");
		register(t, &wrapGL!(glMultiTexCoord2dARB), "glMultiTexCoord2dARB");
		register(t, &wrapGL!(glMultiTexCoord2dvARB), "glMultiTexCoord2dvARB");
		register(t, &wrapGL!(glMultiTexCoord2fARB), "glMultiTexCoord2fARB");
		register(t, &wrapGL!(glMultiTexCoord2fvARB), "glMultiTexCoord2fvARB");
		register(t, &wrapGL!(glMultiTexCoord2iARB), "glMultiTexCoord2iARB");
		register(t, &wrapGL!(glMultiTexCoord2ivARB), "glMultiTexCoord2ivARB");
		register(t, &wrapGL!(glMultiTexCoord2sARB), "glMultiTexCoord2sARB");
		register(t, &wrapGL!(glMultiTexCoord2svARB), "glMultiTexCoord2svARB");
		register(t, &wrapGL!(glMultiTexCoord3dARB), "glMultiTexCoord3dARB");
		register(t, &wrapGL!(glMultiTexCoord3dvARB), "glMultiTexCoord3dvARB");
		register(t, &wrapGL!(glMultiTexCoord3fARB), "glMultiTexCoord3fARB");
		register(t, &wrapGL!(glMultiTexCoord3fvARB), "glMultiTexCoord3fvARB");
		register(t, &wrapGL!(glMultiTexCoord3iARB), "glMultiTexCoord3iARB");
		register(t, &wrapGL!(glMultiTexCoord3ivARB), "glMultiTexCoord3ivARB");
		register(t, &wrapGL!(glMultiTexCoord3sARB), "glMultiTexCoord3sARB");
		register(t, &wrapGL!(glMultiTexCoord3svARB), "glMultiTexCoord3svARB");
		register(t, &wrapGL!(glMultiTexCoord4dARB), "glMultiTexCoord4dARB");
		register(t, &wrapGL!(glMultiTexCoord4dvARB), "glMultiTexCoord4dvARB");
		register(t, &wrapGL!(glMultiTexCoord4fARB), "glMultiTexCoord4fARB");
		register(t, &wrapGL!(glMultiTexCoord4fvARB), "glMultiTexCoord4fvARB");
		register(t, &wrapGL!(glMultiTexCoord4iARB), "glMultiTexCoord4iARB");
		register(t, &wrapGL!(glMultiTexCoord4ivARB), "glMultiTexCoord4ivARB");
		register(t, &wrapGL!(glMultiTexCoord4sARB), "glMultiTexCoord4sARB");
		register(t, &wrapGL!(glMultiTexCoord4svARB), "glMultiTexCoord4svARB");

		pushInt(t, GL_TEXTURE0_ARB); newGlobal(t, "GL_TEXTURE0_ARB");
		pushInt(t, GL_TEXTURE1_ARB); newGlobal(t, "GL_TEXTURE1_ARB");
		pushInt(t, GL_TEXTURE2_ARB); newGlobal(t, "GL_TEXTURE2_ARB");
		pushInt(t, GL_TEXTURE3_ARB); newGlobal(t, "GL_TEXTURE3_ARB");
		pushInt(t, GL_TEXTURE4_ARB); newGlobal(t, "GL_TEXTURE4_ARB");
		pushInt(t, GL_TEXTURE5_ARB); newGlobal(t, "GL_TEXTURE5_ARB");
		pushInt(t, GL_TEXTURE6_ARB); newGlobal(t, "GL_TEXTURE6_ARB");
		pushInt(t, GL_TEXTURE7_ARB); newGlobal(t, "GL_TEXTURE7_ARB");
		pushInt(t, GL_TEXTURE8_ARB); newGlobal(t, "GL_TEXTURE8_ARB");
		pushInt(t, GL_TEXTURE9_ARB); newGlobal(t, "GL_TEXTURE9_ARB");
		pushInt(t, GL_TEXTURE10_ARB); newGlobal(t, "GL_TEXTURE10_ARB");
		pushInt(t, GL_TEXTURE11_ARB); newGlobal(t, "GL_TEXTURE11_ARB");
		pushInt(t, GL_TEXTURE12_ARB); newGlobal(t, "GL_TEXTURE12_ARB");
		pushInt(t, GL_TEXTURE13_ARB); newGlobal(t, "GL_TEXTURE13_ARB");
		pushInt(t, GL_TEXTURE14_ARB); newGlobal(t, "GL_TEXTURE14_ARB");
		pushInt(t, GL_TEXTURE15_ARB); newGlobal(t, "GL_TEXTURE15_ARB");
		pushInt(t, GL_TEXTURE16_ARB); newGlobal(t, "GL_TEXTURE16_ARB");
		pushInt(t, GL_TEXTURE17_ARB); newGlobal(t, "GL_TEXTURE17_ARB");
		pushInt(t, GL_TEXTURE18_ARB); newGlobal(t, "GL_TEXTURE18_ARB");
		pushInt(t, GL_TEXTURE19_ARB); newGlobal(t, "GL_TEXTURE19_ARB");
		pushInt(t, GL_TEXTURE20_ARB); newGlobal(t, "GL_TEXTURE20_ARB");
		pushInt(t, GL_TEXTURE21_ARB); newGlobal(t, "GL_TEXTURE21_ARB");
		pushInt(t, GL_TEXTURE22_ARB); newGlobal(t, "GL_TEXTURE22_ARB");
		pushInt(t, GL_TEXTURE23_ARB); newGlobal(t, "GL_TEXTURE23_ARB");
		pushInt(t, GL_TEXTURE24_ARB); newGlobal(t, "GL_TEXTURE24_ARB");
		pushInt(t, GL_TEXTURE25_ARB); newGlobal(t, "GL_TEXTURE25_ARB");
		pushInt(t, GL_TEXTURE26_ARB); newGlobal(t, "GL_TEXTURE26_ARB");
		pushInt(t, GL_TEXTURE27_ARB); newGlobal(t, "GL_TEXTURE27_ARB");
		pushInt(t, GL_TEXTURE28_ARB); newGlobal(t, "GL_TEXTURE28_ARB");
		pushInt(t, GL_TEXTURE29_ARB); newGlobal(t, "GL_TEXTURE29_ARB");
		pushInt(t, GL_TEXTURE30_ARB); newGlobal(t, "GL_TEXTURE30_ARB");
		pushInt(t, GL_TEXTURE31_ARB); newGlobal(t, "GL_TEXTURE31_ARB");
		pushInt(t, GL_ACTIVE_TEXTURE_ARB); newGlobal(t, "GL_ACTIVE_TEXTURE_ARB");
		pushInt(t, GL_CLIENT_ACTIVE_TEXTURE_ARB); newGlobal(t, "GL_CLIENT_ACTIVE_TEXTURE_ARB");
		pushInt(t, GL_MAX_TEXTURE_UNITS_ARB); newGlobal(t, "GL_MAX_TEXTURE_UNITS_ARB");
	}

	if(ARBOcclusionQuery.isEnabled)
	{
		register(t, &wrapGL!(glGenQueriesARB), "glGenQueriesARB");
		register(t, &wrapGL!(glDeleteQueriesARB), "glDeleteQueriesARB");
		register(t, &wrapGL!(glIsQueryARB), "glIsQueryARB");
		register(t, &wrapGL!(glBeginQueryARB), "glBeginQueryARB");
		register(t, &wrapGL!(glEndQueryARB), "glEndQueryARB");
		register(t, &wrapGL!(glGetQueryivARB), "glGetQueryivARB");
		register(t, &wrapGL!(glGetQueryObjectivARB), "glGetQueryObjectivARB");
		register(t, &wrapGL!(glGetQueryObjectuivARB), "glGetQueryObjectuivARB");

		pushInt(t, GL_QUERY_COUNTER_BITS_ARB); newGlobal(t, "GL_QUERY_COUNTER_BITS_ARB");
		pushInt(t, GL_CURRENT_QUERY_ARB); newGlobal(t, "GL_CURRENT_QUERY_ARB");
		pushInt(t, GL_QUERY_RESULT_ARB); newGlobal(t, "GL_QUERY_RESULT_ARB");
		pushInt(t, GL_QUERY_RESULT_AVAILABLE_ARB); newGlobal(t, "GL_QUERY_RESULT_AVAILABLE_ARB");
		pushInt(t, GL_SAMPLES_PASSED_ARB); newGlobal(t, "GL_SAMPLES_PASSED_ARB");
	}

	if(ARBPixelBufferObject.isEnabled)
	{
		pushInt(t, GL_PIXEL_PACK_BUFFER_ARB); newGlobal(t, "GL_PIXEL_PACK_BUFFER_ARB");
		pushInt(t, GL_PIXEL_UNPACK_BUFFER_ARB); newGlobal(t, "GL_PIXEL_UNPACK_BUFFER_ARB");
		pushInt(t, GL_PIXEL_PACK_BUFFER_BINDING_ARB); newGlobal(t, "GL_PIXEL_PACK_BUFFER_BINDING_ARB");
		pushInt(t, GL_PIXEL_UNPACK_BUFFER_BINDING_ARB); newGlobal(t, "GL_PIXEL_UNPACK_BUFFER_BINDING_ARB");
	}

	if(ARBPointParameters.isEnabled)
	{
		register(t, &wrapGL!(glPointParameterfARB), "glPointParameterfARB");
		register(t, &wrapGL!(glPointParameterfvARB), "glPointParameterfvARB");

		pushInt(t, GL_POINT_SIZE_MIN_ARB); newGlobal(t, "GL_POINT_SIZE_MIN_ARB");
		pushInt(t, GL_POINT_SIZE_MAX_ARB); newGlobal(t, "GL_POINT_SIZE_MAX_ARB");
		pushInt(t, GL_POINT_FADE_THRESHOLD_SIZE_ARB); newGlobal(t, "GL_POINT_FADE_THRESHOLD_SIZE_ARB");
		pushInt(t, GL_POINT_DISTANCE_ATTENUATION_ARB); newGlobal(t, "GL_POINT_DISTANCE_ATTENUATION_ARB");
	}

	if(ARBPointSprite.isEnabled)
	{
		pushInt(t, GL_POINT_SPRITE_ARB); newGlobal(t, "GL_POINT_SPRITE_ARB");
		pushInt(t, GL_COORD_REPLACE_ARB); newGlobal(t, "GL_COORD_REPLACE_ARB");
	}

	if(ARBShaderObjects.isEnabled)
	{
		static uword crocglShaderSourceARB(CrocThread* t)
		{
			auto shader = cast(GLuint)checkIntParam(t, 1);
			auto src = checkStringParam(t, 2);
	
			GLchar* str = src.ptr;
			GLint len = src.length;
	
			glShaderSourceARB(shader, 1, &str, &len);
			
			return 0;
		}

		register(t, &wrapGL!(glDeleteObjectARB), "glDeleteObjectARB");
		register(t, &wrapGL!(glGetHandleARB), "glGetHandleARB");
		register(t, &wrapGL!(glDetachObjectARB), "glDetachObjectARB");
		register(t, &wrapGL!(glCreateShaderObjectARB), "glCreateShaderObjectARB");
		register(t, &crocglShaderSourceARB, "glShaderSourceARB");
		register(t, &wrapGL!(glCompileShaderARB), "glCompileShaderARB");
		register(t, &wrapGL!(glCreateProgramObjectARB), "glCreateProgramObjectARB");
		register(t, &wrapGL!(glAttachObjectARB), "glAttachObjectARB");
		register(t, &wrapGL!(glLinkProgramARB), "glLinkProgramARB");
		register(t, &wrapGL!(glUseProgramObjectARB), "glUseProgramObjectARB");
		register(t, &wrapGL!(glValidateProgramARB), "glValidateProgramARB");
		register(t, &wrapGL!(glUniform1fARB), "glUniform1fARB");
		register(t, &wrapGL!(glUniform2fARB), "glUniform2fARB");
		register(t, &wrapGL!(glUniform3fARB), "glUniform3fARB");
		register(t, &wrapGL!(glUniform4fARB), "glUniform4fARB");
		register(t, &wrapGL!(glUniform1iARB), "glUniform1iARB");
		register(t, &wrapGL!(glUniform2iARB), "glUniform2iARB");
		register(t, &wrapGL!(glUniform3iARB), "glUniform3iARB");
		register(t, &wrapGL!(glUniform4iARB), "glUniform4iARB");
		register(t, &wrapGL!(glUniform1fvARB), "glUniform1fvARB");
		register(t, &wrapGL!(glUniform2fvARB), "glUniform2fvARB");
		register(t, &wrapGL!(glUniform3fvARB), "glUniform3fvARB");
		register(t, &wrapGL!(glUniform4fvARB), "glUniform4fvARB");
		register(t, &wrapGL!(glUniform1ivARB), "glUniform1ivARB");
		register(t, &wrapGL!(glUniform2ivARB), "glUniform2ivARB");
		register(t, &wrapGL!(glUniform3ivARB), "glUniform3ivARB");
		register(t, &wrapGL!(glUniform4ivARB), "glUniform4ivARB");
		register(t, &wrapGL!(glUniformMatrix2fvARB), "glUniformMatrix2fvARB");
		register(t, &wrapGL!(glUniformMatrix3fvARB), "glUniformMatrix3fvARB");
		register(t, &wrapGL!(glUniformMatrix4fvARB), "glUniformMatrix4fvARB");
		register(t, &wrapGL!(glGetObjectParameterfvARB), "glGetObjectParameterfvARB");
		register(t, &wrapGL!(glGetObjectParameterivARB), "glGetObjectParameterivARB");
		register(t, &wrapGL!(glGetInfoLogARB), "glGetInfoLogARB");
		register(t, &wrapGL!(glGetAttachedObjectsARB), "glGetAttachedObjectsARB");
		register(t, &wrapGL!(glGetUniformLocationARB), "glGetUniformLocationARB");
		register(t, &wrapGL!(glGetActiveUniformARB), "glGetActiveUniformARB");
		register(t, &wrapGL!(glGetUniformfvARB), "glGetUniformfvARB");
		register(t, &wrapGL!(glGetUniformivARB), "glGetUniformivARB");
		register(t, &wrapGL!(glGetShaderSourceARB), "glGetShaderSourceARB");

		pushInt(t, GL_PROGRAM_OBJECT_ARB); newGlobal(t, "GL_PROGRAM_OBJECT_ARB");
		pushInt(t, GL_SHADER_OBJECT_ARB); newGlobal(t, "GL_SHADER_OBJECT_ARB");
		pushInt(t, GL_OBJECT_TYPE_ARB); newGlobal(t, "GL_OBJECT_TYPE_ARB");
		pushInt(t, GL_OBJECT_SUBTYPE_ARB); newGlobal(t, "GL_OBJECT_SUBTYPE_ARB");
		pushInt(t, GL_FLOAT_VEC2_ARB); newGlobal(t, "GL_FLOAT_VEC2_ARB");
		pushInt(t, GL_FLOAT_VEC3_ARB); newGlobal(t, "GL_FLOAT_VEC3_ARB");
		pushInt(t, GL_FLOAT_VEC4_ARB); newGlobal(t, "GL_FLOAT_VEC4_ARB");
		pushInt(t, GL_INT_VEC2_ARB); newGlobal(t, "GL_INT_VEC2_ARB");
		pushInt(t, GL_INT_VEC3_ARB); newGlobal(t, "GL_INT_VEC3_ARB");
		pushInt(t, GL_INT_VEC4_ARB); newGlobal(t, "GL_INT_VEC4_ARB");
		pushInt(t, GL_BOOL_ARB); newGlobal(t, "GL_BOOL_ARB");
		pushInt(t, GL_BOOL_VEC2_ARB); newGlobal(t, "GL_BOOL_VEC2_ARB");
		pushInt(t, GL_BOOL_VEC3_ARB); newGlobal(t, "GL_BOOL_VEC3_ARB");
		pushInt(t, GL_BOOL_VEC4_ARB); newGlobal(t, "GL_BOOL_VEC4_ARB");
		pushInt(t, GL_FLOAT_MAT2_ARB); newGlobal(t, "GL_FLOAT_MAT2_ARB");
		pushInt(t, GL_FLOAT_MAT3_ARB); newGlobal(t, "GL_FLOAT_MAT3_ARB");
		pushInt(t, GL_FLOAT_MAT4_ARB); newGlobal(t, "GL_FLOAT_MAT4_ARB");
		pushInt(t, GL_SAMPLER_1D_ARB); newGlobal(t, "GL_SAMPLER_1D_ARB");
		pushInt(t, GL_SAMPLER_2D_ARB); newGlobal(t, "GL_SAMPLER_2D_ARB");
		pushInt(t, GL_SAMPLER_3D_ARB); newGlobal(t, "GL_SAMPLER_3D_ARB");
		pushInt(t, GL_SAMPLER_CUBE_ARB); newGlobal(t, "GL_SAMPLER_CUBE_ARB");
		pushInt(t, GL_SAMPLER_1D_SHADOW_ARB); newGlobal(t, "GL_SAMPLER_1D_SHADOW_ARB");
		pushInt(t, GL_SAMPLER_2D_SHADOW_ARB); newGlobal(t, "GL_SAMPLER_2D_SHADOW_ARB");
		pushInt(t, GL_SAMPLER_2D_RECT_ARB); newGlobal(t, "GL_SAMPLER_2D_RECT_ARB");
		pushInt(t, GL_SAMPLER_2D_RECT_SHADOW_ARB); newGlobal(t, "GL_SAMPLER_2D_RECT_SHADOW_ARB");
		pushInt(t, GL_OBJECT_DELETE_STATUS_ARB); newGlobal(t, "GL_OBJECT_DELETE_STATUS_ARB");
		pushInt(t, GL_OBJECT_COMPILE_STATUS_ARB); newGlobal(t, "GL_OBJECT_COMPILE_STATUS_ARB");
		pushInt(t, GL_OBJECT_LINK_STATUS_ARB); newGlobal(t, "GL_OBJECT_LINK_STATUS_ARB");
		pushInt(t, GL_OBJECT_VALIDATE_STATUS_ARB); newGlobal(t, "GL_OBJECT_VALIDATE_STATUS_ARB");
		pushInt(t, GL_OBJECT_INFO_LOG_LENGTH_ARB); newGlobal(t, "GL_OBJECT_INFO_LOG_LENGTH_ARB");
		pushInt(t, GL_OBJECT_ATTACHED_OBJECTS_ARB); newGlobal(t, "GL_OBJECT_ATTACHED_OBJECTS_ARB");
		pushInt(t, GL_OBJECT_ACTIVE_UNIFORMS_ARB); newGlobal(t, "GL_OBJECT_ACTIVE_UNIFORMS_ARB");
		pushInt(t, GL_OBJECT_ACTIVE_UNIFORM_MAX_LENGTH_ARB); newGlobal(t, "GL_OBJECT_ACTIVE_UNIFORM_MAX_LENGTH_ARB");
		pushInt(t, GL_OBJECT_SHADER_SOURCE_LENGTH_ARB); newGlobal(t, "GL_OBJECT_SHADER_SOURCE_LENGTH_ARB");
	}

	if(ARBShadingLanguage100.isEnabled)
	{
		pushInt(t, GL_SHADING_LANGUAGE_VERSION_ARB); newGlobal(t, "GL_SHADING_LANGUAGE_VERSION_ARB");
	}

	if(ARBShadow.isEnabled)
	{
		pushInt(t, GL_TEXTURE_COMPARE_MODE_ARB); newGlobal(t, "GL_TEXTURE_COMPARE_MODE_ARB");
		pushInt(t, GL_TEXTURE_COMPARE_FUNC_ARB); newGlobal(t, "GL_TEXTURE_COMPARE_FUNC_ARB");
		pushInt(t, GL_COMPARE_R_TO_TEXTURE_ARB); newGlobal(t, "GL_COMPARE_R_TO_TEXTURE_ARB");
	}

	if(ARBShadowAmbient.isEnabled)
	{
		pushInt(t, GL_TEXTURE_COMPARE_FAIL_VALUE_ARB); newGlobal(t, "GL_TEXTURE_COMPARE_FAIL_VALUE_ARB");
	}

	if(ARBTextureBorderClamp.isEnabled)
	{
		pushInt(t, GL_CLAMP_TO_BORDER_ARB); newGlobal(t, "GL_CLAMP_TO_BORDER_ARB");
	}

	if(ARBTextureCompression.isEnabled)
	{
		register(t, &wrapGL!(glCompressedTexImage3DARB), "glCompressedTexImage3DARB");
		register(t, &wrapGL!(glCompressedTexImage2DARB), "glCompressedTexImage2DARB");
		register(t, &wrapGL!(glCompressedTexImage1DARB), "glCompressedTexImage1DARB");
		register(t, &wrapGL!(glCompressedTexSubImage3DARB), "glCompressedTexSubImage3DARB");
		register(t, &wrapGL!(glCompressedTexSubImage2DARB), "glCompressedTexSubImage2DARB");
		register(t, &wrapGL!(glCompressedTexSubImage1DARB), "glCompressedTexSubImage1DARB");
		register(t, &wrapGL!(glGetCompressedTexImageARB), "glGetCompressedTexImageARB");

		pushInt(t, GL_COMPRESSED_ALPHA_ARB); newGlobal(t, "GL_COMPRESSED_ALPHA_ARB");
		pushInt(t, GL_COMPRESSED_LUMINANCE_ARB); newGlobal(t, "GL_COMPRESSED_LUMINANCE_ARB");
		pushInt(t, GL_COMPRESSED_LUMINANCE_ALPHA_ARB); newGlobal(t, "GL_COMPRESSED_LUMINANCE_ALPHA_ARB");
		pushInt(t, GL_COMPRESSED_INTENSITY_ARB); newGlobal(t, "GL_COMPRESSED_INTENSITY_ARB");
		pushInt(t, GL_COMPRESSED_RGB_ARB); newGlobal(t, "GL_COMPRESSED_RGB_ARB");
		pushInt(t, GL_COMPRESSED_RGBA_ARB); newGlobal(t, "GL_COMPRESSED_RGBA_ARB");
		pushInt(t, GL_TEXTURE_COMPRESSION_HINT_ARB); newGlobal(t, "GL_TEXTURE_COMPRESSION_HINT_ARB");
		pushInt(t, GL_TEXTURE_COMPRESSED_IMAGE_SIZE_ARB); newGlobal(t, "GL_TEXTURE_COMPRESSED_IMAGE_SIZE_ARB");
		pushInt(t, GL_TEXTURE_COMPRESSED_ARB); newGlobal(t, "GL_TEXTURE_COMPRESSED_ARB");
		pushInt(t, GL_NUM_COMPRESSED_TEXTURE_FORMATS_ARB); newGlobal(t, "GL_NUM_COMPRESSED_TEXTURE_FORMATS_ARB");
		pushInt(t, GL_COMPRESSED_TEXTURE_FORMATS_ARB); newGlobal(t, "GL_COMPRESSED_TEXTURE_FORMATS_ARB");
	}

	if(ARBTextureCubeMap.isEnabled)
	{
		pushInt(t, GL_NORMAL_MAP_ARB); newGlobal(t, "GL_NORMAL_MAP_ARB");
		pushInt(t, GL_REFLECTION_MAP_ARB); newGlobal(t, "GL_REFLECTION_MAP_ARB");
		pushInt(t, GL_TEXTURE_CUBE_MAP_ARB); newGlobal(t, "GL_TEXTURE_CUBE_MAP_ARB");
		pushInt(t, GL_TEXTURE_BINDING_CUBE_MAP_ARB); newGlobal(t, "GL_TEXTURE_BINDING_CUBE_MAP_ARB");
		pushInt(t, GL_TEXTURE_CUBE_MAP_POSITIVE_X_ARB); newGlobal(t, "GL_TEXTURE_CUBE_MAP_POSITIVE_X_ARB");
		pushInt(t, GL_TEXTURE_CUBE_MAP_NEGATIVE_X_ARB); newGlobal(t, "GL_TEXTURE_CUBE_MAP_NEGATIVE_X_ARB");
		pushInt(t, GL_TEXTURE_CUBE_MAP_POSITIVE_Y_ARB); newGlobal(t, "GL_TEXTURE_CUBE_MAP_POSITIVE_Y_ARB");
		pushInt(t, GL_TEXTURE_CUBE_MAP_NEGATIVE_Y_ARB); newGlobal(t, "GL_TEXTURE_CUBE_MAP_NEGATIVE_Y_ARB");
		pushInt(t, GL_TEXTURE_CUBE_MAP_POSITIVE_Z_ARB); newGlobal(t, "GL_TEXTURE_CUBE_MAP_POSITIVE_Z_ARB");
		pushInt(t, GL_TEXTURE_CUBE_MAP_NEGATIVE_Z_ARB); newGlobal(t, "GL_TEXTURE_CUBE_MAP_NEGATIVE_Z_ARB");
		pushInt(t, GL_PROXY_TEXTURE_CUBE_MAP_ARB); newGlobal(t, "GL_PROXY_TEXTURE_CUBE_MAP_ARB");
		pushInt(t, GL_MAX_CUBE_MAP_TEXTURE_SIZE_ARB); newGlobal(t, "GL_MAX_CUBE_MAP_TEXTURE_SIZE_ARB");
	}

	if(ARBTextureEnvCombine.isEnabled)
	{
		pushInt(t, GL_COMBINE_ARB); newGlobal(t, "GL_COMBINE_ARB");
		pushInt(t, GL_COMBINE_RGB_ARB); newGlobal(t, "GL_COMBINE_RGB_ARB");
		pushInt(t, GL_COMBINE_ALPHA_ARB); newGlobal(t, "GL_COMBINE_ALPHA_ARB");
		pushInt(t, GL_SOURCE0_RGB_ARB); newGlobal(t, "GL_SOURCE0_RGB_ARB");
		pushInt(t, GL_SOURCE1_RGB_ARB); newGlobal(t, "GL_SOURCE1_RGB_ARB");
		pushInt(t, GL_SOURCE2_RGB_ARB); newGlobal(t, "GL_SOURCE2_RGB_ARB");
		pushInt(t, GL_SOURCE0_ALPHA_ARB); newGlobal(t, "GL_SOURCE0_ALPHA_ARB");
		pushInt(t, GL_SOURCE1_ALPHA_ARB); newGlobal(t, "GL_SOURCE1_ALPHA_ARB");
		pushInt(t, GL_SOURCE2_ALPHA_ARB); newGlobal(t, "GL_SOURCE2_ALPHA_ARB");
		pushInt(t, GL_OPERAND0_RGB_ARB); newGlobal(t, "GL_OPERAND0_RGB_ARB");
		pushInt(t, GL_OPERAND1_RGB_ARB); newGlobal(t, "GL_OPERAND1_RGB_ARB");
		pushInt(t, GL_OPERAND2_RGB_ARB); newGlobal(t, "GL_OPERAND2_RGB_ARB");
		pushInt(t, GL_OPERAND0_ALPHA_ARB); newGlobal(t, "GL_OPERAND0_ALPHA_ARB");
		pushInt(t, GL_OPERAND1_ALPHA_ARB); newGlobal(t, "GL_OPERAND1_ALPHA_ARB");
		pushInt(t, GL_OPERAND2_ALPHA_ARB); newGlobal(t, "GL_OPERAND2_ALPHA_ARB");
		pushInt(t, GL_RGB_SCALE_ARB); newGlobal(t, "GL_RGB_SCALE_ARB");
		pushInt(t, GL_ADD_SIGNED_ARB); newGlobal(t, "GL_ADD_SIGNED_ARB");
		pushInt(t, GL_INTERPOLATE_ARB); newGlobal(t, "GL_INTERPOLATE_ARB");
		pushInt(t, GL_SUBTRACT_ARB); newGlobal(t, "GL_SUBTRACT_ARB");
		pushInt(t, GL_CONSTANT_ARB); newGlobal(t, "GL_CONSTANT_ARB");
		pushInt(t, GL_PRIMARY_COLOR_ARB); newGlobal(t, "GL_PRIMARY_COLOR_ARB");
		pushInt(t, GL_PREVIOUS_ARB); newGlobal(t, "GL_PREVIOUS_ARB");
	}

	if(ARBTextureEnvDot3.isEnabled)
	{
		pushInt(t, GL_DOT3_RGB_ARB); newGlobal(t, "GL_DOT3_RGB_ARB");
		pushInt(t, GL_DOT3_RGBA_ARB); newGlobal(t, "GL_DOT3_RGBA_ARB");
	}

	if(ARBTextureFloat.isEnabled)
	{
		pushInt(t, GL_TEXTURE_RED_TYPE_ARB); newGlobal(t, "GL_TEXTURE_RED_TYPE_ARB");
		pushInt(t, GL_TEXTURE_GREEN_TYPE_ARB); newGlobal(t, "GL_TEXTURE_GREEN_TYPE_ARB");
		pushInt(t, GL_TEXTURE_BLUE_TYPE_ARB); newGlobal(t, "GL_TEXTURE_BLUE_TYPE_ARB");
		pushInt(t, GL_TEXTURE_ALPHA_TYPE_ARB); newGlobal(t, "GL_TEXTURE_ALPHA_TYPE_ARB");
		pushInt(t, GL_TEXTURE_LUMINANCE_TYPE_ARB); newGlobal(t, "GL_TEXTURE_LUMINANCE_TYPE_ARB");
		pushInt(t, GL_TEXTURE_INTENSITY_TYPE_ARB); newGlobal(t, "GL_TEXTURE_INTENSITY_TYPE_ARB");
		pushInt(t, GL_TEXTURE_DEPTH_TYPE_ARB); newGlobal(t, "GL_TEXTURE_DEPTH_TYPE_ARB");
		pushInt(t, GL_UNSIGNED_NORMALIZED_ARB); newGlobal(t, "GL_UNSIGNED_NORMALIZED_ARB");
		pushInt(t, GL_RGBA32F_ARB); newGlobal(t, "GL_RGBA32F_ARB");
		pushInt(t, GL_RGB32F_ARB); newGlobal(t, "GL_RGB32F_ARB");
		pushInt(t, GL_ALPHA32F_ARB); newGlobal(t, "GL_ALPHA32F_ARB");
		pushInt(t, GL_INTENSITY32F_ARB); newGlobal(t, "GL_INTENSITY32F_ARB");
		pushInt(t, GL_LUMINANCE32F_ARB); newGlobal(t, "GL_LUMINANCE32F_ARB");
		pushInt(t, GL_LUMINANCE_ALPHA32F_ARB); newGlobal(t, "GL_LUMINANCE_ALPHA32F_ARB");
		pushInt(t, GL_RGBA16F_ARB); newGlobal(t, "GL_RGBA16F_ARB");
		pushInt(t, GL_RGB16F_ARB); newGlobal(t, "GL_RGB16F_ARB");
		pushInt(t, GL_ALPHA16F_ARB); newGlobal(t, "GL_ALPHA16F_ARB");
		pushInt(t, GL_INTENSITY16F_ARB); newGlobal(t, "GL_INTENSITY16F_ARB");
		pushInt(t, GL_LUMINANCE16F_ARB); newGlobal(t, "GL_LUMINANCE16F_ARB");
		pushInt(t, GL_LUMINANCE_ALPHA16F_ARB); newGlobal(t, "GL_LUMINANCE_ALPHA16F_ARB");
	}

	if(ARBTextureMirroredRepeat.isEnabled)
	{
		pushInt(t, GL_MIRRORED_REPEAT_ARB); newGlobal(t, "GL_MIRRORED_REPEAT_ARB");
	}

	if(ARBTextureRectangle.isEnabled)
	{
		pushInt(t, GL_TEXTURE_RECTANGLE_ARB); newGlobal(t, "GL_TEXTURE_RECTANGLE_ARB");
		pushInt(t, GL_TEXTURE_BINDING_RECTANGLE_ARB); newGlobal(t, "GL_TEXTURE_BINDING_RECTANGLE_ARB");
		pushInt(t, GL_PROXY_TEXTURE_RECTANGLE_ARB); newGlobal(t, "GL_PROXY_TEXTURE_RECTANGLE_ARB");
		pushInt(t, GL_MAX_RECTANGLE_TEXTURE_SIZE_ARB); newGlobal(t, "GL_MAX_RECTANGLE_TEXTURE_SIZE_ARB");
	}

	if(ARBTransposeMatrix.isEnabled)
	{
		register(t, &wrapGL!(glLoadTransposeMatrixfARB), "glLoadTransposeMatrixfARB");
		register(t, &wrapGL!(glLoadTransposeMatrixdARB), "glLoadTransposeMatrixdARB");
		register(t, &wrapGL!(glMultTransposeMatrixfARB), "glMultTransposeMatrixfARB");
		register(t, &wrapGL!(glMultTransposeMatrixdARB), "glMultTransposeMatrixdARB");

		pushInt(t, GL_TRANSPOSE_MODELVIEW_MATRIX_ARB); newGlobal(t, "GL_TRANSPOSE_MODELVIEW_MATRIX_ARB");
		pushInt(t, GL_TRANSPOSE_PROJECTION_MATRIX_ARB); newGlobal(t, "GL_TRANSPOSE_PROJECTION_MATRIX_ARB");
		pushInt(t, GL_TRANSPOSE_TEXTURE_MATRIX_ARB); newGlobal(t, "GL_TRANSPOSE_TEXTURE_MATRIX_ARB");
		pushInt(t, GL_TRANSPOSE_COLOR_MATRIX_ARB); newGlobal(t, "GL_TRANSPOSE_COLOR_MATRIX_ARB");
	}

	if(ARBVertexBlend.isEnabled)
	{
		register(t, &wrapGL!(glWeightbvARB), "glWeightbvARB");
		register(t, &wrapGL!(glWeightsvARB), "glWeightsvARB");
		register(t, &wrapGL!(glWeightivARB), "glWeightivARB");
		register(t, &wrapGL!(glWeightfvARB), "glWeightfvARB");
		register(t, &wrapGL!(glWeightdvARB), "glWeightdvARB");
		register(t, &wrapGL!(glWeightubvARB), "glWeightubvARB");
		register(t, &wrapGL!(glWeightusvARB), "glWeightusvARB");
		register(t, &wrapGL!(glWeightuivARB), "glWeightuivARB");
		register(t, &wrapGL!(glWeightPointerARB), "glWeightPointerARB");
		register(t, &wrapGL!(glVertexBlendARB), "glVertexBlendARB");

		pushInt(t, GL_MAX_VERTEX_UNITS_ARB); newGlobal(t, "GL_MAX_VERTEX_UNITS_ARB");
		pushInt(t, GL_ACTIVE_VERTEX_UNITS_ARB); newGlobal(t, "GL_ACTIVE_VERTEX_UNITS_ARB");
		pushInt(t, GL_WEIGHT_SUM_UNITY_ARB); newGlobal(t, "GL_WEIGHT_SUM_UNITY_ARB");
		pushInt(t, GL_VERTEX_BLEND_ARB); newGlobal(t, "GL_VERTEX_BLEND_ARB");
		pushInt(t, GL_CURRENT_WEIGHT_ARB); newGlobal(t, "GL_CURRENT_WEIGHT_ARB");
		pushInt(t, GL_WEIGHT_ARRAY_TYPE_ARB); newGlobal(t, "GL_WEIGHT_ARRAY_TYPE_ARB");
		pushInt(t, GL_WEIGHT_ARRAY_STRIDE_ARB); newGlobal(t, "GL_WEIGHT_ARRAY_STRIDE_ARB");
		pushInt(t, GL_WEIGHT_ARRAY_SIZE_ARB); newGlobal(t, "GL_WEIGHT_ARRAY_SIZE_ARB");
		pushInt(t, GL_WEIGHT_ARRAY_POINTER_ARB); newGlobal(t, "GL_WEIGHT_ARRAY_POINTER_ARB");
		pushInt(t, GL_WEIGHT_ARRAY_ARB); newGlobal(t, "GL_WEIGHT_ARRAY_ARB");
		pushInt(t, GL_MODELVIEW0_ARB); newGlobal(t, "GL_MODELVIEW0_ARB");
		pushInt(t, GL_MODELVIEW1_ARB); newGlobal(t, "GL_MODELVIEW1_ARB");
		pushInt(t, GL_MODELVIEW2_ARB); newGlobal(t, "GL_MODELVIEW2_ARB");
		pushInt(t, GL_MODELVIEW3_ARB); newGlobal(t, "GL_MODELVIEW3_ARB");
		pushInt(t, GL_MODELVIEW4_ARB); newGlobal(t, "GL_MODELVIEW4_ARB");
		pushInt(t, GL_MODELVIEW5_ARB); newGlobal(t, "GL_MODELVIEW5_ARB");
		pushInt(t, GL_MODELVIEW6_ARB); newGlobal(t, "GL_MODELVIEW6_ARB");
		pushInt(t, GL_MODELVIEW7_ARB); newGlobal(t, "GL_MODELVIEW7_ARB");
		pushInt(t, GL_MODELVIEW8_ARB); newGlobal(t, "GL_MODELVIEW8_ARB");
		pushInt(t, GL_MODELVIEW9_ARB); newGlobal(t, "GL_MODELVIEW9_ARB");
		pushInt(t, GL_MODELVIEW10_ARB); newGlobal(t, "GL_MODELVIEW10_ARB");
		pushInt(t, GL_MODELVIEW11_ARB); newGlobal(t, "GL_MODELVIEW11_ARB");
		pushInt(t, GL_MODELVIEW12_ARB); newGlobal(t, "GL_MODELVIEW12_ARB");
		pushInt(t, GL_MODELVIEW13_ARB); newGlobal(t, "GL_MODELVIEW13_ARB");
		pushInt(t, GL_MODELVIEW14_ARB); newGlobal(t, "GL_MODELVIEW14_ARB");
		pushInt(t, GL_MODELVIEW15_ARB); newGlobal(t, "GL_MODELVIEW15_ARB");
		pushInt(t, GL_MODELVIEW16_ARB); newGlobal(t, "GL_MODELVIEW16_ARB");
		pushInt(t, GL_MODELVIEW17_ARB); newGlobal(t, "GL_MODELVIEW17_ARB");
		pushInt(t, GL_MODELVIEW18_ARB); newGlobal(t, "GL_MODELVIEW18_ARB");
		pushInt(t, GL_MODELVIEW19_ARB); newGlobal(t, "GL_MODELVIEW19_ARB");
		pushInt(t, GL_MODELVIEW20_ARB); newGlobal(t, "GL_MODELVIEW20_ARB");
		pushInt(t, GL_MODELVIEW21_ARB); newGlobal(t, "GL_MODELVIEW21_ARB");
		pushInt(t, GL_MODELVIEW22_ARB); newGlobal(t, "GL_MODELVIEW22_ARB");
		pushInt(t, GL_MODELVIEW23_ARB); newGlobal(t, "GL_MODELVIEW23_ARB");
		pushInt(t, GL_MODELVIEW24_ARB); newGlobal(t, "GL_MODELVIEW24_ARB");
		pushInt(t, GL_MODELVIEW25_ARB); newGlobal(t, "GL_MODELVIEW25_ARB");
		pushInt(t, GL_MODELVIEW26_ARB); newGlobal(t, "GL_MODELVIEW26_ARB");
		pushInt(t, GL_MODELVIEW27_ARB); newGlobal(t, "GL_MODELVIEW27_ARB");
		pushInt(t, GL_MODELVIEW28_ARB); newGlobal(t, "GL_MODELVIEW28_ARB");
		pushInt(t, GL_MODELVIEW29_ARB); newGlobal(t, "GL_MODELVIEW29_ARB");
		pushInt(t, GL_MODELVIEW30_ARB); newGlobal(t, "GL_MODELVIEW30_ARB");
		pushInt(t, GL_MODELVIEW31_ARB); newGlobal(t, "GL_MODELVIEW31_ARB");
	}

	if(ARBVertexBufferObject.isEnabled)
	{
		register(t, &wrapGL!(glBindBufferARB), "glBindBufferARB");
		register(t, &wrapGL!(glDeleteBuffersARB), "glDeleteBuffersARB");
		register(t, &wrapGL!(glGenBuffersARB), "glGenBuffersARB");
		register(t, &wrapGL!(glIsBufferARB), "glIsBufferARB");
		register(t, &wrapGL!(glBufferDataARB), "glBufferDataARB");
		register(t, &wrapGL!(glBufferSubDataARB), "glBufferSubDataARB");
		register(t, &wrapGL!(glGetBufferSubDataARB), "glGetBufferSubDataARB");
// 		register(t, &wrapGL!(glMapBufferARB), "glMapBufferARB");
		register(t, &wrapGL!(glUnmapBufferARB), "glUnmapBufferARB");
		register(t, &wrapGL!(glGetBufferParameterivARB), "glGetBufferParameterivARB");
		register(t, &wrapGL!(glGetBufferPointervARB), "glGetBufferPointervARB");

		pushInt(t, GL_BUFFER_SIZE_ARB); newGlobal(t, "GL_BUFFER_SIZE_ARB");
		pushInt(t, GL_BUFFER_USAGE_ARB); newGlobal(t, "GL_BUFFER_USAGE_ARB");
		pushInt(t, GL_ARRAY_BUFFER_ARB); newGlobal(t, "GL_ARRAY_BUFFER_ARB");
		pushInt(t, GL_ELEMENT_ARRAY_BUFFER_ARB); newGlobal(t, "GL_ELEMENT_ARRAY_BUFFER_ARB");
		pushInt(t, GL_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_ELEMENT_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_ELEMENT_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_VERTEX_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_VERTEX_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_NORMAL_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_NORMAL_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_COLOR_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_COLOR_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_INDEX_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_INDEX_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_TEXTURE_COORD_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_TEXTURE_COORD_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_EDGE_FLAG_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_EDGE_FLAG_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_SECONDARY_COLOR_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_SECONDARY_COLOR_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_FOG_COORDINATE_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_FOG_COORDINATE_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_WEIGHT_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_WEIGHT_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING_ARB); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING_ARB");
		pushInt(t, GL_READ_ONLY_ARB); newGlobal(t, "GL_READ_ONLY_ARB");
		pushInt(t, GL_WRITE_ONLY_ARB); newGlobal(t, "GL_WRITE_ONLY_ARB");
		pushInt(t, GL_READ_WRITE_ARB); newGlobal(t, "GL_READ_WRITE_ARB");
		pushInt(t, GL_BUFFER_ACCESS_ARB); newGlobal(t, "GL_BUFFER_ACCESS_ARB");
		pushInt(t, GL_BUFFER_MAPPED_ARB); newGlobal(t, "GL_BUFFER_MAPPED_ARB");
		pushInt(t, GL_BUFFER_MAP_POINTER_ARB); newGlobal(t, "GL_BUFFER_MAP_POINTER_ARB");
		pushInt(t, GL_STREAM_DRAW_ARB); newGlobal(t, "GL_STREAM_DRAW_ARB");
		pushInt(t, GL_STREAM_READ_ARB); newGlobal(t, "GL_STREAM_READ_ARB");
		pushInt(t, GL_STREAM_COPY_ARB); newGlobal(t, "GL_STREAM_COPY_ARB");
		pushInt(t, GL_STATIC_DRAW_ARB); newGlobal(t, "GL_STATIC_DRAW_ARB");
		pushInt(t, GL_STATIC_READ_ARB); newGlobal(t, "GL_STATIC_READ_ARB");
		pushInt(t, GL_STATIC_COPY_ARB); newGlobal(t, "GL_STATIC_COPY_ARB");
		pushInt(t, GL_DYNAMIC_DRAW_ARB); newGlobal(t, "GL_DYNAMIC_DRAW_ARB");
		pushInt(t, GL_DYNAMIC_READ_ARB); newGlobal(t, "GL_DYNAMIC_READ_ARB");
		pushInt(t, GL_DYNAMIC_COPY_ARB); newGlobal(t, "GL_DYNAMIC_COPY_ARB");
	}

	if(ARBVertexProgram.isEnabled)
	{
		register(t, &wrapGL!(glVertexAttrib1dARB), "glVertexAttrib1dARB");
		register(t, &wrapGL!(glVertexAttrib1dvARB), "glVertexAttrib1dvARB");
		register(t, &wrapGL!(glVertexAttrib1fARB), "glVertexAttrib1fARB");
		register(t, &wrapGL!(glVertexAttrib1fvARB), "glVertexAttrib1fvARB");
		register(t, &wrapGL!(glVertexAttrib1sARB), "glVertexAttrib1sARB");
		register(t, &wrapGL!(glVertexAttrib1svARB), "glVertexAttrib1svARB");
		register(t, &wrapGL!(glVertexAttrib2dARB), "glVertexAttrib2dARB");
		register(t, &wrapGL!(glVertexAttrib2dvARB), "glVertexAttrib2dvARB");
		register(t, &wrapGL!(glVertexAttrib2fARB), "glVertexAttrib2fARB");
		register(t, &wrapGL!(glVertexAttrib2fvARB), "glVertexAttrib2fvARB");
		register(t, &wrapGL!(glVertexAttrib2sARB), "glVertexAttrib2sARB");
		register(t, &wrapGL!(glVertexAttrib2svARB), "glVertexAttrib2svARB");
		register(t, &wrapGL!(glVertexAttrib3dARB), "glVertexAttrib3dARB");
		register(t, &wrapGL!(glVertexAttrib3dvARB), "glVertexAttrib3dvARB");
		register(t, &wrapGL!(glVertexAttrib3fARB), "glVertexAttrib3fARB");
		register(t, &wrapGL!(glVertexAttrib3fvARB), "glVertexAttrib3fvARB");
		register(t, &wrapGL!(glVertexAttrib3sARB), "glVertexAttrib3sARB");
		register(t, &wrapGL!(glVertexAttrib3svARB), "glVertexAttrib3svARB");
		register(t, &wrapGL!(glVertexAttrib4NbvARB), "glVertexAttrib4NbvARB");
		register(t, &wrapGL!(glVertexAttrib4NivARB), "glVertexAttrib4NivARB");
		register(t, &wrapGL!(glVertexAttrib4NsvARB), "glVertexAttrib4NsvARB");
		register(t, &wrapGL!(glVertexAttrib4NubARB), "glVertexAttrib4NubARB");
		register(t, &wrapGL!(glVertexAttrib4NubvARB), "glVertexAttrib4NubvARB");
		register(t, &wrapGL!(glVertexAttrib4NuivARB), "glVertexAttrib4NuivARB");
		register(t, &wrapGL!(glVertexAttrib4NusvARB), "glVertexAttrib4NusvARB");
		register(t, &wrapGL!(glVertexAttrib4bvARB), "glVertexAttrib4bvARB");
		register(t, &wrapGL!(glVertexAttrib4dARB), "glVertexAttrib4dARB");
		register(t, &wrapGL!(glVertexAttrib4dvARB), "glVertexAttrib4dvARB");
		register(t, &wrapGL!(glVertexAttrib4fARB), "glVertexAttrib4fARB");
		register(t, &wrapGL!(glVertexAttrib4fvARB), "glVertexAttrib4fvARB");
		register(t, &wrapGL!(glVertexAttrib4ivARB), "glVertexAttrib4ivARB");
		register(t, &wrapGL!(glVertexAttrib4sARB), "glVertexAttrib4sARB");
		register(t, &wrapGL!(glVertexAttrib4svARB), "glVertexAttrib4svARB");
		register(t, &wrapGL!(glVertexAttrib4ubvARB), "glVertexAttrib4ubvARB");
		register(t, &wrapGL!(glVertexAttrib4uivARB), "glVertexAttrib4uivARB");
		register(t, &wrapGL!(glVertexAttrib4usvARB), "glVertexAttrib4usvARB");
		register(t, &wrapGL!(glVertexAttribPointerARB), "glVertexAttribPointerARB");
		register(t, &wrapGL!(glEnableVertexAttribArrayARB), "glEnableVertexAttribArrayARB");
		register(t, &wrapGL!(glDisableVertexAttribArrayARB), "glDisableVertexAttribArrayARB");
		register(t, &wrapGL!(glProgramStringARB), "glProgramStringARB");
		register(t, &wrapGL!(glBindProgramARB), "glBindProgramARB");
		register(t, &wrapGL!(glDeleteProgramsARB), "glDeleteProgramsARB");
		register(t, &wrapGL!(glGenProgramsARB), "glGenProgramsARB");
		register(t, &wrapGL!(glProgramEnvParameter4dARB), "glProgramEnvParameter4dARB");
		register(t, &wrapGL!(glProgramEnvParameter4dvARB), "glProgramEnvParameter4dvARB");
		register(t, &wrapGL!(glProgramEnvParameter4fARB), "glProgramEnvParameter4fARB");
		register(t, &wrapGL!(glProgramEnvParameter4fvARB), "glProgramEnvParameter4fvARB");
		register(t, &wrapGL!(glProgramLocalParameter4dARB), "glProgramLocalParameter4dARB");
		register(t, &wrapGL!(glProgramLocalParameter4dvARB), "glProgramLocalParameter4dvARB");
		register(t, &wrapGL!(glProgramLocalParameter4fARB), "glProgramLocalParameter4fARB");
		register(t, &wrapGL!(glProgramLocalParameter4fvARB), "glProgramLocalParameter4fvARB");
		register(t, &wrapGL!(glGetProgramEnvParameterdvARB), "glGetProgramEnvParameterdvARB");
		register(t, &wrapGL!(glGetProgramEnvParameterfvARB), "glGetProgramEnvParameterfvARB");
		register(t, &wrapGL!(glGetProgramLocalParameterdvARB), "glGetProgramLocalParameterdvARB");
		register(t, &wrapGL!(glGetProgramLocalParameterfvARB), "glGetProgramLocalParameterfvARB");
		register(t, &wrapGL!(glGetProgramivARB), "glGetProgramivARB");
		register(t, &wrapGL!(glGetProgramStringARB), "glGetProgramStringARB");
		register(t, &wrapGL!(glGetVertexAttribdvARB), "glGetVertexAttribdvARB");
		register(t, &wrapGL!(glGetVertexAttribfvARB), "glGetVertexAttribfvARB");
		register(t, &wrapGL!(glGetVertexAttribivARB), "glGetVertexAttribivARB");
		register(t, &wrapGL!(glGetVertexAttribPointervARB), "glGetVertexAttribPointervARB");
		register(t, &wrapGL!(glIsProgramARB), "glIsProgramARB");

		pushInt(t, GL_COLOR_SUM_ARB); newGlobal(t, "GL_COLOR_SUM_ARB");
		pushInt(t, GL_VERTEX_PROGRAM_ARB); newGlobal(t, "GL_VERTEX_PROGRAM_ARB");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY_ENABLED_ARB); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY_ENABLED_ARB");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY_SIZE_ARB); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY_SIZE_ARB");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY_STRIDE_ARB); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY_STRIDE_ARB");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY_TYPE_ARB); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY_TYPE_ARB");
		pushInt(t, GL_CURRENT_VERTEX_ATTRIB_ARB); newGlobal(t, "GL_CURRENT_VERTEX_ATTRIB_ARB");
		pushInt(t, GL_PROGRAM_LENGTH_ARB); newGlobal(t, "GL_PROGRAM_LENGTH_ARB");
		pushInt(t, GL_PROGRAM_STRING_ARB); newGlobal(t, "GL_PROGRAM_STRING_ARB");
		pushInt(t, GL_MAX_PROGRAM_MATRIX_STACK_DEPTH_ARB); newGlobal(t, "GL_MAX_PROGRAM_MATRIX_STACK_DEPTH_ARB");
		pushInt(t, GL_MAX_PROGRAM_MATRICES_ARB); newGlobal(t, "GL_MAX_PROGRAM_MATRICES_ARB");
		pushInt(t, GL_CURRENT_MATRIX_STACK_DEPTH_ARB); newGlobal(t, "GL_CURRENT_MATRIX_STACK_DEPTH_ARB");
		pushInt(t, GL_CURRENT_MATRIX_ARB); newGlobal(t, "GL_CURRENT_MATRIX_ARB");
		pushInt(t, GL_VERTEX_PROGRAM_POINT_SIZE_ARB); newGlobal(t, "GL_VERTEX_PROGRAM_POINT_SIZE_ARB");
		pushInt(t, GL_VERTEX_PROGRAM_TWO_SIDE_ARB); newGlobal(t, "GL_VERTEX_PROGRAM_TWO_SIDE_ARB");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY_POINTER_ARB); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY_POINTER_ARB");
		pushInt(t, GL_PROGRAM_ERROR_POSITION_ARB); newGlobal(t, "GL_PROGRAM_ERROR_POSITION_ARB");
		pushInt(t, GL_PROGRAM_BINDING_ARB); newGlobal(t, "GL_PROGRAM_BINDING_ARB");
		pushInt(t, GL_MAX_VERTEX_ATTRIBS_ARB); newGlobal(t, "GL_MAX_VERTEX_ATTRIBS_ARB");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY_NORMALIZED_ARB); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY_NORMALIZED_ARB");
		pushInt(t, GL_PROGRAM_ERROR_STRING_ARB); newGlobal(t, "GL_PROGRAM_ERROR_STRING_ARB");
		pushInt(t, GL_PROGRAM_FORMAT_ASCII_ARB); newGlobal(t, "GL_PROGRAM_FORMAT_ASCII_ARB");
		pushInt(t, GL_PROGRAM_FORMAT_ARB); newGlobal(t, "GL_PROGRAM_FORMAT_ARB");
		pushInt(t, GL_PROGRAM_INSTRUCTIONS_ARB); newGlobal(t, "GL_PROGRAM_INSTRUCTIONS_ARB");
		pushInt(t, GL_MAX_PROGRAM_INSTRUCTIONS_ARB); newGlobal(t, "GL_MAX_PROGRAM_INSTRUCTIONS_ARB");
		pushInt(t, GL_PROGRAM_NATIVE_INSTRUCTIONS_ARB); newGlobal(t, "GL_PROGRAM_NATIVE_INSTRUCTIONS_ARB");
		pushInt(t, GL_MAX_PROGRAM_NATIVE_INSTRUCTIONS_ARB); newGlobal(t, "GL_MAX_PROGRAM_NATIVE_INSTRUCTIONS_ARB");
		pushInt(t, GL_PROGRAM_TEMPORARIES_ARB); newGlobal(t, "GL_PROGRAM_TEMPORARIES_ARB");
		pushInt(t, GL_MAX_PROGRAM_TEMPORARIES_ARB); newGlobal(t, "GL_MAX_PROGRAM_TEMPORARIES_ARB");
		pushInt(t, GL_PROGRAM_NATIVE_TEMPORARIES_ARB); newGlobal(t, "GL_PROGRAM_NATIVE_TEMPORARIES_ARB");
		pushInt(t, GL_MAX_PROGRAM_NATIVE_TEMPORARIES_ARB); newGlobal(t, "GL_MAX_PROGRAM_NATIVE_TEMPORARIES_ARB");
		pushInt(t, GL_PROGRAM_PARAMETERS_ARB); newGlobal(t, "GL_PROGRAM_PARAMETERS_ARB");
		pushInt(t, GL_MAX_PROGRAM_PARAMETERS_ARB); newGlobal(t, "GL_MAX_PROGRAM_PARAMETERS_ARB");
		pushInt(t, GL_PROGRAM_NATIVE_PARAMETERS_ARB); newGlobal(t, "GL_PROGRAM_NATIVE_PARAMETERS_ARB");
		pushInt(t, GL_MAX_PROGRAM_NATIVE_PARAMETERS_ARB); newGlobal(t, "GL_MAX_PROGRAM_NATIVE_PARAMETERS_ARB");
		pushInt(t, GL_PROGRAM_ATTRIBS_ARB); newGlobal(t, "GL_PROGRAM_ATTRIBS_ARB");
		pushInt(t, GL_MAX_PROGRAM_ATTRIBS_ARB); newGlobal(t, "GL_MAX_PROGRAM_ATTRIBS_ARB");
		pushInt(t, GL_PROGRAM_NATIVE_ATTRIBS_ARB); newGlobal(t, "GL_PROGRAM_NATIVE_ATTRIBS_ARB");
		pushInt(t, GL_MAX_PROGRAM_NATIVE_ATTRIBS_ARB); newGlobal(t, "GL_MAX_PROGRAM_NATIVE_ATTRIBS_ARB");
		pushInt(t, GL_PROGRAM_ADDRESS_REGISTERS_ARB); newGlobal(t, "GL_PROGRAM_ADDRESS_REGISTERS_ARB");
		pushInt(t, GL_MAX_PROGRAM_ADDRESS_REGISTERS_ARB); newGlobal(t, "GL_MAX_PROGRAM_ADDRESS_REGISTERS_ARB");
		pushInt(t, GL_PROGRAM_NATIVE_ADDRESS_REGISTERS_ARB); newGlobal(t, "GL_PROGRAM_NATIVE_ADDRESS_REGISTERS_ARB");
		pushInt(t, GL_MAX_PROGRAM_NATIVE_ADDRESS_REGISTERS_ARB); newGlobal(t, "GL_MAX_PROGRAM_NATIVE_ADDRESS_REGISTERS_ARB");
		pushInt(t, GL_MAX_PROGRAM_LOCAL_PARAMETERS_ARB); newGlobal(t, "GL_MAX_PROGRAM_LOCAL_PARAMETERS_ARB");
		pushInt(t, GL_MAX_PROGRAM_ENV_PARAMETERS_ARB); newGlobal(t, "GL_MAX_PROGRAM_ENV_PARAMETERS_ARB");
		pushInt(t, GL_PROGRAM_UNDER_NATIVE_LIMITS_ARB); newGlobal(t, "GL_PROGRAM_UNDER_NATIVE_LIMITS_ARB");
		pushInt(t, GL_TRANSPOSE_CURRENT_MATRIX_ARB); newGlobal(t, "GL_TRANSPOSE_CURRENT_MATRIX_ARB");
		pushInt(t, GL_MATRIX0_ARB); newGlobal(t, "GL_MATRIX0_ARB");
		pushInt(t, GL_MATRIX1_ARB); newGlobal(t, "GL_MATRIX1_ARB");
		pushInt(t, GL_MATRIX2_ARB); newGlobal(t, "GL_MATRIX2_ARB");
		pushInt(t, GL_MATRIX3_ARB); newGlobal(t, "GL_MATRIX3_ARB");
		pushInt(t, GL_MATRIX4_ARB); newGlobal(t, "GL_MATRIX4_ARB");
		pushInt(t, GL_MATRIX5_ARB); newGlobal(t, "GL_MATRIX5_ARB");
		pushInt(t, GL_MATRIX6_ARB); newGlobal(t, "GL_MATRIX6_ARB");
		pushInt(t, GL_MATRIX7_ARB); newGlobal(t, "GL_MATRIX7_ARB");
		pushInt(t, GL_MATRIX8_ARB); newGlobal(t, "GL_MATRIX8_ARB");
		pushInt(t, GL_MATRIX9_ARB); newGlobal(t, "GL_MATRIX9_ARB");
		pushInt(t, GL_MATRIX10_ARB); newGlobal(t, "GL_MATRIX10_ARB");
		pushInt(t, GL_MATRIX11_ARB); newGlobal(t, "GL_MATRIX11_ARB");
		pushInt(t, GL_MATRIX12_ARB); newGlobal(t, "GL_MATRIX12_ARB");
		pushInt(t, GL_MATRIX13_ARB); newGlobal(t, "GL_MATRIX13_ARB");
		pushInt(t, GL_MATRIX14_ARB); newGlobal(t, "GL_MATRIX14_ARB");
		pushInt(t, GL_MATRIX15_ARB); newGlobal(t, "GL_MATRIX15_ARB");
		pushInt(t, GL_MATRIX16_ARB); newGlobal(t, "GL_MATRIX16_ARB");
		pushInt(t, GL_MATRIX17_ARB); newGlobal(t, "GL_MATRIX17_ARB");
		pushInt(t, GL_MATRIX18_ARB); newGlobal(t, "GL_MATRIX18_ARB");
		pushInt(t, GL_MATRIX19_ARB); newGlobal(t, "GL_MATRIX19_ARB");
		pushInt(t, GL_MATRIX20_ARB); newGlobal(t, "GL_MATRIX20_ARB");
		pushInt(t, GL_MATRIX21_ARB); newGlobal(t, "GL_MATRIX21_ARB");
		pushInt(t, GL_MATRIX22_ARB); newGlobal(t, "GL_MATRIX22_ARB");
		pushInt(t, GL_MATRIX23_ARB); newGlobal(t, "GL_MATRIX23_ARB");
		pushInt(t, GL_MATRIX24_ARB); newGlobal(t, "GL_MATRIX24_ARB");
		pushInt(t, GL_MATRIX25_ARB); newGlobal(t, "GL_MATRIX25_ARB");
		pushInt(t, GL_MATRIX26_ARB); newGlobal(t, "GL_MATRIX26_ARB");
		pushInt(t, GL_MATRIX27_ARB); newGlobal(t, "GL_MATRIX27_ARB");
		pushInt(t, GL_MATRIX28_ARB); newGlobal(t, "GL_MATRIX28_ARB");
		pushInt(t, GL_MATRIX29_ARB); newGlobal(t, "GL_MATRIX29_ARB");
		pushInt(t, GL_MATRIX30_ARB); newGlobal(t, "GL_MATRIX30_ARB");
		pushInt(t, GL_MATRIX31_ARB); newGlobal(t, "GL_MATRIX31_ARB");
	}

	if(ARBVertexShader.isEnabled)
	{
		register(t, &wrapGL!(glBindAttribLocationARB), "glBindAttribLocationARB");
		register(t, &wrapGL!(glGetActiveAttribARB), "glGetActiveAttribARB");
		register(t, &wrapGL!(glGetAttribLocationARB), "glGetAttribLocationARB");

		pushInt(t, GL_VERTEX_SHADER_ARB); newGlobal(t, "GL_VERTEX_SHADER_ARB");
		pushInt(t, GL_MAX_VERTEX_UNIFORM_COMPONENTS_ARB); newGlobal(t, "GL_MAX_VERTEX_UNIFORM_COMPONENTS_ARB");
		pushInt(t, GL_MAX_VARYING_FLOATS_ARB); newGlobal(t, "GL_MAX_VARYING_FLOATS_ARB");
		pushInt(t, GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS_ARB); newGlobal(t, "GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS_ARB");
		pushInt(t, GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS_ARB); newGlobal(t, "GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS_ARB");
		pushInt(t, GL_OBJECT_ACTIVE_ATTRIBUTES_ARB); newGlobal(t, "GL_OBJECT_ACTIVE_ATTRIBUTES_ARB");
		pushInt(t, GL_OBJECT_ACTIVE_ATTRIBUTE_MAX_LENGTH_ARB); newGlobal(t, "GL_OBJECT_ACTIVE_ATTRIBUTE_MAX_LENGTH_ARB");
	}

	if(ARBWindowPos.isEnabled)
	{
		register(t, &wrapGL!(glWindowPos2dARB), "glWindowPos2dARB");
		register(t, &wrapGL!(glWindowPos2dvARB), "glWindowPos2dvARB");
		register(t, &wrapGL!(glWindowPos2fARB), "glWindowPos2fARB");
		register(t, &wrapGL!(glWindowPos2fvARB), "glWindowPos2fvARB");
		register(t, &wrapGL!(glWindowPos2iARB), "glWindowPos2iARB");
		register(t, &wrapGL!(glWindowPos2ivARB), "glWindowPos2ivARB");
		register(t, &wrapGL!(glWindowPos2sARB), "glWindowPos2sARB");
		register(t, &wrapGL!(glWindowPos2svARB), "glWindowPos2svARB");
		register(t, &wrapGL!(glWindowPos3dARB), "glWindowPos3dARB");
		register(t, &wrapGL!(glWindowPos3dvARB), "glWindowPos3dvARB");
		register(t, &wrapGL!(glWindowPos3fARB), "glWindowPos3fARB");
		register(t, &wrapGL!(glWindowPos3fvARB), "glWindowPos3fvARB");
		register(t, &wrapGL!(glWindowPos3iARB), "glWindowPos3iARB");
		register(t, &wrapGL!(glWindowPos3ivARB), "glWindowPos3ivARB");
		register(t, &wrapGL!(glWindowPos3sARB), "glWindowPos3sARB");
		register(t, &wrapGL!(glWindowPos3svARB), "glWindowPos3svARB");
	}

	// ATI
	if(ATIDrawBuffers.isEnabled)
	{
		register(t, &wrapGL!(glDrawBuffersATI), "glDrawBuffersATI");

		pushInt(t, GL_MAX_DRAW_BUFFERS_ATI); newGlobal(t, "GL_MAX_DRAW_BUFFERS_ATI");
		pushInt(t, GL_DRAW_BUFFER0_ATI); newGlobal(t, "GL_DRAW_BUFFER0_ATI");
		pushInt(t, GL_DRAW_BUFFER1_ATI); newGlobal(t, "GL_DRAW_BUFFER1_ATI");
		pushInt(t, GL_DRAW_BUFFER2_ATI); newGlobal(t, "GL_DRAW_BUFFER2_ATI");
		pushInt(t, GL_DRAW_BUFFER3_ATI); newGlobal(t, "GL_DRAW_BUFFER3_ATI");
		pushInt(t, GL_DRAW_BUFFER4_ATI); newGlobal(t, "GL_DRAW_BUFFER4_ATI");
		pushInt(t, GL_DRAW_BUFFER5_ATI); newGlobal(t, "GL_DRAW_BUFFER5_ATI");
		pushInt(t, GL_DRAW_BUFFER6_ATI); newGlobal(t, "GL_DRAW_BUFFER6_ATI");
		pushInt(t, GL_DRAW_BUFFER7_ATI); newGlobal(t, "GL_DRAW_BUFFER7_ATI");
		pushInt(t, GL_DRAW_BUFFER8_ATI); newGlobal(t, "GL_DRAW_BUFFER8_ATI");
		pushInt(t, GL_DRAW_BUFFER9_ATI); newGlobal(t, "GL_DRAW_BUFFER9_ATI");
		pushInt(t, GL_DRAW_BUFFER10_ATI); newGlobal(t, "GL_DRAW_BUFFER10_ATI");
		pushInt(t, GL_DRAW_BUFFER11_ATI); newGlobal(t, "GL_DRAW_BUFFER11_ATI");
		pushInt(t, GL_DRAW_BUFFER12_ATI); newGlobal(t, "GL_DRAW_BUFFER12_ATI");
		pushInt(t, GL_DRAW_BUFFER13_ATI); newGlobal(t, "GL_DRAW_BUFFER13_ATI");
		pushInt(t, GL_DRAW_BUFFER14_ATI); newGlobal(t, "GL_DRAW_BUFFER14_ATI");
		pushInt(t, GL_DRAW_BUFFER15_ATI); newGlobal(t, "GL_DRAW_BUFFER15_ATI");
	}

	if(ATIElementArray.isEnabled)
	{
		register(t, &wrapGL!(glElementPointerATI), "glElementPointerATI");
		register(t, &wrapGL!(glDrawElementArrayATI), "glDrawElementArrayATI");
		register(t, &wrapGL!(glDrawRangeElementArrayATI), "glDrawRangeElementArrayATI");

		pushInt(t, GL_ELEMENT_ARRAY_ATI); newGlobal(t, "GL_ELEMENT_ARRAY_ATI");
		pushInt(t, GL_ELEMENT_ARRAY_TYPE_ATI); newGlobal(t, "GL_ELEMENT_ARRAY_TYPE_ATI");
		pushInt(t, GL_ELEMENT_ARRAY_POINTER_ATI); newGlobal(t, "GL_ELEMENT_ARRAY_POINTER_ATI");
	}

	if(ATIEnvmapBumpmap.isEnabled)
	{
		register(t, &wrapGL!(glTexBumpParameterivATI), "glTexBumpParameterivATI");
		register(t, &wrapGL!(glTexBumpParameterfvATI), "glTexBumpParameterfvATI");
		register(t, &wrapGL!(glGetTexBumpParameterivATI), "glGetTexBumpParameterivATI");
		register(t, &wrapGL!(glGetTexBumpParameterfvATI), "glGetTexBumpParameterfvATI");

		pushInt(t, GL_BUMP_ROT_MATRIX_ATI); newGlobal(t, "GL_BUMP_ROT_MATRIX_ATI");
		pushInt(t, GL_BUMP_ROT_MATRIX_SIZE_ATI); newGlobal(t, "GL_BUMP_ROT_MATRIX_SIZE_ATI");
		pushInt(t, GL_BUMP_NUM_TEX_UNITS_ATI); newGlobal(t, "GL_BUMP_NUM_TEX_UNITS_ATI");
		pushInt(t, GL_BUMP_TEX_UNITS_ATI); newGlobal(t, "GL_BUMP_TEX_UNITS_ATI");
		pushInt(t, GL_DUDV_ATI); newGlobal(t, "GL_DUDV_ATI");
		pushInt(t, GL_DU8DV8_ATI); newGlobal(t, "GL_DU8DV8_ATI");
		pushInt(t, GL_BUMP_ENVMAP_ATI); newGlobal(t, "GL_BUMP_ENVMAP_ATI");
		pushInt(t, GL_BUMP_TARGET_ATI); newGlobal(t, "GL_BUMP_TARGET_ATI");
	}

	if(ATIFragmentShader.isEnabled)
	{
		register(t, &wrapGL!(glGenFragmentShadersATI), "glGenFragmentShadersATI");
		register(t, &wrapGL!(glBindFragmentShaderATI), "glBindFragmentShaderATI");
		register(t, &wrapGL!(glDeleteFragmentShaderATI), "glDeleteFragmentShaderATI");
		register(t, &wrapGL!(glBeginFragmentShaderATI), "glBeginFragmentShaderATI");
		register(t, &wrapGL!(glEndFragmentShaderATI), "glEndFragmentShaderATI");
		register(t, &wrapGL!(glPassTexCoordATI), "glPassTexCoordATI");
		register(t, &wrapGL!(glSampleMapATI), "glSampleMapATI");
		register(t, &wrapGL!(glColorFragmentOp1ATI), "glColorFragmentOp1ATI");
		register(t, &wrapGL!(glColorFragmentOp2ATI), "glColorFragmentOp2ATI");
		register(t, &wrapGL!(glColorFragmentOp3ATI), "glColorFragmentOp3ATI");
		register(t, &wrapGL!(glAlphaFragmentOp1ATI), "glAlphaFragmentOp1ATI");
		register(t, &wrapGL!(glAlphaFragmentOp2ATI), "glAlphaFragmentOp2ATI");
		register(t, &wrapGL!(glAlphaFragmentOp3ATI), "glAlphaFragmentOp3ATI");
		register(t, &wrapGL!(glSetFragmentShaderConstantATI), "glSetFragmentShaderConstantATI");

		pushInt(t, GL_FRAGMENT_SHADER_ATI); newGlobal(t, "GL_FRAGMENT_SHADER_ATI");
		pushInt(t, GL_REG_0_ATI); newGlobal(t, "GL_REG_0_ATI");
		pushInt(t, GL_REG_1_ATI); newGlobal(t, "GL_REG_1_ATI");
		pushInt(t, GL_REG_2_ATI); newGlobal(t, "GL_REG_2_ATI");
		pushInt(t, GL_REG_3_ATI); newGlobal(t, "GL_REG_3_ATI");
		pushInt(t, GL_REG_4_ATI); newGlobal(t, "GL_REG_4_ATI");
		pushInt(t, GL_REG_5_ATI); newGlobal(t, "GL_REG_5_ATI");
		pushInt(t, GL_REG_6_ATI); newGlobal(t, "GL_REG_6_ATI");
		pushInt(t, GL_REG_7_ATI); newGlobal(t, "GL_REG_7_ATI");
		pushInt(t, GL_REG_8_ATI); newGlobal(t, "GL_REG_8_ATI");
		pushInt(t, GL_REG_9_ATI); newGlobal(t, "GL_REG_9_ATI");
		pushInt(t, GL_REG_10_ATI); newGlobal(t, "GL_REG_10_ATI");
		pushInt(t, GL_REG_11_ATI); newGlobal(t, "GL_REG_11_ATI");
		pushInt(t, GL_REG_12_ATI); newGlobal(t, "GL_REG_12_ATI");
		pushInt(t, GL_REG_13_ATI); newGlobal(t, "GL_REG_13_ATI");
		pushInt(t, GL_REG_14_ATI); newGlobal(t, "GL_REG_14_ATI");
		pushInt(t, GL_REG_15_ATI); newGlobal(t, "GL_REG_15_ATI");
		pushInt(t, GL_REG_16_ATI); newGlobal(t, "GL_REG_16_ATI");
		pushInt(t, GL_REG_17_ATI); newGlobal(t, "GL_REG_17_ATI");
		pushInt(t, GL_REG_18_ATI); newGlobal(t, "GL_REG_18_ATI");
		pushInt(t, GL_REG_19_ATI); newGlobal(t, "GL_REG_19_ATI");
		pushInt(t, GL_REG_20_ATI); newGlobal(t, "GL_REG_20_ATI");
		pushInt(t, GL_REG_21_ATI); newGlobal(t, "GL_REG_21_ATI");
		pushInt(t, GL_REG_22_ATI); newGlobal(t, "GL_REG_22_ATI");
		pushInt(t, GL_REG_23_ATI); newGlobal(t, "GL_REG_23_ATI");
		pushInt(t, GL_REG_24_ATI); newGlobal(t, "GL_REG_24_ATI");
		pushInt(t, GL_REG_25_ATI); newGlobal(t, "GL_REG_25_ATI");
		pushInt(t, GL_REG_26_ATI); newGlobal(t, "GL_REG_26_ATI");
		pushInt(t, GL_REG_27_ATI); newGlobal(t, "GL_REG_27_ATI");
		pushInt(t, GL_REG_28_ATI); newGlobal(t, "GL_REG_28_ATI");
		pushInt(t, GL_REG_29_ATI); newGlobal(t, "GL_REG_29_ATI");
		pushInt(t, GL_REG_30_ATI); newGlobal(t, "GL_REG_30_ATI");
		pushInt(t, GL_REG_31_ATI); newGlobal(t, "GL_REG_31_ATI");
		pushInt(t, GL_CON_0_ATI); newGlobal(t, "GL_CON_0_ATI");
		pushInt(t, GL_CON_1_ATI); newGlobal(t, "GL_CON_1_ATI");
		pushInt(t, GL_CON_2_ATI); newGlobal(t, "GL_CON_2_ATI");
		pushInt(t, GL_CON_3_ATI); newGlobal(t, "GL_CON_3_ATI");
		pushInt(t, GL_CON_4_ATI); newGlobal(t, "GL_CON_4_ATI");
		pushInt(t, GL_CON_5_ATI); newGlobal(t, "GL_CON_5_ATI");
		pushInt(t, GL_CON_6_ATI); newGlobal(t, "GL_CON_6_ATI");
		pushInt(t, GL_CON_7_ATI); newGlobal(t, "GL_CON_7_ATI");
		pushInt(t, GL_CON_8_ATI); newGlobal(t, "GL_CON_8_ATI");
		pushInt(t, GL_CON_9_ATI); newGlobal(t, "GL_CON_9_ATI");
		pushInt(t, GL_CON_10_ATI); newGlobal(t, "GL_CON_10_ATI");
		pushInt(t, GL_CON_11_ATI); newGlobal(t, "GL_CON_11_ATI");
		pushInt(t, GL_CON_12_ATI); newGlobal(t, "GL_CON_12_ATI");
		pushInt(t, GL_CON_13_ATI); newGlobal(t, "GL_CON_13_ATI");
		pushInt(t, GL_CON_14_ATI); newGlobal(t, "GL_CON_14_ATI");
		pushInt(t, GL_CON_15_ATI); newGlobal(t, "GL_CON_15_ATI");
		pushInt(t, GL_CON_16_ATI); newGlobal(t, "GL_CON_16_ATI");
		pushInt(t, GL_CON_17_ATI); newGlobal(t, "GL_CON_17_ATI");
		pushInt(t, GL_CON_18_ATI); newGlobal(t, "GL_CON_18_ATI");
		pushInt(t, GL_CON_19_ATI); newGlobal(t, "GL_CON_19_ATI");
		pushInt(t, GL_CON_20_ATI); newGlobal(t, "GL_CON_20_ATI");
		pushInt(t, GL_CON_21_ATI); newGlobal(t, "GL_CON_21_ATI");
		pushInt(t, GL_CON_22_ATI); newGlobal(t, "GL_CON_22_ATI");
		pushInt(t, GL_CON_23_ATI); newGlobal(t, "GL_CON_23_ATI");
		pushInt(t, GL_CON_24_ATI); newGlobal(t, "GL_CON_24_ATI");
		pushInt(t, GL_CON_25_ATI); newGlobal(t, "GL_CON_25_ATI");
		pushInt(t, GL_CON_26_ATI); newGlobal(t, "GL_CON_26_ATI");
		pushInt(t, GL_CON_27_ATI); newGlobal(t, "GL_CON_27_ATI");
		pushInt(t, GL_CON_28_ATI); newGlobal(t, "GL_CON_28_ATI");
		pushInt(t, GL_CON_29_ATI); newGlobal(t, "GL_CON_29_ATI");
		pushInt(t, GL_CON_30_ATI); newGlobal(t, "GL_CON_30_ATI");
		pushInt(t, GL_CON_31_ATI); newGlobal(t, "GL_CON_31_ATI");
		pushInt(t, GL_MOV_ATI); newGlobal(t, "GL_MOV_ATI");
		pushInt(t, GL_ADD_ATI); newGlobal(t, "GL_ADD_ATI");
		pushInt(t, GL_MUL_ATI); newGlobal(t, "GL_MUL_ATI");
		pushInt(t, GL_SUB_ATI); newGlobal(t, "GL_SUB_ATI");
		pushInt(t, GL_DOT3_ATI); newGlobal(t, "GL_DOT3_ATI");
		pushInt(t, GL_DOT4_ATI); newGlobal(t, "GL_DOT4_ATI");
		pushInt(t, GL_MAD_ATI); newGlobal(t, "GL_MAD_ATI");
		pushInt(t, GL_LERP_ATI); newGlobal(t, "GL_LERP_ATI");
		pushInt(t, GL_CND_ATI); newGlobal(t, "GL_CND_ATI");
		pushInt(t, GL_CND0_ATI); newGlobal(t, "GL_CND0_ATI");
		pushInt(t, GL_DOT2_ADD_ATI); newGlobal(t, "GL_DOT2_ADD_ATI");
		pushInt(t, GL_SECONDARY_INTERPOLATOR_ATI); newGlobal(t, "GL_SECONDARY_INTERPOLATOR_ATI");
		pushInt(t, GL_NUM_FRAGMENT_REGISTERS_ATI); newGlobal(t, "GL_NUM_FRAGMENT_REGISTERS_ATI");
		pushInt(t, GL_NUM_FRAGMENT_CONSTANTS_ATI); newGlobal(t, "GL_NUM_FRAGMENT_CONSTANTS_ATI");
		pushInt(t, GL_NUM_PASSES_ATI); newGlobal(t, "GL_NUM_PASSES_ATI");
		pushInt(t, GL_NUM_INSTRUCTIONS_PER_PASS_ATI); newGlobal(t, "GL_NUM_INSTRUCTIONS_PER_PASS_ATI");
		pushInt(t, GL_NUM_INSTRUCTIONS_TOTAL_ATI); newGlobal(t, "GL_NUM_INSTRUCTIONS_TOTAL_ATI");
		pushInt(t, GL_NUM_INPUT_INTERPOLATOR_COMPONENTS_ATI); newGlobal(t, "GL_NUM_INPUT_INTERPOLATOR_COMPONENTS_ATI");
		pushInt(t, GL_NUM_LOOPBACK_COMPONENTS_ATI); newGlobal(t, "GL_NUM_LOOPBACK_COMPONENTS_ATI");
		pushInt(t, GL_COLOR_ALPHA_PAIRING_ATI); newGlobal(t, "GL_COLOR_ALPHA_PAIRING_ATI");
		pushInt(t, GL_SWIZZLE_STR_ATI); newGlobal(t, "GL_SWIZZLE_STR_ATI");
		pushInt(t, GL_SWIZZLE_STQ_ATI); newGlobal(t, "GL_SWIZZLE_STQ_ATI");
		pushInt(t, GL_SWIZZLE_STR_DR_ATI); newGlobal(t, "GL_SWIZZLE_STR_DR_ATI");
		pushInt(t, GL_SWIZZLE_STQ_DQ_ATI); newGlobal(t, "GL_SWIZZLE_STQ_DQ_ATI");
		pushInt(t, GL_SWIZZLE_STRQ_ATI); newGlobal(t, "GL_SWIZZLE_STRQ_ATI");
		pushInt(t, GL_SWIZZLE_STRQ_DQ_ATI); newGlobal(t, "GL_SWIZZLE_STRQ_DQ_ATI");
		pushInt(t, GL_RED_BIT_ATI); newGlobal(t, "GL_RED_BIT_ATI");
		pushInt(t, GL_GREEN_BIT_ATI); newGlobal(t, "GL_GREEN_BIT_ATI");
		pushInt(t, GL_BLUE_BIT_ATI); newGlobal(t, "GL_BLUE_BIT_ATI");
		pushInt(t, GL_2X_BIT_ATI); newGlobal(t, "2X_BIT_ATI");
		pushInt(t, GL_4X_BIT_ATI); newGlobal(t, "4X_BIT_ATI");
		pushInt(t, GL_8X_BIT_ATI); newGlobal(t, "8X_BIT_ATI");
		pushInt(t, GL_HALF_BIT_ATI); newGlobal(t, "GL_HALF_BIT_ATI");
		pushInt(t, GL_QUARTER_BIT_ATI); newGlobal(t, "GL_QUARTER_BIT_ATI");
		pushInt(t, GL_EIGHTH_BIT_ATI); newGlobal(t, "GL_EIGHTH_BIT_ATI");
		pushInt(t, GL_SATURATE_BIT_ATI); newGlobal(t, "GL_SATURATE_BIT_ATI");
		pushInt(t, GL_COMP_BIT_ATI); newGlobal(t, "GL_COMP_BIT_ATI");
		pushInt(t, GL_NEGATE_BIT_ATI); newGlobal(t, "GL_NEGATE_BIT_ATI");
		pushInt(t, GL_BIAS_BIT_ATI); newGlobal(t, "GL_BIAS_BIT_ATI");
	}

	if(ATIMapObjectBuffer.isEnabled)
	{
// 		register(t, &wrapGL!(glMapObjectBufferATI), "glMapObjectBufferATI");
		register(t, &wrapGL!(glUnmapObjectBufferATI), "glUnmapObjectBufferATI");
	}

	if(ATIPnTriangles.isEnabled)
	{
		register(t, &wrapGL!(glPNTrianglesiATI), "glPNTrianglesiATI");
		register(t, &wrapGL!(glPNTrianglesfATI), "glPNTrianglesfATI");

		pushInt(t, GL_PN_TRIANGLES_ATI); newGlobal(t, "GL_PN_TRIANGLES_ATI");
		pushInt(t, GL_MAX_PN_TRIANGLES_TESSELATION_LEVEL_ATI); newGlobal(t, "GL_MAX_PN_TRIANGLES_TESSELATION_LEVEL_ATI");
		pushInt(t, GL_PN_TRIANGLES_POINT_MODE_ATI); newGlobal(t, "GL_PN_TRIANGLES_POINT_MODE_ATI");
		pushInt(t, GL_PN_TRIANGLES_NORMAL_MODE_ATI); newGlobal(t, "GL_PN_TRIANGLES_NORMAL_MODE_ATI");
		pushInt(t, GL_PN_TRIANGLES_TESSELATION_LEVEL_ATI); newGlobal(t, "GL_PN_TRIANGLES_TESSELATION_LEVEL_ATI");
		pushInt(t, GL_PN_TRIANGLES_POINT_MODE_LINEAR_ATI); newGlobal(t, "GL_PN_TRIANGLES_POINT_MODE_LINEAR_ATI");
		pushInt(t, GL_PN_TRIANGLES_POINT_MODE_CUBIC_ATI); newGlobal(t, "GL_PN_TRIANGLES_POINT_MODE_CUBIC_ATI");
		pushInt(t, GL_PN_TRIANGLES_NORMAL_MODE_LINEAR_ATI); newGlobal(t, "GL_PN_TRIANGLES_NORMAL_MODE_LINEAR_ATI");
		pushInt(t, GL_PN_TRIANGLES_NORMAL_MODE_QUADRATIC_ATI); newGlobal(t, "GL_PN_TRIANGLES_NORMAL_MODE_QUADRATIC_ATI");
	}

	if(ATISeparateStencil.isEnabled)
	{
		register(t, &wrapGL!(glStencilOpSeparateATI), "glStencilOpSeparateATI");
		register(t, &wrapGL!(glStencilFuncSeparateATI), "glStencilFuncSeparateATI");

		pushInt(t, GL_STENCIL_BACK_FUNC_ATI); newGlobal(t, "GL_STENCIL_BACK_FUNC_ATI");
		pushInt(t, GL_STENCIL_BACK_FAIL_ATI); newGlobal(t, "GL_STENCIL_BACK_FAIL_ATI");
		pushInt(t, GL_STENCIL_BACK_PASS_DEPTH_FAIL_ATI); newGlobal(t, "GL_STENCIL_BACK_PASS_DEPTH_FAIL_ATI");
		pushInt(t, GL_STENCIL_BACK_PASS_DEPTH_PASS_ATI); newGlobal(t, "GL_STENCIL_BACK_PASS_DEPTH_PASS_ATI");
	}

	if(ATITextFragmentShader.isEnabled)
	{
		pushInt(t, GL_TEXT_FRAGMENT_SHADER_ATI); newGlobal(t, "GL_TEXT_FRAGMENT_SHADER_ATI");
	}

	if(ATITextureCompression3dc.isEnabled)
	{
		pushInt(t, GL_COMPRESSED_LUMINANCE_ALPHA_3DC_ATI); newGlobal(t, "GL_COMPRESSED_LUMINANCE_ALPHA_3DC_ATI");
	}

	if(ATITextureEnvCombine3.isEnabled)
	{
		pushInt(t, GL_MODULATE_ADD_ATI); newGlobal(t, "GL_MODULATE_ADD_ATI");
		pushInt(t, GL_MODULATE_SIGNED_ADD_ATI); newGlobal(t, "GL_MODULATE_SIGNED_ADD_ATI");
		pushInt(t, GL_MODULATE_SUBTRACT_ATI); newGlobal(t, "GL_MODULATE_SUBTRACT_ATI");
	}

	if(ATITextureFloat.isEnabled)
	{
		pushInt(t, GL_RGBA_FLOAT32_ATI); newGlobal(t, "GL_RGBA_FLOAT32_ATI");
		pushInt(t, GL_RGB_FLOAT32_ATI); newGlobal(t, "GL_RGB_FLOAT32_ATI");
		pushInt(t, GL_ALPHA_FLOAT32_ATI); newGlobal(t, "GL_ALPHA_FLOAT32_ATI");
		pushInt(t, GL_INTENSITY_FLOAT32_ATI); newGlobal(t, "GL_INTENSITY_FLOAT32_ATI");
		pushInt(t, GL_LUMINANCE_FLOAT32_ATI); newGlobal(t, "GL_LUMINANCE_FLOAT32_ATI");
		pushInt(t, GL_LUMINANCE_ALPHA_FLOAT32_ATI); newGlobal(t, "GL_LUMINANCE_ALPHA_FLOAT32_ATI");
		pushInt(t, GL_RGBA_FLOAT16_ATI); newGlobal(t, "GL_RGBA_FLOAT16_ATI");
		pushInt(t, GL_RGB_FLOAT16_ATI); newGlobal(t, "GL_RGB_FLOAT16_ATI");
		pushInt(t, GL_ALPHA_FLOAT16_ATI); newGlobal(t, "GL_ALPHA_FLOAT16_ATI");
		pushInt(t, GL_INTENSITY_FLOAT16_ATI); newGlobal(t, "GL_INTENSITY_FLOAT16_ATI");
		pushInt(t, GL_LUMINANCE_FLOAT16_ATI); newGlobal(t, "GL_LUMINANCE_FLOAT16_ATI");
		pushInt(t, GL_LUMINANCE_ALPHA_FLOAT16_ATI); newGlobal(t, "GL_LUMINANCE_ALPHA_FLOAT16_ATI");
	}

	if(ATITextureMirrorOnce.isEnabled)
	{
		pushInt(t, GL_MIRROR_CLAMP_ATI); newGlobal(t, "GL_MIRROR_CLAMP_ATI");
		pushInt(t, GL_MIRROR_CLAMP_TO_EDGE_ATI); newGlobal(t, "GL_MIRROR_CLAMP_TO_EDGE_ATI");
	}

	if(ATIVertexArrayObject.isEnabled)
	{
		register(t, &wrapGL!(glNewObjectBufferATI), "glNewObjectBufferATI");
		register(t, &wrapGL!(glIsObjectBufferATI), "glIsObjectBufferATI");
		register(t, &wrapGL!(glUpdateObjectBufferATI), "glUpdateObjectBufferATI");
		register(t, &wrapGL!(glGetObjectBufferfvATI), "glGetObjectBufferfvATI");
		register(t, &wrapGL!(glGetObjectBufferivATI), "glGetObjectBufferivATI");
		register(t, &wrapGL!(glFreeObjectBufferATI), "glFreeObjectBufferATI");
		register(t, &wrapGL!(glArrayObjectATI), "glArrayObjectATI");
		register(t, &wrapGL!(glGetArrayObjectfvATI), "glGetArrayObjectfvATI");
		register(t, &wrapGL!(glGetArrayObjectivATI), "glGetArrayObjectivATI");
		register(t, &wrapGL!(glVariantArrayObjectATI), "glVariantArrayObjectATI");
		register(t, &wrapGL!(glGetVariantArrayObjectfvATI), "glGetVariantArrayObjectfvATI");
		register(t, &wrapGL!(glGetVariantArrayObjectivATI), "glGetVariantArrayObjectivATI");

		pushInt(t, GL_STATIC_ATI); newGlobal(t, "GL_STATIC_ATI");
		pushInt(t, GL_DYNAMIC_ATI); newGlobal(t, "GL_DYNAMIC_ATI");
		pushInt(t, GL_PRESERVE_ATI); newGlobal(t, "GL_PRESERVE_ATI");
		pushInt(t, GL_DISCARD_ATI); newGlobal(t, "GL_DISCARD_ATI");
		pushInt(t, GL_OBJECT_BUFFER_SIZE_ATI); newGlobal(t, "GL_OBJECT_BUFFER_SIZE_ATI");
		pushInt(t, GL_OBJECT_BUFFER_USAGE_ATI); newGlobal(t, "GL_OBJECT_BUFFER_USAGE_ATI");
		pushInt(t, GL_ARRAY_OBJECT_BUFFER_ATI); newGlobal(t, "GL_ARRAY_OBJECT_BUFFER_ATI");
		pushInt(t, GL_ARRAY_OBJECT_OFFSET_ATI); newGlobal(t, "GL_ARRAY_OBJECT_OFFSET_ATI");
	}

	if(ATIVertexAttribArrayObject.isEnabled)
	{
		register(t, &wrapGL!(glVertexAttribArrayObjectATI), "glVertexAttribArrayObjectATI");
		register(t, &wrapGL!(glGetVertexAttribArrayObjectfvATI), "glGetVertexAttribArrayObjectfvATI");
		register(t, &wrapGL!(glGetVertexAttribArrayObjectivATI), "glGetVertexAttribArrayObjectivATI");
	}

	if(ATIVertexStreams.isEnabled)
	{
		register(t, &wrapGL!(glVertexStream1sATI), "glVertexStream1sATI");
		register(t, &wrapGL!(glVertexStream1svATI), "glVertexStream1svATI");
		register(t, &wrapGL!(glVertexStream1iATI), "glVertexStream1iATI");
		register(t, &wrapGL!(glVertexStream1ivATI), "glVertexStream1ivATI");
		register(t, &wrapGL!(glVertexStream1fATI), "glVertexStream1fATI");
		register(t, &wrapGL!(glVertexStream1fvATI), "glVertexStream1fvATI");
		register(t, &wrapGL!(glVertexStream1dATI), "glVertexStream1dATI");
		register(t, &wrapGL!(glVertexStream1dvATI), "glVertexStream1dvATI");

		register(t, &wrapGL!(glVertexStream2sATI), "glVertexStream2sATI");
		register(t, &wrapGL!(glVertexStream2svATI), "glVertexStream2svATI");
		register(t, &wrapGL!(glVertexStream2iATI), "glVertexStream2iATI");
		register(t, &wrapGL!(glVertexStream2ivATI), "glVertexStream2ivATI");
		register(t, &wrapGL!(glVertexStream2fATI), "glVertexStream2fATI");
		register(t, &wrapGL!(glVertexStream2fvATI), "glVertexStream2fvATI");
		register(t, &wrapGL!(glVertexStream2dATI), "glVertexStream2dATI");
		register(t, &wrapGL!(glVertexStream2dvATI), "glVertexStream2dvATI");

		register(t, &wrapGL!(glVertexStream3sATI), "glVertexStream3sATI");
		register(t, &wrapGL!(glVertexStream3svATI), "glVertexStream3svATI");
		register(t, &wrapGL!(glVertexStream3iATI), "glVertexStream3iATI");
		register(t, &wrapGL!(glVertexStream3ivATI), "glVertexStream3ivATI");
		register(t, &wrapGL!(glVertexStream3fATI), "glVertexStream3fATI");
		register(t, &wrapGL!(glVertexStream3fvATI), "glVertexStream3fvATI");
		register(t, &wrapGL!(glVertexStream3dATI), "glVertexStream3dATI");
		register(t, &wrapGL!(glVertexStream3dvATI), "glVertexStream3dvATI");

		register(t, &wrapGL!(glVertexStream4sATI), "glVertexStream4sATI");
		register(t, &wrapGL!(glVertexStream4svATI), "glVertexStream4svATI");
		register(t, &wrapGL!(glVertexStream4iATI), "glVertexStream4iATI");
		register(t, &wrapGL!(glVertexStream4ivATI), "glVertexStream4ivATI");
		register(t, &wrapGL!(glVertexStream4fATI), "glVertexStream4fATI");
		register(t, &wrapGL!(glVertexStream4fvATI), "glVertexStream4fvATI");
		register(t, &wrapGL!(glVertexStream4dATI), "glVertexStream4dATI");
		register(t, &wrapGL!(glVertexStream4dvATI), "glVertexStream4dvATI");

		register(t, &wrapGL!(glNormalStream3bATI), "glNormalStream3bATI");
		register(t, &wrapGL!(glNormalStream3bvATI), "glNormalStream3bvATI");
		register(t, &wrapGL!(glNormalStream3sATI), "glNormalStream3sATI");
		register(t, &wrapGL!(glNormalStream3svATI), "glNormalStream3svATI");
		register(t, &wrapGL!(glNormalStream3iATI), "glNormalStream3iATI");
		register(t, &wrapGL!(glNormalStream3ivATI), "glNormalStream3ivATI");
		register(t, &wrapGL!(glNormalStream3fATI), "glNormalStream3fATI");
		register(t, &wrapGL!(glNormalStream3fvATI), "glNormalStream3fvATI");
		register(t, &wrapGL!(glNormalStream3dATI), "glNormalStream3dATI");
		register(t, &wrapGL!(glNormalStream3dvATI), "glNormalStream3dvATI");

		register(t, &wrapGL!(glClientActiveVertexStreamATI), "glClientActiveVertexStreamATI");
		register(t, &wrapGL!(glVertexBlendEnviATI), "glVertexBlendEnviATI");
		register(t, &wrapGL!(glVertexBlendEnvfATI), "glVertexBlendEnvfATI");

		pushInt(t, GL_MAX_VERTEX_STREAMS_ATI); newGlobal(t, "GL_MAX_VERTEX_STREAMS_ATI");
		pushInt(t, GL_VERTEX_STREAM0_ATI); newGlobal(t, "GL_VERTEX_STREAM0_ATI");
		pushInt(t, GL_VERTEX_STREAM1_ATI); newGlobal(t, "GL_VERTEX_STREAM1_ATI");
		pushInt(t, GL_VERTEX_STREAM2_ATI); newGlobal(t, "GL_VERTEX_STREAM2_ATI");
		pushInt(t, GL_VERTEX_STREAM3_ATI); newGlobal(t, "GL_VERTEX_STREAM3_ATI");
		pushInt(t, GL_VERTEX_STREAM4_ATI); newGlobal(t, "GL_VERTEX_STREAM4_ATI");
		pushInt(t, GL_VERTEX_STREAM5_ATI); newGlobal(t, "GL_VERTEX_STREAM5_ATI");
		pushInt(t, GL_VERTEX_STREAM6_ATI); newGlobal(t, "GL_VERTEX_STREAM6_ATI");
		pushInt(t, GL_VERTEX_STREAM7_ATI); newGlobal(t, "GL_VERTEX_STREAM7_ATI");
		pushInt(t, GL_VERTEX_SOURCE_ATI); newGlobal(t, "GL_VERTEX_SOURCE_ATI");
	}

	// EXT
	if(EXTCgShader.isEnabled)
	{
		pushInt(t, GL_CG_VERTEX_SHADER_EXT); newGlobal(t, "GL_CG_VERTEX_SHADER_EXT");
		pushInt(t, GL_CG_FRAGMENT_SHADER_EXT); newGlobal(t, "GL_CG_FRAGMENT_SHADER_EXT");
	}

	if(EXTAbgr.isEnabled)
	{
		pushInt(t, GL_ABGR_EXT); newGlobal(t, "GL_ABGR_EXT");
	}

	if(EXTBgra.isEnabled)
	{
		pushInt(t, GL_BGR_EXT); newGlobal(t, "GL_BGR_EXT");
		pushInt(t, GL_BGRA_EXT); newGlobal(t, "GL_BGRA_EXT");
	}

	if(EXTBindableUniform.isEnabled)
	{
		register(t, &wrapGL!(glUniformBufferEXT), "glUniformBufferEXT");
		register(t, &wrapGL!(glGetUniformBufferSizeEXT), "glGetUniformBufferSizeEXT");
		register(t, &wrapGL!(glGetUniformOffsetEXT), "glGetUniformOffsetEXT");

		pushInt(t, GL_MAX_VERTEX_BINDABLE_UNIFORMS_EXT); newGlobal(t, "GL_MAX_VERTEX_BINDABLE_UNIFORMS_EXT");
		pushInt(t, GL_MAX_FRAGMENT_BINDABLE_UNIFORMS_EXT); newGlobal(t, "GL_MAX_FRAGMENT_BINDABLE_UNIFORMS_EXT");
		pushInt(t, GL_MAX_GEOMETRY_BINDABLE_UNIFORMS_EXT); newGlobal(t, "GL_MAX_GEOMETRY_BINDABLE_UNIFORMS_EXT");
		pushInt(t, GL_MAX_BINDABLE_UNIFORM_SIZE_EXT); newGlobal(t, "GL_MAX_BINDABLE_UNIFORM_SIZE_EXT");
		pushInt(t, GL_UNIFORM_BUFFER_EXT); newGlobal(t, "GL_UNIFORM_BUFFER_EXT");
		pushInt(t, GL_UNIFORM_BUFFER_BINDING_EXT); newGlobal(t, "GL_UNIFORM_BUFFER_BINDING_EXT");
	}

	if(EXTBlendColor.isEnabled)
	{
		register(t, &wrapGL!(glBlendColorEXT), "glBlendColorEXT");

		pushInt(t, GL_CONSTANT_COLOR_EXT); newGlobal(t, "GL_CONSTANT_COLOR_EXT");
		pushInt(t, GL_ONE_MINUS_CONSTANT_COLOR_EXT); newGlobal(t, "GL_ONE_MINUS_CONSTANT_COLOR_EXT");
		pushInt(t, GL_CONSTANT_ALPHA_EXT); newGlobal(t, "GL_CONSTANT_ALPHA_EXT");
		pushInt(t, GL_ONE_MINUS_CONSTANT_ALPHA_EXT); newGlobal(t, "GL_ONE_MINUS_CONSTANT_ALPHA_EXT");
		pushInt(t, GL_BLEND_COLOR_EXT); newGlobal(t, "GL_BLEND_COLOR_EXT");
	}

	if(EXTBlendEquationSeparate.isEnabled)
	{
		register(t, &wrapGL!(glBlendEquationSeparateEXT), "glBlendEquationSeparateEXT");

		pushInt(t, GL_BLEND_EQUATION_RGB_EXT); newGlobal(t, "GL_BLEND_EQUATION_RGB_EXT");
		pushInt(t, GL_BLEND_EQUATION_ALPHA_EXT); newGlobal(t, "GL_BLEND_EQUATION_ALPHA_EXT");
	}

	if(EXTBlendFuncSeparate.isEnabled)
	{
		register(t, &wrapGL!(glBlendFuncSeparateEXT), "glBlendFuncSeparateEXT");

		pushInt(t, GL_BLEND_DST_RGB_EXT); newGlobal(t, "GL_BLEND_DST_RGB_EXT");
		pushInt(t, GL_BLEND_SRC_RGB_EXT); newGlobal(t, "GL_BLEND_SRC_RGB_EXT");
		pushInt(t, GL_BLEND_DST_ALPHA_EXT); newGlobal(t, "GL_BLEND_DST_ALPHA_EXT");
		pushInt(t, GL_BLEND_SRC_ALPHA_EXT); newGlobal(t, "GL_BLEND_SRC_ALPHA_EXT");
	}

	if(EXTBlendMinmax.isEnabled)
	{
		register(t, &wrapGL!(glBlendEquationEXT), "glBlendEquationEXT");

		pushInt(t, GL_FUNC_ADD_EXT); newGlobal(t, "GL_FUNC_ADD_EXT");
		pushInt(t, GL_MIN_EXT); newGlobal(t, "GL_MIN_EXT");
		pushInt(t, GL_MAX_EXT); newGlobal(t, "GL_MAX_EXT");
		pushInt(t, GL_BLEND_EQUATION_EXT); newGlobal(t, "GL_BLEND_EQUATION_EXT");
	}

	if(EXTBlendSubtract.isEnabled)
	{
		pushInt(t, GL_FUNC_SUBTRACT_EXT); newGlobal(t, "GL_FUNC_SUBTRACT_EXT");
		pushInt(t, GL_FUNC_REVERSE_SUBTRACT_EXT); newGlobal(t, "GL_FUNC_REVERSE_SUBTRACT_EXT");
	}

	if(EXTClipVolumeHint.isEnabled)
	{
		pushInt(t, GL_CLIP_VOLUME_CLIPPING_HINT); newGlobal(t, "GL_CLIP_VOLUME_CLIPPING_HINT");
	}

	if(EXTCmyka.isEnabled)
	{
		pushInt(t, GL_CMYK_EXT); newGlobal(t, "GL_CMYK_EXT");
		pushInt(t, GL_CMYKA_EXT); newGlobal(t, "GL_CMYKA_EXT");
		pushInt(t, GL_PACK_CMYK_HINT_EXT); newGlobal(t, "GL_PACK_CMYK_HINT_EXT");
		pushInt(t, GL_UNPACK_CMYK_HINT_EXT); newGlobal(t, "GL_UNPACK_CMYK_HINT_EXT");
	}

	if(EXTColorSubtable.isEnabled)
	{
		register(t, &wrapGL!(glColorSubTableEXT), "glColorSubTableEXT");
		register(t, &wrapGL!(glCopyColorSubTableEXT), "glCopyColorSubTableEXT");
	}

	if(EXTCompiledVertexArray.isEnabled)
	{
		register(t, &wrapGL!(glLockArraysEXT), "glLockArraysEXT");
		register(t, &wrapGL!(glUnlockArraysEXT), "glUnlockArraysEXT");

		pushInt(t, GL_ARRAY_ELEMENT_LOCK_FIRST_EXT); newGlobal(t, "GL_ARRAY_ELEMENT_LOCK_FIRST_EXT");
		pushInt(t, GL_ARRAY_ELEMENT_LOCK_COUNT_EXT); newGlobal(t, "GL_ARRAY_ELEMENT_LOCK_COUNT_EXT");
	}

	if(EXTConvolution.isEnabled)
	{
		register(t, &wrapGL!(glConvolutionFilter1DEXT), "glConvolutionFilter1DEXT");
		register(t, &wrapGL!(glConvolutionFilter2DEXT), "glConvolutionFilter2DEXT");
		register(t, &wrapGL!(glConvolutionParameterfEXT), "glConvolutionParameterfEXT");
		register(t, &wrapGL!(glConvolutionParameterfvEXT), "glConvolutionParameterfvEXT");
		register(t, &wrapGL!(glConvolutionParameteriEXT), "glConvolutionParameteriEXT");
		register(t, &wrapGL!(glConvolutionParameterivEXT), "glConvolutionParameterivEXT");
		register(t, &wrapGL!(glCopyConvolutionFilter1DEXT), "glCopyConvolutionFilter1DEXT");
		register(t, &wrapGL!(glCopyConvolutionFilter2DEXT), "glCopyConvolutionFilter2DEXT");
		register(t, &wrapGL!(glGetConvolutionFilterEXT), "glGetConvolutionFilterEXT");
		register(t, &wrapGL!(glGetConvolutionParameterfvEXT), "glGetConvolutionParameterfvEXT");
		register(t, &wrapGL!(glGetConvolutionParameterivEXT), "glGetConvolutionParameterivEXT");
		register(t, &wrapGL!(glGetSeparableFilterEXT), "glGetSeparableFilterEXT");
		register(t, &wrapGL!(glSeparableFilter2DEXT), "glSeparableFilter2DEXT");

		pushInt(t, GL_CONVOLUTION_1D_EXT); newGlobal(t, "GL_CONVOLUTION_1D_EXT");
		pushInt(t, GL_CONVOLUTION_2D_EXT); newGlobal(t, "GL_CONVOLUTION_2D_EXT");
		pushInt(t, GL_SEPARABLE_2D_EXT); newGlobal(t, "GL_SEPARABLE_2D_EXT");
		pushInt(t, GL_CONVOLUTION_BORDER_MODE_EXT); newGlobal(t, "GL_CONVOLUTION_BORDER_MODE_EXT");
		pushInt(t, GL_CONVOLUTION_FILTER_SCALE_EXT); newGlobal(t, "GL_CONVOLUTION_FILTER_SCALE_EXT");
		pushInt(t, GL_CONVOLUTION_FILTER_BIAS_EXT); newGlobal(t, "GL_CONVOLUTION_FILTER_BIAS_EXT");
		pushInt(t, GL_REDUCE_EXT); newGlobal(t, "GL_REDUCE_EXT");
		pushInt(t, GL_CONVOLUTION_FORMAT_EXT); newGlobal(t, "GL_CONVOLUTION_FORMAT_EXT");
		pushInt(t, GL_CONVOLUTION_WIDTH_EXT); newGlobal(t, "GL_CONVOLUTION_WIDTH_EXT");
		pushInt(t, GL_CONVOLUTION_HEIGHT_EXT); newGlobal(t, "GL_CONVOLUTION_HEIGHT_EXT");
		pushInt(t, GL_MAX_CONVOLUTION_WIDTH_EXT); newGlobal(t, "GL_MAX_CONVOLUTION_WIDTH_EXT");
		pushInt(t, GL_MAX_CONVOLUTION_HEIGHT_EXT); newGlobal(t, "GL_MAX_CONVOLUTION_HEIGHT_EXT");
		pushInt(t, GL_POST_CONVOLUTION_RED_SCALE_EXT); newGlobal(t, "GL_POST_CONVOLUTION_RED_SCALE_EXT");
		pushInt(t, GL_POST_CONVOLUTION_GREEN_SCALE_EXT); newGlobal(t, "GL_POST_CONVOLUTION_GREEN_SCALE_EXT");
		pushInt(t, GL_POST_CONVOLUTION_BLUE_SCALE_EXT); newGlobal(t, "GL_POST_CONVOLUTION_BLUE_SCALE_EXT");
		pushInt(t, GL_POST_CONVOLUTION_ALPHA_SCALE_EXT); newGlobal(t, "GL_POST_CONVOLUTION_ALPHA_SCALE_EXT");
		pushInt(t, GL_POST_CONVOLUTION_RED_BIAS_EXT); newGlobal(t, "GL_POST_CONVOLUTION_RED_BIAS_EXT");
		pushInt(t, GL_POST_CONVOLUTION_GREEN_BIAS_EXT); newGlobal(t, "GL_POST_CONVOLUTION_GREEN_BIAS_EXT");
		pushInt(t, GL_POST_CONVOLUTION_BLUE_BIAS_EXT); newGlobal(t, "GL_POST_CONVOLUTION_BLUE_BIAS_EXT");
		pushInt(t, GL_POST_CONVOLUTION_ALPHA_BIAS_EXT); newGlobal(t, "GL_POST_CONVOLUTION_ALPHA_BIAS_EXT");
	}

	if(EXTCoordinateFrame.isEnabled)
	{
		register(t, &wrapGL!(glBinormalPointerEXT), "glBinormalPointerEXT");
		register(t, &wrapGL!(glTangentPointerEXT), "glTangentPointerEXT");

		pushInt(t, GL_TANGENT_ARRAY_EXT); newGlobal(t, "GL_TANGENT_ARRAY_EXT");
		pushInt(t, GL_BINORMAL_ARRAY_EXT); newGlobal(t, "GL_BINORMAL_ARRAY_EXT");
		pushInt(t, GL_CURRENT_TANGENT_EXT); newGlobal(t, "GL_CURRENT_TANGENT_EXT");
		pushInt(t, GL_CURRENT_BINORMAL_EXT); newGlobal(t, "GL_CURRENT_BINORMAL_EXT");
		pushInt(t, GL_TANGENT_ARRAY_TYPE_EXT); newGlobal(t, "GL_TANGENT_ARRAY_TYPE_EXT");
		pushInt(t, GL_TANGENT_ARRAY_STRIDE_EXT); newGlobal(t, "GL_TANGENT_ARRAY_STRIDE_EXT");
		pushInt(t, GL_BINORMAL_ARRAY_TYPE_EXT); newGlobal(t, "GL_BINORMAL_ARRAY_TYPE_EXT");
		pushInt(t, GL_BINORMAL_ARRAY_STRIDE_EXT); newGlobal(t, "GL_BINORMAL_ARRAY_STRIDE_EXT");
		pushInt(t, GL_TANGENT_ARRAY_POINTER_EXT); newGlobal(t, "GL_TANGENT_ARRAY_POINTER_EXT");
		pushInt(t, GL_BINORMAL_ARRAY_POINTER_EXT); newGlobal(t, "GL_BINORMAL_ARRAY_POINTER_EXT");
		pushInt(t, GL_MAP1_TANGENT_EXT); newGlobal(t, "GL_MAP1_TANGENT_EXT");
		pushInt(t, GL_MAP2_TANGENT_EXT); newGlobal(t, "GL_MAP2_TANGENT_EXT");
		pushInt(t, GL_MAP1_BINORMAL_EXT); newGlobal(t, "GL_MAP1_BINORMAL_EXT");
		pushInt(t, GL_MAP2_BINORMAL_EXT); newGlobal(t, "GL_MAP2_BINORMAL_EXT");
	}

	if(EXTCullVertex.isEnabled)
	{
		register(t, &wrapGL!(glCullParameterdvEXT), "glCullParameterdvEXT");
		register(t, &wrapGL!(glCullParameterfvEXT), "glCullParameterfvEXT");

		pushInt(t, GL_CULL_VERTEX_EXT); newGlobal(t, "GL_CULL_VERTEX_EXT");
		pushInt(t, GL_CULL_VERTEX_EYE_POSITION_EXT); newGlobal(t, "GL_CULL_VERTEX_EYE_POSITION_EXT");
		pushInt(t, GL_CULL_VERTEX_OBJECT_POSITION_EXT); newGlobal(t, "GL_CULL_VERTEX_OBJECT_POSITION_EXT");
	}

	if(EXTDepthBoundsTest.isEnabled)
	{
		register(t, &wrapGL!(glDepthBoundsEXT), "glDepthBoundsEXT");

		pushInt(t, GL_DEPTH_BOUNDS_TEST_EXT); newGlobal(t, "GL_DEPTH_BOUNDS_TEST_EXT");
		pushInt(t, GL_DEPTH_BOUNDS_EXT); newGlobal(t, "GL_DEPTH_BOUNDS_EXT");
	}

	if(EXTDrawBuffers2.isEnabled)
	{
		register(t, &wrapGL!(glColorMaskIndexedEXT), "glColorMaskIndexedEXT");
		register(t, &wrapGL!(glDisableIndexedEXT), "glDisableIndexedEXT");
		register(t, &wrapGL!(glEnableIndexedEXT), "glEnableIndexedEXT");
		register(t, &wrapGL!(glGetBooleanIndexedvEXT), "glGetBooleanIndexedvEXT");
		register(t, &wrapGL!(glGetIntegerIndexedvEXT), "glGetIntegerIndexedvEXT");
		register(t, &wrapGL!(glIsEnabledIndexedEXT), "glIsEnabledIndexedEXT");
	}

	if(EXTDrawInstanced.isEnabled)
	{
		register(t, &wrapGL!(glDrawArraysInstancedEXT), "glDrawArraysInstancedEXT");
		register(t, &wrapGL!(glDrawElementsInstancedEXT), "glDrawElementsInstancedEXT");
	}

	if(EXTDrawRangeElements.isEnabled)
	{
		register(t, &wrapGL!(glDrawRangeElementsEXT), "glDrawRangeElementsEXT");

		pushInt(t, GL_MAX_ELEMENTS_VERTICES_EXT); newGlobal(t, "GL_MAX_ELEMENTS_VERTICES_EXT");
		pushInt(t, GL_MAX_ELEMENTS_INDICES_EXT); newGlobal(t, "GL_MAX_ELEMENTS_INDICES_EXT");
	}

	if(EXTFogCoord.isEnabled)
	{
		register(t, &wrapGL!(glFogCoordfEXT), "glFogCoordfEXT");
		register(t, &wrapGL!(glFogCoordfvEXT), "glFogCoordfvEXT");
		register(t, &wrapGL!(glFogCoorddEXT), "glFogCoorddEXT");
		register(t, &wrapGL!(glFogCoorddvEXT), "glFogCoorddvEXT");
		register(t, &wrapGL!(glFogCoordPointerEXT), "glFogCoordPointerEXT");

		pushInt(t, GL_FOG_COORDINATE_SOURCE_EXT); newGlobal(t, "GL_FOG_COORDINATE_SOURCE_EXT");
		pushInt(t, GL_FOG_COORDINATE_EXT); newGlobal(t, "GL_FOG_COORDINATE_EXT");
		pushInt(t, GL_FRAGMENT_DEPTH_EXT); newGlobal(t, "GL_FRAGMENT_DEPTH_EXT");
		pushInt(t, GL_CURRENT_FOG_COORDINATE_EXT); newGlobal(t, "GL_CURRENT_FOG_COORDINATE_EXT");
		pushInt(t, GL_FOG_COORDINATE_ARRAY_TYPE_EXT); newGlobal(t, "GL_FOG_COORDINATE_ARRAY_TYPE_EXT");
		pushInt(t, GL_FOG_COORDINATE_ARRAY_STRIDE_EXT); newGlobal(t, "GL_FOG_COORDINATE_ARRAY_STRIDE_EXT");
		pushInt(t, GL_FOG_COORDINATE_ARRAY_POINTER_EXT); newGlobal(t, "GL_FOG_COORDINATE_ARRAY_POINTER_EXT");
		pushInt(t, GL_FOG_COORDINATE_ARRAY_EXT); newGlobal(t, "GL_FOG_COORDINATE_ARRAY_EXT");
	}

	if(EXT422Pixels.isEnabled)
	{
		pushInt(t, GL_422_EXT); newGlobal(t, "422_EXT");
		pushInt(t, GL_422_REV_EXT); newGlobal(t, "422_REV_EXT");
		pushInt(t, GL_422_AVERAGE_EXT); newGlobal(t, "422_AVERAGE_EXT");
		pushInt(t, GL_422_REV_AVERAGE_EXT); newGlobal(t, "422_REV_AVERAGE_EXT");
	}

	if(EXTFragmentLighting.isEnabled)
	{
		register(t, &wrapGL!(glFragmentColorMaterialEXT), "glFragmentColorMaterialEXT");
		register(t, &wrapGL!(glFragmentLightModelfEXT), "glFragmentLightModelfEXT");
		register(t, &wrapGL!(glFragmentLightModelfvEXT), "glFragmentLightModelfvEXT");
		register(t, &wrapGL!(glFragmentLightModeliEXT), "glFragmentLightModeliEXT");
		register(t, &wrapGL!(glFragmentLightModelivEXT), "glFragmentLightModelivEXT");
		register(t, &wrapGL!(glFragmentLightfEXT), "glFragmentLightfEXT");
		register(t, &wrapGL!(glFragmentLightfvEXT), "glFragmentLightfvEXT");
		register(t, &wrapGL!(glFragmentLightiEXT), "glFragmentLightiEXT");
		register(t, &wrapGL!(glFragmentLightivEXT), "glFragmentLightivEXT");
		register(t, &wrapGL!(glFragmentMaterialfEXT), "glFragmentMaterialfEXT");
		register(t, &wrapGL!(glFragmentMaterialfvEXT), "glFragmentMaterialfvEXT");
		register(t, &wrapGL!(glFragmentMaterialiEXT), "glFragmentMaterialiEXT");
		register(t, &wrapGL!(glFragmentMaterialivEXT), "glFragmentMaterialivEXT");
		register(t, &wrapGL!(glGetFragmentLightfvEXT), "glGetFragmentLightfvEXT");
		register(t, &wrapGL!(glGetFragmentLightivEXT), "glGetFragmentLightivEXT");
		register(t, &wrapGL!(glGetFragmentMaterialfvEXT), "glGetFragmentMaterialfvEXT");
		register(t, &wrapGL!(glGetFragmentMaterialivEXT), "glGetFragmentMaterialivEXT");
		register(t, &wrapGL!(glLightEnviEXT), "glLightEnviEXT");

		pushInt(t, GL_FRAGMENT_LIGHTING_EXT); newGlobal(t, "GL_FRAGMENT_LIGHTING_EXT");
		pushInt(t, GL_FRAGMENT_COLOR_MATERIAL_EXT); newGlobal(t, "GL_FRAGMENT_COLOR_MATERIAL_EXT");
		pushInt(t, GL_FRAGMENT_COLOR_MATERIAL_FACE_EXT); newGlobal(t, "GL_FRAGMENT_COLOR_MATERIAL_FACE_EXT");
		pushInt(t, GL_FRAGMENT_COLOR_MATERIAL_PARAMETER_EXT); newGlobal(t, "GL_FRAGMENT_COLOR_MATERIAL_PARAMETER_EXT");
		pushInt(t, GL_MAX_FRAGMENT_LIGHTS_EXT); newGlobal(t, "GL_MAX_FRAGMENT_LIGHTS_EXT");
		pushInt(t, GL_MAX_ACTIVE_LIGHTS_EXT); newGlobal(t, "GL_MAX_ACTIVE_LIGHTS_EXT");
		pushInt(t, GL_CURRENT_RASTER_NORMAL_EXT); newGlobal(t, "GL_CURRENT_RASTER_NORMAL_EXT");
		pushInt(t, GL_LIGHT_ENV_MODE_EXT); newGlobal(t, "GL_LIGHT_ENV_MODE_EXT");
		pushInt(t, GL_FRAGMENT_LIGHT_MODEL_LOCAL_VIEWER_EXT); newGlobal(t, "GL_FRAGMENT_LIGHT_MODEL_LOCAL_VIEWER_EXT");
		pushInt(t, GL_FRAGMENT_LIGHT_MODEL_TWO_SIDE_EXT); newGlobal(t, "GL_FRAGMENT_LIGHT_MODEL_TWO_SIDE_EXT");
		pushInt(t, GL_FRAGMENT_LIGHT_MODEL_AMBIENT_EXT); newGlobal(t, "GL_FRAGMENT_LIGHT_MODEL_AMBIENT_EXT");
		pushInt(t, GL_FRAGMENT_LIGHT_MODEL_NORMAL_INTERPOLATION_EXT); newGlobal(t, "GL_FRAGMENT_LIGHT_MODEL_NORMAL_INTERPOLATION_EXT");
		pushInt(t, GL_FRAGMENT_LIGHT0_EXT); newGlobal(t, "GL_FRAGMENT_LIGHT0_EXT");
		pushInt(t, GL_FRAGMENT_LIGHT7_EXT); newGlobal(t, "GL_FRAGMENT_LIGHT7_EXT");
	}

	if(EXTFramebufferBlit.isEnabled)
	{
		register(t, &wrapGL!(glBlitFramebufferEXT), "glBlitFramebufferEXT");

		pushInt(t, GL_READ_FRAMEBUFFER_EXT); newGlobal(t, "GL_READ_FRAMEBUFFER_EXT");
		pushInt(t, GL_DRAW_FRAMEBUFFER_EXT); newGlobal(t, "GL_DRAW_FRAMEBUFFER_EXT");
		pushInt(t, GL_READ_FRAMEBUFFER_BINDING_EXT); newGlobal(t, "GL_READ_FRAMEBUFFER_BINDING_EXT");
		pushInt(t, GL_DRAW_FRAMEBUFFER_BINDING_EXT); newGlobal(t, "GL_DRAW_FRAMEBUFFER_BINDING_EXT");
	}

	if(EXTFramebufferMultisample.isEnabled)
	{
		register(t, &wrapGL!(glRenderbufferStorageMultisampleEXT), "glRenderbufferStorageMultisampleEXT");

		pushInt(t, GL_RENDERBUFFER_SAMPLES_EXT); newGlobal(t, "GL_RENDERBUFFER_SAMPLES_EXT");
	}

	if(EXTFramebufferObject.isEnabled)
	{
		register(t, &wrapGL!(glIsRenderbufferEXT), "glIsRenderbufferEXT");
		register(t, &wrapGL!(glBindRenderbufferEXT), "glBindRenderbufferEXT");
		register(t, &wrapGL!(glDeleteRenderbuffersEXT), "glDeleteRenderbuffersEXT");
		register(t, &wrapGL!(glGenRenderbuffersEXT), "glGenRenderbuffersEXT");
		register(t, &wrapGL!(glRenderbufferStorageEXT), "glRenderbufferStorageEXT");
		register(t, &wrapGL!(glGetRenderbufferParameterivEXT), "glGetRenderbufferParameterivEXT");
		register(t, &wrapGL!(glIsFramebufferEXT), "glIsFramebufferEXT");
		register(t, &wrapGL!(glBindFramebufferEXT), "glBindFramebufferEXT");
		register(t, &wrapGL!(glDeleteFramebuffersEXT), "glDeleteFramebuffersEXT");
		register(t, &wrapGL!(glGenFramebuffersEXT), "glGenFramebuffersEXT");
		register(t, &wrapGL!(glCheckFramebufferStatusEXT), "glCheckFramebufferStatusEXT");
		register(t, &wrapGL!(glFramebufferTexture1DEXT), "glFramebufferTexture1DEXT");
		register(t, &wrapGL!(glFramebufferTexture2DEXT), "glFramebufferTexture2DEXT");
		register(t, &wrapGL!(glFramebufferTexture3DEXT), "glFramebufferTexture3DEXT");
		register(t, &wrapGL!(glFramebufferRenderbufferEXT), "glFramebufferRenderbufferEXT");
		register(t, &wrapGL!(glGetFramebufferAttachmentParameterivEXT), "glGetFramebufferAttachmentParameterivEXT");
		register(t, &wrapGL!(glGenerateMipmapEXT), "glGenerateMipmapEXT");

		pushInt(t, GL_FRAMEBUFFER_EXT); newGlobal(t, "GL_FRAMEBUFFER_EXT");
		pushInt(t, GL_RENDERBUFFER_EXT); newGlobal(t, "GL_RENDERBUFFER_EXT");
		pushInt(t, GL_STENCIL_INDEX1_EXT); newGlobal(t, "GL_STENCIL_INDEX1_EXT");
		pushInt(t, GL_STENCIL_INDEX4_EXT); newGlobal(t, "GL_STENCIL_INDEX4_EXT");
		pushInt(t, GL_STENCIL_INDEX8_EXT); newGlobal(t, "GL_STENCIL_INDEX8_EXT");
		pushInt(t, GL_STENCIL_INDEX16_EXT); newGlobal(t, "GL_STENCIL_INDEX16_EXT");
		pushInt(t, GL_RENDERBUFFER_WIDTH_EXT); newGlobal(t, "GL_RENDERBUFFER_WIDTH_EXT");
		pushInt(t, GL_RENDERBUFFER_HEIGHT_EXT); newGlobal(t, "GL_RENDERBUFFER_HEIGHT_EXT");
		pushInt(t, GL_RENDERBUFFER_INTERNAL_FORMAT_EXT); newGlobal(t, "GL_RENDERBUFFER_INTERNAL_FORMAT_EXT");
		pushInt(t, GL_RENDERBUFFER_RED_SIZE_EXT); newGlobal(t, "GL_RENDERBUFFER_RED_SIZE_EXT");
		pushInt(t, GL_RENDERBUFFER_GREEN_SIZE_EXT); newGlobal(t, "GL_RENDERBUFFER_GREEN_SIZE_EXT");
		pushInt(t, GL_RENDERBUFFER_BLUE_SIZE_EXT); newGlobal(t, "GL_RENDERBUFFER_BLUE_SIZE_EXT");
		pushInt(t, GL_RENDERBUFFER_ALPHA_SIZE_EXT); newGlobal(t, "GL_RENDERBUFFER_ALPHA_SIZE_EXT");
		pushInt(t, GL_RENDERBUFFER_DEPTH_SIZE_EXT); newGlobal(t, "GL_RENDERBUFFER_DEPTH_SIZE_EXT");
		pushInt(t, GL_RENDERBUFFER_STENCIL_SIZE_EXT); newGlobal(t, "GL_RENDERBUFFER_STENCIL_SIZE_EXT");
		pushInt(t, GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE_EXT); newGlobal(t, "GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE_EXT");
		pushInt(t, GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME_EXT); newGlobal(t, "GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME_EXT");
		pushInt(t, GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LEVEL_EXT); newGlobal(t, "GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LEVEL_EXT");
		pushInt(t, GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_CUBE_MAP_FACE_EXT); newGlobal(t, "GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_CUBE_MAP_FACE_EXT");
		pushInt(t, GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_3D_ZOFFSET_EXT); newGlobal(t, "GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_3D_ZOFFSET_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT0_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT0_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT1_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT1_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT2_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT2_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT3_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT3_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT4_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT4_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT5_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT5_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT6_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT6_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT7_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT7_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT8_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT8_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT9_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT9_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT10_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT10_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT11_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT11_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT12_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT12_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT13_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT13_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT14_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT14_EXT");
		pushInt(t, GL_COLOR_ATTACHMENT15_EXT); newGlobal(t, "GL_COLOR_ATTACHMENT15_EXT");
		pushInt(t, GL_DEPTH_ATTACHMENT_EXT); newGlobal(t, "GL_DEPTH_ATTACHMENT_EXT");
		pushInt(t, GL_STENCIL_ATTACHMENT_EXT); newGlobal(t, "GL_STENCIL_ATTACHMENT_EXT");
		pushInt(t, GL_FRAMEBUFFER_COMPLETE_EXT); newGlobal(t, "GL_FRAMEBUFFER_COMPLETE_EXT");
		pushInt(t, GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT_EXT); newGlobal(t, "GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT_EXT");
		pushInt(t, GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT_EXT); newGlobal(t, "GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT_EXT");
		pushInt(t, GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS_EXT); newGlobal(t, "GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS_EXT");
		pushInt(t, GL_FRAMEBUFFER_INCOMPLETE_FORMATS_EXT); newGlobal(t, "GL_FRAMEBUFFER_INCOMPLETE_FORMATS_EXT");
		pushInt(t, GL_FRAMEBUFFER_INCOMPLETE_DRAW_BUFFER_EXT); newGlobal(t, "GL_FRAMEBUFFER_INCOMPLETE_DRAW_BUFFER_EXT");
		pushInt(t, GL_FRAMEBUFFER_INCOMPLETE_READ_BUFFER_EXT); newGlobal(t, "GL_FRAMEBUFFER_INCOMPLETE_READ_BUFFER_EXT");
		pushInt(t, GL_FRAMEBUFFER_UNSUPPORTED_EXT); newGlobal(t, "GL_FRAMEBUFFER_UNSUPPORTED_EXT");
		pushInt(t, GL_FRAMEBUFFER_BINDING_EXT); newGlobal(t, "GL_FRAMEBUFFER_BINDING_EXT");
		pushInt(t, GL_RENDERBUFFER_BINDING_EXT); newGlobal(t, "GL_RENDERBUFFER_BINDING_EXT");
		pushInt(t, GL_MAX_COLOR_ATTACHMENTS_EXT); newGlobal(t, "GL_MAX_COLOR_ATTACHMENTS_EXT");
		pushInt(t, GL_MAX_RENDERBUFFER_SIZE_EXT); newGlobal(t, "GL_MAX_RENDERBUFFER_SIZE_EXT");
		pushInt(t, GL_INVALID_FRAMEBUFFER_OPERATION_EXT); newGlobal(t, "GL_INVALID_FRAMEBUFFER_OPERATION_EXT");
	}

	if(EXTFramebufferSRGB.isEnabled)
	{
		pushInt(t, GL_FRAMEBUFFER_SRGB_EXT); newGlobal(t, "GL_FRAMEBUFFER_SRGB_EXT");
		pushInt(t, GL_FRAMEBUFFER_SRGB_CAPABLE_EXT); newGlobal(t, "GL_FRAMEBUFFER_SRGB_CAPABLE_EXT");
	}

	if(EXTGeometryShader4.isEnabled)
	{
		register(t, &wrapGL!(glFramebufferTextureEXT), "glFramebufferTextureEXT");
		register(t, &wrapGL!(glFramebufferTextureFaceEXT), "glFramebufferTextureFaceEXT");
		register(t, &wrapGL!(glFramebufferTextureLayerEXT), "glFramebufferTextureLayerEXT");
		register(t, &wrapGL!(glProgramParameteriEXT), "glProgramParameteriEXT");

		pushInt(t, GL_LINES_ADJACENCY_EXT); newGlobal(t, "GL_LINES_ADJACENCY_EXT");
		pushInt(t, GL_LINE_STRIP_ADJACENCY_EXT); newGlobal(t, "GL_LINE_STRIP_ADJACENCY_EXT");
		pushInt(t, GL_TRIANGLES_ADJACENCY_EXT); newGlobal(t, "GL_TRIANGLES_ADJACENCY_EXT");
		pushInt(t, GL_TRIANGLE_STRIP_ADJACENCY_EXT); newGlobal(t, "GL_TRIANGLE_STRIP_ADJACENCY_EXT");
		pushInt(t, GL_PROGRAM_POINT_SIZE_EXT); newGlobal(t, "GL_PROGRAM_POINT_SIZE_EXT");
		pushInt(t, GL_MAX_VARYING_COMPONENTS_EXT); newGlobal(t, "GL_MAX_VARYING_COMPONENTS_EXT");
		pushInt(t, GL_MAX_GEOMETRY_TEXTURE_IMAGE_UNITS_EXT); newGlobal(t, "GL_MAX_GEOMETRY_TEXTURE_IMAGE_UNITS_EXT");
		pushInt(t, GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LAYER_EXT); newGlobal(t, "GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LAYER_EXT");
		pushInt(t, GL_FRAMEBUFFER_ATTACHMENT_LAYERED_EXT); newGlobal(t, "GL_FRAMEBUFFER_ATTACHMENT_LAYERED_EXT");
		pushInt(t, GL_FRAMEBUFFER_INCOMPLETE_LAYER_TARGETS_EXT); newGlobal(t, "GL_FRAMEBUFFER_INCOMPLETE_LAYER_TARGETS_EXT");
		pushInt(t, GL_FRAMEBUFFER_INCOMPLETE_LAYER_COUNT_EXT); newGlobal(t, "GL_FRAMEBUFFER_INCOMPLETE_LAYER_COUNT_EXT");
		pushInt(t, GL_GEOMETRY_SHADER_EXT); newGlobal(t, "GL_GEOMETRY_SHADER_EXT");
		pushInt(t, GL_GEOMETRY_VERTICES_OUT_EXT); newGlobal(t, "GL_GEOMETRY_VERTICES_OUT_EXT");
		pushInt(t, GL_GEOMETRY_INPUT_TYPE_EXT); newGlobal(t, "GL_GEOMETRY_INPUT_TYPE_EXT");
		pushInt(t, GL_GEOMETRY_OUTPUT_TYPE_EXT); newGlobal(t, "GL_GEOMETRY_OUTPUT_TYPE_EXT");
		pushInt(t, GL_MAX_GEOMETRY_VARYING_COMPONENTS_EXT); newGlobal(t, "GL_MAX_GEOMETRY_VARYING_COMPONENTS_EXT");
		pushInt(t, GL_MAX_VERTEX_VARYING_COMPONENTS_EXT); newGlobal(t, "GL_MAX_VERTEX_VARYING_COMPONENTS_EXT");
		pushInt(t, GL_MAX_GEOMETRY_UNIFORM_COMPONENTS_EXT); newGlobal(t, "GL_MAX_GEOMETRY_UNIFORM_COMPONENTS_EXT");
		pushInt(t, GL_MAX_GEOMETRY_OUTPUT_VERTICES_EXT); newGlobal(t, "GL_MAX_GEOMETRY_OUTPUT_VERTICES_EXT");
		pushInt(t, GL_MAX_GEOMETRY_TOTAL_OUTPUT_COMPONENTS_EXT); newGlobal(t, "GL_MAX_GEOMETRY_TOTAL_OUTPUT_COMPONENTS_EXT");
	}

	if(EXTGpuProgramParameters.isEnabled)
	{
		register(t, &wrapGL!(glProgramEnvParameters4fvEXT), "glProgramEnvParameters4fvEXT");
		register(t, &wrapGL!(glProgramLocalParameters4fvEXT), "glProgramLocalParameters4fvEXT");
	}

	if(EXTGpuShader4.isEnabled)
	{
		register(t, &wrapGL!(glBindFragDataLocationEXT), "glBindFragDataLocationEXT");
		register(t, &wrapGL!(glGetFragDataLocationEXT), "glGetFragDataLocationEXT");
		register(t, &wrapGL!(glGetUniformuivEXT), "glGetUniformuivEXT");
		register(t, &wrapGL!(glGetVertexAttribIivEXT), "glGetVertexAttribIivEXT");
		register(t, &wrapGL!(glGetVertexAttribIuivEXT), "glGetVertexAttribIuivEXT");
		register(t, &wrapGL!(glUniform1uiEXT), "glUniform1uiEXT");
		register(t, &wrapGL!(glUniform1uivEXT), "glUniform1uivEXT");
		register(t, &wrapGL!(glUniform2uiEXT), "glUniform2uiEXT");
		register(t, &wrapGL!(glUniform2uivEXT), "glUniform2uivEXT");
		register(t, &wrapGL!(glUniform3uiEXT), "glUniform3uiEXT");
		register(t, &wrapGL!(glUniform3uivEXT), "glUniform3uivEXT");
		register(t, &wrapGL!(glUniform4uiEXT), "glUniform4uiEXT");
		register(t, &wrapGL!(glUniform4uivEXT), "glUniform4uivEXT");
		register(t, &wrapGL!(glVertexAttribI1iEXT), "glVertexAttribI1iEXT");
		register(t, &wrapGL!(glVertexAttribI1ivEXT), "glVertexAttribI1ivEXT");
		register(t, &wrapGL!(glVertexAttribI1uiEXT), "glVertexAttribI1uiEXT");
		register(t, &wrapGL!(glVertexAttribI1uivEXT), "glVertexAttribI1uivEXT");
		register(t, &wrapGL!(glVertexAttribI2iEXT), "glVertexAttribI2iEXT");
		register(t, &wrapGL!(glVertexAttribI2ivEXT), "glVertexAttribI2ivEXT");
		register(t, &wrapGL!(glVertexAttribI2uiEXT), "glVertexAttribI2uiEXT");
		register(t, &wrapGL!(glVertexAttribI2uivEXT), "glVertexAttribI2uivEXT");
		register(t, &wrapGL!(glVertexAttribI3iEXT), "glVertexAttribI3iEXT");
		register(t, &wrapGL!(glVertexAttribI3ivEXT), "glVertexAttribI3ivEXT");
		register(t, &wrapGL!(glVertexAttribI3uiEXT), "glVertexAttribI3uiEXT");
		register(t, &wrapGL!(glVertexAttribI3uivEXT), "glVertexAttribI3uivEXT");
		register(t, &wrapGL!(glVertexAttribI4bvEXT), "glVertexAttribI4bvEXT");
		register(t, &wrapGL!(glVertexAttribI4iEXT), "glVertexAttribI4iEXT");
		register(t, &wrapGL!(glVertexAttribI4ivEXT), "glVertexAttribI4ivEXT");
		register(t, &wrapGL!(glVertexAttribI4svEXT), "glVertexAttribI4svEXT");
		register(t, &wrapGL!(glVertexAttribI4ubvEXT), "glVertexAttribI4ubvEXT");
		register(t, &wrapGL!(glVertexAttribI4uiEXT), "glVertexAttribI4uiEXT");
		register(t, &wrapGL!(glVertexAttribI4uivEXT), "glVertexAttribI4uivEXT");
		register(t, &wrapGL!(glVertexAttribI4usvEXT), "glVertexAttribI4usvEXT");
		register(t, &wrapGL!(glVertexAttribIPointerEXT), "glVertexAttribIPointerEXT");

		pushInt(t, GL_VERTEX_ATTRIB_ARRAY_INTEGER_EXT); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY_INTEGER_EXT");
		pushInt(t, GL_SAMPLER_1D_ARRAY_EXT); newGlobal(t, "GL_SAMPLER_1D_ARRAY_EXT");
		pushInt(t, GL_SAMPLER_2D_ARRAY_EXT); newGlobal(t, "GL_SAMPLER_2D_ARRAY_EXT");
		pushInt(t, GL_SAMPLER_BUFFER_EXT); newGlobal(t, "GL_SAMPLER_BUFFER_EXT");
		pushInt(t, GL_SAMPLER_1D_ARRAY_SHADOW_EXT); newGlobal(t, "GL_SAMPLER_1D_ARRAY_SHADOW_EXT");
		pushInt(t, GL_SAMPLER_2D_ARRAY_SHADOW_EXT); newGlobal(t, "GL_SAMPLER_2D_ARRAY_SHADOW_EXT");
		pushInt(t, GL_SAMPLER_CUBE_SHADOW_EXT); newGlobal(t, "GL_SAMPLER_CUBE_SHADOW_EXT");
		pushInt(t, GL_UNSIGNED_INT_VEC2_EXT); newGlobal(t, "GL_UNSIGNED_INT_VEC2_EXT");
		pushInt(t, GL_UNSIGNED_INT_VEC3_EXT); newGlobal(t, "GL_UNSIGNED_INT_VEC3_EXT");
		pushInt(t, GL_UNSIGNED_INT_VEC4_EXT); newGlobal(t, "GL_UNSIGNED_INT_VEC4_EXT");
		pushInt(t, GL_INT_SAMPLER_1D_EXT); newGlobal(t, "GL_INT_SAMPLER_1D_EXT");
		pushInt(t, GL_INT_SAMPLER_2D_EXT); newGlobal(t, "GL_INT_SAMPLER_2D_EXT");
		pushInt(t, GL_INT_SAMPLER_3D_EXT); newGlobal(t, "GL_INT_SAMPLER_3D_EXT");
		pushInt(t, GL_INT_SAMPLER_CUBE_EXT); newGlobal(t, "GL_INT_SAMPLER_CUBE_EXT");
		pushInt(t, GL_INT_SAMPLER_2D_RECT_EXT); newGlobal(t, "GL_INT_SAMPLER_2D_RECT_EXT");
		pushInt(t, GL_INT_SAMPLER_1D_ARRAY_EXT); newGlobal(t, "GL_INT_SAMPLER_1D_ARRAY_EXT");
		pushInt(t, GL_INT_SAMPLER_2D_ARRAY_EXT); newGlobal(t, "GL_INT_SAMPLER_2D_ARRAY_EXT");
		pushInt(t, GL_INT_SAMPLER_BUFFER_EXT); newGlobal(t, "GL_INT_SAMPLER_BUFFER_EXT");
		pushInt(t, GL_UNSIGNED_INT_SAMPLER_1D_EXT); newGlobal(t, "GL_UNSIGNED_INT_SAMPLER_1D_EXT");
		pushInt(t, GL_UNSIGNED_INT_SAMPLER_2D_EXT); newGlobal(t, "GL_UNSIGNED_INT_SAMPLER_2D_EXT");
		pushInt(t, GL_UNSIGNED_INT_SAMPLER_3D_EXT); newGlobal(t, "GL_UNSIGNED_INT_SAMPLER_3D_EXT");
		pushInt(t, GL_UNSIGNED_INT_SAMPLER_CUBE_EXT); newGlobal(t, "GL_UNSIGNED_INT_SAMPLER_CUBE_EXT");
		pushInt(t, GL_UNSIGNED_INT_SAMPLER_2D_RECT_EXT); newGlobal(t, "GL_UNSIGNED_INT_SAMPLER_2D_RECT_EXT");
		pushInt(t, GL_UNSIGNED_INT_SAMPLER_1D_ARRAY_EXT); newGlobal(t, "GL_UNSIGNED_INT_SAMPLER_1D_ARRAY_EXT");
		pushInt(t, GL_UNSIGNED_INT_SAMPLER_2D_ARRAY_EXT); newGlobal(t, "GL_UNSIGNED_INT_SAMPLER_2D_ARRAY_EXT");
		pushInt(t, GL_UNSIGNED_INT_SAMPLER_BUFFER_EXT); newGlobal(t, "GL_UNSIGNED_INT_SAMPLER_BUFFER_EXT");
	}

	if(EXTHistogram.isEnabled)
	{
		register(t, &wrapGL!(glGetHistogramEXT), "glGetHistogramEXT");
		register(t, &wrapGL!(glGetHistogramParameterfvEXT), "glGetHistogramParameterfvEXT");
		register(t, &wrapGL!(glGetHistogramParameterivEXT), "glGetHistogramParameterivEXT");
		register(t, &wrapGL!(glGetMinmaxEXT), "glGetMinmaxEXT");
		register(t, &wrapGL!(glGetMinmaxParameterfvEXT), "glGetMinmaxParameterfvEXT");
		register(t, &wrapGL!(glGetMinmaxParameterivEXT), "glGetMinmaxParameterivEXT");
		register(t, &wrapGL!(glHistogramEXT), "glHistogramEXT");
		register(t, &wrapGL!(glMinmaxEXT), "glMinmaxEXT");
		register(t, &wrapGL!(glResetHistogramEXT), "glResetHistogramEXT");
		register(t, &wrapGL!(glResetMinmaxEXT), "glResetMinmaxEXT");

		pushInt(t, GL_HISTOGRAM_EXT); newGlobal(t, "GL_HISTOGRAM_EXT");
		pushInt(t, GL_PROXY_HISTOGRAM_EXT); newGlobal(t, "GL_PROXY_HISTOGRAM_EXT");
		pushInt(t, GL_HISTOGRAM_WIDTH_EXT); newGlobal(t, "GL_HISTOGRAM_WIDTH_EXT");
		pushInt(t, GL_HISTOGRAM_FORMAT_EXT); newGlobal(t, "GL_HISTOGRAM_FORMAT_EXT");
		pushInt(t, GL_HISTOGRAM_RED_SIZE_EXT); newGlobal(t, "GL_HISTOGRAM_RED_SIZE_EXT");
		pushInt(t, GL_HISTOGRAM_GREEN_SIZE_EXT); newGlobal(t, "GL_HISTOGRAM_GREEN_SIZE_EXT");
		pushInt(t, GL_HISTOGRAM_BLUE_SIZE_EXT); newGlobal(t, "GL_HISTOGRAM_BLUE_SIZE_EXT");
		pushInt(t, GL_HISTOGRAM_ALPHA_SIZE_EXT); newGlobal(t, "GL_HISTOGRAM_ALPHA_SIZE_EXT");
		pushInt(t, GL_HISTOGRAM_LUMINANCE_SIZE_EXT); newGlobal(t, "GL_HISTOGRAM_LUMINANCE_SIZE_EXT");
		pushInt(t, GL_HISTOGRAM_SINK_EXT); newGlobal(t, "GL_HISTOGRAM_SINK_EXT");
		pushInt(t, GL_MINMAX_EXT); newGlobal(t, "GL_MINMAX_EXT");
		pushInt(t, GL_MINMAX_FORMAT_EXT); newGlobal(t, "GL_MINMAX_FORMAT_EXT");
		pushInt(t, GL_MINMAX_SINK_EXT); newGlobal(t, "GL_MINMAX_SINK_EXT");
		pushInt(t, GL_TABLE_TOO_LARGE_EXT); newGlobal(t, "GL_TABLE_TOO_LARGE_EXT");
	}

	if(EXTLightTexture.isEnabled)
	{
		register(t, &wrapGL!(glApplyTextureEXT), "glApplyTextureEXT");
		register(t, &wrapGL!(glTextureLightEXT), "glTextureLightEXT");
		register(t, &wrapGL!(glTextureMaterialEXT), "glTextureMaterialEXT");

		pushInt(t, GL_FRAGMENT_MATERIAL_EXT); newGlobal(t, "GL_FRAGMENT_MATERIAL_EXT");
		pushInt(t, GL_FRAGMENT_NORMAL_EXT); newGlobal(t, "GL_FRAGMENT_NORMAL_EXT");
		pushInt(t, GL_FRAGMENT_COLOR_EXT); newGlobal(t, "GL_FRAGMENT_COLOR_EXT");
		pushInt(t, GL_ATTENUATION_EXT); newGlobal(t, "GL_ATTENUATION_EXT");
		pushInt(t, GL_SHADOW_ATTENUATION_EXT); newGlobal(t, "GL_SHADOW_ATTENUATION_EXT");
		pushInt(t, GL_TEXTURE_APPLICATION_MODE_EXT); newGlobal(t, "GL_TEXTURE_APPLICATION_MODE_EXT");
		pushInt(t, GL_TEXTURE_LIGHT_EXT); newGlobal(t, "GL_TEXTURE_LIGHT_EXT");
		pushInt(t, GL_TEXTURE_MATERIAL_FACE_EXT); newGlobal(t, "GL_TEXTURE_MATERIAL_FACE_EXT");
		pushInt(t, GL_TEXTURE_MATERIAL_PARAMETER_EXT); newGlobal(t, "GL_TEXTURE_MATERIAL_PARAMETER_EXT");
	}

	if(EXTMultiDrawArrays.isEnabled)
	{
		register(t, &wrapGL!(glMultiDrawArraysEXT), "glMultiDrawArraysEXT");
		register(t, &wrapGL!(glMultiDrawElementsEXT), "glMultiDrawElementsEXT");
	}

	if(EXTMultiSample.isEnabled)
	{
		register(t, &wrapGL!(glSampleMaskEXT), "glSampleMaskEXT");
		register(t, &wrapGL!(glSamplePatternEXT), "glSamplePatternEXT");

		pushInt(t, GL_MULTISAMPLE_EXT); newGlobal(t, "GL_MULTISAMPLE_EXT");
		pushInt(t, GL_SAMPLE_ALPHA_TO_MASK_EXT); newGlobal(t, "GL_SAMPLE_ALPHA_TO_MASK_EXT");
		pushInt(t, GL_SAMPLE_ALPHA_TO_ONE_EXT); newGlobal(t, "GL_SAMPLE_ALPHA_TO_ONE_EXT");
		pushInt(t, GL_SAMPLE_MASK_EXT); newGlobal(t, "GL_SAMPLE_MASK_EXT");
		pushInt(t, GL_1PASS_EXT); newGlobal(t, "1PASS_EXT");
		pushInt(t, GL_2PASS_0_EXT); newGlobal(t, "2PASS_0_EXT");
		pushInt(t, GL_2PASS_1_EXT); newGlobal(t, "2PASS_1_EXT");
		pushInt(t, GL_4PASS_0_EXT); newGlobal(t, "4PASS_0_EXT");
		pushInt(t, GL_4PASS_1_EXT); newGlobal(t, "4PASS_1_EXT");
		pushInt(t, GL_4PASS_2_EXT); newGlobal(t, "4PASS_2_EXT");
		pushInt(t, GL_4PASS_3_EXT); newGlobal(t, "4PASS_3_EXT");
		pushInt(t, GL_SAMPLE_BUFFERS_EXT); newGlobal(t, "GL_SAMPLE_BUFFERS_EXT");
		pushInt(t, GL_SAMPLES_EXT); newGlobal(t, "GL_SAMPLES_EXT");
		pushInt(t, GL_SAMPLE_MASK_VALUE_EXT); newGlobal(t, "GL_SAMPLE_MASK_VALUE_EXT");
		pushInt(t, GL_SAMPLE_MASK_INVERT_EXT); newGlobal(t, "GL_SAMPLE_MASK_INVERT_EXT");
		pushInt(t, GL_SAMPLE_PATTERN_EXT); newGlobal(t, "GL_SAMPLE_PATTERN_EXT");
	}

	if(EXTPackedDepthStencil.isEnabled)
	{
		pushInt(t, GL_DEPTH_STENCIL_EXT); newGlobal(t, "GL_DEPTH_STENCIL_EXT");
		pushInt(t, GL_UNSIGNED_INT_24_8_EXT); newGlobal(t, "GL_UNSIGNED_INT_24_8_EXT");
		pushInt(t, GL_DEPTH24_STENCIL8_EXT); newGlobal(t, "GL_DEPTH24_STENCIL8_EXT");
		pushInt(t, GL_TEXTURE_STENCIL_SIZE_EXT); newGlobal(t, "GL_TEXTURE_STENCIL_SIZE_EXT");
	}

	if(EXTPackedFloat.isEnabled)
	{
		pushInt(t, GL_R11F_G11F_B10F_EXT); newGlobal(t, "GL_R11F_G11F_B10F_EXT");
		pushInt(t, GL_UNSIGNED_INT_10F_11F_11F_REV_EXT); newGlobal(t, "GL_UNSIGNED_INT_10F_11F_11F_REV_EXT");
		pushInt(t, GL_RGBA_SIGNED_COMPONENTS_EXT); newGlobal(t, "GL_RGBA_SIGNED_COMPONENTS_EXT");
	}

	if(EXTPackedPixels.isEnabled)
	{
		pushInt(t, GL_UNSIGNED_BYTE_3_3_2_EXT); newGlobal(t, "GL_UNSIGNED_BYTE_3_3_2_EXT");
		pushInt(t, GL_UNSIGNED_SHORT_4_4_4_4_EXT); newGlobal(t, "GL_UNSIGNED_SHORT_4_4_4_4_EXT");
		pushInt(t, GL_UNSIGNED_SHORT_5_5_5_1_EXT); newGlobal(t, "GL_UNSIGNED_SHORT_5_5_5_1_EXT");
		pushInt(t, GL_UNSIGNED_INT_8_8_8_8_EXT); newGlobal(t, "GL_UNSIGNED_INT_8_8_8_8_EXT");
		pushInt(t, GL_UNSIGNED_INT_10_10_10_2_EXT); newGlobal(t, "GL_UNSIGNED_INT_10_10_10_2_EXT");
	}

	if(EXTPalettedTexture.isEnabled)
	{
		register(t, &wrapGL!(glColorTableEXT), "glColorTableEXT");
		register(t, &wrapGL!(glGetColorTableEXT), "glGetColorTableEXT");
		register(t, &wrapGL!(glGetColorTableParameterivEXT), "glGetColorTableParameterivEXT");
		register(t, &wrapGL!(glGetColorTableParameterfvEXT), "glGetColorTableParameterfvEXT");

		pushInt(t, GL_COLOR_INDEX1_EXT); newGlobal(t, "GL_COLOR_INDEX1_EXT");
		pushInt(t, GL_COLOR_INDEX2_EXT); newGlobal(t, "GL_COLOR_INDEX2_EXT");
		pushInt(t, GL_COLOR_INDEX4_EXT); newGlobal(t, "GL_COLOR_INDEX4_EXT");
		pushInt(t, GL_COLOR_INDEX8_EXT); newGlobal(t, "GL_COLOR_INDEX8_EXT");
		pushInt(t, GL_COLOR_INDEX12_EXT); newGlobal(t, "GL_COLOR_INDEX12_EXT");
		pushInt(t, GL_COLOR_INDEX16_EXT); newGlobal(t, "GL_COLOR_INDEX16_EXT");
		pushInt(t, GL_TEXTURE_INDEX_SIZE_EXT); newGlobal(t, "GL_TEXTURE_INDEX_SIZE_EXT");
	}

	if(EXTPixelBufferObject.isEnabled)
	{
		pushInt(t, GL_PIXEL_PACK_BUFFER_EXT); newGlobal(t, "GL_PIXEL_PACK_BUFFER_EXT");
		pushInt(t, GL_PIXEL_UNPACK_BUFFER_EXT); newGlobal(t, "GL_PIXEL_UNPACK_BUFFER_EXT");
		pushInt(t, GL_PIXEL_PACK_BUFFER_BINDING_EXT); newGlobal(t, "GL_PIXEL_PACK_BUFFER_BINDING_EXT");
		pushInt(t, GL_PIXEL_UNPACK_BUFFER_BINDING_EXT); newGlobal(t, "GL_PIXEL_UNPACK_BUFFER_BINDING_EXT");
	}

	if(EXTPixelTransform.isEnabled)
	{
		register(t, &wrapGL!(glPixelTransformParameteriEXT), "glPixelTransformParameteriEXT");
		register(t, &wrapGL!(glPixelTransformParameterfEXT), "glPixelTransformParameterfEXT");
		register(t, &wrapGL!(glPixelTransformParameterivEXT), "glPixelTransformParameterivEXT");
		register(t, &wrapGL!(glPixelTransformParameterfvEXT), "glPixelTransformParameterfvEXT");

		pushInt(t, GL_PIXEL_TRANSFORM_2D_EXT); newGlobal(t, "GL_PIXEL_TRANSFORM_2D_EXT");
		pushInt(t, GL_PIXEL_MAG_FILTER_EXT); newGlobal(t, "GL_PIXEL_MAG_FILTER_EXT");
		pushInt(t, GL_PIXEL_MIN_FILTER_EXT); newGlobal(t, "GL_PIXEL_MIN_FILTER_EXT");
		pushInt(t, GL_PIXEL_CUBIC_WEIGHT_EXT); newGlobal(t, "GL_PIXEL_CUBIC_WEIGHT_EXT");
		pushInt(t, GL_CUBIC_EXT); newGlobal(t, "GL_CUBIC_EXT");
		pushInt(t, GL_AVERAGE_EXT); newGlobal(t, "GL_AVERAGE_EXT");
		pushInt(t, GL_PIXEL_TRANSFORM_2D_STACK_DEPTH_EXT); newGlobal(t, "GL_PIXEL_TRANSFORM_2D_STACK_DEPTH_EXT");
		pushInt(t, GL_MAX_PIXEL_TRANSFORM_2D_STACK_DEPTH_EXT); newGlobal(t, "GL_MAX_PIXEL_TRANSFORM_2D_STACK_DEPTH_EXT");
		pushInt(t, GL_PIXEL_TRANSFORM_2D_MATRIX_EXT); newGlobal(t, "GL_PIXEL_TRANSFORM_2D_MATRIX_EXT");
	}

	if(EXTPointParameters.isEnabled)
	{
		register(t, &wrapGL!(glPointParameterfEXT), "glPointParameterfEXT");
		register(t, &wrapGL!(glPointParameterfvEXT), "glPointParameterfvEXT");
	}

	if(EXTRescaleNormal.isEnabled)
	{
		pushInt(t, GL_RESCALE_NORMAL_EXT); newGlobal(t, "GL_RESCALE_NORMAL_EXT");
	}

	if(EXTSceneMarker.isEnabled)
	{
		register(t, &wrapGL!(glBeginSceneEXT), "glBeginSceneEXT");
		register(t, &wrapGL!(glEndSceneEXT), "glEndSceneEXT");
	}

	if(EXTSecondaryColor.isEnabled)
	{
		register(t, &wrapGL!(glSecondaryColor3bEXT), "glSecondaryColor3bEXT");
		register(t, &wrapGL!(glSecondaryColor3bvEXT), "glSecondaryColor3bvEXT");
		register(t, &wrapGL!(glSecondaryColor3dEXT), "glSecondaryColor3dEXT");
		register(t, &wrapGL!(glSecondaryColor3dvEXT), "glSecondaryColor3dvEXT");
		register(t, &wrapGL!(glSecondaryColor3fEXT), "glSecondaryColor3fEXT");
		register(t, &wrapGL!(glSecondaryColor3fvEXT), "glSecondaryColor3fvEXT");
		register(t, &wrapGL!(glSecondaryColor3iEXT), "glSecondaryColor3iEXT");
		register(t, &wrapGL!(glSecondaryColor3ivEXT), "glSecondaryColor3ivEXT");
		register(t, &wrapGL!(glSecondaryColor3sEXT), "glSecondaryColor3sEXT");
		register(t, &wrapGL!(glSecondaryColor3svEXT), "glSecondaryColor3svEXT");
		register(t, &wrapGL!(glSecondaryColor3ubEXT), "glSecondaryColor3ubEXT");
		register(t, &wrapGL!(glSecondaryColor3ubvEXT), "glSecondaryColor3ubvEXT");
		register(t, &wrapGL!(glSecondaryColor3uiEXT), "glSecondaryColor3uiEXT");
		register(t, &wrapGL!(glSecondaryColor3uivEXT), "glSecondaryColor3uivEXT");
		register(t, &wrapGL!(glSecondaryColor3usEXT), "glSecondaryColor3usEXT");
		register(t, &wrapGL!(glSecondaryColor3usvEXT), "glSecondaryColor3usvEXT");
		register(t, &wrapGL!(glSecondaryColorPointerEXT), "glSecondaryColorPointerEXT");

		pushInt(t, GL_COLOR_SUM_EXT); newGlobal(t, "GL_COLOR_SUM_EXT");
		pushInt(t, GL_CURRENT_SECONDARY_COLOR_EXT); newGlobal(t, "GL_CURRENT_SECONDARY_COLOR_EXT");
		pushInt(t, GL_SECONDARY_COLOR_ARRAY_SIZE_EXT); newGlobal(t, "GL_SECONDARY_COLOR_ARRAY_SIZE_EXT");
		pushInt(t, GL_SECONDARY_COLOR_ARRAY_TYPE_EXT); newGlobal(t, "GL_SECONDARY_COLOR_ARRAY_TYPE_EXT");
		pushInt(t, GL_SECONDARY_COLOR_ARRAY_STRIDE_EXT); newGlobal(t, "GL_SECONDARY_COLOR_ARRAY_STRIDE_EXT");
		pushInt(t, GL_SECONDARY_COLOR_ARRAY_POINTER_EXT); newGlobal(t, "GL_SECONDARY_COLOR_ARRAY_POINTER_EXT");
		pushInt(t, GL_SECONDARY_COLOR_ARRAY_EXT); newGlobal(t, "GL_SECONDARY_COLOR_ARRAY_EXT");
	}

	if(EXTSeparateSpecularColor.isEnabled)
	{
		pushInt(t, GL_LIGHT_MODEL_COLOR_CONTROL_EXT); newGlobal(t, "GL_LIGHT_MODEL_COLOR_CONTROL_EXT");
		pushInt(t, GL_SINGLE_COLOR_EXT); newGlobal(t, "GL_SINGLE_COLOR_EXT");
		pushInt(t, GL_SEPARATE_SPECULAR_COLOR_EXT); newGlobal(t, "GL_SEPARATE_SPECULAR_COLOR_EXT");
	}

	if(EXTSharedTexturePalette.isEnabled)
	{
		pushInt(t, GL_SHARED_TEXTURE_PALETTE_EXT); newGlobal(t, "GL_SHARED_TEXTURE_PALETTE_EXT");
	}

	if(EXTStencilClearTag.isEnabled)
	{
		register(t, &wrapGL!(glStencilClearTagEXT), "glStencilClearTagEXT");

		pushInt(t, GL_STENCIL_TAG_BITS_EXT); newGlobal(t, "GL_STENCIL_TAG_BITS_EXT");
		pushInt(t, GL_STENCIL_CLEAR_TAG_VALUE_EXT); newGlobal(t, "GL_STENCIL_CLEAR_TAG_VALUE_EXT");
	}

	if(EXTStencilTwoSide.isEnabled)
	{
		register(t, &wrapGL!(glActiveStencilFaceEXT), "glActiveStencilFaceEXT");

		pushInt(t, GL_STENCIL_TEST_TWO_SIDE_EXT); newGlobal(t, "GL_STENCIL_TEST_TWO_SIDE_EXT");
		pushInt(t, GL_ACTIVE_STENCIL_FACE_EXT); newGlobal(t, "GL_ACTIVE_STENCIL_FACE_EXT");
	}

	if(EXTStencilWrap.isEnabled)
	{
		pushInt(t, GL_INCR_WRAP_EXT); newGlobal(t, "GL_INCR_WRAP_EXT");
		pushInt(t, GL_DECR_WRAP_EXT); newGlobal(t, "GL_DECR_WRAP_EXT");
	}

	if(EXTTexture3D.isEnabled)
	{
		register(t, &wrapGL!(glTexImage3DEXT), "glTexImage3DEXT");
		register(t, &wrapGL!(glTexSubImage3DEXT), "glTexSubImage3DEXT");

		pushInt(t, GL_PACK_SKIP_IMAGES_EXT); newGlobal(t, "GL_PACK_SKIP_IMAGES_EXT");
		pushInt(t, GL_PACK_IMAGE_HEIGHT_EXT); newGlobal(t, "GL_PACK_IMAGE_HEIGHT_EXT");
		pushInt(t, GL_UNPACK_SKIP_IMAGES_EXT); newGlobal(t, "GL_UNPACK_SKIP_IMAGES_EXT");
		pushInt(t, GL_UNPACK_IMAGE_HEIGHT_EXT); newGlobal(t, "GL_UNPACK_IMAGE_HEIGHT_EXT");
		pushInt(t, GL_TEXTURE_3D_EXT); newGlobal(t, "GL_TEXTURE_3D_EXT");
		pushInt(t, GL_PROXY_TEXTURE_3D_EXT); newGlobal(t, "GL_PROXY_TEXTURE_3D_EXT");
		pushInt(t, GL_TEXTURE_DEPTH_EXT); newGlobal(t, "GL_TEXTURE_DEPTH_EXT");
		pushInt(t, GL_TEXTURE_WRAP_R_EXT); newGlobal(t, "GL_TEXTURE_WRAP_R_EXT");
		pushInt(t, GL_MAX_3D_TEXTURE_SIZE_EXT); newGlobal(t, "GL_MAX_3D_TEXTURE_SIZE_EXT");
	}

	if(EXTTextureArray.isEnabled)
	{
		pushInt(t, GL_COMPARE_REF_DEPTH_TO_TEXTURE_EXT); newGlobal(t, "GL_COMPARE_REF_DEPTH_TO_TEXTURE_EXT");
		pushInt(t, GL_MAX_ARRAY_TEXTURE_LAYERS_EXT); newGlobal(t, "GL_MAX_ARRAY_TEXTURE_LAYERS_EXT");
		pushInt(t, GL_TEXTURE_1D_ARRAY_EXT); newGlobal(t, "GL_TEXTURE_1D_ARRAY_EXT");
		pushInt(t, GL_PROXY_TEXTURE_1D_ARRAY_EXT); newGlobal(t, "GL_PROXY_TEXTURE_1D_ARRAY_EXT");
		pushInt(t, GL_TEXTURE_2D_ARRAY_EXT); newGlobal(t, "GL_TEXTURE_2D_ARRAY_EXT");
		pushInt(t, GL_PROXY_TEXTURE_2D_ARRAY_EXT); newGlobal(t, "GL_PROXY_TEXTURE_2D_ARRAY_EXT");
		pushInt(t, GL_TEXTURE_BINDING_1D_ARRAY_EXT); newGlobal(t, "GL_TEXTURE_BINDING_1D_ARRAY_EXT");
		pushInt(t, GL_TEXTURE_BINDING_2D_ARRAY_EXT); newGlobal(t, "GL_TEXTURE_BINDING_2D_ARRAY_EXT");
	}

	if(EXTTextureBufferObject.isEnabled)
	{
		register(t, &wrapGL!(glTexBufferEXT), "glTexBufferEXT");

		pushInt(t, GL_TEXTURE_BUFFER_EXT); newGlobal(t, "GL_TEXTURE_BUFFER_EXT");
		pushInt(t, GL_MAX_TEXTURE_BUFFER_SIZE_EXT); newGlobal(t, "GL_MAX_TEXTURE_BUFFER_SIZE_EXT");
		pushInt(t, GL_TEXTURE_BINDING_BUFFER_EXT); newGlobal(t, "GL_TEXTURE_BINDING_BUFFER_EXT");
		pushInt(t, GL_TEXTURE_BUFFER_DATA_STORE_BINDING_EXT); newGlobal(t, "GL_TEXTURE_BUFFER_DATA_STORE_BINDING_EXT");
		pushInt(t, GL_TEXTURE_BUFFER_FORMAT_EXT); newGlobal(t, "GL_TEXTURE_BUFFER_FORMAT_EXT");
	}

	if(EXTTextureCompressionDxt1.isEnabled)
	{
		pushInt(t, GL_COMPRESSED_RGB_S3TC_DXT1_EXT); newGlobal(t, "GL_COMPRESSED_RGB_S3TC_DXT1_EXT");
		pushInt(t, GL_COMPRESSED_RGBA_S3TC_DXT1_EXT); newGlobal(t, "GL_COMPRESSED_RGBA_S3TC_DXT1_EXT");
	}

	if(EXTTextureCompressionLatc.isEnabled)
	{
		pushInt(t, GL_COMPRESSED_LUMINANCE_LATC1_EXT); newGlobal(t, "GL_COMPRESSED_LUMINANCE_LATC1_EXT");
		pushInt(t, GL_COMPRESSED_SIGNED_LUMINANCE_LATC1_EXT); newGlobal(t, "GL_COMPRESSED_SIGNED_LUMINANCE_LATC1_EXT");
		pushInt(t, GL_COMPRESSED_LUMINANCE_ALPHA_LATC2_EXT); newGlobal(t, "GL_COMPRESSED_LUMINANCE_ALPHA_LATC2_EXT");
		pushInt(t, GL_COMPRESSED_SIGNED_LUMINANCE_ALPHA_LATC2_EXT); newGlobal(t, "GL_COMPRESSED_SIGNED_LUMINANCE_ALPHA_LATC2_EXT");
	}

	if(EXTTextureCompressionRgtc.isEnabled)
	{
		pushInt(t, GL_COMPRESSED_RED_RGTC1_EXT); newGlobal(t, "GL_COMPRESSED_RED_RGTC1_EXT");
		pushInt(t, GL_COMPRESSED_SIGNED_RED_RGTC1_EXT); newGlobal(t, "GL_COMPRESSED_SIGNED_RED_RGTC1_EXT");
		pushInt(t, GL_COMPRESSED_RED_GREEN_RGTC2_EXT); newGlobal(t, "GL_COMPRESSED_RED_GREEN_RGTC2_EXT");
		pushInt(t, GL_COMPRESSED_SIGNED_RED_GREEN_RGTC2_EXT); newGlobal(t, "GL_COMPRESSED_SIGNED_RED_GREEN_RGTC2_EXT");
	}

	if(EXTTextureCompressionS3tc.isEnabled)
	{
		pushInt(t, GL_COMPRESSED_RGBA_S3TC_DXT3_EXT); newGlobal(t, "GL_COMPRESSED_RGBA_S3TC_DXT3_EXT");
		pushInt(t, GL_COMPRESSED_RGBA_S3TC_DXT5_EXT); newGlobal(t, "GL_COMPRESSED_RGBA_S3TC_DXT5_EXT");
	}

	if(EXTTextureCubeMap.isEnabled)
	{
		pushInt(t, GL_NORMAL_MAP_EXT); newGlobal(t, "GL_NORMAL_MAP_EXT");
		pushInt(t, GL_REFLECTION_MAP_EXT); newGlobal(t, "GL_REFLECTION_MAP_EXT");
		pushInt(t, GL_TEXTURE_CUBE_MAP_EXT); newGlobal(t, "GL_TEXTURE_CUBE_MAP_EXT");
		pushInt(t, GL_TEXTURE_BINDING_CUBE_MAP_EXT); newGlobal(t, "GL_TEXTURE_BINDING_CUBE_MAP_EXT");
		pushInt(t, GL_TEXTURE_CUBE_MAP_POSITIVE_X_EXT); newGlobal(t, "GL_TEXTURE_CUBE_MAP_POSITIVE_X_EXT");
		pushInt(t, GL_TEXTURE_CUBE_MAP_NEGATIVE_X_EXT); newGlobal(t, "GL_TEXTURE_CUBE_MAP_NEGATIVE_X_EXT");
		pushInt(t, GL_TEXTURE_CUBE_MAP_POSITIVE_Y_EXT); newGlobal(t, "GL_TEXTURE_CUBE_MAP_POSITIVE_Y_EXT");
		pushInt(t, GL_TEXTURE_CUBE_MAP_NEGATIVE_Y_EXT); newGlobal(t, "GL_TEXTURE_CUBE_MAP_NEGATIVE_Y_EXT");
		pushInt(t, GL_TEXTURE_CUBE_MAP_POSITIVE_Z_EXT); newGlobal(t, "GL_TEXTURE_CUBE_MAP_POSITIVE_Z_EXT");
		pushInt(t, GL_TEXTURE_CUBE_MAP_NEGATIVE_Z_EXT); newGlobal(t, "GL_TEXTURE_CUBE_MAP_NEGATIVE_Z_EXT");
		pushInt(t, GL_PROXY_TEXTURE_CUBE_MAP_EXT); newGlobal(t, "GL_PROXY_TEXTURE_CUBE_MAP_EXT");
		pushInt(t, GL_MAX_CUBE_MAP_TEXTURE_SIZE_EXT); newGlobal(t, "GL_MAX_CUBE_MAP_TEXTURE_SIZE_EXT");
	}

	if(EXTTextureEdgeClamp.isEnabled)
	{
		pushInt(t, GL_CLAMP_TO_EDGE_EXT); newGlobal(t, "GL_CLAMP_TO_EDGE_EXT");
	}

	if(EXTTextureEnvCombine.isEnabled)
	{
		pushInt(t, GL_COMBINE_EXT); newGlobal(t, "GL_COMBINE_EXT");
		pushInt(t, GL_COMBINE_RGB_EXT); newGlobal(t, "GL_COMBINE_RGB_EXT");
		pushInt(t, GL_COMBINE_ALPHA_EXT); newGlobal(t, "GL_COMBINE_ALPHA_EXT");
		pushInt(t, GL_RGB_SCALE_EXT); newGlobal(t, "GL_RGB_SCALE_EXT");
		pushInt(t, GL_ADD_SIGNED_EXT); newGlobal(t, "GL_ADD_SIGNED_EXT");
		pushInt(t, GL_INTERPOLATE_EXT); newGlobal(t, "GL_INTERPOLATE_EXT");
		pushInt(t, GL_CONSTANT_EXT); newGlobal(t, "GL_CONSTANT_EXT");
		pushInt(t, GL_PRIMARY_COLOR_EXT); newGlobal(t, "GL_PRIMARY_COLOR_EXT");
		pushInt(t, GL_PREVIOUS_EXT); newGlobal(t, "GL_PREVIOUS_EXT");
		pushInt(t, GL_SOURCE0_RGB_EXT); newGlobal(t, "GL_SOURCE0_RGB_EXT");
		pushInt(t, GL_SOURCE1_RGB_EXT); newGlobal(t, "GL_SOURCE1_RGB_EXT");
		pushInt(t, GL_SOURCE2_RGB_EXT); newGlobal(t, "GL_SOURCE2_RGB_EXT");
		pushInt(t, GL_SOURCE0_ALPHA_EXT); newGlobal(t, "GL_SOURCE0_ALPHA_EXT");
		pushInt(t, GL_SOURCE1_ALPHA_EXT); newGlobal(t, "GL_SOURCE1_ALPHA_EXT");
		pushInt(t, GL_SOURCE2_ALPHA_EXT); newGlobal(t, "GL_SOURCE2_ALPHA_EXT");
		pushInt(t, GL_OPERAND0_RGB_EXT); newGlobal(t, "GL_OPERAND0_RGB_EXT");
		pushInt(t, GL_OPERAND1_RGB_EXT); newGlobal(t, "GL_OPERAND1_RGB_EXT");
		pushInt(t, GL_OPERAND2_RGB_EXT); newGlobal(t, "GL_OPERAND2_RGB_EXT");
		pushInt(t, GL_OPERAND0_ALPHA_EXT); newGlobal(t, "GL_OPERAND0_ALPHA_EXT");
		pushInt(t, GL_OPERAND1_ALPHA_EXT); newGlobal(t, "GL_OPERAND1_ALPHA_EXT");
		pushInt(t, GL_OPERAND2_ALPHA_EXT); newGlobal(t, "GL_OPERAND2_ALPHA_EXT");
	}

	if(EXTTextureEnvDot3.isEnabled)
	{
		pushInt(t, GL_DOT3_RGB_EXT); newGlobal(t, "GL_DOT3_RGB_EXT");
		pushInt(t, GL_DOT3_RGBA_EXT); newGlobal(t, "GL_DOT3_RGBA_EXT");
	}

	if(EXTTextureFilterAnisotropic.isEnabled)
	{
		pushInt(t, GL_TEXTURE_MAX_ANISOTROPY_EXT); newGlobal(t, "GL_TEXTURE_MAX_ANISOTROPY_EXT");
		pushInt(t, GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT); newGlobal(t, "GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT");
	}

	if(EXTTextureInteger.isEnabled)
	{
		register(t, &wrapGL!(glClearColorIiEXT), "glClearColorIiEXT");
		register(t, &wrapGL!(glClearColorIuiEXT), "glClearColorIuiEXT");
		register(t, &wrapGL!(glGetTexParameterIivEXT), "glGetTexParameterIivEXT");
		register(t, &wrapGL!(glGetTexParameterIuivEXT), "glGetTexParameterIuivEXT");
		register(t, &wrapGL!(glTexParameterIivEXT), "glTexParameterIivEXT");
		register(t, &wrapGL!(glTexParameterIuivEXT), "glTexParameterIuivEXT");

		pushInt(t, GL_RGBA32UI_EXT); newGlobal(t, "GL_RGBA32UI_EXT");
		pushInt(t, GL_RGB32UI_EXT); newGlobal(t, "GL_RGB32UI_EXT");
		pushInt(t, GL_ALPHA32UI_EXT); newGlobal(t, "GL_ALPHA32UI_EXT");
		pushInt(t, GL_INTENSITY32UI_EXT); newGlobal(t, "GL_INTENSITY32UI_EXT");
		pushInt(t, GL_LUMINANCE32UI_EXT); newGlobal(t, "GL_LUMINANCE32UI_EXT");
		pushInt(t, GL_LUMINANCE_ALPHA32UI_EXT); newGlobal(t, "GL_LUMINANCE_ALPHA32UI_EXT");
		pushInt(t, GL_RGBA16UI_EXT); newGlobal(t, "GL_RGBA16UI_EXT");
		pushInt(t, GL_RGB16UI_EXT); newGlobal(t, "GL_RGB16UI_EXT");
		pushInt(t, GL_ALPHA16UI_EXT); newGlobal(t, "GL_ALPHA16UI_EXT");
		pushInt(t, GL_INTENSITY16UI_EXT); newGlobal(t, "GL_INTENSITY16UI_EXT");
		pushInt(t, GL_LUMINANCE16UI_EXT); newGlobal(t, "GL_LUMINANCE16UI_EXT");
		pushInt(t, GL_LUMINANCE_ALPHA16UI_EXT); newGlobal(t, "GL_LUMINANCE_ALPHA16UI_EXT");
		pushInt(t, GL_RGBA8UI_EXT); newGlobal(t, "GL_RGBA8UI_EXT");
		pushInt(t, GL_RGB8UI_EXT); newGlobal(t, "GL_RGB8UI_EXT");
		pushInt(t, GL_ALPHA8UI_EXT); newGlobal(t, "GL_ALPHA8UI_EXT");
		pushInt(t, GL_INTENSITY8UI_EXT); newGlobal(t, "GL_INTENSITY8UI_EXT");
		pushInt(t, GL_LUMINANCE8UI_EXT); newGlobal(t, "GL_LUMINANCE8UI_EXT");
		pushInt(t, GL_LUMINANCE_ALPHA8UI_EXT); newGlobal(t, "GL_LUMINANCE_ALPHA8UI_EXT");
		pushInt(t, GL_RGBA32I_EXT); newGlobal(t, "GL_RGBA32I_EXT");
		pushInt(t, GL_RGB32I_EXT); newGlobal(t, "GL_RGB32I_EXT");
		pushInt(t, GL_ALPHA32I_EXT); newGlobal(t, "GL_ALPHA32I_EXT");
		pushInt(t, GL_INTENSITY32I_EXT); newGlobal(t, "GL_INTENSITY32I_EXT");
		pushInt(t, GL_LUMINANCE32I_EXT); newGlobal(t, "GL_LUMINANCE32I_EXT");
		pushInt(t, GL_LUMINANCE_ALPHA32I_EXT); newGlobal(t, "GL_LUMINANCE_ALPHA32I_EXT");
		pushInt(t, GL_RGBA16I_EXT); newGlobal(t, "GL_RGBA16I_EXT");
		pushInt(t, GL_RGB16I_EXT); newGlobal(t, "GL_RGB16I_EXT");
		pushInt(t, GL_ALPHA16I_EXT); newGlobal(t, "GL_ALPHA16I_EXT");
		pushInt(t, GL_INTENSITY16I_EXT); newGlobal(t, "GL_INTENSITY16I_EXT");
		pushInt(t, GL_LUMINANCE16I_EXT); newGlobal(t, "GL_LUMINANCE16I_EXT");
		pushInt(t, GL_LUMINANCE_ALPHA16I_EXT); newGlobal(t, "GL_LUMINANCE_ALPHA16I_EXT");
		pushInt(t, GL_RGBA8I_EXT); newGlobal(t, "GL_RGBA8I_EXT");
		pushInt(t, GL_RGB8I_EXT); newGlobal(t, "GL_RGB8I_EXT");
		pushInt(t, GL_ALPHA8I_EXT); newGlobal(t, "GL_ALPHA8I_EXT");
		pushInt(t, GL_INTENSITY8I_EXT); newGlobal(t, "GL_INTENSITY8I_EXT");
		pushInt(t, GL_LUMINANCE8I_EXT); newGlobal(t, "GL_LUMINANCE8I_EXT");
		pushInt(t, GL_LUMINANCE_ALPHA8I_EXT); newGlobal(t, "GL_LUMINANCE_ALPHA8I_EXT");
		pushInt(t, GL_RED_INTEGER_EXT); newGlobal(t, "GL_RED_INTEGER_EXT");
		pushInt(t, GL_GREEN_INTEGER_EXT); newGlobal(t, "GL_GREEN_INTEGER_EXT");
		pushInt(t, GL_BLUE_INTEGER_EXT); newGlobal(t, "GL_BLUE_INTEGER_EXT");
		pushInt(t, GL_ALPHA_INTEGER_EXT); newGlobal(t, "GL_ALPHA_INTEGER_EXT");
		pushInt(t, GL_RGB_INTEGER_EXT); newGlobal(t, "GL_RGB_INTEGER_EXT");
		pushInt(t, GL_RGBA_INTEGER_EXT); newGlobal(t, "GL_RGBA_INTEGER_EXT");
		pushInt(t, GL_BGR_INTEGER_EXT); newGlobal(t, "GL_BGR_INTEGER_EXT");
		pushInt(t, GL_BGRA_INTEGER_EXT); newGlobal(t, "GL_BGRA_INTEGER_EXT");
		pushInt(t, GL_LUMINANCE_INTEGER_EXT); newGlobal(t, "GL_LUMINANCE_INTEGER_EXT");
		pushInt(t, GL_LUMINANCE_ALPHA_INTEGER_EXT); newGlobal(t, "GL_LUMINANCE_ALPHA_INTEGER_EXT");
		pushInt(t, GL_RGBA_INTEGER_MODE_EXT); newGlobal(t, "GL_RGBA_INTEGER_MODE_EXT");
	}

	if(EXTTextureLodBias.isEnabled)
	{
		pushInt(t, GL_MAX_TEXTURE_LOD_BIAS_EXT); newGlobal(t, "GL_MAX_TEXTURE_LOD_BIAS_EXT");
		pushInt(t, GL_TEXTURE_FILTER_CONTROL_EXT); newGlobal(t, "GL_TEXTURE_FILTER_CONTROL_EXT");
		pushInt(t, GL_TEXTURE_LOD_BIAS_EXT); newGlobal(t, "GL_TEXTURE_LOD_BIAS_EXT");
	}

	if(EXTTextureMirrorClamp.isEnabled)
	{
		pushInt(t, GL_MIRROR_CLAMP_EXT); newGlobal(t, "GL_MIRROR_CLAMP_EXT");
		pushInt(t, GL_MIRROR_CLAMP_TO_EDGE_EXT); newGlobal(t, "GL_MIRROR_CLAMP_TO_EDGE_EXT");
		pushInt(t, GL_MIRROR_CLAMP_TO_BORDER_EXT); newGlobal(t, "GL_MIRROR_CLAMP_TO_BORDER_EXT");
	}

	if(EXTTexturePerturbNormal.isEnabled)
	{
		register(t, &wrapGL!(glTextureNormalEXT), "glTextureNormalEXT");

		pushInt(t, GL_PERTURB_EXT); newGlobal(t, "GL_PERTURB_EXT");
		pushInt(t, GL_TEXTURE_NORMAL_EXT); newGlobal(t, "GL_TEXTURE_NORMAL_EXT");
	}

	if(EXTTextureRectangle.isEnabled)
	{
		pushInt(t, GL_TEXTURE_RECTANGLE_EXT); newGlobal(t, "GL_TEXTURE_RECTANGLE_EXT");
		pushInt(t, GL_TEXTURE_BINDING_RECTANGLE_EXT); newGlobal(t, "GL_TEXTURE_BINDING_RECTANGLE_EXT");
		pushInt(t, GL_PROXY_TEXTURE_RECTANGLE_EXT); newGlobal(t, "GL_PROXY_TEXTURE_RECTANGLE_EXT");
		pushInt(t, GL_MAX_RECTANGLE_TEXTURE_SIZE_EXT); newGlobal(t, "GL_MAX_RECTANGLE_TEXTURE_SIZE_EXT");
	}

	if(EXTTextureSRGB.isEnabled)
	{
		pushInt(t, GL_SRGB_EXT); newGlobal(t, "GL_SRGB_EXT");
		pushInt(t, GL_SRGB8_EXT); newGlobal(t, "GL_SRGB8_EXT");
		pushInt(t, GL_SRGB_ALPHA_EXT); newGlobal(t, "GL_SRGB_ALPHA_EXT");
		pushInt(t, GL_SRGB8_ALPHA8_EXT); newGlobal(t, "GL_SRGB8_ALPHA8_EXT");
		pushInt(t, GL_SLUMINANCE_ALPHA_EXT); newGlobal(t, "GL_SLUMINANCE_ALPHA_EXT");
		pushInt(t, GL_SLUMINANCE8_ALPHA8_EXT); newGlobal(t, "GL_SLUMINANCE8_ALPHA8_EXT");
		pushInt(t, GL_SLUMINANCE_EXT); newGlobal(t, "GL_SLUMINANCE_EXT");
		pushInt(t, GL_SLUMINANCE8_EXT); newGlobal(t, "GL_SLUMINANCE8_EXT");
		pushInt(t, GL_COMPRESSED_SRGB_EXT); newGlobal(t, "GL_COMPRESSED_SRGB_EXT");
		pushInt(t, GL_COMPRESSED_SRGB_ALPHA_EXT); newGlobal(t, "GL_COMPRESSED_SRGB_ALPHA_EXT");
		pushInt(t, GL_COMPRESSED_SLUMINANCE_EXT); newGlobal(t, "GL_COMPRESSED_SLUMINANCE_EXT");
		pushInt(t, GL_COMPRESSED_SLUMINANCE_ALPHA_EXT); newGlobal(t, "GL_COMPRESSED_SLUMINANCE_ALPHA_EXT");
		pushInt(t, GL_COMPRESSED_SRGB_S3TC_DXT1_EXT); newGlobal(t, "GL_COMPRESSED_SRGB_S3TC_DXT1_EXT");
		pushInt(t, GL_COMPRESSED_SRGB_ALPHA_S3TC_DXT1_EXT); newGlobal(t, "GL_COMPRESSED_SRGB_ALPHA_S3TC_DXT1_EXT");
		pushInt(t, GL_COMPRESSED_SRGB_ALPHA_S3TC_DXT3_EXT); newGlobal(t, "GL_COMPRESSED_SRGB_ALPHA_S3TC_DXT3_EXT");
		pushInt(t, GL_COMPRESSED_SRGB_ALPHA_S3TC_DXT5_EXT); newGlobal(t, "GL_COMPRESSED_SRGB_ALPHA_S3TC_DXT5_EXT");
	}

	if(EXTTimerQuery.isEnabled)
	{
		register(t, &wrapGL!(glGetQueryObjecti64vEXT), "glGetQueryObjecti64vEXT");
		register(t, &wrapGL!(glGetQueryObjectui64vEXT), "glGetQueryObjectui64vEXT");

		pushInt(t, GL_TIME_ELAPSED_EXT); newGlobal(t, "GL_TIME_ELAPSED_EXT");
	}

	if(EXTVertexShader.isEnabled)
	{
		register(t, &wrapGL!(glBeginVertexShaderEXT), "glBeginVertexShaderEXT");
		register(t, &wrapGL!(glEndVertexShaderEXT), "glEndVertexShaderEXT");
		register(t, &wrapGL!(glBindVertexShaderEXT), "glBindVertexShaderEXT");
		register(t, &wrapGL!(glGenVertexShadersEXT), "glGenVertexShadersEXT");
		register(t, &wrapGL!(glDeleteVertexShaderEXT), "glDeleteVertexShaderEXT");
		register(t, &wrapGL!(glShaderOp1EXT), "glShaderOp1EXT");
		register(t, &wrapGL!(glShaderOp2EXT), "glShaderOp2EXT");
		register(t, &wrapGL!(glShaderOp3EXT), "glShaderOp3EXT");
		register(t, &wrapGL!(glSwizzleEXT), "glSwizzleEXT");
		register(t, &wrapGL!(glWriteMaskEXT), "glWriteMaskEXT");
		register(t, &wrapGL!(glInsertComponentEXT), "glInsertComponentEXT");
		register(t, &wrapGL!(glExtractComponentEXT), "glExtractComponentEXT");
		register(t, &wrapGL!(glGenSymbolsEXT), "glGenSymbolsEXT");
		register(t, &wrapGL!(glSetInvariantEXT), "glSetInvariantEXT");
		register(t, &wrapGL!(glSetLocalConstantEXT), "glSetLocalConstantEXT");
		register(t, &wrapGL!(glVariantbvEXT), "glVariantbvEXT");
		register(t, &wrapGL!(glVariantsvEXT), "glVariantsvEXT");
		register(t, &wrapGL!(glVariantivEXT), "glVariantivEXT");
		register(t, &wrapGL!(glVariantfvEXT), "glVariantfvEXT");
		register(t, &wrapGL!(glVariantdvEXT), "glVariantdvEXT");
		register(t, &wrapGL!(glVariantubvEXT), "glVariantubvEXT");
		register(t, &wrapGL!(glVariantusvEXT), "glVariantusvEXT");
		register(t, &wrapGL!(glVariantuivEXT), "glVariantuivEXT");
		register(t, &wrapGL!(glVariantPointerEXT), "glVariantPointerEXT");
		register(t, &wrapGL!(glEnableVariantClientStateEXT), "glEnableVariantClientStateEXT");
		register(t, &wrapGL!(glDisableVariantClientStateEXT), "glDisableVariantClientStateEXT");
		register(t, &wrapGL!(glBindLightParameterEXT), "glBindLightParameterEXT");
		register(t, &wrapGL!(glBindMaterialParameterEXT), "glBindMaterialParameterEXT");
		register(t, &wrapGL!(glBindTexGenParameterEXT), "glBindTexGenParameterEXT");
		register(t, &wrapGL!(glBindTextureUnitParameterEXT), "glBindTextureUnitParameterEXT");
		register(t, &wrapGL!(glBindParameterEXT), "glBindParameterEXT");
		register(t, &wrapGL!(glIsVariantEnabledEXT), "glIsVariantEnabledEXT");
		register(t, &wrapGL!(glGetVariantBooleanvEXT), "glGetVariantBooleanvEXT");
		register(t, &wrapGL!(glGetVariantIntegervEXT), "glGetVariantIntegervEXT");
		register(t, &wrapGL!(glGetVariantFloatvEXT), "glGetVariantFloatvEXT");
		register(t, &wrapGL!(glGetVariantPointervEXT), "glGetVariantPointervEXT");
		register(t, &wrapGL!(glGetInvariantBooleanvEXT), "glGetInvariantBooleanvEXT");
		register(t, &wrapGL!(glGetInvariantIntegervEXT), "glGetInvariantIntegervEXT");
		register(t, &wrapGL!(glGetInvariantFloatvEXT), "glGetInvariantFloatvEXT");
		register(t, &wrapGL!(glGetLocalConstantBooleanvEXT), "glGetLocalConstantBooleanvEXT");
		register(t, &wrapGL!(glGetLocalConstantIntegervEXT), "glGetLocalConstantIntegervEXT");
		register(t, &wrapGL!(glGetLocalConstantFloatvEXT), "glGetLocalConstantFloatvEXT");

		pushInt(t, GL_VERTEX_SHADER_EXT); newGlobal(t, "GL_VERTEX_SHADER_EXT");
		pushInt(t, GL_VERTEX_SHADER_BINDING_EXT); newGlobal(t, "GL_VERTEX_SHADER_BINDING_EXT");
		pushInt(t, GL_OP_INDEX_EXT); newGlobal(t, "GL_OP_INDEX_EXT");
		pushInt(t, GL_OP_NEGATE_EXT); newGlobal(t, "GL_OP_NEGATE_EXT");
		pushInt(t, GL_OP_DOT3_EXT); newGlobal(t, "GL_OP_DOT3_EXT");
		pushInt(t, GL_OP_DOT4_EXT); newGlobal(t, "GL_OP_DOT4_EXT");
		pushInt(t, GL_OP_MUL_EXT); newGlobal(t, "GL_OP_MUL_EXT");
		pushInt(t, GL_OP_ADD_EXT); newGlobal(t, "GL_OP_ADD_EXT");
		pushInt(t, GL_OP_MADD_EXT); newGlobal(t, "GL_OP_MADD_EXT");
		pushInt(t, GL_OP_FRAC_EXT); newGlobal(t, "GL_OP_FRAC_EXT");
		pushInt(t, GL_OP_MAX_EXT); newGlobal(t, "GL_OP_MAX_EXT");
		pushInt(t, GL_OP_MIN_EXT); newGlobal(t, "GL_OP_MIN_EXT");
		pushInt(t, GL_OP_SET_GE_EXT); newGlobal(t, "GL_OP_SET_GE_EXT");
		pushInt(t, GL_OP_SET_LT_EXT); newGlobal(t, "GL_OP_SET_LT_EXT");
		pushInt(t, GL_OP_CLAMP_EXT); newGlobal(t, "GL_OP_CLAMP_EXT");
		pushInt(t, GL_OP_FLOOR_EXT); newGlobal(t, "GL_OP_FLOOR_EXT");
		pushInt(t, GL_OP_ROUND_EXT); newGlobal(t, "GL_OP_ROUND_EXT");
		pushInt(t, GL_OP_EXP_BASE_2_EXT); newGlobal(t, "GL_OP_EXP_BASE_2_EXT");
		pushInt(t, GL_OP_LOG_BASE_2_EXT); newGlobal(t, "GL_OP_LOG_BASE_2_EXT");
		pushInt(t, GL_OP_POWER_EXT); newGlobal(t, "GL_OP_POWER_EXT");
		pushInt(t, GL_OP_RECIP_EXT); newGlobal(t, "GL_OP_RECIP_EXT");
		pushInt(t, GL_OP_RECIP_SQRT_EXT); newGlobal(t, "GL_OP_RECIP_SQRT_EXT");
		pushInt(t, GL_OP_SUB_EXT); newGlobal(t, "GL_OP_SUB_EXT");
		pushInt(t, GL_OP_CROSS_PRODUCT_EXT); newGlobal(t, "GL_OP_CROSS_PRODUCT_EXT");
		pushInt(t, GL_OP_MULTIPLY_MATRIX_EXT); newGlobal(t, "GL_OP_MULTIPLY_MATRIX_EXT");
		pushInt(t, GL_OP_MOV_EXT); newGlobal(t, "GL_OP_MOV_EXT");
		pushInt(t, GL_OUTPUT_VERTEX_EXT); newGlobal(t, "GL_OUTPUT_VERTEX_EXT");
		pushInt(t, GL_OUTPUT_COLOR0_EXT); newGlobal(t, "GL_OUTPUT_COLOR0_EXT");
		pushInt(t, GL_OUTPUT_COLOR1_EXT); newGlobal(t, "GL_OUTPUT_COLOR1_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD0_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD0_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD1_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD1_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD2_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD2_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD3_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD3_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD4_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD4_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD5_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD5_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD6_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD6_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD7_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD7_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD8_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD8_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD9_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD9_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD10_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD10_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD11_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD11_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD12_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD12_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD13_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD13_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD14_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD14_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD15_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD15_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD16_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD16_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD17_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD17_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD18_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD18_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD19_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD19_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD20_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD20_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD21_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD21_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD22_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD22_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD23_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD23_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD24_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD24_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD25_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD25_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD26_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD26_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD27_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD27_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD28_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD28_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD29_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD29_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD30_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD30_EXT");
		pushInt(t, GL_OUTPUT_TEXTURE_COORD31_EXT); newGlobal(t, "GL_OUTPUT_TEXTURE_COORD31_EXT");
		pushInt(t, GL_OUTPUT_FOG_EXT); newGlobal(t, "GL_OUTPUT_FOG_EXT");
		pushInt(t, GL_SCALAR_EXT); newGlobal(t, "GL_SCALAR_EXT");
		pushInt(t, GL_VECTOR_EXT); newGlobal(t, "GL_VECTOR_EXT");
		pushInt(t, GL_MATRIX_EXT); newGlobal(t, "GL_MATRIX_EXT");
		pushInt(t, GL_VARIANT_EXT); newGlobal(t, "GL_VARIANT_EXT");
		pushInt(t, GL_INVARIANT_EXT); newGlobal(t, "GL_INVARIANT_EXT");
		pushInt(t, GL_LOCAL_CONSTANT_EXT); newGlobal(t, "GL_LOCAL_CONSTANT_EXT");
		pushInt(t, GL_LOCAL_EXT); newGlobal(t, "GL_LOCAL_EXT");
		pushInt(t, GL_MAX_VERTEX_SHADER_INSTRUCTIONS_EXT); newGlobal(t, "GL_MAX_VERTEX_SHADER_INSTRUCTIONS_EXT");
		pushInt(t, GL_MAX_VERTEX_SHADER_VARIANTS_EXT); newGlobal(t, "GL_MAX_VERTEX_SHADER_VARIANTS_EXT");
		pushInt(t, GL_MAX_VERTEX_SHADER_INVARIANTS_EXT); newGlobal(t, "GL_MAX_VERTEX_SHADER_INVARIANTS_EXT");
		pushInt(t, GL_MAX_VERTEX_SHADER_LOCAL_CONSTANTS_EXT); newGlobal(t, "GL_MAX_VERTEX_SHADER_LOCAL_CONSTANTS_EXT");
		pushInt(t, GL_MAX_VERTEX_SHADER_LOCALS_EXT); newGlobal(t, "GL_MAX_VERTEX_SHADER_LOCALS_EXT");
		pushInt(t, GL_MAX_OPTIMIZED_VERTEX_SHADER_INSTRUCTIONS_EXT); newGlobal(t, "GL_MAX_OPTIMIZED_VERTEX_SHADER_INSTRUCTIONS_EXT");
		pushInt(t, GL_MAX_OPTIMIZED_VERTEX_SHADER_VARIANTS_EXT); newGlobal(t, "GL_MAX_OPTIMIZED_VERTEX_SHADER_VARIANTS_EXT");
		pushInt(t, GL_MAX_OPTIMIZED_VERTEX_SHADER_LOCAL_CONSTANTS_EXT); newGlobal(t, "GL_MAX_OPTIMIZED_VERTEX_SHADER_LOCAL_CONSTANTS_EXT");
		pushInt(t, GL_MAX_OPTIMIZED_VERTEX_SHADER_INVARIANTS_EXT); newGlobal(t, "GL_MAX_OPTIMIZED_VERTEX_SHADER_INVARIANTS_EXT");
		pushInt(t, GL_MAX_OPTIMIZED_VERTEX_SHADER_LOCALS_EXT); newGlobal(t, "GL_MAX_OPTIMIZED_VERTEX_SHADER_LOCALS_EXT");
		pushInt(t, GL_VERTEX_SHADER_INSTRUCTIONS_EXT); newGlobal(t, "GL_VERTEX_SHADER_INSTRUCTIONS_EXT");
		pushInt(t, GL_VERTEX_SHADER_VARIANTS_EXT); newGlobal(t, "GL_VERTEX_SHADER_VARIANTS_EXT");
		pushInt(t, GL_VERTEX_SHADER_INVARIANTS_EXT); newGlobal(t, "GL_VERTEX_SHADER_INVARIANTS_EXT");
		pushInt(t, GL_VERTEX_SHADER_LOCAL_CONSTANTS_EXT); newGlobal(t, "GL_VERTEX_SHADER_LOCAL_CONSTANTS_EXT");
		pushInt(t, GL_VERTEX_SHADER_LOCALS_EXT); newGlobal(t, "GL_VERTEX_SHADER_LOCALS_EXT");
		pushInt(t, GL_VERTEX_SHADER_OPTIMIZED_EXT); newGlobal(t, "GL_VERTEX_SHADER_OPTIMIZED_EXT");
		pushInt(t, GL_X_EXT); newGlobal(t, "GL_X_EXT");
		pushInt(t, GL_Y_EXT); newGlobal(t, "GL_Y_EXT");
		pushInt(t, GL_Z_EXT); newGlobal(t, "GL_Z_EXT");
		pushInt(t, GL_W_EXT); newGlobal(t, "GL_W_EXT");
		pushInt(t, GL_NEGATIVE_X_EXT); newGlobal(t, "GL_NEGATIVE_X_EXT");
		pushInt(t, GL_NEGATIVE_Y_EXT); newGlobal(t, "GL_NEGATIVE_Y_EXT");
		pushInt(t, GL_NEGATIVE_Z_EXT); newGlobal(t, "GL_NEGATIVE_Z_EXT");
		pushInt(t, GL_NEGATIVE_W_EXT); newGlobal(t, "GL_NEGATIVE_W_EXT");
		pushInt(t, GL_ZERO_EXT); newGlobal(t, "GL_ZERO_EXT");
		pushInt(t, GL_ONE_EXT); newGlobal(t, "GL_ONE_EXT");
		pushInt(t, GL_NEGATIVE_ONE_EXT); newGlobal(t, "GL_NEGATIVE_ONE_EXT");
		pushInt(t, GL_NORMALIZED_RANGE_EXT); newGlobal(t, "GL_NORMALIZED_RANGE_EXT");
		pushInt(t, GL_FULL_RANGE_EXT); newGlobal(t, "GL_FULL_RANGE_EXT");
		pushInt(t, GL_CURRENT_VERTEX_EXT); newGlobal(t, "GL_CURRENT_VERTEX_EXT");
		pushInt(t, GL_MVP_MATRIX_EXT); newGlobal(t, "GL_MVP_MATRIX_EXT");
		pushInt(t, GL_VARIANT_VALUE_EXT); newGlobal(t, "GL_VARIANT_VALUE_EXT");
		pushInt(t, GL_VARIANT_DATATYPE_EXT); newGlobal(t, "GL_VARIANT_DATATYPE_EXT");
		pushInt(t, GL_VARIANT_ARRAY_STRIDE_EXT); newGlobal(t, "GL_VARIANT_ARRAY_STRIDE_EXT");
		pushInt(t, GL_VARIANT_ARRAY_TYPE_EXT); newGlobal(t, "GL_VARIANT_ARRAY_TYPE_EXT");
		pushInt(t, GL_VARIANT_ARRAY_EXT); newGlobal(t, "GL_VARIANT_ARRAY_EXT");
		pushInt(t, GL_VARIANT_ARRAY_POINTER_EXT); newGlobal(t, "GL_VARIANT_ARRAY_POINTER_EXT");
		pushInt(t, GL_INVARIANT_VALUE_EXT); newGlobal(t, "GL_INVARIANT_VALUE_EXT");
		pushInt(t, GL_INVARIANT_DATATYPE_EXT); newGlobal(t, "GL_INVARIANT_DATATYPE_EXT");
		pushInt(t, GL_LOCAL_CONSTANT_VALUE_EXT); newGlobal(t, "GL_LOCAL_CONSTANT_VALUE_EXT");
		pushInt(t, GL_LOCAL_CONSTANT_DATATYPE_EXT); newGlobal(t, "GL_LOCAL_CONSTANT_DATATYPE_EXT");
	}

	if(EXTVertexWeighting.isEnabled)
	{
		register(t, &wrapGL!(glVertexWeightfEXT), "glVertexWeightfEXT");
		register(t, &wrapGL!(glVertexWeightfvEXT), "glVertexWeightfvEXT");
		register(t, &wrapGL!(glVertexWeightPointerEXT), "glVertexWeightPointerEXT");

		pushInt(t, GL_MODELVIEW0_STACK_DEPTH_EXT); newGlobal(t, "GL_MODELVIEW0_STACK_DEPTH_EXT");
		pushInt(t, GL_MODELVIEW1_STACK_DEPTH_EXT); newGlobal(t, "GL_MODELVIEW1_STACK_DEPTH_EXT");
		pushInt(t, GL_MODELVIEW0_MATRIX_EXT); newGlobal(t, "GL_MODELVIEW0_MATRIX_EXT");
		pushInt(t, GL_MODELVIEW1_MATRIX_EXT); newGlobal(t, "GL_MODELVIEW1_MATRIX_EXT");
		pushInt(t, GL_VERTEX_WEIGHTING_EXT); newGlobal(t, "GL_VERTEX_WEIGHTING_EXT");
		pushInt(t, GL_MODELVIEW0_EXT); newGlobal(t, "GL_MODELVIEW0_EXT");
		pushInt(t, GL_MODELVIEW1_EXT); newGlobal(t, "GL_MODELVIEW1_EXT");
		pushInt(t, GL_CURRENT_VERTEX_WEIGHT_EXT); newGlobal(t, "GL_CURRENT_VERTEX_WEIGHT_EXT");
		pushInt(t, GL_VERTEX_WEIGHT_ARRAY_EXT); newGlobal(t, "GL_VERTEX_WEIGHT_ARRAY_EXT");
		pushInt(t, GL_VERTEX_WEIGHT_ARRAY_SIZE_EXT); newGlobal(t, "GL_VERTEX_WEIGHT_ARRAY_SIZE_EXT");
		pushInt(t, GL_VERTEX_WEIGHT_ARRAY_TYPE_EXT); newGlobal(t, "GL_VERTEX_WEIGHT_ARRAY_TYPE_EXT");
		pushInt(t, GL_VERTEX_WEIGHT_ARRAY_STRIDE_EXT); newGlobal(t, "GL_VERTEX_WEIGHT_ARRAY_STRIDE_EXT");
		pushInt(t, GL_VERTEX_WEIGHT_ARRAY_POINTER_EXT); newGlobal(t, "GL_VERTEX_WEIGHT_ARRAY_POINTER_EXT");
	}

	// NV
	if(NVCopyDepthToColor.isEnabled)
	{
			pushInt(t, GL_DEPTH_STENCIL_TO_RGBA_NV); newGlobal(t, "GL_DEPTH_STENCIL_TO_RGBA_NV");
		pushInt(t, GL_DEPTH_STENCIL_TO_BGRA_NV); newGlobal(t, "GL_DEPTH_STENCIL_TO_BGRA_NV");
	}

	if(NVDepthBufferFloat.isEnabled)
	{
		register(t, &wrapGL!(glDepthRangedNV), "glDepthRangedNV");
		register(t, &wrapGL!(glClearDepthdNV), "glClearDepthdNV");
		register(t, &wrapGL!(glDepthBoundsdNV), "glDepthBoundsdNV");

		pushInt(t, GL_DEPTH_COMPONENT32F_NV); newGlobal(t, "GL_DEPTH_COMPONENT32F_NV");
		pushInt(t, GL_DEPTH32F_STENCIL8_NV); newGlobal(t, "GL_DEPTH32F_STENCIL8_NV");
		pushInt(t, GL_FLOAT_32_UNSIGNED_INT_24_8_REV_NV); newGlobal(t, "GL_FLOAT_32_UNSIGNED_INT_24_8_REV_NV");
		pushInt(t, GL_DEPTH_BUFFER_FLOAT_MODE_NV); newGlobal(t, "GL_DEPTH_BUFFER_FLOAT_MODE_NV");
	}

	if(NVDepthClamp.isEnabled)
	{
		pushInt(t, GL_DEPTH_CLAMP_NV); newGlobal(t, "GL_DEPTH_CLAMP_NV");
	}

	if(NVEvaluators.isEnabled)
	{
		register(t, &wrapGL!(glMapControlPointsNV), "glMapControlPointsNV");
		register(t, &wrapGL!(glMapParameterivNV), "glMapParameterivNV");
		register(t, &wrapGL!(glMapParameterfvNV), "glMapParameterfvNV");
		register(t, &wrapGL!(glGetMapControlPointsNV), "glGetMapControlPointsNV");
		register(t, &wrapGL!(glGetMapParameterivNV), "glGetMapParameterivNV");
		register(t, &wrapGL!(glGetMapParameterfvNV), "glGetMapParameterfvNV");
		register(t, &wrapGL!(glGetMapAttribParameterivNV), "glGetMapAttribParameterivNV");
		register(t, &wrapGL!(glGetMapAttribParameterfvNV), "glGetMapAttribParameterfvNV");
		register(t, &wrapGL!(glEvalMapsNV), "glEvalMapsNV");

		pushInt(t, GL_EVAL_2D_NV); newGlobal(t, "GL_EVAL_2D_NV");
		pushInt(t, GL_EVAL_TRIANGULAR_2D_NV); newGlobal(t, "GL_EVAL_TRIANGULAR_2D_NV");
		pushInt(t, GL_MAP_TESSELLATION_NV); newGlobal(t, "GL_MAP_TESSELLATION_NV");
		pushInt(t, GL_MAP_ATTRIB_U_ORDER_NV); newGlobal(t, "GL_MAP_ATTRIB_U_ORDER_NV");
		pushInt(t, GL_MAP_ATTRIB_V_ORDER_NV); newGlobal(t, "GL_MAP_ATTRIB_V_ORDER_NV");
		pushInt(t, GL_EVAL_FRACTIONAL_TESSELLATION_NV); newGlobal(t, "GL_EVAL_FRACTIONAL_TESSELLATION_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB0_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB0_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB1_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB1_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB2_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB2_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB3_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB3_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB4_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB4_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB5_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB5_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB6_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB6_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB7_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB7_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB8_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB8_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB9_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB9_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB10_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB10_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB11_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB11_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB12_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB12_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB13_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB13_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB14_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB14_NV");
		pushInt(t, GL_EVAL_VERTEX_ATTRIB15_NV); newGlobal(t, "GL_EVAL_VERTEX_ATTRIB15_NV");
		pushInt(t, GL_MAX_MAP_TESSELLATION_NV); newGlobal(t, "GL_MAX_MAP_TESSELLATION_NV");
		pushInt(t, GL_MAX_RATIONAL_EVAL_ORDER_NV); newGlobal(t, "GL_MAX_RATIONAL_EVAL_ORDER_NV");
	}

	if(NVFence.isEnabled)
	{
		register(t, &wrapGL!(glDeleteFencesNV), "glDeleteFencesNV");
		register(t, &wrapGL!(glGenFencesNV), "glGenFencesNV");
		register(t, &wrapGL!(glIsFenceNV), "glIsFenceNV");
		register(t, &wrapGL!(glTestFenceNV), "glTestFenceNV");
		register(t, &wrapGL!(glGetFenceivNV), "glGetFenceivNV");
		register(t, &wrapGL!(glFinishFenceNV), "glFinishFenceNV");
		register(t, &wrapGL!(glSetFenceNV), "glSetFenceNV");

		pushInt(t, GL_ALL_COMPLETED_NV); newGlobal(t, "GL_ALL_COMPLETED_NV");
		pushInt(t, GL_FENCE_STATUS_NV); newGlobal(t, "GL_FENCE_STATUS_NV");
		pushInt(t, GL_FENCE_CONDITION_NV); newGlobal(t, "GL_FENCE_CONDITION_NV");
	}

	if(NVFloatBuffer.isEnabled)
	{
		pushInt(t, GL_FLOAT_R_NV); newGlobal(t, "GL_FLOAT_R_NV");
		pushInt(t, GL_FLOAT_RG_NV); newGlobal(t, "GL_FLOAT_RG_NV");
		pushInt(t, GL_FLOAT_RGB_NV); newGlobal(t, "GL_FLOAT_RGB_NV");
		pushInt(t, GL_FLOAT_RGBA_NV); newGlobal(t, "GL_FLOAT_RGBA_NV");
		pushInt(t, GL_FLOAT_R16_NV); newGlobal(t, "GL_FLOAT_R16_NV");
		pushInt(t, GL_FLOAT_R32_NV); newGlobal(t, "GL_FLOAT_R32_NV");
		pushInt(t, GL_FLOAT_RG16_NV); newGlobal(t, "GL_FLOAT_RG16_NV");
		pushInt(t, GL_FLOAT_RG32_NV); newGlobal(t, "GL_FLOAT_RG32_NV");
		pushInt(t, GL_FLOAT_RGB16_NV); newGlobal(t, "GL_FLOAT_RGB16_NV");
		pushInt(t, GL_FLOAT_RGB32_NV); newGlobal(t, "GL_FLOAT_RGB32_NV");
		pushInt(t, GL_FLOAT_RGBA16_NV); newGlobal(t, "GL_FLOAT_RGBA16_NV");
		pushInt(t, GL_FLOAT_RGBA32_NV); newGlobal(t, "GL_FLOAT_RGBA32_NV");
		pushInt(t, GL_TEXTURE_FLOAT_COMPONENTS_NV); newGlobal(t, "GL_TEXTURE_FLOAT_COMPONENTS_NV");
		pushInt(t, GL_FLOAT_CLEAR_COLOR_VALUE_NV); newGlobal(t, "GL_FLOAT_CLEAR_COLOR_VALUE_NV");
		pushInt(t, GL_FLOAT_RGBA_MODE_NV); newGlobal(t, "GL_FLOAT_RGBA_MODE_NV");
	}

	if(NVFogDistance.isEnabled)
	{
		pushInt(t, GL_FOG_DISTANCE_MODE_NV); newGlobal(t, "GL_FOG_DISTANCE_MODE_NV");
		pushInt(t, GL_EYE_RADIAL_NV); newGlobal(t, "GL_EYE_RADIAL_NV");
		pushInt(t, GL_EYE_PLANE_ABSOLUTE_NV); newGlobal(t, "GL_EYE_PLANE_ABSOLUTE_NV");
	}

	if(NVFragmentProgram.isEnabled)
	{
		register(t, &wrapGL!(glProgramNamedParameter4fNV), "glProgramNamedParameter4fNV");
		register(t, &wrapGL!(glProgramNamedParameter4dNV), "glProgramNamedParameter4dNV");
		register(t, &wrapGL!(glProgramNamedParameter4fvNV), "glProgramNamedParameter4fvNV");
		register(t, &wrapGL!(glProgramNamedParameter4dvNV), "glProgramNamedParameter4dvNV");
		register(t, &wrapGL!(glGetProgramNamedParameterfvNV), "glGetProgramNamedParameterfvNV");
		register(t, &wrapGL!(glGetProgramNamedParameterdvNV), "glGetProgramNamedParameterdvNV");

		pushInt(t, GL_MAX_FRAGMENT_PROGRAM_LOCAL_PARAMETERS_NV); newGlobal(t, "GL_MAX_FRAGMENT_PROGRAM_LOCAL_PARAMETERS_NV");
		pushInt(t, GL_FRAGMENT_PROGRAM_NV); newGlobal(t, "GL_FRAGMENT_PROGRAM_NV");
		pushInt(t, GL_MAX_TEXTURE_COORDS_NV); newGlobal(t, "GL_MAX_TEXTURE_COORDS_NV");
		pushInt(t, GL_MAX_TEXTURE_IMAGE_UNITS_NV); newGlobal(t, "GL_MAX_TEXTURE_IMAGE_UNITS_NV");
		pushInt(t, GL_FRAGMENT_PROGRAM_BINDING_NV); newGlobal(t, "GL_FRAGMENT_PROGRAM_BINDING_NV");
		pushInt(t, GL_PROGRAM_ERROR_STRING_NV); newGlobal(t, "GL_PROGRAM_ERROR_STRING_NV");
	}

	if(NVFragmentProgram2.isEnabled)
	{
		pushInt(t, GL_MAX_PROGRAM_EXEC_INSTRUCTIONS_NV); newGlobal(t, "GL_MAX_PROGRAM_EXEC_INSTRUCTIONS_NV");
		pushInt(t, GL_MAX_PROGRAM_CALL_DEPTH_NV); newGlobal(t, "GL_MAX_PROGRAM_CALL_DEPTH_NV");
		pushInt(t, GL_MAX_PROGRAM_IF_DEPTH_NV); newGlobal(t, "GL_MAX_PROGRAM_IF_DEPTH_NV");
		pushInt(t, GL_MAX_PROGRAM_LOOP_DEPTH_NV); newGlobal(t, "GL_MAX_PROGRAM_LOOP_DEPTH_NV");
		pushInt(t, GL_MAX_PROGRAM_LOOP_COUNT_NV); newGlobal(t, "GL_MAX_PROGRAM_LOOP_COUNT_NV");
	}

	if(NVFramebufferMultisampleCoverage.isEnabled)
	{
		register(t, &wrapGL!(glRenderbufferStorageMultisampleCoverageNV), "glRenderbufferStorageMultisampleCoverageNV");

		pushInt(t, GL_RENDERBUFFER_COVERAGE_SAMPLES_NV); newGlobal(t, "GL_RENDERBUFFER_COVERAGE_SAMPLES_NV");
		pushInt(t, GL_RENDERBUFFER_COLOR_SAMPLES_NV); newGlobal(t, "GL_RENDERBUFFER_COLOR_SAMPLES_NV");
		pushInt(t, GL_MAX_RENDERBUFFER_COVERAGE_SAMPLES_NV); newGlobal(t, "GL_MAX_RENDERBUFFER_COVERAGE_SAMPLES_NV");
		pushInt(t, GL_MAX_RENDERBUFFER_COLOR_SAMPLES_NV); newGlobal(t, "GL_MAX_RENDERBUFFER_COLOR_SAMPLES_NV");
		pushInt(t, GL_MAX_MULTISAMPLE_COVERAGE_MODES_NV); newGlobal(t, "GL_MAX_MULTISAMPLE_COVERAGE_MODES_NV");
		pushInt(t, GL_MULTISAMPLE_COVERAGE_MODES_NV); newGlobal(t, "GL_MULTISAMPLE_COVERAGE_MODES_NV");
	}

	if(NVGeometryProgram4.isEnabled)
	{
		register(t, &wrapGL!(glProgramVertexLimitNV), "glProgramVertexLimitNV");

		pushInt(t, GL_GEOMETRY_PROGRAM_NV); newGlobal(t, "GL_GEOMETRY_PROGRAM_NV");
		pushInt(t, GL_MAX_PROGRAM_OUTPUT_VERTICES_NV); newGlobal(t, "GL_MAX_PROGRAM_OUTPUT_VERTICES_NV");
		pushInt(t, GL_MAX_PROGRAM_TOTAL_OUTPUT_COMPONENTS_NV); newGlobal(t, "GL_MAX_PROGRAM_TOTAL_OUTPUT_COMPONENTS_NV");
	}

	if(NVGpuProgram4.isEnabled)
	{
		register(t, &wrapGL!(glProgramLocalParameterI4iNV), "glProgramLocalParameterI4iNV");
		register(t, &wrapGL!(glProgramLocalParameterI4ivNV), "glProgramLocalParameterI4ivNV");
		register(t, &wrapGL!(glProgramLocalParametersI4ivNV), "glProgramLocalParametersI4ivNV");
		register(t, &wrapGL!(glProgramLocalParameterI4uiNV), "glProgramLocalParameterI4uiNV");
		register(t, &wrapGL!(glProgramLocalParameterI4uivNV), "glProgramLocalParameterI4uivNV");
		register(t, &wrapGL!(glProgramLocalParametersI4uivNV), "glProgramLocalParametersI4uivNV");
		register(t, &wrapGL!(glProgramEnvParameterI4iNV), "glProgramEnvParameterI4iNV");
		register(t, &wrapGL!(glProgramEnvParameterI4ivNV), "glProgramEnvParameterI4ivNV");
		register(t, &wrapGL!(glProgramEnvParametersI4ivNV), "glProgramEnvParametersI4ivNV");
		register(t, &wrapGL!(glProgramEnvParameterI4uiNV), "glProgramEnvParameterI4uiNV");
		register(t, &wrapGL!(glProgramEnvParameterI4uivNV), "glProgramEnvParameterI4uivNV");
		register(t, &wrapGL!(glProgramEnvParametersI4uivNV), "glProgramEnvParametersI4uivNV");
		register(t, &wrapGL!(glGetProgramLocalParameterIivNV), "glGetProgramLocalParameterIivNV");
		register(t, &wrapGL!(glGetProgramLocalParameterIuivNV), "glGetProgramLocalParameterIuivNV");
		register(t, &wrapGL!(glGetProgramEnvParameterIivNV), "glGetProgramEnvParameterIivNV");
		register(t, &wrapGL!(glGetProgramEnvParameterIuivNV), "glGetProgramEnvParameterIuivNV");

		pushInt(t, GL_MIN_PROGRAM_TEXEL_OFFSET_NV); newGlobal(t, "GL_MIN_PROGRAM_TEXEL_OFFSET_NV");
		pushInt(t, GL_MAX_PROGRAM_TEXEL_OFFSET_NV); newGlobal(t, "GL_MAX_PROGRAM_TEXEL_OFFSET_NV");
		pushInt(t, GL_PROGRAM_ATTRIB_COMPONENTS_NV); newGlobal(t, "GL_PROGRAM_ATTRIB_COMPONENTS_NV");
		pushInt(t, GL_PROGRAM_RESULT_COMPONENTS_NV); newGlobal(t, "GL_PROGRAM_RESULT_COMPONENTS_NV");
		pushInt(t, GL_MAX_PROGRAM_ATTRIB_COMPONENTS_NV); newGlobal(t, "GL_MAX_PROGRAM_ATTRIB_COMPONENTS_NV");
		pushInt(t, GL_MAX_PROGRAM_RESULT_COMPONENTS_NV); newGlobal(t, "GL_MAX_PROGRAM_RESULT_COMPONENTS_NV");
		pushInt(t, GL_MAX_PROGRAM_GENERIC_ATTRIBS_NV); newGlobal(t, "GL_MAX_PROGRAM_GENERIC_ATTRIBS_NV");
		pushInt(t, GL_MAX_PROGRAM_GENERIC_RESULTS_NV); newGlobal(t, "GL_MAX_PROGRAM_GENERIC_RESULTS_NV");
	}

	if(NVHalfFloat.isEnabled)
	{
		register(t, &wrapGL!(glVertex2hNV), "glVertex2hNV");
		register(t, &wrapGL!(glVertex2hvNV), "glVertex2hvNV");
		register(t, &wrapGL!(glVertex3hNV), "glVertex3hNV");
		register(t, &wrapGL!(glVertex3hvNV), "glVertex3hvNV");
		register(t, &wrapGL!(glVertex4hNV), "glVertex4hNV");
		register(t, &wrapGL!(glVertex4hvNV), "glVertex4hvNV");
		register(t, &wrapGL!(glNormal3hNV), "glNormal3hNV");
		register(t, &wrapGL!(glNormal3hvNV), "glNormal3hvNV");
		register(t, &wrapGL!(glColor3hNV), "glColor3hNV");
		register(t, &wrapGL!(glColor3hvNV), "glColor3hvNV");
		register(t, &wrapGL!(glColor4hNV), "glColor4hNV");
		register(t, &wrapGL!(glColor4hvNV), "glColor4hvNV");
		register(t, &wrapGL!(glTexCoord1hNV), "glTexCoord1hNV");
		register(t, &wrapGL!(glTexCoord1hvNV), "glTexCoord1hvNV");
		register(t, &wrapGL!(glTexCoord2hNV), "glTexCoord2hNV");
		register(t, &wrapGL!(glTexCoord2hvNV), "glTexCoord2hvNV");
		register(t, &wrapGL!(glTexCoord3hNV), "glTexCoord3hNV");
		register(t, &wrapGL!(glTexCoord3hvNV), "glTexCoord3hvNV");
		register(t, &wrapGL!(glTexCoord4hNV), "glTexCoord4hNV");
		register(t, &wrapGL!(glTexCoord4hvNV), "glTexCoord4hvNV");
		register(t, &wrapGL!(glMultiTexCoord1hNV), "glMultiTexCoord1hNV");
		register(t, &wrapGL!(glMultiTexCoord1hvNV), "glMultiTexCoord1hvNV");
		register(t, &wrapGL!(glMultiTexCoord2hNV), "glMultiTexCoord2hNV");
		register(t, &wrapGL!(glMultiTexCoord2hvNV), "glMultiTexCoord2hvNV");
		register(t, &wrapGL!(glMultiTexCoord3hNV), "glMultiTexCoord3hNV");
		register(t, &wrapGL!(glMultiTexCoord3hvNV), "glMultiTexCoord3hvNV");
		register(t, &wrapGL!(glMultiTexCoord4hNV), "glMultiTexCoord4hNV");
		register(t, &wrapGL!(glMultiTexCoord4hvNV), "glMultiTexCoord4hvNV");
		register(t, &wrapGL!(glFogCoordhNV), "glFogCoordhNV");
		register(t, &wrapGL!(glFogCoordhvNV), "glFogCoordhvNV");
		register(t, &wrapGL!(glSecondaryColor3hNV), "glSecondaryColor3hNV");
		register(t, &wrapGL!(glSecondaryColor3hvNV), "glSecondaryColor3hvNV");
		register(t, &wrapGL!(glVertexWeighthNV), "glVertexWeighthNV");
		register(t, &wrapGL!(glVertexWeighthvNV), "glVertexWeighthvNV");
		register(t, &wrapGL!(glVertexAttrib1hNV), "glVertexAttrib1hNV");
		register(t, &wrapGL!(glVertexAttrib1hvNV), "glVertexAttrib1hvNV");
		register(t, &wrapGL!(glVertexAttrib2hNV), "glVertexAttrib2hNV");
		register(t, &wrapGL!(glVertexAttrib2hvNV), "glVertexAttrib2hvNV");
		register(t, &wrapGL!(glVertexAttrib3hNV), "glVertexAttrib3hNV");
		register(t, &wrapGL!(glVertexAttrib3hvNV), "glVertexAttrib3hvNV");
		register(t, &wrapGL!(glVertexAttrib4hNV), "glVertexAttrib4hNV");
		register(t, &wrapGL!(glVertexAttrib4hvNV), "glVertexAttrib4hvNV");
		register(t, &wrapGL!(glVertexAttribs1hvNV), "glVertexAttribs1hvNV");
		register(t, &wrapGL!(glVertexAttribs2hvNV), "glVertexAttribs2hvNV");
		register(t, &wrapGL!(glVertexAttribs3hvNV), "glVertexAttribs3hvNV");
		register(t, &wrapGL!(glVertexAttribs4hvNV), "glVertexAttribs4hvNV");

		pushInt(t, GL_HALF_FLOAT_NV); newGlobal(t, "GL_HALF_FLOAT_NV");
	}

	if(NVLightMaxExponent.isEnabled)
	{
		pushInt(t, GL_MAX_SHININESS_NV); newGlobal(t, "GL_MAX_SHININESS_NV");
		pushInt(t, GL_MAX_SPOT_EXPONENT_NV); newGlobal(t, "GL_MAX_SPOT_EXPONENT_NV");
	}

	if(NVMultisampleFilterHint.isEnabled)
	{
		pushInt(t, GL_MULTISAMPLE_FILTER_HINT_NV); newGlobal(t, "GL_MULTISAMPLE_FILTER_HINT_NV");
	}

	if(NVOcclusionQuery.isEnabled)
	{
		register(t, &wrapGL!(glGenOcclusionQueriesNV), "glGenOcclusionQueriesNV");
		register(t, &wrapGL!(glDeleteOcclusionQueriesNV), "glDeleteOcclusionQueriesNV");
		register(t, &wrapGL!(glIsOcclusionQueryNV), "glIsOcclusionQueryNV");
		register(t, &wrapGL!(glBeginOcclusionQueryNV), "glBeginOcclusionQueryNV");
		register(t, &wrapGL!(glEndOcclusionQueryNV), "glEndOcclusionQueryNV");
		register(t, &wrapGL!(glGetOcclusionQueryivNV), "glGetOcclusionQueryivNV");
		register(t, &wrapGL!(glGetOcclusionQueryuivNV), "glGetOcclusionQueryuivNV");

		pushInt(t, GL_PIXEL_COUNTER_BITS_NV); newGlobal(t, "GL_PIXEL_COUNTER_BITS_NV");
		pushInt(t, GL_CURRENT_OCCLUSION_QUERY_ID_NV); newGlobal(t, "GL_CURRENT_OCCLUSION_QUERY_ID_NV");
		pushInt(t, GL_PIXEL_COUNT_NV); newGlobal(t, "GL_PIXEL_COUNT_NV");
		pushInt(t, GL_PIXEL_COUNT_AVAILABLE_NV); newGlobal(t, "GL_PIXEL_COUNT_AVAILABLE_NV");
	}

	if(NVPackedDepthStencil.isEnabled)
	{
		pushInt(t, GL_DEPTH_STENCIL_NV); newGlobal(t, "GL_DEPTH_STENCIL_NV");
		pushInt(t, GL_UNSIGNED_INT_24_8_NV); newGlobal(t, "GL_UNSIGNED_INT_24_8_NV");
	}

	if(NVParameterBufferObject.isEnabled)
	{
		register(t, &wrapGL!(glProgramBufferParametersfvNV), "glProgramBufferParametersfvNV");
		register(t, &wrapGL!(glProgramBufferParametersIivNV), "glProgramBufferParametersIivNV");
		register(t, &wrapGL!(glProgramBufferParametersIuivNV), "glProgramBufferParametersIuivNV");
	}

	if(NVPixelDataRange.isEnabled)
	{
		register(t, &wrapGL!(glPixelDataRangeNV), "glPixelDataRangeNV");
		register(t, &wrapGL!(glFlushPixelDataRangeNV), "glFlushPixelDataRangeNV");

		pushInt(t, GL_WRITE_PIXEL_DATA_RANGE_NV); newGlobal(t, "GL_WRITE_PIXEL_DATA_RANGE_NV");
		pushInt(t, GL_READ_PIXEL_DATA_RANGE_NV); newGlobal(t, "GL_READ_PIXEL_DATA_RANGE_NV");
		pushInt(t, GL_WRITE_PIXEL_DATA_RANGE_LENGTH_NV); newGlobal(t, "GL_WRITE_PIXEL_DATA_RANGE_LENGTH_NV");
		pushInt(t, GL_READ_PIXEL_DATA_RANGE_LENGTH_NV); newGlobal(t, "GL_READ_PIXEL_DATA_RANGE_LENGTH_NV");
		pushInt(t, GL_WRITE_PIXEL_DATA_RANGE_POINTER_NV); newGlobal(t, "GL_WRITE_PIXEL_DATA_RANGE_POINTER_NV");
		pushInt(t, GL_READ_PIXEL_DATA_RANGE_POINTER_NV); newGlobal(t, "GL_READ_PIXEL_DATA_RANGE_POINTER_NV");
	}

	if(NVPointSprite.isEnabled)
	{
		register(t, &wrapGL!(glPointParameteriNV), "glPointParameteriNV");
		register(t, &wrapGL!(glPointParameterivNV), "glPointParameterivNV");

		pushInt(t, GL_POINT_SPRITE_NV); newGlobal(t, "GL_POINT_SPRITE_NV");
		pushInt(t, GL_COORD_REPLACE_NV); newGlobal(t, "GL_COORD_REPLACE_NV");
		pushInt(t, GL_POINT_SPRITE_R_MODE_NV); newGlobal(t, "GL_POINT_SPRITE_R_MODE_NV");
	}

	if(NVPrimitiveRestart.isEnabled)
	{
		register(t, &wrapGL!(glPrimitiveRestartNV), "glPrimitiveRestartNV");
		register(t, &wrapGL!(glPrimitiveRestartIndexNV), "glPrimitiveRestartIndexNV");

		pushInt(t, GL_PRIMITIVE_RESTART_NV); newGlobal(t, "GL_PRIMITIVE_RESTART_NV");
		pushInt(t, GL_PRIMITIVE_RESTART_INDEX_NV); newGlobal(t, "GL_PRIMITIVE_RESTART_INDEX_NV");
	}

	if(NVRegisterCombiners.isEnabled)
	{
		register(t, &wrapGL!(glCombinerParameterfvNV), "glCombinerParameterfvNV");
		register(t, &wrapGL!(glCombinerParameterfNV), "glCombinerParameterfNV");
		register(t, &wrapGL!(glCombinerParameterivNV), "glCombinerParameterivNV");
		register(t, &wrapGL!(glCombinerParameteriNV), "glCombinerParameteriNV");
		register(t, &wrapGL!(glCombinerInputNV), "glCombinerInputNV");
		register(t, &wrapGL!(glCombinerOutputNV), "glCombinerOutputNV");
		register(t, &wrapGL!(glFinalCombinerInputNV), "glFinalCombinerInputNV");
		register(t, &wrapGL!(glGetCombinerInputParameterfvNV), "glGetCombinerInputParameterfvNV");
		register(t, &wrapGL!(glGetCombinerInputParameterivNV), "glGetCombinerInputParameterivNV");
		register(t, &wrapGL!(glGetCombinerOutputParameterfvNV), "glGetCombinerOutputParameterfvNV");
		register(t, &wrapGL!(glGetCombinerOutputParameterivNV), "glGetCombinerOutputParameterivNV");
		register(t, &wrapGL!(glGetFinalCombinerInputParameterfvNV), "glGetFinalCombinerInputParameterfvNV");
		register(t, &wrapGL!(glGetFinalCombinerInputParameterivNV), "glGetFinalCombinerInputParameterivNV");

		pushInt(t, GL_REGISTER_COMBINERS_NV); newGlobal(t, "GL_REGISTER_COMBINERS_NV");
		pushInt(t, GL_VARIABLE_A_NV); newGlobal(t, "GL_VARIABLE_A_NV");
		pushInt(t, GL_VARIABLE_B_NV); newGlobal(t, "GL_VARIABLE_B_NV");
		pushInt(t, GL_VARIABLE_C_NV); newGlobal(t, "GL_VARIABLE_C_NV");
		pushInt(t, GL_VARIABLE_D_NV); newGlobal(t, "GL_VARIABLE_D_NV");
		pushInt(t, GL_VARIABLE_E_NV); newGlobal(t, "GL_VARIABLE_E_NV");
		pushInt(t, GL_VARIABLE_F_NV); newGlobal(t, "GL_VARIABLE_F_NV");
		pushInt(t, GL_VARIABLE_G_NV); newGlobal(t, "GL_VARIABLE_G_NV");
		pushInt(t, GL_CONSTANT_COLOR0_NV); newGlobal(t, "GL_CONSTANT_COLOR0_NV");
		pushInt(t, GL_CONSTANT_COLOR1_NV); newGlobal(t, "GL_CONSTANT_COLOR1_NV");
		pushInt(t, GL_PRIMARY_COLOR_NV); newGlobal(t, "GL_PRIMARY_COLOR_NV");
		pushInt(t, GL_SECONDARY_COLOR_NV); newGlobal(t, "GL_SECONDARY_COLOR_NV");
		pushInt(t, GL_SPARE0_NV); newGlobal(t, "GL_SPARE0_NV");
		pushInt(t, GL_SPARE1_NV); newGlobal(t, "GL_SPARE1_NV");
		pushInt(t, GL_DISCARD_NV); newGlobal(t, "GL_DISCARD_NV");
		pushInt(t, GL_E_TIMES_F_NV); newGlobal(t, "GL_E_TIMES_F_NV");
		pushInt(t, GL_SPARE0_PLUS_SECONDARY_COLOR_NV); newGlobal(t, "GL_SPARE0_PLUS_SECONDARY_COLOR_NV");
		pushInt(t, GL_UNSIGNED_IDENTITY_NV); newGlobal(t, "GL_UNSIGNED_IDENTITY_NV");
		pushInt(t, GL_UNSIGNED_INVERT_NV); newGlobal(t, "GL_UNSIGNED_INVERT_NV");
		pushInt(t, GL_EXPAND_NORMAL_NV); newGlobal(t, "GL_EXPAND_NORMAL_NV");
		pushInt(t, GL_EXPAND_NEGATE_NV); newGlobal(t, "GL_EXPAND_NEGATE_NV");
		pushInt(t, GL_HALF_BIAS_NORMAL_NV); newGlobal(t, "GL_HALF_BIAS_NORMAL_NV");
		pushInt(t, GL_HALF_BIAS_NEGATE_NV); newGlobal(t, "GL_HALF_BIAS_NEGATE_NV");
		pushInt(t, GL_SIGNED_IDENTITY_NV); newGlobal(t, "GL_SIGNED_IDENTITY_NV");
		pushInt(t, GL_SIGNED_NEGATE_NV); newGlobal(t, "GL_SIGNED_NEGATE_NV");
		pushInt(t, GL_SCALE_BY_TWO_NV); newGlobal(t, "GL_SCALE_BY_TWO_NV");
		pushInt(t, GL_SCALE_BY_FOUR_NV); newGlobal(t, "GL_SCALE_BY_FOUR_NV");
		pushInt(t, GL_SCALE_BY_ONE_HALF_NV); newGlobal(t, "GL_SCALE_BY_ONE_HALF_NV");
		pushInt(t, GL_BIAS_BY_NEGATIVE_ONE_HALF_NV); newGlobal(t, "GL_BIAS_BY_NEGATIVE_ONE_HALF_NV");
		pushInt(t, GL_COMBINER_INPUT_NV); newGlobal(t, "GL_COMBINER_INPUT_NV");
		pushInt(t, GL_COMBINER_MAPPING_NV); newGlobal(t, "GL_COMBINER_MAPPING_NV");
		pushInt(t, GL_COMBINER_COMPONENT_USAGE_NV); newGlobal(t, "GL_COMBINER_COMPONENT_USAGE_NV");
		pushInt(t, GL_COMBINER_AB_DOT_PRODUCT_NV); newGlobal(t, "GL_COMBINER_AB_DOT_PRODUCT_NV");
		pushInt(t, GL_COMBINER_CD_DOT_PRODUCT_NV); newGlobal(t, "GL_COMBINER_CD_DOT_PRODUCT_NV");
		pushInt(t, GL_COMBINER_MUX_SUM_NV); newGlobal(t, "GL_COMBINER_MUX_SUM_NV");
		pushInt(t, GL_COMBINER_SCALE_NV); newGlobal(t, "GL_COMBINER_SCALE_NV");
		pushInt(t, GL_COMBINER_BIAS_NV); newGlobal(t, "GL_COMBINER_BIAS_NV");
		pushInt(t, GL_COMBINER_AB_OUTPUT_NV); newGlobal(t, "GL_COMBINER_AB_OUTPUT_NV");
		pushInt(t, GL_COMBINER_CD_OUTPUT_NV); newGlobal(t, "GL_COMBINER_CD_OUTPUT_NV");
		pushInt(t, GL_COMBINER_SUM_OUTPUT_NV); newGlobal(t, "GL_COMBINER_SUM_OUTPUT_NV");
		pushInt(t, GL_MAX_GENERAL_COMBINERS_NV); newGlobal(t, "GL_MAX_GENERAL_COMBINERS_NV");
		pushInt(t, GL_NUM_GENERAL_COMBINERS_NV); newGlobal(t, "GL_NUM_GENERAL_COMBINERS_NV");
		pushInt(t, GL_COLOR_SUM_CLAMP_NV); newGlobal(t, "GL_COLOR_SUM_CLAMP_NV");
		pushInt(t, GL_COMBINER0_NV); newGlobal(t, "GL_COMBINER0_NV");
		pushInt(t, GL_COMBINER1_NV); newGlobal(t, "GL_COMBINER1_NV");
		pushInt(t, GL_COMBINER2_NV); newGlobal(t, "GL_COMBINER2_NV");
		pushInt(t, GL_COMBINER3_NV); newGlobal(t, "GL_COMBINER3_NV");
		pushInt(t, GL_COMBINER4_NV); newGlobal(t, "GL_COMBINER4_NV");
		pushInt(t, GL_COMBINER5_NV); newGlobal(t, "GL_COMBINER5_NV");
		pushInt(t, GL_COMBINER6_NV); newGlobal(t, "GL_COMBINER6_NV");
		pushInt(t, GL_COMBINER7_NV); newGlobal(t, "GL_COMBINER7_NV");
	}

	if(NVRegisterCombiners2.isEnabled)
	{
		register(t, &wrapGL!(glCombinerStageParameterfvNV), "glCombinerStageParameterfvNV");
		register(t, &wrapGL!(glGetCombinerStageParameterfvNV), "glGetCombinerStageParameterfvNV");

		pushInt(t, GL_PER_STAGE_CONSTANTS_NV); newGlobal(t, "GL_PER_STAGE_CONSTANTS_NV");
	}

	if(NVTexgenEmboss.isEnabled)
	{
		pushInt(t, GL_EMBOSS_LIGHT_NV); newGlobal(t, "GL_EMBOSS_LIGHT_NV");
		pushInt(t, GL_EMBOSS_CONSTANT_NV); newGlobal(t, "GL_EMBOSS_CONSTANT_NV");
		pushInt(t, GL_EMBOSS_MAP_NV); newGlobal(t, "GL_EMBOSS_MAP_NV");
	}

	if(NVTexgenReflection.isEnabled)
	{
		pushInt(t, GL_NORMAL_MAP_NV); newGlobal(t, "GL_NORMAL_MAP_NV");
		pushInt(t, GL_REFLECTION_MAP_NV); newGlobal(t, "GL_REFLECTION_MAP_NV");
	}

	if(NVTextureEnvCombine4.isEnabled)
	{
		pushInt(t, GL_COMBINE4_NV); newGlobal(t, "GL_COMBINE4_NV");
		pushInt(t, GL_SOURCE3_RGB_NV); newGlobal(t, "GL_SOURCE3_RGB_NV");
		pushInt(t, GL_SOURCE3_ALPHA_NV); newGlobal(t, "GL_SOURCE3_ALPHA_NV");
		pushInt(t, GL_OPERAND3_RGB_NV); newGlobal(t, "GL_OPERAND3_RGB_NV");
		pushInt(t, GL_OPERAND3_ALPHA_NV); newGlobal(t, "GL_OPERAND3_ALPHA_NV");
	}

	if(NVTextureExpandNormal.isEnabled)
	{
		pushInt(t, GL_TEXTURE_UNSIGNED_REMAP_MODE_NV); newGlobal(t, "GL_TEXTURE_UNSIGNED_REMAP_MODE_NV");
	}

	if(NVTextureRectangle.isEnabled)
	{
		pushInt(t, GL_TEXTURE_RECTANGLE_NV); newGlobal(t, "GL_TEXTURE_RECTANGLE_NV");
		pushInt(t, GL_TEXTURE_BINDING_RECTANGLE_NV); newGlobal(t, "GL_TEXTURE_BINDING_RECTANGLE_NV");
		pushInt(t, GL_PROXY_TEXTURE_RECTANGLE_NV); newGlobal(t, "GL_PROXY_TEXTURE_RECTANGLE_NV");
		pushInt(t, GL_MAX_RECTANGLE_TEXTURE_SIZE_NV); newGlobal(t, "GL_MAX_RECTANGLE_TEXTURE_SIZE_NV");
	}

	if(NVTextureShader.isEnabled)
	{
		pushInt(t, GL_OFFSET_TEXTURE_RECTANGLE_NV); newGlobal(t, "GL_OFFSET_TEXTURE_RECTANGLE_NV");
		pushInt(t, GL_OFFSET_TEXTURE_RECTANGLE_SCALE_NV); newGlobal(t, "GL_OFFSET_TEXTURE_RECTANGLE_SCALE_NV");
		pushInt(t, GL_DOT_PRODUCT_TEXTURE_RECTANGLE_NV); newGlobal(t, "GL_DOT_PRODUCT_TEXTURE_RECTANGLE_NV");
		pushInt(t, GL_RGBA_UNSIGNED_DOT_PRODUCT_MAPPING_NV); newGlobal(t, "GL_RGBA_UNSIGNED_DOT_PRODUCT_MAPPING_NV");
		pushInt(t, GL_UNSIGNED_INT_S8_S8_8_8_NV); newGlobal(t, "GL_UNSIGNED_INT_S8_S8_8_8_NV");
		pushInt(t, GL_UNSIGNED_INT_8_8_S8_S8_REV_NV); newGlobal(t, "GL_UNSIGNED_INT_8_8_S8_S8_REV_NV");
		pushInt(t, GL_DSDT_MAG_INTENSITY_NV); newGlobal(t, "GL_DSDT_MAG_INTENSITY_NV");
		pushInt(t, GL_SHADER_CONSISTENT_NV); newGlobal(t, "GL_SHADER_CONSISTENT_NV");
		pushInt(t, GL_TEXTURE_SHADER_NV); newGlobal(t, "GL_TEXTURE_SHADER_NV");
		pushInt(t, GL_SHADER_OPERATION_NV); newGlobal(t, "GL_SHADER_OPERATION_NV");
		pushInt(t, GL_CULL_MODES_NV); newGlobal(t, "GL_CULL_MODES_NV");
		pushInt(t, GL_OFFSET_TEXTURE_MATRIX_NV); newGlobal(t, "GL_OFFSET_TEXTURE_MATRIX_NV");
		pushInt(t, GL_OFFSET_TEXTURE_SCALE_NV); newGlobal(t, "GL_OFFSET_TEXTURE_SCALE_NV");
		pushInt(t, GL_OFFSET_TEXTURE_BIAS_NV); newGlobal(t, "GL_OFFSET_TEXTURE_BIAS_NV");
		pushInt(t, GL_OFFSET_TEXTURE_2D_MATRIX_NV); newGlobal(t, "GL_OFFSET_TEXTURE_2D_MATRIX_NV");
		pushInt(t, GL_OFFSET_TEXTURE_2D_SCALE_NV); newGlobal(t, "GL_OFFSET_TEXTURE_2D_SCALE_NV");
		pushInt(t, GL_OFFSET_TEXTURE_2D_BIAS_NV); newGlobal(t, "GL_OFFSET_TEXTURE_2D_BIAS_NV");
		pushInt(t, GL_PREVIOUS_TEXTURE_INPUT_NV); newGlobal(t, "GL_PREVIOUS_TEXTURE_INPUT_NV");
		pushInt(t, GL_CONST_EYE_NV); newGlobal(t, "GL_CONST_EYE_NV");
		pushInt(t, GL_PASS_THROUGH_NV); newGlobal(t, "GL_PASS_THROUGH_NV");
		pushInt(t, GL_CULL_FRAGMENT_NV); newGlobal(t, "GL_CULL_FRAGMENT_NV");
		pushInt(t, GL_OFFSET_TEXTURE_2D_NV); newGlobal(t, "GL_OFFSET_TEXTURE_2D_NV");
		pushInt(t, GL_DEPENDENT_AR_TEXTURE_2D_NV); newGlobal(t, "GL_DEPENDENT_AR_TEXTURE_2D_NV");
		pushInt(t, GL_DEPENDENT_GB_TEXTURE_2D_NV); newGlobal(t, "GL_DEPENDENT_GB_TEXTURE_2D_NV");
		pushInt(t, GL_DOT_PRODUCT_NV); newGlobal(t, "GL_DOT_PRODUCT_NV");
		pushInt(t, GL_DOT_PRODUCT_DEPTH_REPLACE_NV); newGlobal(t, "GL_DOT_PRODUCT_DEPTH_REPLACE_NV");
		pushInt(t, GL_DOT_PRODUCT_TEXTURE_2D_NV); newGlobal(t, "GL_DOT_PRODUCT_TEXTURE_2D_NV");
		pushInt(t, GL_DOT_PRODUCT_TEXTURE_CUBE_MAP_NV); newGlobal(t, "GL_DOT_PRODUCT_TEXTURE_CUBE_MAP_NV");
		pushInt(t, GL_DOT_PRODUCT_DIFFUSE_CUBE_MAP_NV); newGlobal(t, "GL_DOT_PRODUCT_DIFFUSE_CUBE_MAP_NV");
		pushInt(t, GL_DOT_PRODUCT_REFLECT_CUBE_MAP_NV); newGlobal(t, "GL_DOT_PRODUCT_REFLECT_CUBE_MAP_NV");
		pushInt(t, GL_DOT_PRODUCT_CONST_EYE_REFLECT_CUBE_MAP_NV); newGlobal(t, "GL_DOT_PRODUCT_CONST_EYE_REFLECT_CUBE_MAP_NV");
		pushInt(t, GL_HILO_NV); newGlobal(t, "GL_HILO_NV");
		pushInt(t, GL_DSDT_NV); newGlobal(t, "GL_DSDT_NV");
		pushInt(t, GL_DSDT_MAG_NV); newGlobal(t, "GL_DSDT_MAG_NV");
		pushInt(t, GL_DSDT_MAG_VIB_NV); newGlobal(t, "GL_DSDT_MAG_VIB_NV");
		pushInt(t, GL_HILO16_NV); newGlobal(t, "GL_HILO16_NV");
		pushInt(t, GL_SIGNED_HILO_NV); newGlobal(t, "GL_SIGNED_HILO_NV");
		pushInt(t, GL_SIGNED_HILO16_NV); newGlobal(t, "GL_SIGNED_HILO16_NV");
		pushInt(t, GL_SIGNED_RGBA_NV); newGlobal(t, "GL_SIGNED_RGBA_NV");
		pushInt(t, GL_SIGNED_RGBA8_NV); newGlobal(t, "GL_SIGNED_RGBA8_NV");
		pushInt(t, GL_SIGNED_RGB_NV); newGlobal(t, "GL_SIGNED_RGB_NV");
		pushInt(t, GL_SIGNED_RGB8_NV); newGlobal(t, "GL_SIGNED_RGB8_NV");
		pushInt(t, GL_SIGNED_LUMINANCE_NV); newGlobal(t, "GL_SIGNED_LUMINANCE_NV");
		pushInt(t, GL_SIGNED_LUMINANCE8_NV); newGlobal(t, "GL_SIGNED_LUMINANCE8_NV");
		pushInt(t, GL_SIGNED_LUMINANCE_ALPHA_NV); newGlobal(t, "GL_SIGNED_LUMINANCE_ALPHA_NV");
		pushInt(t, GL_SIGNED_LUMINANCE8_ALPHA8_NV); newGlobal(t, "GL_SIGNED_LUMINANCE8_ALPHA8_NV");
		pushInt(t, GL_SIGNED_ALPHA_NV); newGlobal(t, "GL_SIGNED_ALPHA_NV");
		pushInt(t, GL_SIGNED_ALPHA8_NV); newGlobal(t, "GL_SIGNED_ALPHA8_NV");
		pushInt(t, GL_SIGNED_INTENSITY_NV); newGlobal(t, "GL_SIGNED_INTENSITY_NV");
		pushInt(t, GL_SIGNED_INTENSITY8_NV); newGlobal(t, "GL_SIGNED_INTENSITY8_NV");
		pushInt(t, GL_DSDT8_NV); newGlobal(t, "GL_DSDT8_NV");
		pushInt(t, GL_DSDT8_MAG8_NV); newGlobal(t, "GL_DSDT8_MAG8_NV");
		pushInt(t, GL_DSDT8_MAG8_INTENSITY8_NV); newGlobal(t, "GL_DSDT8_MAG8_INTENSITY8_NV");
		pushInt(t, GL_SIGNED_RGB_UNSIGNED_ALPHA_NV); newGlobal(t, "GL_SIGNED_RGB_UNSIGNED_ALPHA_NV");
		pushInt(t, GL_SIGNED_RGB8_UNSIGNED_ALPHA8_NV); newGlobal(t, "GL_SIGNED_RGB8_UNSIGNED_ALPHA8_NV");
		pushInt(t, GL_HI_SCALE_NV); newGlobal(t, "GL_HI_SCALE_NV");
		pushInt(t, GL_LO_SCALE_NV); newGlobal(t, "GL_LO_SCALE_NV");
		pushInt(t, GL_DS_SCALE_NV); newGlobal(t, "GL_DS_SCALE_NV");
		pushInt(t, GL_DT_SCALE_NV); newGlobal(t, "GL_DT_SCALE_NV");
		pushInt(t, GL_MAGNITUDE_SCALE_NV); newGlobal(t, "GL_MAGNITUDE_SCALE_NV");
		pushInt(t, GL_VIBRANCE_SCALE_NV); newGlobal(t, "GL_VIBRANCE_SCALE_NV");
		pushInt(t, GL_HI_BIAS_NV); newGlobal(t, "GL_HI_BIAS_NV");
		pushInt(t, GL_LO_BIAS_NV); newGlobal(t, "GL_LO_BIAS_NV");
		pushInt(t, GL_DS_BIAS_NV); newGlobal(t, "GL_DS_BIAS_NV");
		pushInt(t, GL_DT_BIAS_NV); newGlobal(t, "GL_DT_BIAS_NV");
		pushInt(t, GL_MAGNITUDE_BIAS_NV); newGlobal(t, "GL_MAGNITUDE_BIAS_NV");
		pushInt(t, GL_VIBRANCE_BIAS_NV); newGlobal(t, "GL_VIBRANCE_BIAS_NV");
		pushInt(t, GL_TEXTURE_BORDER_VALUES_NV); newGlobal(t, "GL_TEXTURE_BORDER_VALUES_NV");
		pushInt(t, GL_TEXTURE_HI_SIZE_NV); newGlobal(t, "GL_TEXTURE_HI_SIZE_NV");
		pushInt(t, GL_TEXTURE_LO_SIZE_NV); newGlobal(t, "GL_TEXTURE_LO_SIZE_NV");
		pushInt(t, GL_TEXTURE_DS_SIZE_NV); newGlobal(t, "GL_TEXTURE_DS_SIZE_NV");
		pushInt(t, GL_TEXTURE_DT_SIZE_NV); newGlobal(t, "GL_TEXTURE_DT_SIZE_NV");
		pushInt(t, GL_TEXTURE_MAG_SIZE_NV); newGlobal(t, "GL_TEXTURE_MAG_SIZE_NV");
	}

	if(NVTextureShader2.isEnabled)
	{
		pushInt(t, GL_DOT_PRODUCT_TEXTURE_3D_NV); newGlobal(t, "GL_DOT_PRODUCT_TEXTURE_3D_NV");
	}

	if(NVTextureShader3.isEnabled)
	{
		pushInt(t, GL_OFFSET_PROJECTIVE_TEXTURE_2D_NV); newGlobal(t, "GL_OFFSET_PROJECTIVE_TEXTURE_2D_NV");
		pushInt(t, GL_OFFSET_PROJECTIVE_TEXTURE_2D_SCALE_NV); newGlobal(t, "GL_OFFSET_PROJECTIVE_TEXTURE_2D_SCALE_NV");
		pushInt(t, GL_OFFSET_PROJECTIVE_TEXTURE_RECTANGLE_NV); newGlobal(t, "GL_OFFSET_PROJECTIVE_TEXTURE_RECTANGLE_NV");
		pushInt(t, GL_OFFSET_PROJECTIVE_TEXTURE_RECTANGLE_SCALE_NV); newGlobal(t, "GL_OFFSET_PROJECTIVE_TEXTURE_RECTANGLE_SCALE_NV");
		pushInt(t, GL_OFFSET_HILO_TEXTURE_2D_NV); newGlobal(t, "GL_OFFSET_HILO_TEXTURE_2D_NV");
		pushInt(t, GL_OFFSET_HILO_TEXTURE_RECTANGLE_NV); newGlobal(t, "GL_OFFSET_HILO_TEXTURE_RECTANGLE_NV");
		pushInt(t, GL_OFFSET_HILO_PROJECTIVE_TEXTURE_2D_NV); newGlobal(t, "GL_OFFSET_HILO_PROJECTIVE_TEXTURE_2D_NV");
		pushInt(t, GL_OFFSET_HILO_PROJECTIVE_TEXTURE_RECTANGLE_NV); newGlobal(t, "GL_OFFSET_HILO_PROJECTIVE_TEXTURE_RECTANGLE_NV");
		pushInt(t, GL_DEPENDENT_HILO_TEXTURE_2D_NV); newGlobal(t, "GL_DEPENDENT_HILO_TEXTURE_2D_NV");
		pushInt(t, GL_DEPENDENT_RGB_TEXTURE_3D_NV); newGlobal(t, "GL_DEPENDENT_RGB_TEXTURE_3D_NV");
		pushInt(t, GL_DEPENDENT_RGB_TEXTURE_CUBE_MAP_NV); newGlobal(t, "GL_DEPENDENT_RGB_TEXTURE_CUBE_MAP_NV");
		pushInt(t, GL_DOT_PRODUCT_PASS_THROUGH_NV); newGlobal(t, "GL_DOT_PRODUCT_PASS_THROUGH_NV");
		pushInt(t, GL_DOT_PRODUCT_TEXTURE_1D_NV); newGlobal(t, "GL_DOT_PRODUCT_TEXTURE_1D_NV");
		pushInt(t, GL_DOT_PRODUCT_AFFINE_DEPTH_REPLACE_NV); newGlobal(t, "GL_DOT_PRODUCT_AFFINE_DEPTH_REPLACE_NV");
		pushInt(t, GL_HILO8_NV); newGlobal(t, "GL_HILO8_NV");
		pushInt(t, GL_SIGNED_HILO8_NV); newGlobal(t, "GL_SIGNED_HILO8_NV");
		pushInt(t, GL_FORCE_BLUE_TO_ONE_NV); newGlobal(t, "GL_FORCE_BLUE_TO_ONE_NV");
	}

	if(NVTransformFeedback.isEnabled)
	{
		register(t, &wrapGL!(glBeginTransformFeedbackNV), "glBeginTransformFeedbackNV");
		register(t, &wrapGL!(glEndTransformFeedbackNV), "glEndTransformFeedbackNV");
		register(t, &wrapGL!(glTransformFeedbackAttribsNV), "glTransformFeedbackAttribsNV");
		register(t, &wrapGL!(glBindBufferRangeNV), "glBindBufferRangeNV");
		register(t, &wrapGL!(glBindBufferOffsetNV), "glBindBufferOffsetNV");
		register(t, &wrapGL!(glBindBufferBaseNV), "glBindBufferBaseNV");
		register(t, &wrapGL!(glTransformFeedbackVaryingsNV), "glTransformFeedbackVaryingsNV");
		register(t, &wrapGL!(glActiveVaryingNV), "glActiveVaryingNV");
		register(t, &wrapGL!(glGetVaryingLocationNV), "glGetVaryingLocationNV");
		register(t, &wrapGL!(glGetActiveVaryingNV), "glGetActiveVaryingNV");
		register(t, &wrapGL!(glGetTransformFeedbackVaryingNV), "glGetTransformFeedbackVaryingNV");

		pushInt(t, GL_BACK_PRIMARY_COLOR_NV); newGlobal(t, "GL_BACK_PRIMARY_COLOR_NV");
		pushInt(t, GL_BACK_SECONDARY_COLOR_NV); newGlobal(t, "GL_BACK_SECONDARY_COLOR_NV");
		pushInt(t, GL_TEXTURE_COORD_NV); newGlobal(t, "GL_TEXTURE_COORD_NV");
		pushInt(t, GL_CLIP_DISTANCE_NV); newGlobal(t, "GL_CLIP_DISTANCE_NV");
		pushInt(t, GL_VERTEX_ID_NV); newGlobal(t, "GL_VERTEX_ID_NV");
		pushInt(t, GL_PRIMITIVE_ID_NV); newGlobal(t, "GL_PRIMITIVE_ID_NV");
		pushInt(t, GL_GENERIC_ATTRIB_NV); newGlobal(t, "GL_GENERIC_ATTRIB_NV");
		pushInt(t, GL_TRANSFORM_FEEDBACK_ATTRIBS_NV); newGlobal(t, "GL_TRANSFORM_FEEDBACK_ATTRIBS_NV");
		pushInt(t, GL_TRANSFORM_FEEDBACK_BUFFER_MODE_NV); newGlobal(t, "GL_TRANSFORM_FEEDBACK_BUFFER_MODE_NV");
		pushInt(t, GL_MAX_TRANSFORM_FEEDBACK_SEPARATE_COMPONENTS_NV); newGlobal(t, "GL_MAX_TRANSFORM_FEEDBACK_SEPARATE_COMPONENTS_NV");
		pushInt(t, GL_ACTIVE_VARYINGS_NV); newGlobal(t, "GL_ACTIVE_VARYINGS_NV");
		pushInt(t, GL_ACTIVE_VARYING_MAX_LENGTH_NV); newGlobal(t, "GL_ACTIVE_VARYING_MAX_LENGTH_NV");
		pushInt(t, GL_TRANSFORM_FEEDBACK_VARYINGS_NV); newGlobal(t, "GL_TRANSFORM_FEEDBACK_VARYINGS_NV");
		pushInt(t, GL_TRANSFORM_FEEDBACK_BUFFER_START_NV); newGlobal(t, "GL_TRANSFORM_FEEDBACK_BUFFER_START_NV");
		pushInt(t, GL_TRANSFORM_FEEDBACK_BUFFER_SIZE_NV); newGlobal(t, "GL_TRANSFORM_FEEDBACK_BUFFER_SIZE_NV");
		pushInt(t, GL_TRANSFORM_FEEDBACK_RECORD_NV); newGlobal(t, "GL_TRANSFORM_FEEDBACK_RECORD_NV");
		pushInt(t, GL_PRIMITIVES_GENERATED_NV); newGlobal(t, "GL_PRIMITIVES_GENERATED_NV");
		pushInt(t, GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN_NV); newGlobal(t, "GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN_NV");
		pushInt(t, GL_RASTERIZER_DISCARD_NV); newGlobal(t, "GL_RASTERIZER_DISCARD_NV");
		pushInt(t, GL_MAX_TRANSFORM_FEEDBACK_INTERLEAVED_ATTRIBS_NV); newGlobal(t, "GL_MAX_TRANSFORM_FEEDBACK_INTERLEAVED_ATTRIBS_NV");
		pushInt(t, GL_MAX_TRANSFORM_FEEDBACK_SEPARATE_ATTRIBS_NV); newGlobal(t, "GL_MAX_TRANSFORM_FEEDBACK_SEPARATE_ATTRIBS_NV");
		pushInt(t, GL_INTERLEAVED_ATTRIBS_NV); newGlobal(t, "GL_INTERLEAVED_ATTRIBS_NV");
		pushInt(t, GL_SEPARATE_ATTRIBS_NV); newGlobal(t, "GL_SEPARATE_ATTRIBS_NV");
		pushInt(t, GL_TRANSFORM_FEEDBACK_BUFFER_NV); newGlobal(t, "GL_TRANSFORM_FEEDBACK_BUFFER_NV");
		pushInt(t, GL_TRANSFORM_FEEDBACK_BUFFER_BINDING_NV); newGlobal(t, "GL_TRANSFORM_FEEDBACK_BUFFER_BINDING_NV");
	}

	if(NVVertexArrayRange.isEnabled)
	{
		register(t, &wrapGL!(glFlushVertexArrayRangeNV), "glFlushVertexArrayRangeNV");
		register(t, &wrapGL!(glVertexArrayRangeNV), "glVertexArrayRangeNV");

		pushInt(t, GL_VERTEX_ARRAY_RANGE_NV); newGlobal(t, "GL_VERTEX_ARRAY_RANGE_NV");
		pushInt(t, GL_VERTEX_ARRAY_RANGE_LENGTH_NV); newGlobal(t, "GL_VERTEX_ARRAY_RANGE_LENGTH_NV");
		pushInt(t, GL_VERTEX_ARRAY_RANGE_VALID_NV); newGlobal(t, "GL_VERTEX_ARRAY_RANGE_VALID_NV");
		pushInt(t, GL_MAX_VERTEX_ARRAY_RANGE_ELEMENT_NV); newGlobal(t, "GL_MAX_VERTEX_ARRAY_RANGE_ELEMENT_NV");
		pushInt(t, GL_VERTEX_ARRAY_RANGE_POINTER_NV); newGlobal(t, "GL_VERTEX_ARRAY_RANGE_POINTER_NV");
	}

	if(NVVertexArrayRange2.isEnabled)
	{
		pushInt(t, GL_VERTEX_ARRAY_WITHOUT_FLUSH_NV); newGlobal(t, "GL_VERTEX_ARRAY_WITHOUT_FLUSH_NV");
	}

	if(NVVertexProgram.isEnabled)
	{
		register(t, &wrapGL!(glAreProgramsResidentNV), "glAreProgramsResidentNV");
		register(t, &wrapGL!(glBindProgramNV), "glBindProgramNV");
		register(t, &wrapGL!(glDeleteProgramsNV), "glDeleteProgramsNV");
		register(t, &wrapGL!(glExecuteProgramNV), "glExecuteProgramNV");
		register(t, &wrapGL!(glGenProgramsNV), "glGenProgramsNV");
		register(t, &wrapGL!(glGetProgramParameterdvNV), "glGetProgramParameterdvNV");
		register(t, &wrapGL!(glGetProgramParameterfvNV), "glGetProgramParameterfvNV");
		register(t, &wrapGL!(glGetProgramivNV), "glGetProgramivNV");
		register(t, &wrapGL!(glGetProgramStringNV), "glGetProgramStringNV");
		register(t, &wrapGL!(glGetTrackMatrixivNV), "glGetTrackMatrixivNV");
		register(t, &wrapGL!(glGetVertexAttribdvNV), "glGetVertexAttribdvNV");
		register(t, &wrapGL!(glGetVertexAttribfvNV), "glGetVertexAttribfvNV");
		register(t, &wrapGL!(glGetVertexAttribivNV), "glGetVertexAttribivNV");
		register(t, &wrapGL!(glGetVertexAttribPointervNV), "glGetVertexAttribPointervNV");
		register(t, &wrapGL!(glIsProgramNV), "glIsProgramNV");
		register(t, &wrapGL!(glLoadProgramNV), "glLoadProgramNV");
		register(t, &wrapGL!(glProgramParameter4dNV), "glProgramParameter4dNV");
		register(t, &wrapGL!(glProgramParameter4dvNV), "glProgramParameter4dvNV");
		register(t, &wrapGL!(glProgramParameter4fNV), "glProgramParameter4fNV");
		register(t, &wrapGL!(glProgramParameter4fvNV), "glProgramParameter4fvNV");
		register(t, &wrapGL!(glProgramParameters4dvNV), "glProgramParameters4dvNV");
		register(t, &wrapGL!(glProgramParameters4fvNV), "glProgramParameters4fvNV");
		register(t, &wrapGL!(glRequestResidentProgramsNV), "glRequestResidentProgramsNV");
		register(t, &wrapGL!(glTrackMatrixNV), "glTrackMatrixNV");
		register(t, &wrapGL!(glVertexAttribPointerNV), "glVertexAttribPointerNV");
		register(t, &wrapGL!(glVertexAttrib1dNV), "glVertexAttrib1dNV");
		register(t, &wrapGL!(glVertexAttrib1dvNV), "glVertexAttrib1dvNV");
		register(t, &wrapGL!(glVertexAttrib1fNV), "glVertexAttrib1fNV");
		register(t, &wrapGL!(glVertexAttrib1fvNV), "glVertexAttrib1fvNV");
		register(t, &wrapGL!(glVertexAttrib1sNV), "glVertexAttrib1sNV");
		register(t, &wrapGL!(glVertexAttrib1svNV), "glVertexAttrib1svNV");
		register(t, &wrapGL!(glVertexAttrib2dNV), "glVertexAttrib2dNV");
		register(t, &wrapGL!(glVertexAttrib2dvNV), "glVertexAttrib2dvNV");
		register(t, &wrapGL!(glVertexAttrib2fNV), "glVertexAttrib2fNV");
		register(t, &wrapGL!(glVertexAttrib2fvNV), "glVertexAttrib2fvNV");
		register(t, &wrapGL!(glVertexAttrib2sNV), "glVertexAttrib2sNV");
		register(t, &wrapGL!(glVertexAttrib2svNV), "glVertexAttrib2svNV");
		register(t, &wrapGL!(glVertexAttrib3dNV), "glVertexAttrib3dNV");
		register(t, &wrapGL!(glVertexAttrib3dvNV), "glVertexAttrib3dvNV");
		register(t, &wrapGL!(glVertexAttrib3fNV), "glVertexAttrib3fNV");
		register(t, &wrapGL!(glVertexAttrib3fvNV), "glVertexAttrib3fvNV");
		register(t, &wrapGL!(glVertexAttrib3sNV), "glVertexAttrib3sNV");
		register(t, &wrapGL!(glVertexAttrib3svNV), "glVertexAttrib3svNV");
		register(t, &wrapGL!(glVertexAttrib4dNV), "glVertexAttrib4dNV");
		register(t, &wrapGL!(glVertexAttrib4dvNV), "glVertexAttrib4dvNV");
		register(t, &wrapGL!(glVertexAttrib4fNV), "glVertexAttrib4fNV");
		register(t, &wrapGL!(glVertexAttrib4fvNV), "glVertexAttrib4fvNV");
		register(t, &wrapGL!(glVertexAttrib4sNV), "glVertexAttrib4sNV");
		register(t, &wrapGL!(glVertexAttrib4svNV), "glVertexAttrib4svNV");
		register(t, &wrapGL!(glVertexAttrib4ubNV), "glVertexAttrib4ubNV");
		register(t, &wrapGL!(glVertexAttrib4ubvNV), "glVertexAttrib4ubvNV");
		register(t, &wrapGL!(glVertexAttribs1dvNV), "glVertexAttribs1dvNV");
		register(t, &wrapGL!(glVertexAttribs1fvNV), "glVertexAttribs1fvNV");
		register(t, &wrapGL!(glVertexAttribs1svNV), "glVertexAttribs1svNV");
		register(t, &wrapGL!(glVertexAttribs2dvNV), "glVertexAttribs2dvNV");
		register(t, &wrapGL!(glVertexAttribs2fvNV), "glVertexAttribs2fvNV");
		register(t, &wrapGL!(glVertexAttribs2svNV), "glVertexAttribs2svNV");
		register(t, &wrapGL!(glVertexAttribs3dvNV), "glVertexAttribs3dvNV");
		register(t, &wrapGL!(glVertexAttribs3fvNV), "glVertexAttribs3fvNV");
		register(t, &wrapGL!(glVertexAttribs3svNV), "glVertexAttribs3svNV");
		register(t, &wrapGL!(glVertexAttribs4dvNV), "glVertexAttribs4dvNV");
		register(t, &wrapGL!(glVertexAttribs4fvNV), "glVertexAttribs4fvNV");
		register(t, &wrapGL!(glVertexAttribs4svNV), "glVertexAttribs4svNV");
		register(t, &wrapGL!(glVertexAttribs4ubvNV), "glVertexAttribs4ubvNV");

		pushInt(t, GL_VERTEX_PROGRAM_NV); newGlobal(t, "GL_VERTEX_PROGRAM_NV");
		pushInt(t, GL_VERTEX_STATE_PROGRAM_NV); newGlobal(t, "GL_VERTEX_STATE_PROGRAM_NV");
		pushInt(t, GL_ATTRIB_ARRAY_SIZE_NV); newGlobal(t, "GL_ATTRIB_ARRAY_SIZE_NV");
		pushInt(t, GL_ATTRIB_ARRAY_STRIDE_NV); newGlobal(t, "GL_ATTRIB_ARRAY_STRIDE_NV");
		pushInt(t, GL_ATTRIB_ARRAY_TYPE_NV); newGlobal(t, "GL_ATTRIB_ARRAY_TYPE_NV");
		pushInt(t, GL_CURRENT_ATTRIB_NV); newGlobal(t, "GL_CURRENT_ATTRIB_NV");
		pushInt(t, GL_PROGRAM_LENGTH_NV); newGlobal(t, "GL_PROGRAM_LENGTH_NV");
		pushInt(t, GL_PROGRAM_STRING_NV); newGlobal(t, "GL_PROGRAM_STRING_NV");
		pushInt(t, GL_MODELVIEW_PROJECTION_NV); newGlobal(t, "GL_MODELVIEW_PROJECTION_NV");
		pushInt(t, GL_IDENTITY_NV); newGlobal(t, "GL_IDENTITY_NV");
		pushInt(t, GL_INVERSE_NV); newGlobal(t, "GL_INVERSE_NV");
		pushInt(t, GL_TRANSPOSE_NV); newGlobal(t, "GL_TRANSPOSE_NV");
		pushInt(t, GL_INVERSE_TRANSPOSE_NV); newGlobal(t, "GL_INVERSE_TRANSPOSE_NV");
		pushInt(t, GL_MAX_TRACK_MATRIX_STACK_DEPTH_NV); newGlobal(t, "GL_MAX_TRACK_MATRIX_STACK_DEPTH_NV");
		pushInt(t, GL_MAX_TRACK_MATRICES_NV); newGlobal(t, "GL_MAX_TRACK_MATRICES_NV");
		pushInt(t, GL_MATRIX0_NV); newGlobal(t, "GL_MATRIX0_NV");
		pushInt(t, GL_MATRIX1_NV); newGlobal(t, "GL_MATRIX1_NV");
		pushInt(t, GL_MATRIX2_NV); newGlobal(t, "GL_MATRIX2_NV");
		pushInt(t, GL_MATRIX3_NV); newGlobal(t, "GL_MATRIX3_NV");
		pushInt(t, GL_MATRIX4_NV); newGlobal(t, "GL_MATRIX4_NV");
		pushInt(t, GL_MATRIX5_NV); newGlobal(t, "GL_MATRIX5_NV");
		pushInt(t, GL_MATRIX6_NV); newGlobal(t, "GL_MATRIX6_NV");
		pushInt(t, GL_MATRIX7_NV); newGlobal(t, "GL_MATRIX7_NV");
		pushInt(t, GL_CURRENT_MATRIX_STACK_DEPTH_NV); newGlobal(t, "GL_CURRENT_MATRIX_STACK_DEPTH_NV");
		pushInt(t, GL_CURRENT_MATRIX_NV); newGlobal(t, "GL_CURRENT_MATRIX_NV");
		pushInt(t, GL_VERTEX_PROGRAM_POINT_SIZE_NV); newGlobal(t, "GL_VERTEX_PROGRAM_POINT_SIZE_NV");
		pushInt(t, GL_VERTEX_PROGRAM_TWO_SIDE_NV); newGlobal(t, "GL_VERTEX_PROGRAM_TWO_SIDE_NV");
		pushInt(t, GL_PROGRAM_PARAMETER_NV); newGlobal(t, "GL_PROGRAM_PARAMETER_NV");
		pushInt(t, GL_ATTRIB_ARRAY_POINTER_NV); newGlobal(t, "GL_ATTRIB_ARRAY_POINTER_NV");
		pushInt(t, GL_PROGRAM_TARGET_NV); newGlobal(t, "GL_PROGRAM_TARGET_NV");
		pushInt(t, GL_PROGRAM_RESIDENT_NV); newGlobal(t, "GL_PROGRAM_RESIDENT_NV");
		pushInt(t, GL_TRACK_MATRIX_NV); newGlobal(t, "GL_TRACK_MATRIX_NV");
		pushInt(t, GL_TRACK_MATRIX_TRANSFORM_NV); newGlobal(t, "GL_TRACK_MATRIX_TRANSFORM_NV");
		pushInt(t, GL_VERTEX_PROGRAM_BINDING_NV); newGlobal(t, "GL_VERTEX_PROGRAM_BINDING_NV");
		pushInt(t, GL_PROGRAM_ERROR_POSITION_NV); newGlobal(t, "GL_PROGRAM_ERROR_POSITION_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY0_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY0_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY1_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY1_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY2_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY2_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY3_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY3_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY4_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY4_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY5_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY5_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY6_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY6_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY7_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY7_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY8_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY8_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY9_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY9_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY10_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY10_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY11_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY11_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY12_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY12_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY13_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY13_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY14_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY14_NV");
		pushInt(t, GL_VERTEX_ATTRIB_ARRAY15_NV); newGlobal(t, "GL_VERTEX_ATTRIB_ARRAY15_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB0_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB0_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB1_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB1_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB2_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB2_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB3_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB3_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB4_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB4_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB5_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB5_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB6_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB6_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB7_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB7_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB8_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB8_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB9_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB9_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB10_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB10_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB11_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB11_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB12_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB12_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB13_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB13_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB14_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB14_4_NV");
		pushInt(t, GL_MAP1_VERTEX_ATTRIB15_4_NV); newGlobal(t, "GL_MAP1_VERTEX_ATTRIB15_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB0_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB0_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB1_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB1_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB2_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB2_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB3_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB3_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB4_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB4_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB5_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB5_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB6_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB6_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB7_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB7_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB8_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB8_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB9_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB9_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB10_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB10_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB11_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB11_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB12_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB12_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB13_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB13_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB14_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB14_4_NV");
		pushInt(t, GL_MAP2_VERTEX_ATTRIB15_4_NV); newGlobal(t, "GL_MAP2_VERTEX_ATTRIB15_4_NV");
	}

	if(NVVertexProgram2Option.isEnabled && !NVFragmentProgram2.isEnabled)
	{
		pushInt(t, GL_MAX_PROGRAM_EXEC_INSTRUCTIONS_NV); newGlobal(t, "GL_MAX_PROGRAM_EXEC_INSTRUCTIONS_NV");
		pushInt(t, GL_MAX_PROGRAM_CALL_DEPTH_NV); newGlobal(t, "GL_MAX_PROGRAM_CALL_DEPTH_NV");
	}

	// SGI
	if(SGIColorMatrix.isEnabled)
	{
		pushInt(t, GL_COLOR_MATRIX_SGI); newGlobal(t, "GL_COLOR_MATRIX_SGI");
		pushInt(t, GL_COLOR_MATRIX_STACK_DEPTH_SGI); newGlobal(t, "GL_COLOR_MATRIX_STACK_DEPTH_SGI");
		pushInt(t, GL_MAX_COLOR_MATRIX_STACK_DEPTH_SGI); newGlobal(t, "GL_MAX_COLOR_MATRIX_STACK_DEPTH_SGI");
		pushInt(t, GL_POST_COLOR_MATRIX_RED_SCALE_SGI); newGlobal(t, "GL_POST_COLOR_MATRIX_RED_SCALE_SGI");
		pushInt(t, GL_POST_COLOR_MATRIX_GREEN_SCALE_SGI); newGlobal(t, "GL_POST_COLOR_MATRIX_GREEN_SCALE_SGI");
		pushInt(t, GL_POST_COLOR_MATRIX_BLUE_SCALE_SGI); newGlobal(t, "GL_POST_COLOR_MATRIX_BLUE_SCALE_SGI");
		pushInt(t, GL_POST_COLOR_MATRIX_ALPHA_SCALE_SGI); newGlobal(t, "GL_POST_COLOR_MATRIX_ALPHA_SCALE_SGI");
		pushInt(t, GL_POST_COLOR_MATRIX_RED_BIAS_SGI); newGlobal(t, "GL_POST_COLOR_MATRIX_RED_BIAS_SGI");
		pushInt(t, GL_POST_COLOR_MATRIX_GREEN_BIAS_SGI); newGlobal(t, "GL_POST_COLOR_MATRIX_GREEN_BIAS_SGI");
		pushInt(t, GL_POST_COLOR_MATRIX_BLUE_BIAS_SGI); newGlobal(t, "GL_POST_COLOR_MATRIX_BLUE_BIAS_SGI");
		pushInt(t, GL_POST_COLOR_MATRIX_ALPHA_BIAS_SGI); newGlobal(t, "GL_POST_COLOR_MATRIX_ALPHA_BIAS_SGI");
	}

	// SGIS
	if(SGISGenerateMipMap.isEnabled)
	{
		pushInt(t, GL_GENERATE_MIPMAP_SGIS); newGlobal(t, "GL_GENERATE_MIPMAP_SGIS");
		pushInt(t, GL_GENERATE_MIPMAP_HINT_SGIS); newGlobal(t, "GL_GENERATE_MIPMAP_HINT_SGIS");
	}
}

void loadExtensionFlags(CrocThread* t)
{
	// yeah I'd normally use some compile-time magic to automate this crap, but that slows compilation down considerably :P

	// ARB
	pushBool(t, ARBColorBufferFloat.isEnabled); fielda(t, -2, "ARBColorBufferFloat");
	pushBool(t, ARBDepthTexture.isEnabled); fielda(t, -2, "ARBDepthTexture");
	pushBool(t, ARBDrawBuffers.isEnabled); fielda(t, -2, "ARBDrawBuffers");
	pushBool(t, ARBFragmentProgram.isEnabled); fielda(t, -2, "ARBFragmentProgram");
	pushBool(t, ARBFragmentProgramShadow.isEnabled); fielda(t, -2, "ARBFragmentProgramShadow");
	pushBool(t, ARBFragmentShader.isEnabled); fielda(t, -2, "ARBFragmentShader");
	pushBool(t, ARBHalfFloatPixel.isEnabled); fielda(t, -2, "ARBHalfFloatPixel");
	pushBool(t, ARBMatrixPalette.isEnabled); fielda(t, -2, "ARBMatrixPalette");
	pushBool(t, ARBMultisample.isEnabled); fielda(t, -2, "ARBMultisample");
	pushBool(t, ARBMultitexture.isEnabled); fielda(t, -2, "ARBMultitexture");
	pushBool(t, ARBOcclusionQuery.isEnabled); fielda(t, -2, "ARBOcclusionQuery");
	pushBool(t, ARBPixelBufferObject.isEnabled); fielda(t, -2, "ARBPixelBufferObject");
	pushBool(t, ARBPointParameters.isEnabled); fielda(t, -2, "ARBPointParameters");
	pushBool(t, ARBPointSprite.isEnabled); fielda(t, -2, "ARBPointSprite");
	pushBool(t, ARBShaderObjects.isEnabled); fielda(t, -2, "ARBShaderObjects");
	pushBool(t, ARBShadingLanguage100.isEnabled); fielda(t, -2, "ARBShadingLanguage100");
	pushBool(t, ARBShadow.isEnabled); fielda(t, -2, "ARBShadow");
	pushBool(t, ARBShadowAmbient.isEnabled); fielda(t, -2, "ARBShadowAmbient");
	pushBool(t, ARBTextureBorderClamp.isEnabled); fielda(t, -2, "ARBTextureBorderClamp");
	pushBool(t, ARBTextureCompression.isEnabled); fielda(t, -2, "ARBTextureCompression");
	pushBool(t, ARBTextureCubeMap.isEnabled); fielda(t, -2, "ARBTextureCubeMap");
	pushBool(t, ARBTextureEnvAdd.isEnabled); fielda(t, -2, "ARBTextureEnvAdd");
	pushBool(t, ARBTextureEnvCombine.isEnabled); fielda(t, -2, "ARBTextureEnvCombine");
	pushBool(t, ARBTextureEnvCrossbar.isEnabled); fielda(t, -2, "ARBTextureEnvCrossbar");
	pushBool(t, ARBTextureEnvDot3.isEnabled); fielda(t, -2, "ARBTextureEnvDot3");
	pushBool(t, ARBTextureFloat.isEnabled); fielda(t, -2, "ARBTextureFloat");
	pushBool(t, ARBTextureMirroredRepeat.isEnabled); fielda(t, -2, "ARBTextureMirroredRepeat");
	pushBool(t, ARBTextureNonPowerOfTwo.isEnabled); fielda(t, -2, "ARBTextureNonPowerOfTwo");
	pushBool(t, ARBTextureRectangle.isEnabled); fielda(t, -2, "ARBTextureRectangle");
	pushBool(t, ARBTransposeMatrix.isEnabled); fielda(t, -2, "ARBTransposeMatrix");
	pushBool(t, ARBVertexBlend.isEnabled); fielda(t, -2, "ARBVertexBlend");
	pushBool(t, ARBVertexBufferObject.isEnabled); fielda(t, -2, "ARBVertexBufferObject");
	pushBool(t, ARBVertexProgram.isEnabled); fielda(t, -2, "ARBVertexProgram");
	pushBool(t, ARBVertexShader.isEnabled); fielda(t, -2, "ARBVertexShader");
	pushBool(t, ARBWindowPos.isEnabled); fielda(t, -2, "ARBWindowPos");

	// ATI
	pushBool(t, ATIDrawBuffers.isEnabled); fielda(t, -2, "ATIDrawBuffers");
	pushBool(t, ATIElementArray.isEnabled); fielda(t, -2, "ATIElementArray");
	pushBool(t, ATIEnvmapBumpmap.isEnabled); fielda(t, -2, "ATIEnvmapBumpmap");
	pushBool(t, ATIFragmentShader.isEnabled); fielda(t, -2, "ATIFragmentShader");
	pushBool(t, ATIMapObjectBuffer.isEnabled); fielda(t, -2, "ATIMapObjectBuffer");
	pushBool(t, ATIPnTriangles.isEnabled); fielda(t, -2, "ATIPnTriangles");
	pushBool(t, ATISeparateStencil.isEnabled); fielda(t, -2, "ATISeparateStencil");
	pushBool(t, ATIShaderTextureLod.isEnabled); fielda(t, -2, "ATIShaderTextureLod");
	pushBool(t, ATITextFragmentShader.isEnabled); fielda(t, -2, "ATITextFragmentShader");
	pushBool(t, ATITextureCompression3dc.isEnabled); fielda(t, -2, "ATITextureCompression3dc");
	pushBool(t, ATITextureEnvCombine3.isEnabled); fielda(t, -2, "ATITextureEnvCombine3");
	pushBool(t, ATITextureFloat.isEnabled); fielda(t, -2, "ATITextureFloat");
	pushBool(t, ATITextureMirrorOnce.isEnabled); fielda(t, -2, "ATITextureMirrorOnce");
	pushBool(t, ATIVertexArrayObject.isEnabled); fielda(t, -2, "ATIVertexArrayObject");
	pushBool(t, ATIVertexAttribArrayObject.isEnabled); fielda(t, -2, "ATIVertexAttribArrayObject");
	pushBool(t, ATIVertexStreams.isEnabled); fielda(t, -2, "ATIVertexStreams");

	// EXT
	pushBool(t, EXTCgShader.isEnabled); fielda(t, -2, "EXTCgShader");
	pushBool(t, EXTAbgr.isEnabled); fielda(t, -2, "EXTAbgr");
	pushBool(t, EXTBgra.isEnabled); fielda(t, -2, "EXTBgra");
	pushBool(t, EXTBindableUniform.isEnabled); fielda(t, -2, "EXTBindableUniform");
	pushBool(t, EXTBlendColor.isEnabled); fielda(t, -2, "EXTBlendColor");
	pushBool(t, EXTBlendEquationSeparate.isEnabled); fielda(t, -2, "EXTBlendEquationSeparate");
	pushBool(t, EXTBlendFuncSeparate.isEnabled); fielda(t, -2, "EXTBlendFuncSeparate");
	pushBool(t, EXTBlendMinmax.isEnabled); fielda(t, -2, "EXTBlendMinmax");
	pushBool(t, EXTBlendSubtract.isEnabled); fielda(t, -2, "EXTBlendSubtract");
	pushBool(t, EXTClipVolumeHint.isEnabled); fielda(t, -2, "EXTClipVolumeHint");
	pushBool(t, EXTCmyka.isEnabled); fielda(t, -2, "EXTCmyka");
	pushBool(t, EXTColorSubtable.isEnabled); fielda(t, -2, "EXTColorSubtable");
	pushBool(t, EXTCompiledVertexArray.isEnabled); fielda(t, -2, "EXTCompiledVertexArray");
	pushBool(t, EXTConvolution.isEnabled); fielda(t, -2, "EXTConvolution");
	pushBool(t, EXTCoordinateFrame.isEnabled); fielda(t, -2, "EXTCoordinateFrame");
	pushBool(t, EXTCullVertex.isEnabled); fielda(t, -2, "EXTCullVertex");
	pushBool(t, EXTDepthBoundsTest.isEnabled); fielda(t, -2, "EXTDepthBoundsTest");
	pushBool(t, EXTDrawBuffers2.isEnabled); fielda(t, -2, "EXTDrawBuffers2");
	pushBool(t, EXTDrawInstanced.isEnabled); fielda(t, -2, "EXTDrawInstanced");
	pushBool(t, EXTDrawRangeElements.isEnabled); fielda(t, -2, "EXTDrawRangeElements");
	pushBool(t, EXTFogCoord.isEnabled); fielda(t, -2, "EXTFogCoord");
	pushBool(t, EXT422Pixels.isEnabled); fielda(t, -2, "EXTFour22Pixels");
	pushBool(t, EXTFragmentLighting.isEnabled); fielda(t, -2, "EXTFragmentLighting");
	pushBool(t, EXTFramebufferBlit.isEnabled); fielda(t, -2, "EXTFramebufferBlit");
	pushBool(t, EXTFramebufferMultisample.isEnabled); fielda(t, -2, "EXTFramebufferMultisample");
	pushBool(t, EXTFramebufferObject.isEnabled); fielda(t, -2, "EXTFramebufferObject");
	pushBool(t, EXTFramebufferSRGB.isEnabled); fielda(t, -2, "EXTFramebufferSRGB");
	pushBool(t, EXTGeometryShader4.isEnabled); fielda(t, -2, "EXTGeometryShader4");
	pushBool(t, EXTGpuProgramParameters.isEnabled); fielda(t, -2, "EXTGpuProgramParameters");
	pushBool(t, EXTGpuShader4.isEnabled); fielda(t, -2, "EXTGpuShader4");
	pushBool(t, EXTHistogram.isEnabled); fielda(t, -2, "EXTHistogram");
	pushBool(t, EXTLightTexture.isEnabled); fielda(t, -2, "EXTLightTexture");
	pushBool(t, EXTMiscAttribute.isEnabled); fielda(t, -2, "EXTMiscAttribute");
	pushBool(t, EXTMultiDrawArrays.isEnabled); fielda(t, -2, "EXTMultiDrawArrays");
	pushBool(t, EXTMultiSample.isEnabled); fielda(t, -2, "EXTMultiSample");
	pushBool(t, EXTPackedDepthStencil.isEnabled); fielda(t, -2, "EXTPackedDepthStencil");
	pushBool(t, EXTPackedFloat.isEnabled); fielda(t, -2, "EXTPackedFloat");
	pushBool(t, EXTPackedPixels.isEnabled); fielda(t, -2, "EXTPackedPixels");
	pushBool(t, EXTPalettedTexture.isEnabled); fielda(t, -2, "EXTPalettedTexture");
	pushBool(t, EXTPixelBufferObject.isEnabled); fielda(t, -2, "EXTPixelBufferObject");
	pushBool(t, EXTPixelTransform.isEnabled); fielda(t, -2, "EXTPixelTransform");
	pushBool(t, EXTPixelTransformColorTable.isEnabled); fielda(t, -2, "EXTPixelTransformColorTable");
	pushBool(t, EXTPointParameters.isEnabled); fielda(t, -2, "EXTPointParameters");
	pushBool(t, EXTRescaleNormal.isEnabled); fielda(t, -2, "EXTRescaleNormal");
	pushBool(t, EXTSceneMarker.isEnabled); fielda(t, -2, "EXTSceneMarker");
	pushBool(t, EXTSecondaryColor.isEnabled); fielda(t, -2, "EXTSecondaryColor");
	pushBool(t, EXTSeparateSpecularColor.isEnabled); fielda(t, -2, "EXTSeparateSpecularColor");
	pushBool(t, EXTShadowFuncs.isEnabled); fielda(t, -2, "EXTShadowFuncs");
	pushBool(t, EXTSharedTexturePalette.isEnabled); fielda(t, -2, "EXTSharedTexturePalette");
	pushBool(t, EXTStencilClearTag.isEnabled); fielda(t, -2, "EXTStencilClearTag");
	pushBool(t, EXTStencilTwoSide.isEnabled); fielda(t, -2, "EXTStencilTwoSide");
	pushBool(t, EXTStencilWrap.isEnabled); fielda(t, -2, "EXTStencilWrap");
	pushBool(t, EXTTexture3D.isEnabled); fielda(t, -2, "EXTTexture3D");
	pushBool(t, EXTTextureArray.isEnabled); fielda(t, -2, "EXTTextureArray");
	pushBool(t, EXTTextureBufferObject.isEnabled); fielda(t, -2, "EXTTextureBufferObject");
	pushBool(t, EXTTextureCompressionDxt1.isEnabled); fielda(t, -2, "EXTTextureCompressionDxt1");
	pushBool(t, EXTTextureCompressionLatc.isEnabled); fielda(t, -2, "EXTTextureCompressionLatc");
	pushBool(t, EXTTextureCompressionRgtc.isEnabled); fielda(t, -2, "EXTTextureCompressionRgtc");
	pushBool(t, EXTTextureCompressionS3tc.isEnabled); fielda(t, -2, "EXTTextureCompressionS3tc");
	pushBool(t, EXTTextureCubeMap.isEnabled); fielda(t, -2, "EXTTextureCubeMap");
	pushBool(t, EXTTextureEdgeClamp.isEnabled); fielda(t, -2, "EXTTextureEdgeClamp");
	pushBool(t, EXTTextureEnvAdd.isEnabled); fielda(t, -2, "EXTTextureEnvAdd");
	pushBool(t, EXTTextureEnvCombine.isEnabled); fielda(t, -2, "EXTTextureEnvCombine");
	pushBool(t, EXTTextureEnvDot3.isEnabled); fielda(t, -2, "EXTTextureEnvDot3");
	pushBool(t, EXTTextureFilterAnisotropic.isEnabled); fielda(t, -2, "EXTTextureFilterAnisotropic");
	pushBool(t, EXTTextureInteger.isEnabled); fielda(t, -2, "EXTTextureInteger");
	pushBool(t, EXTTextureLodBias.isEnabled); fielda(t, -2, "EXTTextureLodBias");
	pushBool(t, EXTTextureMirrorClamp.isEnabled); fielda(t, -2, "EXTTextureMirrorClamp");
	pushBool(t, EXTTexturePerturbNormal.isEnabled); fielda(t, -2, "EXTTexturePerturbNormal");
	pushBool(t, EXTTextureRectangle.isEnabled); fielda(t, -2, "EXTTextureRectangle");
	pushBool(t, EXTTextureSRGB.isEnabled); fielda(t, -2, "EXTTextureSRGB");
	pushBool(t, EXTTimerQuery.isEnabled); fielda(t, -2, "EXTTimerQuery");
	pushBool(t, EXTVertexShader.isEnabled); fielda(t, -2, "EXTVertexShader");
	pushBool(t, EXTVertexWeighting.isEnabled); fielda(t, -2, "EXTVertexWeighting");

	// HP
	pushBool(t, HPConvolutionBorderModes.isEnabled); fielda(t, -2, "HPConvolutionBorderModes");

	// NV
	pushBool(t, NVBlendSquare.isEnabled); fielda(t, -2, "NVBlendSquare");
	pushBool(t, NVCopyDepthToColor.isEnabled); fielda(t, -2, "NVCopyDepthToColor");
	pushBool(t, NVDepthBufferFloat.isEnabled); fielda(t, -2, "NVDepthBufferFloat");
	pushBool(t, NVDepthClamp.isEnabled); fielda(t, -2, "NVDepthClamp");
	pushBool(t, NVEvaluators.isEnabled); fielda(t, -2, "NVEvaluators");
	pushBool(t, NVFence.isEnabled); fielda(t, -2, "NVFence");
	pushBool(t, NVFloatBuffer.isEnabled); fielda(t, -2, "NVFloatBuffer");
	pushBool(t, NVFogDistance.isEnabled); fielda(t, -2, "NVFogDistance");
	pushBool(t, NVFragmentProgram.isEnabled); fielda(t, -2, "NVFragmentProgram");
	pushBool(t, NVFragmentProgram2.isEnabled); fielda(t, -2, "NVFragmentProgram2");
	pushBool(t, NVFragmentProgram4.isEnabled); fielda(t, -2, "NVFragmentProgram4");
	pushBool(t, NVFragmentProgramOption.isEnabled); fielda(t, -2, "NVFragmentProgramOption");
	pushBool(t, NVFramebufferMultisampleCoverage.isEnabled); fielda(t, -2, "NVFramebufferMultisampleCoverage");
	pushBool(t, NVGeometryProgram4.isEnabled); fielda(t, -2, "NVGeometryProgram4");
	pushBool(t, NVGeometryShader4.isEnabled); fielda(t, -2, "NVGeometryShader4");
	pushBool(t, NVGpuProgram4.isEnabled); fielda(t, -2, "NVGpuProgram4");
	pushBool(t, NVHalfFloat.isEnabled); fielda(t, -2, "NVHalfFloat");
	pushBool(t, NVLightMaxExponent.isEnabled); fielda(t, -2, "NVLightMaxExponent");
	pushBool(t, NVMultisampleFilterHint.isEnabled); fielda(t, -2, "NVMultisampleFilterHint");
	pushBool(t, NVOcclusionQuery.isEnabled); fielda(t, -2, "NVOcclusionQuery");
	pushBool(t, NVPackedDepthStencil.isEnabled); fielda(t, -2, "NVPackedDepthStencil");
	pushBool(t, NVParameterBufferObject.isEnabled); fielda(t, -2, "NVParameterBufferObject");
	pushBool(t, NVPixelDataRange.isEnabled); fielda(t, -2, "NVPixelDataRange");
	pushBool(t, NVPointSprite.isEnabled); fielda(t, -2, "NVPointSprite");
	pushBool(t, NVPrimitiveRestart.isEnabled); fielda(t, -2, "NVPrimitiveRestart");
	pushBool(t, NVRegisterCombiners.isEnabled); fielda(t, -2, "NVRegisterCombiners");
	pushBool(t, NVRegisterCombiners2.isEnabled); fielda(t, -2, "NVRegisterCombiners2");
	pushBool(t, NVTexgenEmboss.isEnabled); fielda(t, -2, "NVTexgenEmboss");
	pushBool(t, NVTexgenReflection.isEnabled); fielda(t, -2, "NVTexgenReflection");
	pushBool(t, NVTextureCompressionVtc.isEnabled); fielda(t, -2, "NVTextureCompressionVtc");
	pushBool(t, NVTextureEnvCombine4.isEnabled); fielda(t, -2, "NVTextureEnvCombine4");
	pushBool(t, NVTextureExpandNormal.isEnabled); fielda(t, -2, "NVTextureExpandNormal");
	pushBool(t, NVTextureRectangle.isEnabled); fielda(t, -2, "NVTextureRectangle");
	pushBool(t, NVTextureShader.isEnabled); fielda(t, -2, "NVTextureShader");
	pushBool(t, NVTextureShader2.isEnabled); fielda(t, -2, "NVTextureShader2");
	pushBool(t, NVTextureShader3.isEnabled); fielda(t, -2, "NVTextureShader3");
	pushBool(t, NVTransformFeedback.isEnabled); fielda(t, -2, "NVTransformFeedback");
	pushBool(t, NVVertexArrayRange.isEnabled); fielda(t, -2, "NVVertexArrayRange");
	pushBool(t, NVVertexArrayRange2.isEnabled); fielda(t, -2, "NVVertexArrayRange2");
	pushBool(t, NVVertexProgram.isEnabled); fielda(t, -2, "NVVertexProgram");
	pushBool(t, NVVertexProgram11.isEnabled); fielda(t, -2, "NVVertexProgram11");
	pushBool(t, NVVertexProgram2.isEnabled); fielda(t, -2, "NVVertexProgram2");
	pushBool(t, NVVertexProgram2Option.isEnabled); fielda(t, -2, "NVVertexProgram2Option");
	pushBool(t, NVVertexProgram3.isEnabled); fielda(t, -2, "NVVertexProgram3");
	pushBool(t, NVVertexProgram4.isEnabled); fielda(t, -2, "NVVertexProgram4");

	// SGI
	pushBool(t, SGIColorMatrix.isEnabled); fielda(t, -2, "SGIColorMatrix");

	// SGIS
	pushBool(t, SGISGenerateMipMap.isEnabled); fielda(t, -2, "SGISGenerateMipMap");
}

}