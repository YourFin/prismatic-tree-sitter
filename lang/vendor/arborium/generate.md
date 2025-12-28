# Generation Flow

This document describes the proper flow for `cargo xtask gen` to avoid the clusterfuck of running tree-sitter on broken grammars.

## Flow Diagram

```
1. Registry Loading (~100ms)
   ├── Scan crates/arborium-* (legacy structure)
   ├── Scan langs/group-*/*/def/ (new structure)  
   └── Build CrateRegistry with all language definitions

2. Temp Structure Preparation (~200ms)
   ├── For EVERY grammar with grammar.js:
   │   ├── Create temp directory with proper structure
   │   ├── Copy grammar/ directory contents
   │   ├── Copy/move common/ directories to correct locations
   │   ├── Set up cross-grammar dependencies via symlinks
   │   └── Store temp directory paths for validation & generation

3. Pre-Generation Validation (~100ms - CRITICAL)
   ├── For EVERY prepared temp directory:
   │   ├── Create wrapper with dummy tree-sitter globals
   │   ├── Run `node wrapper.js` to require grammar.js
   │   ├── If require() fails → STOP EVERYTHING, SHOW ERROR
   │   └── If require() succeeds → grammar is valid
   └── Only proceed if ALL grammars pass validation

4. Tree-sitter Generation (EXPENSIVE - CACHED)
   ├── For each validated temp directory in parallel:
   │   ├── Check cache by hash of input files
   │   ├── If cache hit → extract cached files
   │   ├── If cache miss → run tree-sitter generate in temp dir (SLOW)
   │   └── Save generated files to cache
   └── Create plans for file updates from generated sources

5. Crate Generation (FAST)
   ├── Generate Cargo.toml files using templates
   ├── Generate build.rs files using templates
   ├── Generate src/lib.rs files using templates
   └── Execute all file operations

6. Post-Generation Lint (VERIFICATION)
   ├── Check that all expected files were generated
   ├── Validate arborium.kdl syntax
   └── Check sample files exist and are reasonable
```

## Why This Order Matters

### 1. Registry Loading
- Fast operation (~100ms)
- Discovers all language definitions
- No external dependencies

### 2. Temp Structure Preparation
- **SHARED SETUP** - creates temp directories with proper structure ONCE
- Copies grammar files and handles common/ directory placement
- Sets up cross-grammar dependencies
- Used by BOTH validation and generation phases
- Eliminates logic duplication

### 3. Pre-Generation Validation
- **CRITICAL PHASE** - catches missing file dependencies BEFORE expensive operations
- Uses Node.js to validate `require()` statements in grammar.js files
- Uses prepared temp directories from step 2
- Should check ALL grammars, not just ones with cross-grammar dependencies
- If ANY grammar fails validation → STOP IMMEDIATELY, don't waste time on tree-sitter

### 4. Tree-sitter Generation  
- **MOST EXPENSIVE** - tree-sitter generate can take 5-20s per grammar
- **HEAVILY CACHED** - results cached by hash of input files
- Uses prepared temp directories from step 2 (NO duplication of setup)
- Runs in parallel for speed
- Only runs if pre-validation passed

### 5. Crate Generation
- Fast file template operations using leon templates
- Creates Rust crate structure
- Uses include_str! for templates

### 6. Post-Generation Lint
- Verification that everything worked
- Catches edge cases missed by earlier phases

## Current Problems

The current implementation duplicates logic between validation and generation:

1. **Directory setup logic is duplicated** - both validation and generation create temp directories
2. **Common directory handling is duplicated** - same logic in two places  
3. **Cross-grammar dependency setup is duplicated** - wasteful and error-prone

## Fix Required

The implementation should follow this exact function sequence:

```rust
pub fn plan_generate() -> Result<(), Report> {
    // 1. Registry loading
    let registry = load_registry()?;
    
    // 2. Prepare temp structures (SHARED by validation & generation) 
    let prepared_temps = prepare_temp_structures(&registry)?;
    
    // 3. Pre-validation using prepared structures
    validate_all_grammars(&prepared_temps)?;
    
    // 4. Tree-sitter generation using same prepared structures  
    let generation_results = generate_all_grammars(&prepared_temps)?;
    
    // 5. Crate generation using templates
    generate_all_crates(&registry, &generation_results)?;
    
    // 6. Post-generation lint
    lint_generated_crates(&registry)?;
    
    Ok(())
}
```

This eliminates ALL duplication and ensures validation uses the exact same setup as generation.