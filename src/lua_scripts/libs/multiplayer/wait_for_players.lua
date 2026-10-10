local wait_for_players = {}

local alexgames = require("alexgames")
local show_buttons_popup = require("libs/ui/show_buttons_popup")

local POPUP_ID_MULTIPLAYER_TYPE = "wfp_multiplayer_type"
local POPUP_ID_WAITING_FOR_PLAYERS = "waiting_for_players"

local MULTIPLAYER_TYPE_BTNS = {
    "Multijugador Local (misma pantalla)",
    "Multijugador en Red (distintos dispositivos)",
}

-- Solo el host puede iniciar la partida
local POPUP_WAITING_FOR_PLAYERS_HOST_BTNS = {
    "Comenzar partido",
}

local players    = nil
local player     = nil
local player_name_to_idx = {}
local is_client  = nil
local start_game_host_func  = nil
local start_game_client_func = nil
local multiplayer_type_selected = nil

function wait_for_players.init(players_arg, player_arg,
                               start_game_host_arg, start_game_client_arg)
                               
    players   = players_arg
    player    = player_arg
    is_client = false
    start_game_host_func = start_game_host_arg
    start_game_client_func = start_game_client_arg 
    multiplayer_type_selected = nil

    -- 1. Primero mostramos el menú para elegir si es Local o en Red
    show_buttons_popup.show_popup(POPUP_ID_MULTIPLAYER_TYPE,
                                  "Modo de Juego",
                                  "Elige cómo quieres jugar:",
                                  MULTIPLAYER_TYPE_BTNS)
end

local function get_vacant_player_spot(players)
    local idx = 1
    while true do
        if players[idx] == nil then
            return idx
        end
        idx = idx + 1
    end
end

function wait_for_players.is_host_tentative()
    return not is_client
end

function wait_for_players.players_tentative()
    return players
end

