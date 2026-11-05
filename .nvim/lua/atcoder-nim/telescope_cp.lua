-- atcoder-nim.telescope_cp: 競プロ資産を検索する3つのTelescope入口
--   <leader>fa  cp-solved-log を検索する(読み取り専用)
--   <leader>fi  cp-nim-lib / nim-acl から選び、include / import 文を挿入する
--   <leader>fs  Snippet と標準ライブラリを検索し、カーソル位置に展開する
--   <C-g>s      <leader>fs と同じものを、インサートモードのまま起動する
-- カーソルの直前が "." なら UFCS 呼び出し(a.sum())、そうでなければ通常呼び出し(sum(a))で展開する

-- このモジュールの公開テーブルを用意する
local M = {}

-- 直前のquickfixを保存・復元する自作モジュールを読み込む
local qf_session = require("util.quickfix_session")
-- 標準ライブラリなどの関数シグネチャを集め、呼び出し用の文字列に変えるモジュールを読み込む
local lib_scan = require("atcoder-nim.nim_lib_scan")

-- カーソルの直前の1文字が "." かどうかを返す
local function cursor_is_after_dot()
  -- カーソルの行番号と、カーソルより前にあるバイト数を取り出す
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  -- カーソルのある行の文字列を取り出す
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  -- 先頭でなく、かつカーソルの左隣が "." なら true を返す
  return col > 0 and line:sub(col, col) == "."
end

-- 空白区切りの語がすべて含まれる行だけを残すソーター(部分一致、大文字小文字は区別しない)を返す
local function and_substring_sorter()
  -- Telescopeのソーター作成モジュールを読み込む
  local sorters = require("telescope.sorters")
  -- 点数を自前で決めるソーターを作って返す
  return sorters.new({
    -- 検索語(prompt)と候補の文字列(line)から点数を返す関数
    scoring_function = function(_, prompt, line)
      -- 検索語が空なら全候補を残す
      if prompt == "" then return 1 end
      -- 候補の文字列を小文字にする
      local target = line:lower()
      -- 検索語を空白で区切って1語ずつ調べる
      for word in prompt:gmatch("%S+") do
        -- 1語でも含まれていなければ不採用(-1)にする
        if not target:find(word:lower(), 1, true) then return -1 end
      end
      -- 全部含まれていれば採用(1)にする
      return 1
    end,
  })
end

-- ============================================================
-- <leader>fa: 過去解答を検索する
-- ============================================================

-- cp-solved-log 配下のファイルを、どう開いても編集できないようにする
local function setup_readonly_solved_log(root)
  -- ファイルを読み込んだ直後に実行する処理を登録する
  vim.api.nvim_create_autocmd("BufReadPost", {
    -- 何度読み込んでも重複しないよう、グループを作り直す
    group = vim.api.nvim_create_augroup("CpSolvedLogReadonly", { clear = true }),
    -- 対象は cp-solved-log 配下のすべてのファイル
    pattern = root .. "/*",
    -- 読み取り専用にして、変更も禁止する
    callback = function(ev)
      vim.bo[ev.buf].readonly = true
      vim.bo[ev.buf].modifiable = false
    end,
  })
end

