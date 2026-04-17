-- =============================================================
-- game/rules.lua
-- Regole pure degli scacchi: validazione mosse, scacco, arrocco.
-- ZERO side effects: nessuna scrittura a globali, nessun I/O.
-- Dipende da: is_white (board.lua), board, ep_target, castling (globali di stato)
-- =============================================================

-- -------------------------------------------------------------------------
-- Helpers base
-- -------------------------------------------------------------------------

local function sign(n) if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end end

local function is_black(pc) return pc ~= "." and pc == string.lower(pc) end

local function same_color(a, b)
  if a == "." or b == "." then return false end
  return (is_white(a) and is_white(b)) or (is_black(a) and is_black(b))
end

local function is_empty_xy(b, x, y) return b[y][x] == "." end

function piece_belongs_to_turn(pc, turn)
  if pc == "." then return false end
  return (turn == "w" and is_white(pc)) or (turn == "b" and is_black(pc))
end

-- -------------------------------------------------------------------------
-- Percorso libero per pezzi in linea (torre, alfiere, regina)
-- -------------------------------------------------------------------------

local function clear_line(b, x1, y1, x2, y2)
  local dx = sign(x2 - x1)
  local dy = sign(y2 - y1)
  local cx, cy = x1 + dx, y1 + dy
  while cx ~= x2 or cy ~= y2 do
    if b[cy][cx] ~= "." then return false end
    cx = cx + dx
    cy = cy + dy
  end
  return true
end

-- -------------------------------------------------------------------------
-- Validazione per tipo di pezzo (funzioni locali)
-- -------------------------------------------------------------------------

local function is_valid_pawn(b, x1, y1, x2, y2, pc, ep)
  local dir        = is_white(pc) and 1 or -1
  local start_rank = is_white(pc) and 2 or 7
  local dx, dy     = x2 - x1, y2 - y1
  if dx == 0 and dy == dir and is_empty_xy(b, x2, y2) then return true end
  if dx == 0 and dy == 2 * dir and y1 == start_rank
     and is_empty_xy(b, x2, y2) and is_empty_xy(b, x1, y1 + dir) then
    return true
  end
  if math.abs(dx) == 1 and dy == dir then
    if not is_empty_xy(b, x2, y2) and not same_color(pc, b[y2][x2]) then return true end
    if ep and x2 == ep.x and y2 == ep.y then 
      local victim = b[y1][x2]
      if victim ~= "." and not same_color(pc, victim) then return true end
    end
  end
  return false
end

local function is_valid_rook(b, x1, y1, x2, y2)
  if x1 ~= x2 and y1 ~= y2 then return false end
  return clear_line(b, x1, y1, x2, y2)
end

local function is_valid_bishop(b, x1, y1, x2, y2)
  if math.abs(x2 - x1) ~= math.abs(y2 - y1) then return false end
  return clear_line(b, x1, y1, x2, y2)
end

local function is_valid_knight(_, x1, y1, x2, y2)
  local dx, dy = math.abs(x2 - x1), math.abs(y2 - y1)
  return (dx == 1 and dy == 2) or (dx == 2 and dy == 1)
end

local function is_valid_queen(b, x1, y1, x2, y2)
  return is_valid_rook(b, x1, y1, x2, y2) or is_valid_bishop(b, x1, y1, x2, y2)
end

local function is_valid_king(_, x1, y1, x2, y2)
  local dx, dy = math.abs(x2 - x1), math.abs(y2 - y1)
  return dx <= 1 and dy <= 1 and not (dx == 0 and dy == 0)
end

-- -------------------------------------------------------------------------
-- Dispatcher pubblico: is_valid_move
-- -------------------------------------------------------------------------

function is_valid_move(x1, y1, x2, y2, b, ep)
  if x2 < 1 or x2 > 8 or y2 < 1 or y2 > 8 then return false end
  local pc  = b[y1][x1]
  local dst = b[y2][x2]
  if pc == "." then return false end
  if ep and dst == "." and string.lower(pc) == "p" then
    -- en passant: casella dst vuota ma mossa diagonale pedone valida
  elseif same_color(pc, dst) then
    return false
  end
  local p = string.lower(pc)
  if     p == "p" then return is_valid_pawn(b, x1, y1, x2, y2, pc, ep)
  elseif p == "r" then return is_valid_rook(b, x1, y1, x2, y2)
  elseif p == "n" then return is_valid_knight(b, x1, y1, x2, y2)
  elseif p == "b" then return is_valid_bishop(b, x1, y1, x2, y2)
  elseif p == "q" then return is_valid_queen(b, x1, y1, x2, y2)
  elseif p == "k" then return is_valid_king(b, x1, y1, x2, y2)
  end
  return false
end

-- -------------------------------------------------------------------------
-- Ricerca re e verifica scacco
-- -------------------------------------------------------------------------

function find_king(color, b)
  local target = (color == "w") and "K" or "k"
  for y = 1, 8 do for x = 1, 8 do
    if b[y][x] == target then return x, y end
  end end
  return nil, nil
end


