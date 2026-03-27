-- atcoder-nim/format.lua
-- Nim ファイルの自動整形を project-local で管理する。

local M = {}
local buffer_ops = require("atcoder-nim.buffer_ops")

local function pick_nim_formatter()
  -- nph は整形ルールが強めなので優先。
  if vim.fn.executable("nph") == 1 then
    return "nph"
  end
  if vim.fn.executable("nimpretty") == 1 then
    return "nimpretty"
  end
  return nil
end

local function refresh_nim_buffer_after_external_write(bufnr)
  -- 外部フォーマッタが直接ファイルを書き換えるため、バッファを同期する。
  pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd("silent checktime")
  end)

  -- semantic token が有効な場合、色付けの追従を促す。
  if vim.lsp and vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.force_refresh then
    pcall(vim.lsp.semantic_tokens.force_refresh, bufnr)
  end
end

local function format_current_nim(bufnr)
  if not buffer_ops.is_nim_source_buffer(bufnr) or vim.b[bufnr].nim_formatting then
    return
  end

  local file = buffer_ops.buffer_abs_path(bufnr)
  local formatter = pick_nim_formatter()
  if not file or not formatter then
    return
  end

  vim.b[bufnr].nim_formatting = true
  local view = vim.fn.winsaveview()

  -- 保存前の差分を反映してから整形する。
  if vim.bo[bufnr].modified then
    buffer_ops.write_buffer_silently(bufnr, { noautocmd = true, silent_bang = false })
  end

  vim.fn.system({ formatter, file })
  if vim.v.shell_error ~= 0 then
    vim.notify("Nim format failed: " .. formatter, vim.log.levels.WARN)
    vim.b[bufnr].nim_formatting = false
    return
  end

  refresh_nim_buffer_after_external_write(bufnr)
  vim.fn.winrestview(view)
  vim.b[bufnr].nim_formatting = false
end

function M.setup()
  local group = vim.api.nvim_create_augroup("AtcoderNimAutoFormat", { clear = true })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    pattern = "*.nim",
    callback = function(ev)
      format_current_nim(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.nim",
    callback = function(ev)
      format_current_nim(ev.buf)
    end,
  })

  pcall(vim.api.nvim_del_user_command, "NimFormat")
  vim.api.nvim_create_user_command("NimFormat", function()
    format_current_nim(vim.api.nvim_get_current_buf())
  end, { desc = "Format current Nim file in atcoder-nim-env" })
end

return M
