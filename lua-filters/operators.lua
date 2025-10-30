-- Mapping operators for map.lua

local utils = require "utils"
local pu = require "pandoc.utils"
local logging = require "logging"

local operators = {}

-- Supported types by this filter

blockTypes = {
  Div = true,
  Header = true,
  Para = true,
  BlockQuote = true,
  LineBlock = true,
  BulletList = true,
  OrderedList = true,
  CodeBlock = true,
  Note = true,
  RawBlock = true
}

inlineTypes = {
  Link = true,
  Code = true,
  Span = true,
  Superscript = true,
  Emph = true,
  SmallCaps = true,
  Strikeout = true,
  Strong = true,
  Subscript = true,
  Underline = true
}

blockSupportsAttrs = {
  Div = true,
  Header = true,
  CodeBlock = true
}

inlineSupportsAttrs = {
  Span = true,
  Code = true,
  Link = true
}

-- Helper function to get every Attr value as a table
local function getAttr(attr)
  local id, classes, attrs

  if not attr then
    id = ""
    classes = {}
    attrs = {}
  elseif type(attr) == "table" then
    id = attr[1] or ""
    classes = attr[2] or {}
    attrs = attr[3] or {}
  else
    id = attr.identifier
    classes = attr.classes
    attrs = attr.attributes
  end

  return id, classes, attrs
end

-- Helper function to check if an Attr is empty
local function isEmptyAttr(attr)
  local id, classes, attrs = getAttr(attr)
  return id == "" and #classes == 0 and #attrs == 0
end

-- Helper function to remove useless Span and Div around
local function removeEmptyWrapper(el)
  if (el.t == "Div" or el.t == "Span") and isEmptyAttr(el.attr) then
    return el.content
  end
  return el
end

-- This returns a new Attr object with an updated
-- wrapper attribute value.
-- Some Pandoc types have tuples as attributes,
-- others have Attr. This function covers both cases.
local function getAttrWithWrapper(attr, value)
  local id, classes, attrs = getAttr(attr)
  attrs["wrapper"] = value
  return pandoc.Attr(id, classes, attrs)
end

-- Helper function to wrap element in wrapper if attrs are needed.
local function addWrapper(el)
  local attr = pandoc.Attr("", {}, {})
  if blockTypes[el.t] and not blockSupportsAttrs[el.t] then
    el = pandoc.Div({el}, getAttrWithWrapper(attr, 1))
  elseif inlineTypes[el.t] and not inlineSupportsAttrs[el.t] then
    el = pandoc.Span({el}, getAttrWithWrapper(attr, 1))
  end
  return el
end

-- Function that removes a useless wrapper
-- i.e. A Div with only a wrapper attribute
-- or a span with only a wrapper attribute
local function removeUselessWrapper(el)
  if not utils.isWrapper(el) then
    return el
  end

  local id, classes, attrs = getAttr(el.attr)

  -- Check if the only attribute is wrapper="1", and no id/classes
  local only_wrapper = #attrs == 1 and attrs["wrapper"] == "1"
  local no_other_attrs = #classes == 0 and id == ""

  if only_wrapper and no_other_attrs then
    -- Unwrap: return content directly
    return el.content
  else
    return el
  end
  return el
end

-- This is highly specific to the IDML Pandoc Reader specific.
-- It can be handy to keep empty elements. The idml2docbook
-- module sends the data of empty elements to the AST by
-- just filling it with a LineBreak. (Should it be a SoftBreak?)
function isContentOneLineBreak(el)
  div_wrapper_with_one_linebreak = pandoc.Div(pandoc.Para(pandoc.LineBreak()), pandoc.Attr("", el.classes, { wrapper = 1 }))
  return el == div_wrapper_with_one_linebreak
end

-- Add a unique id attribute to the element if it doesn't have one,
-- based on the selector. The ID goes like:
-- type-selector_class1-...-selector_classn-counter
-- Global counter table for unique IDs
local id_counters = {}