-- cp-solved-log の .nim ファイルを、空白区切りのAND条件で検索する
local function search_solved_log(root)
  -- 必要なTelescopeのモジュールを読み込む
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local make_entry = require("telescope.make_entry")
  local sorters = require("telescope.sorters")

  -- 入力のたびに rg を実行する検索元を作る
  local finder = finders.new_job(function(prompt)
    -- 空白で区切った語を、rg用の先読みパターンに変える("h w" -> "(?=.*h)(?=.*w)")
    local lookaheads = {}
    for word in prompt:gmatch("%S+") do
      table.insert(lookaheads, "(?=.*" .. word .. ")")
    end
    -- 語が無ければ検索しない
    if #lookaheads == 0 then return nil end
    -- 実行するrgコマンドを返す(行頭 ^ を付けて、同じ行の重複ヒットを1件にまとめる)
    return {
      "rg", "--vimgrep", "--no-heading", "--color=never", "--smart-case",
      "-P", "-e", "^" .. table.concat(lookaheads), "--glob", "*.nim",
    }
  end, make_entry.gen_from_vimgrep({ cwd = root }), nil, root)

  -- 検索画面を作って開く
  pickers.new({}, {
    -- 画面のタイトル
    prompt_title = "Solved log (read-only, AND search)",
    -- 検索元
    finder = finder,
    -- ヒット位置を表示するプレビュー
    previewer = conf.grep_previewer({ cwd = root }),
    -- 並べ替えはせず、rgの出力順のまま表示する
    sorter = sorters.empty(),
  }):find()
end

-- ============================================================
-- <leader>fi: ライブラリを選んで include / import を挿入する
-- ============================================================

-- 選んだファイルを表示するプレビューを作る
local function file_previewer()
  -- プレビュー作成と、今の選択状態を調べるためのモジュールを読み込む
  local previewers = require("telescope.previewers")
  local action_state = require("telescope.actions.state")

  -- 検索語のうち、本文で最初に見つかる行番号を返す(見つからなければ nil)
  local function first_hit_line(lines, prompt)
    -- 検索語を1語ずつ調べる
    for word in prompt:gmatch("%S+") do
      -- 本文を1行ずつ調べる
      for i, line in ipairs(lines) do
        -- 見つかったら、その行番号を返す
        if line:lower():find(word:lower(), 1, true) then return i end
      end
    end
    -- どこにも無ければ nil を返す
    return nil
  end

  -- プレビュー用のバッファを使う仕組みを作って返す
  return previewers.new_buffer_previewer({
    -- プレビュー枠のタイトル
    title = "File Preview",
    -- 同じファイルなら同じバッファを使い回す
    get_buffer_by_name = function(_, entry) return entry.path end,
    -- 選択が変わるたびに呼ばれ、プレビューの中身を作る
    define_preview = function(self, entry, status)
      -- プレビューのバッファと、それを表示するウィンドウを控える
      local bufnr, winid = self.state.bufnr, self.state.winid
      -- ファイルを読み込み、プレビューのバッファに書き込む
      local lines = vim.fn.readfile(entry.path)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- 拡張子から色付け(syntax)を決める。filetypeにするとFileTypeの自動処理が動いてしまうので使わない
      local ext = vim.fn.fnamemodify(entry.path, ":e")
      vim.bo[bufnr].syntax = (ext == "md") and "markdown" or ext
      -- markdownだけ、**太字** などの記号を隠して表示する
      vim.wo[winid].conceallevel = (ext == "md") and 2 or 0
      vim.wo[winid].concealcursor = "nc"

      -- 今入力されている検索語を取り出す
      local prompt = ""
      local ok, picker = pcall(action_state.get_current_picker, status.prompt_bufnr)
      if ok and picker then prompt = picker:_get_prompt() or "" end
      -- 検索語が本文のどこかに見つかるかを調べる
      local target = prompt ~= "" and first_hit_line(lines, prompt) or nil
      -- 見つからなければ先頭のまま終わる
      if not target then return end

      -- 少し遅らせてその行へ移動する(すぐだと前の選択の表示が残っていてエラーになる)
      vim.schedule(function()
        -- ウィンドウが閉じていた、または別のバッファに切り替わっていたら何もしない
        if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= bufnr then return end
        -- 行番号がバッファの行数を超えないようにして、カーソルを移動し、中央に表示する
        pcall(vim.api.nvim_win_set_cursor, winid, { math.min(target, vim.api.nvim_buf_line_count(bufnr)), 0 })
        pcall(vim.api.nvim_win_call, winid, function() vim.cmd("normal! zz") end)
      end)
    end,
  })
end

