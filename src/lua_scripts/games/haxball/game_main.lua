local alexgames = require("alexgames")
local core = require("games/haxball/game_core")
local draw = require("games/haxball/game_draw")
local serialize = require("games/haxball/game_serialize")
local wait_for_players = require("libs/multiplayer/wait_for_players")

local FPS = 60
local MS_PER_FRAME = 1000/FPS

local left_touch_id = nil
local right_touch_id = nil

-- ==========================================
-- VARIABLES DE RED MULTIJUGADOR
-- ==========================================
local players = { [1] = "You" }
local my_player_idx = 1
local is_client = false
local is_network_game = false
local player_name_to_idx = {}
local last_sent_input = ""

-- Envía los controles a través de la red solo si cambiaron (para ahorrar ancho de banda)
local function send_input_if_changed()
    if not is_network_game then return end
    
    local p = core.state.players[my_player_idx]
    local mx, my = 0, 0
    
    if p.pad_active then
        mx, my = p.pad_vec.x, p.pad_vec.y
    else
        if p.up then my = my - 1 end
        if p.down then my = my + 1 end
        if p.left then mx = mx - 1 end
        if p.right then mx = mx + 1 end
        if mx ~= 0 or my ~= 0 then
            local len = math.sqrt(mx*mx + my*my)
            mx = mx / len
            my = my / len
        end
    end
    
    local kick = p.kicking and 1 or 0
    local input_str = string.format("%.3f,%.3f,%d", mx, my, kick)
    
    if input_str ~= last_sent_input then
        alexgames.send_message("all", "action:input," .. input_str)
        last_sent_input = input_str
    end
end

-- ==========================================
-- BUCLE PRINCIPAL
-- ==========================================
function update(dt_ms)
    local dt = dt_ms / 1000.0
    
    if dt_ms > 0 then
        core.state.fps = math.floor(1000 / dt_ms)
    end
    
    -- El cliente NUNCA calcula físicas, solo obedece al Host para evitar desincronización
    if not is_client then
        core.update_physics(dt)
        
        -- Si somos el Host y estamos en red, enviamos la foto del mundo
        if is_network_game then
            local state_msg = "state:" .. serialize.serialize_state(core.state)
            for dst_player, player_name in pairs(players) do
                if dst_player ~= my_player_idx then
                    alexgames.send_message(player_name, state_msg)
                end
            end
        end
    end
    
    draw.render(core.state)
end

-- ==========================================
-- CONTROLES
-- ==========================================
function handle_key_evt(evt_id, code)
    local is_pressed = (evt_id == "keydown")

    if is_network_game then
        -- En red, TODAS las teclas (WASD o Flechas) mueven a TU jugador
        local p = core.state.players[my_player_idx]
        if code == "KeyW" or code == "ArrowUp" then p.up = is_pressed
        elseif code == "KeyS" or code == "ArrowDown" then p.down = is_pressed
        elseif code == "KeyA" or code == "ArrowLeft" then p.left = is_pressed
        elseif code == "KeyD" or code == "ArrowRight" then p.right = is_pressed
        elseif code == "Space" or code == "ShiftRight" then p.kicking = is_pressed
        end
        send_input_if_changed()
    else
        -- Local Clásico: Split screen (P1 WASD, P2 Flechas)
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
    end
    
    return true
end