function applyId(el)
  local id, classes, attrs = getAttr(el.attr)
  if id ~= "" then return el end

  -- Compose base id parts
  local base_parts = { }
  if utils.isWrapper(el) then
    table.insert(base_parts, string.lower(el.content[1].tag))
  else
    table.insert(base_parts, string.lower(el.tag))
  end

  if classes and #classes > 0 then
    for _, c in ipairs(classes) do
      table.insert(base_parts, c)
    end
  end

  local base_id = table.concat(base_parts, "-")

  id_counters[base_id] = (id_counters[base_id] or 0) + 1
  local counter = id_counters[base_id]
  local new_id = string.format("%s-%d", base_id, counter)

  if inlineSupportsAttrs[el.tag] or blockSupportsAttrs[el.tag] then
      -- If element already has an id, preserve it unless it's empty
    if id == "" then
      id = new_id
    end

    el.attr = pandoc.Attr(id, classes, attrs)
  else
    local attr = pandoc.Attr(new_id, {}, {})

    if blockTypes[el.tag] then
      return pandoc.Div({el}, getAttrWithWrapper(attr, 1))
    elseif inline[el.tag] then
      return pandoc.Span({el}, getAttrWithWrapper(attr, 1))
    end
  end

  return el
end

-- Modify el.classes based on selector and operation rules:
--   - operation_classes == false → remove all classes
--   - operation_classes == ""    → remove selector_classes only
--   - operation_classes is string → replace selector_classes with new ones
function applyClasses(el, selector_classes, operation_classes)
  -- Handle case where o.classes == false → remove all classes
  if operation_classes == false then
    el.classes = {}
    return removeUselessWrapper(el)
  end

  -- Case 1: o.classes == "" -> remove only selector classes
  if operation_classes == "" then
    local new = {}
    for _, c in ipairs(el.classes) do
      local keep = true
      for _, sel_c in ipairs(selector_classes or {}) do
        if c == sel_c then
          keep = false
          break
        end
      end
      if keep then table.insert(new, c) end
    end
    el.classes = new
    return removeUselessWrapper(el)
  end

  -- Case 2: o.classes is a string -> replace selector classes with these new ones
  if type(operation_classes) == "string" then
    -- Split the operation_classes string into words
    local new_classes = {}
    for class in string.gmatch(operation_classes, "%S+") do
      table.insert(new_classes, class)
    end

    -- Remove selector classes from el.classes
    local filtered = {}

    -- Add wrapper if the element does not support attributes
    el = addWrapper(el)

    for _, c in ipairs(el.classes) do
      local keep = true
      for _, sel_c in ipairs(selector_classes or {}) do
        if c == sel_c then
          keep = false
          break
        end
      end
      if keep then table.insert(filtered, c) end
    end

    -- Append the new replacement classes
    for _, c in ipairs(new_classes) do
      table.insert(filtered, c)
    end

    el.classes = filtered
  end

  -- Default: do nothing special
  return removeUselessWrapper(el)
end


-- THIS RELATES TO applyAttrs


-- Helper to merge key/value pairs into an existing attr
local function mergeKeyvals(old_attr, new_keyvals)
  local id = old_attr.identifier or ""
  local classes = old_attr.classes or {}
  local keyvals = old_attr.attributes or {}

  for k, v in pairs(new_keyvals) do
    local found = false
    for i, kv in ipairs(keyvals) do
      if kv[1] == k then
        kv[2] = v
        found = true
        break
      end
    end
    if not found then
      table.insert(keyvals, {k, v})
    end
  end

  return {id, classes, keyvals}
end

-- Apply key/value attributes to a block
local function applyAttrsBlock(el, keyvals)
  if blockSupportsAttrs[el.tag] then
    el.attr = mergeKeyvals(el.attr or {"", {}, {}}, keyvals)
    return el
  else
    -- Wrap in Div
    return pandoc.Div({el}, {"", {}, keyvals})
  end
end

