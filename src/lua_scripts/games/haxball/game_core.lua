local alexgames = require("alexgames")
local core = {}

local FRICTION = 0.995 
local PLAYER_FRICTION = 0.985 
local PLAYER_ACCEL = 350

local KICKING_SPEED_MULT = 0.75
local SPEED_TRANSITION_TIME = 1.25 
local SPEED_CHANGE_RATE = (1.0 - KICKING_SPEED_MULT) / SPEED_TRANSITION_TIME
local IMPULSE_FORCE = 1

local KICK_REACH = 8

core.state = {
    ball = { x = 400, y = 240, vx = 0, vy = 0, radius = 11 },
    score = { red = 0, blue = 0 },
    goal_scored = false,
    last_goal_team = nil, -- Registra el equipo que hizo el último gol
    goal_timer = 0,
    match_time = 0,
    fps = 0,
    settings = {
        goals_limit = 3, -- 1, 3 o 5 goles
        time_limit = 180, -- en segundos; 60, 180, 300 o 0 (sin límite)
    },
    match_started = false, -- true únicamente cuando el partido está en juego (tras Iniciar o Revancha)
    match_over = false,
    match_over_timer = 0, -- temporizador de celebración de 3 segundos post-partido
    winner = nil, -- 'red', 'blue', 'tie'
    overtime = false, -- true cuando el tiempo reglamentario expira en empate (Gol de Oro)
    players = {
        { id = 1, team = "red", color = '#ff0000', x = 200, y = 240, vx = 0, vy = 0, radius = 15, up = false, down = false, left = false, right = false, kicking = false, speed_mult = 1.0, pad_active = false, pad_origin = {x=0, y=0}, pad_vec = {x=0, y=0} },
        { id = 2, team = "blue", color = '#4d4dff', x = 600, y = 240, vx = 0, vy = 0, radius = 15, up = false, down = false, left = false, right = false, kicking = false, speed_mult = 1.0, pad_active = false, pad_origin = {x=0, y=0}, pad_vec = {x=0, y=0} }
    }
}

local POST_RADIUS = 6
local POSTS = {
    { x = 50, y = 180 }, { x = 50, y = 300 },
    { x = 750, y = 180 }, { x = 750, y = 300 }
}

local function check_posts(entity, is_ball)
    local bounce = is_ball and 0.8 or 0.2 

    for _, post in ipairs(POSTS) do
        local dx = entity.x - post.x
        local dy = entity.y - post.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist == 0 then dist = 0.001 end
        
        local min_dist = entity.radius + POST_RADIUS
        if dist < min_dist then
            local overlap = min_dist - dist
            local nx = dx / dist
            local ny = dy / dist
            
            entity.x = entity.x + nx * overlap
            entity.y = entity.y + ny * overlap
            
            local vel_along_normal = entity.vx * nx + entity.vy * ny
            if vel_along_normal < 0 then
                local impulse = -(1 + bounce) * vel_along_normal
                entity.vx = entity.vx + impulse * nx
                entity.vy = entity.vy + impulse * ny
            end
        end
    end
end

local function apply_bounds(entity, is_ball)
    local r = entity.radius
    local bounce = is_ball and -0.8 or 0

    if entity.y < 60 + r then entity.y = 60 + r; entity.vy = entity.vy * bounce end
    if entity.y > 420 - r then entity.y = 420 - r; entity.vy = entity.vy * bounce end

    if entity.x < 50 then
        if entity.y < 180 + r then entity.y = 180 + r; entity.vy = entity.vy * bounce end
        if entity.y > 300 - r then entity.y = 300 - r; entity.vy = entity.vy * bounce end
    elseif entity.x > 750 then
        if entity.y < 180 + r then entity.y = 180 + r; entity.vy = entity.vy * bounce end
        if entity.y > 300 - r then entity.y = 300 - r; entity.vy = entity.vy * bounce end
    end

    if entity.y > 180 and entity.y < 300 then
        if entity.x < 25 + r then entity.x = 25 + r; entity.vx = entity.vx * bounce end
        if entity.x > 775 - r then entity.x = 775 - r; entity.vx = entity.vx * bounce end
    else
        if entity.x < 50 + r then entity.x = 50 + r; entity.vx = entity.vx * bounce end
        if entity.x > 750 - r then entity.x = 750 - r; entity.vx = entity.vx * bounce end
    end
end

