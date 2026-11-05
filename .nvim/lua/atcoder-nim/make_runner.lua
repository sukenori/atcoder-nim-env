-- atcoder-nim/make_runner.lua
-- キー操作(<Leader>c など)から make を実行する。
--   <Leader>c コンパイル / s テスト+提出 / u URL指定で提出 / d デバッグ
--   <Leader>b バンドルしてコピー / p 正解コードに昇格 / a work を全消去
local M = {}

-- 出力用の下側ウィンドウとバッファ(tmux を使わないときに使う)
local output_win = nil
-- debug の完了を待つための監視(二重に動かさないよう覚えておく)
local debug_watcher = nil

-- 変更のあるバッファをファイルに保存する
local function save(bufnr)
  -- バッファがなければ何もしない
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  -- 変更があるときだけ、そのバッファで write を実行する
  if vim.bo[bufnr].modified then
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! write!") end)
  end
end

-- 実行対象のファイルを決める。現在のバッファ、なければ直前のバッファ(#)から選ぶ
-- 戻り値は「プロジェクト直下からの相対パス」と「バッファ番号」
local function resolve_source(root)
  -- 現在のバッファと、直前に開いていたバッファの 2 つを順に調べる
  for _, bufnr in ipairs({ vim.api.nvim_get_current_buf(), vim.fn.bufnr("#") }) do
    -- 読み込み済みで、普通のファイル(特殊バッファでない)ものだけが対象
    if bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "" then
      -- バッファのファイル名
      local name = vim.api.nvim_buf_get_name(bufnr)
      -- ファイル名があれば、プロジェクト直下からの相対パスに直す(外にあれば nil)
      local rel = name ~= "" and vim.fs.relpath(root, vim.fn.fnamemodify(name, ":p")) or nil
      -- プロジェクトの中のファイルなら、それに決める
      if rel then return rel, bufnr end
    end
  end
  -- 見つからなければ警告を出して nil を返す
  vim.notify("実行対象ファイルが見つかりません", vim.log.levels.WARN)
end

-- make を呼び出すシェルコマンドを作る(例: make -s -C /path compile FILE=work/a.nim)
local function make_cmd(root, target, file)
  -- ファイルが空のとき(all-clear など)は FILE を付けない
  local file_arg = file and (" FILE=" .. vim.fn.shellescape(file)) or ""
  return "make -s --no-print-directory -C " .. vim.fn.shellescape(root) .. " " .. target .. file_arg
end

-- コマンドを実行して、成功したかどうかと出力(行のリスト)を返す(終わるまで待つ)
local function run_sync(cmd)
  -- bash で実行し、標準エラー出力も出力に含める
  local output = vim.fn.systemlist({ "bash", "-lc", cmd .. " 2>&1" })
  -- 終了コードが 0 なら成功
  return vim.v.shell_error == 0, output
end

-- tmux のペインにコマンドを送って実行させる(実行中のものがあれば Ctrl-C で止めてから)
local function send_to_pane(pane, command)
  -- 先に Ctrl-C を送って、実行中の処理を止める
  -- 次にコマンドを文字のまま(-l)入力し、最後に Enter で実行する
  for _, keys in ipairs({ { "C-c" }, { "-l", command }, { "Enter" } }) do
    vim.fn.system(vim.list_extend({ "tmux", "send-keys", "-t", pane }, keys))
    if vim.v.shell_error ~= 0 then return false end
  end
  return true
end

-- Neovim と同じ tmux ウィンドウにある「もう 1 つのペイン」を探す。なければ作る
-- tmux の外で使っているときは nil を返す
local function companion_pane()
  -- tmux の中でなければ使えない
  if (vim.env.TMUX or "") == "" or (vim.env.TMUX_PANE or "") == "" then return nil end
  -- 同じウィンドウのペイン ID の一覧を得る
  local panes = vim.fn.systemlist({ "tmux", "list-panes", "-t", vim.env.TMUX_PANE, "-F", "#{pane_id}" })
  -- tmux の呼び出しに失敗したら使えない
  if vim.v.shell_error ~= 0 then return nil end
  -- Neovim 自身のペイン以外を探す
  for _, id in ipairs(panes) do
    if id ~= vim.env.TMUX_PANE then return id end
  end
  -- ペインが 1 つだけなら、下に新しく分割して、その ID を得る
  local created = vim.fn.systemlist({ "tmux", "split-window", "-v", "-P", "-F", "#{pane_id}", "-t", vim.env.TMUX_PANE })
  -- 作れたら新しいペインの ID を返す(失敗なら nil)
  return vim.v.shell_error == 0 and created[1] or nil
end

-- tmux を使わないとき、Neovim の下側に出力用のターミナルを開いてコマンドを実行する
local function run_in_terminal(root, cmd)
  -- 出力ウィンドウがまだ開いていなければ、画面の下側に作る
  if not (output_win and vim.api.nvim_win_is_valid(output_win)) then
    vim.cmd("botright split")
    output_win = vim.api.nvim_get_current_win()
  end
  -- 出力ウィンドウに移動して、高さを画面の 3 割(最低 8 行)にする
  vim.api.nvim_set_current_win(output_win)
  vim.api.nvim_win_set_height(output_win, math.max(8, math.floor(vim.o.lines * 0.30)))
  -- 出力用の空のバッファを作って、ウィンドウに表示する
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(output_win, buf)
  -- コマンドの最後に、終了コードを [exit N] の形で表示する
  local wrapped = cmd .. "; code=$?; printf '\\n[exit %s]\\n' \"$code\"; exit \"$code\""
  -- ターミナルとしてコマンドを実行する
  vim.fn.termopen({ "bash", "-lc", wrapped }, { cwd = root })
  -- Esc でターミナル入力を抜ける、q でウィンドウを閉じる
  vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { buffer = buf, silent = true })
  vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = buf, silent = true })
  -- 最終行に移動しておく(そうすると出力が増えても自動で追従する)
  vim.cmd("normal! G")