-- Apply key/value attributes to an inline
local function applyAttrsInline(el, keyvals)
  if inlineSupportsAttrs[el.tag] then
    el.attr = mergeKeyvals(el.attr or {"", {}, {}}, keyvals)
    return el
  else
    -- Wrap in Span
    return pandoc.Span({el}, {"", {}, keyvals})
  end
end

-- Dispatcher
function applyAttrs(el, keyvals)
  if blockTypes[el.t] then
    return applyAttrsBlock(el, keyvals)
  elseif inlineTypes[el.t] then
    return applyAttrsInline(el, keyvals)
  else
    return el
  end
end

-- THIS RELATES TO applyType

-- Smart block conversion
local function blockToBlock(el, newtype, wrapper_attr, is_list)
  local attr
  if wrapper_attr ~= nil then
    attr = wrapper_attr
  else
    attr = el.attr
  end

  local is_empty_attr = isEmptyAttr(attr)

  if is_empty_attr then
    attr = {"", {}, {}}
  end

  local content

  if type(el) == "table" and el[1] and el[1].t then
    -- el is a list of block elements (e.g. { Para(), Para() })
    if newtype == "LineBlock" then
      -- Convert each Para into a line (list of inlines)
      local lines = pandoc.List()
      for _, blk in ipairs(el) do
        if blk.t == "Para" or blk.t == "Plain" then
          lines:insert(blk.content)
        elseif blk.t == "LineBlock" then
          -- Flatten nested LineBlocks
          for _, line in ipairs(blk.content) do
            lines:insert(line)
          end
        end
      end
      return pandoc.LineBlock(lines)
    else
      -- For other types, treat it as a list of blocks
      content = el
    end
  else
    -- el is a single block
    content = el.content
  end

  if newtype == "Header" then
    result = pandoc.Header(1, pu.blocks_to_inlines({el}), getAttrWithWrapper(attr, nil))
  elseif newtype == "Para" then
    result = pandoc.Para(content)
  elseif newtype == "BlockQuote" then
    result = pandoc.BlockQuote(el)
  elseif newtype == "LineBlock" then
    result = pandoc.LineBlock({ content })
  elseif newtype == "Div" then
    result = pandoc.Div(content, getAttrWithWrapper(attr, nil))
  elseif newtype == "BulletList" then
    result = pandoc.BulletList({ el })
  elseif newtype == "OrderedList" then
    result = pandoc.OrderedList({ el })
  elseif newtype == "CodeBlock" then
    result = pandoc.CodeBlock(pu.stringify(content), getAttrWithWrapper(attr, nil))
  else
    result = el
  end

  -- Wrap in Div if new node doesn't support attributes but old node had them
  if not is_empty_attr then
    local attr_supported = (newtype == "Div" or newtype == "Header" or newtype == "CodeBlock")
    if not attr_supported then
      attr_with_wrapper = getAttrWithWrapper(attr, 1) -- adding a wrapper attribute to attrs
      result = pandoc.Div({result}, attr_with_wrapper) 
    end
  end

  return result
end

-- Smart inline conversion
local function inlineToInline(el, newtype, wrapper_attr)
  local attr
  is_empty_attr = isEmptyAttr(el.attr)
  if is_empty_attr then
    attr = {"", {}, {}}
  else
    attr = el.attr
  end

  local inlines = el.content or ({ pandoc.Str(el.text)}) or {}
  local text = el.text or pu.stringify(inlines)
  local result

  if newtype == "Span" then
    result = pandoc.Span(inlines, attr)
  elseif newtype == "Emph" then
    result = pandoc.Emph(inlines)
  elseif newtype == "Strong" then
    result = pandoc.Strong(inlines)
  elseif newtype == "Link" then
    result = pandoc.Link(inlines, el.target or "", el.title or "", attr)
  elseif newtype == "Superscript" then
    result = pandoc.Superscript(inlines)
  elseif newtype == "Subscript" then
    result = pandoc.Subscript(inlines)
  elseif newtype == "SmallCaps" then
    result = pandoc.SmallCaps(inlines)
  elseif newtype == "Code" then
    result = pandoc.Code(text, attr)
  elseif newtype == "Strikeout" then
    result = pandoc.Strikeout(inlines)
  elseif newtype == "Underline" then
    result = pandoc.Underline(inlines)
  else
    result = el
  end

  -- Wrap in Span if new node doesn't support attributes but old node had them
  if not is_empty_attr then
    local attr_supported = (newtype == "Span" or newtype == "Code" or newtype == "Link")
    if not attr_supported then
      attr_with_wrapper = getAttrWithWrapper(attr, 1) -- adding a wrapper attribute to attrs
      result = pandoc.Span({result}, attr_with_wrapper) 
    end
  end

  return result