local function check_collision(state)
    local p1 = state.players[1]
    local p2 = state.players[2]
    local pdx = p2.x - p1.x
    local pdy = p2.y - p1.y
    local p_dist = math.sqrt(pdx * pdx + pdy * pdy)
    if p_dist == 0 then p_dist = 0.001 end
    local p_min_dist = p1.radius + p2.radius

    if p_dist < p_min_dist then
        local nx = pdx / p_dist
        local ny = pdy / p_dist
        
        local overlap = (p_min_dist - p_dist) * 0.5
        p1.x = p1.x - nx * overlap
        p1.y = p1.y - ny * overlap
        p2.x = p2.x + nx * overlap
        p2.y = p2.y + ny * overlap
        
        local rvx = p1.vx - p2.vx
        local rvy = p1.vy - p2.vy
        local vel_along_normal = rvx * nx + rvy * ny
        
        if vel_along_normal > 0 then
            local restitution = 0.2 
            local impulse = (1 + restitution) * vel_along_normal * 0.5
            p1.vx = p1.vx - impulse * nx
            p1.vy = p1.vy - impulse * ny
            p2.vx = p2.vx + impulse * nx
            p2.vy = p2.vy + impulse * ny
        end
    end

    for _, p in ipairs(state.players) do
        local dx = state.ball.x - p.x
        local dy = state.ball.y - p.y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance == 0 then distance = 0.001 end 

        local min_dist = p.radius + state.ball.radius
        local kick_dist = min_dist + KICK_REACH 

        local nx = dx / distance
        local ny = dy / distance

        if distance < min_dist then
            local overlap = min_dist - distance
            state.ball.x = state.ball.x + nx * (overlap * 0.8)
            state.ball.y = state.ball.y + ny * (overlap * 0.8)
            p.x = p.x - nx * (overlap * 0.2)
            p.y = p.y - ny * (overlap * 0.2)

            local rvx = state.ball.vx - p.vx
            local rvy = state.ball.vy - p.vy
            local vel_along_normal = rvx * nx + rvy * ny

            if vel_along_normal < 0 then
                if not p.kicking then
                    local ball_restitution = 0.2 
                    local impulse = -(1 + ball_restitution) * vel_along_normal
                    state.ball.vx = state.ball.vx + impulse * nx
                    state.ball.vy = state.ball.vy + impulse * ny
                    local mass_ratio = 0.15 
                    p.vx = p.vx - (impulse * mass_ratio) * nx
                    p.vy = p.vy - (impulse * mass_ratio) * ny
                end
            end
        end

        if p.kicking and distance < kick_dist then
            local kick_force = IMPULSE_FORCE * 350  
            state.ball.vx = state.ball.vx + nx * kick_force
            state.ball.vy = state.ball.vy + ny * kick_force
            p.kicking = false
        end
    end
end

local function check_goal(state)
    if state.goal_scored or state.match_over then return end
    
    local in_goal_y = (state.ball.y > 180 and state.ball.y < 300)
    
    if state.ball.x < 50 and in_goal_y then
        state.score.blue = state.score.blue + 1
        state.goal_scored = true
        state.last_goal_team = "blue"
        state.goal_timer = 3.0
        state.ball.vx = state.ball.vx * 0.2
        state.ball.vy = state.ball.vy * 0.2

        local limit = state.settings.goals_limit or 3
        if state.overtime or state.score.blue >= limit then
            state.match_over = true
            state.winner = "blue"
            state.match_over_timer = 3.0
        end
        
    elseif state.ball.x > 750 and in_goal_y then
        state.score.red = state.score.red + 1
        state.goal_scored = true
        state.last_goal_team = "red"
        state.goal_timer = 3.0
        state.ball.vx = state.ball.vx * 0.2
        state.ball.vy = state.ball.vy * 0.2

        local limit = state.settings.goals_limit or 3
        if state.overtime or state.score.red >= limit then
            state.match_over = true
            state.winner = "red"
            state.match_over_timer = 3.0
        end
    end
end

function core.reset_match(goals_limit, time_limit)
    local state = core.state
    if goals_limit then state.settings.goals_limit = tonumber(goals_limit) end
    if time_limit ~= nil then state.settings.time_limit = tonumber(time_limit) end
    
    state.score.red = 0
    state.score.blue = 0
    state.goal_scored = false
    state.last_goal_team = nil
    state.goal_timer = 0
    state.match_time = 0
    state.match_started = false
    state.match_over = false
    state.match_over_timer = 0
    state.winner = nil
    state.overtime = false
    
    state.ball.x, state.ball.y = 400, 240
    state.ball.vx, state.ball.vy = 0, 0
    
    state.players[1].x, state.players[1].y = 200, 240
    state.players[1].vx, state.players[1].vy = 0, 0
    state.players[1].pad_active = false
    state.players[1].kicking = false
    state.players[1].up = false
    state.players[1].down = false
    state.players[1].left = false
    state.players[1].right = false
    
    state.players[2].x, state.players[2].y = 600, 240
    state.players[2].vx, state.players[2].vy = 0, 0
    state.players[2].pad_active = false
    state.players[2].kicking = false
    state.players[2].up = false
    state.players[2].down = false
    state.players[2].left = false
    state.players[2].right = false
