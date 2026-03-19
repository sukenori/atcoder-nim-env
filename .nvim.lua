-- atcoder-nim-env/.nvim.lua プロジェクトローカル設定
-- 素の Neovim で make と Nim LSP を扱う

-- ===========================================================================
-- 1) プロジェクト前提の基本設定
-- ===========================================================================

-- このファイル自身の場所をプロジェクトルートとして扱う
local env_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

-- 同じファイルを複数の Neovim から触るなどで swap 競合 (W325) の警告が起動時のノイズになるので、この project では無効化する
-- ファイルの保全は 保存と Git が前提
vim.opt.swapfile = false

-- このプロジェクト専用のスニペットを .nvim/snippets から読み込む
local function register_project_snippets()
  local ok_loader, loader = pcall(require, "luasnip.loaders.from_lua")
  if not ok_loader then
    vim.notify("LuaSnip loader が読み込めないため project snippet を登録できません", vim.log.levels.WARN)
    return
  end

  local snippet_dir = env_dir .. "/.nvim/snippets"
  if vim.fn.isdirectory(snippet_dir) ~= 1 then
    return
  end

  loader.load({ paths = { snippet_dir } })
end

register_project_snippets()

-- 共有出力バッファと表示ウィンドウのハンドル
-- 非同期の make は追記して使い回すため保持する
local output_buf = nil
local output_win = nil

-- ===========================================================================
-- 2) 下部出力パネル（make 実行ログ表示）
-- ===========================================================================
-- 非同期 make のログ表示用の scratch バッファを用意
-- 同期 make 時の terminal バッファだった場合は作り直す
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

-- 出力バッファを表示する下側ウィンドウを確保
-- 既存があれば再利用し、なければ botright split で作成
local function ensure_output_window()
  local previous_win = vim.api.nvim_get_current_win()
  -- 画面下の出力は作業エリアを圧迫しすぎないよう 30% 程度に抑える
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

-- 出力ターミナルで PageUp/PageDown によるページ送りを使えるようにする
local function setup_output_terminal_keymaps(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local opts = { buffer = bufnr, silent = true }
  -- 端末差で PageUp/PageDown のキーコードが異なるため、主要パターンをまとめて受ける。
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

-- 出力ウィンドウを末尾へ追従させる
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

-- 一連の make コマンドに対して出力バッファ末尾へログを追記
-- 空行は省き、必要なら prefix を付けて見分けやすくする
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

-- コマンド開始時に出力バッファを初期化する
local function start_output()
  ensure_output_log_buffer()
  ensure_output_window()
  vim.api.nvim_win_set_buf(output_win, output_buf)
  vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, {})
end

-- 非同期で（NeoVim を止めずに）make を実行する（ターミナルのペースで対話入力するためにも必須）
-- 編集ウィンドウを維持しつつ、下部パネルで進行と終了コードを確認できる
-- opts.focus_output=true を渡すと出力ターミナルへフォーカスし、標準入力を直接送れる
local function run_make_async(cmd, opts)
  opts = opts or {}
  if opts.focus_output == nil then
    opts.focus_output = true
  end
  vim.cmd("write")

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

  -- termopen は「現在ウィンドウ」のバッファで動くため、
  -- いったん下側の出力ウィンドウに移動してから起動する。
  vim.api.nvim_set_current_win(output_win)

  local wrapped =
    -- 実行結果だけを表示し、最後に [exit N] で終了コードのみ明示する。
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

-- 同期で make を実行する（bundle の結果を待ってクリップボードに読むため）
-- systemlist で stdout/stderr をまとめて取得し、同じ出力パネルへ流す
local function run_make_sync(cmd)
  vim.cmd("write")

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