end

-- This function replaces the type of the given element by a new type.
-- It works for both Inlines and Blocks, but it will only replace Block elements
-- with other Block elements, and only replace Inline elements with Inline elements.
-- This function keeps track of classes, attributes and ids. When necessary,
-- a wrapper Div or Span is created around the new element type to keep all
-- the data after conversion.
function applyType(el, newtype)
  if utils.isWrapper(el) then
    local wrapper_id, wrapper_classes, wrapper_attributes = getAttr(el)
    local wrapper_attr = pandoc.Attr(wrapper_id, wrapper_classes, wrapper_attributes)

    el = el.content[1]

    if blockTypes[el.t] and blockTypes[newtype] then
      return blockToBlock(el, newtype, wrapper_attr, false)
    elseif inlineTypes[el.t] and inlineTypes[newtype] then
      return inlineToInline(el, newtype, wrapper_attr)
    else
      return el
    end
  else
    if blockTypes[el.t] and blockTypes[newtype] then
      return blockToBlock(el, newtype, nil, false)
    elseif inlineTypes[el.t] and inlineTypes[newtype] then
      return inlineToInline(el, newtype, nil)
    else
      if type(el) == "table" then
        -- We are in the context where this is an unwrapped Div that
        -- contains only one element. It won't work for several elements.
        if blockTypes[el[1].t] and blockTypes[newtype] then
          return blockToBlock(el[1], newtype, wrapper_attr, true)
        end
      else
        -- That means we are trying to do inline-to-block
        -- or block-to-inline conversions
        error(el.t .. " to " .. newtype .. " conversions are not possible.")
      end
    end
    return el
  end
end

function applyLevel(el, level)
  if el.t == "Header" then
    -- Preserve attributes and content
    return pandoc.Header(level, el.content, el.attr)
  else
    -- If it's not a Header, raise an error
    error("Level attributes are not applicable to " .. tostring(el.t) .. " elements.")
  end
  return el
end

-- Function that simplifies an element.
-- If the element is a wrapper, it unwraps its content.
-- If it is not a wrapper, it only deleted its Attr.
function simplify(el)

  id, classes, attrs = getAttr(el.attr)
  
  if attrs["wrapper"] == "1" then
    return el.content  -- unwrap wrapper: return content directly
  end

  -- Rebuild element without attributes
  local t = el.t
  if t == "Div" then
    return pandoc.Div(el.content) -- remove Attr
  elseif t == "Para" then
    return pandoc.Para(el.content)
  elseif t == "Header" then
    -- I have no idea why the id is not being returned, it really
    -- seems like a bug here...
    return pandoc.Header(el.level, el.content, pandoc.Attr("", {}, {}))
  elseif t == "BlockQuote" then
    return pandoc.BlockQuote(el.content)
  elseif t == "LineBlock" then
    return pandoc.LineBlock(el.content)
  elseif t == "BulletList" then
    return pandoc.BulletList(el.content)
  elseif t == "OrderedList" then
    return pandoc.OrderedList(el.content, el.listAttributes or {0, ""})
  elseif t == "CodeBlock" then
    return pandoc.CodeBlock(el.text)
  elseif t == "Span" then
    return pandoc.Span(el.content)
  elseif t == "Code" then
    return pandoc.Code(el.text)
  elseif t == "Link" then
    return pandoc.Link(el.content, el.target)
  elseif t == "Emph" then
    return pandoc.Emph(el.content)
  elseif t == "Strong" then
    return pandoc.Strong(el.content)
  elseif t == "Strikeout" then
    return pandoc.Strikeout(el.content)
  elseif t == "Superscript" then
    return pandoc.Superscript(el.content)
  elseif t == "Subscript" then
    return pandoc.Subscript(el.content)
  elseif t == "SmallCaps" then
    return pandoc.SmallCaps(el.content)
  elseif t == "Underline" then
    return pandoc.Underline(el.content)
  else
    return el  -- fallback: unknown element, return as-is
  end
