-- atcoder-nim/make_runner.lua
-- AtCoder 用の make 実行ラッパー（非同期/同期）とローカルキーマップを管理する。

local M = {}
local buffer_ops = require("atcoder-nim.buffer_ops")

local output_buf = nil
local output_win = nil

local function write_source_buffer(bufnr)
  return buffer_ops.write_buffer_silently(bufnr, { silent_bang = true })
end

local function resolve_source_file(env_dir)
  local prefix = env_dir .. "/"

  local function from_buf(bufnr)
    if not buffer_ops.is_editable_loaded_buffer(bufnr) then
      return nil, nil
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then
      return nil, nil
    end

    local abs = vim.fn.fnamemodify(name, ":p")
    if abs:sub(1, #prefix) ~= prefix then
      return nil, nil
    end

    return abs:gsub("^" .. vim.pesc(prefix), ""), bufnr
  end

  local rel, bufnr = from_buf(vim.api.nvim_get_current_buf())
  if rel then
    return rel, bufnr
  end

  rel, bufnr = from_buf(vim.fn.bufnr("#"))
  if rel then
    return rel, bufnr
  end

  return nil, nil
end

local function ensure_output_log_buffer()
  if output_buf and vim.api.nvim_buf_is_valid(output_buf) and vim.bo[output_buf].buftype ~= "terminal" then
    return
  end

  output_buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, output_buf, "AtCoder Output")
  vim.bo[output_buf].buftype = "nofile"
  vim.bo[output_buf].bufhidden = "hide"
  vim.bo[output_buf].swapfile = false
  vim.bo[output_buf].filetype = "log"
end

local function ensure_output_window()
  local previous_win = vim.api.nvim_get_current_win()
  local height = math.max(8, math.floor(vim.o.lines * 0.30))

  if not (output_win and vim.api.nvim_win_is_valid(output_win)) then
    output_win = nil
    if output_buf and vim.api.nvim_buf_is_valid(output_buf) then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == output_buf then
          output_win = win
          break
        end
      end
    end
  end

  if not output_win then
    vim.cmd("botright split")
    output_win = vim.api.nvim_get_current_win()
    if output_buf and vim.api.nvim_buf_is_valid(output_buf) then
      vim.api.nvim_win_set_buf(output_win, output_buf)
    end
  elseif output_buf and vim.api.nvim_buf_is_valid(output_buf)
    and vim.api.nvim_win_get_buf(output_win) ~= output_buf
  then
    vim.api.nvim_win_set_buf(output_win, output_buf)
  end

  vim.api.nvim_win_set_height(output_win, height)
  vim.api.nvim_set_current_win(previous_win)
end

local function setup_output_terminal_keymaps(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local opts = { buffer = bufnr, silent = true }
  vim.keymap.set("t", "<PageUp>", [[<C-\><C-n><C-b>]], opts)
  vim.keymap.set("t", "<PageDown>", [[<C-\><C-n><C-f>]], opts)
  vim.keymap.set("t", "<kPageUp>", [[<C-\><C-n><C-b>]], opts)
  vim.keymap.set("t", "<kPageDown>", [[<C-\><C-n><C-f>]], opts)
  vim.keymap.set("t", "<C-b>", [[<C-\><C-n><C-b>]], opts)
  vim.keymap.set("t", "<C-f>", [[<C-\><C-n><C-f>]], opts)
  vim.keymap.set("n", "<PageUp>", "<C-b>", opts)
  vim.keymap.set("n", "<PageDown>", "<C-f>", opts)
  vim.keymap.set("n", "<kPageUp>", "<C-b>", opts)
  vim.keymap.set("n", "<kPageDown>", "<C-f>", opts)
end

local function follow_output_tail()
  if not (output_win and vim.api.nvim_win_is_valid(output_win)) then
    return
  end
  if not (output_buf and vim.api.nvim_buf_is_valid(output_buf)) then
    return
  end

  local last = vim.api.nvim_buf_line_count(output_buf)
  pcall(vim.api.nvim_win_set_cursor, output_win, { last, 0 })
end

local function append_output(lines, prefix)
  if not output_buf or not vim.api.nvim_buf_is_valid(output_buf) or not lines then
    return
  end

  local out = {}
  for _, line in ipairs(lines) do
    if line ~= "" then
      table.insert(out, (prefix or "") .. line)
    end
  end

  if #out == 0 then
    return
  end

  vim.api.nvim_buf_set_lines(output_buf, -1, -1, false, out)
  if output_win and vim.api.nvim_win_is_valid(output_win) then
    vim.api.nvim_win_set_cursor(output_win, { vim.api.nvim_buf_line_count(output_buf), 0 })
  end
end

local function start_output()
  ensure_output_log_buffer()
  ensure_output_window()
  vim.api.nvim_win_set_buf(output_win, output_buf)
  vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, {})