-- bundle 結果を「手動提出しやすい形」でクリップボードへ送る
-- 優先順位:
-- 1) WSL -> Windows の clip.exe / powershell
-- 2) Neovim の + レジスタ
-- 3) Linux 側 clipboard (wl-copy / xclip)
local function copy_for_manual_submit(text)
  -- Neovim 内での再利用用に、まず無名レジスタへは必ず入れる
  pcall(vim.fn.setreg, '"', text)

  local function try_copy(cmd)
    vim.fn.system(cmd, text)
    return vim.v.shell_error == 0
  end

  -- WSL では Windows 側クリップボードに直接渡すのが最優先
  if vim.fn.has("wsl") == 1 then
    if vim.fn.executable("clip.exe") == 1 and try_copy({ "clip.exe" }) then
      return true, "clip.exe"
    end

    local clip_exe = "/mnt/c/Windows/System32/clip.exe"
    if vim.fn.executable(clip_exe) == 1 and try_copy({ clip_exe }) then
      return true, "clip.exe"
    end

    if vim.fn.executable("powershell.exe") == 1 then
      local ps_cmd = {
        "powershell.exe",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        "$input | Set-Clipboard",
      }
      if try_copy(ps_cmd) then
        return true, "powershell Set-Clipboard"
      end
    end
  end

  -- provider が有効なら + レジスタ経由でも外部貼り付けできる
  if pcall(vim.fn.setreg, "+", text) then
    return true, "+register"
  end

  -- Linux 側の一般的な clipboard コマンドにもフォールバック
  if vim.fn.executable("wl-copy") == 1 and try_copy({ "wl-copy" }) then
    return true, "wl-copy"
  end
  if vim.fn.executable("xclip") == 1 and try_copy({ "xclip", "-selection", "clipboard" }) then
    return true, "xclip"
  end

  return false, "利用可能な clipboard provider が見つかりません"
end

-- ===========================================================================
-- 3) AtCoder 操作用キーマップ
-- ===========================================================================
-- <LocalLeader> は init.lua 側で "," に設定済み
-- 例: ,c で build、,r で run、,s で submit、,u で URL 指定 submit、,b で bundle+copy

-- 基本操作: コンパイル / テスト+提出
vim.keymap.set("n", "<LocalLeader>c", function()
  local file = vim.fn.expand("%:p"):gsub("^" .. vim.pesc(env_dir) .. "/", "")
  local cmd = "make -s --no-print-directory -C " .. vim.fn.shellescape(env_dir)
    .. " build FILE=" .. vim.fn.shellescape(file)
  run_make_async(cmd)
end, { silent = true, desc = "AtCoder: コンパイル" })

-- コンパイルしてそのまま実行する
-- 下部ターミナルへフォーカスして terminal-mode に入るため、入力をそのまま貼り付けられる。
vim.keymap.set("n", "<LocalLeader>r", function()
  local file = vim.fn.expand("%:p"):gsub("^" .. vim.pesc(env_dir) .. "/", "")
  local cmd = "make -s --no-print-directory -C " .. vim.fn.shellescape(env_dir)
    .. " run FILE=" .. vim.fn.shellescape(file)
  run_make_async(cmd, { focus_output = true, startinsert = true })
end, { silent = true, desc = "AtCoder: コンパイル＋実行" })

vim.keymap.set("n", "<LocalLeader>s", function()
  local file = vim.fn.expand("%:p"):gsub("^" .. vim.pesc(env_dir) .. "/", "")
  local cmd = "make -s --no-print-directory -C " .. vim.fn.shellescape(env_dir)
    .. " submit FILE=" .. vim.fn.shellescape(file)
  run_make_async(cmd)
end, { silent = true, desc = "AtCoder: テスト＋提出" })

-- クリップボードの URL で提出する
vim.keymap.set("n", "<LocalLeader>u", function()
  local url = vim.fn.getreg("+"):gsub("%s+", "")
  if url == "" then
    print("クリップボードが空です")
    return
  end
  local file = vim.fn.expand("%:p"):gsub("^" .. vim.pesc(env_dir) .. "/", "")
  local cmd = "make -s --no-print-directory -C " .. vim.fn.shellescape(env_dir)
    .. " submit FILE=" .. vim.fn.shellescape(file)
    .. " URL=" .. vim.fn.shellescape(url)
  run_make_async(cmd)
end, { silent = true, desc = "AtCoder: URL 指定で提出" })

-- bundle を同期実行して結果をクリップボードへコピーする
vim.keymap.set("n", "<LocalLeader>b", function()
  local file = vim.fn.expand("%:p"):gsub("^" .. vim.pesc(env_dir) .. "/", "")
  local cmd = "make -s --no-print-directory -C " .. vim.fn.shellescape(env_dir) .. " bundle FILE=" .. vim.fn.shellescape(file)
  local ok = run_make_sync(cmd)
  if not ok then
    print("bundle の実行に失敗しました")
    return
  end

  local target = env_dir .. "/bundled.txt"
  if vim.fn.filereadable(target) == 1 then
    local lines = vim.fn.readfile(target)
    local bundled_text = table.concat(lines, "\n") .. "\n"
    local copied, method = copy_for_manual_submit(bundled_text)
    if copied then
      print("バンドル結果をクリップボードにコピーしました (" .. method .. ")")
    else
      print("コピーに失敗しました: " .. method)
      print("bundled.txt は生成済みです。必要ならファイルを開いて手動コピーしてください")
    end
  else
    print("エラー: " .. target .. " が見つかりません")
  end
end, { silent = true, desc = "AtCoder: バンドル＋コピー" })

