-- atcoder-nim.line_rg — 「このプロジェクト内で自分が既に書いた行」を
-- そのまま補完候補として出す、cmp用のプロジェクトローカルsource。
--
-- 以前は .nvim/scope_dirs.txt に複数ディレクトリ
-- （cp-nim-lib / cp-solved-log 等）を列挙して横断検索していたが、
-- それらは役割が重複するためTelescope側の三つの入口へ移した:
--   - 過去解答を読む   → cp-solved-log を対象にした live_grep（read-only）
--   - ライブラリを使う → cp-nim-lib / nim-acl を対象にした import/include picker
--   - 定型を置く       → snippet picker
--
-- この source が担うのは「今書いている問題ファイルの中で、
-- さっき書いた行の続きを速く補う」というローカルな用途だけなので、
-- 検索対象は現在のプロジェクトルート一つに固定してよく、
-- .nvim/scope_dirs.txt という外部設定ファイルはもう不要。

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

  -- 検索対象は「今のプロジェクトルート」一つだけ。
  -- 外部リポジトリ（cp-nim-lib, cp-solved-log, nim-acl）は
  -- Telescope側の専用pickerで明示的に検索する運用にしたため、
  -- ここでは横断しない。
  local root = project_root()
  if not root then
    callback({ items = {}, isIncomplete = false })
    return
  end

  -- ripgrep の実行コマンドと引数を定義
  local cmd = {
    "rg",              -- ripgrepを呼ぶコマンド名
    "-F",              -- --fixed-strings 入力文字列（input）を正規表現としてではなく、ただの文字列としてそのまま検索させる（*や.といった記号が含まれていてもエラーにならない）
    "--no-heading",    -- ripgrepが返す「どのファイルで見つかったか」の見出しの出力をオフに
    "--no-filename",   -- 先頭に付く「ファイル名:」という出力もオフに（「見つけた行のテキストだけ」を取得）
    "--smart-case",    -- キーワードがすべて小文字なら大文字・小文字を区別しない、大文字が1文字でも含まれていたら厳密に区別して探す
    "--color=never",   -- 見つかった文字を赤くハイライトするなどの色付けを禁止（エスケープシーケンスが挿入されてテキストデータとして扱いにくくなるため）
    "--glob", "*.nim", -- このプロジェクトの検索対象はNimファイルのみでよい（グローバル変数化しない）
    input,             -- 検索する文字列
    root,              -- 検索対象ディレクトリ（プロジェクトルート一つだけ）
  }

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
-- 「sourceの登録」と「Nimバッファへの適用（cmp.setup.buffer）」の
-- 両方をここに閉じ込めることで、.nvim.lua 側には一行しか残らない。
local registered = false

function M.setup()
  local cmp = require("cmp")

  -- "line_rg" という名前で nvim-cmp に登録する（冪等）
  if not registered then
    cmp.register_source("line_rg", cp_source:new())
    registered = true
  end

  -- Nimバッファを開いたときだけ、buffer単位でsourceを追加する。
  -- dotfiles側の共通 cmp.lua（luasnip / nvim_lsp の2本）には触れず、
  -- このプロジェクトのNimバッファにだけ line_rg を積み増す形にする。
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("AtcoderNimLineRg", { clear = true }),
    pattern = "nim",
    callback = function()
      cmp.setup.buffer({
        sources = cmp.config.sources({
          { name = "luasnip" },
          { name = "line_rg" },
          { name = "nvim_lsp" },
        }),
      })
    end,
  })
end

return M