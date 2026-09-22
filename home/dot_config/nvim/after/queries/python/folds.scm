;; extends

; Fold multi-line structured-log calls.
;
; nvim-treesitter's python folds.scm covers definitions and compound
; statements but not calls, so a wrapped slog.*() would stay expanded and
; keep bloating every function it appears in. Capturing the call node gives
; it a fold level of its own; lua/reader/foldtext.lua then renders the
; collapsed line with its `event=` value intact.
(call
  function: (attribute
    object: (identifier) @_obj
    (#eq? @_obj "slog"))) @fold

; Same treatment for logging/logger, so the reader behaves consistently in
; files that predate the slog wrapper.
(call
  function: (attribute
    object: (identifier) @_obj
    (#any-of? @_obj "logger" "logging" "log"))) @fold
