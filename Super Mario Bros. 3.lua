--Thanks to Southbird for his SMB3 disassembly and replying to my questions
--I rewrote this script due to my hard drive being wiped, oops. ;P

--toggle features, change to false if you don't want them
local toggle_corner_boost               = true
local toggle_display_hitboxes           = true
local toggle_display_sprite_information = true
local toggle_display_time               = true
local toggle_display_rng                = true
local toggle_display_8_frame_timer      = true
local toggle_display_mario_position     = true
local toggle_display_mario_velocity     = true
local toggle_display_next_p             = true
local toggle_display_p_kill_counter     = true

--variables
local nes_framerate   = 60.0988138974405
local sprite_slots    = 7
local text_color      = "#009900ff"
local text_back_color = "black"

local ram_high_x          = 0x0075
local ram_x               = 0x0090
local ram_low_x           = 0x074D
local ram_relative_x      = 0x00AB
local ram_x_speed         = 0x00BD
local ram_high_y          = 0x0087
local ram_y               = 0x00A2
local ram_low_y           = 0x075F
local ram_relative_y      = 0x00B4
local ram_y_speed         = 0x00CF
local ram_sprites_id      = 0x0670
local ram_sprite_state    = 0x0660
local ram_rng             = 0x0781
local ram_8_frame_timer   = 0x055D
local ram_next_p          = 0x0515
local ram_p_kill_counter  = 0x056E

local rom_sprite_attributes = 0x0304
local rom_sprite_hitboxes   = 0x02C4

local x_prev = 0
local x_speed_prev = 0

local pixel_boost_total = 0
local pixel_boost_negative_total = 0

local hour_frames        = nes_framerate * 3600
local minute_frames      = nes_framerate * 60
local second_frames      = nes_framerate
local centisecond_frames = nes_framerate * (1 / 100)

--the exact x position of mario, down to the sub pixel
function x_total()
    return (memory.readbyte(ram_high_x) * 65536) + (memory.readbyte(ram_x) * 256) + memory.readbyte(ram_low_x)
end

--grab some position and speed values before the next frame
function pre_corner_boost()
    x_prev = x_total()
    x_speed_prev = memory.readbyte(ram_x_speed)
end

--do all preframe calculations
function preframe_calculations()
    pre_corner_boost()
end

