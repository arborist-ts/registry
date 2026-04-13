#!/usr/bin/env -S nvim -l
--- Sync editor-neutral parser metadata from nvim-treesitter `main`.
---
--- nvim-treesitter is archived (2026-04-03); main is its frozen final
--- snapshot. We capture facts about each grammar (url, location,
--- maintainers, dependencies, install hints, descriptive notes) into
--- editor-neutral TOML files. Editor-specific decisions (revision pins,
--- query compatibility) live downstream in consumers like arborist.nvim.
---
--- Captured (per parsers.lua entry):
---   url            install_info.url       — git repository
---   location       install_info.location  — subpath in monorepo
---   branch         install_info.branch    — non-default branch (rare)
---   generate       install_info.generate  — needs `tree-sitter generate`
---   maintainers    maintainers            — GitHub @-handles
---   requires       requires               — other parsers this depends on
---   readme_note    readme_note            — human-readable gotchas
---
--- Dropped (editor-specific or redundant):
---   revision       — nvim-specific compatibility pin (lives in arborist.nvim/registry/pins.toml)
---   tier           — nvim-treesitter quality opinion
---   readme_name    — UI concern, no concrete neutral consumer
---   filetype       — Neovim-specific (handled by neovim-filetypes.toml)
---
--- Usage: nvim -l scripts/sync.lua

local PARSERS_URL = "https://raw.githubusercontent.com/nvim-treesitter/nvim-treesitter/main/lua/nvim-treesitter/parsers.lua"
local FILETYPES_URL = "https://raw.githubusercontent.com/nvim-treesitter/nvim-treesitter/main/plugin/filetypes.lua"

--- @param url string
--- @return string?
local function fetch(url)
  local result = vim.system({ "curl", "-fsSL", url }, { text = true }):wait()
  if result.code ~= 0 then return nil end
  return result.stdout
end

--- Parse parsers.lua via sandboxed loadstring. The file is `return { ... }`
--- with no side effects — empty env is sufficient and prevents any
--- accidental global access on a malicious upstream.
--- @param text string
--- @return table<string, table>
local function parse_parsers(text)
  local fn, err = loadstring(text, "parsers.lua")
  if not fn then
    io.stderr:write("loadstring failed: " .. tostring(err) .. "\n")
    os.exit(1)
  end
  setfenv(fn, setmetatable({}, {
    __index = function() return nil end,
    __newindex = function() end,
  }))
  local ok, entries = pcall(fn)
  if not ok or type(entries) ~= "table" then
    io.stderr:write("evaluating parsers.lua failed: " .. tostring(entries) .. "\n")
    os.exit(1)
  end
  return entries
end

