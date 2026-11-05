-- atcoder-nim.nim_lib_scan: cp-nim-lib と Nim標準ライブラリから、公開された proc / func / template / iterator を集める
-- 説明文(## コメント)が付いた関数だけを候補にし、呼び出し用のスニペット文字列も作る
-- nim-acl は対象外(import は <leader>fi が担い、型を見て絞れる LSP の方が正確なため)

-- このモジュールの公開テーブルを用意する
local M = {}

-- Nim標準ライブラリの場所(Nimを更新して名前が変わったら、この1行だけ直す)
local stdlib_root = "/home/dev/.choosenim/toolchains/nim-2.2.4/lib"

-- 探す場所の一覧(path: 場所、library: 表示に使うライブラリ名)
local search_dirs = {
  { path = "/workspace/cp-nim-lib", library = "cp-nim-lib" },
  { path = stdlib_root, library = "std" },
}

-- rg で探す宣言の形: 名前の末尾に * が付いた(=公開の) proc / func / template / iterator
-- 名前は通常の識別子のほか、`[]` や `$` のようなバッククォート付きも拾う
local rg_pattern = [[^\s*(proc|func|template|iterator)\s+(`[^`]+`|[A-Za-z_][A-Za-z0-9_]*)\*]]

-- ファイルの場所から、表示用の名前を作る(例: .../lib/pure/strutils.nim -> std/strutils)
local function make_library_name(root, library, file)
  -- ライブラリの場所より後ろの部分から、拡張子 .nim を除く
  local rel = file:sub(#root + 2):gsub("%.nim$", "")
  -- 標準ライブラリの pure/ と std/ は内部のフォルダ名なので、表示では省く
  if library == "std" then
    rel = rel:gsub("^pure/", ""):gsub("^std/", "")
  end
  -- 「ライブラリ名/相対パス」の形にして返す
  return library .. "/" .. rel
end

-- ファイルの場所だけから表示用の名前を作る(どの探す場所にも属さなければ、場所をそのまま返す)
function M.module_label(file)
  -- 探す場所を順に調べる
  for _, source in ipairs(search_dirs) do
    -- ファイルの場所が、その場所の配下なら名前を作って返す
    if file:sub(1, #source.path) == source.path then
      return make_library_name(source.path, source.library, file)
    end
  end
  -- どこにも属さなければ、場所をそのまま返す
  return file
end

-- 行から ## や ##- を外して、説明の本文だけにする(gsubの2つ目の戻り値を捨てるため、一度変数に受ける)
local function strip_doc_prefix(line)
  local stripped = vim.trim(line):gsub("^##%-?%s*", "")
  return stripped
end

-- 行が proc / func / template / iterator の宣言の始まりかどうかを返す
local function is_declaration(trimmed)
  -- Luaの検索パターンには「または」が無いので、4つを順に試す
  for _, kw in ipairs({ "proc", "func", "template", "iterator" }) do
    if trimmed:match("^" .. kw .. "%s+") then return true end
  end
  return false
end

-- 行番号 from から続く ## コメントを集めて返す。step が -1 なら上向き、1 なら下向きに進む
local function collect_doc_run(lines, from, step)
  -- 集めた説明の行
  local docs = {}
  -- 行番号が範囲内で、かつ ## で始まる間だけ進む
  local i = from
  while lines[i] and vim.trim(lines[i]):match("^##") do
    -- 上向きなら先頭に、下向きなら末尾に加えて、元の並び順を保つ
    table.insert(docs, step < 0 and 1 or #docs + 1, strip_doc_prefix(lines[i]))
    i = i + step
  end
  return docs
end

-- 宣言の説明を集める。宣言の直前の ## コメントを優先し、無ければ直後(標準ライブラリの書き方)を探す
local function collect_doc_lines(lines, decl_lnum)
  -- 直前に ## コメントがあれば、それを使う
  local before = collect_doc_run(lines, decl_lnum - 1, -1)
  if #before > 0 then return before end
  -- 直後は、宣言が複数行にまたがる場合を考えて、最大12行先まで探す
  for i = decl_lnum + 1, math.min(#lines, decl_lnum + 12) do
    local trimmed = vim.trim(lines[i])
    -- 最初に見つかった ## コメントの並びを使う
    if trimmed:match("^##") then return collect_doc_run(lines, i, 1) end
    -- 先に次の宣言が現れたら、説明は無かったものとして打ち切る
    if is_declaration(trimmed) then break end
  end
  -- 説明は見つからなかった
  return {}
end

-- 公開された宣言を集めて返す。各要素は file(場所)、text(宣言の1行)、doc(説明の本文)
function M.scan()
  -- 結果を貯める表
  local results = {}
  -- 読み込んだファイルの中身を、使い回すために覚えておく表
  local file_cache = {}

  -- 探す場所を順に調べる
  for _, source in ipairs(search_dirs) do
    -- その場所が存在するときだけ調べる
    if vim.fn.isdirectory(source.path) == 1 then
      -- rg で宣言の位置を JSON で列挙する(説明の判定は、自分でファイルを読んで行う)
      local raw_lines = vim.fn.systemlist({ "rg", "--json", "--glob", "*.nim", "-e", rg_pattern, source.path })
      -- 出力を1行ずつ調べる
      for _, raw in ipairs(raw_lines) do
        -- JSON を読み取る(壊れた行は読み飛ばす)
        local ok, event = pcall(vim.json.decode, raw)
        -- 見つかった宣言(match)だけを扱う
        if ok and type(event) == "table" and event.type == "match" then
          -- 見つかったファイルの場所と行番号
          local file = event.data.path.text
          local lnum = event.data.line_number
          -- ファイルの中身を読み込む(一度読んだものは使い回す)
          file_cache[file] = file_cache[file] or vim.fn.readfile(file)
          -- その宣言の説明を集める
          local doc_lines = collect_doc_lines(file_cache[file], lnum)
          -- 説明が付いた宣言だけを候補に加える
          if #doc_lines > 0 then
            table.insert(results, {
              -- ファイルの場所
              file = file,
              -- 宣言の1行(末尾の改行を除く)
              text = vim.trim(event.data.lines.text or ""),
              -- 説明の本文(複数行は空白でつなぐ)
              doc = table.concat(doc_lines, " "),
            })
          end
        end
      end
    end
  end

  -- 集めた結果を返す
  return results
end

-- Nimの宣言の1行から、関数名と引数名の一覧を取り出す(取り出せなければ nil)
-- 1行で終わる宣言が対象。複数行の宣言などは候補から外れる
local function parse_signature(text)
  -- 型引数 [T] を挟む形 (func sum*[T](x: openArray[T]): T) を先に試す
  local name, paramstr = text:match("^%a+%s+([%w_]+)%*?%b[]%s*%((.*)%)%s*:?.*$")
  -- 無ければ、型引数なしの形 (proc foo*(a: int): int) を試す
  if not name then
    name, paramstr = text:match("^%a+%s+([%w_]+)%*?%s*%((.*)%)%s*:?.*$")
  end
  -- どちらにも合わなければ、取り出せない
  if not name then return nil end

  -- 引数名を貯める表
  local params = {}
  -- カンマで区切って、各引数の先頭の名前だけを取り出す
  for part in paramstr:gmatch("[^,]+") do
    local pname = part:match("^%s*([%w_]+)")
    if pname then table.insert(params, pname) end
  end
  -- 関数名と引数名の一覧を返す
  return { name = name, params = params }
end

-- LSP のスニペット形式の文字列を作る(例: sum(${1:a}, ${2:initial})$0)
-- opts.ufcs が true なら、先頭の引数は a.sum(...) の a として渡し済みとみなして除く
-- 引数が無い関数を UFCS で呼ぶことはできないので、その場合は nil を返す
function M.build_snippet_body(text, opts)
  -- 宣言から関数名と引数名を取り出す(できなければ nil)
  local sig = parse_signature(text)
  if not sig then return nil end

  -- 使う引数名の一覧
  local params = sig.params
  -- UFCS のときは先頭の引数を除く
  if opts and opts.ufcs then
    -- 除く引数が無ければ、UFCS では呼べない
    if #params == 0 then return nil end
    params = { unpack(params, 2) }
  end

  -- 引数が無ければ、カーソルを括弧の中に置く
  if #params == 0 then return sig.name .. "($0)" end

  -- 各引数を ${番号:名前} の形に変える
  local placeholders = {}
  for i, pname in ipairs(params) do
    table.insert(placeholders, ("${%d:%s}"):format(i, pname))
  end
  -- 関数名と括弧でつなぎ、最後にカーソル位置 $0 を置いて返す
  return sig.name .. "(" .. table.concat(placeholders, ", ") .. ")$0"
end

-- 公開テーブルを返す
return M
