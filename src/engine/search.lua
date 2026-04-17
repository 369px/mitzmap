-- =============================================================
-- game/ai/search.lua
-- AI search engine (Minimax, Quiescence, Simulation)
-- =============================================================

local AI_MAX_Q_DEPTH = 3
local AI_MOVE_TIMEOUT = 10 -- Reduced slightly for responsiveness
local ai_nodes_visited = 0
local ai_search_start_time = 0
local ai_search_interrupted = false

-- Transposition Table
local ai_tt = {}
local ai_tt_hits = 0

-- Flags for TT
local TT_EXACT = 0
local TT_ALPHA = 1
local TT_BETA  = 2

-- Update castling rights for simulation
function ai_update_castling(mv, pc, rights)
  local nr = {wK = rights.wK, wQ = rights.wQ, bK = rights.bK, bQ = rights.bQ}
  -- King moved
  if pc == "K" then nr.wK = false nr.wQ = false
  elseif pc == "k" then nr.bK = false nr.bQ = false end
  
  -- Rook moved or captured
  -- White Rooks: (1,1) and (8,1)
  if (mv.x1 == 1 and mv.y1 == 1) or (mv.x2 == 1 and mv.y2 == 1) then nr.wQ = false end
  if (mv.x1 == 8 and mv.y1 == 1) or (mv.x2 == 8 and mv.y2 == 1) then nr.wK = false end
  -- Black Rooks: (1,8) and (8,8)
  if (mv.x1 == 1 and mv.y1 == 8) or (mv.x2 == 1 and mv.y2 == 8) then nr.bQ = false end
  if (mv.x1 == 8 and mv.y1 == 8) or (mv.x2 == 8 and mv.y2 == 8) then nr.bK = false end
  
  return nr
end

-- Apply move directly for simulation, save state for undo
function ai_apply_move_sim(b, mv, pc, ep)
  local is_ep = (ep and string.lower(pc) == "p" and mv.x2 == ep.x and mv.y2 == ep.y and b[mv.y2][mv.x2] == ".")
  local captured = b[mv.y2][mv.x2]

  local undo = {
    x1 = mv.x1, y1 = mv.y1, x2 = mv.x2, y2 = mv.y2,
    pc = pc, captured = captured,
    castle = mv.castle, is_ep = is_ep, cap_p_y = nil, cap_p_pc = nil
  }

  if mv.castle then
    b[mv.y2][mv.x2] = pc
    b[mv.y1][mv.x1] = "."
    if mv.castle == "K" then
      b[mv.y2][6] = b[mv.y2][8]
      b[mv.y2][8] = "."
    else
      b[mv.y2][4] = b[mv.y2][1]
      b[mv.y2][1] = "."
    end
  else
    b[mv.y2][mv.x2] = pc
    b[mv.y1][mv.x1] = "."
    if is_ep then
      undo.cap_p_y = mv.y2 - (is_white(pc) and 1 or -1)
      undo.cap_p_pc = b[undo.cap_p_y][mv.x2]
      b[undo.cap_p_y][mv.x2] = "."
    end
    if string.lower(pc) == "p" and (mv.y2 == 1 or mv.y2 == 8) then
      b[mv.y2][mv.x2] = is_white(pc) and "Q" or "q"
    end
  end
  
  return undo
end

function ai_revert_move_sim(b, undo)
  if undo.castle then
    b[undo.y1][undo.x1] = undo.pc
    b[undo.y2][undo.x2] = "."
    if undo.castle == "K" then
      b[undo.y2][8] = b[undo.y2][6]
      b[undo.y2][6] = "."
    else
      b[undo.y2][1] = b[undo.y2][4]
      b[undo.y2][4] = "."
    end
  else
    b[undo.y1][undo.x1] = undo.pc
    b[undo.y2][undo.x2] = undo.captured
    if undo.is_ep then
      b[undo.cap_p_y][undo.x2] = undo.cap_p_pc
    end
  end
end