--- @param text string
--- @return table<string, string[]>
local function parse_filetypes(text)
  local result = {}
  for line in text:gmatch("[^\n]+") do
    local lang, fts = line:match("^%s+([%w_]+)%s*=%s*(%b{})")
    if lang and fts then
      local list = {}
      for ft in fts:gmatch("'([^']+)'") do
        list[#list + 1] = ft
      end
      if #list > 0 then result[lang] = list end
    end
  end
  return result
end

--- Read existing neovim-filetypes.toml so manual additions/edits survive
--- sync runs (e.g. arborist restored `latex = ["plaintex", "tex"]` after
--- nvim-treesitter main dropped the plaintex mapping).
--- @param path string
--- @return table<string, string[]>
local function read_existing_filetypes(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local result = {}
  for line in f:lines() do
    local lang, arr = line:match("^([%w_]+)%s*=%s*%[(.+)%]$")
    if lang and arr then
      local list = {}
      for ft in arr:gmatch('"([^"]+)"') do
        list[#list + 1] = ft
      end
      if #list > 0 then result[lang] = list end
    end
  end
  f:close()
  return result
end

--- Merge existing entries on top of upstream. Local additions persist;
--- a local entry whose filetype list is a SUPERSET of upstream's wins
--- (assume the maintainer added items deliberately). When the lists are
--- equal or local is a subset of upstream, take upstream.
--- @param upstream table<string, string[]>
--- @param existing table<string, string[]>
--- @return table<string, string[]>, integer preserved_count
local function merge_filetypes(upstream, existing)
  local function set_of(arr)
    local s = {}
    for _, v in ipairs(arr) do
      s[v] = true
    end
    return s
  end
  local result, preserved = {}, 0
  for lang, fts in pairs(upstream) do
    result[lang] = fts
  end
  for lang, fts in pairs(existing) do
    local up = upstream[lang]
    if not up then
      -- arborist-only mapping (no upstream entry). Keep.
      result[lang] = fts
      preserved = preserved + 1
    else
      local up_set = set_of(up)
      local missing = false
      for _, f in ipairs(fts) do
        if not up_set[f] then
          missing = true
          break
        end
      end
      if missing then
        -- existing has at least one filetype upstream doesn't — superset
        -- (or divergent); preserve.
        result[lang] = fts
        preserved = preserved + 1
      end
    end
  end
  return result, preserved
end

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

--- TOML escape: backslashes and double quotes.
--- @param s string
--- @return string
local function toml_escape(s) return (s:gsub("\\", "\\\\"):gsub('"', '\\"')) end

--- TOML quoted-array of strings: ["a", "b", "c"]
--- @param arr string[]
--- @return string
local function toml_array(arr)
  local out = {}
  for _, v in ipairs(arr) do out[#out + 1] = '"' .. toml_escape(v) .. '"' end
  return "[" .. table.concat(out, ", ") .. "]"
end

-- Fetch
io.write("Fetching parsers.lua... ")
local parsers_text = fetch(PARSERS_URL)
if not parsers_text then
  io.write("FAILED\n")
  os.exit(1)
end
io.write("OK\n")

io.write("Fetching filetypes.lua... ")
local filetypes_text = fetch(FILETYPES_URL)
if not filetypes_text then
  io.write("FAILED\n")
  os.exit(1)
end
io.write("OK\n")

-- Parse
local parsers = parse_parsers(parsers_text)
local upstream_filetypes = parse_filetypes(filetypes_text)
local existing_filetypes = read_existing_filetypes("neovim-filetypes.toml")

-- Merge: arborist additions / supersets persist across syncs.
local filetypes, preserved = merge_filetypes(upstream_filetypes, existing_filetypes)

-- Drop filetype entries for parsers that don't exist
for lang in pairs(filetypes) do
  if not parsers[lang] then
    io.write("Warning: filetype mapping for unknown parser '" .. lang .. "', dropping\n")
    filetypes[lang] = nil
  end
end

-- Sort
local sorted_parsers = {}
for lang in pairs(parsers) do
  sorted_parsers[#sorted_parsers + 1] = lang
end
table.sort(sorted_parsers)

local sorted_ft = {}
for lang in pairs(filetypes) do
  sorted_ft[#sorted_ft + 1] = lang
end
table.sort(sorted_ft)

-- Write parsers.toml
local lines = {
  "# Tree-sitter Parser Registry",
  "#",
  "# Editor-neutral metadata about tree-sitter grammars. Captures facts about",
  "# each parser repo for any tool to consume. Editor-specific decisions",
  "# (revision pins, query compatibility) live downstream.",
  "#",
  "# Fields:",
  "#   url           Git repository containing the grammar",
  "#   location      Subdirectory within the repo (mono-repos)",
  "#   branch        Non-default git branch hosting the grammar (rare)",
  "#   generate      Whether the parser needs `tree-sitter generate` before build",
  "#   maintainers   GitHub @-handles of active maintainers",
  "#   requires      Other parsers this grammar depends on (e.g. injections)",
  "#   readme_note   Human-readable note (gotchas, scope, dialect)",
  "#",
  string.format("# %s | %d parsers | synced from nvim-treesitter main", os.date("%Y-%m-%d"), #sorted_parsers),
  "",
}
for _, lang in ipairs(sorted_parsers) do
  local entry = parsers[lang]
  local ii = entry.install_info or {}
  if not ii.url then
    io.write("Warning: '" .. lang .. "' has no install_info.url, skipping\n")
  else
    lines[#lines + 1] = "[" .. lang .. "]"
    lines[#lines + 1] = 'url = "' .. toml_escape(ii.url:gsub("%.git$", "")) .. '"'
    if ii.location then lines[#lines + 1] = 'location = "' .. toml_escape(ii.location) .. '"' end
    if ii.branch then lines[#lines + 1] = 'branch = "' .. toml_escape(ii.branch) .. '"' end
    if ii.generate then lines[#lines + 1] = "generate = true" end
    if entry.maintainers and #entry.maintainers > 0 then
      lines[#lines + 1] = "maintainers = " .. toml_array(entry.maintainers)
    end
    if entry.requires and #entry.requires > 0 then
      lines[#lines + 1] = "requires = " .. toml_array(entry.requires)
    end
    if entry.readme_note and entry.readme_note ~= "" then
      lines[#lines + 1] = 'readme_note = "' .. toml_escape(entry.readme_note) .. '"'
    end
    lines[#lines + 1] = ""
  end
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
  '# Format: parser = ["filetype1", "filetype2"]',
  "#",
  string.format("# %s | %d mappings | synced from nvim-treesitter main", os.date("%Y-%m-%d"), #sorted_ft),
  "",
  "[filetypes]",
}
for _, lang in ipairs(sorted_ft) do
  local fts = filetypes[lang]
  table.sort(fts)
  local quoted = {}
  for _, ft in ipairs(fts) do
    quoted[#quoted + 1] = '"' .. ft .. '"'
  end
  lines[#lines + 1] = lang .. " = [" .. table.concat(quoted, ", ") .. "]"
end
lines[#lines + 1] = ""
atomic_write("neovim-filetypes.toml", table.concat(lines, "\n"))
io.write(string.format("Wrote %d filetype mappings to neovim-filetypes.toml (%d preserved from existing)\n", #sorted_ft, preserved))
