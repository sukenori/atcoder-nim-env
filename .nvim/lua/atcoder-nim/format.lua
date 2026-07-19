-- atcoder-nim/format.lua — プロジェクトローカルで Nim ファイルの自動整形の設定を管理する

local M = {}

local function format_current_nim(bufnr, opts)
  opts = opts or {}

  -- 対象がNimファイルでなければ何もしない
  if vim.bo[bufnr].filetype ~= "nim" then return end
  
  -- この関数中で nph による整形中なら何もしない（無限ループ防止）
  if vim.b[bufnr].nim_formatting then return end

  -- バッファのファイル名（フルパス）を取得、未保存なら nil
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then return end

  -- フォーマット作業中のフラグを立てる
  vim.b[bufnr].nim_formatting = true
  -- フォーマット前の画面の見え方（カーソルの位置や、スクロールの具合）を一時的に記憶しておく
  local view = vim.fn.winsaveview()

  -- 未保存の変更があれば、先に静かに保存する
  if vim.bo[bufnr].modified and not opts.skip_presave_write then
    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.cmd, "silent! write")
    end)
  end

  -- nph で整形
  vim.fn.system({ "nph", file })
  -- 外部コマンド nph の終了ステータス（コード）を取得し、正常終了 0 以外の場合
  if vim.v.shell_error ~= 0 then
    vim.notify("Nim format failed: nph", vim.log.levels.WARN)
    -- 整形中フラグを解除
    vim.b[bufnr].nim_formatting = false
    return
  end

  -- フォーマッタが外部でファイルを書き換えたので、Neovim に読み直させる
  -- 裏側で指定したバッファ（bufnr）にフォーカスを移して処理を行う
  vim.api.nvim_buf_call(bufnr, function()
    -- ディスク上のファイルが外部（今回は nph）によって書き換えられていないか確認し、書き換えられていれば最新の状態をバッファに読み込み直す
    pcall(vim.cmd, "silent! checktime")
  end)
  -- 画面の表示状態（カーソルの位置、スクロールの具合など）を復元
  vim.fn.winrestview(view)
  -- 整形中フラグを解除
  vim.b[bufnr].nim_formatting = false
end

function M.setup()
  -- "AtcoderNimAutoFormat" という名前の自動コマンドのグループを作成する
  -- { clear = true } を指定すると、Neovimの再読み込みしても設定が重複して登録されない
  local group = vim.api.nvim_create_augroup("AtcoderNimAutoFormat", { clear = true })
  
  -- インサートモードを Esc で抜けて、ノーマルモードに戻ったときにフォーマット
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,           -- 上で作ったグループに所属させる
    pattern = "*.nim",       -- 拡張子が .nim のファイルにのみ適用
    callback = function(ev)
      --当該バッファ（ev.buf）に対して、フォーマット関数を実行
      format_current_nim(ev.buf)
    end,
  })
  
  -- `:w` などでファイルをディスクに書き込む「直前」にフォーマット
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    pattern = "*.nim",
    callback = function(ev)
      -- オプション { skip_presave_write = true } にて、今まさに保存しようとしているから、事前の保存処理をスキップ（設定しないと再帰的無限ループに陥る）
      format_current_nim(ev.buf, { skip_presave_write = true })
    end,
  })

  -- Neovim のコマンドラインで `:NimFormat` と打ち込むことで、いつでも手動でフォーマットを実行
  vim.api.nvim_create_user_command("NimFormat", function()
    -- 手動実行の場合はイベント変数（ev）がないため、vim.api.nvim_get_current_buf() で「現在アクティブになっているバッファ」の ID を取得して関数に渡す
    format_current_nim(vim.api.nvim_get_current_buf())
  end, { desc = "Format current Nim file using nph" })
end

return M