-- nimlangserver 独自拡張: カーソル位置のマクロ展開結果をプレビューする
vim.keymap.set("n", "<LocalLeader>m", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients and vim.lsp.get_clients({ bufnr = bufnr, name = "nim_langserver" }) or {}
  if #clients == 0 then
    vim.notify("nim_langserver が未接続です", vim.log.levels.WARN)
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
end, { silent = true, desc = "AtCoder: nim マクロ展開" })

-- ===========================================================================
-- 4) Nim LSP の起動経路
-- ===========================================================================
local nim_cmd = { "nimlangserver" }

-- nvim-cmp の capability を LSP に渡す。
-- cmp 側が読み込めない場合でも、Nim LSP 本体は無効化せず基本 capability で継続する。
local capabilities = vim.lsp.protocol.make_client_capabilities()
local ok_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if ok_cmp then
  capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
else
  vim.notify("cmp-nvim-lsp が読み込めないため、基本 capability で Nim LSP を起動します", vim.log.levels.WARN)
end

-- nimlangserver の Info 通知は多く、コマンドラインの "Press ENTER" ノイズになりやすい。
-- Warning/Error は残し、Info のみ抑制する。
if not vim.g.atcoder_nim_lsp_handlers_patched then
  local message_type = vim.lsp.protocol.MessageType
  local default_log_message = vim.lsp.handlers["window/logMessage"]
  local default_show_message = vim.lsp.handlers["window/showMessage"]

  local function is_nim_langserver_ctx(ctx)
    if not (ctx and ctx.client_id) then
      return false
    end
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    return client and client.name == "nim_langserver"
  end

  if default_log_message then
    vim.lsp.handlers["window/logMessage"] = function(err, result, ctx, config)
      if is_nim_langserver_ctx(ctx) then
        local t = result and result.type
        if t and t > message_type.Warning then
          return
        end
      end
      return default_log_message(err, result, ctx, config)
    end
  end

  if default_show_message then
    vim.lsp.handlers["window/showMessage"] = function(err, result, ctx, config)
      if is_nim_langserver_ctx(ctx) then
        local t = result and result.type
        if t and t > message_type.Warning then
          return
        end
      end
      return default_show_message(err, result, ctx, config)
    end
  end

  vim.g.atcoder_nim_lsp_handlers_patched = true
end

-- nimlangserver 公式設定（README の Configuration Options）を優先して使う。
local nim_settings = {
  nim = {
    notificationVerbosity = "warning",
    autoCheckFile = true,
    autoCheckProject = true,
    checkOnSave = true,
    useNimCheck = true,
  },
}

-- バッファ（ファイル）パスから LSP ルートを定義する
-- nim.cfg / .git の在処を優先し、見つからない場合はバッファの親ディレクトリでフォールバック
local function resolve_root(fname)
  local start = env_dir
  if fname and fname ~= "" then
    start = vim.fs.dirname(fname)
  end

  local found = vim.fs.find({ "nim.cfg", ".git" }, { path = start, upward = true })[1]
  if found then
    return vim.fs.dirname(found)
  end

  if fname and fname ~= "" then
    return vim.fn.fnamemodify(fname, ":p:h")
  end
  return env_dir
end

-- Nim バッファかどうかを判定する。
local function is_nim_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  return vim.bo[bufnr].filetype == "nim"
end

local function is_nim_candidate_buffer(bufnr)
  if is_nim_buffer(bufnr) then
    return true
  end
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local fname = vim.api.nvim_buf_get_name(bufnr)
  return fname ~= "" and fname:match("%.nim$") ~= nil
end

-- 現在バッファに nimlangserver を直接アタッチする。
-- LspStart コマンド経由だと実行環境差分で起動しないケースがあるため、API で明示起動する。
local function start_nim_lsp_for_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local fname = vim.api.nvim_buf_get_name(bufnr)
  if fname == "" then
    return
  end

  local root = resolve_root(fname)
  vim.api.nvim_buf_call(bufnr, function()
    local ok_start, start_result = pcall(vim.lsp.start, {
      name = "nim_langserver",
      cmd = nim_cmd,
      root_dir = root,
      capabilities = capabilities,
      settings = nim_settings,
    })

    if not ok_start then
      vim.notify("nimlangserver の起動に失敗しました: " .. tostring(start_result), vim.log.levels.WARN)
    end
  end)