-- ファイルの中身を1行の文字列にして返す(検索対象を本文まで広げるために使う)
local function read_file_text(path)
  -- 読み込みに失敗したら空文字にする
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return "" end
  -- 全行を空白でつないで返す
  return table.concat(lines, " ")
end

-- cp-nim-lib と nim-acl のファイルを、1つの候補リストにまとめる
local function collect_library_entries(lib_root, acl_root)
  -- 候補を貯める表
  local entries = {}

  -- 指定フォルダ内で、拡張子が ext のファイルを探して候補に追加する関数
  local function add(root, ext, origin, mode, declaration_of, ordinal_extra)
    -- フォルダが無ければ何もしない
    if vim.fn.isdirectory(root) ~= 1 then return end
    -- 条件に合うファイルを再帰的に探す(template.nim は毎回読み込み済みなので除く)
    local files = vim.fs.find(function(name)
      return name:match("%." .. ext .. "$") and name ~= "template.nim"
    end, { path = root, type = "file", limit = math.huge })
    -- 見つかったファイルを1つずつ候補にする
    for _, path in ipairs(files) do
      -- フォルダ名を除いた相対パス
      local rel = path:sub(#root + 2)
      -- 拡張子を除いたファイル名
      local name = vim.fn.fnamemodify(path, ":t:r")
      table.insert(entries, {
        -- プレビューで読むファイルの場所
        path = path,
        -- 一覧に表示する文字列
        display = rel .. "  [" .. origin .. "]",
        -- 検索対象の文字列(相対パス + ファイル本文)
        ordinal = rel .. " " .. ordinal_extra(name) .. read_file_text(path),
        -- 選んだ時に挿入する宣言文
        declaration = declaration_of(rel, name),
      })
    end
  end

  -- cp-nim-lib の .nim は include "相対パス" を挿入する
  add(lib_root, "nim", "cp-nim-lib", "include",
    function(rel) return ('include "%s"'):format(rel) end,
    function() return "" end)
  -- nim-acl の本体(src)の .nim は import atcoder/名前 を挿入する
  add(acl_root .. "/src", "nim", "nim-acl", "import",
    function(_, name) return "import atcoder/" .. name end,
    function(name) return "atcoder/" .. name .. " " end)
  -- nim-acl の解説(notes)の .md も、同じ import atcoder/名前 を挿入する
  add(acl_root .. "/notes", "md", "nim-acl notes", "import",
    function(_, name) return "import atcoder/" .. name end,
    function(name) return "atcoder/" .. name .. " " end)

  -- まとめた候補を返す
  return entries
end

-- 宣言文を import / include の並びの最後に1行追加する(すでにあれば追加しない)
local function add_declaration_once(bufnr, declaration)
  -- バッファの全行を取り出す
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- 挿入位置(初期値は先頭)
  local insert_at = 0
  -- 1行ずつ調べる
  for i, line in ipairs(lines) do
    -- 同じ宣言がすでにあれば、知らせて終わる
    if vim.trim(line) == declaration then
      vim.notify("Already declared: " .. declaration)
      return
    end
    -- include / import の行なら、その直後を挿入位置にする
    if line:match("^%s*include%s+") or line:match("^%s*import%s+") then insert_at = i end
  end
  -- 決めた位置に宣言を1行挿入する
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { declaration })
end

-- 両ピッカー共通のキー割り当て: Ctrl-d / Ctrl-u でプレビューをスクロールする
local function map_preview_scroll(map)
  local actions = require("telescope.actions")
  map({ "i", "n" }, "<C-d>", actions.preview_scrolling_down)
  map({ "i", "n" }, "<C-u>", actions.preview_scrolling_up)
end

