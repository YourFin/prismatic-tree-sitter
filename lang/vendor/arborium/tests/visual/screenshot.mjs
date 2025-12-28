#!/usr/bin/env node
// Visual regression testing for arborium demo
// Captures screenshots of each language's syntax highlighting

import { chromium } from 'playwright';
import { existsSync, mkdirSync, readFileSync, writeFileSync, unlinkSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';
import { execSync } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SNAPSHOTS_DIR = join(__dirname, 'snapshots');
const DIFF_DIR = join(__dirname, 'diffs');

// Config
const VIEWPORT = { width: 800, height: 600 };
const DEVICE_SCALE_FACTOR = 2; // HiDPI for crisp text rendering
const BASE_URL = process.env.DEMO_URL || 'http://127.0.0.1:8000';
const THRESHOLD = 0.1; // 0.1% pixel difference allowed
// SSIM threshold for skipping update in --update mode.
// Due to JXL lossy compression, even identical screenshots will have minor differences
// after a PNG->JXL->PNG roundtrip. DSSIM ~50 is typical for compression artifacts.
// 1/(1+50) ≈ 0.02, so we use 0.01 as threshold (anything above = similar enough)
const SSIM_THRESHOLD = 0.01;
// Note: Keep parallel browsers low to avoid Chromium WASM OOM crashes
const PARALLEL_BROWSERS = parseInt(process.env.PARALLEL_BROWSERS || '2', 10);

// CSS to isolate code output for screenshots
const FONT_CSS = `
    /* Hide everything except the code output */
    .page-header, .about-panel, .lang-info-panel, .editor-toolbar,
    .sample-bar, .status, .section-nav, .cards-container, footer,
    #source, .main-layout > aside {
        display: none !important;
    }
    /* Make code output fill viewport */
    body, .container, .main-layout, .editor-container, .panel,
    .editor-scroll, .editor-layers {
        margin: 0 !important;
        padding: 0 !important;
        width: 100% !important;
        height: 100% !important;
        max-width: none !important;
        display: block !important;
    }
    .output {
        position: fixed !important;
        inset: 0 !important;
        margin: 0 !important;
        padding: 12px !important;
        overflow: auto !important;
        font-family: 'Iosevka', 'JetBrains Mono', monospace !important;
        font-size: 11px !important;
        line-height: 1.4 !important;
    }
`;

// Convert PNG to JPEG-XL using ImageMagick
function pngToJxl(pngPath) {
    const jxlPath = pngPath.replace(/\.png$/, '.jxl');
    try {
        // Use ImageMagick to convert PNG to JXL
        // -quality 90 gives good compression while preserving detail
        execSync(`magick "${pngPath}" -quality 90 "${jxlPath}"`, { stdio: 'pipe' });
        // Remove the PNG after successful conversion
        unlinkSync(pngPath);
        return jxlPath;
    } catch (e) {
        console.warn(`  Warning: Failed to convert to JXL: ${e.message}`);
        return pngPath; // Keep PNG if conversion fails
    }
}

// Convert JPEG-XL to PNG for comparison
function jxlToPng(jxlPath) {
    const pngPath = jxlPath.replace(/\.jxl$/, '.png');
    try {
        execSync(`magick "${jxlPath}" "${pngPath}"`, { stdio: 'pipe' });
        return readFileSync(pngPath);
    } catch (e) {
        throw new Error(`Failed to decode JXL: ${e.message}`);
    } finally {
        // Clean up temp PNG
        if (existsSync(pngPath)) {
            unlinkSync(pngPath);
        }
    }
}

// Compute SSIM between two PNG files using ImageMagick
// Returns a value between 0 and 1 (1 = identical)
function computeSSIM(pngPath1, pngPath2) {
    try {
        // ImageMagick compare outputs: "distortion (ssim)" e.g. "0 (1)" or "5512.77 (0.0841195)"
        // For identical images it outputs "0 (0)" which is confusing - the parenthesized value
        // is actually 1-SSIM for some metrics. Let's use DSSIM which is clearer.
        const result = execSync(
            `magick compare -metric DSSIM "${pngPath1}" "${pngPath2}" null: 2>&1`,
            { stdio: 'pipe', encoding: 'utf-8' }
        );
        // DSSIM outputs just a number: 0 = identical, higher = more different
        // Parse just the first number (ignore anything in parentheses)
        const match = result.match(/^[\d.e+-]+/i);
        if (match) {
            const dssim = parseFloat(match[0]);
            // Convert DSSIM to similarity: 1/(1+dssim) gives us 1 for identical, approaching 0 for very different
            return isNaN(dssim) ? 0 : 1 / (1 + dssim);
        }
        return 0;
    } catch (e) {
        // compare returns exit code 1 when images differ, but still outputs the metric
        const output = e.stdout?.toString() || e.stderr?.toString() || '';
        const match = output.match(/^[\d.e+-]+/i);
        if (match) {
            const dssim = parseFloat(match[0]);
            return isNaN(dssim) ? 0 : 1 / (1 + dssim);
        }
        return 0;
    }
}

async function getLanguages(baseUrl) {
    // Fetch the registry to get all available languages
    const response = await fetch(`${baseUrl}/plugins.json`);
    const registry = await response.json();
    return registry.entries.map(e => e.language);
}

async function captureScreenshot(page, language) {
    // Navigate to language
    await page.goto(`${BASE_URL}/#${language}`);

    // Set dark theme (Catppuccin Mocha)
    await page.evaluate(() => {
        document.documentElement.setAttribute('data-theme', 'catppuccin-mocha');
    });

    // Inject consistent styling
    await page.addStyleTag({ content: FONT_CSS });

    // Wait for highlighting to complete (output should have highlighted spans)
    await page.waitForSelector('#output a-k, #output a-f, #output a-s', { timeout: 10000 }).catch(() => {
        console.warn(`  Warning: No highlighting spans found for ${language}`);
    });

    // Small delay for rendering
    await page.waitForTimeout(100);

    // Capture full page (code area is now fullscreen)
    return await page.screenshot({ type: 'png' });
}

function compareImages(img1Buffer, img2Buffer) {
    const img1 = PNG.sync.read(img1Buffer);
    const img2 = PNG.sync.read(img2Buffer);

    // If dimensions differ, images are definitely different
    if (img1.width !== img2.width || img1.height !== img2.height) {
        return { match: false, diffPercent: 100, diff: null };
    }

    const { width, height } = img1;
    const diff = new PNG({ width, height });

    const numDiffPixels = pixelmatch(
        img1.data,
        img2.data,
        diff.data,
        width,
        height,
        { threshold: 0.1 }
    );

    const totalPixels = width * height;
    const diffPercent = (numDiffPixels / totalPixels) * 100;

    return {
        match: diffPercent <= THRESHOLD,
        diffPercent,
        diff: PNG.sync.write(diff)
    };
}

// Process a single language test
async function processLanguage(context, language, updateMode, results, debugMode = false) {
    const page = await context.newPage();

    // Capture console logs if in debug mode
    const consoleLogs = [];
    if (debugMode) {
        page.on('console', msg => {
            consoleLogs.push({ type: msg.type(), text: msg.text() });
        });
    }

    // Check for JXL snapshot first, then PNG
    const jxlSnapshotPath = join(SNAPSHOTS_DIR, `${language}.jxl`);
    const pngSnapshotPath = join(SNAPSHOTS_DIR, `${language}.png`);
    const snapshotPath = existsSync(jxlSnapshotPath) ? jxlSnapshotPath : pngSnapshotPath;
    const diffPath = join(DIFF_DIR, `${language}.png`);

    try {
        const screenshot = await captureScreenshot(page, language);
        if (!screenshot) {
            return { lang: language, status: 'skip', message: 'no content' };
        }

        const hasExistingSnapshot = existsSync(jxlSnapshotPath) || existsSync(pngSnapshotPath);

        if (updateMode && hasExistingSnapshot) {
            // In update mode with existing snapshot: check SSIM first
            // Only write if images are different enough to matter
            const tempPngPath = join(SNAPSHOTS_DIR, `${language}-new.png`);
            writeFileSync(tempPngPath, screenshot);

            // Decode existing snapshot to PNG for comparison
            let existingPngPath;
            if (snapshotPath.endsWith('.jxl')) {
                existingPngPath = join(SNAPSHOTS_DIR, `${language}-existing.png`);
                execSync(`magick "${snapshotPath}" "${existingPngPath}"`, { stdio: 'pipe' });
            } else {
                existingPngPath = snapshotPath;
            }

            const ssim = computeSSIM(existingPngPath, tempPngPath);

            // Clean up temp existing PNG if we created it
            if (snapshotPath.endsWith('.jxl') && existsSync(existingPngPath)) {
                unlinkSync(existingPngPath);
            }

            if (ssim >= SSIM_THRESHOLD) {
                // Images are similar enough, skip update
                unlinkSync(tempPngPath);
                return { lang: language, status: 'unchanged', ssim, consoleLogs };
            } else {
                // Images are different, update the snapshot
                // Remove old snapshot
                if (existsSync(jxlSnapshotPath)) unlinkSync(jxlSnapshotPath);
                if (existsSync(pngSnapshotPath)) unlinkSync(pngSnapshotPath);
                // Rename temp to final and convert to JXL
                const finalPngPath = join(SNAPSHOTS_DIR, `${language}.png`);
                if (tempPngPath !== finalPngPath) {
                    writeFileSync(finalPngPath, readFileSync(tempPngPath));
                    unlinkSync(tempPngPath);
                }
                pngToJxl(finalPngPath);
                return { lang: language, status: 'updated', ssim, consoleLogs };
            }
        } else if (!hasExistingSnapshot) {
            // No existing snapshot, create new one
            const tempPngPath = join(SNAPSHOTS_DIR, `${language}.png`);
            writeFileSync(tempPngPath, screenshot);
            pngToJxl(tempPngPath);
            return { lang: language, status: 'new', consoleLogs };
        } else {
            // Load existing snapshot (decode JXL if needed)
            let existing;
            if (snapshotPath.endsWith('.jxl')) {
                existing = jxlToPng(snapshotPath);
            } else {
                existing = readFileSync(snapshotPath);
            }

            const { match, diffPercent, diff } = compareImages(existing, screenshot);

            if (match) {
                return { lang: language, status: 'pass', consoleLogs };
            } else {
                // Save diff image
                if (diff) {
                    writeFileSync(diffPath, diff);
                }
                // Save actual screenshot for comparison
                writeFileSync(join(DIFF_DIR, `${language}-actual.png`), screenshot);
                return { lang: language, status: 'fail', diffPercent, consoleLogs };
            }
        }
    } catch (e) {
        return { lang: language, status: 'error', message: e.message, consoleLogs };
    } finally {
        await page.close();
    }
}

async function main() {
    const args = process.argv.slice(2);
    const updateMode = args.includes('--update');
    const debugMode = args.includes('--debug');
    const specificLangs = args.filter(a => !a.startsWith('--'));

    // Ensure directories exist
    mkdirSync(SNAPSHOTS_DIR, { recursive: true });
    mkdirSync(DIFF_DIR, { recursive: true });

    // Check if ImageMagick is available
    try {
        execSync('magick --version', { stdio: 'pipe' });
    } catch {
        console.error('Error: ImageMagick is required for JPEG-XL support.');
        console.error('Install with: brew install imagemagick (macOS) or apt install imagemagick (Linux)');
        process.exit(1);
    }

    console.log('Launching browser...');
    const browser = await chromium.launch({ headless: true });

    // Get languages
    let languages;
    try {
        languages = await getLanguages(BASE_URL);
    } catch (e) {
        console.error(`Failed to fetch languages from ${BASE_URL}/plugins.json`);
        console.error('Make sure the demo server is running: cargo xtask serve');
        await browser.close();
        process.exit(1);
    }

    if (specificLangs.length > 0) {
        // Filter to only specified languages
        const validLangs = languages.filter(l => specificLangs.includes(l));
        const invalidLangs = specificLangs.filter(l => !languages.includes(l));

        if (invalidLangs.length > 0) {
            console.warn(`Warning: Unknown languages: ${invalidLangs.join(', ')}`);
        }

        if (validLangs.length === 0) {
            console.error('No valid languages specified.');
            console.error(`Available: ${languages.join(', ')}`);
            await browser.close();
            process.exit(1);
        }

        languages = validLangs;
    }

    console.log(`Testing ${languages.length} languages with ${PARALLEL_BROWSERS} parallel browsers...`);

    const results = { passed: [], failed: [], new: [], updated: [], unchanged: [], errors: [] };

    // Create browser contexts for parallel execution
    const contexts = await Promise.all(
        Array(PARALLEL_BROWSERS).fill(null).map(() => browser.newContext({
            viewport: VIEWPORT,
            deviceScaleFactor: DEVICE_SCALE_FACTOR
        }))
    );

    // Process languages in parallel batches
    let langIndex = 0;
    const totalLangs = languages.length;

    while (langIndex < totalLangs) {
        const batch = languages.slice(langIndex, langIndex + PARALLEL_BROWSERS);
        const batchPromises = batch.map((lang, i) =>
            processLanguage(contexts[i % contexts.length], lang, updateMode, results, debugMode)
        );

        const batchResults = await Promise.all(batchPromises);

        for (const result of batchResults) {
            const { lang, status, diffPercent, ssim, message, consoleLogs } = result;

            // Print console logs if in debug mode
            if (debugMode && consoleLogs && consoleLogs.length > 0) {
                console.log(`\n  Console logs for ${lang}:`);
                for (const log of consoleLogs) {
                    console.log(`    [${log.type}] ${log.text}`);
                }
            }

            switch (status) {
                case 'pass':
                    process.stdout.write(`  ${lang}... PASS\n`);
                    results.passed.push(lang);
                    break;
                case 'fail':
                    process.stdout.write(`  ${lang}... FAIL (${diffPercent.toFixed(2)}% diff)\n`);
                    results.failed.push({ lang, diffPercent });
                    break;
                case 'new':
                    process.stdout.write(`  ${lang}... NEW\n`);
                    results.new.push(lang);
                    break;
                case 'updated':
                    process.stdout.write(`  ${lang}... UPDATED (SSIM: ${ssim?.toFixed(6) || 'N/A'})\n`);
                    results.updated.push(lang);
                    break;
                case 'unchanged':
                    process.stdout.write(`  ${lang}... UNCHANGED (SSIM: ${ssim?.toFixed(6) || 'N/A'})\n`);
                    results.unchanged.push(lang);
                    break;
                case 'skip':
                    process.stdout.write(`  ${lang}... SKIP (${message})\n`);
                    break;
                case 'error':
                    process.stdout.write(`  ${lang}... ERROR: ${message}\n`);
                    results.errors.push({ lang, error: message });
                    break;
            }
        }

        langIndex += PARALLEL_BROWSERS;
    }

    // Cleanup
    await Promise.all(contexts.map(ctx => ctx.close()));
    await browser.close();

    // Summary
    console.log('\n--- Summary ---');
    console.log(`Passed:    ${results.passed.length}`);
    console.log(`Failed:    ${results.failed.length}`);
    console.log(`New:       ${results.new.length}`);
    console.log(`Updated:   ${results.updated.length}`);
    console.log(`Unchanged: ${results.unchanged.length}`);
    console.log(`Errors:    ${results.errors.length}`);

    if (results.failed.length > 0) {
        console.log('\nFailed languages:');
        for (const { lang, diffPercent } of results.failed) {
            console.log(`  - ${lang}: ${diffPercent.toFixed(2)}% difference`);
        }
        console.log('\nDiff images saved to: tests/visual/diffs/');
        console.log('Run with --update to accept current screenshots as new baseline.');
        process.exit(1);
    }

    if (results.errors.length > 0) {
        console.log('\nErrors:');
        for (const { lang, error } of results.errors) {
            console.log(`  - ${lang}: ${error}`);
        }
        process.exit(1);
    }

    if (results.new.length > 0) {
        console.log('\nNew snapshots created. Review and commit them.');
    }
}

main().catch(e => {
    console.error(e);
    process.exit(1);
});
