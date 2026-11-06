// MH09 audit reference only. Run from project root; source HTML stays untouched.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { createHash } = require('crypto');
const hash = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');

(async () => {
  const source = 'docs/ui_mocks/MH09_Manager_Order_Details.html';
  const output = 'docs/features/mh09/artifacts';
  const before = hash(source);
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
    page.on('requestfailed', r => failures.push({ url: r.url(), error: r.failure() }));
    page.on('response', r => {
      if (r.status() >= 400) failures.push({ url: r.url(), status: r.status() });
    });
    await page.goto(pathToFileURL(path.resolve(source)).href, { waitUntil: 'networkidle' });
    await page.waitForFunction(() =>
      getComputedStyle(document.querySelector('header > div')).height === '64px')
      .catch(async error => {
        console.error(JSON.stringify({ failures, header: await page.locator('header > div')
          .evaluate(el => ({ height: getComputedStyle(el).height, className: el.className })) }));
        throw error;
      });
    const fontLoads = await page.evaluate(async () => {
      const specs = [
        '400 14px Inter', '500 14px Inter', '600 14px Inter', '700 14px Inter',
        '600 28px "Barlow Condensed"', '700 28px "Barlow Condensed"',
        '800 32px "Barlow Condensed"', 'italic 700 28px "Barlow Condensed"',
        '400 20px "Material Symbols Outlined"',
      ];
      const result = [];
      for (const spec of specs) {
        const sample = spec.includes('Symbols') ? 'arrow_back check_circle' : 'ĐƠN HÀNG Nguyễn';
        const faces = await document.fonts.load(spec, sample);
        result.push({ spec, faces: faces.length, loaded: faces.every(f => f.status === 'loaded') });
      }
      await document.fonts.ready;
      await Promise.all([...document.images].map(img => img.decode().catch(() => {})));
      return result;
    });
    if (fontLoads.some(f => !f.faces || !f.loaded)) throw Error('Original fonts not loaded');
    const measured = await page.evaluate(() => {
      const rect = el => {
        const b = el.getBoundingClientRect(), s = getComputedStyle(el);
        return { text: el.textContent.trim().replace(/\s+/g, ' ').slice(0, 100),
          x: b.x, y: b.y, width: b.width, height: b.height,
          font: s.fontFamily, size: s.fontSize, lineHeight: s.lineHeight,
          weight: s.fontWeight, radius: s.borderRadius, padding: s.padding,
          gap: s.gap, color: s.color, background: s.backgroundColor };
      };
      const all = selector => [...document.querySelectorAll(selector)].map(rect);
      return {
        viewport: { width: innerWidth, height: innerHeight, dpr: devicePixelRatio },
        scrollWidth: document.documentElement.scrollWidth,
        scrollHeight: document.documentElement.scrollHeight,
        fontStatus: document.fonts.status,
        fontFaces: [...document.fonts].map(f => ({ family: f.family, weight: f.weight, status: f.status })),
        header: all('header, header > div'), title: all('h1'),
        meta: all('main > div > div:first-child, main > div > div:nth-child(2)'),
        sections: [...document.querySelectorAll('h2')].map(el => rect(el.closest('.bg-soft-cloud'))),
        headings: all('h2'), items: all('h3'), images: [...document.images].map(img =>
          ({ ...rect(img), complete: img.complete, naturalWidth: img.naturalWidth })),
        footer: all('main .fixed.bottom-0'), buttons: all('button, a'),
      };
    });
    const screenshots = [];
    for (const [name, fullPage] of [['html_390x844.png', false], ['html_390_full.png', true]]) {
      const file = path.join(output, name);
      await page.screenshot({ path: file, fullPage, animations: 'disabled' });
      screenshots.push({ path: `${output}/${name}`, sha256: hash(file) });
    }
    const manifest = { source, generatedAt: new Date().toISOString(),
      browser: await browser.version(), renderer: 'tool/ui_preview/render_mh09_reference.cjs',
      rendererSha256: hash(__filename), sourceSha256Before: before,
      sourceSha256After: hash(source), sourceModified: before !== hash(source),
      failures, fontLoads, screenshots, ...measured };
    fs.writeFileSync(path.join(output, 'html_render_manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
    console.log(JSON.stringify({ viewport: measured.viewport, scrollHeight: measured.scrollHeight,
      failures, fontsLoaded: fontLoads.length, sourceModified: manifest.sourceModified }));
    if (manifest.sourceModified || measured.images.some(img => !img.naturalWidth)) process.exitCode = 1;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
