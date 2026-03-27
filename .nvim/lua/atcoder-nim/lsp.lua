-- atcoder-nim/lsp.lua
-- Nim LSP 設定を project-local で管理する。

local M = {}

function M.setup(opts)
  opts = opts or {}
  local env_dir = opts.env_dir
  if type(env_dir) ~= "string" or env_dir == "" then
    return
  end

  -- Nim 向け line_rg 補完の絞り込み。
  vim.g.user_line_rg_file_glob = "*.nim"

  local function resolve_nim_root(bufnr)
    local uv = vim.uv or vim.loop
    local fname = vim.api.nvim_buf_get_name(bufnr)
    if fname == "" then
      return env_dir
    end

    local real = uv.fs_realpath(fname) or fname
    local start = vim.fs.dirname(real)
    local marker = vim.fs.find({ "nim.cfg", ".git" }, { path = start, upward = true })[1]
    if marker then
      return vim.fs.dirname(marker)
    end

    local dir = start
    while dir and dir ~= "" do
      if vim.fn.glob(dir .. "/*.nimble") ~= "" then
        return dir
      end

      local parent = vim.fs.dirname(dir)
      if not parent or parent == dir then
        break
      end
      dir = parent
    end

    return start
  end

  local function setup_project_nim_lsp()
    if not (vim.lsp and vim.lsp.config and vim.lsp.enable) then
      return
    end

    if vim.g.atcoder_project_nim_lsp_initialized then
      return
    end
    vim.g.atcoder_project_nim_lsp_initialized = true

    local server_name = "nim_langserver"
    if vim.lsp.config.nim_ls and not vim.lsp.config.nim_langserver then
      server_name = "nim_ls"
    end

    -- nimlangserver の Info 通知はノイズになりやすいため抑制する。
    if not vim.g.atcoder_project_nim_lsp_message_filter_installed then
      vim.g.atcoder_project_nim_lsp_message_filter_installed = true

      local default_show = vim.lsp.handlers["window/showMessage"]
      local default_log = vim.lsp.handlers["window/logMessage"]

      local function should_drop_nim_info(result, ctx)
        if not (result and ctx and ctx.client_id and vim.lsp.get_client_by_id) then
          return false
        end
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        if not client then
          return false
        end
        if client.name ~= "nim_langserver" and client.name ~= "nim_ls" then
          return false
        end
        return result.type == vim.lsp.protocol.MessageType.Info
      end

      vim.lsp.handlers["window/showMessage"] = function(err, result, ctx, config)
        if should_drop_nim_info(result, ctx) then
          return
        end
        if default_show then
          return default_show(err, result, ctx, config)
        end
      end

      vim.lsp.handlers["window/logMessage"] = function(err, result, ctx, config)
        if should_drop_nim_info(result, ctx) then
          return
        end
        if default_log then
          return default_log(err, result, ctx, config)
        end
      end
    end

    vim.lsp.config(server_name, {
      cmd = { "nimlangserver" },
      settings = {
        nim = {
          autoCheckFile = true,
          autoCheckProject = false,
          checkOnSave = false,
          useNimCheck = false,
          notificationVerbosity = "warning",
        },
      },
      root_dir = function(bufnr, on_dir)
        local fname = vim.api.nvim_buf_get_name(bufnr)
        -- 新規未保存ファイルは実体がないため、保存前に LSP を起動しない。
        if fname == "" or vim.fn.filereadable(fname) ~= 1 then
          if on_dir then
            on_dir(nil)
          else
            return nil
          end
          return
        end

        local root = resolve_nim_root(bufnr)
        if on_dir then
          on_dir(root)
        else
          return root
        end
      end,
    })

    vim.lsp.enable(server_name)

    -- 設定時点で開かれている Nim バッファにも接続を適用する。
    vim.schedule(function()
      pcall(vim.cmd.doautoall, "nvim.lsp.enable FileType")
    end)
  end

  setup_project_nim_lsp()
end

return M
