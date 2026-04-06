# Tree-sitter Parser Registry

A community-maintained mapping of tree-sitter parsers to their source
repositories. Any editor or tool that needs to find, download, or build
tree-sitter parsers can use this as a data source.

## Files

| File | Purpose | Audience |
|------|---------|----------|
| `parsers.toml` | Parser name → git repo URL | Everyone |
| `neovim-filetypes.toml` | Neovim filetype → parser name | Neovim tools |
| `neovim-ignore.toml` | Neovim filetypes to skip | Neovim tools |

### parsers.toml

The core registry. Each section is a parser:

```toml
[rust]
url = "https://github.com/tree-sitter/tree-sitter-rust"

[typescript]
url = "https://github.com/tree-sitter/tree-sitter-typescript"
location = "typescript"
```

- **url** — Git repository containing the grammar
- **location** — Subdirectory for mono-repos (omitted when the grammar is at the repo root)

### neovim-filetypes.toml

Maps Neovim filetype names to parser names where they differ:

```toml
[filetypes]
bash = ["sh", "zsh"]
latex = ["plaintex", "tex"]
```

If the Neovim filetype matches the parser name (e.g. `rust` → `rust`), no
entry is needed.

### neovim-ignore.toml

Filetypes that should never trigger parser installation — UI buffers, plugin
windows, and virtual filetypes that will never have parsers.

## Using This Registry

Fetch the raw files directly:

```
https://raw.githubusercontent.com/arborist-ts/registry/main/parsers.toml
```

The TOML is deliberately simple — every value is either a quoted string or an
array of quoted strings. A full TOML parser works, but basic line-by-line
string matching is enough.

**To find and build a parser:**

1. Look up the parser name in `parsers.toml` → get `url` and optional `location`
2. Clone the repo
3. If `location` is set, `cd` into that subdirectory
4. Build: `tree-sitter build`, `cc -shared`, or download a pre-built binary

## Contributing

### Adding a parser

Add a section to `parsers.toml` in alphabetical order:

```toml
[my_language]
url = "https://github.com/user/tree-sitter-my-language"
```

For mono-repos:

```toml
[my_language]
url = "https://github.com/user/tree-sitter-languages"
location = "my-language"
```

### Adding a Neovim filetype mapping

If a Neovim filetype doesn't match the parser name, add it to
`neovim-filetypes.toml`:

```toml
my_parser = ["nvim_filetype1", "nvim_filetype2"]
```

## Origin

The initial data was extracted from
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
(Apache-2.0), which was archived in April 2026. This registry is an
independent fork of that data — it is maintained separately and is not synced
from upstream.

The extracted data consists of factual mappings (parser names to repository
URLs and Neovim filetype associations) which are not copyrightable expression.
Attribution is provided here as a courtesy.

The `scripts/` directory contains the one-time import tool used to seed this
registry. It is not part of ongoing maintenance.

## License

[CC0 1.0](LICENSE) — public domain.
