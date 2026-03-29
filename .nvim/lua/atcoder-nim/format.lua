-- atcoder-nim/format.lua
-- Nim ファイルの自動整形を project-local で管理する。

local M = {}
local buffer_ops = require("atcoder-nim.buffer_ops")

local function resolve_cmd_path(cmd)
  if vim.fn.executable(cmd) == 1 then
    local path = vim.fn.exepath(cmd)
    if path ~= nil and path ~= "" then
      return path
    end
    return cmd
  end
  return nil
end

local function first_existing(paths)
  for _, p in ipairs(paths) do
    if p ~= nil and p ~= "" and vim.fn.executable(p) == 1 then
      return p
    end
  end
  return nil
end

local function pick_nim_formatter()
  -- nph は整形ルールが強めなので優先。
  local direct = first_existing({
    resolve_cmd_path("nph"),
    resolve_cmd_path("nimpretty"),
  })
  if direct then
    return direct
  end

  -- PATH が薄い環境向けに、nim の隣と choosenim/toolchain を探索する。
  local nim = vim.fn.exepath("nim")
  if nim ~= nil and nim ~= "" then
    local bindir = vim.fn.fnamemodify(nim, ":h")
    local alongside = first_existing({
      bindir .. "/nph",
      bindir .. "/nimpretty",
    })
    if alongside then
      return alongside
    end
  end

  local home = vim.env.HOME or ""
  if home ~= "" then
    local from_home = first_existing({
      home .. "/.nimble/bin/nph",
      home .. "/.nimble/bin/nimpretty",
    })
    if from_home then
      return from_home
    end

    local toolchain_nph = vim.fn.glob(home .. "/.choosenim/toolchains/*/bin/nph", false, true)
    local toolchain_pretty = vim.fn.glob(home .. "/.choosenim/toolchains/*/bin/nimpretty", false, true)
    local from_toolchain = first_existing(vim.list_extend(toolchain_nph, toolchain_pretty))
    if from_toolchain then
      return from_toolchain
    end
  end

  return nil
end

local function formatter_debug_info()
  local candidates = {
    resolve_cmd_path("nph") or "",
    resolve_cmd_path("nimpretty") or "",
    (vim.fn.exepath("nim") ~= "" and (vim.fn.fnamemodify(vim.fn.exepath("nim"), ":h") .. "/nph")) or "",
    (vim.fn.exepath("nim") ~= "" and (vim.fn.fnamemodify(vim.fn.exepath("nim"), ":h") .. "/nimpretty")) or "",
    ((vim.env.HOME or "") ~= "" and ((vim.env.HOME or "") .. "/.nimble/bin/nph")) or "",
    ((vim.env.HOME or "") ~= "" and ((vim.env.HOME or "") .. "/.nimble/bin/nimpretty")) or "",
  }

  local lines = {
    "Nim formatter debug:",
    "selected: " .. (pick_nim_formatter() or "<none>"),
  }

  for _, c in ipairs(candidates) do
    if c ~= "" then
      table.insert(lines, string.format("- %s (exec=%d)", c, vim.fn.executable(c)))
    end
  end

  return table.concat(lines, "\n")
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

local function format_current_nim(bufnr, opts)
  opts = opts or {}

  if not buffer_ops.is_nim_source_buffer(bufnr) or vim.b[bufnr].nim_formatting then
    return
  end

  local file = buffer_ops.buffer_abs_path(bufnr)
  local formatter = pick_nim_formatter()
  if not file or not formatter then
    if not formatter and not vim.g.atcoder_nim_formatter_missing_warned then
      vim.g.atcoder_nim_formatter_missing_warned = true
      vim.notify("Nim formatter not found (tried nph/nimpretty).", vim.log.levels.WARN)
    end
    return
  end

  vim.b[bufnr].nim_formatting = true
  local view = vim.fn.winsaveview()

  -- 保存前の差分を反映してから整形する。
  if vim.bo[bufnr].modified and not opts.skip_presave_write then
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

  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    pattern = "*.nim",
    callback = function(ev)
      format_current_nim(ev.buf, { skip_presave_write = true })
    end,
  })

  pcall(vim.api.nvim_del_user_command, "NimFormat")
  vim.api.nvim_create_user_command("NimFormat", function()
    format_current_nim(vim.api.nvim_get_current_buf())
  end, { desc = "Format current Nim file in atcoder-nim-env" })

  pcall(vim.api.nvim_del_user_command, "NimFormatInfo")
  vim.api.nvim_create_user_command("NimFormatInfo", function()
    vim.notify(formatter_debug_info(), vim.log.levels.INFO)
  end, { desc = "Show resolved Nim formatter in atcoder-nim-env" })
end

return M
