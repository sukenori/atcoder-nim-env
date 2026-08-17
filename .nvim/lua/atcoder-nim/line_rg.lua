-- atcoder-nim.line_rg — 「自分が既に書いた行」をそのまま補完候補として出す、
-- cmp用のプロジェクトローカルsource。
--
-- 以前は .nvim/scope_dirs.txt に複数ディレクトリ
-- （cp-nim-lib / cp-solved-log 等）を列挙して横断検索していたが、
-- 「ライブラリの検索」「snippetの検索」はTelescope側の入口へ移した:
--   - ライブラリを使う → cp-nim-lib / nim-acl を対象にした import/include picker
--   - 定型を置く       → snippet picker
--
-- 一方「過去に書いた行の続きを速く補う」という用途については、
-- 量そのものが cp-solved-log に蓄積されているため、
-- 検索対象を現在のプロジェクトルート一つに絞ると候補が枯渇してしまう。
-- そのためこの source では、現在のプロジェクトルートに加えて
-- cp-solved-log（sibling directory）も検索対象にする。
-- .nvim/scope_dirs.txt という外部設定ファイル自体はもう不要
-- （検索先はここでコード側に直接書く）。


local M = {}


-- プロジェクトルートを一度だけ特定してキャッシュする。
-- .nvim.lua をこのプロジェクトのアンカーとして使う既存方針に合わせ、
-- Gitリポジトリのトップを「プロジェクトルート」とみなす。
local cached_root = nil


local function project_root()
  if cached_root then
    return cached_root
  end


  local result = vim.system(
    { "git", "rev-parse", "--show-toplevel" },
    { text = true }
  ):wait()


  if result.code == 0 and result.stdout then
    cached_root = vim.trim(result.stdout)
  end


  return cached_root
end


-- cp-solved-log は atcoder-nim-env と同じ階層に置く sibling directory。
-- telescope_cp.lua の sibling() と同じ考え方をここでも使う。
local function sibling(root, name)
  return vim.fn.fnamemodify(root, ":h") .. "/" .. name
end


-- ripgrep を使って行単位の補完を行うためのソースのオブジェクト
local cp_source = {}


function cp_source:new()
  return setmetatable({}, { __index = cp_source })
end


-- 補完のトリガーは「空白以外の文字からカーソル位置まで」の正規表現
function cp_source:get_keyword_pattern()
  return [[\S.*]]
end


