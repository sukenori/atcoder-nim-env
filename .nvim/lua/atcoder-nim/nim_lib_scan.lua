-- atcoder-nim.nim_lib_scan
--
-- 標準ライブラリ・cp-nim-libから、
-- public な proc / func / template / iterator を収集する。
--
-- nim-aclはここでは扱わない。理由は次の2点。
--
--   1. nim-aclの発見・importは <leader>fi が既に担っている。
--      importした後は nvim_lsp が現在の文脈(実際にimportされているもの)
--      を解決してcmpの候補に出すので、ここでもう一度拾う必要がない。
--
--   2. nim-aclの関数はDsu/FenwickTree/ModIntのような構造体のメソッドが多く、
--      実際にはUFCS(uf.merge(a, b)のような書き方)で呼ぶのが前提になる。
--      この呼び方の正しさは「uf の実際の型」を見て判定する必要があるが、
--      ここでのUFCS対応は宣言テキストから先頭引数を機械的に外すだけで、
--      型を見ていない。オブジェクト指向的なnim-aclのAPIに対しては、
--      型を見て候補を絞れるLSP(cmp経由)の方が正確で安全。
--
-- 一方cp-nim-libは素の関数(bfs, gridNeighborsなど)が中心で、
-- 呼び出しテンプレートをその場で組み立てる価値がまだ大きいため、
-- ここでは引き続き対象にする。
--
-- docコメントは、次の両方を扱う。
--
--   1. 宣言の直前にある ## コメント
--      - 自作ライブラリで採用している書き方
--
--   2. 宣言の直後にある ## コメント
--      - Nim標準ライブラリで多く使われている書き方
--
-- ## コメント本文は:
--   1. Telescope候補の説明文
--   2. Telescope検索対象
--   3. 右プレビューの説明文
-- に使う。
--
-- これにより、内部ヘルパーやdocコメントのない関数を候補から除外する。

local M = {}

-- 画像で確認した、現在のコンテナ内のNim標準ライブラリ。
-- Nimを更新してtoolchain名が変わったときだけ、この1行を更新する。
local stdlib_root = "/home/dev/.choosenim/toolchains/nim-2.2.4/lib"

M.search_dirs = {
  {
    path = "/workspace/cp-nim-lib",
    library = "cp-nim-lib",
  },
  {
    path = stdlib_root,
    library = "std",
  },
}

