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
-- CONSTANTES DE MENÚS Y POPUPS
-- ==========================================
local POPUP_ID_MATCH_SETTINGS = "haxball_match_settings"
local POPUP_ID_MATCH_OVER     = "haxball_match_over"

local POPUP_ITEM_ID_GOALS_DROPDOWN = 1
local POPUP_ITEM_ID_TIME_DROPDOWN  = 2
local POPUP_ITEM_ID_BTN_START      = 3
local POPUP_ITEM_ID_BTN_BACK       = 4

local GOALS_OPTIONS = { "1 Gol", "3 Goles", "5 Goles" }
local GOALS_VALUES  = { 1, 3, 5 }

local TIME_OPTIONS  = { "1 Minuto", "3 Minutos", "5 Minutos", "Sin límite" }
local TIME_VALUES   = { 60, 180, 300, 0 }

local pending_mode = nil -- "local" o "network"
local match_over_popup_shown = false

-- ==========================================
-- VARIABLES DE RED MULTIJUGADOR
-- ==========================================
local players = { [1] = "You" }
local my_player_idx = 1
local is_client = false
local is_network_game = false
local player_name_to_idx = {}
local last_sent_input = ""

local function show_match_settings(mode)
    pending_mode = mode
    local mode_title = (mode == "local") and "Configuración del Partido (Local)" or "Configuración del Partido (Online)"
    local btn_text = (mode == "local") and "Comenzar Partido" or "Comenzar Partido (Host)"
    local back_text = (mode == "local") and "Volver" or "Volver a la Sala"

    alexgames.show_popup(POPUP_ID_MATCH_SETTINGS, {
        title = mode_title,
        items = {
            {
                id = POPUP_ITEM_ID_GOALS_DROPDOWN,
                item_type = alexgames.POPUP_ITEM_TYPE_DROPDOWN,
                label = "Límite de Goles",
                options = GOALS_OPTIONS,
            },
            {
                id = POPUP_ITEM_ID_TIME_DROPDOWN,
                item_type = alexgames.POPUP_ITEM_TYPE_DROPDOWN,
                label = "Tiempo del Partido",
                options = TIME_OPTIONS,
            },
            {
                id = POPUP_ITEM_ID_BTN_START,
                item_type = alexgames.POPUP_ITEM_TYPE_BTN,
                text = btn_text,
            },
            {
                id = POPUP_ITEM_ID_BTN_BACK,
                item_type = alexgames.POPUP_ITEM_TYPE_BTN,
                text = back_text,
            },
        },
    })
end

local function show_match_over_popup()
    local s = core.state
    local winner_str = "¡Empate!"
    if s.winner == "red" then
        winner_str = "Ganador: Equipo Rojo"
    elseif s.winner == "blue" then
        winner_str = "Ganador: Equipo Azul"
    end
    
    local msg = string.format("Marcador Final:\nRojo %d - Azul %d\n%s", s.score.red, s.score.blue, winner_str)
    
    local items = {
        {
            item_type = alexgames.POPUP_ITEM_TYPE_MSG,
            msg = msg,
        }
    }
    
    if not is_client then
        table.insert(items, {
            id = 0,
            item_type = alexgames.POPUP_ITEM_TYPE_BTN,
            text = "Revancha (Mismas Reglas)",
        })
        table.insert(items, {
            id = 1,
            item_type = alexgames.POPUP_ITEM_TYPE_BTN,
            text = "Configurar Nuevo Partido",
        })
        table.insert(items, {
            id = 2,
            item_type = alexgames.POPUP_ITEM_TYPE_BTN,
            text = "Menú Principal",
        })
    else
        table.insert(items, {
            id = 0,
            item_type = alexgames.POPUP_ITEM_TYPE_BTN,
            text = "Volver al Menú Principal",
        })
    end
    
    alexgames.show_popup(POPUP_ID_MATCH_OVER, {
        title = "Fin del Partido",
        items = items,
    })
end

local function get_dropdown_selection(popup_state, target_id)
    if not popup_state then return 0 end
    for _, item in ipairs(popup_state) do
        if item.id == target_id then
            return item.selected
        end
    end
    return 0
end

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
    
    -- El cliente NUNCA calcula físicas, solo obedece al Host
    if not is_client then
        core.update_physics(dt)
        
        if is_network_game then
            local state_msg = "state:" .. serialize.serialize_state(core.state)
            for dst_player, player_name in pairs(players) do
                if dst_player ~= my_player_idx then
                    alexgames.send_message(player_name, state_msg)
                end
            end
        end
    end

    -- Comprobación de fin de partido para mostrar popup solo tras expirar match_over_timer
    if core.state.match_started and core.state.match_over and not match_over_popup_shown then
        if core.state.match_over_timer <= 0 then
            match_over_popup_shown = true
            show_match_over_popup()
        end
    end
    
    -- Pasamos el índice del jugador local
    draw.render(core.state, my_player_idx)
end

-- ==========================================
-- CONTROLES
-- ==========================================
function handle_key_evt(evt_id, code)
    if not core.state.match_started then
        return true
    end

    if core.state.match_over and core.state.match_over_timer <= 0 then
        return true
    end

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
    if not core.state.match_started then
        return true
    end

    if core.state.match_over and core.state.match_over_timer <= 0 then
        return true
    end

    -- El touch siempre maneja a mi jugador asignado
    local target_idx = is_network_game and my_player_idx or 1
    local p = core.state.players[target_idx]

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
    match_over_popup_shown = false
    
    -- Resetear el partido limpio con las reglas configuradas y arrancarlo
    core.reset_match(core.state.settings.goals_limit, core.state.settings.time_limit)
    core.state.match_started = true
