package main

import "core:math"
import r "vendor:raylib"

// TODO: get them to seperate file (.conf)

// window params
WINDOW_WIDTH    :: 1600;
WINDOW_HEIGHT   :: 900;
GRID_WIDTH      :: f32(TARGET_COLS) * TARGET_WIDTH +
                        f32(TARGET_COLS - 1) * PAD_X;
NAME            :: "ODINOUT";
TICK_RATE       :: 1.0 / 120.0;
curtain      : f32 = 0.0;  // 0.0 = clear, 1.0 = backround_color
fade_out_dur : f32 = 2.0;  // Seconds to fade to black
fade_in_dur  : f32 = 1.0;  // Seconds to fade back into the game
show_prompt  := false;

// game params height
BAR_WIDTH  : f32 : 100.0;
BAR_HEIGHT : f32 : 20.0;
BAR_COLOR  : u32 : 0x3B82F6FF;
BAR_SPEED  : f32 : 800.0;
// -----------------------
TARGET_WIDTH    : f32 : 100.0;
TARGET_HEIGHT   : f32 : 20.0;
TARGET_ROWS     : int : 10;
TARGET_COLS     : int : 10;
PAD_Y           : f32 : 20;
PAD_X           : f32 : 20;
// -----------------------
BACKROUND_COLOR : u32 : 0x000000FF;
// -----------------------
BALL_WIDTH      : f32 : BAR_WIDTH / 4;
BALL_HEIGHT     : f32 : 20.0;
BALL_COLOR      : u32 : 0xFFFFFFFF;
BALL_SPEED      : f32 : 500.0;
// -----------------------
game_state : ^GameState = nil;
ball_prev: r.Rectangle;
bar_prev: r.Rectangle;
ball: Ball;
bar: Bar;
targets: ^[TARGET_ROWS * TARGET_COLS]Target;
PART_SIZE :: 256;
particles: [PART_SIZE]Particle;

Target :: struct {
    rect: r.Rectangle,
    col: r.Color,
    hits_rem: i32 // hits needed to destroy it
}

GameState :: struct {
    state: State,
    lives: u32,
    death_timer: u32, // frames to stay in bottom
    score: u32,
    pause: bool,
    victory: bool
}

State :: enum {
    START, // shows mess , waiting until move
    READY, // waiting until space is pressed
    RESTART, // restarts the game
    GAME_OVER, // when ball hits the floor 3 times
    VICTORY, // all targets are eliminated
    UPDATE // normal update while playing
}

ResetType :: enum {
    INIT,
    RESET,
    RESTART
}

FadeType :: enum {
    FADE_IN,
    FADE_OUT
}

Ball :: struct {
    rect: r.Rectangle,
    vel: r.Vector2,
    active: bool
}

Bar :: struct {
    rect: r.Rectangle,
    vel: r.Vector2
}

Particle :: struct {
    pos: r.Vector2,
    vel: r.Vector2,
    col: r.Color,
    size: f32,
    alpha: f32,
    life_time: f32,
    active: bool
}

init_state :: proc () {
    game_state = new(GameState);
    reset_state(ResetType.INIT);

    game_state.state = .START;
}

