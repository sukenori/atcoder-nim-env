-- atcoder-nim/lsp.lua — プロジェクトローカルで Nim LSP (nimlangserver) の設定を管理する
local M = {}

-- project_root を呼び出し側（.nvim.lua）から受け取る
function M.setup(project_root)
  -- このプロジェクトで既に初期化済みなら二重起動しない
  if vim.g.atcoder_project_nim_lsp_initialized then
    return
  end
  vim.g.atcoder_project_nim_lsp_initialized = true

  -- 既存のハンドラ（コントローラー）（orig）を受け取り、それをラップした新しい関数を返す関数
  local function wrap_handler(orig)
    return function(err, result, ctx, config)
      -- イベントを送信してきた LSP クライアントの情報を取得（エラー防止のため、ctx と ctx.client_id の存在を確認）
      local client = ctx
        and ctx.client_id
        and vim.lsp.get_client_by_id(ctx.client_id)
      -- 以下の条件をすべて満たした場合、nimlangserver からの Info 通知とみなして、元のハンドラに渡さず終了する
      if client
        and client.name == "nim_langserver"                  -- 送信元が nim_langserver である
        and result                                           -- サーバーからの結果（メッセージ本体）が存在する
        and result.type == vim.lsp.protocol.MessageType.Info -- メッセージの種類が "Info" である
      then
        return
      end
      -- 上記の条件に当てはまらない（エラーや別のサーバーからの通知など）場合は、元のハンドラに引数を渡す
      if orig then
        orig(err, result, ctx, config)
      end
    end
  end

  -- Neovim の画面右下のポップアップ通知（showMessage）の処理を、ラップした関数で上書きする
  vim.lsp.handlers["window/showMessage"] =
    wrap_handler(vim.lsp.handlers["window/showMessage"])

  -- Neovim の内部ログへの記録（logMessage）も、同様にラップした関数で上書きする
  vim.lsp.handlers["window/logMessage"] =
    wrap_handler(vim.lsp.handlers["window/logMessage"])

  -- "nim_langserver" という名前で、LSPサーバーの起動方法や設定を Neovim に登録
  vim.lsp.config("nim_langserver", {
    cmd = { "nimlangserver" },
    -- これが無いと、.nim ファイルを開いても自動起動しない
    filetypes = { "nim" },
    -- nimlangserver に渡す設定
    settings = {
      nim = {
        autoCheckFile     = true,           -- 開いているファイルのエラーチェックを自動で行う
        autoCheckProject  = false,          -- プロジェクト全体のチェックは重いので無効にする
        checkOnSave       = false,          -- `nim check` コマンドによる保存時のチェックは無効にする
        useNimCheck       = false,          -- `nim check` ではなく、LSP 組み込みの機能(nimsuggest)を使う
        notificationVerbosity = "warning",  -- サーバー側でも、Info レベル以下の細かい通知を出さないようにする
      },
    },

    -- この LSP を「どのフォルダを基準に動かすか」決める関数
    root_dir = function(bufnr, on_dir)
      -- バッファのファイル名（フルパス）を取得
      local fname = vim.api.nvim_buf_get_name(bufnr)
      -- まだディスクに保存されていない空のバッファや、実在しないファイルの場合、クラッシュ防止で起動をキャンセルする
      if fname == "" or vim.fn.filereadable(fname) ~= 1 then
        return
      end
      -- さもなければプロジェクトルート（/atcoder-nim-env）で確定
      on_dir(project_root)
    end,
  })

  -- 上で登録した "nim_langserver" の設定を有効化し、Nim ファイルを開いたときに自動で LSP が立ち上がるようにする
  vim.lsp.enable("nim_langserver")

  -- .nvim.lua 読み込み時点で既に開かれている Nim バッファに対しても、LSP を確実に接続させる
  vim.schedule(function()
    pcall(vim.cmd.doautoall, "nvim.lsp.enable FileType")
  end)
end

return M