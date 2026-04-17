-- =============================================================
-- game/ai/zobrist.lua
-- Implementation of Zobrist Hashing to speed up TT
-- =============================================================

Z_PIECES = {}    -- [64][12]
Z_SIDE   = 0     -- Random number for White's turn
Z_CASTLING = {}  -- [4] (wK, wQ, bK, bQ)
Z_EP     = {}    -- [8] (columns a-h)

local function rand32()
  -- math.random(0, 2^31-1)
  return flr(rnd(0x7FFFFFFF))
end

function zobrist_init()
  math.randomseed(1337) -- Fixed seed for deterministic debugging
  
  -- 1. Initialize pieces for each square
  for i = 1, 64 do
    Z_PIECES[i] = {}
    for j = 1, 12 do
      Z_PIECES[i][j] = rand32()
    end
  end
  
  -- 2. Side to move (White)
  Z_SIDE = rand32()
  
  -- 3. Castling rights
  for i = 1, 4 do
    Z_CASTLING[i] = rand32()
  end
  
  -- 4. En Passant (file-based)
  for i = 1, 8 do
    Z_EP[i] = rand32()
  end
  
  printh("zobrist: tables initialized")
end

-- Map a piece string to an ID 1..12
Z_MAP = {
  ["P"]=1, ["R"]=2, ["N"]=3, ["B"]=4, ["Q"]=5, ["K"]=6,
  ["p"]=7, ["r"]=8, ["n"]=9, ["b"]=10,["q"]=11,["k"]=12
}

-- Calculate full hash from scratch (slow, use only at the beginning)
function zobrist_hash_board(b, turn, cast, ep)
  local h = 0
  
  -- Pieces
  for y = 1, 8 do
    local row = b[y]
    for x = 1, 8 do
      local pc = row[x]
      if pc ~= "." then
        local id = Z_MAP[pc]
        local idx = (y-1)*8 + x
        h = h ~ Z_PIECES[idx][id]
      end
    end
  end
  
  -- Turn (XOR if White is next)
  if turn == "w" then
    h = h ~ Z_SIDE
  end
  
  -- Castling
  if cast.wK then h = h ~ Z_CASTLING[1] end
  if cast.wQ then h = h ~ Z_CASTLING[2] end
  if cast.bK then h = h ~ Z_CASTLING[3] end
  if cast.bQ then h = h ~ Z_CASTLING[4] end
  
  -- En Passant
  if ep then
    h = h ~ Z_EP[ep.x]
  end
  
  return h
end

-- Fast Incremental Update
-- h: current hash
-- mv: move {x1,y1,x2,y2,promote,castle}
-- pc: moving piece
-- captured: piece at dest (can be nil/".")
-- old_ep/new_ep: en passant squares
-- old_cast/new_cast: castling rights
function zobrist_update(h, mv, pc, captured, old_ep, new_ep, old_cast, new_cast)
  -- 1. Flip Turn
  h = h ~ Z_SIDE
  
  -- 2. Remove piece from source
  local idx1 = (mv.y1-1)*8 + mv.x1
  h = h ~ Z_PIECES[idx1][Z_MAP[pc]]
  
  -- 3. Add piece to destination (handle promotion)
  local idx2 = (mv.y2-1)*8 + mv.x2
  local final_pc = pc
  if mv.promote then final_pc = (pc < "a") and "Q" or "q" end
  h = h ~ Z_PIECES[idx2][Z_MAP[final_pc]]
  
  -- 4. Remove captured piece
  if captured and captured ~= "." then
    h = h ~ Z_PIECES[idx2][Z_MAP[captured]]
  end
  
  -- 5. Special: En Passant capture (removes pawn behind/ahead of dest)
  if not captured or captured == "." then
    if string.lower(pc) == "p" and mv.x1 ~= mv.x2 then
       -- It must be an EP capture
       local ep_pawn_y = mv.y1
       local idx_ep = (ep_pawn_y-1)*8 + mv.x2
       local victim = (pc < "a") and "p" or "P"
       h = h ~ Z_PIECES[idx_ep][Z_MAP[victim]]
    end
  end

  -- 6. Special: Castling (moves the rook too)
  if mv.castle then
     local rx1, ry, rx2
     if mv.x2 == 7 then rx1=8 rx2=6 else rx1=1 rx2=4 end
     ry = mv.y1
     local rook = (pc < "a") and "R" or "r"
     h = h ~ Z_PIECES[(ry-1)*8 + rx1][Z_MAP[rook]]
     h = h ~ Z_PIECES[(ry-1)*8 + rx2][Z_MAP[rook]]
  end

  -- 7. EP Rights
  if old_ep then h = h ~ Z_EP[old_ep.x] end
  if new_ep then h = h ~ Z_EP[new_ep.x] end
  
  -- 8. Castling Rights (easiest to just XOR out old and XOR in new)
  if old_cast.wK ~= new_cast.wK then h = h ~ Z_CASTLING[1] end
  if old_cast.wQ ~= new_cast.wQ then h = h ~ Z_CASTLING[2] end
  if old_cast.bK ~= new_cast.bK then h = h ~ Z_CASTLING[3] end
  if old_cast.bQ ~= new_cast.bQ then h = h ~ Z_CASTLING[4] end
  
  return h
end

-- Initialize tables immediately at load time
zobrist_init()
