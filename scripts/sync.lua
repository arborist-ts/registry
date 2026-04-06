#!/usr/bin/env -S nvim -l
--- One-time import tool: seeds registry files from nvim-treesitter data.
--- Used to create the initial parsers.toml and neovim-filetypes.toml.
--- NOT part of ongoing maintenance — the registry is now maintained independently.
---
--- Produces:
---   parsers.toml            Universal parser registry
---   neovim-filetypes.toml   Neovim filetype → parser mappings
---
--- Usage: nvim -l scripts/sync.lua

local PARSERS_URL = "https://raw.githubusercontent.com/nvim-treesitter/nvim-treesitter/main/lua/nvim-treesitter/parsers.lua"
local FILETYPES_URL = "https://raw.githubusercontent.com/nvim-treesitter/nvim-treesitter/main/plugin/filetypes.lua"

--- Fetch a URL to a string. Returns nil on failure.
--- @param url string
--- @return string?
local function fetch(url)
  local result = vim.system({ "curl", "-fsSL", url }, { text = true }):wait()
  if result.code ~= 0 then return nil end
  return result.stdout
end

--- @param text string
--- @return table<string, {url: string, location?: string}>
local function parse_parsers(text)
  local result = {}
  local lang, in_install, url, location
  for line in text:gmatch("[^\n]+") do
    local l = line:match("^  ([%w_]+)%s*=%s*{")
    if l then
      if lang and url then
        result[lang] = { url = url:gsub("%.git$", ""), location = location }
      end
      lang, url, location, in_install = l, nil, nil, false
    end
    if line:match("install_info") then in_install = true end
    if in_install then
      local u = line:match("url%s*=%s*'([^']+)'")
      if u then url = u end
      local loc = line:match("location%s*=%s*'([^']+)'")
      if loc then location = loc end
    end
    if in_install and line:match("^    },") then in_install = false end
  end
  if lang and url then
    result[lang] = { url = url:gsub("%.git$", ""), location = location }
  end
  return result
end

--- @param text string
--- @return table<string, string[]>
local function parse_filetypes(text)
  local result = {}
  for line in text:gmatch("[^\n]+") do
    local lang, fts = line:match("^%s+([%w_]+)%s*=%s*(%b{})")
    if lang and fts then
      local list = {}
      for ft in fts:gmatch("'([^']+)'") do list[#list + 1] = ft end
      if #list > 0 then result[lang] = list end
    end
  end
  return result
end

--- Write a file atomically (write to .tmp, rename over target).
--- @param path string
--- @param content string
local function atomic_write(path, content)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    io.stderr:write("Cannot write " .. tmp .. "\n")
    os.exit(1)
  end
  f:write(content)
  f:close()
  os.rename(tmp, path)
end

-- Fetch
io.write("Fetching parsers.lua... ")
local parsers_text = fetch(PARSERS_URL)
if not parsers_text then io.write("FAILED\n"); os.exit(1) end
io.write("OK\n")

io.write("Fetching filetypes.lua... ")
local filetypes_text = fetch(FILETYPES_URL)
if not filetypes_text then io.write("FAILED\n"); os.exit(1) end
io.write("OK\n")

-- Parse
local parsers = parse_parsers(parsers_text)
local filetypes = parse_filetypes(filetypes_text)

-- Validate: drop filetype entries for parsers that don't exist
for lang in pairs(filetypes) do
  if not parsers[lang] then
    io.write("Warning: filetype mapping for unknown parser '" .. lang .. "', dropping\n")
    filetypes[lang] = nil
  end
end

-- Sort
local sorted_parsers = {}
for lang in pairs(parsers) do sorted_parsers[#sorted_parsers + 1] = lang end
table.sort(sorted_parsers)

local sorted_ft = {}
for lang in pairs(filetypes) do sorted_ft[#sorted_ft + 1] = lang end
table.sort(sorted_ft)

-- Write parsers.toml
local lines = {
  "# Tree-sitter Parser Registry",
  "#",
  "# Maps parser names to their source repositories.",
  "# Editor-agnostic — any tool that builds tree-sitter parsers can use this.",
  "#",
  "# Fields:",
  "#   url       Git repository containing the parser grammar",
  "#   location  Subdirectory within the repo (for mono-repos only)",
  "#",
  string.format("# %s | %d parsers | synced from nvim-treesitter", os.date("%Y-%m-%d"), #sorted_parsers),
  "",
}
for _, lang in ipairs(sorted_parsers) do
  local info = parsers[lang]
  lines[#lines + 1] = "[" .. lang .. "]"
  lines[#lines + 1] = 'url = "' .. info.url .. '"'
  if info.location then lines[#lines + 1] = 'location = "' .. info.location .. '"' end
  lines[#lines + 1] = ""
end
atomic_write("parsers.toml", table.concat(lines, "\n"))
io.write("Wrote " .. #sorted_parsers .. " parsers to parsers.toml\n")

-- Write neovim-filetypes.toml
lines = {
  "# Neovim Filetype Mappings",
  "#",
  "# Maps Neovim filetype names to tree-sitter parser names,",
  "# for cases where they differ (e.g. sh → bash, tex → latex).",
  "#",
  "# Format: parser = [\"filetype1\", \"filetype2\"]",
  "#",
  string.format("# %s | %d mappings | synced from nvim-treesitter", os.date("%Y-%m-%d"), #sorted_ft),
  "",
  "[filetypes]",
}
for _, lang in ipairs(sorted_ft) do
  local fts = filetypes[lang]
  table.sort(fts)
  local quoted = {}
  for _, ft in ipairs(fts) do quoted[#quoted + 1] = '"' .. ft .. '"' end
  lines[#lines + 1] = lang .. " = [" .. table.concat(quoted, ", ") .. "]"
end
lines[#lines + 1] = ""
atomic_write("neovim-filetypes.toml", table.concat(lines, "\n"))
io.write("Wrote " .. #sorted_ft .. " filetype mappings to neovim-filetypes.toml\n")
