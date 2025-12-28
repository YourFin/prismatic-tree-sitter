//! Content-addressed storage for incremental builds
//!
//! Uses rapidhash for fast hashing and canopydb for persistent storage.
//! Tracks which files have been written and their content hashes to avoid
//! unnecessary disk writes.
//!
//! Also provides image caching to avoid re-processing images across restarts.

use crate::db::ProcessedImages;
use camino::Utf8Path;
use canopydb::Database;
use rapidhash::fast::RapidHasher;
use std::fs;
use std::hash::Hasher;
use std::path::Path;
use std::sync::OnceLock;

// Global image cache instance
static IMAGE_CACHE: OnceLock<Database> = OnceLock::new();

/// Content-addressed storage for build outputs
pub struct ContentStore {
    db: Database,
}

impl ContentStore {
    /// Open or create a content store at the given path
    pub fn open(path: &Utf8Path) -> color_eyre::Result<Self> {
        // canopydb stores data in a directory
        fs::create_dir_all(path)?;
        let db = Database::new(path.as_std_path())?;
        Ok(Self { db })
    }

    /// Compute the rapidhash of content
    fn hash(content: &[u8]) -> u64 {
        let mut hasher = RapidHasher::default();
        hasher.write(content);
        hasher.finish()
    }

    /// Write content to a file if it has changed since last build.
    /// Returns true if the file was written, false if skipped (unchanged).
    pub fn write_if_changed(&self, path: &Utf8Path, content: &[u8]) -> color_eyre::Result<bool> {
        let hash = Self::hash(content);
        let hash_bytes = hash.to_le_bytes();
        let path_key = path.as_str().as_bytes();

        // Check if we have a stored hash for this path
        let unchanged = {
            let rx = self.db.begin_read()?;
            if let Some(tree) = rx.get_tree(b"hashes")? {
                if let Some(stored) = tree.get(path_key)? {
                    stored.as_ref() == hash_bytes
                } else {
                    false
                }
            } else {
                false
            }
        };

        if unchanged {
            return Ok(false);
        }

        // Hash differs or not stored - write the file
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, content)?;

        // Update stored hash
        let tx = self.db.begin_write()?;
        let mut tree = tx.get_or_create_tree(b"hashes")?;
        tree.insert(path_key, &hash_bytes)?;
        drop(tree);
        tx.commit()?;

        Ok(true)
    }
}

// ============================================================================
// Image Cache (global, for processed images)
// ============================================================================

/// Initialize the global image cache
pub fn init_image_cache(cache_dir: &Path) -> color_eyre::Result<()> {
    // canopydb stores data in a directory, not a single file
    let db_path = cache_dir.join("images.canopy");

    // Ensure the database directory exists
    fs::create_dir_all(&db_path)?;

    let db = Database::new(&db_path)?;
    let _ = IMAGE_CACHE.set(db);
    tracing::info!("Image cache initialized at {:?}", db_path);
    Ok(())
}

/// Image processing pipeline version - bump this when encoding settings change
/// (widths, quality, formats, etc.) to invalidate the cache
pub const IMAGE_PIPELINE_VERSION: u64 = 1;

/// Hash of input image content (includes pipeline version)
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct InputHash(pub [u8; 32]);

/// Key for a specific image variant (format + size)
/// Used to compute deterministic cache-busted URLs without processing the image
#[derive(Hash)]
pub struct ImageVariantKey {
    /// Hash of input image content (includes pipeline version)
    pub input_hash: InputHash,
    /// Output format
    pub format: crate::image::OutputFormat,
    /// Output width in pixels
    pub width: u32,
}
