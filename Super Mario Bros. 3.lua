--Thanks to Southbird for his SMB3 disassembly and replying to my questions, sorry for bugging you. :P
--I rewrote this script due to wiping my hard drive.
--TODO optimize everything, make prettier, better explanations

--toggle features, change to false if you don't want them
local toggle_display_pixel_boost                    = true
local toggle_display_sprite_hitboxes                = true
local toggle_display_mario_hitbox                   = true
local toggle_display_sprite_id_above_sprite         = true
local toggle_display_sprite_information             = true
local toggle_display_sprite_information_after_death = false
local toggle_display_time                           = true
local toggle_display_rng                            = true
local toggle_display_is_lagged                      = true
local toggle_display_8_frame_timer                  = true
local toggle_display_mario_position                 = true
local toggle_display_mario_velocity                 = true
local toggle_display_p_meter                        = true
local toggle_display_next_p                         = true
local toggle_display_p_kill_counter                 = true
local toggle_display_block_y                        = true --for walljumps
local toggle_display_rerecords                      = true
local toggle_display_lag_frames                     = true
local toggle_display_frames                         = true
local toggle_display_level                          = true
local toggle_display_screen_in_level                = true
local toggle_display_mario_in_level                 = true
local toggle_display_sprites_in_level               = true
local toggle_display_level_toggleable               = true --able to toggle level with key in get_input
local toggle_display_level_on_overworld             = false
--to change the button to toggle the level, see get_input

--variables
local text_color               = "#009900ff"
local text_faded_color         = "#003300ff"
local text_back_color          = "black"
local text_lag_color           = "red"
local hitbox_edge_color        = "red"
local hitbox_back_color        = nil --default
local sprite_id_text_color     = "white"
local sprite_id_back_color     = "#00000066"
local level_block_color        = "#009900ff"
local level_block_faded_color  = "#003300ff"
local level_sprite_color       = "#990099ff"
local level_sprite_faded_color = "#330033ff"
local level_mario_color        = "red"
local level_back_color         = "black"
local level_horizontal_draw_y  = 196 --y position of drawn level on screen when level is horizontal
local level_vertical_draw_x    = 238 --x position of drawn level on screen when level is vertical

--all of the ram addresses I need, sorry for the garbage (and sometimes inaccurate) names
local ram_mario_suit       = 0x00ED --mario powerup (0 = small, 1 = big, ...)
local ram_is_crouching     = 0x056F --set if mario is crouching
local ram_high_x           = 0x0075 --high byte of mario's x position, when mario's x goes above 0xff, this increases by one
local ram_x                = 0x0090 --mario's x
local ram_low_x            = 0x074D --mario's subpixel x (16 subpixels in a pixel)
local ram_relative_x       = 0x00AB --mario's x position on the screen
local ram_x_speed          = 0x00BD --mario's x speed
local ram_high_y           = 0x0087 --high byte of mario's y position, when mario's y goes above 0xff, this increases by one
local ram_y                = 0x00A2 --mario's y
local ram_low_y            = 0x075F --mario's subpixel y (16 subpixels in a pixel)
local ram_relative_y       = 0x00B4 --mario's y position on the screen
local ram_y_speed          = 0x00CF --mario's y speed
local ram_sprite_id        = 0x0670 --list of the id's of currently loaded, or once loaded sprites
local ram_sprite_state     = 0x0660 --the states of those sprites (0 = dead)
local ram_rng              = 0x0781 --Random Number Generator
local ram_8_frame_timer    = 0x055D --8 frame timer, 0-7
local ram_p_meter          = 0x03DD --P meter
local ram_next_p           = 0x0515 --countdown timer until the next p arrow fills up
local ram_p_kill_counter   = 0x056E --countdown timer until p speed expires
local ram_stack            = 0x0100 --the stack, stores whether the level is horizontal or vertical, oddly enough
local ram_level_data       = 0x6000 --the level stored as tiles
local ram_level_size       = 0x0022 --stores the size of the level in screens
local ram_tile_attr_table  = 0x7E94 --stores 8 bytes which determine whether a tile is solid
local ram_tileset          = 0x070A --which tileset the game is using (0 = level)
local ram_high_horz_scroll = 0x0012 --the screen's high x value
local ram_horz_scroll      = 0x00FD --the screen's x value
local ram_high_vert_scroll = 0x0013 --the screen's high y value
local ram_vert_scroll      = 0x00FC --the screen's y value

