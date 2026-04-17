-- =============================================================
-- game/history.lua
-- Time travel: storico mosse, navigazione avanti/indietro.
-- Dipende da: board.lua (apply_state, clone_state), animating_pieces (board_renderer)
-- =============================================================

-- Stato globale dello storico
move_history    = {}   -- lista stringhe SAN
states_history  = {}   -- states_history[0..N]: snapsot dopo ogni mossa
view_move_index = 0    -- quale snapshot si sta visualizzando
history_scroll_x = 0
target_scroll_x  = 0

function push_history(str)
  move_history[#move_history+1] = str
end

-- Naviga di `dir` step nello storico (-1 = indietro, +1 = avanti)
function step_history(dir)
  local next_idx = view_move_index + dir
  if next_idx >= 0 and next_idx <= #states_history then
    if dir < 0 then
      local lm = states_history[view_move_index].last_move
      if lm then
        animating_pieces = {}
        queue_animation(lm.pc, lm.x2, lm.y2, lm.x1, lm.y1)
      end
    else
      local lm = states_history[next_idx].last_move
      if lm then
        animating_pieces = {}
        queue_animation(lm.pc, lm.x1, lm.y1, lm.x2, lm.y2)
      end
    end
    view_move_index = next_idx
    apply_state(states_history[view_move_index])
    selected_square = nil
    legal_moves     = {}
  end
end
-- Genera stringa PGN standard per l'esportazione
function export_pgn()
  -- Determina risultato
  local res = "*"
  if game_state.result == "checkmate_w" then res = "0-1"
  elseif game_state.result == "checkmate_b" then res = "1-0"
  elseif game_state.result == "stalemate" then res = "1/2-1/2" end

  -- Header PGN
  local date_str = string.gsub(date(), "%-", ".")
  local pgn = "[Event \"ChessTron Match\"]\n"
  pgn = pgn .. "[Site \"ChessTron\"]\n"
  pgn = pgn .. "[Date \""..date_str.."\"]\n"
  pgn = pgn .. "[White \"White\"]\n"
  pgn = pgn .. "[Black \"Black\"]\n"
  pgn = pgn .. "[Result \""..res.."\"]\n\n"

  -- Lista mosse
  for i = 1, #move_history do
    local m = move_history[i]
    if m ~= "Resign" then
      if i % 2 == 1 then
        pgn = pgn .. math.floor(i/2 + 1) .. ". "
      end
      pgn = pgn .. m .. " "
    end
  end

  pgn = pgn .. res
  return pgn
end