reset_state :: proc (res_type: ResetType) {
    if res_type == ResetType.RESET { // reset -> ball on platform
        ball.rect.x = bar.rect.x + bar.rect.width/2.0 - ball.rect.width/2.0;
        ball.rect.y = bar.rect.y - ball.rect.height;
        ball.active = true;
        ball.vel = r.Vector2{0, 0};

        ball_prev = ball.rect; // teleport to middle of bar (due to lerp in draw)

        return;
    } else { // restart: plat and ball on init pos
        bar.rect.x = (WINDOW_WIDTH - BAR_WIDTH)/2.0;
        bar.rect.y = WINDOW_HEIGHT * 10/11.0;
        bar.rect.width = BAR_WIDTH;
        bar.rect.height = BAR_HEIGHT;

        ball.rect.x = (WINDOW_WIDTH - BALL_WIDTH)/2.0;
        ball.rect.y = bar.rect.y - BAR_HEIGHT - 2.0;
        ball.rect.width = BALL_WIDTH;
        ball.rect.height = BALL_HEIGHT;
        ball.vel = r.Vector2{0, 0};
        ball.active = true;
    }


    game_state.pause = false;
    game_state.lives = 3;
    game_state.score = 0;
    game_state.victory = false;

    pos_y: f32 = WINDOW_HEIGHT/30;
    targ_color: [5]r.Color = {r.RED, r.ORANGE, r.GREEN, r.YELLOW, r.PURPLE};
    idx := 0;
    hits_rem: i32;

    if res_type == .INIT do targets = new([TARGET_ROWS * TARGET_COLS]Target);
    for i := 0; i < TARGET_ROWS; i += 1 {
        pos_x: f32 = (WINDOW_WIDTH - GRID_WIDTH)/2;

        switch (i) {
            case 0,1:
                hits_rem = 3;
            case 2,3,4:
                hits_rem = 2;
            case:
                hits_rem = 1;
        }

        for j := 0; j < TARGET_COLS; j += 1 {
            targets[i*TARGET_COLS + j].rect.x = pos_x;
            targets[i*TARGET_COLS + j].rect.y = pos_y;
            targets[i*TARGET_COLS + j].rect.width = TARGET_WIDTH;
            targets[i*TARGET_COLS + j].rect.height = TARGET_HEIGHT;
            targets[i*TARGET_COLS + j].col = targ_color[idx];
            targets[i*TARGET_COLS + j].hits_rem = hits_rem;

            pos_x += TARGET_WIDTH + PAD_X;
        }
        pos_y += TARGET_HEIGHT + PAD_Y;
        if i % 2 == 1 do idx += 1;
    }

}

spawn_particles :: proc (pos_x, pos_y: f32, targ_color: r.Color, part_count: int = 20) {
    per_hit_spawn := part_count;
    spawned := 0;

    for i := 0; i < PART_SIZE; i += 1 {
        if spawned >= per_hit_spawn do break;

        if !particles[i].active {
            particles[i].active = true;
            particles[i].pos = {pos_x, pos_y};

            angle := r.GetRandomValue(0, 360);
            speed := f32(r.GetRandomValue(300, 400));

            rad := f32(angle) * f32(math.RAD_PER_DEG);
            particles[i].vel.x = math.cos(rad) * speed;
            particles[i].vel.y = math.sin(rad) * speed;

            particles[i].col = targ_color;
            particles[i].alpha = 1.0;
            // 0.7 to 1 sec
            particles[i].life_time = f32(r.GetRandomValue(7, 10.0)) / 10.0;
            particles[i].size = f32(r.GetRandomValue(6, 10));

            spawned += 1;
        }
    }

}

update_particles :: proc (dt: f32) {
    for i := 0; i < PART_SIZE; i += 1 {
        if particles[i].active {
            particles[i].pos += particles[i].vel * dt;

            // age particle and fade out
            particles[i].life_time -= dt;
            particles[i].alpha = math.max(0.0, particles[i].life_time / 0.5);

            if particles[i].life_time <= 0 {
                particles[i].active = false;
            }
        }
    }
}

update_platform_pos :: proc (do_ball: bool, dt: f32) -> bool {
    key_pressed: bool = false;
    x_offs := BAR_SPEED*dt;
    bar.vel.x = 0.0;

    if r.IsKeyDown(r.KeyboardKey.LEFT) &&
    bar.rect.x - x_offs >= 0.0 {
        bar.rect.x -= x_offs;
        bar.vel.x = -BAR_SPEED;
        if do_ball do ball.rect.x -= x_offs;
        key_pressed = true;
    }
    if r.IsKeyDown(r.KeyboardKey.RIGHT) &&
    bar.rect.x + x_offs + BAR_WIDTH <= WINDOW_WIDTH {
        bar.rect.x += x_offs;
        bar.vel.x = BAR_SPEED;
        if do_ball do ball.rect.x += x_offs;
        key_pressed = true;
    }
    return key_pressed;
}

