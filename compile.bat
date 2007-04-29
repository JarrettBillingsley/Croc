@echo off

rem goto makemdcl
rem goto makeminidc

:maketest
	build @test
goto end

:makemdcl
	build @mdcl
goto end

:makeminidc
	build @minidc
goto end

:end