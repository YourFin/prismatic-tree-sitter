# miette-arborium

Syntax highlighting for [miette](https://crates.io/crates/miette) diagnostics using arborium.

## Features

- Automatic language detection from file extensions
- Tree-sitter based highlighting (same engine as the main arborium crate)
- All arborium themes available
- Zero configuration needed

## Quick Start

```rust
fn main() {
    // Install the highlighter globally (call once at startup)
    miette_arborium::install_global().ok();

    // Now all miette errors will have syntax highlighting!
}
```

## With Custom Theme

```rust
fn main() {
    let theme = arborium_theme::builtin::github_light().clone();
    miette_arborium::install_global_with_theme(theme).ok();
}
```

## Example Output

Error diagnostics will show syntax-highlighted code snippets:

```
  × cannot find derive macro `Facet` in this scope
   ╭─[src/lib.rs:3:10]
 1 │ use facet::Facet;
 2 │
 3 │ #[derive(Facet)]
   ·          ──┬──
   ·            ╰── cannot find derive macro `Facet` in this scope
 4 │ struct FooBar {
   ╰────
```
---

Part of the [arborium](https://github.com/bearcove/arborium) project. See [arborium.dev](https://arborium.dev) for more information.
