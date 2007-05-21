module tests.opsys;

os.microTime();
local p = os.PerfCounter();
p.start();
p.stop();
p.period();
p.seconds();
p.millisecs();
p.microsecs();