end

-- Function that unwraps the content of an element in its parent.
-- For Inlines, that means replacing the Inline object with its content.
-- For Blocks, that means (opinionated):
-- 1) With a Div that is not a wrapper, that means replacing the Div
--    with its content. 
-- 2) With a Div that is a wrapper, that means replacing the Div and its
--    content element with a Para element without Attr.
-- 3) With any other Block, that means replacing the tag with a Para.
function unwrap(el)
  if inlineTypes[el.t] then -- We check if we handle this element
    -- Code is an exception as it contains text and not content
    if el.t == "Code" then
      return el.text
    end
    return el.content
  end

  if blockTypes[el.t] then
    if utils.isWrapper(el) then
      return pandoc.Para(el.content[1].content)
    else
      return el.content
    end

    -- Handle other Block elements
    if el.t == "Plain" then
      return pandoc.Para(el.content)

    elseif el.t == "BlockQuote" or el.t == "LineBlock" or el.t == "Note" or
          el.t == "CodeBlock" or el.t == "RawBlock" or 
          el.t == "Div" or el.t == "Header" or
          el.t == "BulletList" or el.t == "OrderedList" then
      return pandoc.Para(pu.blocks_to_inlines({el}))

    elseif el.t == "Para" then
      return el  -- already Para
    end

    -- Fallback
    return el
  end
end

-- Function that wraps a Block element or an Inline element
-- in a wrapper element. Not all elements can be wrapper elements.
-- Many wraps possibilities are actually covered by applyType.
-- Here, we will consider that a wrapper element has to be a Div
-- or a Span, and that it can have classes.
-- The wrapper argument is actually a string that can hold classes,
-- Note: These wrappers are explicit, not explicit such as elements
-- with wrapper=1 atributes.
function wrap(el, wrapper)
  local tag, _, classes = utils.parseSelector(wrapper)
  if blockTypes[el.t] then
    -- Wrap Blocks in a Div
    return pandoc.Div({el}, pandoc.Attr("", classes))
  elseif inlineTypes[el.t] then
    -- Wrap Inlines in a the corresponding tag
    if tag == "Superscript" then
      el = pandoc.Superscript({el})
    elseif tag == "Emph" then
      el = pandoc.Emph({el})
    elseif tag == "SmallCaps" then
      el = pandoc.SmallCaps({el})
    elseif tag == "Strikeout" then
      el = pandoc.Strikeout({el})
    elseif tag == "Strong" then
      el = pandoc.Strong({el})
    elseif tag == "Underline" then
      el = pandoc.Underline({el})
    elseif tag == "Subscript" then
      el = pandoc.Subscript({el})
    else -- Then it is wrapped only in a Span
      return pandoc.Span({el}, pandoc.Attr("", classes))
    end
    return pandoc.Span({el}, pandoc.Attr("", classes)) -- wrap in a Span
  else
    return el
  end
end

-- Cleans the final returned object.
function clean(el)
  return removeEmptyWrapper(el)
end

