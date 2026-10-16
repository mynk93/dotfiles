-- Inline diagram rendering.
--
-- render-markdown highlights a ```mermaid fence but never draws it. This
-- renders the diagram to a PNG and displays it in the buffer over the Kitty
-- graphics protocol, which Ghostty implements and cmux passes through.
--
-- mermaid-cli drives a headless browser. It defaults to a puppeteer-managed
-- Chrome that must be downloaded separately and is version-pinned to the mmdc
-- build, so any version skew breaks rendering. Point it at the Chrome already
-- installed instead: no second browser, no pin to drift.

-- diagram.nvim shells out to `mmdc` directly, so the puppeteer config file
-- cannot be passed through. puppeteer honours this env var instead. Set here
-- rather than in .zshenv so other projects' puppeteer keeps its own pinned
-- browser, and only when Chrome exists: Chrome is not in the Brewfile, and
-- without it mmdc's own error is clearer than a bad path.
local CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if not vim.env.PUPPETEER_EXECUTABLE_PATH and vim.fn.executable(CHROME) == 1 then
  vim.env.PUPPETEER_EXECUTABLE_PATH = CHROME
end

require("image").setup({
  backend = "kitty",
  processor = "magick_cli",   -- ImageMagick CLI; avoids the magick luarock
  integrations = {},          -- diagram.nvim drives rendering, not the built-ins
  max_width_window_percentage = 80,
  window_overlap_clear_enabled = true,
  editor_only_render_when_focused = true,
  tmux_show_only_in_active_window = true,
})

require("diagram").setup({
  integrations = {
    require("diagram.integrations.markdown"),
  },
  renderer_options = {
    mermaid = {
      theme = "dark",         -- matches dracula better than the default
      background = "transparent",
      scale = 2,              -- retina; the default renders soft
    },
  },
})

vim.keymap.set("n", "<leader>D", function()
  require("diagram").show_diagram_hover()
end, { desc = "diagram: render under cursor" })
