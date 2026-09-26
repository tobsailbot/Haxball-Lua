local alexgames = require("alexgames")
local core = require("games/haxball/game_core")
local draw = require("games/haxball/game_draw")

local FPS = 60
local MS_PER_FRAME = 1000/FPS

local left_touch_id = nil
local right_touch_id = nil

function update(dt_ms)
    local dt = dt_ms / 1000.0
    
    if dt_ms > 0 then
        core.state.fps = math.floor(1000 / dt_ms)
    end
    
    core.update_physics(dt)
    draw.render(core.state)
end

function handle_key_evt(evt_id, code)
    local is_pressed = (evt_id == "keydown")

    if code == "KeyW" then core.state.players[1].up = is_pressed
    elseif code == "KeyS" then core.state.players[1].down = is_pressed
    elseif code == "KeyA" then core.state.players[1].left = is_pressed
    elseif code == "KeyD" then core.state.players[1].right = is_pressed
    elseif code == "Space" then core.state.players[1].kicking = is_pressed
    
    elseif code == "ArrowUp" then core.state.players[2].up = is_pressed
    elseif code == "ArrowDown" then core.state.players[2].down = is_pressed
    elseif code == "ArrowLeft" then core.state.players[2].left = is_pressed
    elseif code == "ArrowRight" then core.state.players[2].right = is_pressed
    elseif code == "ShiftRight" then core.state.players[2].kicking = is_pressed
    end
    
    return true
end

function handle_touch_evt(evt_id, touches)
    local p1 = core.state.players[1]
    
    -- Variables temporales para saber si los dedos asignados siguen activos en este frame
    local left_touch_found = false

    for _, touch in ipairs(touches) do
        
        -- Si el toque es nuevo (touchstart), decidimos su función en base a dónde tocó
        if evt_id == 'touchstart' then
            if touch.x >= 400 then
                -- Inicia en la mitad derecha: lo asignamos a patear
                if not right_touch_id then
                    right_touch_id = touch.id
                    p1.kicking = true
                end
            else
                -- Inicia en la mitad izquierda: lo asignamos al movimiento (joystick)
                if not left_touch_id then
                    left_touch_id = touch.id
                    p1.pad_origin.x = touch.x
                    p1.pad_origin.y = touch.y
                    p1.pad_active = true
                    left_touch_found = true
                end
            end
        end

        -- Para movimientos y levantamientos, procesamos por ID, sin importar dónde estén ahora
        if evt_id == 'touchmove' then
            if touch.id == right_touch_id then
                -- (El pateo no se actualiza con movimiento, pero mantenemos el if por estructura)
            elseif touch.id == left_touch_id then
                left_touch_found = true
                
                local dx = touch.x - p1.pad_origin.x
                local dy = touch.y - p1.pad_origin.y
                local dist = math.sqrt(dx * dx + dy * dy)
                local max_radius = 60 
                
                if dist > 0 then
                    local intensity = math.min(dist, max_radius) / max_radius
                    p1.pad_vec.x = (dx / dist) * intensity
                    p1.pad_vec.y = (dy / dist) * intensity
                else
                    p1.pad_vec.x = 0
                    p1.pad_vec.y = 0
                end
            end
            
        elseif evt_id == 'touchend' or evt_id == 'touchcancel' then
            if touch.id == right_touch_id then
                right_touch_id = nil
                p1.kicking = false
            elseif touch.id == left_touch_id then
                left_touch_id = nil
                p1.pad_active = false
                p1.pad_vec.x = 0
                p1.pad_vec.y = 0
            end
        end
    end

    -- Medida de seguridad en caso de pérdida de eventos:
    -- Si no hay toques en pantalla, reseteamos todo por la fuerza.
    if #touches == 0 then
        p1.pad_active = false
        p1.pad_vec.x = 0
        p1.pad_vec.y = 0
        left_touch_id = nil
        
        p1.kicking = false
        right_touch_id = nil
    end
    
    return true
end

function start_game()
    alexgames.set_status_msg("Fútbol de mesa - Jugador 1 (Táctil o WASD) | Jugador 2 (Flechas)")
    alexgames.enable_evt("key")
    alexgames.enable_evt("touch")
    alexgames.set_timer_update_ms(MS_PER_FRAME)
end