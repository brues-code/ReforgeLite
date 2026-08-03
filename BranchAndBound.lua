---@type string, AddonTable
local addonName, addonTable = ...
local REFORGE_COEFF = addonTable.REFORGE_COEFF

local ReforgeLite = addonTable.ReforgeLite
local print = addonTable.print
local ITEM_STATS, ITEM_STAT_COUNT = addonTable.itemStats, addonTable.itemStatCount

local huge = math.huge

local dpChoices

--- Determines which stat cap should be prioritized during item ordering.
--- Calculates current distance from target for each cap and prioritizes the one furthest from its goal.
--- @param data table The reforge data structure containing caps configuration
--- @return number Cap index (1 or 2) indicating which cap has priority
function ReforgeLite:CalculatePriorityCap(data)
  -- Calculate total stats for each cap across all items
  local capDistances = {}
  local baseline = self:GetBaselineStats(data)
  for i = 1, 2 do
    local cap = data.caps[i]
    if cap.stat > 0 then
      -- Character base plus every item's un-reforged stats, in amplified space
      local capTotal = baseline[cap.stat] or 0

      -- Calculate target value (use first constraint point for simplicity)
      local capTarget = 0
      if cap.points and cap.points[1] then
        capTarget = cap.points[1].value or 0
      end

      -- Calculate distance from target
      capDistances[i] = abs(capTotal - capTarget)
    else
      capDistances[i] = -1 -- No cap, lowest priority
    end
  end

  -- Determine which cap to prioritize (furthest from target)
  local priorityCap = 1
  if capDistances[2] > capDistances[1] then
    priorityCap = 2
  end

  return priorityCap
end

--- Orders items for optimal branch-and-bound processing to maximize early pruning.
--- Sorts items by primary cap contribution DESC, secondary cap contribution DESC, then total reforge potential DESC.
--- @param data table The reforge data structure containing item stats and caps
--- @param priorityCap number Which cap to prioritize (from CalculatePriorityCap)
--- @return table Array of slot numbers in processing order [slot5, slot12, slot3, ...]
function ReforgeLite:GetItemSortingOrder(data, priorityCap)
  local itemOrder = {}

  for slot = 1, #data.method.items do
    local itemStats = data.method.items[slot].stats

    -- Primary cap contribution (the cap furthest from target)
    local primaryCapContrib = 0
    if data.caps[priorityCap].stat > 0 then
      primaryCapContrib = itemStats[data.caps[priorityCap].stat] or 0
    end

    -- Secondary cap contribution (the other cap)
    local secondaryCapContrib = 0
    local otherCap = priorityCap == 1 and 2 or 1
    if data.caps[otherCap].stat > 0 then
      secondaryCapContrib = itemStats[data.caps[otherCap].stat] or 0
    end

    -- Calculate sum of all reforgeable stats
    local reforgePotential = 0
    for stat = 1, ITEM_STAT_COUNT do
      reforgePotential = reforgePotential + (itemStats[stat] or 0)
    end

    tinsert(itemOrder, {
      slot = slot,
      primaryCapContrib = primaryCapContrib,
      secondaryCapContrib = secondaryCapContrib,
      reforgePotential = reforgePotential
    })
  end

  -- Sort by primary cap DESC, secondary cap DESC, then reforge potential DESC
  sort(itemOrder, function(a, b)
    if a.primaryCapContrib ~= b.primaryCapContrib then
      return a.primaryCapContrib > b.primaryCapContrib
    elseif a.secondaryCapContrib ~= b.secondaryCapContrib then
      return a.secondaryCapContrib > b.secondaryCapContrib
    else
      return a.reforgePotential > b.reforgePotential
    end
  end)

  -- Return slot order array: [slot14, slot3, slot7, ...]
  local sortedSlots = {}
  for i, entry in ipairs(itemOrder) do
    sortedSlots[i] = entry.slot
  end

  return sortedSlots
end

