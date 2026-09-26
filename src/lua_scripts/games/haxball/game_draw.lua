local alexgames = require("alexgames")
local draw = {}

local function draw_field()
    alexgames.draw_rect('#327134', 0, 0, 480, 800)
    alexgames.draw_rect('#327134', 4, 4, 476, 796)
    alexgames.draw_rect('#4CAF50', 60, 50, 420, 750)
    alexgames.draw_circle('#4CAF50', '#ededed', 240, 400, 70, 4)
    alexgames.draw_line('#ededed', 4, 60, 400, 420, 400)
    
    alexgames.draw_rect('#ededed', 180, 25, 300, 50)
    alexgames.draw_rect('#ededed', 180, 750, 300, 775)

    alexgames.draw_line('#ededed', 4, 58, 50, 422, 50)
    alexgames.draw_line('#ededed', 4, 58, 750, 422, 750)
    alexgames.draw_line('#ededed', 4, 60, 50, 60, 750)
    alexgames.draw_line('#ededed', 4, 420, 50, 420, 750)

    alexgames.draw_circle('#ededed', '#b0b0b0', 180, 50, 6, 2)
    alexgames.draw_circle('#ededed', '#b0b0b0', 300, 50, 6, 2)
    alexgames.draw_circle('#ededed', '#b0b0b0', 180, 750, 6, 2)
    alexgames.draw_circle('#ededed', '#b0b0b0', 300, 750, 6, 2)
end

local function draw_hud(state)
    alexgames.draw_rect('rgba(0,0,0,0.5)', 0, 0, 45, 800) 
    
    alexgames.draw_rect('#ff0000', 15, 10, 35, 30) 
    alexgames.draw_text(tostring(state.score.red), '#ffffff', 35, 50, 20) 
    alexgames.draw_text("-", '#ffffff', 35, 70, 20)
    alexgames.draw_rect('#4d4dff', 15, 110, 35, 130) 
    alexgames.draw_text(tostring(state.score.blue), '#ffffff', 35, 90, 20)

    local minutos = math.floor(state.match_time / 60)
    local segundos = math.floor(state.match_time % 60)
    local tiempo_str = string.format("%02d:%02d", minutos, segundos)
    alexgames.draw_text(tiempo_str, '#ffffff', 35, 400, 24)
end

local function draw_touchpad(state)
    local p1 = state.players[1]
    
    if p1.pad_active then
        local pad_x = p1.pad_origin.x
        local pad_y = p1.pad_origin.y
        
        alexgames.draw_circle('rgba(255,255,255,0.15)', '#ffffff', pad_y, pad_x, 60, 2)
        
        local stick_x = pad_x + (p1.pad_vec.x * 38)
        local stick_y = pad_y + (p1.pad_vec.y * 38)
        
        alexgames.draw_circle('rgba(255,255,255,0.7)', '#ffffff', stick_y, stick_x, 22, 2)
    end
end

-- Nueva función para el panel de Debug
local function draw_debug_stats(state)
    local p1 = state.players[1]
    local ball = state.ball
    
    -- Magnitud de la velocidad calculada por Pitágoras
    local p_speed = math.sqrt(p1.vx * p1.vx + p1.vy * p1.vy)
    local b_speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
    
    -- Fondo semitransparente (Y_inicio, X_inicio, Y_fin, X_fin) en la esquina inferior izquierda
    alexgames.draw_rect('rgba(0,0,0,0.6)', 400, 10, 470, 200)
    
    -- Textos de debugging con colores distintos (Y, X, tamaño)
    alexgames.draw_text(string.format("FPS: %d", state.fps or 0), '#00ff00', 418, 20, 16)
    alexgames.draw_text(string.format("Vel P1: %.1f", p_speed), '#ffff00', 440, 20, 16)
    alexgames.draw_text(string.format("Vel Pelota: %.1f", b_speed), '#ff8800', 462, 20, 16)
end

function draw.render(state)
    alexgames.draw_clear()
    draw_field()
    
    for _, p in ipairs(state.players) do
        local p_outline = '#000000'
        local p_thickness = 2
        
        if p.kicking then
            p_outline = '#ffffff'
            p_thickness = 3
        end
        
        alexgames.draw_circle(p.color, p_outline, p.y, p.x, p.radius, p_thickness)
    end
    
    alexgames.draw_circle('#ffffff', '#000000', state.ball.y, state.ball.x, state.ball.radius, 2)
    
    draw_hud(state)
    draw_touchpad(state)
    
    -- Dibujamos el panel de stats por encima de todo
    draw_debug_stats(state)
    
    alexgames.draw_refresh()
end

return draw