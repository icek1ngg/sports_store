// Artifact renderer: leaves the source HTML unchanged.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const path = require('path');
(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: true,
  });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
  await page.goto('file:///' + path.resolve('docs/ui_mocks/MH07_My_Orders.html').replaceAll('\\', '/'));
  await page.waitForFunction(() => getComputedStyle(document.querySelector('h2')).fontSize === '32px');
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: 'docs/ui_review_artifacts/mh07_html_390.png' });
  await page.screenshot({ path: 'docs/ui_review_artifacts/mh07_html_390_full.png', fullPage: true });
  console.log(JSON.stringify(await page.evaluate(() => ({ width: innerWidth, height: innerHeight, scrollWidth: document.documentElement.scrollWidth, fonts: document.fonts.status })), null, 2));
  await browser.close();
})();
