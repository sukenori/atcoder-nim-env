-- atcoder-nim.nim_lib_scan
--
-- 標準ライブラリ・nim-acl・cp-nim-libから、
-- 直前に ## docコメントを持つ public な proc / func / template / iterator
-- だけを収集する。
--
-- ## コメント本文は:
--   1. Telescope候補の説明文
--   2. Telescope検索対象
--   3. 右プレビューの説明文
-- に使う。
--
-- これにより、内部ヘルパーやコメントのない関数を候補から除外する。

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
    path = "/workspace/nim-acl/src",
    library = "atcoder",
  },
  {
    path = stdlib_root,
    library = "std",
  },
}

-- 公開シンボルだけを候補にする。
-- Nimの公開シンボルには名前末尾に * が付く。
-- rgの正規表現なので \s や \* はバックスラッシュでエスケープする。
local rg_pattern = [[^\s*(proc|func|template|iterator)\s+[A-Za-z_][A-Za-z0-9_]*\*]]

-- 各ライブラリの物理パスから、表示用の論理名を作る。
--
-- 例:
--   /.../lib/pure/strutils.nim       -> std/strutils
--   /.../lib/std/sequtils.nim        -> std/sequtils
--   /workspace/nim-acl/src/dsu.nim   -> atcoder/dsu
--   /workspace/nim-acl/src/atcoder/dsu.nim
--                                  -> atcoder/atcoder/dsu
--   /workspace/cp-nim-lib/Graph/BFS.nim
--                                  -> cp-nim-lib/Graph/BFS
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
--
-- telescope_cp.lua 側は M.scan() の結果に含まれる item.library を
-- そのまま使う設計だったが、item.file だけからでも同じ論理名を
-- 引けるように、後方互換として用意しておく。
-- どの search_dirs にも一致しない file が渡された場合は、
-- 元のフルパスをそのまま返す（表示が乱れても実害はない安全策）。
function M.module_label(file)
  for _, source in ipairs(M.search_dirs) do
    local root = source.path
    if file:sub(1, #root) == root then
      return make_library_name(root, source.library, file)
    end
  end

  return file
end

-- 直前に連続している ## コメントだけを拾う。
--
-- docコメントとproc宣言の間に空行・通常コメント・pragmaなどがある場合は、
-- その宣言をdocコメント付きとは見なさない。
local function collect_adjacent_doc_lines(context, decl_lnum)
  local doc_lines = {}
  local want_lnum = decl_lnum - 1

  for i = #context, 1, -1 do
    local line = context[i]

    if line.lnum ~= want_lnum then
      break
    end

    local trimmed = vim.trim(line.text)
    if not trimmed:match("^##") then
      break
    end

    -- ##、##-、## などを外して説明本文だけにする。
    local doc = trimmed:gsub("^##%-?%s*", "")
    table.insert(doc_lines, 1, doc)
    want_lnum = want_lnum - 1
  end

  return doc_lines
end

-- ripgrep --json のcontext行とmatch行を使う。
--
-- -B 12 により、宣言の直前12行までを取得する。
-- 長いdocコメントを採用することが増えたら、この値だけ増やせばよい。
function M.scan()
  local results = {}

  for _, source in ipairs(M.search_dirs) do
    if vim.fn.isdirectory(source.path) == 1 then
      local cmd = {
        "rg",
        "--json",
        "-B",
        "12",
        "--glob",
        "*.nim",
        "-e",
        rg_pattern,
        source.path,
      }

      local ok, raw_lines = pcall(vim.fn.systemlist, cmd)
      if ok then
        -- ファイルごとに「直前文脈」を保持する。
        local contexts = {}

        for _, raw in ipairs(raw_lines) do
          if raw ~= "" then
            local decoded_ok, event = pcall(vim.json.decode, raw)

            if decoded_ok and event and event.data then
              local data = event.data
              local file = data.path and data.path.text

              if event.type == "context" and file then
                local text = (data.lines and data.lines.text or ""):gsub("\n$", "")

                contexts[file] = contexts[file] or {}
                table.insert(contexts[file], {
                  lnum = data.line_number,
                  text = text,
                })
              end

              if event.type == "match" and file then
                local text = (data.lines and data.lines.text or ""):gsub("\n$", "")
                local context = contexts[file] or {}

                local doc_lines = collect_adjacent_doc_lines(context, data.line_number)

                -- ## docコメントを持つ関数だけ候補に採用する。
                if #doc_lines > 0 then
                  table.insert(results, {
                    file = file,
                    lnum = data.line_number,
                    text = vim.trim(text),
                    doc = table.concat(doc_lines, " "),
                    library = make_library_name(
                      source.path,
                      source.library,
                      file
                    ),
                  })
                end

                -- 次のmatchは別のcontextを使う。
                contexts[file] = nil
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
local function parse_signature(text)
  local kind, name, paramstr = text:match(
    "^(%a+)%s+([%w_]+)%*?%s*%((.*)%)%s*:?.*$"
  )

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
-- 例:
--   proc sum*(a: seq[int], initial: int = 0): int
--   -> sum(${1:a}, ${2:initial})$0
function M.build_snippet_body(text)
  local sig = parse_signature(text)
  if not sig then
    return nil
  end

  if #sig.params == 0 then
    return sig.name .. "($0)"
  end

  local placeholders = {}

  for i, pname in ipairs(sig.params) do
    table.insert(placeholders, string.format("${%d:%s}", i, pname))
  end

  return sig.name .. "(" .. table.concat(placeholders, ", ") .. ")$0"
end

return M
