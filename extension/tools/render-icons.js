// Renders icons/icon.svg and icons/icon-connected.svg to the PNG sizes the
// manifest lists. Run with `npm run icons` after editing either SVG.
const fs = require('node:fs');
const path = require('node:path');
const { Resvg } = require('@resvg/resvg-js');

const dir = path.join(__dirname, '..', 'icons');
for (const name of ['icon', 'icon-connected']) {
  const svg = fs.readFileSync(path.join(dir, `${name}.svg`));
  for (const size of [16, 32, 48, 128]) {
    const png = new Resvg(svg, { fitTo: { mode: 'width', value: size } }).render().asPng();
    fs.writeFileSync(path.join(dir, `${name}-${size}.png`), png);
  }
}
console.log('icons rendered');
