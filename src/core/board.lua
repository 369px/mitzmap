-- =============================================================
-- game/board.lua
-- Data structure of the board: creation, setup, clone, status.
-- No validation logic (see rules.lua).
-- No rendering (see ui/board_renderer.lua).
-- =============================================================

-- -------------------------------------------------------------------------
-- Shared layout constants
-- -------------------------------------------------------------------------

SCREEN_W, SCREEN_H = 480, 270
TILE     = 32
BOARD_PX = TILE * 8

function board_origin()
  -- Centered board at 480x270 -> (112, 7)
  return (SCREEN_W - BOARD_PX) // 2, (SCREEN_H - BOARD_PX) // 2
end

-- Pixel rectangle of a square (x,y in board coordinates 1..8)
-- y=1 = bottom row; on screen row 8 is at the top
function cell_rect(x, y)
  local x0, y0 = board_origin()
  local sx, sy
  if not board_flipped then
    sx = x0 + (x - 1) * TILE
    sy = y0 + (8 - y) * TILE
  else
    sx = x0 + (8 - x) * TILE
    sy = y0 + (y - 1) * TILE
  end
  return sx, sy, sx + TILE - 1, sy + TILE - 1
end

-- Square colors
COL_LIGHT    = 22
COL_DARK     = 5
COL_SELECTED = 10
COL_CURSOR   = 9
COL_TEXT     = 0
COL_LEGAL    = 10
COL_CAPTURE  = 8

-- Piece set table
PIECE_STYLES = {
  classic = {
    ["P"]=8, ["R"]=9, ["N"]=10, ["B"]=11, ["Q"]=12, ["K"]=13,
    ["p"]=16,["r"]=17,["n"]=18, ["b"]=19, ["q"]=20, ["k"]=21
  },
  modern = {
    ["P"]=96, ["R"]=97, ["N"]=98, ["B"]=99, ["Q"]=100, ["K"]=101,
    ["p"]=104,["r"]=105,["n"]=106, ["b"]=107, ["q"]=108, ["k"]=109
  },
  pico = {
    ["P"]=64, ["R"]=65, ["N"]=66, ["B"]=67, ["Q"]=68, ["K"]=69,
    ["p"]=72, ["r"]=73, ["n"]=74, ["b"]=75, ["q"]=76, ["k"]=77
  }
}

-- Sprite-id for each piece (will be overwritten by apply_piece_style)
PIECE_SPRITE = {}

function apply_piece_style(style_id)
  local set = PIECE_STYLES[style_id] or PIECE_STYLES.classic
  for k, v in pairs(set) do
    PIECE_SPRITE[k] = v
  end
end

-- Draw order for captured pieces sidebar
DRAW_ORDER_W = {"Q","R","B","N","P"}
DRAW_ORDER_B = {"q","r","b","n","p"}

-- -------------------------------------------------------------------------
-- Piece utilities
-- -------------------------------------------------------------------------

function is_white(pc) return pc ~= "." and pc == string.upper(pc) end

function xy_to_alg(x, y)
  return string.sub("abcdefgh", x, x) .. tostring(y)
end

function alg_to_xy(s)
  if type(s) ~= "string" or #s < 2 then return nil end
  local fmap = {a=1,b=2,c=3,d=4,e=5,f=6,g=7,h=8}
  local f = fmap[string.sub(s, 1, 1)]
  local r = tonumber(string.sub(s, 2))
  if f and r and r >= 1 and r <= 8 then return {x=f, y=r} end
  return nil
end

-- -------------------------------------------------------------------------
-- Board creation and setup
-- -------------------------------------------------------------------------

function new_empty_board()
  local b = {}
  for y = 1, 8 do
    b[y] = {}
    for x = 1, 8 do b[y][x] = "." end
  end
  return b
end

function setup_initial_position()
  board = new_empty_board()
  local back_b = {"r","n","b","q","k","b","n","r"}
  local back_w = {"R","N","B","Q","K","B","N","R"}
  for x = 1, 8 do
    board[8][x] = back_b[x]; board[7][x] = "p"
    board[1][x] = back_w[x]; board[2][x] = "P"
  end
  castling = {wK=true, wQ=true, bK=true, bQ=true}
end

-- -------------------------------------------------------------------------
-- Clone and state snapshot (time travel)
-- -------------------------------------------------------------------------

function clone_board(b)
  local c = {}
  for y = 1, 8 do
    c[y] = {}
    for x = 1, 8 do c[y][x] = b[y][x] end
  end
  return c
end

function clone_state()
  local s = {}
  s.board    = clone_board(board)
  s.turn     = game_state.turn
  s.mode     = game_state.mode
  s.msg      = game_state.msg
  s.result   = game_state.result
  s.ep_target = ep_target and {x=ep_target.x, y=ep_target.y} or nil
  s.castling = {wK=castling.wK, wQ=castling.wQ, bK=castling.bK, bQ=castling.bQ}
  s.white_turn = white_turn
  s.halfmove_clock = halfmove_clock
  
  -- Include hash for repetition detection
  if zobrist_hash_board then
    s.hash = zobrist_hash_board(board, game_state.turn, castling, ep_target)
  else
    s.hash = hash_state(board, game_state.turn, castling, ep_target)
  end
  
  return s
end

-- Generate string hash for triple repetition detection
function hash_state(b, turn, cast, ep)
  local h = ""
  for y=1,8 do for x=1,8 do h = h .. b[y][x] end end
  h = h .. turn
  h = h .. (cast.wK and "1" or "0") .. (cast.wQ and "1" or "0")
  h = h .. (cast.bK and "1" or "0") .. (cast.bQ and "1" or "0")
  if ep then h = h .. ep.x .. ep.y else h = h .. "-" end
  return h
end

function apply_state(s)
  board            = clone_board(s.board)
  game_state.turn  = s.turn
  game_state.mode  = (s.mode == "gameover") and "select_src" or s.mode
  game_state.msg   = s.msg
  game_state.result = s.result
  ep_target        = s.ep_target and {x=s.ep_target.x, y=s.ep_target.y} or nil
  castling         = {wK=s.castling.wK, wQ=s.castling.wQ, bK=s.castling.bK, bQ=s.castling.bQ}
  white_turn       = s.white_turn
  halfmove_clock   = s.halfmove_clock or 0
end

