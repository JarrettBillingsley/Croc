module tests.interpreter;

local x, y, z;

y = null; try x = #y; catch(e){}
y = true; try x = #y; catch(e){}
y = 4; try x = #y; catch(e){}
y = 4.5; try x = #y; catch(e){}
y = 'h'; try x = #y; catch(e){}
y = {}; x = #y;
y[0] = 1; y[true] = 1; y[4.5] = 1; y['h'] = 1;
y = typeof(5); y = typeof(class{}); y = typeof(class{}());
if(y){}
format(null, true, 4, 4.5, 'g', {});
try if({} < {}){} catch(e){}
try if(class{} < class{}){} catch(e){}
try if({} == {}){} catch(e){}
y = "hi"; x = #y; x = 'h' in y; x = 'z' in y;
if(y == "bye"){}
x = y[0];
x = y[0..];
x = y ~ "hi" ~ y ~ 'h';