end

local function run_make_async(env_dir, cmd, opts)
  opts = opts or {}
  if opts.focus_output == nil then
    opts.focus_output = true
  end
  write_source_buffer(opts.source_bufnr)

  ensure_output_window()
  local previous_win = vim.api.nvim_get_current_win()

  if not output_win or not vim.api.nvim_win_is_valid(output_win) then
    vim.notify("出力ウィンドウを確保できませんでした", vim.log.levels.ERROR)
    return
  end

  output_buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, output_buf, "AtCoder Output")
  vim.bo[output_buf].bufhidden = "hide"
  vim.bo[output_buf].swapfile = false
  vim.api.nvim_win_set_buf(output_win, output_buf)

  vim.api.nvim_set_current_win(output_win)

  local wrapped =
    cmd
    .. "; code=$?; printf '\\n[exit %s]\\n' \"$code\"; exit \"$code\""

  local job = vim.fn.termopen({ "bash", "-lc", wrapped }, {
    cwd = env_dir,
    on_stdout = function()
      vim.schedule(follow_output_tail)
    end,
    on_stderr = function()
      vim.schedule(follow_output_tail)
    end,
    on_exit = function()
      vim.schedule(follow_output_tail)
    end,
  })

  if job <= 0 then
    vim.notify("make の非同期実行に失敗しました", vim.log.levels.ERROR)
  else
    pcall(function()
      vim.bo[output_buf].scrollback = 100000
    end)
    setup_output_terminal_keymaps(output_buf)
  end

  if opts.focus_output then
    if output_win and vim.api.nvim_win_is_valid(output_win) then
      vim.api.nvim_set_current_win(output_win)
      if opts.startinsert and job > 0 then
        vim.cmd("startinsert")
      end
    end
  elseif previous_win and vim.api.nvim_win_is_valid(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end
end

local function run_make_sync(env_dir, cmd)
  local bufnr = nil
  if type(cmd) == "table" then
    bufnr = cmd.source_bufnr
    cmd = cmd.command
  end

  write_source_buffer(bufnr)

  start_output()
  local output = vim.fn.systemlist({ "bash", "-lc", cmd .. " 2>&1" })
  if #output == 0 then
    append_output({ "(no output)" })
  else
    append_output(output)
  end

  append_output({ "", ("[exit %d]"):format(vim.v.shell_error) })
  if output_win and vim.api.nvim_win_is_valid(output_win) then
    vim.api.nvim_set_current_win(output_win)
  end
  return vim.v.shell_error == 0
end

local function copy_for_manual_submit(text)
  local text_lines = vim.split(text, "\n", { plain = true })

  local function try_osc52()
    local ok_osc52, osc52 = pcall(require, "vim.ui.clipboard.osc52")
    if not ok_osc52 or type(osc52.copy) ~= "function" then
      return false
    end

    local ok_copy = pcall(function()
      local copy_plus = osc52.copy("+")
      copy_plus(text_lines, "v")
    end)
    return ok_copy
  end

  if try_osc52() then
    return true
  end

  return false, "OSC52 copy に失敗しました（端末の OSC52 対応と設定を確認してください）"
end

local function get_nim_lsp_clients(bufnr)
  if not vim.lsp.get_clients then
    return {}
  end

  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "nim_langserver" })
  if #clients > 0 then
    return clients
  end

  return vim.lsp.get_clients({ bufnr = bufnr, name = "nim_ls" })
