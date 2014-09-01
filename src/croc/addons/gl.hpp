#ifndef CROC_ADDONS_GL_HPP
#define CROC_ADDONS_GL_HPP

#include "croc/ext/glad/glad.hpp"

#include "croc/api.h"

namespace croc
{
	void loadOpenGL(CrocThread* t, GLADloadproc load);
}

#endif