-- Utility functions for map.lua

local json = require 'pandoc.json' -- requires Pandoc>=3.1.1

local logging = require 'logging'

local utils = {}

utils.ext = {
  -- Markdown family
  markdown          = "md",
  commonmark        = "md",
  gfm               = "md",
  markdown_mmd      = "md",
  markdown_phpextra = "md",
  markdown_strict   = "md",

  -- HTML
  html   = "html",
  html4  = "html",
  html5  = "html",

  -- DocBook
  docbook      = "xml",
  docbook4     = "xml",
  docbook5     = "xml",

  -- LaTeX / TeX
  latex  = "tex",
  beamer = "tex",
  context= "tex",

  -- MS Office
  docx = "docx",
  pptx = "pptx",
  xlsx = "xlsx",

  -- OpenDocument
  odt = "odt",
  odp = "odp",
  ods = "ods",

  -- RTF / TXT
  rtf = "rtf",
  plain = "txt",

  -- OPML
  opml = "opml",

  -- EPUB
  epub  = "epub",
  epub2 = "epub",
  epub3 = "epub",

  -- JSON (Pandoc AST)
  json = "json",

  -- ICML (Adobe InCopy)
  icml = "icml",

  -- Man page / roff
  man  = "1",
  ms   = "ms",

  -- Textile
  textile = "textile",

  -- Org
  org = "org",

  -- AsciiDoc
  asciidoc  = "adoc",
  asciidoctor = "adoc",

  -- Other special ones
  native = "native",
  pdf    = "pdf"
}

-- Helper function to slugify Header contents for filenames.
-- There might be some problems with accentuated chars...
function utils.slugify(str)
  str = pandoc.text.lower(str)
  str = str:gsub("[%z\1-\127\194-\244][\128-\191]*", { ["ü"]="u", ["ä"]="a", 
                    ["ö"]="o", ["ß"]="ss", ["é"]="e", ["è"]="e", ["ê"]="e", 
                    ["à"]="a", ["á"]="a", ["ç"]="c", ["ñ"]="n" })
  str = str:gsub("[^%w%s-]", "")     -- drop non-word chars
  str = str:gsub("[%s-]+", "_")      -- spaces to underscores
  str = str:gsub("_+", "_")          -- collapse multiple _
  str = str:gsub("^_*(.-)_*$", "%1") -- trim leading/trailing _
  
  -- Extract only the first ten words
  local result, count = {}, 0
  for word in string.gmatch(str, "([^_]+)") do
      count = count + 1
      if count > 10 then break end
      table.insert(result, word)
  end

  return table.concat(result, "_")
end