-- ライブラリ検索画面を開く
local function search_library(lib_root, acl_root)
  -- 必要なTelescopeのモジュールを読み込む
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  -- 挿入先は、画面を開く前のバッファ
  local bufnr = vim.api.nvim_get_current_buf()

  -- 検索画面を作って開く(1つ目の表が配置、2つ目の表が中身)
  pickers.new({
    -- ファイルのプレビュー
    previewer = file_previewer(),
    -- 横並びで、プレビューを幅の55%にする
    layout_strategy = "horizontal",
    layout_config = { preview_width = 0.55 },
  }, {
    -- 画面のタイトル
    prompt_title = "Include / Import library",
    -- 候補の一覧
    finder = finders.new_table({
      results = collect_library_entries(lib_root, acl_root),
      -- 候補1件を、Telescopeが扱う形に変える
      entry_maker = function(e)
        return { value = e, display = e.display, ordinal = e.ordinal, path = e.path }
      end,
    }),
    -- 空白区切りのAND部分一致で絞り込む
    sorter = and_substring_sorter(),
    -- キー割り当てを設定する
    attach_mappings = function(prompt_bufnr, map)
      -- Enterを押した時の動作を差し替える
      actions.select_default:replace(function()
        -- 選ばれた候補を取り出し、画面を閉じる
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        -- 画面が閉じた後に、宣言を挿入する
        vim.schedule(function() add_declaration_once(bufnr, selection.value.declaration) end)
      end)
      -- プレビューのスクロールキーを割り当てる
      map_preview_scroll(map)
      return true
    end,
  }):find()
end

-- ============================================================
-- <leader>fs / <C-g>s: Snippet と標準ライブラリを検索して展開する
-- ============================================================
-- 候補は2種類ある
--   kind が無い  : LuaSnip のスニペットそのもの
--   kind="stdlib": ripgrepで集めた関数から作った疑似候補(標準ライブラリ、nim-acl、cp-nim-lib)

-- 一覧を「名前」と「説明」の2列で表示する仕組みを作る
local entry_display = require("telescope.pickers.entry_display")
local displayer = entry_display.create({
  separator = " ",
  items = { { width = 24 }, { remaining = true } },
})

-- 候補の名前を返す
local function name_of(item)
  -- 疑似候補は表示名、スニペットは name か trigger を使う
  if item.kind == "stdlib" then return item.display_name end
  return item.name or item.trigger or ""
end

-- 候補の説明を返す(未設定なら空文字)
local function description_of(item)
  -- 疑似候補は、元の宣言に付いた ## コメントを使う
  if item.kind == "stdlib" then return item.description or "" end
  -- スニペットの説明を取り出す(複数行なら1行につなぐ)
  local desc = item.dscr or ""
  if type(desc) == "table" then desc = table.concat(desc, " ") end
  -- LuaSnipは説明が無いとき名前を入れてしまうので、名前と同じなら未設定として空にする
  if desc == name_of(item) or desc == (item.trigger or "") then return "" end
  return desc
end

-- 検索対象の文字列(トリガー、名前、説明など)を作る
local function ordinal_of(item)
  -- 疑似候補は、シグネチャとライブラリ名も検索対象に含める
  if item.kind == "stdlib" then
    return table.concat({ item.trigger or "", item.display_name or "", item.description or "", item.signature or "", item.library or "" }, " ")
  end
  -- スニペットは、トリガー、名前、説明を検索対象にする
  return table.concat({ item.trigger or "", name_of(item), description_of(item) }, " ")
end