-- Inserts a LineBreak element before the element given
-- as argument.
function insertLineBreakBefore(el)
  -- We are in the context where this is an unwrapped Div that
  -- contains only one element. It won't work for several elements.
  if el.t == nil and type(el) ~= "string" then
    els = { pandoc.LineBreak() }
    for i, elem in pairs(el) do
      table.insert(els, elem)
    end
    return els
  else
    return { pandoc.LineBreak(), el }
  end
end

local function getSeparatorElement(sep)
  if sep == "Space" then return pandoc.Space() end
  if sep == "SoftBreak" then return pandoc.SoftBreak() end
  if sep == "LineBreak" then return pandoc.LineBreak() end
  return pandoc.Str(sep)
end

-- Merge consecutive Block elements together in a wrapper element
-- specified as argument, such as "Div.class1" or "BlockQuote.class2"
-- Careful: this function is executed after applyMapping,
-- so keep in mind that this operation is applied as very last.
function operators.mergeAndJoin(blocks, map)
  for _, entry in ipairs(map) do
    local result = {}

    local selector
    local is_block_merge = false
    local is_inline_merge = false
    local merge_table = nil

    if entry.operation.merge then
      if type(entry.operation.merge) == "table" then
        merge_table = entry.operation.merge
        selector = merge_table.type or "Div"
      else
        selector = entry.operation.merge
      end
      is_block_merge = true
    elseif entry.operation.join then
      if type(entry.operation.join) == "table" then
        merge_table = entry.operation.join
        selector = merge_table.type or "Space"
      else
        selector = entry.operation.join
      end
      is_inline_merge = true
    end

    local inlineSeparatorTypes = {
      Space = true,
      SoftBreak = true,
      LineBreak = true
    }

    if is_block_merge or is_inline_merge then
      local wrapper_tag
      local selector_tag, _, wrapper_classes = utils.parseSelector(selector)
      local is_list_merge = (selector_tag == "BulletList" or selector_tag == "OrderedList")

      local i = 1
      while i <= #blocks do
        local matched_sel = utils.isMatchingSelectorList(blocks[i], entry._selectors)
        if matched_sel then
          local merged_items = pandoc.List()
          -- Start merging consecutive matches
          while i <= #blocks and utils.isMatchingSelectorList(blocks[i], entry._selectors) do
            local blk = blocks[i]

            -- If we're doing a list merge, each matching block becomes one list item
            if is_list_merge then
              -- Each list item must be a list of blocks
              local inner_blocks
              if blk.t == "Div" and #blk.content > 0 then
                inner_blocks = blk.content
              else
                inner_blocks = { blk }
              end
              merged_items:insert(inner_blocks)

            -- If we are doing an inline merge
            elseif is_inline_merge then
              if utils.isWrapper(blk) then
                wrapper_tag = blk.content[1].tag
              else
                wrapper_tag = blk.t or entry._tag or "Para" -- Fallbacks to the selector, then Para
              end
              merged_items:insert(blk)

            -- Normal merge: merge content of matching blocks
            else
              for _, inner in ipairs(blk.content or {}) do
                merged_items:insert(inner)
              end
            end
            i = i + 1
          end

          -- In the case of an inline merge, we must convert the blocks to inlines.
          if is_inline_merge then
            local sep
            if merge_table and merge_table.separator then
              sep = merge_table.separator
            else
              sep = selector_tag
            end
            merged_items = pandoc.Para(pu.blocks_to_inlines(merged_items, { getSeparatorElement(sep) }))
          else
            wrapper_tag = selector_tag
          end

          -- Now wrap merged content
          local wrapper_attr = pandoc.Attr("", wrapper_classes, {})
          local merged_el

          if is_list_merge then
            local list
            if wrapper_tag == "BulletList" then
              list = pandoc.BulletList(merged_items)
            else
              list = pandoc.OrderedList(merged_items)
            end
            -- Include attributes
            if #wrapper_classes > 0 then
              merged_el = pandoc.Div(list, getAttrWithWrapper(wrapper_attr, 1))
            else
              merged_el = list
            end
          else
            -- Non-list merging (Div, BlockQuote, etc.)
            if wrapper_tag == "Div" then
              merged_el = pandoc.Div(merged_items, wrapper_attr)
            else
              merged_el = blockToBlock(merged_items, wrapper_tag, wrapper_attr, false)
            end
          end

          -- Apply operation dict if merge/join is a table
          if merge_table then
            merged_el = operators.applyOperation(merged_el, entry, matched_sel, merge_table)
          end

          table.insert(result, merged_el)

        else
          table.insert(result, blocks[i])
          i = i + 1
        end
      end

      blocks = result
    end
  end

  return blocks