end

-- make を実行する。tmux があればもう 1 つのペインで、なければ下側のターミナルで実行する
local function run(root, cmd, source_bufnr)
  -- 実行前に、編集中のコードを保存する
  save(source_bufnr)
  -- tmux のもう 1 つのペイン
  local pane = companion_pane()
  -- あれば、そこへ送って実行させる(送れたら終わり)
  if pane and send_to_pane(pane, "cd " .. vim.fn.shellescape(root) .. " && " .. cmd) then return end
  -- なければ、下側のターミナルで実行する
  run_in_terminal(root, cmd)
end

-- テキストをクリップボードに送る。成功したかどうかと、使った方法を返す
local function copy_text(text)
  -- 方法 1: 端末の OSC52 という仕組みで、端末側のクリップボードに送る
  local encoded = vim.base64 and vim.base64.encode(text) or ""
  -- /dev/tty に直接書く(Neovim の画面を経由しない)
  local tty = encoded ~= "" and io.open("/dev/tty", "w") or nil
  if tty then
    -- OSC52 の命令(ESC ] 52 ; c ; データ BEL)
    local esc = string.char(27)
    local seq = esc .. "]52;c;" .. encoded .. string.char(7)
    -- tmux の中では、tmux を通り抜けるための包みで囲む
    if (vim.env.TMUX or "") ~= "" then
      seq = esc .. "Ptmux;" .. seq:gsub(esc, esc .. esc) .. esc .. "\\"
    end
    tty:write(seq)
    tty:close()
    return true, "osc52"
  end
  -- 方法 2: OSC52 が使えなければ、入っているクリップボードコマンドを探して使う
  for _, command in ipairs({ { "clip.exe" }, { "wl-copy" }, { "xclip", "-selection", "clipboard" },
                             { "xsel", "--clipboard", "--input" }, { "pbcopy" } }) do
    if vim.fn.executable(command[1]) == 1 then
      vim.fn.system(command, text)
      if vim.v.shell_error == 0 then return true, command[1] end
    end
  end
  -- どちらもだめだった
  return false, "クリップボード連携に失敗しました"
end

-- debug.log の行の先頭に応じて色を付ける。{ 行の先頭の文字, 色の名前, 色 }
local DEBUG_COLORS = {
  { "[INFO]", "AtCoderDebugInfo", "#61AFEF" },
  { "[SUCCESS]", "AtCoderDebugSuccess", "#98C379" },
  { "[FAILURE]", "AtCoderDebugFailure", "#E06C75" },
}
-- 色付けの名前空間(あとでまとめて消せるようにする)
local debug_ns = vim.api.nvim_create_namespace("atcoder_debug_log")

