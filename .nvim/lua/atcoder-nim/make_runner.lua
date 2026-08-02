-- atcoder-nim/make_runner.lua
-- AtCoder用のmake実行ラッパーとローカルキーマップ。

local M = {}

local output_buf = nil
local output_win = nil
local debug_log_ns = vim.api.nvim_create_namespace("atcoder_debug_log")

local function write_source_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  if vim.bo[bufnr].modified then
    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.cmd, "silent! write!")
    end)
  end
end

local function is_editable_loaded_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return false end
  if not vim.api.nvim_buf_is_loaded(bufnr) then return false end
  local bt = vim.bo[bufnr].buftype
  return bt == "" or bt == "acwrite"
end

local function resolve_source_file(project_root)
  local prefix = project_root .. "/"

  local function from_buf(bufnr)
    if not is_editable_loaded_buffer(bufnr) then return nil, nil end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then return nil, nil end

    local abs = vim.fn.fnamemodify(name, ":p")
    if abs:sub(1, #prefix) ~= prefix then return nil, nil end

    return abs:gsub("^" .. vim.pesc(prefix), ""), bufnr
  end

  local rel, bufnr = from_buf(vim.api.nvim_get_current_buf())
  if rel then return rel, bufnr end

  rel, bufnr = from_buf(vim.fn.bufnr("#"))
  if rel then return rel, bufnr end

  return nil, nil
end

local function ensure_output_window()
  local previous_win = vim.api.nvim_get_current_win()
  local height = math.max(8, math.floor(vim.o.lines * 0.30))

  if not (output_win and vim.api.nvim_win_is_valid(output_win)) then
    output_win = nil
    if output_buf and vim.api.nvim_buf_is_valid(output_buf) then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == output_buf then
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
      and vim.api.nvim_win_get_buf(output_win) ~= output_buf then
    vim.api.nvim_win_set_buf(output_win, output_buf)
  end

  vim.api.nvim_win_set_height(output_win, height)

  if previous_win and vim.api.nvim_win_is_valid(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end
end

local function setup_output_terminal_keymaps(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  local opts = { buffer = bufnr, silent = true }
  vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], opts)
  vim.keymap.set("n", "q", "<Cmd>close<CR>", opts)
end

local function follow_output_tail()
  if not (output_win and vim.api.nvim_win_is_valid(output_win)) then return end
  if not (output_buf and vim.api.nvim_buf_is_valid(output_buf)) then return end

  local last = vim.api.nvim_buf_line_count(output_buf)
  pcall(vim.api.nvim_win_set_cursor, output_win, { last, 0 })
end

local function run_make_async(project_root, cmd, opts)
  opts = opts or {}
  if opts.focus_output == nil then opts.focus_output = true end

  write_source_buffer(opts.source_bufnr)
  ensure_output_window()

  local previous_win = vim.api.nvim_get_current_win()

  output_buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, output_buf, "AtCoder Output")
  vim.bo[output_buf].bufhidden = "hide"
  vim.bo[output_buf].swapfile = false
  vim.api.nvim_win_set_buf(output_win, output_buf)
  vim.api.nvim_set_current_win(output_win)

  local wrapped = cmd .. "; code=$?; printf '\\n[exit %s]\\n' \"$code\"; exit \"$code\""

  local job = vim.fn.termopen({ "bash", "-lc", wrapped }, {
    cwd = project_root,
    on_stdout = function() vim.schedule(follow_output_tail) end,
    on_stderr = function() vim.schedule(follow_output_tail) end,
    on_exit = function() vim.schedule(follow_output_tail) end,
  })

  if job <= 0 then
    vim.notify("makeの非同期実行に失敗しました", vim.log.levels.ERROR)
    return
  end

  pcall(function()
    vim.bo[output_buf].scrollback = 100000
  end)
  setup_output_terminal_keymaps(output_buf)

  if opts.focus_output then
    vim.api.nvim_set_current_win(output_win)
    if opts.startinsert then vim.cmd("startinsert") end
  elseif previous_win and vim.api.nvim_win_is_valid(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end
end

local function resolve_tmux_companion_pane()
  if not vim.env.TMUX or vim.env.TMUX == "" then return nil end
  if not vim.env.TMUX_PANE or vim.env.TMUX_PANE == "" then return nil end

  local info = vim.fn.systemlist({
    "tmux", "display-message", "-p", "-t", vim.env.TMUX_PANE,
    "#{window_id} #{pane_index}",
  })
  if vim.v.shell_error ~= 0 or #info == 0 then return nil end

  local window_id, current_index = info[1]:match("^(%S+)%s+(%d+)$")
  if not window_id or not current_index then return nil end

  local panes = vim.fn.systemlist({
    "tmux", "list-panes", "-t", window_id, "-F", "#{pane_index}",
  })
  if vim.v.shell_error ~= 0 then return nil end

  if #panes < 2 then
    vim.fn.system({ "tmux", "split-window", "-v", "-t", window_id })
    if vim.v.shell_error ~= 0 then return nil end

    panes = vim.fn.systemlist({
      "tmux", "list-panes", "-t", window_id, "-F", "#{pane_index}",
    })
    if vim.v.shell_error ~= 0 then return nil end
  end

  for _, index in ipairs(panes) do
    if index ~= current_index then
      return window_id .. "." .. index
    end
  end

  return nil
end

local function send_to_tmux_pane(target, command)
  vim.fn.system({ "tmux", "send-keys", "-t", target, "C-c" })
  if vim.v.shell_error ~= 0 then return false end

  -- -lはliteral送信。シェル文字列をtmuxのキー名として解釈させない。
  vim.fn.system({ "tmux", "send-keys", "-t", target, "-l", command })
  if vim.v.shell_error ~= 0 then return false end

  vim.fn.system({ "tmux", "send-keys", "-t", target, "Enter" })
  return vim.v.shell_error == 0
end

local function run_make_in_tmux_companion(project_root, cmd, source_bufnr)
  local target = resolve_tmux_companion_pane()
  if not target then return false end

  write_source_buffer(source_bufnr)

  local command = "cd " .. vim.fn.shellescape(project_root) .. " && " .. cmd
  if not send_to_tmux_pane(target, command) then
    vim.notify("tmux companion paneへのmake実行に失敗しました", vim.log.levels.ERROR)
    return false
  end

  return true
end

local function run_make_sync(project_root, cmd)
  local bufnr = nil
  local show_output = true

  if type(cmd) == "table" then
    bufnr = cmd.source_bufnr
    show_output = cmd.show_output ~= false
    cmd = cmd.command
  end

  write_source_buffer(bufnr)
  local output = vim.fn.systemlist({ "bash", "-lc", cmd .. " 2>&1" })
  local exit_code = vim.v.shell_error

  if show_output and #output > 0 then
    vim.notify(table.concat(output, "\n"), vim.log.levels.INFO)
  end

  return exit_code == 0, output, exit_code
end

local function copy_for_manual_submit(text)
  local lines = vim.split(text, "\n", { plain = true })

  local function try_osc52_direct()
    if not vim.base64 or type(vim.base64.encode) ~= "function" then
      return false, nil
    end

    local ok, encoded = pcall(vim.base64.encode, text)
    if not ok or not encoded or encoded == "" then return false, nil end

    local esc = string.char(27)
    local bel = string.char(7)
    local sequence = esc .. "]52;c;" .. encoded .. bel

    if vim.env.TMUX and vim.env.TMUX ~= "" then
      sequence = esc .. "Ptmux;" .. sequence:gsub(esc, esc .. esc) .. esc .. "\\"
    end

    local tty = io.open("/dev/tty", "w")
    if not tty then return false, nil end

    tty:write(sequence)
    tty:flush()
    tty:close()
    return true, "osc52-direct"
  end

  local function try_osc52()
    local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
    if not ok or type(osc52.copy) ~= "function" then return false, nil end

    local copied = pcall(function()
      osc52.copy("+")(lines, "v")
    end)
    if copied then return true, "osc52" end
    return false, nil
  end

  local function try_external_clipboard()
    local candidates = {
      { "clip.exe" },
      { "wl-copy" },
      { "xclip", "-selection", "clipboard" },
      { "xsel", "--clipboard", "--input" },
      { "pbcopy" },
    }

    for _, command in ipairs(candidates) do
      if vim.fn.executable(command[1]) == 1 then
        vim.fn.system(command, text)
        if vim.v.shell_error == 0 then return true, command[1] end
      end
    end

    return false, nil
  end

  local ok, detail = try_osc52_direct()
  if ok then return true, detail end

  ok, detail = try_osc52()
  if ok then return true, detail end

  ok, detail = try_external_clipboard()
  if ok then return true, detail end

  return false, "クリップボード連携に失敗しました"
end

local function get_nim_lsp_clients(bufnr)
  if not vim.lsp.get_clients then return {} end
  return vim.lsp.get_clients({ bufnr = bufnr, name = "nim_langserver" })
end

local function map_atcoder(lhs, rhs, desc)
  vim.keymap.set("n", "<Leader>" .. lhs, rhs, {
    silent = true,
    desc = desc,
  })
end

local function make_base_cmd(project_root, target, file)
  return "make -s --no-print-directory -C "
    .. vim.fn.shellescape(project_root)
    .. " " .. target
    .. " FILE=" .. vim.fn.shellescape(file)
end

local function register_make_async_action(project_root, lhs, target, desc, action_opts)
  action_opts = action_opts or {}

  map_atcoder(lhs, function()
    local file, source_bufnr = resolve_source_file(project_root)
    if not file then
      vim.notify("実行対象ファイルが見つかりません", vim.log.levels.WARN)
      return
    end

    local command = make_base_cmd(project_root, target, file)

    if action_opts.use_clipboard_url then
      local url = vim.fn.getreg("+"):gsub("%s+", "")
      if url == "" then
        vim.notify("クリップボードが空です", vim.log.levels.WARN)
        return
      end
      command = command .. " URL=" .. vim.fn.shellescape(url)
    end

    local run_opts = { source_bufnr = source_bufnr }
    if action_opts.focus_output ~= nil then
      run_opts.focus_output = action_opts.focus_output
    end
    if action_opts.startinsert ~= nil then
      run_opts.startinsert = action_opts.startinsert
    end

    if not run_make_in_tmux_companion(project_root, command, source_bufnr) then
      run_make_async(project_root, command, run_opts)
    end
  end, desc)
end

local function colorize_debug_log(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_set_hl(0, "AtCoderDebugInfo", { fg = "#61AFEF", bold = true })
  vim.api.nvim_set_hl(0, "AtCoderDebugSuccess", { fg = "#98C379", bold = true })
  vim.api.nvim_set_hl(0, "AtCoderDebugFailure", { fg = "#E06C75", bold = true })

  vim.api.nvim_buf_clear_namespace(bufnr, debug_log_ns, 0, -1)

  for index, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:sub(1, 6) == "[INFO]" then
      vim.api.nvim_buf_add_highlight(
        bufnr, debug_log_ns, "AtCoderDebugInfo", index - 1, 0, 6
      )
    elseif line:sub(1, 9) == "[SUCCESS]" then
      vim.api.nvim_buf_add_highlight(
        bufnr, debug_log_ns, "AtCoderDebugSuccess", index - 1, 0, 9
      )
    elseif line:sub(1, 9) == "[FAILURE]" then
      vim.api.nvim_buf_add_highlight(
        bufnr, debug_log_ns, "AtCoderDebugFailure", index - 1, 0, 9
      )
    end
  end
end

local function find_window_showing_file(path)
  local target = vim.fn.fnamemodify(path, ":p")

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if name ~= "" and vim.fn.fnamemodify(name, ":p") == target then
      return win
    end
  end

  return nil
end

local function open_debug_log(log_path, source_win)
  local existing = find_window_showing_file(log_path)

  if existing then
    vim.api.nvim_set_current_win(existing)
    vim.cmd("edit!")
    colorize_debug_log(vim.api.nvim_get_current_buf())
    vim.cmd("normal! G")
    return
  end

  if source_win and vim.api.nvim_win_is_valid(source_win) then
    vim.api.nvim_set_current_win(source_win)
  end

  vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(log_path))
  vim.cmd("edit!")
  colorize_debug_log(vim.api.nvim_get_current_buf())
  vim.cmd("normal! G")
end

local function register_debug_action(project_root, lhs)
  map_atcoder(lhs, function()
    local file, source_bufnr = resolve_source_file(project_root)
    if not file then
      vim.notify("実行対象ファイルが見つかりません", vim.log.levels.WARN)
      return
    end

    local tmux_target = resolve_tmux_companion_pane()
    if not tmux_target then
      vim.notify("tmux companion paneを取得できませんでした", vim.log.levels.ERROR)
      return
    end

    write_source_buffer(source_bufnr)

    local source_win = vim.api.nvim_get_current_win()
    local done_file = project_root .. "/.nvim-debug-done"
    vim.fn.delete(done_file)

    local make_command = make_base_cmd(project_root, "debug", file)

    local command =
      "cd " .. vim.fn.shellescape(project_root)
      .. " && rm -f .nvim-debug-done"
      .. " && " .. make_command
      .. "; code=$?"
      .. "; printf '\\n[debug] debug.log を出力しました\\n[exit %s]\\n' \"$code\""
      .. "; printf '%s\\n' \"$code\" > .nvim-debug-done"

    if not send_to_tmux_pane(tmux_target, command) then
      vim.notify("tmux companion paneへのdebug実行に失敗しました", vim.log.levels.ERROR)
      return
    end

    local timer = vim.uv.new_timer()

    timer:start(100, 100, vim.schedule_wrap(function()
      if vim.fn.filereadable(done_file) ~= 1 then return end

      timer:stop()
      timer:close()
      vim.fn.delete(done_file)

      local log_path = project_root .. "/debug.log"
      if vim.fn.filereadable(log_path) == 1 then
        open_debug_log(log_path, source_win)
      else
        vim.notify("debug.logが生成されませんでした", vim.log.levels.ERROR)
      end
    end))
  end, "AtCoder: デバッグ（愚直解比較＋TLE/MLE）")
end

function M.setup(opts)
  opts = opts or {}

  local project_root = opts.project_root
  if type(project_root) ~= "string" or project_root == "" then return end

  register_make_async_action(project_root, "c", "compile", "AtCoder: コンパイル")

  register_make_async_action(project_root, "s", "submit", "AtCoder: テスト＋提出")
  register_make_async_action(project_root, "u", "submit", "AtCoder: URL指定で提出", {
    use_clipboard_url = true,
  })

  register_debug_action(project_root, "d")

  map_atcoder("b", function()
    local file, source_bufnr = resolve_source_file(project_root)
    if not file then
      vim.notify("実行対象ファイルが見つかりません", vim.log.levels.WARN)
      return
    end

    local ok, output = run_make_sync(project_root, {
      command = make_base_cmd(project_root, "bundle", file),
      source_bufnr = source_bufnr,
      show_output = false,
    })

    if not ok then
      vim.notify(
        "bundleの実行に失敗しました\n" .. table.concat(output, "\n"),
        vim.log.levels.ERROR
      )
      return
    end

    local bundled = project_root .. "/bundled.txt"
    if vim.fn.filereadable(bundled) ~= 1 then
      vim.notify("bundled.txtが見つかりません", vim.log.levels.ERROR)
      return
    end

    local text = table.concat(vim.fn.readfile(bundled), "\n") .. "\n"
    local copied, detail = copy_for_manual_submit(text)

    if copied then
      vim.notify("バンドル結果をコピーしました: " .. tostring(detail), vim.log.levels.INFO)
    else
      vim.notify("コピーに失敗しました: " .. tostring(detail), vim.log.levels.ERROR)
    end
  end, "AtCoder: バンドル＋コピー")

  map_atcoder("m", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = get_nim_lsp_clients(bufnr)

    if #clients == 0 then
      vim.notify("Nim LSPが未接続です", vim.log.levels.WARN)
      return
    end

    local client = clients[1]
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    params.level = 1

    client.request("extension/macroExpand", params, function(err, result)
      vim.schedule(function()
        if err then
          vim.notify(
            "macroExpandに失敗しました: " .. (err.message or vim.inspect(err)),
            vim.log.levels.WARN
          )
          return
        end

        if not result or not result.content or result.content == "" then
          vim.notify("macroExpandの結果が空です", vim.log.levels.INFO)
          return
        end

        vim.lsp.util.open_floating_preview(
          vim.split(result.content, "\n", { plain = true }),
          "nim",
          { border = "rounded" }
        )
      end)
    end, bufnr)
  end, "AtCoder: nim マクロ展開")
end

return M