function ai_quiescence(b, alpha, beta, is_maximizing, ai_color, q_depth, h, cast)
  ai_nodes_visited = ai_nodes_visited + 1
  if check_yield then check_yield() end

  -- TT Lookup
  local tt_entry = ai_tt[h]
  if tt_entry and tt_entry.depth >= 0 then
    if tt_entry.flag == TT_EXACT then return tt_entry.score
    elseif tt_entry.flag == TT_ALPHA and tt_entry.score <= alpha then return alpha
    elseif tt_entry.flag == TT_BETA and tt_entry.score >= beta then return beta
    end
  end

  local stand_pat = ai_eval_board(b, ai_color)
  if q_depth >= AI_MAX_Q_DEPTH then return stand_pat end

  if is_maximizing then
    if stand_pat >= beta then return stand_pat end
    if alpha < stand_pat then alpha = stand_pat end
  else
    if stand_pat <= alpha then return stand_pat end
    if beta > stand_pat then beta = stand_pat end
  end

  local color = is_maximizing and ai_color or (ai_color == "w" and "b" or "w")
  local captures = get_all_moves(color, b, nil, true, cast)
  
  if #captures == 0 then return stand_pat end

  if is_maximizing then
    local best_score = stand_pat
    for i = 1, #captures do
      local mv = captures[i]
      local pc = b[mv.y1][mv.x1]
      local target = b[mv.y2][mv.x2]
      
      -- Update Hash Incrementale
      local next_cast = ai_update_castling(mv, pc, cast)
      local next_h = zobrist_update(h, mv, pc, target, nil, nil, cast, next_cast)
      
      local undo = ai_apply_move_sim(b, mv, pc, nil)
      local ev = ai_quiescence(b, alpha, beta, false, ai_color, q_depth + 1, next_h, next_cast)
      ai_revert_move_sim(b, undo)

      if ev > best_score then best_score = ev end
      if ev > alpha then alpha = ev end
      if beta <= alpha then break end
    end
    return best_score
  else
    local best_score = stand_pat
    for i = 1, #captures do
      local mv = captures[i]
      local pc = b[mv.y1][mv.x1]
      local target = b[mv.y2][mv.x2]

      -- Update Hash Incrementale
      local next_cast = ai_update_castling(mv, pc, cast)
      local next_h = zobrist_update(h, mv, pc, target, nil, nil, cast, next_cast)

      local undo = ai_apply_move_sim(b, mv, pc, nil)
      local ev = ai_quiescence(b, alpha, beta, true, ai_color, q_depth + 1, next_h, next_cast)
      ai_revert_move_sim(b, undo)

      if ev < best_score then best_score = ev end
      if ev < beta then beta = ev end
      if beta <= alpha then break end
    end
    return best_score
  end
end

-- Heuristic score for move ordering
-- Analyze most promising moves FIRST to maximize Alpha-Beta pruning
function ai_score_move(b, mv, is_maximizing, ai_color)
  local score = 0
  local pc = b[mv.y1][mv.x1]
  local target = b[mv.y2][mv.x2]
  
  -- 1. Captures (MVV-LVA: Most Valuable Victim - Least Valuable Attacker)
  if target and target ~= "." then
    -- Use fixed values to avoid slow string lookups
    -- P=1, R=2, N=3, B=4, Q=5, K=6
    local v_val = 0
    if target == "p" or target == "P" then v_val = 100
    elseif target == "n" or target == "N" then v_val = 320
    elseif target == "b" or target == "B" then v_val = 330
    elseif target == "r" or target == "R" then v_val = 500
    elseif target == "q" or target == "Q" then v_val = 900
    else v_val = 10000 end
    
    local a_val = 0
    if pc == "p" or pc == "P" then a_val = 1
    elseif pc == "n" or pc == "N" then a_val = 3
    elseif pc == "b" or pc == "B" then a_val = 3
    elseif pc == "r" or pc == "R" then a_val = 5
    elseif pc == "q" or pc == "Q" then a_val = 9
    else a_val = 10 end

    score = score + 1000 + (v_val * 10) - a_val
  end
  
  -- 2. Promotion
  if (pc == "p" or pc == "P") and (mv.y2 == 1 or mv.y2 == 8) then
    score = score + 900
  end
  
  -- 3. Check (fast heuristic)
  -- Note: is_in_check is expensive, use a light version or avoid if it slows down too much
  -- For now, give a small bonus to castling
  if mv.castle then
    score = score + 50
  end

  return score
end

function ai_sort_moves_by_score(b, moves, color)
  if not b or not moves then return moves end
  local scored = {}
  for i=1,#moves do
     -- pass all the parameters to ai_score_move
     scored[i] = {mv = moves[i], score = ai_score_move(b, moves[i], true, color)}
  end
  
  -- Sort descending by score
  for i=1,#scored do
    for j=i+1,#scored do
      if scored[j].score > scored[i].score then
        scored[i], scored[j] = scored[j], scored[i]
      end
    end
  end
  
  local sorted = {}
  for i=1,#scored do sorted[i] = scored[i].mv end
  return sorted
end

