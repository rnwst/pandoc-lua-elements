---@type boolean  Whether to execute this filter; overwritten by document front matter
local lua_elements = false

---@type table  Lua environment for to be executed Lua code elements from the document
local env = {}

-- We need to populate this environment with all the necessary globals.
for key, val in pairs(_G) do
   env[key] = val
end

---@type string
---Markdown source file content needed for source mapping, to be populated once
---we know the document contains Lua elements
local source = ''

---@type integer  Last Markdown source file position (row and column), used for source mapping purposes
local prev_source_pos = 0

---Check if the return value of a code block or inline code element is valid.
---@param return_val any
---@param level      ('Inline' | 'Block')
---@return true, (nil | Inline | Inlines | Block | Blocks)
---@overload fun(return_val: any, level: 'Inline' | 'Block'): false
local function check_return_val(return_val, level)
   local type = pandoc.utils.type(return_val)
   if level == 'Inline' and (type == 'number' or type == 'string') then
      return true, pandoc.Str(tostring(return_val))
   end
   -- Allowed return values are `nil` (only for Block element), an Inline or
   -- Block element, an empty table, and a list of Inline or Block elements.
   -- Note that the code element is deleted from the AST if it returns `nil`, a
   -- key difference to filter function behaviour (where `nil` has no effect).
   if level == 'Block' and type == 'nil' then return true, {} end -- `nil`
   if type == level then return true, return_val end -- single Inline or Block element
   if type == 'table' then return_val = pandoc.List(return_val) end
   if type == 'List' then -- List of Inline or Block elements
      local types = return_val:map(pandoc.utils.type)
      -- Elements must all be of same type. Note that the following condition covers empty Lists as well.
      if not types:find_if(function(t) return t ~= level end) then return true, return_val end
   end
   return false
end

local function error_msg_part(level, source_pos)
   return (level == 'Inline' and 'inline Code element' or 'CodeBlock')
      .. ' in '
      .. PANDOC_STATE.input_files[1]
      .. ' at '
      .. source_pos
end

---Warn about code error.
---@param source_pos string
---@param level ('Inline' | 'Block')
---@param err string
---@param kind ('exec' | 'parse')
local function warn_error(source_pos, level, err, kind)
   pandoc.log.warn(
      'The following error occurred while '
         .. (kind == 'exec' and 'executing' or 'parsing')
         .. ' the '
         .. error_msg_part(level, source_pos)
         .. ':\n'
         .. err
   )
end

---Warn about invalid return value.
---@param source_pos string
---@param level ('Inline' | 'Block')
---@param return_val any
local function warn_invalid_return_val(source_pos, level, return_val)
   pandoc.log.warn(
      'Received invalid return value `'
         .. tostring(return_val)
         .. '` from '
         .. error_msg_part(level, source_pos)
         .. '. Expected a block-level AST element'
         .. (level == 'Block' and ' or a list of Blocks.' or ', a list of Blocks, a number, or a string.')
   )
end

---Run Lua CodeBlock.
---@param elt CodeBlock
---@return Block | Blocks | {} | nil
local function code_block(elt)
   if elt.classes:includes('lua') then
      if elt.attributes.exec ~= 'false' then
         -- This is a very crude method to find the corresponding source position,
         -- but it should work most of the time. Note that this method doesn't work
         -- for indented code blocks.
         local start, finish = source:find(elt.text, prev_source_pos, true)
         if finish then prev_source_pos = finish + 1 end
         local line = 'line ' .. (start and ({ source:sub(1, start - 1):gsub('\n', '') })[2] + 1 or '??')
         local fun, err = load(elt.text, 'string', 't', env)
         local block_or_blocks
         if fun then
            local exec_succeeded, return_val = pcall(fun)
            if not exec_succeeded then
               warn_error(line, 'Block', return_val, 'exec')
            else
               local check_succeeded, adjusted_result = check_return_val(return_val, 'Block')
               if check_succeeded then
                  block_or_blocks = adjusted_result
               else
                  warn_invalid_return_val(line, 'Block', return_val)
               end
            end
         else
            ---@cast err string
            warn_error(line, 'Block', err, 'parse')
         end
         return block_or_blocks
      elseif elt.attributes.include == 'false' then
         return {} -- delete element from AST
      end
   end
end

---Evaluate a Lua expression or statement.
---@param expr string
---@return fun(): any
---@overload fun(expr: string): nil, string
local function eval(expr)
   local fun, err = load('return ' .. expr, 'string', 't', env)
   if not fun then
      -- Try as a statement if not an expression
      fun, err = load(expr, 'string', 't', env)
   end
   if not fun then
      ---@cast err string
      return nil, err
   end
   return fun
end

---Filter function for [Code](lua://Code) elements.
---@param elt Code
---@return Inline | Inlines | nil
local function code(elt)
   if elt.classes:includes('lua') and elt.attributes.exec ~= 'false' then
      -- Again, crude method to find source position...
      local start, finish = source:find('`' .. elt.text .. '`', prev_source_pos, true)
      prev_source_pos = finish or prev_source_pos
      local line = start and ({ source:sub(1, start - 1):gsub('\n', '') })[2] + 1 or '??'
      local column = start and #(({ source:sub(1, start - 1):find('\n([^\n]-)$') })[3] or source:sub(1, start - 1))
         or '??'
      local fun, err = eval(elt.text)
      local source_pos = 'line ' .. line .. ' column ' .. column
      if fun then
         local exec_succeeded, return_val = pcall(fun)
         if not exec_succeeded then
            warn_error(source_pos, 'Inline', return_val, 'exec')
         else
            local check_succeeded, adjusted_result = check_return_val(return_val, 'Inline')
            ---@cast adjusted_result (Inline | Inlines)
            if check_succeeded then
               return adjusted_result
            else
               warn_invalid_return_val(source_pos, 'Inline', return_val)
            end
         end
      else
         ---@cast err string
         warn_error(source_pos, 'Inline', err, 'parse')
      end
   end
end

return {
   {
      Meta = function(meta)
         if meta['lua-elements'] == true then
            lua_elements = true
            source = table.pack(pandoc.mediabag.fetch(PANDOC_STATE.input_files[1]))[2] or ''
            -- On Windoze, ensure Unix line endings. This is required, since
            -- pandoc uses Unix line endings when it parses CodeBlocks, and
            -- source mapping otherwise wouldn't work.
            source = source:gsub('\r', '')
         end
      end,
   },
   {
      Pandoc = function(doc)
         if lua_elements then
            return doc:walk {
               traverse = 'topdown',
               CodeBlock = code_block,
               Code = code,
            }
         end
      end,
   },
}
