-- Inspired by https://github.com/Shatur/neovim-session-manager
local M = {}

local Path = require("plenary.path")
local scandir = require("plenary.scandir")
local sessions_dir = Path:new(vim.fn.stdpath("data"), "sessions")
local utils = require("utils.utils")

local function session_filename_to_dir(filename)
	-- Get session filename
	local dir = filename:sub(#tostring(sessions_dir) + 2)
	dir = dir:gsub("++", ":")
	dir = dir:gsub("__", Path.path.sep)
	return Path:new(dir)
end

local function get_last_session_filename()
	if not Path:new(sessions_dir):is_dir() then
		return nil
	end

	local most_recent_filename = nil
	local most_recent_timestamp = 0
	for _, session_filename in ipairs(scandir.scan_dir(tostring(sessions_dir))) do
		if session_filename_to_dir(session_filename):is_dir() then
			local timestamp = vim.fn.getftime(session_filename)
			if most_recent_timestamp < timestamp then
				most_recent_timestamp = timestamp
				most_recent_filename = session_filename
			end
		end
	end
	return most_recent_filename
end

local function dir_to_session_filename(dir)
	local filename = dir and dir.filename or vim.loop.cwd()
	filename = filename:gsub(":", "++")
	filename = filename:gsub(Path.path.sep, "__")
	return Path:new(sessions_dir):joinpath(filename)
end

function M:load_session(dir)
	local filename = dir_to_session_filename(dir).filename
	-- save all files
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_get_option_value("modified", { buf = buffer }) then
			vim.api.nvim_command("silent wall")
		end
	end

	vim.schedule(function()
		local has_buffer = false
		if Path:new(filename):exists() then
			vim.api.nvim_command("silent source " .. filename)
			for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
				if utils:startswith(vim.api.nvim_buf_get_name(buffer), vim.fn.getcwd()) then
					has_buffer = true
					break
				end
			end
		end

		-- open debug ui automatically
		local dap_ = require("dap")
		local debug_session = dap_.session()
		if debug_session and debug_session.stopped_thread_id then
			-- this session is for this dir
			if utils:startswith(debug_session.config.program, dir) then
				require("dapui").toggle({})
			end
		end
		if not has_buffer then
			vim.api.nvim_command("enew")
		end
	end)
end

function M:load_last_session()
	-- Don't load session if using neovim to open a single file
	if vim.fn.argc() ~= 0 then
		return
	end

	local last_session = get_last_session_filename()
	if last_session then
		self:load_session(session_filename_to_dir(last_session))
	end
end

function M:is_restorable(buffer)
	local buftype = vim.api.nvim_get_option_value("buftype", { buf = buffer })
	if #buftype == 0 then
		-- Normal buffer, check if it listed
		if
			not vim.api.nvim_get_option_value("buflisted", { buf = buffer })
			or not utils:startswith(vim.api.nvim_buf_get_name(buffer), vim.fn.getcwd())
		then
			return false
		end
	elseif buftype == "terminal" then
		-- we need to save terminal buffer to enable in-nvim session change
		return true
	end

	if vim.tbl_contains({ "lazy" }, vim.api.nvim_get_option_value("filetype", { buf = buffer })) then
		return false
	end

	if vim.tbl_contains({ "gitcommit" }, vim.api.nvim_get_option_value("filetype", { buf = buffer })) then
		return false
	end
	return true
end

function M:save_current_session()
	-- don't save session if not inside a session (mainly single file mode)
	if vim.fn.argc() ~= 0 then
		return
	end

	local dir = Path:new(tostring(sessions_dir))
	if not dir:is_dir() then
		dir:mkdir()
	end

	-- toggle dap
	local debug_session = require("dap").session()
	if debug_session and debug_session.stopped_thread_id then
		-- this session is for this dir
		if utils:startswith(debug_session.config.program, vim.loop.cwd()) then
			-- Not hard close, can reload
			require("dapui").close({})
		end
	end

	-- Remove all non-file and utility buffers because they cannot be saved, also need to remove the buffers not belong to cwd
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		if not M:is_restorable(buffer) then
			vim.api.nvim_buf_delete(buffer, { force = true })
		end
	end

	local filename = dir_to_session_filename().filename
	vim.api.nvim_command("mksession! " .. filename)
end

return M
