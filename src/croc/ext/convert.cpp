
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv)
{
	if(argc < 2)
		exit(EXIT_FAILURE);

	auto slash = strrchr(argv[1], '/');

	if(slash)
		slash++;
	else
	{
		slash = strrchr(argv[1], '\\');

		if(slash)
			slash++;
		else
			slash = argv[1];
	}

	auto name = (char*)malloc(strlen(slash) + 1);
	strcpy(name, slash);

	for(auto pos = strchr(name, '.'); pos != nullptr; pos = strchr(pos + 1, '.'))
		*pos = '_';

	auto fp = fopen(argv[1], "rb");

	if(fp == nullptr)
		exit(EXIT_FAILURE);

	printf("const char %s_text[] =\n{", name);

	int i = 0;
	char c;
	for( ; (c = fgetc(fp)) != EOF; i++)
	{
		if((i % 20) == 0)
			printf("\n\t");

		printf("%#04x, ", c);
	}

	printf("\n};\n\nconst size_t %s_length = %d;\n", name, i);
	fclose(fp);
	free(name);

	return 0;
}
