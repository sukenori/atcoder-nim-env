-- atcoder-nim-env/.nvim.lua プロジェクトローカル設定
-- 素の Neovim で make と Nim LSP を扱う

-- ===========================================================================
-- 1) プロジェクト前提の基本設定
-- ===========================================================================

-- このファイル自身の場所をプロジェクトルートとして扱う
local env_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local project_nvim_dir = env_dir .. "/.nvim"

-- project-local runtime（syntax/ftplugin など）を有効化する。
if vim.fn.isdirectory(project_nvim_dir) == 1 then
  vim.opt.runtimepath:prepend(project_nvim_dir)

  -- 既に開いている Nim バッファにも project-local syntax を即時適用する。
  local function apply_project_nim_syntax(bufnr)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)) then
      return
    end
    if vim.bo[bufnr].filetype ~= "nim" then
      return
    end
    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.cmd, "silent! runtime! syntax/nim.vim")
    end)
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    apply_project_nim_syntax(bufnr)
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("AtcoderProjectNimSyntax", { clear = true }),
    pattern = "nim",
    callback = function(ev)
      apply_project_nim_syntax(ev.buf)
    end,
  })
end

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
-- 2) Linux 側 clipboard (wl-copy / xclip)
-- 3) Neovim clipboard provider (+ レジスタ)
-- 4) OSC52（端末対応時のみ）
local function copy_for_manual_submit(text)
  -- Neovim 内での再利用用に、まず無名レジスタへは必ず入れる
  pcall(vim.fn.setreg, '"', text)

  local text_lines = vim.split(text, "\n", { plain = true })

  local function try_copy(cmd)
    vim.fn.system(cmd, text)
    return vim.v.shell_error == 0
  end

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

  -- Linux 側の一般的な clipboard コマンドにもフォールバック
  if vim.fn.executable("wl-copy") == 1 and try_copy({ "wl-copy" }) then
    return true, "wl-copy"
  end
  if vim.fn.executable("xclip") == 1 and try_copy({ "xclip", "-selection", "clipboard" }) then
    return true, "xclip"
  end

  -- provider が有効な環境に限り + レジスタ経由を外部コピー成功として扱う
  if vim.fn.has("clipboard") == 1 and pcall(vim.fn.setreg, "+", text) then
    return true, "+register"
  end

  -- 端末が対応していれば OSC52 で外部クリップボードへ渡せる
  if try_osc52() then
    return true, "osc52"
  end

  return false, "外部 clipboard provider が見つかりません（無名レジスタには保存済み）"
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

vim.keymap.set("n", "<LocalLeader>m", function()
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
end, { silent = true, desc = "AtCoder: nim マクロ展開" })

-- ===========================================================================
-- 4) Nim LSP 設定（project-local）
-- ===========================================================================
local function resolve_nim_root(bufnr)
  local uv = vim.uv or vim.loop
  local fname = vim.api.nvim_buf_get_name(bufnr)
  if fname == "" then
    return env_dir
  end

  local real = uv.fs_realpath(fname) or fname
  local start = vim.fs.dirname(real)
  local marker = vim.fs.find({ "nim.cfg", ".git" }, { path = start, upward = true })[1]
  if marker then
    return vim.fs.dirname(marker)
  end

  local dir = start
  while dir and dir ~= "" do
    if vim.fn.glob(dir .. "/*.nimble") ~= "" then
      return dir
    end

    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then
      break
    end
    dir = parent
  end

  return start
end

local function setup_project_nim_lsp()
  if not (vim.lsp and vim.lsp.config and vim.lsp.enable) then
    return
  end

  if vim.g.atcoder_project_nim_lsp_initialized then
    return
  end
  vim.g.atcoder_project_nim_lsp_initialized = true

  local server_name = "nim_langserver"
  if vim.lsp.config.nim_ls and not vim.lsp.config.nim_langserver then
    server_name = "nim_ls"
  end

  vim.lsp.config(server_name, {
    cmd = { "nimlangserver" },
    settings = {
      nim = {
        autoCheckFile = true,
        autoCheckProject = false,
        checkOnSave = false,
        useNimCheck = false,
        notificationVerbosity = "warning",
      },
    },
    root_dir = function(bufnr, on_dir)
      local root = resolve_nim_root(bufnr)
      if on_dir then
        on_dir(root)
      else
        return root
      end
    end,
  })

  vim.lsp.enable(server_name)

  -- 設定時点で開かれている Nim バッファにも接続を適用する。
  vim.schedule(function()
    pcall(vim.cmd.doautoall, "nvim.lsp.enable FileType")
  end)
end

setup_project_nim_lsp()