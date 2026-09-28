local serialize = {}

function serialize.serialize_state(state)
    -- Extraemos las entidades
    local b = state.ball
    local p1 = state.players[1]
    local p2 = state.players[2]
    
    -- Normalizamos booleanos y nils
    local lg = state.last_goal_team or "none"
    local gs = state.goal_scored and 1 or 0
    local p1k = p1.kicking and 1 or 0
    local p2k = p2.kicking and 1 or 0
    
    -- Empaquetamos todo en un CSV (Valores separados por comas)
    return string.format("%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%.2f,%.2f,%s,%.2f,%.2f,%.2f,%.2f,%d,%.2f,%.2f,%.2f,%.2f,%d",
        b.x, b.y, b.vx, b.vy,
        state.score.red, state.score.blue, gs, state.goal_timer, state.match_time, lg,
        p1.x, p1.y, p1.vx, p1.vy, p1k,
        p2.x, p2.y, p2.vx, p2.vy, p2k
    )
end

function serialize.deserialize_state(payload, state)
    -- Separamos el string recibido usando las comas
    local parts = {}
    for part in string.gmatch(payload, '([^,]+)') do
        table.insert(parts, part)
    end

    -- Si recibimos el paquete completo (20 variables), actualizamos el estado visual
    if #parts >= 20 then
        state.ball.x, state.ball.y = tonumber(parts[1]), tonumber(parts[2])
        state.ball.vx, state.ball.vy = tonumber(parts[3]), tonumber(parts[4])
        
        state.score.red, state.score.blue = tonumber(parts[5]), tonumber(parts[6])
        state.goal_scored = (tonumber(parts[7]) == 1)
        state.goal_timer = tonumber(parts[8])
        state.match_time = tonumber(parts[9])
        state.last_goal_team = (parts[10] == "none") and nil or parts[10]

        local p1 = state.players[1]
        p1.x, p1.y = tonumber(parts[11]), tonumber(parts[12])
        p1.vx, p1.vy = tonumber(parts[13]), tonumber(parts[14])
        p1.kicking = (tonumber(parts[15]) == 1)

        local p2 = state.players[2]
        p2.x, p2.y = tonumber(parts[16]), tonumber(parts[17])
        p2.vx, p2.vy = tonumber(parts[18]), tonumber(parts[19])
        p2.kicking = (tonumber(parts[20]) == 1)
    end
end

return serialize