-- Ritorna true se la casa (tx, ty) è attaccata da un pezzo del colore `by_color`
function is_square_attacked(tx, ty, by_color, b)
  local is_w     = (by_color == "w")
  local target_n = is_w and "N" or "n"
  local target_k = is_w and "K" or "k"
  local target_p = is_w and "P" or "p"
  local target_r = is_w and "R" or "r"
  local target_b = is_w and "B" or "b"
  local target_q = is_w and "Q" or "q"

  -- 1. Cavallo
  local kn_dirs = {{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}
  for i=1, 8 do
    local x, y = tx + kn_dirs[i][1], ty + kn_dirs[i][2]
    if x >= 1 and x <= 8 and y >= 1 and y <= 8 and b[y][x] == target_n then return true end
  end
  
  -- 2. Re
  local k_dirs = {{-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1}}
  for i=1, 8 do
    local x, y = tx + k_dirs[i][1], ty + k_dirs[i][2]
    if x >= 1 and x <= 8 and y >= 1 and y <= 8 and b[y][x] == target_k then return true end
  end

  -- 3. Pedone
  local py = is_w and (ty - 1) or (ty + 1)
  if py >= 1 and py <= 8 then
    if tx > 1 and b[py][tx - 1] == target_p then return true end
    if tx < 8 and b[py][tx + 1] == target_p then return true end
  end

  -- 4. Sliders (Torre, Alfiere, Regina)
  local sliding_configs = {
    {dirs = {{1,0},{-1,0},{0,1},{0,-1}}, targets = {target_r, target_q}},
    {dirs = {{1,1},{1,-1},{-1,1},{-1,-1}}, targets = {target_b, target_q}}
  }

  for _, cfg in ipairs(sliding_configs) do
    for _, d in ipairs(cfg.dirs) do
      local x, y = tx + d[1], ty + d[2]
      while x >= 1 and x <= 8 and y >= 1 and y <= 8 do
        local pc = b[y][x]
        if pc ~= "." then
          if pc == cfg.targets[1] or pc == cfg.targets[2] then return true end
          break
        end
        x, y = x + d[1], y + d[2]
      end
    end
  end

  return false
end

function is_in_check(color, b)
  local kx, ky = find_king(color, b)
  if not kx then return false end
  local attacker = (color == "w") and "b" or "w"
  return is_square_attacked(kx, ky, attacker, b)
end

-- -------------------------------------------------------------------------
-- Legalità arrocco (legge castling globale)
-- -------------------------------------------------------------------------

function can_castle(side, color, b, rights)
  rights = rights or castling
  local y  = (color == "w") and 1 or 8
  local kx = 5
  local rx = (side == "K") and 8 or 1

  local kpc = (color == "w") and "K" or "k"
  local rpc = (color == "w") and "R" or "r"
  if b[y][kx] ~= kpc then return false, "Re non in casa." end
  if b[y][rx] ~= rpc then return false, "Torre non in casa." end

  if color == "w" then
    if side == "K" and not rights.wK then return false, "Arrocco consumato (wK)." end
    if side == "Q" and not rights.wQ then return false, "Arrocco consumato (wQ)." end
  else
    if side == "K" and not rights.bK then return false, "Arrocco consumato (bK)." end
    if side == "Q" and not rights.bQ then return false, "Arrocco consumato (bQ)." end
  end

  if side == "K" then
    if not is_empty_xy(b, 6, y) or not is_empty_xy(b, 7, y) then return false, "Case non libere." end
  else
    if not is_empty_xy(b, 2, y) or not is_empty_xy(b, 3, y) or not is_empty_xy(b, 4, y) then
      return false, "Case non libere."
    end
  end

  local enemy = (color == "w") and "b" or "w"
  if is_square_attacked(kx, y, enemy, b) then return false, "Re in scacco." end
  if side == "K" then
    if is_square_attacked(6, y, enemy, b) then return false, "f sotto attacco." end
    if is_square_attacked(7, y, enemy, b) then return false, "g sotto attacco." end
  else
    if is_square_attacked(4, y, enemy, b) then return false, "d sotto attacco." end
    if is_square_attacked(3, y, enemy, b) then return false, "c sotto attacco." end
  end
  return true
end

-- -------------------------------------------------------------------------
-- Verifica esistenza mosse legali (per stallo / scacco matto)
-- -------------------------------------------------------------------------

function has_any_legal_moves(color, b, ep)
  for sy = 1, 8 do for sx = 1, 8 do
    local pc = b[sy][sx]
    if pc ~= "." then
      local pc_color = (is_white(pc) and "w" or "b")
      if pc_color == color then
        for ty = 1, 8 do for tx = 1, 8 do
          if is_valid_move(sx, sy, tx, ty, b, ep) then
            local test = clone_board(b)
            test[ty][tx] = pc
            test[sy][sx] = "."
            if ep and tx == ep.x and ty == ep.y and string.lower(pc) == "p" and b[ty][tx] == "." then
              test[ty - (is_white(pc) and 1 or -1)][tx] = "."
            end
            if not is_in_check(color, test) then return true end
          end
        end end
      end
    end
  end end
  return false
end