-- 公開シンボルだけを候補にする。
-- Nimの公開シンボルには名前末尾に * が付く。
--
-- 通常の識別子だけでなく、`[]` や `$` のようなバッククォート演算子も拾う。
local rg_pattern = [[^\s*(proc|func|template|iterator)\s+(`[^`]+`|[A-Za-z_][A-Za-z0-9_]*)\*]]

-- 各ライブラリの物理パスから、表示用の論理名を作る。
--
-- 例:
--   /.../lib/pure/strutils.nim       -> std/strutils
--   /.../lib/std/sequtils.nim        -> std/sequtils
--   /workspace/cp-nim-lib/Graph/BFS.nim
--                                      -> cp-nim-lib/Graph/BFS
local function make_library_name(root, library, file)
  local rel = file:sub(#root + 2)
  rel = rel:gsub("%.nim$", "")

  -- Nim標準ライブラリの pure/ と std/ は内部ディレクトリ名なので、
  -- UI上は std/strutils のように統一して見せる。
  if library == "std" then
    rel = rel:gsub("^pure/", "")
    rel = rel:gsub("^std/", "")
  end

  return library .. "/" .. rel
end

-- file (フルパス) だけから、対応する search_dirs のエントリを逆引きして
-- make_library_name を呼ぶ薄いラッパー。
function M.module_label(file)
  for _, source in ipairs(M.search_dirs) do
    local root = source.path

    if file:sub(1, #root) == root then
      return make_library_name(root, source.library, file)
    end
  end

  return file
end

-- ##、##-、## などを外して説明本文だけにする。
--
-- string.gsub は「変換後文字列」と「置換回数」の2値を返す。
-- ここでいったんローカル変数に受けることで、文字列だけを返す。
-- 呼び出し側で table.insert に直接 gsub の戻り値を渡すと、
-- 第2引数・第3引数に展開されてエラーになるため、ここで1値に絞る。
local function strip_doc_prefix(line)
  local stripped = vim.trim(line):gsub("^##%-?%s*", "")
  return stripped
end

-- 宣言の直前に連続している ## コメントを拾う。
--
-- 例:
--
--   ## 文字列を整数へ変換する。
--   proc parse*(s: string): int =
local function collect_doc_lines_before(lines, decl_lnum)
  local doc_lines = {}
  local i = decl_lnum - 1

  while i >= 1 do
    local trimmed = vim.trim(lines[i])

    if not trimmed:match("^##") then
      break
    end

    table.insert(doc_lines, 1, strip_doc_prefix(lines[i]))
    i = i - 1
  end

  return doc_lines
end

-- 宣言の直後に連続している ## コメントを拾う。
--
-- Nim標準ライブラリでは次の形が多い。
--
--   proc parseInt*(s: string): int =
--     ## Parses a decimal integer from `s`.
--
-- 宣言が複数行にまたがる場合にも対応するため、宣言開始行から
-- 最大12行先までで最初に現れる ## コメント列を採用する。
--
-- 途中で次のproc / func / template / iteratorが現れた場合は、
-- 元の宣言にdocコメントがなかったものとして中断する。
local function collect_doc_lines_after(lines, decl_lnum)
  local doc_lines = {}
  local last_lnum = math.min(#lines, decl_lnum + 12)

  for i = decl_lnum + 1, last_lnum do
    local trimmed = vim.trim(lines[i])

    if trimmed:match("^##") then
      while i <= #lines do
        local doc_trimmed = vim.trim(lines[i])

        if not doc_trimmed:match("^##") then
          break
        end

        table.insert(doc_lines, strip_doc_prefix(lines[i]))
        i = i + 1
      end

      return doc_lines
    end

    if trimmed:match("^(proc|func|template|iterator)%s+") then
      break
    end
  end

  return doc_lines
end

-- 前置形式・後置形式のどちらのdocコメントも扱う。
--
-- 両方あった場合は、宣言直前のコメントを優先する。
-- 自作ライブラリで従来どおりの挙動を保つため。
local function collect_doc_lines(lines, decl_lnum)
  local before = collect_doc_lines_before(lines, decl_lnum)

  if #before > 0 then
    return before
  end

  return collect_doc_lines_after(lines, decl_lnum)
end

-- fileごとの内容をキャッシュしながら読み込む。
-- scan中に同じファイルの公開シンボルを何件も処理するので、
-- 毎回readfileしないようにする。
local function read_lines_cached(cache, file)
  if cache[file] ~= nil then
    return cache[file]
  end

  local ok, lines = pcall(vim.fn.readfile, file)

  if not ok then
    cache[file] = false
    return nil
  end

  cache[file] = lines
  return lines
end

-- ripgrepで公開宣言の位置だけを高速に列挙し、
-- docコメントの判定は元ファイルを直接読んで行う。
--
-- --jsonを使うのは、ファイルパスと行番号を安全に受け取るため。
-- -B / -A は使わない。
-- docコメントが宣言の前後どちらにあるかをLua側で判定するため。
function M.scan()
  local results = {}
  local file_cache = {}

  for _, source in ipairs(M.search_dirs) do
    if vim.fn.isdirectory(source.path) == 1 then
      local cmd = {
        "rg",
        "--json",
        "--glob",
        "*.nim",
        "-e",
        rg_pattern,
        source.path,
      }

      local ok, raw_lines = pcall(vim.fn.systemlist, cmd)

      if ok then
        for _, raw in ipairs(raw_lines) do
          if raw ~= "" then
            local decoded_ok, event = pcall(vim.json.decode, raw)

            if decoded_ok and event and event.type == "match" and event.data then
              local data = event.data
              local file = data.path and data.path.text
              local lnum = data.line_number

              if file and lnum then
                local lines = read_lines_cached(file_cache, file)

                if lines then
                  local doc_lines = collect_doc_lines(lines, lnum)

                  -- docコメントを持つ関数だけ候補に採用する。
                  if #doc_lines > 0 then
                    local text = (data.lines and data.lines.text or ""):gsub("\n$", "")

                    table.insert(results, {
                      file = file,
                      lnum = lnum,
                      text = vim.trim(text),
                      doc = table.concat(doc_lines, " "),
                      library = make_library_name(
                        source.path,
                        source.library,
                        file
                      ),
                    })
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  return results
end

-- Nimシグネチャから、関数名と引数文字列を取り出す。
--
-- 現段階では「1行で完結する宣言」を対象にする。
-- 複数行宣言・特殊なgeneric制約・複雑なdefault値は候補から落ちる可能性がある。
-- 無理に壊れたテンプレートを出すより安全である。
--
-- generic引数 [T] や [T: SomeInteger] を挟む形にも対応する。
-- 例: func sum*[T](x: openArray[T]): T =
local function parse_signature(text)
  local kind, name, paramstr = text:match(
    "^(%a+)%s+([%w_]+)%*?%b[]%s*%((.*)%)%s*:?.*$"
  )

  if not name then
    kind, name, paramstr = text:match(
      "^(%a+)%s+([%w_]+)%*?%s*%((.*)%)%s*:?.*$"
    )
  end

  if not name then
    kind, name = text:match(
      "^(%a+)%s+([%w_]+)%*?%b[]%s*%(%s*%)"
    )
  end

  if not name then
    kind, name = text:match(
      "^(%a+)%s+([%w_]+)%*?%s*%(%s*%)"
    )
  end

  if not name then
    return nil
  end

  local params = {}

  if paramstr and paramstr ~= "" then
    for part in paramstr:gmatch("[^,]+") do
      local pname = part:match("^%s*([%w_]+)")

      if pname then
        table.insert(params, pname)
      end
    end
  end

  return {
    kind = kind,
    name = name,
    params = params,
  }
end

-- lsp_expandに渡すLSP snippet形式の本文を作る。
--
-- 通常呼び出し:
--   proc sum*(a: seq[int], initial: int = 0): int
--   -> sum(${1:a}, ${2:initial})$0
--
-- opts.ufcs = true の場合、先頭引数(レシーバ)は
-- 呼び出し元の "a." のように既に渡されているものとみなし、
-- プレースホルダーから除外する。
--
--   proc sum*(a: seq[int], initial: int = 0): int
--   -> sum(${1:initial})$0   （a.sum(initial) として使う前提）
--
-- 引数を1つも持たない関数をUFCSで呼ぼうとした場合は、
-- レシーバを消費する対象がないため nil を返す。
-- 呼び出し側はこれを「UFCS不可」として扱うこと。
function M.build_snippet_body(text, opts)
  opts = opts or {}

  local sig = parse_signature(text)

  if not sig then
    return nil
  end

  local params = sig.params

  if opts.ufcs then
    if #params == 0 then
      return nil
    end

    local rest = {}
    for i = 2, #params do
      table.insert(rest, params[i])
    end
    params = rest
  end

  if #params == 0 then
    return sig.name .. "($0)"
  end

  local placeholders = {}

  for i, pname in ipairs(params) do
    table.insert(placeholders, string.format("${%d:%s}", i, pname))
  end

  return sig.name .. "(" .. table.concat(placeholders, ", ") .. ")$0"
end

return M