function ai_minimax(b, depth, alpha, beta, is_maximizing, ai_color, ep, h, cast, history)
  ai_nodes_visited = ai_nodes_visited + 1
  if check_yield then check_yield() end

  -- 0. Repetition Detection
  if history and history[h] then
    -- Repetition penalty (minor to allow tactical draws but avoid loops)
    return is_maximizing and -100 or 100
  end

  -- 1. TT Lookup
  local alpha_orig = alpha
  local tt_entry = ai_tt[h]
  
  if tt_entry and tt_entry.depth >= depth then
    ai_tt_hits = ai_tt_hits + 1
    if tt_entry.flag == TT_EXACT then return tt_entry.score
    elseif tt_entry.flag == TT_ALPHA then alpha = math.max(alpha, tt_entry.score)
    elseif tt_entry.flag == TT_BETA then beta = math.min(beta, tt_entry.score)
    end
    if alpha >= beta then return tt_entry.score end
  end

  if depth <= 0 then
    return ai_quiescence(b, alpha, beta, is_maximizing, ai_color, 0, h, cast)
  end

  -- Check Timeout
  if ai_search_start_time > 0 and t() - ai_search_start_time > AI_MOVE_TIMEOUT then
    ai_search_interrupted = true
    return ai_eval_board(b, ai_color)
  end

  local current_color = is_maximizing and ai_color or (ai_color == "w" and "b" or "w")
  local moves = get_all_moves(current_color, b, ep, false, cast)
  
  if #moves == 0 then
    if is_in_check(current_color, b) then
       return is_maximizing and (-99999 - depth) or (99999 + depth)
    else
       -- Stalemate / Draw
       -- Contempt Factor: Penalize draw if winning, seek if losing
       -- This score is ALWAYS relative to 'ai_color'.
       local eval = ai_eval_board(b, ai_color)
       if eval > 300 then return -5000 end -- Bad for AI (winning but drawing)
       if eval < -300 then return 5000 end  -- Good for AI (losing but drawing)
       return 0
    end
  end

  -- Move Ordering premia la mossa suggerita dalla TT
  if tt_entry and tt_entry.move then
    for i=1,#moves do
      if moves[i].x1 == tt_entry.move.x1 and moves[i].y1 == tt_entry.move.y1 and 
         moves[i].x2 == tt_entry.move.x2 and moves[i].y2 == tt_entry.move.y2 then
         table.remove(moves, i)
         table.insert(moves, 1, tt_entry.move)
         break
      end
    end
  end

  if depth > 1 then
    moves = ai_sort_moves_by_score(b, moves, current_color)
  end

  local best_depth_move = moves[1]
  if is_maximizing then
    local max_eval = -math.huge
    for i = 1, #moves do
      local mv = moves[i]
      local pc = b[mv.y1][mv.x1]
      local captured = b[mv.y2][mv.x2]

      local next_ep = nil
      if (pc=="P" or pc=="p") and math.abs(mv.y2 - mv.y1) == 2 then
         next_ep = {x = mv.x1, y = mv.y1 + (is_white(pc) and 1 or -1)}
      end
      
      -- Update State incrementale
      local next_cast = ai_update_castling(mv, pc, cast)
      local next_h = zobrist_update(h, mv, pc, captured, ep, next_ep, cast, next_cast)

      local undo = ai_apply_move_sim(b, mv, pc, ep)
      local ev = ai_minimax(b, depth - 1, alpha, beta, false, ai_color, next_ep, next_h, next_cast, history)
      ai_revert_move_sim(b, undo)

      if ev > max_eval then
        max_eval = ev
        best_depth_move = mv
      end
      alpha = math.max(alpha, ev)
      if beta <= alpha then break end
    end
    
    -- Salva in TT
    local flag = (max_eval <= alpha_orig) and TT_BETA or ((max_eval >= beta) and TT_ALPHA or TT_EXACT)
    ai_tt[h] = {score = max_eval, depth = depth, flag = flag, move = best_depth_move}
    return max_eval
  else
    local min_eval = math.huge
    for i = 1, #moves do
      local mv = moves[i]
      local pc = b[mv.y1][mv.x1]
      local captured = b[mv.y2][mv.x2]

      local next_ep = nil
      if (pc=="P" or pc=="p") and math.abs(mv.y2 - mv.y1) == 2 then
         next_ep = {x = mv.x1, y = mv.y1 + (is_white(pc) and 1 or -1)}
      end

      -- Update State incrementale
      local next_cast = ai_update_castling(mv, pc, cast)
      local next_h = zobrist_update(h, mv, pc, captured, ep, next_ep, cast, next_cast)

      local undo = ai_apply_move_sim(b, mv, pc, ep)
      local ev = ai_minimax(b, depth - 1, alpha, beta, true, ai_color, next_ep, next_h, next_cast, history)
      ai_revert_move_sim(b, undo)

      if ev < min_eval then
        min_eval = ev
        best_depth_move = mv
      end
      beta = math.min(beta, ev)
      if beta <= alpha then break end
    end
    
    -- Salva in TT
    local flag = (min_eval <= alpha_orig) and TT_BETA or ((min_eval >= beta) and TT_ALPHA or TT_EXACT)
    ai_tt[h] = {score = min_eval, depth = depth, flag = flag, move = best_depth_move}
    return min_eval
  end