-- バッファの [INFO] / [SUCCESS] / [FAILURE] の部分に色を付ける
local function colorize_debug_log(bufnr)
  -- 色の定義を登録する
  for _, c in ipairs(DEBUG_COLORS) do
    vim.api.nvim_set_hl(0, c[2], { fg = c[3], bold = true })
  end
  -- 前回の色付けを消す
  vim.api.nvim_buf_clear_namespace(bufnr, debug_ns, 0, -1)
  -- 各行を調べて、先頭が一致したら、その部分に色を付ける
  for index, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    for _, c in ipairs(DEBUG_COLORS) do
      if line:sub(1, #c[1]) == c[1] then
        vim.api.nvim_buf_add_highlight(bufnr, debug_ns, c[2], index - 1, 0, #c[1])
      end
    end
  end
end

-- debug.log を Neovim の右側に開く(すでに開いているウィンドウがあればそこを使う)
local function open_debug_log(log_path, source_win)
  -- すでに debug.log を表示しているウィンドウを探す
  local target = vim.fn.fnamemodify(log_path, ":p")
  local existing = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if name ~= "" and vim.fn.fnamemodify(name, ":p") == target then existing = win end
  end
  if existing then
    -- あればそのウィンドウに移動する
    vim.api.nvim_set_current_win(existing)
  else
    -- なければ、コードのウィンドウに戻ってから、その右側に開く
    if source_win and vim.api.nvim_win_is_valid(source_win) then vim.api.nvim_set_current_win(source_win) end
    vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(log_path))
  end
  -- ファイルを読み直し(最新の内容にする)、色を付けて、末尾に移動する
  vim.cmd("edit!")
  colorize_debug_log(vim.api.nvim_get_current_buf())
  vim.cmd("normal! G")
end

-- キーを登録する。<Leader> + lhs で rhs を実行する
local function map(lhs, rhs, desc)
  vim.keymap.set("n", "<Leader>" .. lhs, rhs, { silent = true, desc = desc })
end

-- ターゲット(compile など)を実行するキーを登録する。use_url なら、クリップボードの URL を問題 URL として渡す
local function map_make(root, lhs, target, desc, use_url)
  map(lhs, function()
    -- 実行対象のファイルを決める
    local file, bufnr = resolve_source(root)
    if not file then return end
    local cmd = make_cmd(root, target, file)
    -- URL 指定のときは、クリップボードの URL を空白を除いて取り出す
    if use_url then
      local url = vim.fn.getreg("+"):gsub("%s+", "")
      if url == "" then return vim.notify("クリップボードが空です", vim.log.levels.WARN) end
      cmd = cmd .. " URL=" .. vim.fn.shellescape(url)
    end
    -- 実行する
    run(root, cmd, bufnr)
  end, desc)
end

-- デバッグを実行するキーを登録する
-- tmux のペインで make debug を実行し、終わったら debug.log を右側に開く
local function map_debug(root, lhs)
  map(lhs, function()
    -- 実行対象のファイルを決める
    local file, bufnr = resolve_source(root)
    if not file then return end
    -- debug は tmux のもう 1 つのペインで実行する
    local pane = companion_pane()
    if not pane then return vim.notify("tmux のもう 1 つのペインがありません", vim.log.levels.ERROR) end
    save(bufnr)
    -- 終わりの合図に使うファイル。前回の分が残っていれば消す
    local done = root .. "/.nvim-debug-done"
    vim.fn.delete(done)
    -- 前回の監視が残っていれば止める
    if debug_watcher then debug_watcher:stop() debug_watcher:close() end
    -- 送るコマンド。make debug のあと、終了コードを表示し、合図のファイルを作る
    local command = "cd " .. vim.fn.shellescape(root) .. " && " .. make_cmd(root, "debug", file)
      .. "; code=$?; printf '\\n[debug] debug.log を出力しました\\n[exit %s]\\n' \"$code\""
      .. "; printf '%s\\n' \"$code\" > .nvim-debug-done"
    -- tmux のペインに送って実行させる
    if not send_to_pane(pane, command) then
      return vim.notify("tmux のペインへの送信に失敗しました", vim.log.levels.ERROR)
    end
    -- 開く位置の基準になる、今のウィンドウを覚えておく
    local source_win = vim.api.nvim_get_current_win()
    -- プロジェクトのフォルダを監視して、合図のファイルができたら debug.log を開く
    debug_watcher = vim.uv.new_fs_event()
    local watcher = debug_watcher
    watcher:start(root, {}, vim.schedule_wrap(function(err, filename)
      -- 合図のファイル以外の変化や、すでに終えた監視への通知は無視する
      if err or filename ~= ".nvim-debug-done" or debug_watcher ~= watcher then return end
      -- 監視を終える
      debug_watcher = nil
      watcher:stop()
      watcher:close()
      -- 合図のファイルを消して、debug.log を開く
      vim.fn.delete(done)
      local log = root .. "/debug.log"
      if vim.fn.filereadable(log) == 1 then
        open_debug_log(log, source_win)
      else
        vim.notify("debug.log が生成されませんでした", vim.log.levels.ERROR)
      end
    end))
  end, "AtCoder: デバッグ(愚直解との比較)")
end

-- 初期設定。.nvim.lua から project_root を渡して呼ぶ
function M.setup(opts)
  -- プロジェクトのフォルダ(絶対パス)
  local root = opts and opts.project_root
  if type(root) ~= "string" or root == "" then return end

  -- コンパイル、提出、URL 指定で提出、デバッグ
  map_make(root, "c", "compile", "AtCoder: コンパイル")
  map_make(root, "s", "submit", "AtCoder: テスト+提出")
  map_make(root, "u", "submit", "AtCoder: URL指定で提出", true)
  map_debug(root, "d")

  -- バンドルして、結果をクリップボードにコピーする(手動提出用)
  map("b", function()
    local file, bufnr = resolve_source(root)
    if not file then return end
    save(bufnr)
    -- make bundle で bundled.txt を作る
    local ok, output = run_sync(make_cmd(root, "bundle", file))
    if not ok then return vim.notify("bundle に失敗しました\n" .. table.concat(output, "\n"), vim.log.levels.ERROR) end
    -- bundled.txt を読んで、クリップボードに送る
    local text = table.concat(vim.fn.readfile(root .. "/bundled.txt"), "\n") .. "\n"
    local copied, detail = copy_text(text)
    vim.notify(copied and ("バンドル結果をコピーしました: " .. detail) or detail,
      copied and vim.log.levels.INFO or vim.log.levels.ERROR)
  end, "AtCoder: バンドル+コピー")

  -- 今の work のコードを、正解コードとして隣の cp-solved-log に複製する
  local function promote()
    local file, bufnr = resolve_source(root)
    if not file then return end
    -- 古い内容を昇格しないよう、先に保存する
    save(bufnr)
    local ok, output = run_sync(make_cmd(root, "promote", file))
    vim.notify(ok and "正解コードとして保存しました" or table.concat(output, "\n"),
      ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end

  -- work の中身をすべて削除し、work のバッファも閉じる(確認なし、保存もしない)
  local function all_clear()
    -- work フォルダのパス
    local work = vim.fn.fnamemodify(root .. "/work", ":p")
    -- 先に、work 内のファイルを開いているバッファを集めておく
    local buffers = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bufnr):sub(1, #work) == work then buffers[#buffers + 1] = bufnr end
    end
    -- make all-clear で work の中身を削除する
    local ok, output = run_sync(make_cmd(root, "all-clear"))
    if not ok then return vim.notify(table.concat(output, "\n"), vim.log.levels.ERROR) end
    -- 削除済みのファイルが後で保存されて復活しないよう、バッファを破棄する
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_delete(bufnr, { force = true }) end
    end
    vim.notify("work をすべて消去しました", vim.log.levels.INFO)
  end

  -- キーとコマンドを登録する
  map("p", promote, "AtCoder: work を正解コードに昇格")
  map("a", all_clear, "AtCoder: work を全消去(確認なし)")
  vim.api.nvim_create_user_command("CpPromote", promote, { force = true })
  vim.api.nvim_create_user_command("CpAllClear", all_clear, { force = true })
end

return M