function display_hitboxes()
    --didn't bother to search for the screen's position in ram
    local screen = {}
    screen[0]    = ((memory.readbytesigned(ram_high_x) * 256) + memory.readbyte(ram_x)) -  memory.readbyte(ram_relative_x)          --left side
    screen[1]    = ((memory.readbytesigned(ram_high_x) * 256) + memory.readbyte(ram_x)) - (memory.readbyte(ram_relative_x) - 0xff) --right side
    screen[2]    = ((memory.readbytesigned(ram_high_y) * 256) + memory.readbyte(ram_y)) -  memory.readbyte(ram_relative_y)          --top
    screen[3]    = ((memory.readbytesigned(ram_high_y) * 256) + memory.readbyte(ram_y)) - (memory.readbyte(ram_relative_y) - 0xff) --bottom
    
    --find screen if mario is off-screen. Very hacky solution, don't try to analyze this garbage, please.
    for i=0, 3, 1 do
        local loops = 0 --used for odd math issues, unsure of the cause, just going to use a hacky solution, works fine
        while screen[i] < 0 do --loop through the screen sides
            screen[i] = 0xff + screen[i] + (loops > 0 and 1 or 0) --add 0xff to get back to the screen, disguisting solution, I'm so sorry ;P
            local pair = (i % 2) --getting which partner screen[i] is in its pair (by partner I mean left + right or top + bottom)
            if pair == 0 then --if zero, it's the first partner (0 or 2) (left or top)
                pair = 1
            else --else it's the second partner (1, 3) (right or bottom)
                pair = -1
            end
            screen[i + pair] = screen[i + pair] + 0xff + (loops > 0 and 1 or 0) --add to the other partner as well (horizontal or vertical partner)
            loops = loops + 1
        end
    end
    
    local sprites = {}
    for i=sprite_slots-1, 0, -1 do
        sprites[i]    = {}
        sprites[i][0] = memory.readbyte((ram_sprites_id + sprite_slots) - i)   --get sprite id
        sprites[i][1] = memory.readbyte((ram_relative_x + sprite_slots) - i)   --get sprite relative x
        sprites[i][2] = memory.readbyte((ram_relative_y + sprite_slots) - i)   --get sprite relative y
        sprites[i][3] = memory.readbyte((ram_sprite_state + sprite_slots) - i) --get sprite state (alive, dead, etc.)
        sprites[i][4] = memory.readbyte((ram_x + sprite_slots) - i)            --get x
        sprites[i][5] = memory.readbyte((ram_y + sprite_slots) - i)            --get y
        sprites[i][6] = memory.readbyte((ram_low_x + sprite_slots) - i)        --get sub x
        sprites[i][7] = memory.readbyte((ram_low_y + sprite_slots) - i)        --get sub y
        
        if toggle_display_hitboxes then
            local sprite_x = (memory.readbyte((ram_high_x + sprite_slots) - i) * 256) + sprites[i][4] --get specific sprite x (without sub pixel)
            local sprite_y = (memory.readbyte((ram_high_y + sprite_slots) - i) * 256) + sprites[i][5] --get specific sprite y
            if (sprites[i][3] ~= 0) and ((sprite_x - 1 > screen[0]) and (sprite_x + 1 < screen[1]) and (sprite_y - 1 > screen[2]) and (sprite_y + 1 < screen[3])) then --check if within screen, I add or subtract one to be sure
                local hitbox = AND((rom.readbyte(rom_sprite_attributes + sprites[i][0])), 0x0F) * 4 --check the rom for the hitbox index specified by the attributes table + the sprite id. Get the last 4 bits
                                                                                                    --multiply by 4 for searching the table after this, each hitbox consists of four numbers
                local rect = {}
                rect[0] = rom.readbytesigned(rom_sprite_hitboxes + hitbox)     + sprites[i][1] --left; search the hitbox table for offsets for sprite hitboxes, then add in the sprite's position
                rect[1] = rom.readbytesigned(rom_sprite_hitboxes + hitbox + 3) + sprites[i][2] --top
                rect[2] = rom.readbytesigned(rom_sprite_hitboxes + hitbox + 1) + sprites[i][1] --right
                rect[3] = rom.readbytesigned(rom_sprite_hitboxes + hitbox + 2) + sprites[i][2] --bottom
                
                gui.drawrect(rect[0], rect[1], rect[2], rect[3], nil, "red") --draw the actual hitbox
                gui.drawtext(((rect[0] + rect[2]) / 2) - 5, rect[3] - 8, string.format("[" .. i .. "]"), "white", "#00000066") --draw the sprite id above it
            end
        end
    end
    
  local y_counter = 24 --for listing sprites and removing blank spriteslot's spaces
    for i=0, sprite_slots - 1, 1 do
        if toggle_display_sprite_information then
            if (sprites[i][3] ~= 0) then --if you need sprite information to display after the sprite's despawn, change the 0 to -1 in this statement
                gui.drawtext(1, y_counter, string.format(i), text_color, text_back_color)
                gui.drawtext(9, y_counter, string.format("%s%d%s%s%X%s%d%s%s%X%s", "(", sprites[i][4], ".", (sprites[i][6] == 0 and "0" or ""), sprites[i][6], ", ", 
                                                                                        sprites[i][5], ".", (sprites[i][7] == 0 and "0" or ""), sprites[i][7], ")"), text_color, text_back_color) --draw the text
                y_counter = y_counter + 8 --add to y_counter so the next sprite is shown below the previous
            end
        end
    end
end

--calculate if mario moved 1 pixel more than he should have
function post_corner_boost()
    local x_expected = x_total() --expected x
    local x_actual = x_prev + (x_speed_prev * 16) --actual x
    local x_difference = x_expected - x_actual --difference
    pixel_boost_total = pixel_boost_total + (x_difference == 256 and 1 or 0) --if the difference was exactly one, it was a pixel boost
    pixel_boost_negative_total = pixel_boost_negative_total + (x_difference == -256 and 1 or 0) --or a negative boost (wall pushing back, etc.)
    gui.drawtext(1, 9, "Pixel Boost Pos: " .. pixel_boost_total .. "; Neg: " .. pixel_boost_negative_total, text_color, text_back_color) --draw text
