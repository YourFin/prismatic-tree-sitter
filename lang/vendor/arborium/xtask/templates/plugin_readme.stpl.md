# @arborium/<%= grammar_id %>

[![Part of Arborium](https://img.shields.io/badge/🌳_Arborium-grammar_collection-228B22)](https://github.com/bearcove/arborium)
[![npm](https://img.shields.io/npm/v/@arborium/<%= grammar_id %>)](https://www.npmjs.com/package/@arborium/<%= grammar_id %>)
[![license](https://img.shields.io/npm/l/@arborium/<%= grammar_id %>)](https://github.com/bearcove/arborium)

Syntax highlighting for [<%= grammar_name %>](<%= language_link %>), powered by WebAssembly and [tree-sitter](https://tree-sitter.github.io/).
<% if !description.is_empty() { %>
> <%- description %>
<% } %>
<% if !inventor.is_empty() || year > 0 { %>
| | |
|---|---|<% if !inventor.is_empty() { %>
| **Inventor** | <%= inventor %> |<% } %><% if year > 0 { %>
| **Year** | <%= year %> |<% } %>
<% } %>
## Installation

```bash
npm install @arborium/<%= grammar_id %>
```

## Usage

```javascript
import { createHighlighter } from '@arborium/arborium';
import * as grammar from '@arborium/<%= grammar_id %>';

const highlighter = await createHighlighter();
await highlighter.loadGrammar(grammar);

const html = highlighter.highlight(code, '<%= grammar_id %>');
```

## What's included

This package contains:

- `grammar.js` - ES module that loads the WebAssembly grammar
- `grammar.d.ts` - TypeScript type definitions
- `grammar_bg.wasm` - The tree-sitter grammar compiled to WebAssembly

## About Arborium

This package is part of [**Arborium**](https://github.com/bearcove/arborium), a collection of tree-sitter grammars for syntax highlighting, maintained by [Amos Wenger](https://fasterthanli.me).

Arborium provides:
- **98+ language grammars** compiled to WebAssembly
- **Browser and Node.js support** via ES modules
- **TypeScript definitions** for all packages
- **Consistent API** across all grammars

## Related packages

- [`@arborium/arborium`](https://www.npmjs.com/package/@arborium/arborium) - Core highlighter library
- [All @arborium packages](https://www.npmjs.com/org/arborium)

## License

MIT OR Apache-2.0

## Links

- [GitHub](https://github.com/bearcove/arborium)
- [Issues](https://github.com/bearcove/arborium/issues)