end

function core.update_physics(dt)
    local state = core.state

    -- Si el partido no ha iniciado (en menús), no avanza reloj ni físicas
    if not state.match_started then
        return
    end

    -- Si el partido terminó, las físicas y controles continúan durante match_over_timer (3 segundos)
    if state.match_over then
        if state.match_over_timer > 0 then
            state.match_over_timer = state.match_over_timer - dt
            if state.goal_scored and state.goal_timer > 0 then
                state.goal_timer = state.goal_timer - dt
            end
        else
            -- Tiempo de festejo post-partido finalizado: congelar movimiento
            return
        end
    end

    if not state.goal_scored and not state.match_over then
        state.match_time = state.match_time + dt

        local time_limit = state.settings.time_limit or 0
        if time_limit > 0 and not state.overtime and state.match_time >= time_limit then
            if state.score.red > state.score.blue then
                state.match_over = true
                state.winner = "red"
                state.match_over_timer = 3.0
            elseif state.score.blue > state.score.red then
                state.match_over = true
                state.winner = "blue"
                state.match_over_timer = 3.0
            else
                -- Empate: Gol de Oro / Prórroga
                state.overtime = true
            end
        end
    end

    check_goal(state)

    if state.goal_scored and not state.match_over then
        state.goal_timer = state.goal_timer - dt
        if state.goal_timer <= 0 then
            state.ball.x, state.ball.y = 400, 240
            state.ball.vx, state.ball.vy = 0, 0
            
            state.players[1].x, state.players[1].y = 200, 240
            state.players[1].vx, state.players[1].vy = 0, 0
            
            state.players[2].x, state.players[2].y = 600, 240
            state.players[2].vx, state.players[2].vy = 0, 0
            
            state.goal_scored = false
            state.last_goal_team = nil
        end
    end

    -- FÍSICA INDEPENDIENTE DEL TIEMPO 
    local frame_ratio = dt * 144
    -- Se reemplaza math.pow por el operador de exponenciación ^ de Lua 5.4
    local current_player_friction = PLAYER_FRICTION ^ frame_ratio
    local current_ball_friction = FRICTION ^ frame_ratio

    for _, p in ipairs(state.players) do
        if p.kicking then
            p.speed_mult = p.speed_mult - (SPEED_CHANGE_RATE * dt)
            if p.speed_mult < KICKING_SPEED_MULT then
                p.speed_mult = KICKING_SPEED_MULT
            end
        else
            p.speed_mult = p.speed_mult + (SPEED_CHANGE_RATE * dt)
            if p.speed_mult > 1.0 then
                p.speed_mult = 1.0
            end
        end

        local current_accel = PLAYER_ACCEL * p.speed_mult
        local move_x, move_y = 0, 0
        local intensity = 1.0

        if p.pad_active then
            move_x = p.pad_vec.x
            move_y = p.pad_vec.y
            intensity = math.sqrt(move_x * move_x + move_y * move_y)
            if intensity > 0 then
                move_x = move_x / intensity
                move_y = move_y / intensity
            end
        else
            if p.up then move_y = move_y - 1 end
            if p.down then move_y = move_y + 1 end
            if p.left then move_x = move_x - 1 end
            if p.right then move_x = move_x + 1 end

            if move_x ~= 0 or move_y ~= 0 then
                local length = math.sqrt(move_x * move_x + move_y * move_y)
                if length > 1 then
                    move_x = move_x / length
                    move_y = move_y / length
                end
            end
        end

        if move_x ~= 0 or move_y ~= 0 then
            p.vx = p.vx + move_x * (current_accel * intensity) * dt
            p.vy = p.vy + move_y * (current_accel * intensity) * dt
        end

        p.vx = p.vx * current_player_friction
        p.vy = p.vy * current_player_friction

        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt

        if p.x < 0 + p.radius then p.x = 0 + p.radius; p.vx = 0 end
        if p.x > 800 - p.radius then p.x = 800 - p.radius; p.vx = 0 end
        if p.y < 0 + p.radius then p.y = 0 + p.radius; p.vy = 0 end
        if p.y > 480 - p.radius then p.y = 480 - p.radius; p.vy = 0 end
    end

    check_collision(state)

    state.ball.vx = state.ball.vx * current_ball_friction
    state.ball.vy = state.ball.vy * current_ball_friction

    state.ball.x = state.ball.x + state.ball.vx * dt
    state.ball.y = state.ball.y + state.ball.vy * dt

    check_posts(state.ball, true)
    apply_bounds(state.ball, true)
end

return core