-- extract first heading text from a block list
function utils.firstNonEmptyHeader(blocks)
  for _, blk in ipairs(blocks) do
    if blk.t == "Header" and not (#blk.content == 1 and blk.content[1].t == "LineBreak") then
      return pandoc.utils.stringify(blk.content)
    end
  end
  return nil
end

-- Helper function for timing performances
-- example call: el = utils.timeit("simplify", operators.simplify, el)
function utils.timeit(message, func, ...)
    local info = debug.getinfo(func, "S")
    local location = string.format("%s:%d", info.short_src, info.linedefined)

    local start_time = os.clock()
    local results = {func(...)}
    local end_time = os.clock()

    print(string.format(message .. ": Function defined at %s took %.6f seconds",
        location, end_time - start_time))

    return table.unpack(results)
end

function utils.mkdir(path)
  path = path:gsub("/+$", "")
  if path == "" then return true end

  local ok, _, code = os.rename(path, path)
  if ok or code == 13 then return true end

  local parent = path:match("(.+)/[^/]+$")
  if parent and parent ~= path then
    mkdir_p(parent)
  end

  -- create this dir
  if package.config:sub(1,1) == "\\" then
    -- Windows
    os.execute('mkdir "' .. path .. '" >NUL 2>&1')
  else
    -- POSIX
    os.execute('mkdir -p "' .. path .. '"')
  end
  return true
end

function utils.printTable(tbl, indent)
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

local function readMap(map_file)
    -- Open the file in read mode
    local file = io.open(map_file, "r")
    if not file then
        error("Could not open " .. map_file .. "!")
    end
    -- Read the entire file content
    local content = file:read("*all")
    -- Close the file
    file:close()
    return content
end

-- Parse one selector like "BlockQuote.class1.class2"
local function split(str, pat)
  local t = {}
  str:gsub("([^" .. pat .. "]+)", function(c) t[#t+1] = c end)
  return t
end

function utils.parseSelector(sel)
  if type(sel) ~= "string" or sel == "" then
    error("Selector must be a non-empty string.")
  end

  local tag
  local id = ""
  local classes = {}

  -- Split into parts: tag, id, classes
  -- /!\ CSS-like syntax is order-independent
  local tag_pattern = "^[%a]+"
  local tag_match = sel:match(tag_pattern)

  local remainder = sel
  if tag_match then
    tag = tag_match
    remainder = sel:sub(#tag + 1)
  end

  -- Extract ID (at most one)
  local id_pos = remainder:find("#")
  if id_pos then
    local after_id = remainder:sub(id_pos + 1)
    local id_match = after_id:match("^[%w_-]+")
    if not id_match then
      error("Invalid ID in selector: " .. sel)
    end
    id = id_match
    -- remove the ID part by slicing
    remainder = remainder:sub(1, id_pos - 1) .. remainder:sub(id_pos + 1 + #id)
    -- check for another '#'
    if remainder:find("#") then
      error("Selector cannot contain multiple IDs: " .. sel)
    end
  end

  -- Handle classes (can appear before or after #)
  for class in remainder:gmatch("%.[%w_-]+") do
    table.insert(classes, class:sub(2))
  end

  -- Check for invalid punctuation (anything not . or # or valid chars)
  local cleaned = remainder:gsub("%.[%w_-]+", "")
  cleaned = cleaned:gsub("#[%w_-]+", "")
  -- we also accept ":" as it can appear in hub XML files...
  cleaned = cleaned:gsub("[%w_:]+", "")
  if cleaned:match("[^%s]") then
    error("Invalid selector syntax: " .. sel)
  end

  return tag, id, classes
end

function utils.parseSelectorList(sel)
  if type(sel) ~= "string" or sel == "" then
    error("Selector must be a non-empty string.")
  end

  local selectors = {}
  for part in sel:gmatch("[^,]+") do
    local trimmed = part:match("^%s*(.-)%s*$")
    local tag, id, classes = utils.parseSelector(trimmed)
    table.insert(selectors, {
      _tag = tag,
      _id = id,
      _classes = classes,
      _raw = trimmed
    })
  end
  return selectors
end

-- Cache for memoization: element+selector -> match result
local matchCache = {}

-- Precompute parsed selectors for map entries
local function preprocessMap(map)
  for _, entry in ipairs(map) do
    local ok, result = pcall(utils.parseSelectorList, entry.selector)
    if ok then
      entry._selectors = result
    else
      logging.warning("preprocessMap: " .. result)
    end
  end
end

function utils.readAndPreprocessMap(meta)
  if meta.map then
    map_file = pandoc.utils.stringify(meta.map)
    content = readMap(map_file)
    map = json.decode(content)
    preprocessMap(map)
  end
  return meta
end

-- Cutting is done after the mapping, so we need to update
-- The entry._classes values with the new classes if necessary.
function utils.updateMapWithNewClasses()
  for _, entry in ipairs(map) do
    local o = entry.operation
    if o.classes and o.classes ~= "" then
      local new_classes = {}
      for class in string.gmatch(o.classes, "%S+") do
          table.insert(new_classes, class)
      end
      entry._classes = new_classes
    end
  end
end

-- Function that checks if a cut entry if in the operations
-- in order to determine if the output needs to be cut
function utils.isCutable()
  for _, entry in ipairs(map) do
    if entry.operation.cut then
      return true
    end
  end
  return false
end

-- Helper function that checks if an element is a wrapper
-- that is, if it is a Span or a Div with a wrapper=1 attribute.
function utils.isWrapper(el)
  if (el.t == "Div" or el.t == "Span") and el.attr and el.attr.attributes then
    return el.attr.attributes["wrapper"] == "1"
  end
  return false
end

-- Memoized matching function
function utils.isMatchingSelector(el, tag, id, classes)
  -- Build a unique key per element + selector
  local el_tag = el.t or ""
  local el_id = el.identifier or ""
  local el_classes = el.classes or {}

  if utils.isWrapper(el) then
    el_tag = el.content[1].tag or el_tag
    el_id = el.content[1].identifier or el_id
  end

  local key = el_tag .. ":" .. el_id .. ":" .. table.concat(el_classes, ",") ..
              "|" .. (tag or "") .. ":" .. (id or "") .. ":" .. table.concat(classes or {}, ",")

  if matchCache[key] ~= nil then
    return matchCache[key]
  end

  -- Check tag
  if tag and el_tag ~= tag then
    matchCache[key] = false
    return false
  end

  -- Check ID
  if id ~= "" and el_id ~= id then
    matchCache[key] = false
    return false
  end

  -- Check classes
  if classes and #classes > 0 then
    local el_class_set = {}
    for _, c in ipairs(el_classes) do
      el_class_set[c] = true
    end
    for _, class in ipairs(classes) do
      if not el_class_set[class] then
        matchCache[key] = false
        return false
      end
    end
  end

  matchCache[key] = true
  return true
end

function utils.isMatchingSelectorList(el, selectorList)
  for _, sel in ipairs(selectorList) do
    if utils.isMatchingSelector(el, sel._tag, sel._id, sel._classes) then
      return sel
    end
  end
  return false
end

return utils