import std.string;
import std.stream;
import std.stdio;

void main()
{
	auto File i = new File(`g:\documents and settings\me\desktop\minid opcodes.csv`, FileMode.In);
	auto File o = new File(`g:\documents and settings\me\desktop\out.txt`, FileMode.OutNew);

	foreach(char[] line; i)
	{
		o.writef("||'''");

		bool inQuotes = false;
		bool isFirst = true;

		foreach(char c; line)
		{
			if(c == ',' && !inQuotes)
			{
				if(isFirst)
				{
					o.writef(" '''||");
					isFirst = false;
				}
				else
					o.writef("||");
			}
			else if(c == '\"')
				inQuotes = !inQuotes;
			else
				o.writef(c);
		}

		o.writefln("||");
	}
}