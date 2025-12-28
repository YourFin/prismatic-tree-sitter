# Sample Sourcing TODO

Goal: add permissively licensed sample files to each grammar’s `info.toml` under `[[samples]]` with attribution (`path`, `description`, `link`, `license`).

State legend:
- made-up: placeholder/stub (avoid)
- llm-picked: real sample chosen by me
- amos-picked: sample explicitly specified by Amos

## Completed samples
- asm (llm-picked): NASM `test/struc.asm` (BSD-2-Clause) → `crates/arborium-asm/samples/struc.asm`
- bash (llm-picked): Bash3Boilerplate `main.sh` (MIT) → `crates/arborium-bash/samples/bash3boilerplate_main.sh`
- c (llm-picked): `queue_linked_list.c` (MIT) → `crates/arborium-c/samples/queue_linked_list.c`
- java (llm-picked): Spring Petclinic `Vet.java` (Apache-2.0) → `crates/arborium-java/samples/Vet.java`
- python (llm-picked): Rich `dynamic_progress.py` (MIT) → `crates/arborium-python/samples/dynamic_progress.py`
- typescript (llm-picked): `discriminatedUnionTypes4.ts` (Apache-2.0) → `crates/arborium-typescript/samples/discriminatedUnionTypes4.ts`
- yaml (llm-picked): Kubernetes Deployment (Apache-2.0) → `crates/arborium-yaml/samples/deployment.yaml`
- go (llm-picked): go/types `implements.go` (BSD-3) → `crates/arborium-go/samples/implements.go`
- rust (llm-picked): Tokio `chat.rs` (MIT/Apache-2.0) → `crates/arborium-rust/samples/chat.rs`
- sql (llm-picked): Postgres `join.sql` (PostgreSQL) → `crates/arborium-sql/samples/join.sql`
- csharp (llm-picked): ref readonly sample (MIT) → `crates/arborium-c-sharp/samples/*`
- clojure (llm-picked): Ring params middleware (MIT) → `crates/arborium-clojure/samples/params.clj`
- cpp (llm-picked): fmt chrono test (MIT) → `crates/arborium-cpp/samples/chrono-test.cc`
- css (llm-picked): modern-normalize (MIT) → `crates/arborium-css/samples/modern-normalize.css`
- dart (llm-picked): extension methods fluent API (BSD-3) → `crates/arborium-dart/samples/fluid_api.dart`
- dockerfile (llm-picked): VS Code devcontainer (MIT) → `crates/arborium-dockerfile/samples/devcontainer-node.Dockerfile`
- elixir (llm-picked): Phoenix controller (MIT) → `crates/arborium-elixir/samples/controller.ex`
- elm (llm-picked): `Http.elm` (BSD-3) → `crates/arborium-elm/samples/Http.elm`
- fsharp (llm-picked): MathService `Library.fs` (MIT) → `crates/arborium-fsharp/samples/Library.fs`
- gleam (llm-picked): echo-server router (Apache-2.0) → `crates/arborium-gleam/samples/router.gleam`
- glsl (llm-picked): Vulkan Phong fragment (MIT) → `crates/arborium-glsl/samples/phong.frag`
- hcl (llm-picked): Terraform VPC example (Apache-2.0) → `crates/arborium-hcl/samples/vpc-main.tf`
- nginx (llm-picked): H5BP nginx.conf (MIT) → `crates/arborium-nginx/samples/nginx.conf`
- devicetree (llm-picked): Zephyr board DTS (Apache-2.0) → `crates/arborium-devicetree/samples/decawave_dwm1001_dev.dts`
- starlark (llm-picked): Bazel http.bzl (Apache-2.0) → `crates/arborium-starlark/samples/http.bzl`
- wasm (llm-picked): WebAssembly br.wast (Apache-2.0) → `crates/arborium-wasm/samples/br.wast`
- x86asm (llm-picked): NASM elftest.asm (BSD-2-Clause) → `crates/arborium-x86asm/samples/elftest.asm`
- xml (llm-picked): Spring Petclinic pom.xml (Apache-2.0) → `crates/arborium-xml/samples/pom.xml`
- zig (llm-picked): Ziglings async5 (MIT) → `crates/arborium-zig/samples/async5.zig`
- lua (llm-picked): Lua UTF-8 tests (MIT) → `crates/arborium-lua/samples/utf8.lua`
- nix (amos-picked): crane `buildDepsOnly.nix` (Apache-2.0) → `crates/arborium-nix/samples/buildDepsOnly.nix`
- markdown (llm-picked): rust-lang/rust README (Apache-2.0) → `crates/arborium-markdown/samples/rust-readme.md`
- zsh (llm-picked): oh-my-zsh git plugin (MIT) → `crates/arborium-zsh/samples/git.plugin.zsh`
- php (llm-picked): laravel `routes/web.php` (MIT) → `crates/arborium-php/samples/web.php`

## Still TODO
- Remaining languages without `[[samples]]` populated. If you want specific sources, call them out (they’ll be marked amos-picked). Otherwise I’ll choose permissive real samples (llm-picked).
- Powershell needs a good permissive script (previous GitHub repo 404).

## Guidance for adding more
1. Pick a permissive (MIT/Apache/BSD/CC0) real file per language (avoid “hello world”).  
2. Vendor it under `crates/arborium-<lang>/samples/` and add a `[[samples]]` entry with path, description, link, license.  
3. Include upstream license text if required.