check_horiz_collisions :: proc (dt: f32) {
    next_x := ball.rect.x + ball.vel.x * dt; // default next point without col

    if next_x <= 0.0 { // left
        ball.rect.x = 0;
        ball.vel.x *= -1;
        return;
    }

    if next_x + ball.rect.width >= WINDOW_WIDTH { // right
        ball.rect.x = WINDOW_WIDTH - ball.rect.width;
        ball.vel.x *= -1;
        return;
    }

    fut_ball := r.Rectangle{next_x, ball.rect.y, ball.rect.width, ball.rect.height};
    if r.CheckCollisionRecs(fut_ball, bar.rect) {

        // move it a little so it doesnt get stuck in the platform
        if next_x < bar.rect.x {
            ball.rect.x = bar.rect.x - ball.rect.width;
        } else {
            ball.rect.x = bar.rect.x + bar.rect.width;
        }

        ball.vel.x *= -1;

        if bar.vel.x != 0.0 {
            ball.vel.x = math.lerp(ball.vel.x, bar.vel.x, f32(0.40));

            max_h_speed := BALL_SPEED * 1.5;
            ball.vel.x = clamp(ball.vel.x, -max_h_speed, max_h_speed);
        }

        return;
    }

    // ball vs targets
    targ_hit : int = 0;
    for i := 0; i < TARGET_ROWS; i += 1 {
        for j := 0; j < TARGET_COLS; j += 1 {
            if targets[i*TARGET_COLS + j].hits_rem == 0 {
                targ_hit += 1;
                continue;
            }
            fut_ball := r.Rectangle{next_x, ball.rect.y, ball.rect.width, ball.rect.height};

            if r.CheckCollisionRecs(fut_ball, targets[i*TARGET_COLS + j].rect) {
                targets[i*TARGET_COLS + j].hits_rem -= 1;
                if targets[i*TARGET_COLS + j].hits_rem == 0 {
                    game_state.score += 1;
                } else {
                    spawn_particles(fut_ball.x,
                                    fut_ball.y,
                                    targets[i*TARGET_COLS + j].col);
                }
                ball.vel.x *= -1;
                return;
            }
        }
    }

    ball.rect.x = next_x;
    if targ_hit == TARGET_COLS*TARGET_ROWS do game_state.victory = true;
    return;
}