function handle_touch_evt(evt_id, touches)
    -- El touch siempre maneja a mi jugador asignado
    local target_idx = is_network_game and my_player_idx or 1
    local p = core.state.players[target_idx]
    
    local touch_kicking = false

    for _, touch in ipairs(touches) do
        if touch.x >= 400 then
            if evt_id == 'touchstart' then
                if not right_touch_id then
                    right_touch_id = touch.id
                    p.kicking = true
                end
            elseif evt_id == 'touchend' or evt_id == 'touchcancel' then
                if right_touch_id == touch.id then
                    right_touch_id = nil
                    p.kicking = false
                end
            end
        else
            if evt_id == 'touchstart' or evt_id == 'touchmove' then
                if not p.pad_active or left_touch_id == touch.id then
                    if not p.pad_active then
                        p.pad_origin.x = touch.x
                        p.pad_origin.y = touch.y
                        p.pad_active = true
                        left_touch_id = touch.id
                    end
                    
                    local dx = touch.x - p.pad_origin.x
                    local dy = touch.y - p.pad_origin.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local max_radius = 60 
                    
                    if dist > 0 then
                        local intensity = math.min(dist, max_radius) / max_radius
                        p.pad_vec.x = (dx / dist) * intensity
                        p.pad_vec.y = (dy / dist) * intensity
                    else
                        p.pad_vec.x = 0
                        p.pad_vec.y = 0
                    end
                end
                
            elseif evt_id == 'touchend' or evt_id == 'touchcancel' then
                if left_touch_id == touch.id then
                    p.pad_active = false
                    p.pad_vec.x = 0
                    p.pad_vec.y = 0
                    left_touch_id = nil
                end
            end
        end
    end

    if #touches == 0 then
        p.pad_active = false
        p.pad_vec.x = 0
        p.pad_vec.y = 0
        left_touch_id = nil
        p.kicking = false
        right_touch_id = nil
    end
    
    if is_network_game then
        send_input_if_changed()
    end
    
    return true
end

-- ==========================================
-- GESTIÓN DE SALAS Y MENSAJES (WAIT_FOR_PLAYERS)
-- ==========================================
local function start_host_game(players_arg, player_arg, player_name_to_idx_arg)
    players = players_arg
    my_player_idx = player_arg
    player_name_to_idx = player_name_to_idx_arg
    is_client = false
    is_network_game = (#players > 1)
    
    -- Resetear el partido limpio
    core.state.ball.x, core.state.ball.y = 400, 240
    core.state.ball.vx, core.state.ball.vy = 0, 0
    core.state.players[1].x, core.state.players[1].y = 200, 240
    core.state.players[2].x, core.state.players[2].y = 600, 240
    core.state.score.red, core.state.score.blue = 0, 0
end

local function start_client_game(players_arg, player_arg, player_name_to_idx_arg)
    players = players_arg
    my_player_idx = player_arg
    player_name_to_idx = player_name_to_idx_arg
    is_client = true
    is_network_game = true
end

function handle_msg_received(src, msg)
    local handled = wait_for_players.handle_msg_received(src, msg)
    if handled then return end

    local header, payload = msg:match("([^:]+):(.*)")
    
    if header == "state" then
        if not is_client then return end
        serialize.deserialize_state(payload, core.state)
        
    elseif header == "action" then
        if is_client then return end
        -- El Host recibe los comandos del jugador remoto y los inyecta como un pad analógico
        local src_player_idx = player_name_to_idx[src]
        if src_player_idx then
            local action_type, data = payload:match("([^,]+),(.*)")
            if action_type == "input" then
                local mx, my, k = data:match("([^,]+),([^,]+),([^,]+)")
                local p = core.state.players[src_player_idx]
                
                p.pad_active = true
                p.pad_vec.x = tonumber(mx)
                p.pad_vec.y = tonumber(my)
                p.kicking = (tonumber(k) == 1)
            end
        end
    end
end 

function handle_popup_btn_clicked(popup_id, btn_idx)
    wait_for_players.handle_popup_btn_clicked(popup_id, btn_idx)
end

function start_game()
    alexgames.set_status_msg("Fútbol de mesa - Multijugador")
    alexgames.enable_evt("key")
    alexgames.enable_evt("touch")
    alexgames.set_timer_update_ms(MS_PER_FRAME)

    -- Inicia el menú de "Local" o "Red" de la librería
    wait_for_players.init(players, my_player_idx, start_host_game, start_client_game)
end