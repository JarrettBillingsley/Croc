
namespace ImGui
{

int WindowStackDepth()
{
	return GImGui.CurrentWindowStack.size();
}

bool IsInitialized()
{
	return GImGui.Initialized;
}

}