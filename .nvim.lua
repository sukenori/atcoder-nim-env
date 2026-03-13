-- atcoder-nim-env/.nvim.lua プロジェクトローカル設定
-- VSCode とリモート接続時の素の Neovim の両方で make を呼ぶ

-- このファイル自身の場所をプロジェクトルートとして扱う
local env_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

-- 非同期で make を実行する
-- VSCode では統合ターミナルへ送信し、素の Neovim では :! で実行する
local function run_make_async(cmd)
  vim.cmd("write")

  if vim.g.vscode then
    local ok, vscode = pcall(require, "vscode")
    if not ok then
      print("vscode-neovim が読み込めません")
      return
    end
    vscode.action("workbench.action.terminal.sendSequence", {
      args = { { text = cmd .. "\n" } },
    })
    return
  end

  vim.cmd("!" .. cmd)
end

-- 同期で make を実行する（bundle の結果をすぐ使いたいとき用）
local function run_make_sync(cmd)
  vim.cmd("write")
  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

-- 基本操作: コンパイル / テスト+提出
vim.keymap.set("n", "<LocalLeader>c", function()
  local file = vim.fn.expand("%:p"):gsub("^" .. vim.pesc(env_dir) .. "/", "")
  local cmd = "make -C " .. vim.fn.shellescape(env_dir) .. " build FILE=" .. vim.fn.shellescape(file)
  run_make_async(cmd)
end, { silent = true, desc = "AtCoder: コンパイル" })

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
    vim.fn.setreg("+", table.concat(lines, "\n") .. "\n")
    print("バンドル結果をクリップボードにコピーしました")
  else
    print("エラー: " .. target .. " が見つかりません")
  end
end, { silent = true, desc = "AtCoder: バンドル＋コピー" })

-- nimlangserver が無い場合だけ LSP 設定をスキップする
if vim.fn.executable("nimlangserver") ~= 1 then
  return
end

-- nvim-cmp / lspconfig は dotfiles setup で導入済み前提にする
local lspconfig = require("lspconfig")
local cmp_nvim_lsp = require("cmp_nvim_lsp")

-- nvim-cmp の capability を LSP に渡す
local capabilities = cmp_nvim_lsp.default_capabilities(
  vim.lsp.protocol.make_client_capabilities()
)

local nim_config = {
  cmd = { "nimlangserver" },
  filetypes = { "nim" },
  root_dir = lspconfig.util.root_pattern("nim.cfg", "*.nimble", ".git"),
  capabilities = capabilities,
}

if vim.lsp.config then
  vim.lsp.config("nim_langserver", nim_config)
  vim.lsp.enable("nim_langserver")
else
  lspconfig.nim_langserver.setup(nim_config)
end