end

function operators.cut(doc)
  local current = {}
  local file_index = 1

  if not PANDOC_STATE.output_file then
    -- We only apply the cuts if an output file is specified
    -- as the stdout is for the uncut file.
    return doc
  end

  local outdir, basename
  if PANDOC_STATE.output_file and #PANDOC_STATE.output_file > 0 then
    outdir = PANDOC_STATE.output_file:match("(.+)/[^/]+$") or "."
    basename = PANDOC_STATE.output_file:match(".*/([^/]+)$") or PANDOC_STATE.output_file
    local name = basename:match("^(.*)%.([^%.]+)$")
    if name then
      basename = name
    end
  else
    outdir = "."
    basename = "cut"
  end

  local extension = utils.ext[FORMAT] or "txt"

  local function flush()
    if #current > 0 then
      local subdoc = pandoc.Pandoc(current, doc.meta)

      local slug = utils.firstNonEmptyHeader(current)
      if slug then
        slug = "_" .. utils.slugify(slug)
      else
        slug = ""
      end

      local filename = string.format("%s/%s_%03d%s.%s",
                                     outdir, basename, file_index, slug, extension)

      -- Follow this recommendation:
      -- https://fosstodon.org/@pandoc/114578758417418208
      local encoded_filename = pandoc.text.toencoding(filename)
      local encoded_outdir = pandoc.text.toencoding(outdir)

      utils.mkdir(outdir) -- creates the output directory if necessary
      local fh = io.open(encoded_filename, "w")

      
      fh:write(pandoc.write(subdoc, FORMAT, PANDOC_WRITER_OPTIONS))
      fh:close()

      file_index = file_index + 1
      current = {}
    end
  end

  for _, blk in ipairs(doc.blocks) do
    local is_cut = false
    for _, entry in ipairs(map) do
      if utils.isMatchingSelectorList(blk, entry._selectors)
         and entry.operation.cut then
        is_cut = true
        break
      end
    end

    if is_cut then
      flush()
    end
    table.insert(current, blk)
  end

  flush()

  return doc
end

function operators.applyOperation(el, entry, matched_sel, operation)
  local o = operation

  if o == nil then error("Missing operation in an entry.") end

  -- and apply the various operations
  if o.delete then
    return {}
  end
  if not o.empty then
    if isContentOneLineBreak(el) then
      return {}
    end
  end
  if o.simplify then
    el = simplify(el)
  end
  if o.classes ~= nil then
    el = applyClasses(el, matched_sel._classes, o.classes)
  end
  if o.attrs then
    applyAttrs(el, o.attrs)
  end
  if o.type then
    local ok, result = pcall(applyType, el, o.type)
    if ok then
      el = result
    else
      logging.warning("applyType: \"" .. matched_sel._raw .. "\": " .. result)
    end
  end
  if o.id then
     el = applyId(el)
  end
  if o.level then
    local ok, result = pcall(applyLevel, el, o.level)
    if ok then
      el = result
    else
      logging.warning("applyLevel: \"" .. matched_sel._raw .. "\": " .. result)
    end
  end
  if o.unwrap then
    el = unwrap(el)
  end
  if o.wrap then
    el = wrap(el, o.wrap)
  end
  el = clean(el)
  if o.br then
    el = insertLineBreakBefore(el)
  end
  return el
end


return operators