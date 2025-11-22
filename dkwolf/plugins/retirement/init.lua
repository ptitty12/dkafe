-- retirement.lua – Retired Kong: auto Game Over on level 2 after delay

local exports = {}
exports.name        = "retirement"
exports.version     = "0.21"
exports.description = "Retired Kong"
exports.license     = "GNU GPLv3"
exports.author      = { name = "Patrick Taylor" }
local retirement = exports

function retirement.startplugin()
    ----------------------------------------------------------------
    -- CONSTANTS / ADDRESSES
    ----------------------------------------------------------------
    local CUR = 0x6228   -- current-player lives
    local LVL = 0x6229   -- level number
    local GM2 = 0x600A   -- GameMode2 (0x0E = dec life/handle GO)

    local FPS          = 60
    local HOLD_FRAMES  = 3 * FPS    -- ≈ 3 seconds
    local REARM_FRAMES = 10 * FPS   -- ≈ 10 seconds after fired

    ----------------------------------------------------------------
    -- PLATFORM / SOUND
    ----------------------------------------------------------------
    -- True on Linux/Pi, false on Windows
    local is_pi = (package.config:sub(1, 1) == "/")

    local function play_jb()
        -- Play plugins/retirement/sounds/jb.mp3
        if is_pi then
            -- Requires mpg321 installed in PATH
            io.popen("mpg321 -q plugins/retirement/sounds/jb.mp3 &")
        else
            -- Requires an mp3 player exe; easiest is:
            -- copy plugins/allenkong/bin/mp3play0.exe to plugins/retirement/bin/
            io.popen("start /B /HIGH plugins/retirement/bin/mp3play0.exe plugins/retirement/sounds/jb.mp3")
        end
    end

    ----------------------------------------------------------------
    -- STATE (persists across frames)
    ----------------------------------------------------------------
    local last_level  = nil
    local countdown   = -1
    local fired       = false
    local rearm_timer = -1

    ----------------------------------------------------------------
    -- Helper: get program memory safely each frame
    ----------------------------------------------------------------
    local function get_mem()
        -- Only care about DK; do this check every frame, cheap + safe
        if emu.romname() ~= "dkong" then
            return nil
        end

        local mac
        -- Match dkcoach style / version handling
        local mame_version = tonumber(emu.app_version())
        if mame_version >= 0.227 then
            mac = manager.machine
        elseif mame_version >= 0.196 then
            mac = manager:machine()
        else
            -- Very old MAME; DKAFE/DKWolf shouldn’t hit this, but bail safely
            return nil
        end

        if not mac then return nil end

        local cpu = mac.devices[":maincpu"]
        if not cpu then return nil end

        local mem = cpu.spaces["program"]
        return mem
    end

    ----------------------------------------------------------------
    -- Main per-frame callback (this is your old autoboot logic)
    ----------------------------------------------------------------
    local function main()
        local mem = get_mem()
        if not mem then
            return
        end

        -- Edge-detect: level just became 0x02?
        local lvl = mem:read_u8(LVL)
        if last_level == nil then
            last_level = lvl
            return
        end

        if (not fired) and countdown < 0 and last_level ~= 0x02 and lvl == 0x02 then
            countdown = HOLD_FRAMES
            print(string.format(
                "[retirement] LVL edge %02X->%02X: armed %d frames",
                last_level, lvl, HOLD_FRAMES
            ))
        end

        -- Countdown, then trigger legit Game Over path (DEC lives -> GO)
        if countdown >= 0 then
            countdown = countdown - 1
            if countdown == 0 then
                -- *** CHANGE #1: play jb.mp3 after waiting ~3 seconds ***
                play_jb()

                -- Make sure the DEC at 12F2..130A will hit zero instead of underflowing.
                mem:write_u8(CUR, 0x01)  -- set lives to 1
                mem:write_u8(GM2, 0x0E)  -- switch to handler that decrements life & does GO sequence
                fired       = true
                rearm_timer = REARM_FRAMES

                print("[retirement] Triggered GO via E-path (lives=1, GM2=0x0E); re-arming in 10s")
            end
        end

        -- Simple 10s wait after firing, then auto re-arm
        if fired and rearm_timer >= 0 then
            rearm_timer = rearm_timer - 1
            if rearm_timer == 0 then
                fired       = false
                rearm_timer = -1
                print("[retirement] Re-armed (10s elapsed)")
            end
        end

        last_level = lvl
    end

    ----------------------------------------------------------------
    -- Hook into DKWolf (same style as dkcoach)
    ----------------------------------------------------------------
    emu.register_frame_done(main, "frame")
end

return exports
