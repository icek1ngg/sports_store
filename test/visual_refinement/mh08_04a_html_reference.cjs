// Reuses MH07's Chromium renderer approach; never modifies the reference HTML.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { createHash } = require('crypto');
const sha256 = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');

(async () => {
  const source = path.resolve('docs/ui_mocks/MH08_Manager_Order_List.html');
  const sourceHashBefore = sha256(source);
  const output = path.resolve('docs/features/mh08/artifacts/visual_04a');
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_PATH ||
      'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: true,
  });
  try {
    const page = await browser.newPage({
      viewport: { width: 390, height: 844 }, deviceScaleFactor: 1,
    });
    const failures = [];
    page.on('requestfailed', request => failures.push({
      url: request.url(), error: request.failure()?.errorText,
    }));
    await page.goto(pathToFileURL(source).href, { waitUntil: 'networkidle' });
    await page.waitForFunction(() =>
      getComputedStyle(document.querySelector('header > div')).height === '64px')
      .catch(async error => {
        console.error(JSON.stringify({ failures, header: await page.locator('header > div')
          .evaluate(el => ({ height: getComputedStyle(el).height,
            className: el.className })) }));
        throw error;
      });
    await page.evaluate(async () => {
      await Promise.all([
        document.fonts.load('700 28px "Barlow Condensed"', 'ĐƠN HÀNG'),
        document.fonts.load('400 20px "Material Symbols Outlined"', 'search'),
      ]);
      await document.fonts.ready;
    });
    await page.screenshot({ path: path.join(output, 'html_390x844.png') });
    await page.screenshot({
      path: path.join(output, 'html_390_full.png'), fullPage: true,
    });
    const measured = await page.evaluate(() => {
      const inspect = selector => [...document.querySelectorAll(selector)].map(el => {
        const box = el.getBoundingClientRect();
        const css = getComputedStyle(el);
        return {
          text: el.textContent.trim().replace(/\s+/g, ' ').slice(0, 100),
          x: box.x, y: box.y, width: box.width, height: box.height,
          font: css.fontFamily, size: css.fontSize, lineHeight: css.lineHeight,
          radius: css.borderRadius, padding: css.padding,
          color: css.color, background: css.backgroundColor,
        };
      });
      return {
        viewport: { width: innerWidth, height: innerHeight, dpr: devicePixelRatio },
        scrollWidth: document.documentElement.scrollWidth,
        scrollHeight: document.documentElement.scrollHeight,
        fonts: {
          status: document.fonts.status,
          inter: document.fonts.check('14px Inter'),
          barlow: document.fonts.check('700 28px "Barlow Condensed"', 'ĐƠN HÀNG'),
          symbols: document.fonts.check('400 20px "Material Symbols Outlined"', 'search'),
        },
        header: inspect('header > div'),
        title: inspect('h1'),
        search: inspect('input'),
        kpis: inspect('main .grid.grid-cols-3 > div'),
        cards: inspect('main .shadow-\\[0_4px_16px_rgba\\(17\\,17\\,17\\,0\\.06\\)\\]'),
        navigation: inspect('nav, main .fixed.bottom-0'),
      };
    });
    const manifest = {
      source: 'docs/ui_mocks/MH08_Manager_Order_List.html',
      generatedAt: new Date().toISOString(),
      browser: await browser.version(),
      renderer: 'test/visual_refinement/mh08_04a_html_reference.cjs',
      rendererSha256: sha256(__filename),
      sourceSha256Before: sourceHashBefore,
      sourceSha256After: sha256(source),
      sourceModified: sourceHashBefore !== sha256(source), failures, ...measured,
    };
    fs.writeFileSync(path.join(output, 'html_render_manifest.json'),
      JSON.stringify(manifest, null, 2) + '\n');
    console.log(JSON.stringify({
      viewport: manifest.viewport, scrollWidth: manifest.scrollWidth,
      fonts: manifest.fonts, failedRequests: failures.length,
      artifacts: 'docs/features/mh08/artifacts/visual_04a',
    }));
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
