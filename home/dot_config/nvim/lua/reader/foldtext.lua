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

-- Pure, so it can be tested without driving a real fold.
function M.identifying_value(lines)
  for _, key in ipairs(IDENTIFYING_KEYS) do
    for _, line in ipairs(lines) do
      local value = line:match(key .. '%s*=%s*(%b"")')
      if value then
        return key .. "=" .. value
      end
    end
  end
  return nil
end

-- True when the fold opens a wrapped call or literal, i.e. its first line ends
-- on an open bracket. Those are the folds worth summarising.
local function opens_bracket(text)
  return text:match("[%(%[{]%s*$") ~= nil
end

function M.handler(virt_text, lnum, end_lnum, width, truncate)
  local count = end_lnum - lnum
  local lines = vim.api.nvim_buf_get_lines(0, lnum - 1, end_lnum, false)

  local head_text = table.concat(vim.tbl_map(function(c) return c[1] end, virt_text))
  local ident = opens_bracket(head_text) and M.identifying_value(lines) or nil

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