function ReforgeLite:CalculateMethodScore(method)
  if not method or not method.stats or not self.pdb.weights then return 0 end

  local stats = method.stats
  local score = 0
  local maxIndex = min(#stats, #self.pdb.weights)

  -- Identify which stats have caps to avoid double-counting
  local cappedStats = {}
  if self.pdb.caps then
    if self.pdb.caps[1] and self.pdb.caps[1].stat > 0 then
      cappedStats[self.pdb.caps[1].stat] = true
    end
    if self.pdb.caps[2] and self.pdb.caps[2].stat > 0 then
      cappedStats[self.pdb.caps[2].stat] = true
    end
  end

  -- Score non-capped stats with base weights
  for i = 1, maxIndex do
    if not cappedStats[i] then
      score = score + (self.pdb.weights[i] or 0) * (stats[i] or 0)
    end
  end

  -- Score capped stats using GetCapScore
  for capIndex = 1, 2 do
    local cap = self.pdb.caps and self.pdb.caps[capIndex]
    if cap and cap.stat > 0 and cap.stat <= #stats then
      local statValue = stats[cap.stat]
      if statValue then
        score = score + self:GetCapScore(cap, statValue)
      end
    end
  end

  return score
end

function ReforgeLite:CheckConstraintsSatisfied(method)
  if not method or not method.stats or not self.pdb.caps then return false end

  local stats = method.stats
  for capIndex = 1, 2 do
    local cap = self.pdb.caps[capIndex]
    if cap and cap.stat > 0 and cap.stat <= #stats then
      local statValue = stats[cap.stat]
      if statValue and not self:CapAllows(cap, statValue) then
        return false
      end
    end
  end

  return true
end

------------------------------------- BRANCH AND BOUND ------------------------------

--[[
BRANCH AND BOUND REFORGE OPTIMIZATION
Overview:
The branch-and-bound algorithm provides an alternative to dynamic programming for solving
the reforge optimization problem. While dynamic programming explores all possible stat
combinations systematically, branch-and-bound uses intelligent search tree pruning to
avoid exploring provably suboptimal solutions.
Algorithm Characteristics:
- Best Case: O(n) when aggressive pruning eliminates most branches early
- Average Case: O(n * b^d) where n=items, b=branching factor, d=depth
- Worst Case: O(b^n) - exponential when pruning is ineffective
- Memory: O(n) for the current path + O(n²) for precomputed bounds
Key Advantages:
1. Can find optimal solutions much faster than DP when pruning is effective
2. Memory usage scales linearly with problem size
Key Disadvantages:
1. Performance highly dependent on problem characteristics
2. Worst-case exponential runtime when bounds are loose
3. More complex implementation and debugging
Implementation Details:
The algorithm works by:
1. Ordering items by their potential impact on constrained stats
2. Enumerating the full set of reforge options per item (same space as the DP)
3. Precomputing suffix bounds for aggressive pruning
4. Exploring reforge combinations depth-first with constraint/bound pruning
5. Maintaining the best feasible solution found so far
Pruning Strategies:
- Constraint Propagation: Eliminates branches that cannot satisfy stat caps
- Upper Bound Pruning: Uses very generous upper score bounds to eliminate suboptimal branches
When to Use:
Branch-and-bound typically outperforms DP when:
- Stat weights have significant differences (enables tighter bounds)
- Items have large amounts of capped stats (enables early good solutions)
- There are clear "best" reforge choices (reduces branching factor)
It may underperform DP when:
- Many stats have similar weights (loose bounds, poor pruning)
- Items have small stat amounts (weak early solutions)
- Configuration creates uniform reforge value distribution
--]]

----------------------------------------------------------------------------------------------

--- Orders reforge options to surface high-impact moves first (better early pruning):
--- priority-cap reforges, then secondary-cap, then higher source weight, then score.
--- @param options table Reforge options to sort in place
--- @param data table The reforge data structure
--- @param priorityCap number Which cap to prioritize
function ReforgeLite:SortReforgeOptions(options, data, priorityCap)
  local otherCap = priorityCap == 1 and 2 or 1
  sort(options, function(a, b)
    local aPri = (a.src == data.caps[priorityCap].stat) or (a.dst == data.caps[priorityCap].stat)
    local bPri = (b.src == data.caps[priorityCap].stat) or (b.dst == data.caps[priorityCap].stat)
    if aPri ~= bPri then return aPri end

    local aSec = (a.src == data.caps[otherCap].stat) or (a.dst == data.caps[otherCap].stat)
    local bSec = (b.src == data.caps[otherCap].stat) or (b.dst == data.caps[otherCap].stat)
    if aSec ~= bSec then return aSec end

    local aw = (a.src and data.weights[a.src]) or 0
    local bw = (b.src and data.weights[b.src]) or 0
    if aw ~= bw then return aw > bw end

    return (a.score or 0) > (b.score or 0)
  end)
end

--- Enumerates the COMPLETE set of reforge options for an item (every src->dst, deduped by
--- distinct cap effect keeping the highest score), so B&B searches the same space as the DP
--- and can reach the true optimum. Nothing is pruned up front; the suffix-bound search
--- handles tractability.
--- @param data table The reforge data structure
--- @param slot number The item slot index
--- @param priorityCap number Which cap to prioritize (for move ordering)
--- @return table Sorted array of reforge options
function ReforgeLite:GetFullReforgeOptions(data, slot, priorityCap)
  local item = data.method.items[slot]
  if self:IsItemLocked(slot) then
    local src, dst = nil, nil
    if self.itemData[slot].itemInfo.reforge then
      src, dst = unpack(self.reforgeTable[self.itemData[slot].itemInfo.reforge])
    end
    return { self:MakeReforgeOption(item, data, src, dst) }
  end

  -- Key by cap effect "d1:d2"; same effect -> the higher-scoring option dominates.
  local byEffect = { ["0:0"] = self:MakeReforgeOption(item, data) }
  for src = 1, ITEM_STAT_COUNT do
    if item.stats[src] > 0 then
      for dst = 1, ITEM_STAT_COUNT do
        if item.stats[dst] == 0 then
          local o = self:MakeReforgeOption(item, data, src, dst)
          local key = o.d1 .. ":" .. o.d2
          if not byEffect[key] or byEffect[key].score < o.score then
            byEffect[key] = o
          end
        end
      end
    end
  end

  local options = {}
  for _, o in pairs(byEffect) do
    tinsert(options, o)
  end
  self:SortReforgeOptions(options, data, priorityCap)
  return options
end

--- Precomputes tight upper bounds for constraint and score pruning.
--- Works backwards from position 16 to 1, accumulating best-case contributions for aggressive pruning.
--- @param data table The reforge data structure containing caps and weights
--- @param allItemOptions table Pre-computed reforge options for all items [slot] = {options}
--- @param sortedSlots table Array of slot numbers in processing order
--- @return table Array of bound objects with cap1/cap2 min/max and maxScore for each suffix position
function ReforgeLite:PrecomputeSuffixBounds(data, allItemOptions, sortedSlots)
  local suffixBounds = {}

  -- Steepest slope of GetCapScore for a cap (its stat weight, or a steeper above-cap
  -- "after" slope if configured). Used as a linear over-estimate of a cap stat's marginal
  -- value for the joint per-item score bound below.
  local function capSlope(cap)
    if not cap or cap.stat <= 0 then return 0 end
    local w = self.pdb.weights[cap.stat] or 0
    for _, p in ipairs(cap.points or {}) do
      w = max(w, p.after or 0)
    end
    return w
  end
  local w1, w2 = capSlope(data.caps[1]), capSlope(data.caps[2])

  -- Calculate bounds in sorted order (from the last position back to 1)
  local lastPos = #sortedSlots
  for pos = lastPos, 1, -1 do
    suffixBounds[pos] = {
      cap1 = {min = 0, max = 0},
      cap2 = {min = 0, max = 0},
      maxScore = 0,
      bestMarginal = 0,
    }

    -- Use pre-computed reforge options for this item
    local slot = sortedSlots[pos]
    local options = allItemOptions[slot]

    -- Find min/max contributions for this item
    -- For constraint pruning: track true min/max for each cap independently
    local minCap1, maxCap1 = huge, -huge
    local minCap2, maxCap2 = huge, -huge

    -- For score pruning: use max score contribution (non-cap stats only)
    local maxScore = -huge

    -- For the joint bound: the best single reforge this item can contribute, valuing its
    -- cap gains linearly (only positive gains, since w*d under-estimates a negative delta's
    -- cap loss). Floored at 0 because leaving the item unreforged is always available.
    local bestMarginal = 0

    for _, opt in ipairs(options) do
      local cap1Contrib = opt.d1 or 0
      local cap2Contrib = opt.d2 or 0
      local scoreContrib = opt.score or 0

      -- Track true min/max for constraint pruning
      minCap1 = min(minCap1, cap1Contrib)
      maxCap1 = max(maxCap1, cap1Contrib)
      minCap2 = min(minCap2, cap2Contrib)
      maxCap2 = max(maxCap2, cap2Contrib)

      -- Use only non-cap score contribution for frankenitem bound
      maxScore = max(maxScore, scoreContrib)

      local capGain = (cap1Contrib > 0 and w1 * cap1Contrib or 0) + (cap2Contrib > 0 and w2 * cap2Contrib or 0)
      bestMarginal = max(bestMarginal, scoreContrib + capGain)
    end

    -- Ensure we have valid bounds even if no options
    if minCap1 == huge then minCap1 = 0 end
    if maxCap1 == -huge then maxCap1 = 0 end
    if minCap2 == huge then minCap2 = 0 end
    if maxCap2 == -huge then maxCap2 = 0 end
    if maxScore == -huge then maxScore = 0 end

    -- Set bounds for this suffix
    if pos == lastPos then
      -- Base case: just this item
      suffixBounds[pos].cap1.min = minCap1
      suffixBounds[pos].cap1.max = maxCap1
      suffixBounds[pos].cap2.min = minCap2
      suffixBounds[pos].cap2.max = maxCap2
      suffixBounds[pos].maxScore = maxScore
      suffixBounds[pos].bestMarginal = bestMarginal
    else
      -- Cumulative: this item plus suffix
      suffixBounds[pos].cap1.min = minCap1 + suffixBounds[pos + 1].cap1.min
      suffixBounds[pos].cap1.max = maxCap1 + suffixBounds[pos + 1].cap1.max
      suffixBounds[pos].cap2.min = minCap2 + suffixBounds[pos + 1].cap2.min
      suffixBounds[pos].cap2.max = maxCap2 + suffixBounds[pos + 1].cap2.max
      suffixBounds[pos].maxScore = maxScore + suffixBounds[pos + 1].maxScore
      suffixBounds[pos].bestMarginal = bestMarginal + suffixBounds[pos + 1].bestMarginal
    end
  end

  return suffixBounds
end

--- Determines if remaining items can possibly satisfy stat cap constraints.
--- Uses precomputed suffix bounds to check if AtLeast/AtMost/Exactly constraints can be met.
--- @param position number Current search position in the item processing order
--- @param currentStats table Current stat totals accumulated so far
--- @param suffixBounds table Precomputed bounds for remaining positions
--- @param data table The reforge data structure containing cap constraints
--- @return boolean True if constraints can be satisfied, false if impossible
function ReforgeLite:CanSatisfyConstraints(position, currentStats, suffixBounds, data)
  -- If we've processed all items, no more flexibility
  if position > #data.method.items then
    return true
  end

  -- Check each cap
  for capIdx = 1, 2 do
    local cap = data.caps[capIdx]
    if cap and cap.stat > 0 then
      local currentValue = currentStats[cap.stat] or 0

      -- Check each constraint point
      for _, point in ipairs(cap.points or {}) do
        if point.method == addonTable.StatCapMethods.AtLeast then
          -- Need to reach at least this value
          local maxPossible = currentValue
          if capIdx == 1 then
            maxPossible = maxPossible + (suffixBounds[position].cap1.max or 0)
          else
            maxPossible = maxPossible + (suffixBounds[position].cap2.max or 0)
          end
          if maxPossible < point.value then
            return false -- Can't reach minimum
          end
        elseif point.method == addonTable.StatCapMethods.AtMost then
          -- Need to stay below this value
          local minPossible = currentValue
          if capIdx == 1 then
            minPossible = minPossible + (suffixBounds[position].cap1.min or 0)
          else
            minPossible = minPossible + (suffixBounds[position].cap2.min or 0)
          end
          if minPossible > point.value then
            return false -- Will exceed maximum
          end
        elseif point.method == addonTable.StatCapMethods.Exactly then
          -- Need to hit exactly this value
          local minPossible, maxPossible = currentValue, currentValue
          if capIdx == 1 then
            minPossible = minPossible + (suffixBounds[position].cap1.min or 0)
            maxPossible = maxPossible + (suffixBounds[position].cap1.max or 0)
          else
            minPossible = minPossible + (suffixBounds[position].cap2.min or 0)
            maxPossible = maxPossible + (suffixBounds[position].cap2.max or 0)
          end
          if maxPossible < point.value or minPossible > point.value then
            return false -- Can't hit exact value
          end
        end
      end
    end
  end

  return true
end

-- Branch and Bound state tracking
local bbBestSolution = nil
-- When true (best-effort pass for an infeasible cap config), constraint pruning is skipped so
-- the search still reaches complete solutions and keeps the closest constraint-failing one.
local bbIgnoreConstraints = false
local bbNodesExplored = 0
local bbBranchesPruned = 0
local bbConstraintPrunes = 0
local bbScorePrunes = 0
local bbFoundExactDPPath = false

--- Core recursive search function that explores reforge combinations with pruning.
--- Uses depth-first search with constraint propagation and upper bound pruning to find optimal solutions.
--- @param position number Current item position in the search (1-16)
--- @param currentStats table Running stat totals accumulated so far
--- @param currentPath table Current reforge choices made [position] = {src, dst}
--- @param data table The reforge data structure containing all problem parameters
--- @param suffixBounds table Precomputed bounds for pruning decisions
--- @param allItemOptions table Pre-computed reforge options for all items
--- @param sortedSlots table Array of slot numbers in processing order
--- @return nil Updates global bbBestSolution with the best solution found
function ReforgeLite:BranchAndBoundSearch(position, currentStats, currentPath, data, suffixBounds, allItemOptions, sortedSlots)
  self:RunYieldCheck() -- Cheap operation
  bbNodesExplored = bbNodesExplored + 1

  -- Base case: all items processed
  if position > #sortedSlots then
    -- Check if this solution is better than current best
    local constraintsMet = true
    for capIdx = 1, 2 do
      local cap = data.caps[capIdx]
      if cap and cap.stat > 0 then
        local statValue = currentStats[cap.stat] or 0
        if not self:CapAllows(cap, statValue) then
          constraintsMet = false
          break
        end
      end
    end

    -- Calculate the actual total score for this complete solution
    -- We need to create a temporary method object to use CalculateMethodScore
    local tempMethod = { stats = currentStats }
    local actualTotalScore = self:CalculateMethodScore(tempMethod)

    -- Check if this is the exact DP path
    local isExactDPPath = true
    if dpChoices then
      for pos = 1, position - 1 do
        local slot = sortedSlots[pos]
        if dpChoices[slot] then
          local pathChoice = currentPath[pos]
          if not pathChoice or pathChoice.src ~= dpChoices[slot].src or pathChoice.dst ~= dpChoices[slot].dst then
            isExactDPPath = false
            break
          end
        end
      end
    else
      isExactDPPath = false
    end

    if isExactDPPath then
      bbFoundExactDPPath = true
      if self.db.debug then
        print(("B&B: Evaluating exact DP path - B&B thinks total score is %.1f"):format(actualTotalScore))
      end
    end

    -- Update best if this is better
    if constraintsMet or not bbBestSolution or not bbBestSolution.constraintsMet then
      if not bbBestSolution or 
         (constraintsMet and not bbBestSolution.constraintsMet) or
         (constraintsMet == bbBestSolution.constraintsMet and actualTotalScore > bbBestSolution.score) then
        local previousBestScore = bbBestSolution and bbBestSolution.score or 0
        bbBestSolution = {
          score = actualTotalScore,  -- Use the actual total score
          path = CopyTable(currentPath),
          stats = CopyTable(currentStats),
          constraintsMet = constraintsMet
        }
        if self.db.debug then
          -- Show path summary for the solution we just found
          local pathStr = ""
          for pos = 1, position - 1 do
            local slot = sortedSlots[pos]
            if currentPath[pos] and currentPath[pos].src then
              pathStr = pathStr .. (" pos%d(slot%d):%d->%d"):format(pos, slot, currentPath[pos].src, currentPath[pos].dst)
            end
          end
          local pathNote = isExactDPPath and " ← EXACT DP PATH!" or ""
          local scoreDelta = actualTotalScore - previousBestScore
          print(("B&B: Found better solution, score: %.1f (delta: %.1f), constraints: %s, path:%s%s"):format(actualTotalScore, scoreDelta, constraintsMet and "Pass" or "Fail", pathStr, pathNote))
        end
      end
    end
    return
  end

  self:RunYieldCheck() -- Expensive operation coming

  -- Use pre-computed reforge options for current item
  local slot = sortedSlots[position]
  local options = allItemOptions[slot]

  for _, opt in ipairs(options) do
    -- Debug: Check if we're considering the DP choice for this item
    local isDPChoice = false
    if self.db.debug and dpChoices and dpChoices[slot] then
      local dpChoice = dpChoices[slot]
      isDPChoice = (opt.src == dpChoice.src and opt.dst == dpChoice.dst)
    end

    -- Apply the reforge to currentStats IN PLACE (undone at the end of this iteration). This
    -- avoids copying the whole stat table for every branch -- the dominant per-node cost.
    local src, dst = opt.src, opt.dst
    local srcAmount, dstAmount = 0, 0
    if src and dst then
      local itemStats = data.method.items[slot].stats
      local amountRaw = floor(itemStats[src] * REFORGE_COEFF)
      srcAmount = Round(amountRaw * (data.mult[src] or 1))
      dstAmount = Round(amountRaw * (data.mult[dst] or 1))
      currentStats[src] = (currentStats[src] or 0) - srcAmount
      currentStats[dst] = (currentStats[dst] or 0) + dstAmount
      if data.conv[src] then
        for to, factor in pairs(data.conv[src]) do
          currentStats[to] = (currentStats[to] or 0) - Round(srcAmount * factor)
        end
      end
      if data.conv[dst] then
        for to, factor in pairs(data.conv[dst]) do
          currentStats[to] = (currentStats[to] or 0) + Round(dstAmount * factor)
        end
      end
    end

    -- Check if this branch can be pruned
    local shouldPrune = false
    local pruneReason = ""

    -- Constraint propagation check first (skipped in the best-effort pass, where no feasible
    -- solution exists and we instead want the closest constraint-failing one).
    if not bbIgnoreConstraints and not self:CanSatisfyConstraints(position + 1, currentStats, suffixBounds, data) then
      shouldPrune = true
      pruneReason = "constraint violation"
      bbConstraintPrunes = bbConstraintPrunes + 1
    end

    -- Upper bound pruning. Two valid upper bounds; prune if either rules the branch out.
    local nextBounds = suffixBounds[position + 1]
    if not shouldPrune and bbBestSolution and nextBounds then
      local currentActualScore = self:CalculateMethodScore({ stats = currentStats })

      -- Joint bound: each remaining item credited only its single best reforge (tight when
      -- caps are still unmet -- the case that otherwise explores the whole tree).
      local jointUB = currentActualScore + nextBounds.bestMarginal

      -- Frankenitem bound: independently-maxed score + saturating cap gains (tighter once a
      -- cap is already satisfied, where the joint bound keeps over-crediting cap stats).
      local frankenUB = currentActualScore + nextBounds.maxScore
      if data.caps[1].stat > 0 then
        local projected = (currentStats[data.caps[1].stat] or 0) + (nextBounds.cap1.max or 0)
        frankenUB = frankenUB + self:GetCapScore(data.caps[1], projected) - self:GetCapScore(data.caps[1], currentStats[data.caps[1].stat] or 0)
      end
      if data.caps[2].stat > 0 then
        local projected = (currentStats[data.caps[2].stat] or 0) + (nextBounds.cap2.max or 0)
        frankenUB = frankenUB + self:GetCapScore(data.caps[2], projected) - self:GetCapScore(data.caps[2], currentStats[data.caps[2].stat] or 0)
      end

      local upperBound = min(jointUB, frankenUB)
      if upperBound <= bbBestSolution.score then
        shouldPrune = true
        pruneReason = ("upper bound %.1f <= best %.1f"):format(upperBound, bbBestSolution.score)
        bbScorePrunes = bbScorePrunes + 1
      end
    end

    -- Debug: Log when we prune a DP choice (but only if we're on the DP path so far)
    if self.db.debug and isDPChoice and shouldPrune then
      -- Check if we're actually on the DP path up to this point
      local onDPPath = true
      for prevPos = 1, position - 1 do
        local prevSlot = sortedSlots[prevPos]
        if dpChoices[prevSlot] then
          local prevChoice = currentPath[prevPos]
          if not prevChoice or prevChoice.src ~= dpChoices[prevSlot].src or prevChoice.dst ~= dpChoices[prevSlot].dst then
            onDPPath = false
            break
          end
        end
      end

      if onDPPath then
        local choiceStr = opt.src and ("%d->%d"):format(opt.src, opt.dst) or "none"

        local currentActualScore = self:CalculateMethodScore({ stats = currentStats })
        local suffixMaxScore = suffixBounds[position + 1] and suffixBounds[position + 1].maxScore or 0
        local upperBound = currentActualScore + suffixMaxScore

        if not bbBestSolution then
          print(("B&B: PRUNING DP choice at pos%d(slot%d) (%s) - %s (no incumbent yet)"):format(position, slot, choiceStr, pruneReason))
        elseif upperBound == bbBestSolution.score then
          -- Equal scores - just a brief note
          print(("B&B: Pruning equivalent DP choice at pos%d(slot%d) (%s)"):format(position, slot, choiceStr))
        else
          -- Different scores - show full debug
          print(("B&B: PRUNING DP choice at pos%d(slot%d) (%s) - %s"):format(position, slot, choiceStr, pruneReason))
          if pruneReason:find("upper bound") then
            print(("  Upper bound debug: currentActualScore=%.1f + suffixMaxScore=%.1f = upperBound=%.1f"):format(
              currentActualScore, suffixMaxScore, upperBound))
            print(("  Best solution score: %.1f"):format(bbBestSolution.score))
            print(("  Pruning because: %.1f <= %.1f is %s"):format(upperBound, bbBestSolution.score, upperBound <= bbBestSolution.score and "true" or "false"))
          end
        end
      end
    end

    if not shouldPrune then
      -- Update path
      currentPath[position] = {src = opt.src, dst = opt.dst}

      -- Debug: Check if we're following the DP path
      if self.db.debug and dpChoices and isDPChoice then
        local onDPPath = true
        for prevPos = 1, position do
          local prevSlot = sortedSlots[prevPos]
          if dpChoices[prevSlot] then
            local pathChoice = currentPath[prevPos]
            if not pathChoice or pathChoice.src ~= dpChoices[prevSlot].src or pathChoice.dst ~= dpChoices[prevSlot].dst then
              onDPPath = false
              break
            end
          end
        end
        if onDPPath then
          local pathStr = ""
          for pos = 1, position do
            local debugSlot = sortedSlots[pos]
            if currentPath[pos] and currentPath[pos].src then
              pathStr = pathStr .. (" pos%d(slot%d):%d->%d"):format(pos, debugSlot, currentPath[pos].src, currentPath[pos].dst)
            end
          end
          print(("B&B: Following DP path at pos%d(slot%d), path so far:%s"):format(position, slot, pathStr))
        end
      end

      -- Recursive search
      self:BranchAndBoundSearch(position + 1, currentStats, currentPath, data, suffixBounds, allItemOptions, sortedSlots)

      -- Backtrack
      currentPath[position] = nil
    else
      bbBranchesPruned = bbBranchesPruned + 1
    end

    -- Undo the in-place reforge so the next sibling option starts from a clean state.
    if src and dst then
      currentStats[src] = currentStats[src] + srcAmount
      currentStats[dst] = currentStats[dst] - dstAmount
      if data.conv[src] then
        for to, factor in pairs(data.conv[src]) do
          currentStats[to] = currentStats[to] + Round(srcAmount * factor)
        end
      end
      if data.conv[dst] then
        for to, factor in pairs(data.conv[dst]) do
          currentStats[to] = currentStats[to] - Round(dstAmount * factor)
        end
      end
    end
  end
end

--- Main entry point for branch-and-bound optimization.
--- Orchestrates the complete B&B process: initialization, precomputation, search, and result application.
--- @return nil Updates self.pdb.method with the optimal reforge solution
function ReforgeLite:ComputeReforgeBranchBound()
  if self.db.debug then
    print("B&B: Starting Branch and Bound search")
  end

  -- Initialize data structures
  local data = self:InitReforgeClassic()

  -- Reset B&B state
  bbBestSolution = nil
  bbNodesExplored = 0
  bbBranchesPruned = 0
  bbConstraintPrunes = 0
  bbScorePrunes = 0
  bbFoundExactDPPath = false
  bbIgnoreConstraints = false

  -- Calculate priority cap once at the beginning
  local priorityCap = self:CalculatePriorityCap(data)

  -- Pre-compute the full reforge option set for all items (B&B searches the same space as
  -- the DP so it reaches the true optimum; the suffix bounds keep it tractable).
  local allItemOptions = {}
  for slot = 1, #data.method.items do
    allItemOptions[slot] = self:GetFullReforgeOptions(data, slot, priorityCap)
  end

  -- Get item sorting order using the same priority cap
  local sortedSlots = self:GetItemSortingOrder(data, priorityCap)

  -- Debug: Show item processing order
  if self.db.debug then
    local priorityCapStat = data.caps[priorityCap].stat
    local otherCap = priorityCap == 1 and 2 or 1
    local otherCapStat = data.caps[otherCap].stat
    print(("B&B: Priority cap %d (stat %d), secondary cap %d (stat %d)"):format(
      priorityCap, priorityCapStat, otherCap, otherCapStat))

    local orderStr = "B&B: Item processing order:"
    for pos = 1, #sortedSlots do
      local slot = sortedSlots[pos]
      local itemStats = data.method.items[slot].stats
      local primaryContrib = (priorityCapStat > 0) and (itemStats[priorityCapStat] or 0) or 0
      local secondaryContrib = (otherCapStat > 0) and (itemStats[otherCapStat] or 0) or 0
      local reforgeSum = 0
      for stat = 1, ITEM_STAT_COUNT do
        reforgeSum = reforgeSum + (itemStats[stat] or 0)
      end
      orderStr = orderStr .. (" slot%d(%d/%d/%d)"):format(slot, primaryContrib, secondaryContrib, reforgeSum)
    end
    print(orderStr)
  end

  -- Precompute suffix bounds using pre-computed options and sorted order
  local suffixBounds = self:PrecomputeSuffixBounds(data, allItemOptions, sortedSlots)


  -- Initialize starting stats (character + item base stats, amplified to match option deltas)
  local initialStats = self:GetBaselineStats(data)

  -- Run branch and bound search
  local currentPath = {}
  self:BranchAndBoundSearch(1, initialStats, currentPath, data, suffixBounds, allItemOptions, sortedSlots)

  if self.db.debug then
    print(("B&B: Completed - nodes explored: %d, branches pruned: %d (constraints: %d, score: %d)"):format(bbNodesExplored, bbBranchesPruned, bbConstraintPrunes, bbScorePrunes))
    if not bbFoundExactDPPath and dpChoices then
      print("B&B: WARNING - Never evaluated the exact DP path!")
    end
  end

  -- No feasible solution means the caps are unreachable. Re-run without constraint pruning so the
  -- search reaches complete solutions and keeps the highest-scoring (closest) one as best-effort,
  -- rather than dropping to the much slower DP.
  if not bbBestSolution then
    if self.db.debug then
      print("B&B: No feasible solution; running best-effort pass (constraints relaxed)")
    end
    bbIgnoreConstraints = true
    bbNodesExplored, bbBranchesPruned, bbConstraintPrunes, bbScorePrunes = 0, 0, 0, 0
    self:BranchAndBoundSearch(1, initialStats, {}, data, suffixBounds, allItemOptions, sortedSlots)
    bbIgnoreConstraints = false
    if self.db.debug then
      print(("B&B: Best-effort complete - nodes explored: %d, branches pruned: %d (score: %d)"):format(bbNodesExplored, bbBranchesPruned, bbScorePrunes))
    end
  end

  -- Apply best solution if found
  if bbBestSolution and bbBestSolution.path then
    -- Map position-based solution back to slot-based structure
    for position = 1, #sortedSlots do
      local slot = sortedSlots[position]
      local reforge = bbBestSolution.path[position]
      if reforge then
        -- Handle spirit->hit conversion special case
        if data.conv[addonTable.statIds.SPIRIT] and data.conv[addonTable.statIds.SPIRIT][addonTable.statIds.HIT] == 1 then
          if reforge.dst == addonTable.statIds.HIT and data.method.items[slot].stats[addonTable.statIds.SPIRIT] == 0 then
            reforge.dst = addonTable.statIds.SPIRIT
          end
        end
        data.method.items[slot].src = reforge.src
        data.method.items[slot].dst = reforge.dst
      else
        data.method.items[slot].src = nil
        data.method.items[slot].dst = nil
      end
    end

    self.methodDebug = { data = CopyTable(data) }
    self:FinalizeReforge(data)
    self.methodDebug.method = CopyTable(data.method)

    if data.method then
      self.pdb.method = data.method
      self.pdb.methodOrigin = addonName
      self:UpdateMethodCategory()
    end
  else
    if self.db.debug then
      print("B&B: No solution found, falling back to DP")
    end
    self:ComputeReforgeClassic()
  end
end

--- Runs both Dynamic Programming and Branch-and-Bound algorithms for performance comparison.
--- Prints detailed debug output comparing execution times, scores, and individual reforge choices.
--- Used for algorithm validation and performance analysis during development.
--- @return nil Updates self.pdb.method with the better solution and prints comparison results
function ReforgeLite:RunAlgorithmComparison()
  self:GetConversion()

  local _, specName = addonTable.compat.GetSpecInfoByID(addonTable.compat.GetCurrentSpecID())
  local _, ilvl = GetAverageItemLevel()
  print(("=== %s %s - %s ilvl ==="):format(specName or "", addonTable.localeClass, ilvl))
  local version, build = GetBuildInfo()
  print("WoW Build:", version, build)

  local weightsStr = ""
  for i = 1, #self.pdb.weights do
    if self.pdb.weights[i] and self.pdb.weights[i] ~= 0 then
      local statName = ITEM_STATS[i] and ITEM_STATS[i].tip or ("s" .. i)
      weightsStr = weightsStr .. (" %s:%.0f"):format(statName, self.pdb.weights[i])
    end
  end
  print(("Weights:%s"):format(weightsStr))

  for i = 1, 2 do
    local cap = self.pdb.caps[i]
    if cap and cap.stat > 0 and cap.points[1] then
      local statName = ITEM_STATS[cap.stat] and ITEM_STATS[cap.stat].tip or ("s" .. cap.stat)
      local methodNames = {"AtLeast", "AtMost", "Exactly", "NewValue"}
      local pt = cap.points[1]
      print(("Cap %d: %s %s %.0f"):format(i, statName, methodNames[pt.method] or pt.method, pt.value or 0))
    end
  end

  -- Store original method
  local originalMethod = self.pdb.method and CopyTable(self.pdb.method) or nil

  -- Run DP algorithm
  print("Running Dynamic Programming...")
  local dpStart = debugprofilestop()
  self:ComputeReforgeClassic()
  local dpTime = debugprofilestop() - dpStart
  local dpMethod = CopyTable(self.pdb.method)
  local dpScore = self:CalculateMethodScore(dpMethod)
  local dpConstraintsMet = self:CheckConstraintsSatisfied(dpMethod)

  -- Store DP choices for debugging
  dpChoices = wipe(dpChoices or {})
  local dpPathStr = ""
  for i = 1, #dpMethod.items do
    dpChoices[i] = {src = dpMethod.items[i].src, dst = dpMethod.items[i].dst}
    if dpMethod.items[i].src and dpMethod.items[i].dst then
      dpPathStr = dpPathStr .. (" %d:%d->%d"):format(i, dpMethod.items[i].src, dpMethod.items[i].dst)
    end
  end

  if self.db.debug then
    print(("DP: Found solution, score: %.1f, constraints: %s, path:%s"):format(
      dpScore, dpConstraintsMet and "Pass" or "Fail", dpPathStr))

  -- Check that the B&B option set can generate all DP choices (should be full coverage now)
    print("=== Option Coverage ===")
    local data = self:InitReforgeClassic()
    local priorityCap = self:CalculatePriorityCap(data)

    for i = 1, #dpMethod.items do
      local dpChoice = dpChoices[i]
      if dpChoice.src or dpChoice.dst then -- Skip "no reforge" choices
        local fullOptions = self:GetFullReforgeOptions(data, i, priorityCap)

        local foundDPChoice = false
        for _, opt in ipairs(fullOptions) do
          if opt.src == dpChoice.src and opt.dst == dpChoice.dst then
            foundDPChoice = true
            break
          end
        end
        if not foundDPChoice then
          local dpStr = dpChoice.src and ("%d->%d"):format(dpChoice.src, dpChoice.dst) or "none"
          print(("Item %d: DP choice %s NOT in options"):format(i, dpStr))
        end
      end
    end
  end

  -- Reset to original
  self.pdb.method = originalMethod and CopyTable(originalMethod) or nil

  -- Run Branch and Bound
  print("Running Branch and Bound...")
  local bbStart = debugprofilestop()
  self:ComputeReforgeBranchBound()
  local bbTime = debugprofilestop() - bbStart
  local bbMethod = CopyTable(self.pdb.method)
  local bbScore = self:CalculateMethodScore(bbMethod)
  local bbConstraintsMet = self:CheckConstraintsSatisfied(bbMethod)

  -- Print comparison
  local function fmtTime(ms)
    return ms >= 1000 and ("%.2fs"):format(ms / 1000) or ("%.0fms"):format(ms)
  end
  print("=== Results ===")
  print(("DP: Score %.1f, Time %s, Constraints %s"):format(
    dpScore, fmtTime(dpTime), dpConstraintsMet and "Pass" or "Fail"))
  print(("B&B: Score %.1f, Time %s, Constraints %s"):format(
    bbScore, fmtTime(bbTime), bbConstraintsMet and "Pass" or "Fail"))

  -- Compare individual choices
  if self.db.debug then
    print("=== Choice Comparison ===")
    for i = 1, #dpMethod.items do
      local dpChoice = dpChoices[i]
      local bbChoice = {src = bbMethod.items[i].src, dst = bbMethod.items[i].dst}

      local dpStr = dpChoice.src and ("%d->%d"):format(dpChoice.src, dpChoice.dst) or "none"
      local bbStr = bbChoice.src and ("%d->%d"):format(bbChoice.src, bbChoice.dst) or "none"

      if dpChoice.src ~= bbChoice.src or dpChoice.dst ~= bbChoice.dst then
        print(("Item %d: DP=%s, B&B=%s (DIFFERENT)"):format(i, dpStr, bbStr))
      end
    end
  end

  -- Determine winner
  local winner
  if dpConstraintsMet ~= bbConstraintsMet then
    winner = dpConstraintsMet and "DP (constraints)" or "B&B (constraints)"
  elseif abs(dpScore - bbScore) > 0.1 then
    winner = dpScore > bbScore and "DP" or "B&B"
  else
    winner = dpTime < bbTime and "DP (faster)" or "B&B (faster)"
  end
  print("Winner: " .. winner)

  -- Use better solution
  if bbConstraintsMet and (not dpConstraintsMet or bbScore > dpScore) then
    self.pdb.method = bbMethod
  else
    self.pdb.method = dpMethod
  end

  -- Clear debug state
  dpChoices = nil

  self:UpdateMethodCategory()
end