-- Snippet検索のプレビューを作る。get_ufcs は UFCS 展開かどうかを返す関数
local function snippet_previewer(get_ufcs)
  -- プレビュー作成モジュールを読み込む
  local previewers = require("telescope.previewers")
  -- プレビュー用のバッファを使う仕組みを作って返す
  return previewers.new_buffer_previewer({
    -- プレビュー枠のタイトル
    title = "Preview",
    -- 選択が変わるたびに呼ばれ、プレビューの中身を作る
    define_preview = function(self, entry)
      -- 選ばれた候補
      local item = entry.value
      -- 上段: 名前、説明、区切り線
      local lines = { "Name: " .. name_of(item), "", description_of(item), "", "---", "" }

      -- 下段: 展開した結果
      if item.kind == "stdlib" then
        -- 展開後の文字列を作る(UFCS なら先頭の引数を除く)
        local ufcs = get_ufcs()
        local body = lib_scan.build_snippet_body(item.source_text, { ufcs = ufcs })
        -- 作れたらそのまま、作れなければ理由を載せる
        table.insert(lines, body or (ufcs and "(UFCS不可: レシーバに渡せる引数がありません)" or "(snippet生成に失敗しました)"))
        -- 元の宣言とライブラリ名を続ける
        vim.list_extend(lines, { "", item.signature or "", "", "library: " .. (item.library or "") })
      else
        -- スニペットの展開例(docstring)を取り出す
        local ok, doc = pcall(function() return item:get_docstring() end)
        -- 取れなければ、その旨を載せる
        if not ok or not doc then doc = "(preview unavailable)" end
        -- 文字列なら行ごとに分けて追加する
        vim.list_extend(lines, type(doc) == "string" and vim.split(doc, "\n") or doc)
      end

      -- プレビューのバッファに書き込む
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      -- 色付けはsyntaxで行う(filetypeにするとFileTypeの自動処理が動いてエラーになる)
      vim.bo[self.state.bufnr].syntax = "nim"
      -- 長い行を折り返して全文を見せる(単語の途中で切らず、字下げを揃え、続きの行に矢印を付ける)
      local win = self.state.winid
      vim.wo[win].wrap = true
      vim.wo[win].linebreak = true
      vim.wo[win].breakindent = true
      vim.wo[win].showbreak = "↳ "
    end,
  })
end

