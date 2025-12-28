#!/usr/bin/env node
// Test if Svelte grammar plugin returns injections

import { chromium } from 'playwright';

const DEMO_URL = process.env.DEMO_URL || 'http://127.0.0.1:8001';

const svelteCode = `<script>
  export let name;
</script>

<main>
  <h1>Hello {name}!</h1>
</main>

<style>
  main {
    text-align: center;
  }
</style>`;

async function main() {
    console.log('Launching browser...');
    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();

    // Capture console logs
    page.on('console', msg => {
        console.log(`[browser ${msg.type()}] ${msg.text()}`);
    });

    // Navigate to demo
    await page.goto(`${DEMO_URL}/#svelte`);

    // Wait for highlight to be ready
    await page.waitForSelector('#output a-k, #output a-f, #output a-s', { timeout: 10000 }).catch(() => {
        console.warn('No highlighting spans found');
    });

    // Now test the parse function directly
    const result = await page.evaluate(async (code) => {
        // Wait for loadGrammar to be available
        if (!window.loadGrammar) {
            return { error: 'loadGrammar not found' };
        }

        try {
            const plugin = await window.loadGrammar('svelte');
            if (!plugin) {
                return { error: 'Failed to load svelte plugin' };
            }

            // The plugin provider should have parse capability
            // Let's check what methods are available
            const methods = Object.keys(plugin);

            // Try to get the raw parse result
            const session = plugin.createSession();
            plugin.setText(session, code);
            const parseResult = plugin.parse(session);
            plugin.freeSession(session);

            return {
                methods,
                parseResult,
                injectionCount: parseResult?.val?.injections?.length || parseResult?.injections?.length || 0
            };
        } catch (e) {
            return { error: e.message, stack: e.stack };
        }
    }, svelteCode);

    console.log('\n=== Test Result ===');
    console.log(JSON.stringify(result, null, 2));

    await browser.close();
}

main().catch(e => {
    console.error(e);
    process.exit(1);
});
