// ==UserScript==
// @name         NPM Trusted Publisher Auto-fill for @arborium
// @namespace    http://tampermonkey.net/
// @version      2.0
// @description  Auto-fill trusted publisher settings for @arborium packages
// @author       You
// @match        https://www.npmjs.com/package/@arborium/*
// @grant        none
// ==/UserScript==

(function() {
    'use strict';

    // Configuration - edit these values
    const CONFIG = {
        repositoryOwner: 'bearcove',
        repositoryName: 'arborium',
        workflowFilename: 'ci.yml',
        environmentName: '' // leave empty
    };

    function setInputValue(input, value) {
        // React inputs need special handling
        const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
        nativeInputValueSetter.call(input, value);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
    }

    function clickIfExists(selector) {
        const el = document.querySelector(selector);
        if (el) {
            console.log(`[NPM Trusted Publisher] Clicking: ${selector}`);
            el.click();
            return true;
        }
        return false;
    }

    function fillFormIfReady() {
        const ownerInput = document.querySelector('#oidc_repositoryOwner');
        if (!ownerInput) return false;

        const repoInput = document.querySelector('#oidc_repositoryName');
        const workflowInput = document.querySelector('#oidc_workflowName');
        const envInput = document.querySelector('#oidc_githubEnvironmentName');

        if (ownerInput) setInputValue(ownerInput, CONFIG.repositoryOwner);
        if (repoInput) setInputValue(repoInput, CONFIG.repositoryName);
        if (workflowInput) setInputValue(workflowInput, CONFIG.workflowFilename);
        if (envInput) setInputValue(envInput, CONFIG.environmentName);

        console.log('[NPM Trusted Publisher] Form filled!');
        return true;
    }

    let formFilled = false;
    let navigated = false;

    function tick() {
        // Only run on visible/active tab
        if (document.hidden) return;

        // If not on /access page, navigate there (only once)
        if (!window.location.pathname.endsWith('/access')) {
            if (!navigated) {
                navigated = true;
                const currentPath = window.location.pathname;
                const accessPath = currentPath.replace(/\/?$/, '/access');
                console.log(`[NPM Trusted Publisher] Navigating to ${accessPath}`);
                window.location.href = accessPath;
            }
            return;
        }

        // Click "Use security key" button if present
        clickIfExists('button.e64d5a00');

        // Click "GitHub Actions" button to reveal the form
        clickIfExists('button[aria-label="Add Trusted Publisher connection for GitHub Actions"]');

        // Try to fill the form
        if (!formFilled && fillFormIfReady()) {
            formFilled = true;
        }

        // Click submit button (keep trying even after formFilled)
        if (formFilled) {
            const submitBtn = document.querySelector('button[aria-label="Set up new trusted publisher connection"]');
            if (submitBtn && !submitBtn.disabled) {
                console.log('[NPM Trusted Publisher] Clicking submit...');
                submitBtn.click();
            }
        }
    }

    console.log('[NPM Trusted Publisher] Script loaded, starting...');

    // Run tick every 500ms forever
    setInterval(tick, 500);

    // Also run immediately
    setTimeout(tick, 1000);
})();