-- rg で集めた1件を、検索・展開に使う疑似候補に変える(展開できないものは nil)
local function to_stdlib_item(raw)
  -- 通常呼び出し用の展開文字列を作る
  local body = lib_scan.build_snippet_body(raw.text)
  -- 作れなければ候補にしない
  if not body then return nil end
  -- 展開文字列の先頭の関数名を取り出す
  local name = body:match("^([%w_]+)%(") or raw.text
  -- 疑似候補を返す
  return {
    kind = "stdlib",
    -- 検索と表示に使う名前
    trigger = name,
    display_name = name,
    -- 説明(## コメントの本文)
    description = raw.doc,
    -- 元のNim宣言(プレビュー表示用)
    signature = raw.text,
    -- UFCS展開を作り直すための元の文字列
    source_text = raw.text,
    -- 通常呼び出しの展開文字列
    snippet_body = body,
    -- 出どころの表示用ラベル(std/strutils など)
    library = lib_scan.module_label(raw.file),
  }
end

-- 展開した直後に、引数のヒント表示(lsp_signature)を開く
local function trigger_signature_help()
  -- 展開が終わってから実行する
  vim.schedule(function()
    -- lsp_signature があればそれを、無ければ標準のシグネチャヘルプを開く
    local ok, sig = pcall(require, "lsp_signature")
    if ok then sig.toggle_float_win() else vim.lsp.buf.signature_help() end
  end)
end

-- Snippet と標準ライブラリの検索画面を開く。ufcs が true なら、レシーバ付き呼び出しで展開する
local function search_snippets(ufcs)
  -- 必要なモジュールを読み込む
  local luasnip = require("luasnip")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  -- 候補を貯める表
  local results = {}
  -- UFCS のときは、レシーバの概念が無い通常スニペットを除く
  if not ufcs then
    vim.list_extend(results, luasnip.get_snippets(vim.bo.filetype) or {})
  end
  -- 標準ライブラリなどの関数を集めて、疑似候補にして追加する
  for _, raw in ipairs(lib_scan.scan()) do
    local item = to_stdlib_item(raw)
    if item then table.insert(results, item) end
  end

  -- 検索画面を作って開く(1つ目の表が配置、2つ目の表が中身)
  pickers.new({
    -- 展開結果のプレビュー
    previewer = snippet_previewer(function() return ufcs end),
    -- 横並びで、画面を左右半分ずつにする
    layout_strategy = "horizontal",
    layout_config = { preview_width = 0.5 },
  }, {
    -- 画面のタイトル(UFCSのときは印を付ける)
    prompt_title = ufcs and "Snippet + StdLib  [UFCS]" or "Snippet + StdLib",
    -- 候補の一覧
    finder = finders.new_table({
      results = results,
      -- 候補1件を、Telescopeが扱う形に変える
      entry_maker = function(item)
        return {
          value = item,
          ordinal = ordinal_of(item),
          display = function(e)
            return displayer({ name_of(e.value), description_of(e.value) })
          end,
        }
      end,
    }),
    -- 空白区切りのAND部分一致で絞り込む(日本語の説明も安定して検索できる)
    sorter = and_substring_sorter(),
    -- キー割り当てを設定する
    attach_mappings = function(prompt_bufnr, map)
      -- Enterを押した時の動作を差し替える
      actions.select_default:replace(function()
        -- 選ばれた候補を取り出し、画面を閉じる
        local item = action_state.get_selected_entry().value
        actions.close(prompt_bufnr)
        -- 画面が閉じた後に展開する
        vim.schedule(function()
          if item.kind == "stdlib" then
            -- UFCS なら先頭の引数を除いた展開文字列を作り直し、通常なら用意済みのものを使う
            local body = ufcs and lib_scan.build_snippet_body(item.source_text, { ufcs = true }) or item.snippet_body
            -- UFCS で作れなければ知らせて終わる
            if not body then
              vim.notify("UFCSでは呼べません: " .. item.display_name, vim.log.levels.WARN)
              return
            end
            -- 展開文字列をスニペットとして展開する
            luasnip.lsp_expand(body)
          else
            -- 通常のスニペットはそのまま展開する
            luasnip.snip_expand(item)
          end
          -- 展開後に引数のヒントを開く
          trigger_signature_help()
        end)
      end)
      -- プレビューのスクロールキーを割り当てる
      map_preview_scroll(map)
      return true
    end,
  }):find()
end

-- ============================================================
-- .nvim.lua から呼ぶ入口
-- ============================================================

-- 3つの検索入口のキー割り当てを登録する
function M.setup(project_root)
  -- 各リポジトリは、このプロジェクトと同じ階層に並べて置いてある
  local parent = vim.fn.fnamemodify(project_root, ":h")
  local solved_log_root = parent .. "/cp-solved-log"
  local lib_root = parent .. "/cp-nim-lib"
  local acl_root = parent .. "/nim-acl"

  -- cp-solved-log を読み取り専用にする
  setup_readonly_solved_log(solved_log_root)

  -- 検索を始める前に、現在のquickfixを保存する関数を使ってキーを登録する
  local function map(mode, lhs, fn, desc)
    vim.keymap.set(mode, lhs, function()
      qf_session.save()
      fn()
    end, { desc = desc })
  end

  -- <leader>fa: 過去解答を検索する
  map("n", "<leader>fa", function() search_solved_log(solved_log_root) end, "過去解答を検索(読み取り専用)")
  -- <leader>fi: ライブラリを選んで include / import を挿入する
  map("n", "<leader>fi", function() search_library(lib_root, acl_root) end, "ライブラリを検索してinclude/importを挿入")
  -- <leader>fs: Snippet と標準ライブラリを検索して展開する
  map("n", "<leader>fs", function() search_snippets(cursor_is_after_dot()) end, "Snippet + StdLibを検索して展開")
  -- <C-g>s: 同じ検索をインサートモードのまま起動する
  map("i", "<C-g>s", function() search_snippets(cursor_is_after_dot()) end, "Snippet + StdLibを検索して展開(インサート)")
end

-- 公開テーブルを返す
return M
