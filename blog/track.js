/*
 * Phlix blog: GA4 tracking for App Store link clicks.
 *
 * Shared by every blog page (the index and all posts), which load it once
 * with a deferred script tag placed just before the closing body tag.
 *
 * Sends the same event as the inline handler on the homepage:
 *     gtag('event', 'app_store_click', { button_text, page_section })
 *
 *     button_text   the link text, trimmed, first 40 characters
 *     page_section  blog-nav     link inside <nav>
 *                   blog-cta     link inside an element with class "cta-box"
 *                   blog-footer  link inside <footer>
 *                   blog-inline  anywhere else
 *
 * The listener only observes the click. It never cancels, stops or delays
 * it, and it does nothing when gtag is missing (for example when a content
 * blocker removed it), so the link always opens normally.
 */
(function () {
    'use strict';

    var APP_STORE_LINK = 'a[href*="apps.apple.com"]';

    function pageSection(link) {
        if (link.closest('nav')) { return 'blog-nav'; }
        if (link.closest('.cta-box')) { return 'blog-cta'; }
        if (link.closest('footer')) { return 'blog-footer'; }
        return 'blog-inline';
    }

    function onClick(event) {
        try {
            var node = event.target;
            if (node && node.nodeType === 3) { node = node.parentNode; }
            if (!node || typeof node.closest !== 'function') { return; }

            var link = node.closest(APP_STORE_LINK);
            if (!link || typeof window.gtag !== 'function') { return; }

            window.gtag('event', 'app_store_click', {
                button_text: (link.textContent || '').trim().substring(0, 40),
                page_section: pageSection(link)
            });
        } catch (err) {
            // Analytics must never get in the way of the click: ignore.
        }
    }

    // One listener for the whole page. "passive" tells the browser this
    // listener cannot cancel the click; browsers too old to read the options
    // object treat it as "capture", which is the phase wanted here anyway.
    document.addEventListener('click', onClick, { capture: true, passive: true });
})();
