-- merge_top_level_elements.lua
-- This filter implements a basic merge operator using the Block callback
-- 1. A lookup table is build from the top-level elements using the Pandoc callback
-- 2. In the Block callback, when a top-level with the right class is called, a buffer is populated
-- 3. When a top-level element without the right class is called, the buffer is flushed
-- 4. Before exiting the program, the buffer is flushed to keep possible leftovers.

local merge_selector = "to-merge"
local buffer = {}

top_level_blocks = {}

local function getTopLevelBlocks(doc)
  for _, blk in ipairs(doc.blocks) do
    top_level_blocks[tostring(blk)] = true
  end
  return doc
end

local function has_class(el, class)
  if el.t ~= "Div" then return false end
  for _, c in ipairs(el.classes or {}) do
    if c == class then return true end
  end
  return false
end

local function flush()
  if #buffer == 0 then
    return {}
  end
  local merged = pandoc.Div(buffer)
  buffer = {}
  return { merged }
end

function Block(el)
  -- printTable(top_level_blocks)
  -- only merge if it's BOTH top-level and matches class

  if not top_level_blocks[tostring(el)] then
    return el
  end

  if has_class(el, merge_selector) then
    table.insert(buffer, el)
    return {}
  else
    local out = {}
    if #buffer > 0 then
      for _, b in ipairs(flush()) do table.insert(out, b) end
    end
    table.insert(out, el)
    return out
  end
end

-- final cleanup after traversal
function Pandoc(doc)
  -- the walk already replaced the blocks; we just need to flush tail
  local tail = flush()
  if #tail == 0 then
    return doc
  end
  -- append trailing merged group
  for _, blk in ipairs(tail) do
    table.insert(doc.blocks, blk)
  end
  return doc
end

return {
  { Pandoc = getTopLevelBlocks },
  { Block = Block },
  { Pandoc = Pandoc }
}