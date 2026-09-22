-- Custom fold text.
--
-- Neovim renders a closed fold with whatever `foldtext` returns, so the fold
-- can carry content pulled from *inside* the folded region. That is the whole
-- reason this config exists: a collapsed structured-log call should still show
-- which event it logs.
--
--   slog.info(                                slog.info(event="tool call failed", …)  5L
--       event="tool call failed",     ──▶
--       subsystem="harness",
--       call_id=self.call_id,
--   )

local M = {}

-- Keyword whose value identifies a folded call. Ordered: first hit wins.
local IDENTIFYING_KEYS = { "event", "name", "label" }

local function identifying_value(lines)
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

-- Pure: given a line range, produce the collapsed representation. Split out
-- from render() so it can be tested without driving a real fold.
function M.text(first, last, bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr or 0, first - 1, last, false)
  if #lines == 0 then
    return vim.fn.foldtext()
  end

  local head = lines[1]:gsub("%s+$", "")
  local count = last - first + 1
  local suffix = ("  %dL"):format(count)

  -- A fold whose first line ends in an open bracket is a wrapped call or
  -- literal. Splice the identifying kwarg in so the fold reads as a call.
  if head:match("[%(%[{]$") then
    local ident = identifying_value(lines)
    if ident then
      return head .. ident .. ", …)" .. suffix
    end
    return head .. "…)" .. suffix
  end

  return head .. " …" .. suffix
end

function M.render()
  return M.text(vim.v.foldstart, vim.v.foldend, 0)
end

return M
