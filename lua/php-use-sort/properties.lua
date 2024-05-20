local utils = require("php-use-sort.utils")

local Properties = {}

local ts = vim.treesitter
local ts_utils = require("nvim-treesitter.ts_utils")

local function get_comments(property, range)
  local node = ts_utils.get_previous_node(property, false, false)
  local table_lines = {}

  if node == nil or node:type() ~= "comment" then
    return table_lines
  end

  local start_row, _, end_row, _ = node:range()
  range.min = math.min(range.min, start_row + 1)
  range.max = math.max(range.max, end_row + 1)

  local buff_lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)
  for _, buf_line in ipairs(buff_lines) do
    table.insert(table_lines, buf_line)
  end

  return table_lines
end

local function extract_properties_declarations(class_body)
  local range = { min = math.huge, max = 0 }
  local lines = {}

  local property_query = [[
    (property_declaration
        (visibility_modifier) @vis
        (static_modifier)? @modifier
        (property_element) @property_element
    ) @prop
    (const_declaration
        (visibility_modifier) @vis
        "const" @modifier
        (const_element) @property_element
    ) @prop
    ]]

  local query = ts.query.parse("php", property_query)

  for _, match, _ in query:iter_matches(class_body, 0) do
    local line = { "", "", "", "", "", "" }
    for id, node in pairs(match) do
      line[id] = ts.get_node_text(node, 0)
      if id == 4 then
        local start_row, _, end_row, _ = node:range()
        range.min = math.min(range.min, start_row + 1)
        range.max = math.max(range.max, end_row + 1)

        local table_lines = get_comments(node, range)
        local buff_lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)
        for _, buf_line in ipairs(buff_lines) do
          table.insert(table_lines, buf_line)
        end
        line["raw"] = table_lines
      end
    end
    table.insert(lines, line)
  end

  return lines, range
end

local function compare_properties(a, b)
  -- Sort by statics first
  if a[2] == "const" and b[2] ~= "const" then
    return true
  elseif a[2] ~= "const" and b[2] == "const" then
    return false
  end

  if a[2] == "static" and b[2] ~= "static" then
    return true
  elseif a[2] ~= "static" and b[2] == "static" then
    return false
  end

  -- If both are static or both are not static, sort by access modifier
  local access_order = { ["private"] = 1, ["protected"] = 2, ["public"] = 3 }
  if access_order[a[1]] ~= access_order[b[1]] then
    return access_order[a[1]] < access_order[b[1]]
  end

  -- If access modifiers are the same, sort by property name
  return a[3] < b[3]
end

local function sort_properties(lines, range, options)
  if not options.enable then
    return
  end

  local copied_table = utils.tablecopy(lines)

  table.sort(lines, compare_properties)

  if not utils.table_changed(copied_table, lines) then
    return
  end

  if options.space == "between properties" then
    local lines_with = {}
    for _, line in ipairs(lines) do
      table.insert(lines_with, { raw = line.raw })
      table.insert(lines_with, { raw = { "" } })
    end
    lines = lines_with
  end

  if options.space == "between types" then
    local type = lines[1][1]
    local lines_with = {}
    for _, line in ipairs(lines) do
      if type ~= line[1] then
        type = line[1]
        table.insert(lines_with, { raw = { "" } })
      end
      table.insert(lines_with, { raw = line.raw })
    end
    lines = lines_with
  end

  utils.update_buffer(range, lines)
end

function Properties.sort(root, lang, options)
  local query = ts.query.parse(lang, "((class_declaration) @class)")
  local properties_info = {}

  for _, node, _, _ in query:iter_captures(root, 0) do
    if node:type() == "class_declaration" then
      local class_lines, class_range = extract_properties_declarations(node)
      if next(class_lines) then
        table.insert(properties_info, { properties = class_lines, range = class_range })
      end
    end
  end

  for i = #properties_info, 1, -1 do
    local class_info = properties_info[i]
    local class_lines = class_info.properties
    local class_range = class_info.range

    sort_properties(class_lines, class_range, options)
  end
end

return Properties
