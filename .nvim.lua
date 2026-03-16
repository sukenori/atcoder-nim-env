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

-- ===========================================================================
-- 2) 下部出力パネル（make 実行ログ表示）
-- ===========================================================================
-- 共有出力バッファと表示ウィンドウのハンドル
-- 非同期の make は追記して使い回すため保持する
local output_buf = nil
local output_win = nil

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
  -- 画面下の出力は作業エリアを圧迫しすぎないよう 35% 程度に抑える
  local height = math.max(8, math.floor(vim.o.lines * 0.35))

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

-- コマンド開始時に出力バッファを初期化し、ヘッダを表示する
local function start_output(cmd)
  ensure_output_log_buffer()
  ensure_output_window()
  vim.api.nvim_win_set_buf(output_win, output_buf)
  vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, {
    "AtCoder command output",
    "$ " .. cmd,
    "",
  })
end

-- 非同期で（NeoVim を止めずに）make を実行する（ターミナルのペースで対話入力するためにも必須）
-- 編集ウィンドウを維持しつつ、下部パネルで進行と終了コードを確認できる
-- opts.focus_output=true を渡すと出力ターミナルへフォーカスし、標準入力を直接送れる
local function run_make_async(cmd, opts)
  opts = opts or {}
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
    -- 先頭に実行コマンドを表示し、最後に [exit N] を必ず出して結果を明示する。
    "printf 'AtCoder command output\\n$ %s\\n\\n' " .. vim.fn.shellescape(cmd)
    .. "; " .. cmd
    .. "; code=$?; printf '\\n[exit %s]\\n' \"$code\"; exit \"$code\""

  local job = vim.fn.termopen({ "bash", "-lc", wrapped }, {
    cwd = env_dir,
  })

  if job <= 0 then
    vim.notify("make の非同期実行に失敗しました", vim.log.levels.ERROR)
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

  start_output(cmd)
  local output = vim.fn.systemlist({ "bash", "-lc", cmd .. " 2>&1" })
  if #output == 0 then
    append_output({ "(no output)" })
  else
    append_output(output)
  end

  append_output({ "", ("[exit %d]"):format(vim.v.shell_error) })
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
  local cmd = "make -C " .. vim.fn.shellescape(env_dir) .. " build FILE=" .. vim.fn.shellescape(file)
  run_make_async(cmd)
end, { silent = true, desc = "AtCoder: コンパイル" })

-- コンパイルしてそのまま実行する
-- 下部ターミナルへフォーカスして terminal-mode に入るため、入力をそのまま貼り付けられる。
vim.keymap.set("n", "<LocalLeader>r", function()
  local file = vim.fn.expand("%:p"):gsub("^" .. vim.pesc(env_dir) .. "/", "")
  local cmd = "make -C " .. vim.fn.shellescape(env_dir) .. " run FILE=" .. vim.fn.shellescape(file)
  run_make_async(cmd, { focus_output = true, startinsert = true })
end, { silent = true, desc = "AtCoder: コンパイル＋実行" })

vim.keymap.set("n", "<LocalLeader>s", function()
  local file = vim.fn.expand("%:p"):gsub("^" .. vim.pesc(env_dir) .. "/", "")
  local cmd = "make -C " .. vim.fn.shellescape(env_dir) .. " submit FILE=" .. vim.fn.shellescape(file)
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
  local cmd = "make -C " .. vim.fn.shellescape(env_dir)
    .. " submit FILE=" .. vim.fn.shellescape(file)
    .. " URL=" .. vim.fn.shellescape(url)
  run_make_async(cmd)
end, { silent = true, desc = "AtCoder: URL 指定で提出" })

-- bundle を同期実行して結果をクリップボードへコピーする
vim.keymap.set("n", "<LocalLeader>b", function()
  local file = vim.fn.expand("%:p"):gsub("^" .. vim.pesc(env_dir) .. "/", "")
  local cmd = "make -C " .. vim.fn.shellescape(env_dir) .. " bundle FILE=" .. vim.fn.shellescape(file)
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

-- ===========================================================================
-- 4) Nim LSP を Docker コンテナ内で起動する
-- ===========================================================================
-- compose.yaml の container_name に合わせて Nim LSP を Docker 内で起動するコマンドを定義
if vim.fn.executable("docker") ~= 1 then
  vim.notify("docker コマンドが見つからないため Nim LSP を無効化します", vim.log.levels.WARN)
  return