check_vert_collisions :: proc (dt: f32) {
    next_y := ball.rect.y + ball.vel.y * dt; // normal next pos without col

    if next_y < 0.0 { // top
        ball.rect.y = 0.0;
        ball.vel.y *= -1;
        return;
    }

    if next_y + ball.rect.height >= WINDOW_HEIGHT { // bottom
        ball.vel = r.Vector2{0, 0};
        ball.active = false;
        game_state.lives -= 1;
        spawn_particles(ball.rect.x,
                        ball.rect.y,
                        r.GetColor(BALL_COLOR),
                        50);

        if game_state.lives == 0 {
            game_state.state = .GAME_OVER;
            spawn_particles(bar.rect.x,
                            bar.rect.y,
                            r.GetColor(BAR_COLOR),
                           50);

            return;
        }

        game_state.state = .READY;
        reset_state(.RESET);
        return;
    }

    // ball vs platform
    fut_ball := r.Rectangle{ball.rect.x, next_y, ball.rect.width, ball.rect.height};
    if r.CheckCollisionRecs(fut_ball, bar.rect) {
        ball.vel.y *= -1;

        // calculate the natural hit factor based on where it hit (-1.0 to 1.0)
        hit_f := ((ball.rect.x + ball.rect.width/2.0) - (bar.rect.x + bar.rect.width/2.0)) / (bar.rect.width/2.0);
        natural_vel_x := hit_f * BALL_SPEED;

        plat_influence: f32 = 0.30;
        if bar.vel.x == 0.0 do plat_influence = 0.0;

        // ball.vel = based on bar's influence
        ball.vel.x = math.lerp(natural_vel_x, bar.vel.x, plat_influence);

        // upper limit ball vel: 1.5 * Ball_SPEED
        max_h_speed := BALL_SPEED * 1.5;
        ball.vel.x = clamp(ball.vel.x, -max_h_speed, max_h_speed);

        return;
    }

    targ_hit: int = 0;
    for i := 0; i < TARGET_ROWS; i += 1 {
        for j := 0; j < TARGET_COLS; j += 1 {
            if targets[i*TARGET_COLS + j].hits_rem == 0 {
                targ_hit += 1;
                continue;
            }
            fut_ball := r.Rectangle{ball.rect.x, next_y, ball.rect.width, ball.rect.height};

            if r.CheckCollisionRecs(fut_ball, targets[i*TARGET_COLS + j].rect) {
                targets[i*TARGET_COLS + j].hits_rem -= 1;
                if targets[i*TARGET_COLS + j].hits_rem == 0 {
                    game_state.score += 1;
                } else {
                    spawn_particles(fut_ball.x,
                                    fut_ball.y,
                                    targets[i*TARGET_COLS + j].col);
                }
                ball.vel.y *= -1;
                return;
            }
        }
    }

    ball.rect.y = next_y;
    if targ_hit == TARGET_COLS*TARGET_ROWS do game_state.victory = true;
    return;
}

update_curtain :: proc (fade: FadeType, dt: f32) {
    switch (fade) {
        case .FADE_OUT:
            curtain = math.clamp(curtain + (dt / fade_out_dur), 0.0, 1.0);
            if curtain == 1.0 do show_prompt = true;

        case .FADE_IN:
            show_prompt = false;
            curtain = math.clamp(curtain - (dt / fade_in_dur), 0.0, 1.0);
            if curtain == 0.0 do game_state.state = .READY;
    }
}

update :: proc (dt: f32) {
    switch (game_state.state) {
        case .START:
            ball.vel = r.Vector2{0,0};
            ret: bool = update_platform_pos(do_ball = true, dt = dt);
            if ret do game_state.state = .READY;

        case .GAME_OVER, .VICTORY:
            update_particles(dt);
            update_curtain(.FADE_OUT, dt);
            if show_prompt && r.IsKeyDown(r.KeyboardKey.SPACE) {
                game_state.state = .RESTART;
                reset_state(ResetType.RESTART);
            }

        case .RESTART:
            update_curtain(.FADE_IN, dt);

        case .READY:
            update_particles(dt);
            update_platform_pos(do_ball = true, dt = dt);
            if r.IsKeyDown(r.KeyboardKey.SPACE) {
                ball.vel.y = -BALL_SPEED;
                ball.vel.x = bar.vel.x * 0.5;
                if ball.vel.x == 0.0 do ball.vel.x = BALL_SPEED * 0.35; // give it an angle
                game_state.state = .UPDATE;
            }
        case .UPDATE:
            update_platform_pos(do_ball = false, dt = dt);
            update_particles(dt);
            // upd ball pos
            check_horiz_collisions(dt);
            check_vert_collisions(dt);
            if game_state.victory do game_state.state = .VICTORY;
    }
}

draw_particles :: proc() {
    for i := 0; i < PART_SIZE; i += 1 {
        if !particles[i].active do continue;

        p := particles[i];
        render_color := p.col;
        render_color.a = u8(p.alpha * 255.0);

        r.DrawRectangleV(p.pos, {p.size, p.size}, render_color);
    }
}

