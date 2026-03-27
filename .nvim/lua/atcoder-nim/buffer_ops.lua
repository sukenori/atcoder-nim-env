-- atcoder-nim/util.lua
-- project-local モジュール間で使う共通ユーティリティ。

local M = {}

function M.is_editable_loaded_buffer(bufnr)
  return bufnr
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.api.nvim_buf_is_loaded(bufnr)
    and vim.bo[bufnr].buftype == ""
end

function M.is_nim_source_buffer(bufnr)
  return M.is_editable_loaded_buffer(bufnr) and vim.bo[bufnr].filetype == "nim"
end

function M.buffer_abs_path(bufnr)
  if not M.is_editable_loaded_buffer(bufnr) then
    return nil
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end

  return vim.fn.fnamemodify(name, ":p")
end

function M.write_buffer_silently(bufnr, opts)
  if not M.is_editable_loaded_buffer(bufnr) then
    return false
  end

  opts = opts or {}
  local noautocmd = opts.noautocmd == true
  local silent_bang = opts.silent_bang ~= false

  local cmd = "write"
  if noautocmd then
    cmd = "noautocmd " .. cmd
  end
  if silent_bang then
    cmd = "silent! " .. cmd
  else
    cmd = "silent " .. cmd
  end

  return pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd(cmd)
  end)
end

return M
