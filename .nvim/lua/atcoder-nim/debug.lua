-- atcoder-nim/debug.lua
-- Nim 向けの DAP 設定とデバッグ用ビルドコマンドを project-local で管理する。

local M = {}
local buffer_ops = require("atcoder-nim.buffer_ops")

local function ensure_codelldb_adapter(dap)
  -- global 側が未ロードでも project-local 単体で動くように保険で定義する。
  if dap.adapters.codelldb then
    return
  end

  dap.adapters.codelldb = {
    type = "server",
    port = "${port}",
    executable = {
      command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
      args = { "--port", "${port}" },
    },
  }
end

local function default_nim_program_path()
  local file = buffer_ops.buffer_abs_path(vim.api.nvim_get_current_buf())
  if not file then
    return vim.fn.getcwd() .. "/a.out"
  end

  local dir = vim.fs.dirname(file)
  local stem = vim.fn.fnamemodify(file, ":t:r")

  local candidate_same_stem = dir .. "/" .. stem
  if vim.fn.filereadable(candidate_same_stem) == 1 then
    return candidate_same_stem
  end

  local candidate_aout = dir .. "/a.out"
  if vim.fn.filereadable(candidate_aout) == 1 then
    return candidate_aout
  end

  return vim.fn.getcwd() .. "/a.out"
end

local function build_nim_debug_binary(env_dir, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not buffer_ops.is_editable_loaded_buffer(bufnr) then
    vim.notify("NimDebugBuild: invalid buffer", vim.log.levels.WARN)
    return nil
  end

  if not buffer_ops.is_nim_source_buffer(bufnr) then
    vim.notify("NimDebugBuild: current buffer is not a Nim file", vim.log.levels.WARN)
    return nil
  end

  local src_abs = buffer_ops.buffer_abs_path(bufnr)
  if not src_abs then
    vim.notify("NimDebugBuild: source path not found", vim.log.levels.WARN)
    return nil
  end

  if src_abs:sub(1, #env_dir + 1) ~= (env_dir .. "/") then
    vim.notify("NimDebugBuild: file is outside atcoder-nim-env", vim.log.levels.WARN)
    return nil
  end

  if vim.bo[bufnr].modified then
    buffer_ops.write_buffer_silently(bufnr, { silent_bang = true })
  end

  -- 出力は src と同じ場所に拡張子なし実行ファイルで作る。
  local out = vim.fs.dirname(src_abs) .. "/" .. vim.fn.fnamemodify(src_abs, ":t:r")
  local cmd = {
    "nim",
    "c",
    "--debugger:native",
    "-d:debug",
    "-o:" .. out,
    src_abs,
  }

  -- atcoder-nim-env 直下でコンパイルして、相対 include の挙動を安定させる。
  local result = vim.system(cmd, { text = true, cwd = env_dir }):wait()
  if result.code ~= 0 then
    local err = (result.stderr or ""):gsub("\n+$", "")
    if err == "" then
      err = "nim build failed"
    end
    vim.notify("NimDebugBuild failed: " .. err, vim.log.levels.ERROR)
    return nil
  end

  vim.notify("NimDebugBuild done: " .. out, vim.log.levels.INFO)
  return out
end

function M.setup(opts)
  opts = opts or {}
  local env_dir = opts.env_dir
  if type(env_dir) ~= "string" or env_dir == "" then
    return
  end

  local ok_dap, dap = pcall(require, "dap")
  if not ok_dap then
    return
  end

  ensure_codelldb_adapter(dap)

  dap.configurations.nim = {
    {
      name = "Debug Nim",
      type = "codelldb",
      request = "launch",
      program = function()
        return vim.fn.input("Path to executable: ", default_nim_program_path(), "file")
      end,
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
    },
  }

  pcall(vim.api.nvim_del_user_command, "NimDebugBuild")
  vim.api.nvim_create_user_command("NimDebugBuild", function(opts2)
    local target = opts2.args ~= "" and vim.fn.fnamemodify(opts2.args, ":p") or nil
    if target then
      local b = vim.fn.bufnr(target, true)
      if b ~= -1 then
        build_nim_debug_binary(env_dir, b)
        return
      end
    end
    build_nim_debug_binary(env_dir, vim.api.nvim_get_current_buf())
  end, {
    nargs = "?",
    complete = "file",
    desc = "Build current Nim file with debug info",
  })

  pcall(vim.api.nvim_del_user_command, "NimDebugRun")
  vim.api.nvim_create_user_command("NimDebugRun", function()
    local out = build_nim_debug_binary(env_dir, vim.api.nvim_get_current_buf())
    if not out then
      return
    end

    dap.run({
      name = "Debug Nim (build+run)",
      type = "codelldb",
      request = "launch",
      program = out,
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
    })
  end, {
    desc = "Build current Nim file and start debugger",
  })

  vim.keymap.set("n", "<Leader>nb", "<Cmd>NimDebugBuild<CR>", {
    silent = true,
    desc = "Nim: debug build",
  })
  vim.keymap.set("n", "<Leader>nd", "<Cmd>NimDebugRun<CR>", {
    silent = true,
    desc = "Nim: debug build + run",
  })
end

return M