end

-- Nim バッファを開いた時、（プロジェクト設定ゆえに）未接続なら nim_langserver を起動する
local function ensure_nim_lsp_for_current_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not is_nim_candidate_buffer(bufnr) then
    return
  end

  local has_client = false
  if vim.lsp.get_clients then
    local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "nim_langserver" })
    has_client = #clients > 0
  end

  if has_client then
    return
  end

  vim.schedule(function()
    if not is_nim_candidate_buffer(bufnr) then
      return
    end
    if #vim.lsp.get_clients({ bufnr = bufnr, name = "nim_langserver" }) > 0 then
      return
    end
    start_nim_lsp_for_buffer(bufnr)
  end)
end

-- 新規 Nim ファイルは開いた時点で一度保存し、実体ファイルを作る。
-- これで「既存ファイルのみ LSP 起動」の方針を保ちながら、new file でも補完を有効化できる。
local function setup_autowrite_new_nim_file()
  local group = vim.api.nvim_create_augroup("AtcoderNimAutoWriteNewFile", { clear = true })

  vim.api.nvim_create_autocmd("BufNewFile", {
    group = group,
    pattern = "*.nim",
    callback = function(ev)
      local bufnr = ev.buf
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local fname = vim.api.nvim_buf_get_name(bufnr)
      if fname == "" then
        return
      end

      if not vim.startswith(fname, env_dir .. "/") then
        return
      end

      if vim.fn.filereadable(fname) == 1 then
        return
      end

      vim.api.nvim_buf_call(bufnr, function()
        local ok_write = pcall(vim.cmd, "silent! write")
        if not ok_write then
          vim.notify("新規 Nim ファイルの自動保存に失敗しました: " .. fname, vim.log.levels.WARN)
          return
        end

        -- 保存で実体化した直後に接続を試す（BufWritePost でも同等だが即時性を上げる）。
        ensure_nim_lsp_for_current_buffer(bufnr)
      end)
    end,
  })
end

-- 起動時/保存時に nim LSP を必要なバッファへだけ接続する
local function setup_nim_lsp_autostart()
  local group = vim.api.nvim_create_augroup("AtcoderNimLspAutostart", { clear = true })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufEnter" }, {
    group = group,
    pattern = "*.nim",
    callback = function(ev)
      ensure_nim_lsp_for_current_buffer(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function(ev)
      ensure_nim_lsp_for_current_buffer(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "nim",
    callback = function(ev)
      ensure_nim_lsp_for_current_buffer(ev.buf)
    end,
  })
end

-- 一時的な detach 後に LSP が消えっぱなしになるのを防ぐ
-- nim バッファに対して短時間後に再接続を試みる keepalive を用意 
local function setup_nim_lsp_keepalive()
  local group = vim.api.nvim_create_augroup("AtcoderNimLspKeepAlive", { clear = true })
  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(ev)
      local client_id = ev.data and ev.data.client_id or nil
      if not client_id then
        return
      end

      local client = vim.lsp.get_client_by_id(client_id)
      if not client or client.name ~= "nim_langserver" then
        return
      end

      local bufnr = ev.buf
      if not is_nim_buffer(bufnr) then
        return
      end

      vim.defer_fn(function()
        if not is_nim_buffer(bufnr) then
          return
        end
        if #vim.lsp.get_clients({ bufnr = bufnr, name = "nim_langserver" }) > 0 then
          return
        end
        start_nim_lsp_for_buffer(bufnr)
      end, 500)
    end,
  })
end

-- Neovim 0.11 以降の API（vim.lsp.config / vim.lsp.enable）で nim LSP を設定する。
if not (vim.lsp and vim.lsp.config) then
  vim.notify("Neovim 0.11 以降が必要です（vim.lsp.config が見つかりません）", vim.log.levels.WARN)
  return
end

vim.lsp.config("nim_langserver", {
  cmd = nim_cmd,
  filetypes = { "nim" },
  capabilities = capabilities,
  settings = nim_settings,
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)

    if fname == "" then
      return nil
    end

    local root = resolve_root(fname)
    if on_dir then
      on_dir(root)
    else
      return root
    end
  end,
})
vim.lsp.enable("nim_langserver")

-- このプロジェクト向けの補助機能を有効化。
setup_autowrite_new_nim_file()
setup_nim_lsp_autostart()
setup_nim_lsp_keepalive()
ensure_nim_lsp_for_current_buffer()
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    ensure_nim_lsp_for_current_buffer()
  end,
})