end

local container_name = "atcoder-nim"

-- まず通常の docker で稼働コンテナ一覧を取得する（docker ps）
local running_containers = vim.fn.systemlist({ "docker", "ps", "--format", "{{.Names}}" })
local use_sg_docker = false
if vim.v.shell_error ~= 0 then
  -- docker グループ反映前でも動くように、sg docker （switch group）経由で実行してフォールバック
  running_containers = vim.fn.systemlist({ "sg", "docker", "-c", "docker ps --format '{{.Names}}'" })
  if vim.v.shell_error ~= 0 then
    vim.notify("docker ps の実行に失敗したため Nim LSP を無効化します（docker 権限を確認）", vim.log.levels.WARN)
    return
  end
  use_sg_docker = true
end

if not vim.tbl_contains(running_containers, container_name) then
  vim.notify(container_name .. " が起動していないため Nim LSP を無効化します", vim.log.levels.WARN)
  return
end

local nim_cmd
if use_sg_docker then
  -- sg 経由時は 1 コマンド文字列として渡す必要がある。
  nim_cmd = {
    "sg",
    "docker",
    "-c",
    "docker exec -i -w /home/sukenori/atcoder-nim-env " .. container_name .. " nimlangserver",
  }
else
  -- 通常時は引数配列で docker exec を実行する。
  nim_cmd = {
    "docker",
    "exec",
    "-i",
    "-w",
    "/home/sukenori/atcoder-nim-env",
    container_name,
    "nimlangserver",
  }
end

-- nvim-cmp / lspconfig は lazy.nvim 側で導入済み前提にする
local ok_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if not ok_cmp then
  vim.notify("cmp-nvim-lsp が読み込めません", vim.log.levels.WARN)
  return
end

-- nvim-cmp の capability を LSP に渡し、それに応じた出力を得る
local capabilities = cmp_nvim_lsp.default_capabilities(
  vim.lsp.protocol.make_client_capabilities()
)

-- Nim LSP の INFO ログが多いため、エラーと警告のみ通知するようハンドラを一度だけ差し替える
if not vim.g.atcoder_nim_lsp_handlers_patched then
  local message_type = vim.lsp.protocol.MessageType
  local default_log_message = vim.lsp.handlers["window/logMessage"]
  local default_show_message = vim.lsp.handlers["window/showMessage"]

  if default_log_message then
    vim.lsp.handlers["window/logMessage"] = function(err, result, ctx, config)
      local t = result and result.type
      if t and t <= message_type.Warning then
        return default_log_message(err, result, ctx, config)
      end
    end
  end

  if default_show_message then
    vim.lsp.handlers["window/showMessage"] = function(err, result, ctx, config)
      local t = result and result.type
      if t and t <= message_type.Warning then
        return default_show_message(err, result, ctx, config)
      end
    end
  end

  vim.g.atcoder_nim_lsp_handlers_patched = true
end

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

-- Nim バッファを開いた時、（プロジェクト設定ゆえに）未接続なら nim_langserver を起動する
local function ensure_nim_lsp_for_current_buffer()
  if vim.bo.filetype ~= "nim" then
    return
  end

  local has_client = false
  if vim.lsp.get_clients then
    local clients = vim.lsp.get_clients({ bufnr = 0, name = "nim_langserver" })
    has_client = #clients > 0
  end

  if has_client then
    return
  end

  if vim.fn.exists(":LspStart") == 2 then
    vim.schedule(function()
      vim.cmd("LspStart nim_langserver")
    end)
  end
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
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "nim" then
        return
      end

      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "nim" then
          return
        end
        if #vim.lsp.get_clients({ bufnr = bufnr, name = "nim_langserver" }) > 0 then
          return
        end
        if vim.fn.exists(":LspStart") == 2 then
          vim.cmd("silent! LspStart nim_langserver")
        end
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
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
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
setup_nim_lsp_keepalive()
ensure_nim_lsp_for_current_buffer()