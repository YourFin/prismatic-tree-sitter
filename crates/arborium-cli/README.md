# arborium-cli

A terminal-friendly syntax highlighter powered by [Tree-sitter](https://tree-sitter.github.io/tree-sitter/).

## Features

- **ANSI terminal output** - Beautiful syntax highlighting in your terminal
- **HTML output** - Generate highlighted HTML for web pages
- **Auto-detection** - Automatically detects language from filenames or shebangs
- **Multiple themes** - Choose from 12 built-in themes
- **Flexible input** - Highlight files, stdin, or literal code strings

## Installation

```bash
cargo install arborium-cli
```

## Usage

```bash
# Highlight a file (auto-detects language from extension)
arborium file.rs

# Highlight from stdin
cat file.py | arborium -

# Highlight with explicit language
arborium --lang javascript "const x = 42;"

# Generate HTML output
arborium --html index.js

# Use a specific theme
arborium --theme dracula script.sh
```

## Options

- `-l, --lang <LANGUAGE>` - Specify the language explicitly (e.g., rust, python, javascript)
- `--html` - Output HTML instead of ANSI escape sequences
- `--theme <THEME>` - Choose a color theme for ANSI output (see below)
- `<input>` - Input source: filename, `-` for stdin, or literal code string

## Available Themes

Catppuccin variants:
- `mocha` / `catppuccin-mocha` (default)
- `latte` / `catppuccin-latte`
- `macchiato` / `catppuccin-macchiato`
- `frappe` / `catppuccin-frappe`

Other themes:
- `dracula`
- `tokyo-night`
- `nord`
- `one-dark`
- `github-dark`
- `github-light`
- `gruvbox-dark`
- `gruvbox-light`

## Examples

```bash
# Compare different themes
arborium --theme nord mycode.rs
arborium --theme dracula mycode.rs

# Highlight a script with shebang detection
arborium script.py  # Detects Python from .py extension
echo '#!/usr/bin/env python3\nprint("hello")' | arborium -  # Detects from shebang

# Generate HTML for a blog post
arborium --html snippet.rs > highlighted.html

# Pipe code through arborium
git diff | arborium --lang diff
```

## Language Auto-Detection

Arborium attempts to detect the language in this order:

1. **Explicit `--lang` flag** (highest priority)
2. **File extension** - If input is a file path
3. **Shebang line** - For stdin or literal strings (e.g., `#!/usr/bin/env python3`)

Supported languages include Rust, Python, JavaScript, TypeScript, C, C++, Go, Java, and many more.

## License

See the main [arborium](https://github.com/bearcove/arborium) repository for license information.
