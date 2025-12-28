//! # arborium docs.rs demo
//!
//! This crate demonstrates [arborium](https://github.com/bearcove/arborium)
//! syntax highlighting on docs.rs. Rust code is already highlighted by rustdoc,
//! but other languages are left plain. arborium fixes that!
//!
//! ## TOML
//!
//! Configuration files are everywhere in the Rust ecosystem:
//!
//! ```toml
//! [package]
//! name = "my-awesome-crate"
//! version = "1.0.0"
//! edition = "2021"
//!
//! [dependencies]
//! serde = { version = "1.0", features = ["derive"] }
//! tokio = { version = "1", features = ["full"] }
//!
//! [dev-dependencies]
//! criterion = "0.5"
//!
//! [features]
//! default = ["std"]
//! std = []
//! async = ["tokio"]
//! ```
//!
//! ## Shell
//!
//! Installation and usage instructions often include shell commands:
//!
//! ```bash
//! # Install the crate
//! cargo install my-awesome-crate
//!
//! # Run with arguments
//! my-awesome-crate --config config.toml --verbose
//!
//! # Set environment variables
//! export RUST_LOG=debug
//! cargo run -- serve --port 8080
//! ```
//!
//! ## JSON
//!
//! API responses, configuration, and data interchange:
//!
//! ```json
//! {
//!   "name": "arborium",
//!   "version": "1.0.0",
//!   "features": ["syntax-highlighting", "tree-sitter", "wasm"],
//!   "languages": 69,
//!   "config": {
//!     "theme": "tokyo-night",
//!     "maxDepth": 3
//!   }
//! }
//! ```
//!
//! ## YAML
//!
//! CI/CD pipelines and Kubernetes configs:
//!
//! ```yaml
//! name: CI
//! on: [push, pull_request]
//!
//! jobs:
//!   test:
//!     runs-on: ubuntu-latest
//!     steps:
//!       - uses: actions/checkout@v4
//!       - name: Install Rust
//!         uses: dtolnay/rust-toolchain@stable
//!       - name: Run tests
//!         run: cargo test --all-features
//! ```
//!
//! ## SQL
//!
//! Database queries and migrations:
//!
//! ```sql
//! -- Create a users table
//! CREATE TABLE users (
//!     id SERIAL PRIMARY KEY,
//!     username VARCHAR(255) NOT NULL UNIQUE,
//!     email VARCHAR(255) NOT NULL,
//!     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
//! );
//!
//! -- Query with joins
//! SELECT u.username, COUNT(p.id) as post_count
//! FROM users u
//! LEFT JOIN posts p ON p.author_id = u.id
//! WHERE u.created_at > '2024-01-01'
//! GROUP BY u.id
//! ORDER BY post_count DESC
//! LIMIT 10;
//! ```
//!
//! ## JavaScript
//!
//! Browser code and Node.js examples:
//!
//! ```javascript
//! import { loadGrammar, highlight } from '@arborium/arborium';
//!
//! async function highlightCode(language, source) {
//!   const grammar = await loadGrammar(language);
//!   const html = grammar.highlight(source);
//!   document.getElementById('output').innerHTML = html;
//! }
//!
//! // Auto-highlight all code blocks
//! document.querySelectorAll('pre code').forEach(block => {
//!   const lang = block.className.match(/language-(\w+)/)?.[1];
//!   if (lang) highlightCode(lang, block.textContent);
//! });
//! ```
//!
//! ## TypeScript
//!
//! Type-safe JavaScript:
//!
//! ```typescript
//! interface HighlightConfig {
//!   theme: string;
//!   selector: string;
//!   maxDepth?: number;
//! }
//!
//! async function highlight(
//!   language: string,
//!   source: string,
//!   config?: HighlightConfig
//! ): Promise<string> {
//!   const grammar = await loadGrammar(language);
//!   return grammar.highlight(source);
//! }
//!
//! const config: HighlightConfig = {
//!   theme: 'mocha',
//!   selector: 'pre > code',
//! };
//! ```
//!
//! ## Python
//!
//! Scripts and tooling:
//!
//! ```python
//! import subprocess
//! from pathlib import Path
//!
//! def build_and_test(project_dir: Path) -> bool:
//!     """Build the project and run tests."""
//!     result = subprocess.run(
//!         ["cargo", "test", "--all-features"],
//!         cwd=project_dir,
//!         capture_output=True,
//!         text=True,
//!     )
//!     if result.returncode != 0:
//!         print(f"Tests failed:\n{result.stderr}")
//!         return False
//!     return True
//!
//! if __name__ == "__main__":
//!     success = build_and_test(Path.cwd())
//!     exit(0 if success else 1)
//! ```
//!
//! ## Dockerfile
//!
//! Container builds:
//!
//! ```dockerfile
//! FROM rust:1.75 as builder
//! WORKDIR /app
//! COPY Cargo.toml Cargo.lock ./
//! COPY src ./src
//! RUN cargo build --release
//!
//! FROM debian:bookworm-slim
//! RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
//! COPY --from=builder /app/target/release/myapp /usr/local/bin/
//! ENTRYPOINT ["myapp"]
//! ```
//!
//! ## Nix
//!
//! Reproducible builds:
//!
//! ```nix
//! { pkgs ? import <nixpkgs> {} }:
//!
//! pkgs.rustPlatform.buildRustPackage rec {
//!   pname = "arborium";
//!   version = "1.0.0";
//!
//!   src = ./.;
//!
//!   cargoLock = {
//!     lockFile = ./Cargo.lock;
//!   };
//!
//!   nativeBuildInputs = [ pkgs.pkg-config ];
//!   buildInputs = [ pkgs.openssl ];
//! }
//! ```
//!
//! ## GraphQL
//!
//! API schemas:
//!
//! ```graphql
//! type Query {
//!   user(id: ID!): User
//!   posts(limit: Int = 10, offset: Int = 0): [Post!]!
//! }
//!
//! type User {
//!   id: ID!
//!   username: String!
//!   email: String!
//!   posts: [Post!]!
//! }
//!
//! type Post {
//!   id: ID!
//!   title: String!
//!   content: String!
//!   author: User!
//!   createdAt: DateTime!
//! }
//!
//! mutation CreatePost($input: CreatePostInput!) {
//!   createPost(input: $input) {
//!     id
//!     title
//!   }
//! }
//! ```
//!
//! ## CSS
//!
//! Styling:
//!
//! ```css
//! :root {
//!   --primary-color: #50C878;
//!   --background: #1a1b26;
//!   --foreground: #c0caf5;
//! }
//!
//! .code-block {
//!   background: var(--background);
//!   color: var(--foreground);
//!   padding: 1rem;
//!   border-radius: 8px;
//!   font-family: 'Iosevka', monospace;
//!   overflow-x: auto;
//! }
//!
//! .code-block a-k { color: #bb9af7; }  /* keywords */
//! .code-block a-s { color: #9ece6a; }  /* strings */
//! .code-block a-n { color: #ff9e64; }  /* numbers */
//! ```
//!
//! ## Rust (for comparison)
//!
//! Rust code is already highlighted by rustdoc - arborium skips it:
//!
//! ```rust
//! use std::collections::HashMap;
//!
//! pub fn highlight(language: &str, source: &str) -> String {
//!     let mut cache: HashMap<String, Grammar> = HashMap::new();
//!
//!     let grammar = cache
//!         .entry(language.to_string())
//!         .or_insert_with(|| load_grammar(language));
//!
//!     grammar.highlight(source)
//! }
//! ```
//!
//! ---
//!
//! This demo is powered by [arborium](https://github.com/bearcove/arborium).
//! See the [integration guide](https://arborium.bearcove.eu/) for setup instructions.

// Empty crate - this is just a docs demo
