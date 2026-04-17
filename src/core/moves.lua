-- =============================================================
-- game/moves.lua
-- Punto di ingresso principale per l'esecuzione fisica delle mosse.
-- Incorporta i moduli di fine partita, notazione e helper.
-- =============================================================

include "game/end_conditions.lua"
include "game/san.lua"
include "game/move_helpers.lua"

-- -------------------------------------------------------------------------
-- Completamento mossa (post-validazione)
-- -------------------------------------------------------------------------


function finish_make_move(x1, y1, x2, y2, pc, dst, is_ep, promoted)
  update_castling_rights_on_move(x1, y1, x2, y2, pc, dst)

  local prev_ep = ep_target
  if string.lower(pc) == "p" and math.abs(y2 - y1) == 2 then
    ep_target = {x=x1, y=y1 + (is_white(pc) and 1 or -1)}
  else
    ep_target = nil
  end

  -- Genera SAN corretta
  local movestr = get_san_move(x1, y1, x2, y2, pc, dst, is_ep, promoted, board, prev_ep)
  push_history(movestr)

  if string.lower(pc) == "p" or cap then
    halfmove_clock = 0
  else
    halfmove_clock = halfmove_clock + 1
  end

  -- Tronca storia se si muove mentre si naviga il passato
  if view_move_index < #states_history then
    local new_sh, new_mh = {}, {}
    for i = 0, view_move_index do new_sh[i] = states_history[i] end
    for i = 1, view_move_index do new_mh[i] = move_history[i]   end
    states_history = new_sh
    move_history   = new_mh
  end

  toggle_turn()
  selected_square = nil
  legal_moves     = {}
  game_state.mode = "select_src"

  local opp = (game_state.turn == "w") and "w" or "b"
  local msg = (game_state.turn == "w") and "Tocca al Bianco." or "Tocca al Nero."
  local in_check = is_in_check(opp, board)
  if in_check then msg = msg .. " SCACCO!" end
  game_state.msg = msg

  -- Bot dynamic quotes hook
  if (game_mode == "cpu" or game_mode == "arena_bot") and current_bot_id then
    local mover_color = is_white(pc) and "w" or "b"
    local mover_is_cpu = (mover_color == cpu_color)
    -- (Note: Turn is ALREADY toggled, so opp is the victim)
    if in_check then
      trigger_bot_event_quote(mover_is_cpu and "on_giving_check" or "on_receiving_check")
    elseif dst ~= "." or is_ep then
      local cap_pc = is_ep and (is_white(pc) and "p" or "P") or dst
      trigger_bot_event_quote(mover_is_cpu and "on_capture_piece" or "on_lose_piece", cap_pc)
    end
  end


  check_game_end(board)

  local s = clone_state()
  s.last_move = {x1=x1, y1=y1, x2=x2, y2=y2, pc=pc}
  table.insert(states_history, s)
  view_move_index = #states_history
end




-- -------------------------------------------------------------------------
-- Esecuzione mossa principale
-- -------------------------------------------------------------------------

function make_move(x1, y1, x2, y2, b)
  local pc  = b[y1][x1]
  local dst = b[y2][x2]

  if not piece_belongs_to_turn(pc, game_state.turn) then
    return false, "Non e' il tuo pezzo."
  end

  -- Arrocco tramite spostamento re di 2 case
  if string.lower(pc) == "k" and y1 == y2 and x1 == 5 and math.abs(x2 - x1) == 2 then
    local side = (x2 == 7) and "K" or "Q"
    if try_castle(side) then return true end
    return false, "Arrocco non consentito."
  end

  if not is_valid_move(x1, y1, x2, y2, b, ep_target) then
    return false, "Mossa non valida."
  end

  local test  = clone_board(b)
  local is_ep = (ep_target and string.lower(pc) == "p" and math.abs(x2 - x1) == 1
                 and x2 == ep_target.x and y2 == ep_target.y and b[y2][x2] == ".")
  test[y2][x2] = pc; test[y1][x1] = "."
  if is_ep then
    test[y2 - (is_white(pc) and 1 or -1)][x2] = "."
  end
  if is_in_check(game_state.turn == "w" and "w" or "b", test) then
    return false, "Il tuo re sarebbe sotto scacco."
  end

  if b == board then
    queue_animation(pc, x1, y1, x2, y2, false)
    if dst ~= "." then
      queue_animation(dst, x2, y2, x2, y2, true)
    elseif is_ep then
      local cap_y = y2 - (is_white(pc) and 1 or -1)
      queue_animation(board[cap_y][x2], x2, cap_y, x2, cap_y, true)
    end
  end

  b[y2][x2] = pc; b[y1][x1] = "."
  if is_ep then b[y2 - (is_white(pc) and 1 or -1)][x2] = "." end

  -- Promozione pedone
  local promoted = false
  if string.lower(pc) == "p" and (y2 == 1 or y2 == 8) then
    if (game_mode == "cpu" or game_mode == "arena_bot") and game_state.turn == cpu_color then
      local promo_pc = (game_state.turn == "w") and "Q" or "q"
      b[y2][x2] = promo_pc; pc = promo_pc; promoted = true
    else
      pending_promotion = {sx=x1, sy=y1, x2=x2, y2=y2, pc=pc, dst=dst, is_ep=is_ep}
      game_state.mode = "promote"
      return true
    end
  end

  finish_make_move(x1, y1, x2, y2, pc, dst, is_ep, promoted)
  return true
end

-- -------------------------------------------------------------------------
-- Calcolo mosse legali per un pezzo (usato dall'input handler)
-- -------------------------------------------------------------------------

function get_legal_moves(sx, sy)
  local moves = {}
  local pc    = board[sy][sx]
  local color = game_state.turn
  for ty = 1, 8 do for tx = 1, 8 do
    if is_valid_move(sx, sy, tx, ty, board, ep_target) then
      local test = clone_board(board)
      test[ty][tx] = pc; test[sy][sx] = "."
      local is_ep_move = (ep_target and string.lower(pc) == "p" and math.abs(tx - sx) == 1
                          and tx == ep_target.x and ty == ep_target.y
                          and board[ty][tx] == ".")
      if is_ep_move then
        test[ty - (is_white(pc) and 1 or -1)][tx] = "."
      end
      if not is_in_check(color, test) then
        moves[#moves+1] = {x=tx, y=ty, ep=is_ep_move}
      end
    end
  end end
  -- Arrocco: evidenzia le caselle delle torri (stile chess.com)
  if string.lower(pc) == "k" then
    local ky = (color == "w") and 1 or 8
    if sy == ky and sx == 5 then
      if can_castle("K", color, board) then moves[#moves+1] = {x=8, y=ky, castle="K"} end
      if can_castle("Q", color, board) then moves[#moves+1] = {x=1, y=ky, castle="Q"} end
    end
  end
  return moves
end