function wait_for_players.show_waiting_for_players_popup()
    local body_txt = ''
    if alexgames.is_multiplayer_session_id_needed() then
        local session_id = alexgames.get_multiplayer_session_id()
        body_txt = string.format("ID de Sala: %s\n", session_id)
        body_txt = body_txt .. string.format("Comparte la URL de la barra de direcciones con tu amigo, asegurándote de incluir el parámetro \"ID\" (%s). Así es como el servidor sabe conectarlos.\n", session_id)
        body_txt = body_txt .. "El ID de sesión se puede cambiar en las opciones o editando la URL manualmente.\n\n"
    end

    body_txt = body_txt .. string.format("Jugadores en la sala: %d", #players)
    for player_id, player_ip in pairs(players) do
        local more_info = ""
        if player_id == player then
            if is_client then
                more_info = "(tú) "
            else
                more_info = "(tú, host) "
            end
        end
        body_txt = body_txt .. string.format("\nJugador %d: %s%s", player_id, more_info, player_ip)
    end

    local btns = {}
    if is_client then
        body_txt = body_txt .. "\n\nEsperando a que el host inicie el partido..."
    else
        btns = POPUP_WAITING_FOR_PLAYERS_HOST_BTNS
    end
    
    show_buttons_popup.show_popup(POPUP_ID_WAITING_FOR_PLAYERS,
                          "Sala de Espera",
                          body_txt,
                          btns)
end

function wait_for_players.handle_popup_btn_clicked(popup_id, btn_idx)
    if popup_id == POPUP_ID_MULTIPLAYER_TYPE then
        alexgames.hide_popup()
        if btn_idx == 0 then
            -- [JUEGO LOCAL]
            multiplayer_type_selected = "local"
            -- Como es local, cerramos el menú y vamos directo a la cancha
            start_game_host_func(players, player, player_name_to_idx)
        elseif btn_idx == 1 then
            -- [JUEGO EN RED]
            multiplayer_type_selected = "network"
            alexgames.set_status_msg("Esperando jugadores en la sala...")
            wait_for_players.show_waiting_for_players_popup()
            alexgames.send_message("all", "joined:")
        end
        return true
        
    elseif popup_id == POPUP_ID_WAITING_FOR_PLAYERS then
        -- Botón "Comenzar partido" presionado por el Host
        if btn_idx == 0 then
            alexgames.send_message("all", "start_game:")
            start_game_host_func(players, player, player_name_to_idx)
            alexgames.hide_popup()
            return true
        end
    end
    return false
end

local function become_client_player(player_idx, player_name)
    alexgames.set_status_msg(string.format("Eres el jugador %d (cliente), %s", player_idx, player_name))
    is_client = true
    player = player_idx
    players = { [player_idx] = "Tú" }
end

function wait_for_players.handle_msg_received(src, msg)
    -- Si elegimos jugar en local, bloqueamos la entrada de cualquier mensaje de red para evitar interferencias
    if multiplayer_type_selected == "local" then
        return false
    end

    local m = msg:gmatch("([^:]+):(.*)")
    local header, payload
    header, payload = m()

    if header == "player" then
        local m2 = payload:gmatch("(%d+),(.*)")
        local new_player_idx, new_player_name = m2()
        become_client_player(tonumber(new_player_idx), new_player_name)
        wait_for_players.show_waiting_for_players_popup()
        
    elseif header == "clear_players" then
        if is_client then
            player = nil
            players = {}
        end
        
    elseif header == "add_player" then
        local m3 = payload:gmatch("(%d+),(.*)")
        local new_player_idx, new_player_name = m3()
        new_player_idx = tonumber(new_player_idx)
        alexgames.set_status_msg(string.format("El Jugador %d se unió desde %s", new_player_idx, new_player_name))
        players[new_player_idx] = new_player_name
        player_name_to_idx[new_player_name] = new_player_idx
        wait_for_players.show_waiting_for_players_popup()
        
    elseif header == "player_left" then
        if src ~= "ctrl" then
            print("Se recibió un mensaje 'player_left' de otro jugador")
            return false
        end
        local player_left_name = payload
        local player_left_idx = player_name_to_idx[player_left_name]
        local player_left_msg = string.format("El Jugador %s \"%s\" abandonó la partida", player_left_idx or "?", player_left_name)
        alexgames.set_status_msg(player_left_msg)
        if player_left_idx == nil then
            return false
        end
        table.remove(players, player_left_idx)
        player_name_to_idx[player_left_name] = nil

        alexgames.send_message("all", "clear_players:")
        for player_idx,_ in ipairs(players) do
            local player_name = players[player_idx]
            alexgames.send_message(player_name, string.format("player:%d,%s", player_idx, player_name))
        end
        for player_idx,_ in ipairs(players) do
            alexgames.send_message("all", string.format("add_player:%d,%s", player_idx, players[player_idx]))
        end
        wait_for_players.show_waiting_for_players_popup()
        
    elseif header == "joined" then
        if not is_client then
            local players_joined = get_vacant_player_spot(players)
            local new_player_idx = players_joined
            players[new_player_idx] = src
            player_name_to_idx[src] = new_player_idx

            wait_for_players.show_waiting_for_players_popup()

            alexgames.send_message(src, string.format("player:%d,%s", new_player_idx, src))
            for player_id, player_name in pairs(players) do
                if player_id == new_player_idx then
                    goto next_player
                end
                if player_name == "You" or player_name == "Tú" then
                    player_name = "Host"
                end
                alexgames.send_message(src, string.format("add_player:%d,%s", player_id, player_name))
                ::next_player::
            end
            alexgames.send_message("all", string.format("add_player:%d,%s", new_player_idx, src))
            alexgames.set_status_msg(string.format("El Jugador %d se unió desde %s", new_player_idx, src))
        end
        
    elseif header == "start_game" then
        if is_client then
            alexgames.hide_popup()
            start_game_client_func(players, player, player_name_to_idx)
        end
    else
        return false
    end

    return true
end

return wait_for_players