-- =============================================================
-- game/ai/bot_logic.lua
-- Bot logic, difficulty scaling, animations and the main thinking loop.
-- =============================================================

-- Coroutine for asynchronous AI thinking
local ai_co = nil
local ai_skip_next_thinking_quote = false
local ai_quote_locked_this_turn = false

-- =============================================================
-- EASY: Mix between sensible moves (depth 1) and parametric randomness
-- =============================================================
function ai_easy(color, b, ep, hist)
  local chance = (cpu_randomness ~= nil) and cpu_randomness or 0.5
  if rnd(1) < chance then
    local moves = get_all_moves(color, b, ep, false, castling)
    if #moves == 0 then return nil end
    return moves[math.floor(rnd(#moves)) + 1]
  else
    return ai_search_best(color, b, ep, 1, hist)
  end
end

-- =============================================================
-- MEDIUM: Minimax Depth 2 + potential rare random moves
-- =============================================================
function ai_medium(color, b, ep, hist)
  local chance = (cpu_randomness ~= nil) and cpu_randomness or 0.0
  if chance > 0 and rnd(1) < chance then
    local moves = get_all_moves(color, b, ep, false, castling)
    if #moves > 0 then return moves[math.floor(rnd(#moves)) + 1] end
  end
  return ai_search_best(color, b, ep, 2, hist)
end

-- =============================================================
-- HARD: Minimax Depth 3 + potential rare random moves
-- =============================================================
function ai_hard(color, b, ep, hist)
  local chance = (cpu_randomness ~= nil) and cpu_randomness or 0.0
  if chance > 0 and rnd(1) < chance then
    local moves = get_all_moves(color, b, ep, false, castling)
    if #moves > 0 then return moves[math.floor(rnd(#moves)) + 1] end
  end
  return ai_search_best(color, b, ep, 3, hist)
end

-- =============================================================
-- EXPERT: Minimax Depth 4 (bot 2000+)
-- =============================================================
function ai_expert(color, b, ep, hist)
  return ai_search_best(color, b, ep, 4, hist)
end

-- =============================================================
-- MASTER: Minimax Depth 5 (Final bosses, 2700+)
-- =============================================================
function ai_master(color, b, ep, hist)
  return ai_search_best(color, b, ep, 5, hist)
end

-- =============================================================
-- OPENING BOOK MANAGEMENT
-- =============================================================
function get_book_move()
  local key = ""
  for i = 1, #states_history do
    local s = states_history[i]
    if s and s.last_move then
      local m = s.last_move
      key = key .. m.x1 .. m.y1 .. m.x2 .. m.y2
      if i < #states_history then key = key .. " " end
    end
  end
  
  local choices = OPENING_BOOK[key]
  if not choices or #choices == 0 then 
    if key ~= "" then
      printh("book: no move found for key [" .. key .. "]")
    end
    return nil 
  end
  
  local pick = choices[math.floor(rnd(#choices)) + 1]
  printh("book: found move " .. pick .. " for key [" .. key .. "]")
  
  return {
    x1 = tonumber(string.sub(pick, 1, 1)),
    y1 = tonumber(string.sub(pick, 2, 2)),
    x2 = tonumber(string.sub(pick, 3, 3)),
    y2 = tonumber(string.sub(pick, 4, 4))
  }
end

-- =============================================================
-- ASYCHRONOUS API (Coroutine management)
-- =============================================================
function ai_start_thinking(color, b, difficulty, ep)
  -- Accumula gli hash della storia per evitare ripetizioni
  local history_hashes = {}
  if states_history then
    for i=0,#states_history do
      if states_history[i] and states_history[i].hash then
        history_hashes[states_history[i].hash] = true
      end
    end
  end

  ai_co = cocreate(function()
    difficulty = string.lower(difficulty or "easy")
    printh("ai_start_thinking: " .. color .. " (level: " .. difficulty .. ")")
    
    if difficulty == "hard" or difficulty == "medium" or difficulty == "expert" or difficulty == "master" then
      local book_mv = get_book_move()
      if book_mv then
        printh("ai: using book move")
        for i=1,2 do yield() end
        return book_mv
      end
    end
    if states_history and #states_history < 20 then
      printh("ai: book move not found, starting engine search")
    end
    
    if difficulty == "easy"   then return ai_easy(color, b, ep, history_hashes) end
    if difficulty == "medium" then return ai_medium(color, b, ep, history_hashes) end
    if difficulty == "hard"   then return ai_hard(color, b, ep, history_hashes) end
    if difficulty == "expert" then return ai_expert(color, b, ep, history_hashes) end
    if difficulty == "master" then return ai_master(color, b, ep, history_hashes) end
    return ai_easy(color, b, ep, history_hashes)
  end)
end

function ai_update()
  if type(ai_co) == "thread" and costatus(ai_co) ~= "dead" then
    local ok, res = coresume(ai_co)
    if not ok then
      printh("AI Coroutine Error: " .. tostring(res))
      ai_co = nil
      return {error=true}
    end
    if costatus(ai_co) == "dead" then
       local move = res
       ai_co = nil
       return move
    end
  end
  return nil
end

-- =============================================================
-- update_ai_logic - Frame-by-frame management of AI thinking
-- =============================================================
function update_ai_logic()
  -- CPU thinking only during active turns in CPU or Arena mode
  local is_cpu_turn = (game_mode == "cpu" or game_mode == "arena_bot") 
                  and game_state.mode ~= "gameover" 
                  and game_state.result == "" 
                  and game_state.turn == cpu_color 
                  and view_move_index == #states_history

  if is_cpu_turn then
    if not ai_is_thinking and cpu_timer <= 0 then
      printh("bot: turn detected, starting logic chain...")
    end
    
    if cpu_timer > 0 then 
      cpu_timer = cpu_timer - 1
      return true
    end

    if not ai_is_thinking then
      printh("bot: launching thinking coroutine (level: " .. (cpu_level or "unknown") .. ")...")
      ai_start_thinking(cpu_color, board, cpu_level, ep_target)
      ai_is_thinking   = true
      ai_bubble_timer  = 120 -- Minimum display time for the *new* thinking quote
      ai_pending_move  = nil
      
      -- Pick quote: preferentially from bot's thinking table
      -- AVOID overwriting the greeting on the first move of the game!
      -- AVOID overwriting a dynamic event reaction (capture/check)
      -- LOCK: Ensure only ONE thinking quote is picked per full turn
      if #move_history > 0 and not ai_quote_locked_this_turn then
        ai_quote_locked_this_turn = true
        if ai_skip_next_thinking_quote then
          ai_skip_next_thinking_quote = false -- Use once
        else
          local bot = get_bot_by_id(current_bot_id)
          if bot and bot.quotes and bot.quotes.thinking and #bot.quotes.thinking > 0 then
            ai_current_quote = bot.quotes.thinking[math.floor(rnd(#bot.quotes.thinking))+1]
          else
            ai_current_quote = ai_quotes[math.floor(rnd(#ai_quotes))+1]
          end
          ai_text_progress = 0 -- Restart typewriter for the new quote
        end
      end
      game_state.msg   = ""

    else
      if ai_bubble_timer > 0 then ai_bubble_timer = ai_bubble_timer - 1 end

      if not ai_pending_move then
        ai_pending_move = ai_update()
      end

      -- If move is ready AND we've shown the bubble for enough time
      if ai_pending_move and ai_bubble_timer <= 0 then
        local mv = ai_pending_move
        ai_pending_move = nil
        ai_is_thinking  = false -- This hides dots, but bubble stays because ai_current_quote persists
        game_state.msg  = ""

        if not mv.error then
          if mv.castle then
            printh("bot: performing castle " .. mv.castle)
            perform_castle(mv.castle, cpu_color, board)
            legal_moves = {}
            check_game_end(board)
          else
            printh("bot: making move " .. mv.x1 .. mv.y1 .. " to " .. mv.x2 .. mv.y2)
            make_move(mv.x1, mv.y1, mv.x2, mv.y2, board)
          end
        else
          game_state.msg = mv.err_msg or "AI SYSTEM ERROR"
        end
        cpu_timer = 15
      else
        local n = math.floor(time() * 2) % 4
        ai_thinking_dots = ""
        for i = 1, n do ai_thinking_dots = ai_thinking_dots .. "." end
      end
    end
    return true
  else
    -- Reset lock when it's NOT the CPU turn, so it can pick a new one next time
    ai_quote_locked_this_turn = false
    
    if ai_is_thinking then
      ai_is_thinking   = false
      ai_pending_move  = nil
    end
    return false
  end


end

-- =============================================================
-- DYNAMIC REACTIONS (Captures & Checks)
-- =============================================================

function trigger_bot_event_quote(event_type, piece_char)
  local bot = get_bot_by_id(current_bot_id)
  if not bot or not bot.quotes or not bot.quotes[event_type] then return end

  local q_list = bot.quotes[event_type]
  if #q_list == 0 then return end

  local quote = q_list[math.floor(rnd(#q_list)) + 1]
  
  -- Piece name mapping
  local p_names = {
    p = "Pawn", n = "Knight", b = "Bishop", r = "Rook", q = "Queen", k = "King",
    P = "Pawn", N = "Knight", B = "Bishop", R = "Rook", Q = "Queen", K = "King"
  }
  local pname = piece_char and p_names[piece_char] or "piece"

  -- Placeholder substitution
  quote = string.gsub(quote, "%[PIECE%]", pname)
  quote = string.gsub(quote, "%[piece%]", string.lower(pname))

  -- Apply and reset typewriter
  ai_current_quote = quote
  ai_text_progress = 0
  ai_skip_next_thinking_quote = true -- Do not overwrite this event quote with "thinking..."
end

-- =============================================================
-- AVATAR ANIMATIONS
-- =============================================================
function update_ai_avatar_animation()
  -- Increment typewriter progress (0.8 chars per frame = ~48 chars per second)
  if ai_current_quote and ai_current_quote ~= "" then
    if ai_text_progress < #ai_current_quote then
      ai_text_progress = math.min(#ai_current_quote, ai_text_progress + 0.8)
    end
  end



  if (game_mode == "arena_bot" or game_mode == "cpu") and current_bot_id then
    local bot = get_bot_by_id(current_bot_id)
    if bot and bot.update_anim then
      ai_avatar_spr = bot:update_anim()
      return
    end
  end


  ai_blink_timer = ai_blink_timer - 1
  if ai_blink_timer <= 0 then
    if ai_avatar_spr == 56 then
      local r = math.random()
      if r < 0.2 then
        ai_avatar_spr = 58
        ai_blink_timer = 20 + math.random(40)
      else
        ai_avatar_spr = 57
        ai_blink_timer = 4 + math.random(6)
      end
    else
      ai_avatar_spr = 56
      ai_blink_timer = 50 + math.random(150)
    end
  end
end