end

function ai_search_best(color, board_state, ep, max_depth, history)
  ai_nodes_visited = 0
  ai_tt_hits = 0
  ai_search_start_time = t()
  ai_search_interrupted = false
  
  -- Svuota la TT se troppo grande
  local count = 0
  for _ in pairs(ai_tt) do count = count + 1 end
  if count > 20000 then ai_tt = {} end

  -- Copia locale dei diritti di arrocco per la simulazione
  local root_cast = {wK=castling.wK, wQ=castling.wQ, bK=castling.bK, bQ=castling.bQ}

  local best_overall_move = nil
  local last_eval = 0
  local moves = get_all_moves(color, board_state, ep, false, root_cast)
  if #moves == 0 then return nil end

  -- Calcola hash iniziale con i diritti locali
  local root_h = zobrist_hash_board(board_state, color, root_cast, ep)

  printh("\n--- bot thinking (max depth " .. max_depth .. ") ---")

  -- Iterative Deepening
  for d = 1, max_depth do
    local d_start_t = t()
    local current_depth_best_move = nil
    local best_eval = -math.huge
    
    -- Move Ordering
    moves = ai_sort_moves_by_score(board_state, moves, color)
    
    -- Priotità mossa TT
    local tt_root = ai_tt[root_h]
    if tt_root and tt_root.move then
      for i=1,#moves do
        if moves[i].x1 == tt_root.move.x1 and moves[i].y1 == tt_root.move.y1 and 
           moves[i].x2 == tt_root.move.x2 and moves[i].y2 == tt_root.move.y2 then
           table.remove(moves, i)
           table.insert(moves, 1, tt_root.move)
           break
        end
      end
    end

    local sim_board = clone_board(board_state)
    local threshold = (d <= 2) and 60 or 20

    for i = 1, #moves do
      local mv = moves[i]
      local pc = sim_board[mv.y1][mv.x1]
      local captured = sim_board[mv.y2][mv.x2]

      local next_ep = nil
      if (pc=="P" or pc=="p") and math.abs(mv.y2 - mv.y1) == 2 then
         next_ep = {x = mv.x1, y = mv.y1 + (is_white(pc) and 1 or -1)}
      end
      
      -- Update incrementale
      local next_cast = ai_update_castling(mv, pc, root_cast)
      local next_h = zobrist_update(root_h, mv, pc, captured, ep, next_ep, root_cast, next_cast)

      local undo = ai_apply_move_sim(sim_board, mv, pc, ep)
      local alpha = best_eval - threshold
      local ev = ai_minimax(sim_board, d - 1, alpha, math.huge, false, color, next_ep, next_h, next_cast, history)
      ai_revert_move_sim(sim_board, undo)
      
      if ai_search_interrupted then break end

      if ev > best_eval then
        best_eval = ev
        current_depth_best_move = moves[i]
      end
    end

    if ai_search_interrupted then
      printh("timeout! stopping at depth " .. d .. " (incomplete)")
      break
    else
      best_overall_move = current_depth_best_move
      last_eval = best_eval
      
      -- Early Exit: if we found a mate or overwhelming win, no need to search deeper
      if best_eval > 90000 then
        printh("early exit: overwhelming advantage detected")
        break
      end
      
      local d_duration = t() - d_start_t
      printh("completed depth " .. d .. " | time: " .. d_duration .. "s | best: " .. (best_overall_move.x1..best_overall_move.y1..best_overall_move.x2..best_overall_move.y2) .. " | eval: " .. best_eval)
      
      -- Early Exit: Se abbiamo un vantaggio enorme e siamo a profondità >= 3, chiudiamo subito
      if d >= 3 and best_eval > 1500 then
         printh("early exit: overwhelming advantage detected")
         break
      end
    end
    
    if t() - ai_search_start_time > AI_MOVE_TIMEOUT * 0.5 then
      printh("time management: stopping before depth " .. (d+1))
      break
    end
  end

  local total_duration = t() - ai_search_start_time
  printh("thinking complete | nodes: " .. ai_nodes_visited .. " | TT hits: " .. ai_tt_hits .. " | total time: " .. total_duration .. "s")

  return best_overall_move or moves[1]
end