end

local function start_client_game(players_arg, player_arg, player_name_to_idx_arg)
    players = players_arg
    my_player_idx = player_arg
    player_name_to_idx = player_name_to_idx_arg
    is_client = true
    is_network_game = true
    match_over_popup_shown = false
    core.state.match_started = true
end

function handle_msg_received(src, msg)
    local header, payload = msg:match("([^:]+):(.*)")

    if header == "config" then
        if is_client and payload then
            local g, t = payload:match("(%d+),(%d+)")
            if g and t then
                core.reset_match(tonumber(g), tonumber(t))
            end
        end
        return
    elseif header == "rematch" then
        if is_client then
            alexgames.hide_popup()
            match_over_popup_shown = false
            core.reset_match(core.state.settings.goals_limit, core.state.settings.time_limit)
            core.state.match_started = true
        end
        return
    end

    local handled = wait_for_players.handle_msg_received(src, msg)
    if handled then return end
    
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

function handle_popup_btn_clicked(popup_id, btn_idx, popup_state)
    -- 1. Interceptar selección en el menú inicial de Modo de Juego
    if popup_id == "wfp_multiplayer_type" then
        if btn_idx == 0 then
            -- Multijugador Local: abrimos configuración de partido
            alexgames.hide_popup()
            show_match_settings("local")
            return true
        else
            -- Multijugador en Red: dejamos que wait_for_players gestione la sala
            return wait_for_players.handle_popup_btn_clicked(popup_id, btn_idx)
        end
    end

    -- 2. Interceptar cuando el Host pulsa "Comenzar partido" en la sala de espera
    if popup_id == "waiting_for_players" then
        if btn_idx == 0 then
            alexgames.hide_popup()
            show_match_settings("network")
            return true
        end
    end

    -- 3. Diálogo de Configuración de Partido (Goles y Tiempo)
    if popup_id == POPUP_ID_MATCH_SETTINGS then
        if btn_idx == POPUP_ITEM_ID_BTN_START then
            local sel_goals = get_dropdown_selection(popup_state, POPUP_ITEM_ID_GOALS_DROPDOWN)
            local sel_time  = get_dropdown_selection(popup_state, POPUP_ITEM_ID_TIME_DROPDOWN)
            local goals = GOALS_VALUES[sel_goals + 1] or 3
            local time  = TIME_VALUES[sel_time + 1] or 180

            alexgames.hide_popup()
            match_over_popup_shown = false
            core.reset_match(goals, time)
            core.state.match_started = true

            if pending_mode == "local" then
                is_client = false
                is_network_game = false
                alexgames.set_status_msg("Fútbol de mesa - Modo Local")
                start_host_game({ [1] = "Jugador 1", [2] = "Jugador 2" }, 1, {})
            else
                -- Host en red: transmite configuración a los clientes e inicia
                alexgames.send_message("all", string.format("config:%d,%d", goals, time))
                alexgames.send_message("all", "start_game:")
                start_host_game(players, my_player_idx, player_name_to_idx)
            end
            return true
        elseif btn_idx == POPUP_ITEM_ID_BTN_BACK then
            alexgames.hide_popup()
            match_over_popup_shown = false
            core.reset_match()
            if pending_mode == "local" then
                wait_for_players.init(players, my_player_idx, start_host_game, start_client_game)
            else
                wait_for_players.show_waiting_for_players_popup()
            end
            return true
        end
    end

    -- 4. Diálogo de Fin de Partido
    if popup_id == POPUP_ID_MATCH_OVER then
        alexgames.hide_popup()
        match_over_popup_shown = false

        if is_client then
            -- Cliente vuelve al menú principal
            is_client = false
            is_network_game = false
            core.reset_match(core.state.settings.goals_limit, core.state.settings.time_limit)
            wait_for_players.init(players, my_player_idx, start_host_game, start_client_game)
        else
            if btn_idx == 0 then
                -- Revancha (Mismas Reglas)
                core.reset_match(core.state.settings.goals_limit, core.state.settings.time_limit)
                core.state.match_started = true
                if is_network_game then
                    alexgames.send_message("all", "rematch:")
                    start_host_game(players, my_player_idx, player_name_to_idx)
                else
                    start_host_game({ [1] = "Jugador 1", [2] = "Jugador 2" }, 1, {})
                end
            elseif btn_idx == 1 then
                -- Configurar nuevo partido
                core.reset_match(core.state.settings.goals_limit, core.state.settings.time_limit)
                show_match_settings(is_network_game and "network" or "local")
            elseif btn_idx == 2 then
                -- Menú principal
                is_client = false
                is_network_game = false
                core.reset_match(core.state.settings.goals_limit, core.state.settings.time_limit)
                wait_for_players.init(players, my_player_idx, start_host_game, start_client_game)
            end
        end
        return true
    end

    return wait_for_players.handle_popup_btn_clicked(popup_id, btn_idx)
end

function start_game()
    alexgames.set_status_msg("Fútbol de mesa - Multijugador")
    alexgames.enable_evt("key")
    alexgames.enable_evt("touch")
    alexgames.set_timer_update_ms(MS_PER_FRAME)

    match_over_popup_shown = false
    core.reset_match() -- reloj en 0, físicas congeladas hasta pulsar comenzar

    -- Inicia el menú de selección de modo
    wait_for_players.init(players, my_player_idx, start_host_game, start_client_game)
end