-- =============================================================
-- game/ai/move_gen.lua
-- Logica di generazione delle mosse per l'AI
-- =============================================================

-- Direzioni di movimento dei pezzi (Globali per il modulo AI)
AI_KN_DIRS = {{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}
AI_K_DIRS  = {{-1,-1},{-1,0},{-1,1},{0,-1},{0,1},{1,-1},{1,0},{1,1}}
AI_R_DIRS  = {{-1,0},{1,0},{0,-1},{0,1}}
AI_B_DIRS  = {{-1,-1},{-1,1},{1,-1},{1,1}}
AI_Q_DIRS  = {{-1,-1},{-1,1},{1,-1},{1,1},{-1,0},{1,0},{0,-1},{0,1}}

-- QuickSort per mosse
function ai_sort_moves(arr, key)
  local function ins_sort(min, max)
    for i = min + 1, max do
      for j = i, min + 1, -1 do
        local item, other = arr[j], arr[j - 1]
        if other[key] <= item[key] then break end
        arr[j], arr[j - 1] = other, item
      end
    end
  end

  local function q_sort(min, max)
    if min >= max then return end
    local pivot
    local pivot_i = flr((max + min) / 2)
    pivot = arr[pivot_i][key]
    
    local first = arr[min][key]
    local last = arr[max][key]
    if first > pivot then
      arr[min], arr[pivot_i] = arr[pivot_i], arr[min]
      first, pivot = pivot, first
    end
    if pivot > last then
      arr[pivot_i], arr[max] = arr[max], arr[pivot_i]
      pivot = last
    end
    if first > pivot then
      arr[min], arr[pivot_i] = arr[pivot_i], arr[min]
      pivot = first
    end
    
    if max - min < 3 then return end
    local low, high = min + 1, max - 1
    while true do
      while low < high and arr[low][key] < pivot do low += 1 end
      while low < high and arr[high][key] > pivot do high -= 1 end
      if low >= high then break end
      arr[low], arr[high] = arr[high], arr[low]
      low += 1
      high -= 1
    end
    local algo = high - min < 8 and ins_sort or q_sort
    algo(min, high)
    algo = max - low < 8 and ins_sort or q_sort
    algo(low, max)
  end

  local algo = #arr <= 8 and ins_sort or q_sort
  algo(1, #arr)
  return arr
end

-- Controlla velocemente (senza clone) se la mossa lascia il re in sicurezza
function is_safe_fast(sx, sy, tx, ty, pc, b, ep, color)
  local captured = b[ty][tx]
  b[ty][tx] = pc
  b[sy][sx] = "."
  local is_ep = false
  local cap_p_y = 0
  local cap_p_pc = "."

  if ep and string.lower(pc) == "p" and tx == ep.x and ty == ep.y and captured == "." then
    is_ep = true
    cap_p_y = ty - (is_white(pc) and 1 or -1)
    cap_p_pc = b[cap_p_y][tx]
    b[cap_p_y][tx] = "."
  end

  local safe = not is_in_check(color, b)

  -- undo move
  b[sy][sx] = pc
  b[ty][tx] = captured
  if is_ep then
    b[cap_p_y][tx] = cap_p_pc
  end
  return safe
end

function ai_add_if_safe(moves, sx, sy, tx, ty, pc, b, ep, color, only_captures)
  local target_pc = b[ty][tx]
  local is_capture = target_pc ~= "."
  local is_ep_cap = ep and string.lower(pc) == "p" and tx == ep.x and ty == ep.y
  
  if only_captures and not (is_capture or is_ep_cap) then return end
  
  if is_safe_fast(sx, sy, tx, ty, pc, b, ep, color) then
    local val = is_capture and piece_val(target_pc) or 0
    moves[#moves+1] = {x1=sx, y1=sy, x2=tx, y2=ty, cap_score= -val}
  end
end

function ai_gen_sliding(moves, sx, sy, pc, color, b, ep, only_captures, dirs)
  for i = 1, #dirs do
    local dx, dy = dirs[i][1], dirs[i][2]
    local tx, ty = sx + dx, sy + dy
    while tx >= 1 and tx <= 8 and ty >= 1 and ty <= 8 do
      local target_pc = b[ty][tx]
      if target_pc == "." then
        if not only_captures then ai_add_if_safe(moves, sx, sy, tx, ty, pc, b, ep, color, false) end
      else
        if is_white(target_pc) ~= (color == "w") then
          ai_add_if_safe(moves, sx, sy, tx, ty, pc, b, ep, color, true)
        end
        break
      end
      tx = tx + dx
      ty = ty + dy
    end
  end
end

function ai_gen_leaping(moves, sx, sy, pc, color, b, ep, only_captures, dirs)
  for i = 1, #dirs do
    local tx, ty = sx + dirs[i][1], sy + dirs[i][2]
    if tx >= 1 and tx <= 8 and ty >= 1 and ty <= 8 then
      local target_pc = b[ty][tx]
      if target_pc == "." then
        if not only_captures then ai_add_if_safe(moves, sx, sy, tx, ty, pc, b, ep, color, false) end
      elseif is_white(target_pc) ~= (color == "w") then
        ai_add_if_safe(moves, sx, sy, tx, ty, pc, b, ep, color, true)
      end
    end
  end
end

-- Genera tutte le mosse legali per un dato colore
function get_all_moves(color, b, ep, only_captures, rights)
  local moves = {}
  for sy = 1, 8 do
    for sx = 1, 8 do
      if check_yield then check_yield() end
      local pc = b[sy][sx]
      if pc ~= "." and (is_white(pc) and "w" or "b") == color then
        local p = string.lower(pc)
        
        if p == "p" then
          local dir = (color == "w") and 1 or -1
          local start_rank = (color == "w") and 2 or 7
          if not only_captures then
            local ty = sy + dir
            if ty >= 1 and ty <= 8 and b[ty][sx] == "." then
              ai_add_if_safe(moves, sx, sy, sx, ty, pc, b, ep, color, false)
              if sy == start_rank then
                local ty2 = sy + dir * 2
                if ty2 >= 1 and ty2 <= 8 and b[ty2][sx] == "." then
                  ai_add_if_safe(moves, sx, sy, sx, ty2, pc, b, ep, color, false)
                end
              end
            end
          end
          local d_xs = {-1, 1}
          for k = 1, 2 do
            local dx = d_xs[k]
            local tx, ty = sx + dx, sy + dir
            if tx >= 1 and tx <= 8 and ty >= 1 and ty <= 8 then
              local target_pc = b[ty][tx]
              if target_pc ~= "." and is_white(target_pc) ~= (color == "w") then
                ai_add_if_safe(moves, sx, sy, tx, ty, pc, b, ep, color, true)
              elseif ep and tx == ep.x and ty == ep.y then
                ai_add_if_safe(moves, sx, sy, tx, ty, pc, b, ep, color, true)
              end
            end
          end
          
        elseif p == "n" then
          ai_gen_leaping(moves, sx, sy, pc, color, b, ep, only_captures, AI_KN_DIRS)
        elseif p == "b" then
          ai_gen_sliding(moves, sx, sy, pc, color, b, ep, only_captures, AI_B_DIRS)
        elseif p == "r" then
          ai_gen_sliding(moves, sx, sy, pc, color, b, ep, only_captures, AI_R_DIRS)
        elseif p == "q" then
          ai_gen_sliding(moves, sx, sy, pc, color, b, ep, only_captures, AI_Q_DIRS)
        elseif p == "k" then
          ai_gen_leaping(moves, sx, sy, pc, color, b, ep, only_captures, AI_K_DIRS)
          if p == "k" and not only_captures then
            local ky = (color == "w") and 1 or 8
            if can_castle("K", color, b, rights) then
              moves[#moves+1] = {x1=5, y1=ky, x2=7, y2=ky, castle="K", cap_score=0}
            end
            if can_castle("Q", color, b, rights) then
              moves[#moves+1] = {x1=5, y1=ky, x2=3, y2=ky, castle="Q", cap_score=0}
            end
          end
        end
      end
    end
  end

  if #moves > 1 then ai_sort_moves(moves, "cap_score") end
  return moves
end