end

--convert frames to hours::minutes::seconds.centiseconds, for example 02:15:34:97 is 2 hours, 15 minutes, and 34.97 seconds
function display_time()
    local frames      = movie.framecount() --current frames in movie
    local frames_left = frames --counts how many frames are left after subtracting each unit of time, for example, if a movie is 56312 frames, 
                               --it can be broken into 15 minutes, which is 54089. That leaves about 2223 frames to be broken into about 37 seconds
    
    --do math
    local hours_frames        = frames_left - (frames_left % hour_frames)
    frames_left = frames_left - hours_frames
    local minutes_frames      = frames_left - (frames_left % minute_frames)
    frames_left = frames_left - minutes_frames
    local seconds_frames      = frames_left - (frames_left % second_frames)
    frames_left = frames_left - seconds_frames
    local centiseconds_frames = frames_left
    
    --turn frames into hours, minutes, seconds, and the remainder
    local hours        = math.floor(hours_frames / hour_frames)
    local minutes      = math.floor(minutes_frames / minute_frames)
    local seconds      = math.floor(seconds_frames / second_frames)
    local centiseconds = math.floor(centiseconds_frames / centisecond_frames)
    
    gui.drawtext(198, 224, string.format((hours < 10 and "0" or "") .. hours .. ":" .. (minutes < 10 and "0" or "") .. minutes .. ":" .. 
                                         (seconds < 10 and "0" or "") .. seconds .. "." .. (centiseconds < 10 and "0" or "") .. centiseconds), text_color, text_back_color) --draw it
end

function display_information()

    local y_counter = 9
    if toggle_display_rng then
        local rng = memory.readbyte(ram_rng)
        gui.drawtext(211, y_counter, string.format("RNG: " .. (rng < 100 and (rng < 10 and "00" or "0") or "")) .. rng, text_color, text_back_color)
		y_counter = y_counter + 8
    end
    
    if toggle_display_8_frame_timer then
        gui.drawtext(202, y_counter, string.format("8 Frame: " .. memory.readbyte(ram_8_frame_timer)), text_color, text_back_color)
    end
	
    --display mario information
    if not (toggle_display_mario_position or toggle_display_mario_velocity or toggle_display_next_p or toggle_display_p_kill_counter) then
        return
    end
    
	y_counter = 96
	
    gui.drawtext(1, y_counter, "Mario:", text_color, text_back_color)
    y_counter = y_counter + 8
    
    if toggle_display_mario_position then
        local mario_sub_x = memory.readbyte(ram_low_x)
        local mario_sub_y = memory.readbyte(ram_low_y)
        gui.drawtext(1, y_counter, string.format("%s%d%s%s%X%s%d%s%s%X%s", "Pos: (", memory.readbyte      (ram_x), ".", (mario_sub_x == 0 and "0" or ""), mario_sub_x, ", ", 
                                                                                     memory.readbytesigned(ram_y), ".", (mario_sub_y == 0 and "0" or ""), mario_sub_y, ")"), text_color, text_back_color)
        y_counter = y_counter + 8
    end
    
    if toggle_display_mario_velocity then
        gui.drawtext(1, y_counter, string.format("Speed: (" .. memory.readbytesigned(ram_x_speed) .. ", " .. memory.readbytesigned(ram_y_speed) .. ")"), text_color, text_back_color)
        y_counter = y_counter + 8
    end
    
    if toggle_display_next_p then
        gui.drawtext(1, y_counter, string.format("Next P: " .. memory.readbyte(ram_next_p)), text_color, text_back_color)
        y_counter = y_counter + 8
    end
    
    if toggle_display_p_kill_counter then
        gui.drawtext(1, y_counter, string.format("P Kill Counter: " .. memory.readbyte(ram_p_kill_counter)), text_color, text_back_color)
        y_counter = y_counter + 8
    end
end

--do postframe calculations
function postframe_calculations()
    if toggle_display_hitboxes or toggle_display_sprite_information then
        display_hitboxes()
    end
    
    if toggle_corner_boost then
        post_corner_boost()
    end
    
    if toggle_display_time then
        display_time()
    end
    
    display_information()
end

emu.registerbefore(preframe_calculations)
emu.registerafter(postframe_calculations)
