module tests.iando;

io.changeDir(`tests\files`);

//io.File("foo", io.FileMode.OutNew).close();
io.rename("foo", "bar");
io.copy("bar", "foo");
io.size("foo");
io.exists("foo");
io.isFile("foo");
io.isDir("bar");
io.currentDir();
io.makeDir("dir");
io.removeDir("dir");
io.listDir(io.currentDir());
io.listDir(io.currentDir(), "*.md");
/*local f = io.File("foo");
try io.File("FOASAF"); catch(e){}
f.seek(0, 'c');
f.seek(0, 'e');
f.seek(0, 'b');
try f.seek(0, 'n'); catch(e){}
f.position();
f.position(0);
f.size();
f.close();
f = io.File("foo", io.FileMode.In | io.FileMode.Out);
f.isOpen();
f.eof();
f.available();
f.flush();
f.writeInt(4);
f.writeString("hi");
f.writeLine("hello");
f.writef("bye");
f.writefln("foo");
f.writeChars("xyz");
f.position(0);
f.readInt();
f.readString();
f.readLine();
f.readf("%s");
f.readChars(1);
f.close();

foreach(line; io.File("lines.txt")){}*/

io.remove("foo");
io.remove("bar");
io.changeDir(`..\..`);