-- 補完処理
function cp_source:complete(request, callback)
  local cmp = require("cmp")


  -- 行頭からカーソル位置までの全体から、補完の開始位置（offset）から末尾までを切り出し
  local input = request.context.cursor_before_line:sub(request.offset)
  -- 念のため、空白を取り除く
  input = vim.trim(input)


  -- 入力が空文字列なら、候補なしで終了する（空文字を渡すと全行に一致してしまう）
  if input == "" then
    callback({ items = {}, isIncomplete = false })
    return
  end


  local root = project_root()
  if not root then
    callback({ items = {}, isIncomplete = false })
    return
  end


  -- 検索対象は「今のプロジェクトルート」だけでなく、cp-solved-log も含める。
  -- ここを現在プロジェクトだけに絞ると、量そのものが少なく候補が枯渇する
  -- （for や let のような頻出語すら1件も出ない、という事故が実際に起きた）。
  -- cp-solved-log は読み取り専用の実例集だが、ここでは検索対象として
  -- 使うだけで書き込みは一切しないので、read-only方針とは矛盾しない。
  local search_paths = { root }
  local cp_solved_log_root = sibling(root, "cp-solved-log")
  if vim.fn.isdirectory(cp_solved_log_root) == 1 then
    table.insert(search_paths, cp_solved_log_root)
  end


  -- ripgrep の実行コマンドと引数を定義
  local cmd = {
    "rg",              -- ripgrepを呼ぶコマンド名
    "-F",              -- --fixed-strings 入力文字列（input）を正規表現としてではなく、ただの文字列としてそのまま検索させる（*や.といった記号が含まれていてもエラーにならない）
    "--no-heading",    -- ripgrepが返す「どのファイルで見つかったか」の見出しの出力をオフに
    "--no-filename",   -- 先頭に付く「ファイル名:」という出力もオフに（「見つけた行のテキストだけ」を取得）
    "--smart-case",    -- キーワードがすべて小文字なら大文字・小文字を区別しない、大文字が1文字でも含まれていたら厳密に区別して探す
    "--color=never",   -- 見つかった文字を赤くハイライトするなどの色付けを禁止（エスケープシーケンスが挿入されてテキストデータとして扱いにくくなるため）
    "--no-ignore",     -- work/ のような .gitignore 対象のスクラッチファイルも検索対象にする
    "--glob", "*.nim", -- このプロジェクトの検索対象はNimファイルのみでよい（グローバル変数化しない）
    input,             -- 検索する文字列
  }
  -- 検索対象ディレクトリを末尾にすべて積む（rgは複数PATH引数を受け付ける）
  for _, path in ipairs(search_paths) do
    table.insert(cmd, path)
  end


  -- リクエストごとに世代番号を進め、古い非同期結果が新しい入力を
  -- 上書きしてしまう（レースコンディション）のを防ぐ
  self._generation = (self._generation or 0) + 1
  local my_generation = self._generation


  -- ripgrep の実行結果を受け取って、補完候補のリストを作成する
  local function build_items(stdout, code)
    local items = {}
    -- コマンドが成功して出力がある場合、重複チェック用のテーブルを用意
    if code == 0 and stdout then
      local seen = {}
      for line in string.gmatch(stdout, "[^\r\n]+") do
        -- 各行の前後の空白を取り除き、入力中の文字列よりも長く、かつ入力文字列から始まっていて、まだリストにない文字列を抽出
        local text = vim.trim(line)
        if #text > #input and vim.startswith(text, input) and not seen[text] then
          -- 抽出した文字列に対し、重複チェックのフラグを立て、補完候補のデータ形式に整形してリストに追加
          seen[text] = true
          table.insert(items, {
            label = text,
            insertText = text,
            kind = cmp.lsp.CompletionItemKind.Text,
          })
        end
      end
    end


    return items
  end


  -- 非同期で ripgrep コマンドを実行（.system）し、完了後に build_items 関数で候補リストを作成、Neovim のメイン処理に結果を渡して補完メニューを表示させる
  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      -- 検索中に入力が進み、別のcompleteが後から呼ばれていたら
      -- この古い結果は捨てて何も返さない
      if my_generation ~= self._generation then
        return
      end


      local items = build_items(obj.stdout, obj.code)
      -- isIncomplete は不完全かどうか（追加検索の必要性）
      callback({ items = items, isIncomplete = false })
    end)
  end)
end


-- format.lua / lsp.lua / make_runner.lua と同じく、
-- .nvim.lua から setup() を一回呼ぶだけで完結させる。
local registered = false


function M.setup()
  local cmp = require("cmp")


  -- "line_rg" という名前で nvim-cmp に登録する（冪等）
  if not registered then
    cmp.register_source("line_rg", cp_source:new())
    registered = true
  end


  -- FileType autocmd + cmp.setup.buffer だと、既に開いているバッファの
  -- FileTypeイベントがこの登録より先に発火していた場合に取りこぼす
  -- （nvim foo.nim のように最初からnimファイルを開いて起動した場合など）。
  -- cmp.setup.filetype はcmp内部で「そのfiletypeなら常に適用」されるため、
  -- 起動タイミングに依存しない。
  cmp.setup.filetype("nim", {
    sources = cmp.config.sources({
      { name = "luasnip" },
      { name = "line_rg" },
      { name = "nvim_lsp" },
    }),
  })
end


return M