draw :: proc (alpha: f32) {
    draw_particles();

    // render targets
    for i := 0; i < len(targets); i += 1 {
        if targets[i].hits_rem != 0 {
            r.DrawRectangleRec(targets[i].rect, targets[i].col);
        }
    }

    // render bar and ball
    if game_state.lives != 0 {
        rend_bar := bar.rect;
        rend_bar.x = math.lerp(bar_prev.x, bar.rect.x, alpha);
        r.DrawRectangleRec(rend_bar, r.GetColor(BAR_COLOR));
    }

    if ball.active {
        rend_ball := ball.rect
        rend_ball.x = math.lerp(ball_prev.x, ball.rect.x, alpha)
        rend_ball.y = math.lerp(ball_prev.y, ball.rect.y, alpha)
        r.DrawRectangleRec(rend_ball, r.GetColor(BALL_COLOR));
    }

    // render score and lives
    pos_y   : i32 = WINDOW_HEIGHT / 30;
    base_x  : i32 = i32((WINDOW_WIDTH - GRID_WIDTH) / 4) - 80; // Left edge of the labels
    value_x : i32 = base_x + 110;

    r.DrawText("Score:", base_x, pos_y, 30, r.LIGHTGRAY);
    r.DrawText(r.TextFormat("%d", game_state.score), value_x, pos_y, 30, r.LIGHTGRAY);

    r.DrawText("Lives:", base_x, pos_y + 40, 30, r.LIGHTGRAY);
    r.DrawText(r.TextFormat("%d", game_state.lives), value_x, pos_y + 40, 30, r.LIGHTGRAY);

    // render curtain
    if curtain > 0.0 {
        cc: r.Color = r.GetColor(BACKROUND_COLOR);
        cc.a = cast(u8) (curtain * 255.0);
        r.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, cc);
    }

    if game_state.pause {
        mes: cstring = "PAUSED";
        mes_len: i32 = r.MeasureText(mes, 50);
        r.DrawText(mes, (WINDOW_WIDTH-mes_len)/2, WINDOW_HEIGHT/2, 50, r.LIGHTGRAY);
    }

    #partial switch (game_state.state) {
        case .START:
            mes: cstring = "Press left or right arrow to move";
            mes_len: i32 = r.MeasureText(mes, 40);
            r.DrawText(mes, (WINDOW_WIDTH-mes_len)/2, WINDOW_HEIGHT/2, 40, r.LIGHTGRAY);
        case .GAME_OVER, .VICTORY:
            if !show_prompt do break;
            mes: cstring = (game_state.state == .GAME_OVER) ? "Game Over" : "Victory !";
            mes_len: i32 = r.MeasureText(mes, 60);
            r.DrawText(mes, (WINDOW_WIDTH-mes_len)/2, WINDOW_HEIGHT/2 - 40, 60, r.LIGHTGRAY);

            mes = "Press SPACE to restart";
            mes_len = r.MeasureText(mes, 30);
            r.DrawText(mes, (WINDOW_WIDTH-mes_len)/2, WINDOW_HEIGHT/2 + 30, 30, r.GRAY);
    }
}

main :: proc () {
    r.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, NAME);
    defer r.CloseWindow();

    init_state();
    defer free(targets);
    defer free(game_state);

    r.SetTargetFPS(0);

    accumulator: f32 = 0.0;
    alpha: f32 = 0.0;
    for !r.WindowShouldClose() {
        if r.IsKeyPressed(r.KeyboardKey.P) {
            game_state.pause = !game_state.pause;
        }

        if r.IsKeyPressed(r.KeyboardKey.Q) {
            break;
        }

        if !game_state.pause {
            last_frame_time := r.GetFrameTime();

            if last_frame_time > 0.25 do last_frame_time = 0.25;
            accumulator += last_frame_time;

            for accumulator >= TICK_RATE {
                bar_prev = bar.rect;
                ball_prev = ball.rect;

                update(f32(TICK_RATE));

                accumulator -= TICK_RATE;
            }

            alpha = f32(accumulator / TICK_RATE);
        }

        r.BeginDrawing();
        r.ClearBackground(r.GetColor(BACKROUND_COLOR));

        draw(alpha);

        r.EndDrawing();
    }

}
