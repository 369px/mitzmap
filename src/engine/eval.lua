-- =============================================================
-- game/ai/eval.lua
-- AI board evaluation logic
-- =============================================================

-- Evaluate the board for the indicated color (material + PST)
-- Optimized to minimize lookups and function calls
function ai_eval_board(b, p_color)
  local score = 0
  local pv = PIECE_VAL
  local pst = PST
  
  local wkX, wkY, bkX, bkY
  local total_material = 0
  
  for y = 1, 8 do
    local row = b[y]
    for x = 1, 8 do
      local pc = row[x]
      if pc ~= "." then
        local v = pv[pc] + pst[pc][y][x]
        
        -- Track kings for endgame mop-up
        if pc == "K" then wkX, wkY = x, y 
        elseif pc == "k" then bkX, bkY = x, y 
        else total_material = total_material + pv[pc] end

        if pc < "a" then 
          score = score + v 
        else 
          score = score - v 
        end
      end
    end
  end
  
  -- Mop-up evaluation for endgames
  -- If we have more material, push enemy king to edge and bring our king closer
  local is_endgame = total_material < 1500 -- queens are 900 each
  if is_endgame and math.abs(score) > 200 then
    local mopup = 0
    if score > 0 then -- White winning
      -- 1. Push Black king to edge
      local b_dist_center = math.max(math.abs(bkX - 3.5), math.abs(bkY - 3.5))
      mopup = mopup + b_dist_center * 10
      -- 2. Bring White king closer to Black king
      local k_dist = math.abs(wkX - bkX) + math.abs(wkY - bkY)
      mopup = mopup + (14 - k_dist) * 4
    else -- Black winning
      -- 1. Push White king to edge
      local w_dist_center = math.max(math.abs(wkX - 3.5), math.abs(wkY - 3.5))
      mopup = mopup - w_dist_center * 10
      -- 2. Bring Black king closer to White king
      local k_dist = math.abs(wkX - bkX) + math.abs(wkY - bkY)
      mopup = mopup - (14 - k_dist) * 4
    end
    score = score + mopup
  end

  return (p_color == "w") and score or -score
end
