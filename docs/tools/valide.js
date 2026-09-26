// Vérifie chaque animation SMIL des schémas, avant publication.
//
// Un navigateur rejette une animation dont les keyTimes ne commencent pas
// à 0, ne finissent pas à 1, reculent, ou n'ont pas autant d'entrées que
// ses values (ou ses keyPoints). Et une seule animation rejetée fige tout
// le SVG : il reste sur sa première image, sans erreur visible. Les
// planches (planche.js) ne le voient pas, puisqu'elles forcent l'instant.
//
//   node docs/tools/valide.js            # tous les SVG de docs/schemas
const fs = require('fs');
const path = require('path');

const racine = path.join(__dirname, '..', 'schemas');
const fichiers = [];
(function parcourir(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) parcourir(p);
    else if (e.name.endsWith('.svg')) fichiers.push(p);
  }
})(racine);

let fautes = 0;
for (const f of fichiers) {
  const svg = fs.readFileSync(f, 'utf8');
  const erreurs = [];
  for (const m of svg.matchAll(/<(animate|animateMotion|animateTransform)\b([^>]*)>/g)) {
    const attr = (nom) => (m[2].match(new RegExp(`\\b${nom}="([^"]*)"`)) || [])[1];
    const kt = attr('keyTimes');
    if (!kt) continue;
    const t = kt.split(';').map(Number);
    const autres = attr('keyPoints') ?? attr('values');
    const n = autres ? autres.split(';').length : t.length;
    const mode = attr('calcMode') || (m[1] === 'animateMotion' ? 'paced' : 'linear');
    const ennui = [];
    if (t.some(Number.isNaN)) ennui.push('instant illisible');
    if (t[0] !== 0) ennui.push('ne commence pas à 0');
    if (mode !== 'discrete' && t[t.length - 1] !== 1) ennui.push('ne finit pas à 1');
    if (t.some((x, i) => i && x < t[i - 1])) ennui.push('recule');
    if (t.some((x) => x < 0 || x > 1)) ennui.push('hors de 0..1');
    if (n !== t.length) ennui.push(`${t.length} instants pour ${n} valeurs`);
    if (m[1] === 'animateMotion' && mode === 'paced') ennui.push('keyTimes ignorés en mode paced');
    if (ennui.length) erreurs.push(`${m[1]} ${ennui.join(', ')} : keyTimes="${kt.slice(0, 80)}"`);
  }
  const nom = path.relative(racine, f);
  if (erreurs.length) {
    fautes += erreurs.length;
    console.log(`  ${nom} : ${erreurs.length} animation(s) rejetée(s)`);
    for (const e of erreurs.slice(0, 4)) console.log(`    ${e}`);
  } else console.log(`  ${nom} : ok`);
}
process.exitCode = fautes ? 1 : 0;
