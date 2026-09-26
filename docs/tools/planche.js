// Contrôle des schémas animés : fige un SVG à plusieurs instants de son
// cycle et les empile sur une seule page, que Chrome capture. On voit
// d'un coup d'œil un texte qui déborde, une flèche qui tombe à côté de
// sa carte ou une bille qui s'arrête au mauvais endroit.
//
//   node docs/tools/planche.js docs/schemas/relais.svg [instants...]
//
// Les instants sont en secondes ; par défaut, huit instants répartis sur
// le cycle le plus long du fichier. L'image sort dans docs/tools/controle/,
// que git ignore.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const [, , fichier, ...args] = process.argv;
const source = fs.readFileSync(fichier, 'utf8');
const [, largeur, hauteur] = source.match(/viewBox="0 0 (\d+) (\d+)"/).map(Number);
const cycle = Math.max(...[...source.matchAll(/dur="([\d.]+)s"/g)].map((m) => +m[1]));
const instants = args.length ? args.map(Number) : [...Array(8)].map((_, i) => +((cycle * (i + 0.5)) / 8).toFixed(2));

const dossier = path.join(__dirname, 'controle');
fs.mkdirSync(dossier, { recursive: true });
const nom = path.basename(fichier, '.svg');
// Chaque copie garde ses propres identifiants, sinon les dégradés de l'une
// servent aux autres.
const copie = (i) => source.replace(/id="([^"]+)"/g, `id="$1_${i}"`).replace(/url\(#([^)]+)\)/g, `url(#$1_${i})`);
const page = `<!doctype html><html><head><meta charset="utf-8"><style>
body{margin:0;background:#05080C;font:14px monospace;color:#94A3B0}
div{padding:10px 0 4px 12px}svg{display:block;width:${largeur}px;height:${hauteur}px}
</style></head><body>
${instants.map((s, i) => `<div>t = ${s} s</div>${copie(i)}`).join('\n')}
<script>
const t=${JSON.stringify(instants)};
document.querySelectorAll('svg').forEach((s,i)=>{s.pauseAnimations();s.setCurrentTime(t[i]);});
</script></body></html>`;
const html = path.join(dossier, `${nom}.html`);
fs.writeFileSync(html, page);
const png = path.join(dossier, `${nom}.png`);
const h = instants.length * (hauteur + 34) + 10;
execFileSync(CHROME, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--virtual-time-budget=3000',
  `--window-size=${largeur + 24},${h}`, `--screenshot=${png}`, 'file:///' + html.replace(/\\/g, '/')], { stdio: 'ignore' });
console.log(`  ${png}  (${instants.join(', ')} s)`);
