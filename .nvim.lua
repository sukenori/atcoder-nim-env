-- atcoder-nim-env/.nvim.lua プロジェクトローカル設定
-- 素の Neovim で make と Nim LSP を扱う

-- このファイル自身の場所をプロジェクトルートとして扱う
local env_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

-- 非同期で make を実行する
local function run_make_async(cmd)
  vim.cmd("write")

  local job = vim.fn.jobstart({ "bash", "-lc", cmd }, {
    cwd = env_dir,
    detach = true,
  })
  if job <= 0 then
    vim.notify("make の非同期実行に失敗しました", vim.log.levels.ERROR)
  end
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

-- compose.yaml の container_name に合わせて Nim LSP を Docker 内で起動する
if vim.fn.executable("docker") ~= 1 then
  vim.notify("docker コマンドが見つからないため Nim LSP を無効化します", vim.log.levels.WARN)
  return
end

local container_name = "atcoder-nim"
local running_containers = vim.fn.systemlist({ "docker", "ps", "--format", "{{.Names}}" })
if vim.v.shell_error ~= 0 or not vim.tbl_contains(running_containers, container_name) then
  vim.notify(container_name .. " が起動していないため Nim LSP を無効化します", vim.log.levels.WARN)
  return
end

local nim_cmd = {
  "docker",
  "exec",
  "-i",
  "-w",
  "/home/sukenori/atcoder-nim-env",
  container_name,
  "nimlangserver",
}

-- nvim-cmp / lspconfig は lazy.nvim 側で導入済み前提にする
local ok_lspconfig, lspconfig = pcall(require, "lspconfig")
local ok_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if not ok_lspconfig or not ok_cmp then
  vim.notify("lspconfig または cmp-nvim-lsp が読み込めません", vim.log.levels.WARN)
  return
end

-- nvim-cmp の capability を LSP に渡す
local capabilities = cmp_nvim_lsp.default_capabilities(
  vim.lsp.protocol.make_client_capabilities()
)

local nim_config = {
  cmd = nim_cmd,
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