# AdSense setup and testing

This repository now contains a lightweight consent banner and placeholders for Google AdSense ad slots. Implementation details:

- The ads consent script is scripts/ads-consent.js. It shows a small consent banner to visitors and injects the AdSense script only after the visitor accepts (recommended for GDPR compliance).
- Ad slot placeholders exist in index.html (below the hero, between features and premium, and footer). Product pages include a footer ad slot.
- The ads are lazy-loaded using IntersectionObserver to improve performance; the ad will only be pushed when the slot is near the viewport and consent has been given.

How to configure
1. Replace placeholder ad unit IDs in the HTML files (search for REPLACE_WITH_SLOT_*) with the ad unit IDs created in your AdSense account.
2. You have already provided the publisher script client id (ca-pub-5520788108565807) — the ads-consent.js injects that script when consent is accepted. If you need to change the publisher ID, update the URL inside scripts/ads-consent.js.

Testing locally
- Run a local server from the repository root (e.g. python3 -m http.server 8080) and open http://localhost:8080
- The consent banner will appear for new visitors. Click Accept to load ads. Note that AdSense may not show real ads on localhost — use AdSense test ad units or deploy to a staging URL that AdSense recognizes.

Notes & privacy
- For EU visitors and certain regions you should use a full CMP/TM approach (OneTrust / Cookiebot / Klaro) to meet TCF/consent requirements. This script is a lightweight approach to give visitors a choice.
- Keep a log of where ad units are placed and ensure ads do not compete with primary CTAs.
