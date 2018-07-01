require("globals")
require("utils")
require("camera")
require("objects.all")
require("level")
require("collision")




local t = {
	x = 5,
	
	f = function()
		print("hi!")
	end,
}

local a = {1, 2, 3}

for i = 1, #a do
	print(a[i])
end

local x = 5
x = x+10
do local __augtmp__, __augidx__ = t, "x"; __augtmp__[__augidx__] = __augtmp__[__augidx__] + 1 end

function love.load()
	
	GX.setDefaultFilter("nearest", "nearest")
	Player_Texture = GX.newImage("gfx/spritesheet_players.png")
	Enemy_Texture = GX.newImage("gfx/enemies/enemies.png")
	Player = Object_New("Obj_Player")
	Level_Load("maps/welcome.lua")
end

function love.update(dt)
	
	if DBG_Freeze then
		
		if DBG_Step then
			DBG_Step = false
		
		else return
		end end
	
	Player.jumpHeld = KB.isDown("space")
	Player.duckHeld = KB.isDown("down")
	
	if KB.isDown("left")then
		
		if KB.isDown("right")then
			Player.directionHeld = false
		
		else Player.directionHeld = "left" end
	
	elseif KB.isDown("right")then
		Player.directionHeld = "right"
	
	else Player.directionHeld = false end
	
	Level_Update(dt)
	Camera_Update(dt)
end

function love.keypressed(key)
	
	if key == "escape" then
		love.event.quit()
	elseif key == "space" then
		Player.jumpPressed = true
	elseif key == "down" then
		Player.duckPressed = true
	elseif key == "c" then
		Level_Debug_ToggleDrawCollision()
	elseif key == "return" then
		DBG_Freeze = not DBG_Freeze
	elseif key == "\'" then
		DBG_Step = true end
end

function love.draw()
	
	Camera_Draw()
	
	GX.setColor(255, 255, 255)
	GX.print(
	"FPS: " .. love.timer.getFPS() .. "\n" .. 
	"Objects: " .. NumGameObjects .. "\n" .. 
	Player.state .. "\n" .. 
	(Player.vx) .. ", " .. (Player.vy) .. "\n" .. 
	tostring(Player.animFlipX) .. " " .. tostring(Player.animFlipY) .. "\n" .. 
	"Standing: " .. ((Player.standingObj and tostring(Player.standingObj.type)) or "nil") .. "\n" .. 
	DBGTABLE.msg .. "\n" .. 
	DBGTEXT, 
	2, 0)
end