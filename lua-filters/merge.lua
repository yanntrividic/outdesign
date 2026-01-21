-- merge_top_level_elements.lua

-- Avec une version où tu as un callback par nœud, j’ai l’impression que tout ce dont tu as 
-- besoin pour connaître la profondeur d’un nœud, c’est d’une table P qui, à un identifiant 
-- de nœud (disons son adresse) associe un entier (sa profondeur).
-- Ensuite, au début de chaque callback appelé sur un nœud N, tu effectues les opérations suivantes :

-- 1. Tester si l’identifiant du nœud courant est dans P :
--    a. S’il ne l’est pas, il s’agit de la racine, qu’il faut ajouter à P avec une profondeur initiale à 0 ;
--    b. S’il l’est, ce qui devrait être le cas pour tous les autres nœuds, y lire la profondeur courante p.
-- 2. Pour chaque nœud enfant C de N, ajouter une entrée dans P associant l’identifiant de C à p + 1.

local merge_selector = "to-merge"

local pu = require "pandoc.utils"

counter = 0
depths = {}

filtered_inlines = {
  Str = true,
  Space = true,
  LineBreak = true,
  SoftBreak = true
}

function printTable(tbl, indent)
    indent = indent or 0
    for k, v in pairs(tbl) do
        local formatting = string.rep("  ", indent) .. tostring(k) .. ": "
        if type(v) == "table" then
            print(formatting)
            utils.printTable(v, indent + 1)
        else
            print(formatting .. tostring(v))
        end
    end
end

local function get_child_blocks(el)
  -- if not el or type(el) ~= "table" then return {} end
  if el.t == "Div" or el.t == "BlockQuote" then
    return el.content or {}
  elseif el.t == "BulletList" or el.t == "OrderedList" then
    local blocks = {}
    for _, item in ipairs(el.content or {}) do
      for _, blk in ipairs(item) do
        table.insert(blocks, blk)
      end
    end
    return blocks
  else
    return {}
  end
end

local function has_class(el, class)
  if el.t ~= "Div" then return false end
  for _, c in ipairs(el.classes or {}) do
    if c == class then return true end
  end
  return false
end

buffer = {}
buffer_level = nil -- init a large number

local function flush()
  if #buffer == 0 then
    return {}
  end
  local merged = pandoc.Div(buffer)
  buffer = {}
  buffer_level = nil
  return { merged }
end

local function register_depths(el, level)
  -- This logics works for blocks as long as two exactly identical
  -- blocks are at different depths of the tree. Same for inlines...
  local s_el = tostring(el)
  depths[s_el] = { level, counter }
  counter = counter +1 
  print(counter .. "," .. level .. ": " .. pu.stringify(el))
  -- printTable(depths[s_el])

  for _, child in ipairs(get_child_blocks(el)) do
    register_depths(child, level + 1)
  end
end

function addBlockToDepthTable(doc)
  for _, blk in ipairs(doc.blocks) do
    register_depths(blk, 1)
  end
  -- printTable(depths)
end

function Block(el)
  -- printTable(top_level_blocks)
  -- only merge if it's BOTH top-level and matches class

  if buffer_level == depths[tostring(el)] then
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
  { Pandoc = addBlockToDepthTable },
  { Block = Block },
  { Pandoc = Pandoc }
}