end

local function map_atcoder(lhs, rhs, desc)
  vim.keymap.set("n", "<LocalLeader>" .. lhs, rhs, { silent = true, desc = desc })
end

local function make_base_cmd(env_dir, target, file)
  return "make -s --no-print-directory -C " .. vim.fn.shellescape(env_dir)
    .. " " .. target .. " FILE=" .. vim.fn.shellescape(file)
end

local function register_make_async_action(env_dir, lhs, target, desc, action_opts)
  action_opts = action_opts or {}

  map_atcoder(lhs, function()
    local file, source_bufnr = resolve_source_file(env_dir)
    if not file then
      print("実行対象ファイルが見つかりません（コードバッファで実行してください）")
      return
    end

    local cmd = make_base_cmd(env_dir, target, file)

    if action_opts.use_clipboard_url then
      local url = vim.fn.getreg("+"):gsub("%s+", "")
      if url == "" then
        print("クリップボードが空です")
        return
      end
      cmd = cmd .. " URL=" .. vim.fn.shellescape(url)
    end

    local run_opts = { source_bufnr = source_bufnr }
    if action_opts.focus_output ~= nil then
      run_opts.focus_output = action_opts.focus_output
    end
    if action_opts.startinsert ~= nil then
      run_opts.startinsert = action_opts.startinsert
    end

    run_make_async(env_dir, cmd, run_opts)
  end, desc)
end

function M.setup(opts)
  opts = opts or {}
  local env_dir = opts.env_dir
  if type(env_dir) ~= "string" or env_dir == "" then
    return
  end

  register_make_async_action(env_dir, "c", "build", "AtCoder: コンパイル")
  register_make_async_action(env_dir, "r", "run", "AtCoder: コンパイル＋実行", {
    focus_output = true,
    startinsert = true,
  })
  register_make_async_action(env_dir, "s", "submit", "AtCoder: テスト＋提出")
  register_make_async_action(env_dir, "u", "submit", "AtCoder: URL 指定で提出", {
    use_clipboard_url = true,
  })

  map_atcoder("b", function()
    local file, source_bufnr = resolve_source_file(env_dir)
    if not file then
      print("実行対象ファイルが見つかりません（コードバッファで実行してください）")
      return
    end

    local cmd = "make -s --no-print-directory -C " .. vim.fn.shellescape(env_dir)
      .. " bundle FILE=" .. vim.fn.shellescape(file)
    local ok = run_make_sync(env_dir, { command = cmd, source_bufnr = source_bufnr })
    if not ok then
      print("bundle の実行に失敗しました")
      return
    end

    local target = env_dir .. "/bundled.txt"
    if vim.fn.filereadable(target) == 1 then
      local lines = vim.fn.readfile(target)
      local bundled_text = table.concat(lines, "\n") .. "\n"
      local copied, err = copy_for_manual_submit(bundled_text)
      if copied then
        print("バンドル結果をクリップボードにコピーしました")
      else
        print("コピーに失敗しました: " .. err)
        print("bundled.txt は生成済みです。必要ならファイルを開いて手動コピーしてください")
      end
    else
      print("エラー: " .. target .. " が見つかりません")
    end
  end, "AtCoder: バンドル＋コピー")

  map_atcoder("m", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = get_nim_lsp_clients(bufnr)
    if #clients == 0 then
      vim.notify("Nim LSP が未接続です", vim.log.levels.WARN)
      return
    end

    local client = clients[1]
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    params.level = 1

    client.request("extension/macroExpand", params, function(err, result)
      vim.schedule(function()
        if err then
          local msg = err.message or vim.inspect(err)
          vim.notify("macroExpand に失敗しました: " .. msg, vim.log.levels.WARN)
          return
        end
        if not result or not result.content or result.content == "" then
          vim.notify("macroExpand の結果が空です", vim.log.levels.INFO)
          return
        end

        local lines = vim.split(result.content, "\n", { plain = true })
        vim.lsp.util.open_floating_preview(lines, "nim", { border = "rounded" })
      end)
    end, bufnr)
  end, "AtCoder: nim マクロ展開")
end

return M
