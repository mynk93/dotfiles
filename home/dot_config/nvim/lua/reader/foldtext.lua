-- Fold text.
--
-- A collapsed structured-log call should still say which event it logs:
--
--   slog.info(                          slog.info(event="tool call failed", …) 󰁂 5
--       event="tool call failed",  ──▶
--       subsystem="harness",
--   )
--
-- Rendered through nvim-ufo's fold_virt_text_handler rather than `foldtext`,
-- which hands us the first line already tokenized as {text, hlGroup} chunks.
-- The collapsed line therefore keeps its syntax colours; a plain `foldtext`
-- string would flatten them to one highlight group.

local M = {}

-- Keyword whose value identifies a folded call. Ordered: first hit wins.
local IDENTIFYING_KEYS = { "event", "name", "label" }

-- True when the fold opens a wrapped call: the first line ends on `name(`.
-- A wrapped `def f(` or `class C(` ends the same way but is a signature, and
-- summarising it would lift an event out of the body below.
local function opens_call(head)
  if head:match("^%s*def%s") or head:match("^%s*async%s+def%s") or head:match("^%s*class%s") then
    return false
  end
  return head:match("[%w_%.]%(%s*$") ~= nil
end

-- Pure, so it can be tested without driving a real fold. lines[1] is the
-- fold's first line. Only keyword arguments that start a line at the call's
-- own argument indent count, so `event=` inside a nested call is skipped. The
-- scan stops at the closing bracket (the first line back at the head's
-- indent): a fold headed by `with lock(` also holds the block's body.
function M.identifying_value(lines)
  if not lines[1] or not opens_call(lines[1]) then
    return nil
  end
  local head_indent = #lines[1]:match("^%s*")
  local args = {}
  for i = 2, #lines do
    if lines[i]:match("%S") and #lines[i]:match("^%s*") <= head_indent then
      break
    end
    args[#args + 1] = lines[i]
  end
  local first_arg = vim.iter(args):find(function(l) return l:match("%S") end)
  if not first_arg then
    return nil
  end
  local arg_indent = first_arg:match("^%s*")
  for _, key in ipairs(IDENTIFYING_KEYS) do
    for _, line in ipairs(args) do
      local value = line:match("^" .. arg_indent .. key .. '%s*=%s*(%b"")')
      if value then
        return key .. "=" .. value
      end
    end
  end
  return nil
end

function M.handler(virt_text, lnum, end_lnum, width, truncate)
  local count = end_lnum - lnum
  local lines = vim.api.nvim_buf_get_lines(0, lnum - 1, end_lnum, false)

  local ident = M.identifying_value(lines)

  local suffix = ident and ("%s, …)  󰁂 %d"):format(ident, count) or ("  󰁂 %d"):format(count)
  local suffix_width = vim.fn.strdisplaywidth(suffix)
  local target = width - suffix_width

  local out, cur = {}, 0
  for _, chunk in ipairs(virt_text) do
    local text, hl = chunk[1], chunk[2]
    local w = vim.fn.strdisplaywidth(text)
    if target > cur + w then
      table.insert(out, chunk)
      cur = cur + w
    else
      text = truncate(text, target - cur)
      table.insert(out, { text, hl })
      break
    end
  end

  table.insert(out, { suffix, "Comment" })
  return out
end

return M