--all of the rom addresses I need
local rom_sprite_attributes = 0x0304 --table containing sprite information
local rom_sprite_hitboxes   = 0x02C4 --table storing all 16 possible hitboxes
local rom_mario_hitbox      = 0x183C --mario's hitbox, TODO display mario hitbox, but doesn't want to play nice ;(

local nes_framerate   = 60.0988138974405 --the NES's "exact" frame rate
local sprite_slots    = 7 --8 - mario

local screen_width  = 0x10 --256 pixels, 16 blocks
local screen_height = 0x0F --240 pixels, 15 blocks

local level_horizontal_height = 0x1a         --height of the level if the level is horizontal
local level_vertical_width    = screen_width --width of the level if level is vertical

local x_prev = 0       --used for checking pixel boost (corner/ceiling boost)
local x_speed_prev = 0 --same as x_prev

local pixel_boost_total = 0          --total unexpected pixel change forward
local pixel_boost_negative_total = 0 --total unexpected pixel change backward

local hour_frames        = nes_framerate * 3600      --frames per hour
local minute_frames      = nes_framerate * 60        --frames per minute
local second_frames      = nes_framerate             --frames per second
local centisecond_frames = nes_framerate * (1 / 100) --frames per hundredth of a second

local sprite = {} --array storing sprite information
local screen = {} --screen coordinates and size

local level_toggle = false --if toggle_display_level button is pressed

local buttons = {} --array of buttons
function get_input()
    buttons = input.read() --get buttons
    if toggle_display_level_toggleable then
        if (buttons.enter) and (not level_toggle) then --if button is pressed and toggle hasn't been set
            toggle_display_level = not toggle_display_level --stop displaying the level
            level_toggle = true
        end
        
        if (not buttons.enter) and (level_toggle) then --if button has been let go and toggle is set
            level_toggle = false
        end
    end
end

--the exact x position of mario, down to the sub pixel
function x_total()
    return (memory.readbyte(ram_high_x) * 0x10000) + (memory.readbyte(ram_x) * 0x100) + memory.readbyte(ram_low_x)
end

--grab some position and speed values before the next frame
function pre_pixel_boost()
    x_prev = x_total()
    x_speed_prev = memory.readbyte(ram_x_speed)
end

--do all preframe calculations
function preframe_calculations()
    pre_pixel_boost()
end

function get_screen_information()
    screen[0] = (memory.readbyte(ram_high_horz_scroll) * (screen_width  * 0x10)) + memory.readbyte(ram_horz_scroll)                          --left side
    screen[1] = (memory.readbyte(ram_high_horz_scroll) * (screen_width  * 0x10)) + (screen_width  * 0x10) + memory.readbyte(ram_horz_scroll) --right side
    screen[2] = (memory.readbyte(ram_high_vert_scroll) * (screen_height * 0x10)) + memory.readbyte(ram_vert_scroll)                          --top
    screen[3] = (memory.readbyte(ram_high_vert_scroll) * (screen_height * 0x10)) + (screen_height * 0x10) + memory.readbyte(ram_vert_scroll) --bottom
end

function get_sprite_information()
    for i=1, sprite_slots, 1 do
        sprite[i]       = {} --let each sprite hold many variables
        sprite[i][0]    = memory.readbyte(ram_sprite_id + i)    --get sprite id
        --sprite[i][1]    = memory.readbyte(ram_relative_x + i)   --get sprite relative x
        --sprite[i][2]    = memory.readbyte(ram_relative_y + i)   --get sprite relative y
        --I've opted to calculate relative x and y for "reasons"
        sprite[i][1]    = ((memory.readbytesigned(ram_high_x+i) * 0x100) + memory.readbyte(ram_x+i)) - screen[0]
        sprite[i][2]    = ((memory.readbytesigned(ram_high_y+i) * 0x100) + memory.readbyte(ram_y+i)) - screen[2]
        sprite[i][3]    = memory.readbyte(ram_sprite_state + i) --get sprite state (alive, dead, etc.)
        sprite[i][4]    = memory.readbyte(ram_x + i)            --get x
        sprite[i][5]    = memory.readbyte(ram_y + i)            --get y
        sprite[i][6]    = memory.readbyte(ram_low_x + i)        --get sub x
        sprite[i][7]    = memory.readbyte(ram_low_y + i)        --get sub y
        sprite[i][8]    = AND((rom.readbyte(rom_sprite_attributes + sprite[i][0])), 0x0F) * 4 --hitbox address
        sprite[i][9]    = {} --hitbox offsets
        sprite[i][9][0] = rom.readbytesigned(rom_sprite_hitboxes + sprite[i][8]    ) --left
        sprite[i][9][1] = rom.readbytesigned(rom_sprite_hitboxes + sprite[i][8] + 2) --top
        sprite[i][9][2] = rom.readbytesigned(rom_sprite_hitboxes + sprite[i][8] + 1) --right
        sprite[i][9][3] = rom.readbytesigned(rom_sprite_hitboxes + sprite[i][8] + 3) --bottom
    end
end

function display_sprite_hitboxes()
    for i=1, sprite_slots, 1 do
        local sprite_x = (memory.readbyte(ram_high_x + i) * 0x100) + sprite[i][4] --get specific sprite x (without sub pixel)
        local sprite_y = (memory.readbyte(ram_high_y + i) * 0x100) + sprite[i][5] --get specific sprite y
        
        if (sprite[i][3] ~= 0) and --if alive
          ((sprite_x - 1 > screen[0]) and (sprite_x + 1 < screen[1]) and (sprite_y - 1 > screen[2]) and (sprite_y + 1 < screen[3])) then --check if within screen, I add or subtract one to be sure
            gui.drawrect(sprite[i][9][0] + sprite[i][1], sprite[i][9][1] + sprite[i][2], 
                         sprite[i][9][0] + sprite[i][9][2] + sprite[i][1], sprite[i][9][1] + sprite[i][9][3] + sprite[i][2], hitbox_back_color, hitbox_edge_color) --draw the actual hitbox
        end
    end
end

function display_mario_hitbox()
    local mario_x = (memory.readbyte(ram_high_x) * 0x100) + memory.readbyte(ram_x)
    local mario_y = (memory.readbyte(ram_high_y) * 0x100) + memory.readbyte(ram_y)
    
    if (mario_x - 1 > screen[0]) and (mario_x + 1 < screen[1]) and (mario_y - 1 > screen[2]) and (mario_y + 1 < screen[3]) then --if on screen
        local hitbox_offset = 0
        if (memory.readbyte(ram_mario_suit) > 0) and (memory.readbyte(ram_is_crouching) == 0) then
            hitbox_offset = 4
        end
        
        local mario_hitbox_x = (mario_x - screen[0]) + rom.readbyte(rom_mario_hitbox+hitbox_offset  )
        local mario_hitbox_y = (mario_y - screen[2]) + rom.readbyte(rom_mario_hitbox+hitbox_offset+2)
        
        gui.drawrect(mario_hitbox_x, mario_hitbox_y,
                     mario_hitbox_x + rom.readbyte(rom_mario_hitbox+hitbox_offset+1), mario_hitbox_y + rom.readbyte(rom_mario_hitbox+hitbox_offset+3), hitbox_back_color, hitbox_edge_color)
    end
end


function display_sprite_id_above_sprite()
    if toggle_display_sprite_id_above_sprite then
        for i=1, sprite_slots, 1 do
        local sprite_x = (memory.readbyte(ram_high_x + i) * 0x100) + sprite[i][4] --get specific sprite x (without sub pixel)
        local sprite_y = (memory.readbyte(ram_high_y + i) * 0x100) + sprite[i][5] --get specific sprite y
        
            if (sprite[i][3] ~= 0) and --if alive
              ((sprite_x - 1 > screen[0]) and (sprite_x + 1 < screen[1]) and (sprite_y - 1 > screen[2]) and (sprite_y + 1 < screen[3])) then --check if within screen, I add or subtract one to be sure
                gui.drawtext(((sprite[i][9][0] + sprite[i][1] + sprite[i][9][2] + sprite[i][1]) / 2) - 5, 
                              (sprite[i][9][1] + sprite[i][2]) - 8, string.format("[%d]", i-1), sprite_id_text_color, sprite_id_back_color) --draw the sprite id above it
            end
        end
    end
end

function display_spriteslots()
    local y_counter = 24 --for listing sprites and removing blank spriteslot's spaces
    for i=1, sprite_slots, 1 do
        if memory.readbyte(ram_sprite_state + i) ~= (toggle_display_sprite_information_after_death and -1 or 0) then --if the sprites state isn't dead, unless ..._after_death is set
            gui.drawtext(1, y_counter, string.format("%d", i-1), text_color, text_back_color) --display sprite id
            gui.drawtext(9, y_counter, string.format("(%d.%02X, %d.%02X)", sprite[i][4], sprite[i][6], sprite[i][5], sprite[i][7]), text_color, text_back_color) --draw position
            y_counter = y_counter + 8 --add to y_counter so the next sprite is shown below the previous
        end
    end
end

--calculate if mario moved 1 pixel more than he should have
function post_pixel_boost()
    local x_expected = x_total() --expected x
    local x_actual = x_prev + (x_speed_prev * 16) --actual x
    local x_difference = x_expected - x_actual --difference
    pixel_boost_total = pixel_boost_total + (x_difference == 0x100 and 1 or 0) --if the difference was exactly one, it was a pixel boost
    pixel_boost_negative_total = pixel_boost_negative_total + (x_difference == -0x100 and 1 or 0) --or a negative boost (wall pushing back, etc.)
    gui.drawtext(1, 9, "Pixel Boost Pos: " .. pixel_boost_total .. "; Neg: " .. pixel_boost_negative_total, text_color, text_back_color) --draw text
end

--convert frames to hours::minutes::seconds.centiseconds, for example 02:15:34:97 is 2 hours, 15 minutes, and 34.97 seconds
function display_time()
    local frames      = movie.framecount() --current frames in movie
    local frames_left = frames --counts how many frames are left after subtracting each unit of time, for example, if a movie is 56312 frames, 
                               --it can be broken into 15 minutes, which is 54089. That leaves about 2223 frames to be broken into about 37 seconds
    
    local hours_frames        = frames_left - (frames_left % hour_frames) --get whole number of hours into frames (if movie is 2.5 hours, remove .5 and calculate frames)
    frames_left = frames_left - hours_frames --remove x hours worth of frames
    local minutes_frames      = frames_left - (frames_left % minute_frames)
    frames_left = frames_left - minutes_frames
    local seconds_frames      = frames_left - (frames_left % second_frames)
    frames_left = frames_left - seconds_frames
    local centiseconds_frames = frames_left
    
    --turn frames into hours, minutes, seconds, and the remainder
    local hours        = math.floor(hours_frames / hour_frames) --sorry for similar name, hour_frames is 1 hour into frames, hours_frames is above
    local minutes      = math.floor(minutes_frames / minute_frames)
    local seconds      = math.floor(seconds_frames / second_frames)
    local centiseconds = math.floor(centiseconds_frames / centisecond_frames)
    
    gui.drawtext(198, 224, string.format("%02d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds), text_color, text_back_color) --draw it
end

function draw_level()
    local tile_attributes = {} --8 bytes which describe which blocks are unsolid, solid on top, or completely solid
    for i=0, 7, 1 do
        tile_attributes[i] = memory.readbyte(ram_tile_attr_table+i) --read all 8 bytes
    end
    
    if (memory.readbyte(ram_tileset) == 0) and (not toggle_display_level_on_overworld) then --if on overworld and set to not display on overworld
        return --exit the loop
    end
    
    local level_type = memory.readbyte(ram_stack) --no clue why it's in the stack
    
    --horizontal level, vertical, or whatever 0xA0 means ;)
    if (level_type == 0x80) or (level_type == 0xC0) or (level_type == 0xA0) then
        local level_width
        local level_height
        local x_offset --x offset to draw level
        local y_offset --y offset to draw level
        --offsets 93 and 75 will draw level at (93, 75)
        
        if level_type == 0x80 then --if level is vertical
            level_width  = level_vertical_width --level width is a single screen
            level_height = (memory.readbyte(ram_level_size)+1) * screen_height --level height is determined by ram_level_size
            x_offset     = level_vertical_draw_x --constant x offset
            y_offset     = ((screen_height * 16) - level_height) / 2 --center the level along the y axis
        else --if level is not vertical
            level_width  = (memory.readbyte(ram_level_size)+1) * screen_width --level width is determined by ram_level_size
            level_height = level_horizontal_height --constant level height
            x_offset     = ((screen_width * 16) - level_width) / 2 --center the level along the x axis
            y_offset     = level_horizontal_draw_y --constant y offset
        end
        
        local block_color = level_block_color
        
        gui.drawrect(x_offset, y_offset, x_offset + level_width, y_offset + level_height, level_back_color, level_back_color) --background rectangle
        for y=0, level_height, 1 do
            for x=0, level_width, 1 do
                local block
                if level_type == 0x80 then --if level is vertical
                    block = memory.readbyte(ram_level_data + x + y * screen_width) --simple formula to find an index in a one dimensional array with x and y coordinates
                else
                    block = memory.readbyte(ram_level_data + x + (math.floor(x / screen_width) * (screen_width * level_height)) + y * screen_width) --similar to vertical formula, but
                                                                                                                                                    --more complicated due to how the level is stored in ram
                end
                local quadrant = math.floor(block / 0x40) --used for checking solidity
                if (block >= tile_attributes[quadrant]) and (block < (quadrant+1) * 0x40) then --check soliditiy within quadran
                    if toggle_display_screen_in_level then
                        if ((x * 16 >= screen[0]) and (x * 16 <= screen[1])) and ((y * 16 >= screen[2]) and (y * 16 <= screen[3])) then
                            block_color = level_block_color
                        else
                            block_color = level_block_faded_color
                        end
                    end
                    gui.drawpixel(x_offset + x, y_offset + y, block_color) --draw the block
                end
            end
        end
        
        local sprite_color = level_sprite_color
        
        if toggle_display_sprites_in_level then
            for i=1, sprite_slots, 1 do
                if sprite[i][3] ~= 0 then --if alive
                    local display_width  = math.ceil((sprite[i][9][2] - sprite[i][9][0]) / 16) --width of hitbox rounded up
                    local display_height = math.ceil((sprite[i][9][3] - sprite[i][9][1]) / 16) --height of the hitbox rounded up
                    
                    for y=0, display_height-1, 1 do
                        for x=0, display_width-1, 1 do
                            local sprite_x = (memory.readbyte(ram_high_x + i) * 16) + math.floor((sprite[i][4] + sprite[i][9][0] + 6) / 16) + x
                            local sprite_y = (memory.readbyte(ram_high_y + i) * 16) + math.floor((sprite[i][5] + sprite[i][9][1] + 6) / 16) + y
                            if toggle_display_screen_in_level then
                                if ((sprite_x * 16 >= screen[0]) and (sprite_x * 16 <= screen[1])) and ((sprite_y * 16 >= screen[2]) and (sprite_y * 16 <= screen[3])) then
                                    sprite_color = level_sprite_color
                                else
                                    sprite_color = level_sprite_faded_color
                                end
                            end
                            gui.drawpixel(x_offset + sprite_x, y_offset + sprite_y, sprite_color) --draw the sprite pixels
                        end
                    end
                end
            end
        end
        
        if toggle_display_mario_in_level then
            local mario_suit = memory.readbyte(ram_mario_suit) --mario powerup
            local mario_y_offset = 0 --changes if mario is crouching
            local is_crouching = memory.readbyte(ram_is_crouching)
            
            if (mario_suit == 0) or (is_crouching ~= 0) then --if mario is small or crouching
                mario_y_offset = 1
            end
            
            gui.drawpixel(x_offset + (memory.readbyte(ram_high_x) * 16) + math.floor(memory.readbyte(ram_x) / 16), 
                          y_offset + (memory.readbyte(ram_high_y) * 16) + math.floor(memory.readbyte(ram_y) / 16) + mario_y_offset, level_mario_color)
            if (memory.readbyte(ram_mario_suit) ~= 0) and (is_crouching == 0) then --if isn't small and not crouching, display extra pixels below mario
                gui.drawpixel(x_offset + (memory.readbyte(ram_high_x) * 16) + math.floor(memory.readbyte(ram_x) / 16), 
                              y_offset + (memory.readbyte(ram_high_y) * 16) + math.floor(memory.readbyte(ram_y) / 16) + mario_y_offset + 1, level_mario_color)
            end
        end
        
    end
end

function display_information()
    --hopefully shouldn't need to comment on these, rather self explanitory
    local y_counter = 9
    if toggle_display_rng then
        local rng = memory.readbyte(ram_rng)
        gui.drawtext(211, y_counter, string.format("RNG: %03d", rng), text_color, text_back_color)
        y_counter = y_counter + 8
    end
    
    if toggle_display_8_frame_timer then
        gui.drawtext(202, y_counter, string.format("8 Frame: %d", memory.readbyte(ram_8_frame_timer)), text_color, text_back_color)
    end
    
    if toggle_display_is_lagged then
        gui.drawtext(((screen_width * 16) - (5 * 3)) / 2, 17, (emu.lagged() and "LAG" or ""), text_lag_color, text_back_color)
    end
    
    y_counter = 96
    
    --display mario information
    if (toggle_display_mario_position or toggle_display_mario_velocity or toggle_display_next_p or toggle_display_p_kill_counter) then
        gui.drawtext(1, y_counter, "Mario:", text_color, text_back_color)
        y_counter = y_counter + 8
    end
    
    if toggle_display_mario_position then
        local mario_sub_x = memory.readbyte(ram_low_x)
        local mario_sub_y = memory.readbyte(ram_low_y)
        gui.drawtext(1, y_counter, string.format("Pos: (%d.%02X, %d.%02X)", memory.readbyte(ram_x), mario_sub_x, memory.readbytesigned(ram_y), mario_sub_y), text_color, text_back_color)
        y_counter = y_counter + 8
    end
    
    if toggle_display_mario_velocity then
        gui.drawtext(1, y_counter, string.format("Speed: (%d, %d)", memory.readbytesigned(ram_x_speed), memory.readbytesigned(ram_y_speed)), text_color, text_back_color)
        y_counter = y_counter + 8
    end
    
    if toggle_display_p_meter then
        gui.drawtext(1, y_counter, "P Meter:", text_color, text_back_color)
        gui.drawtext(40, y_counter, " >>>>>>P", text_faded_color, text_back_color)
        local p_meter_bits = memory.readbyte(ram_p_meter)
        local p_meter = 0
        for i=0, 6, 1 do
            if AND(p_meter_bits, math.pow(2, i)) ~= 0 then
                p_meter = p_meter + 1
            end
        end
        
        for i=0, p_meter-1, 1 do
            gui.drawtext(46 + i * 4, y_counter, ">", text_color, "clear")
        end
        if p_meter == 7 then
            gui.drawtext(70, y_counter, "P", text_color, text_back_color)
        end
        y_counter = y_counter + 8
    end
    
    if toggle_display_next_p then
        gui.drawtext(1, y_counter, string.format("Next P: %d", memory.readbyte(ram_next_p)), text_color, text_back_color)
        y_counter = y_counter + 8
    end
    
    if toggle_display_p_kill_counter then
        gui.drawtext(1, y_counter, string.format("P Kill Counter: %d", memory.readbyte(ram_p_kill_counter)), text_color, text_back_color)
        y_counter = y_counter + 8
    end
    
    if toggle_display_block_y then
        gui.drawtext(1, y_counter, string.format("Block Y: %d", memory.readbyte(ram_y) % 16), text_color, text_back_color)
    end
    
    y_counter = 169
    
    if toggle_display_rerecords then
        if (movie.active() or taseditor.engaged()) then
            gui.drawtext(1, y_counter, string.format("%d", movie.rerecordcount()), text_color, text_back_color)
            y_counter = y_counter + 8
        end
    end
    
    if toggle_display_lag_frames then
        gui.drawtext(1, y_counter, string.format("%d", emu.lagcount()), text_color, text_back_color)
        y_counter = y_counter + 8
    end
    
    if toggle_display_frames then
        if not (movie.active() or taseditor.engaged()) then
            gui.drawtext(1, y_counter, string.format("%d", emu.framecount()), text_color, text_back_color)
        else
            gui.drawtext(1, y_counter, string.format("%d/%d", emu.framecount(), movie.length()), text_color, text_back_color)
        end
        y_counter = y_counter + 8
    end
    
end

--do postframe calculations
function postframe_calculations()
    if (toggle_display_sprite_hitboxes) or (toggle_display_sprite_information) or (toggle_display_sprites_in_level) or (toggle_display_sprite_id_above_sprite) then
        get_screen_information()
        get_sprite_information()
    end
    
    if toggle_display_sprite_hitboxes then
        display_sprite_hitboxes()
    end
    
    if toggle_display_mario_hitbox then
        display_mario_hitbox()
    end
    
    if toggle_display_sprite_id_above_sprite then
        display_sprite_id_above_sprite()
    end
    
    if toggle_display_sprite_information then
        display_spriteslots()
    end
    
    if toggle_display_pixel_boost then
        post_pixel_boost()
    end
    
    if toggle_display_time then
        display_time()
    end
    
    if toggle_display_level then
        draw_level()
    end
    
    display_information()
end

gui.register(get_input)
emu.registerbefore(preframe_calculations)
emu.registerafter(postframe_calculations)
