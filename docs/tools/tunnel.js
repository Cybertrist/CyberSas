// Le tunnel du logo, pour le README : la traduction fidèle, ligne à ligne,
// du peintre de l'appli (mobile/lib/dessins.dart, _PeintreTunnel). Mêmes
// tracés, mêmes couleurs, mêmes dégradés, mêmes flous, même ordre des
// couches, mêmes délais et mêmes courbes d'allumage et d'extinction, même
// respiration du halo et de la porte, mêmes paquets. Le cycle joue ce que
// fait l'accueil quand on touche l'interrupteur : coupé, allumage,
// connecté, extinction.
//
// Toute modification du dessin dans l'appli doit être reportée ici.
const S = require('./svg');
const { K, MONO, SANS, t } = S;

const C = 16; // secondes par cycle
const A = 1.5; // début de l'allumage
const E = 10; // début de l'extinction
const r4 = (n) => +n.toFixed(4);
const bez = (c) => c.join(' ');

// Les courbes de l'appli (Cubic de Flutter = keySplines de SMIL).
const EASE = [0.25, 0.1, 0.25, 1];
const ALLUMAGE = { bg: [0, 0.7, EASE], a2: [0.45, 0.4, EASE], a1: [0.8, 0.4, EASE], h: [1.15, 0.4, EASE], cable: [1.5, 1.1, [0.2, 0, 0.5, 1]], points: [2.5, 0.4, EASE] };
const EXTINCTION = { points: [0, 0.25, EASE], cable: [0, 1.1, [0.5, 0, 0.8, 1]], h: [1.15, 0.45, EASE], a1: [1.55, 0.45, EASE], a2: [1.95, 0.45, EASE], bg: [2.35, 0.8, EASE] };

/// Une valeur qui passe de v0 à v1 à l'allumage de la couche, et revient
/// à v0 à son extinction, avec les courbes de l'appli.
function cycle(attribut, couche, v0, v1) {
  const [da, ua, ca] = ALLUMAGE[couche];
  const [de, ue, ce] = EXTINCTION[couche];
  const kt = [0, (A + da) / C, (A + da + ua) / C, (E + de) / C, (E + de + ue) / C, 1].map(r4);
  const lin = '0 0 1 1';
  return `<animate attributeName="${attribut}" dur="${C}s" repeatCount="indefinite" calcMode="spline" keyTimes="${kt.join(';')}" values="${v0};${v0};${v1};${v1};${v0};${v0}" keySplines="${lin};${bez(ca)};${lin};${bez(ce)};${lin}"/>`;
}
/// La couche de l'appli : un groupe dont l'opacité suit son minutage.
const couche = (nom, contenu) => `<g opacity="0">${cycle('opacity', nom, 0, 1)}${contenu}</g>`;
/// pulse(a, b, période) de l'appli : un triangle, de a à b et retour.
const pulse = (attr, a, b, periode) => `<animate attributeName="${attr}" dur="${periode}s" repeatCount="indefinite" keyTimes="0;0.5;1" values="${a};${b};${a}"/>`;

const T = {
  maison: 'M69 205 V98 Q69 86 80 80 L137 50 Q144 46 151 50 L208 80 Q219 86 219 98 V205',
  arche1: 'M97 200 V137 A47 47 0 0 1 191 137 V200',
  arche2: 'M124 190 V140 A20 20 0 0 1 164 140 V190',
  porte: 'M129 160 V141 A15 15 0 0 1 159 141 V160 Z',
  sol: 'M121 159.5 L167 159.5 L330 250 L330 330 L-42 330 L-42 250 Z',
  bords: 'M121 159.5 L-42 250 M167 159.5 L330 250',
  dessus: 'M-60 -60 H350 V260 L167 159.5 H121 L-60 260 Z',
  cables: ['M34 252 C62 236 84 222 98 200 L134 160', 'M144 290 L144 160', 'M254 252 C226 236 204 222 190 200 L154 160'],
};

const hex = (n) => '#' + n.toString(16).padStart(6, '0').toUpperCase();
/// Un dégradé linéaire vertical, en coordonnées du dessin.
const lin = (id, y1, y2, arrets) => `<linearGradient id="${id}" x1="0" y1="${y1}" x2="0" y2="${y2}" gradientUnits="userSpaceOnUse">${arrets.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${hex(c)}" stop-opacity="${a}"/>`).join('')}</linearGradient>`;
const rad = (id, cx, cy, r, arrets) => `<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${r}" gradientUnits="userSpaceOnUse">${arrets.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${hex(c)}" stop-opacity="${a}"/>`).join('')}</radialGradient>`;

/// Le dessin entier, allumé (on) ou fantôme (le peintre « fantome » de
/// l'appli : couleurs éteintes et filtre bleu nuit sur les traits).
function dessin(on) {
  const p = on ? 'on' : 'off';
  const nuit = on ? '' : ' filter="url(#tNuit)"';
  const defs = `
${rad(`${p}Ciel`, 144, 110, 150, on ? [[0, 0x0A3246, 0.9], [0.6, 0x061A26, 0.5], [1, 0x04060A, 0]] : [[0, 0x0E151C, 0.9], [0.6, 0x0A1016, 0.5], [1, 0x04060A, 0]])}
${lin(`${p}Anneau`, 20, 200, [[0, on ? 0x31E7FD : 0x3A4450, 0.32], [0.7, on ? 0x31E7FD : 0x3A4450, 0.12], [1, 0x31E7FD, 0]])}
${lin(`${p}Sol`, 160, 300, on ? [[0, 0x0E3446], [0.45, 0x08202D], [1, 0x04060A, 0]] : [[0, 0x161D24], [0.45, 0x0C1117], [1, 0x04060A, 0]])}
${lin(`${p}Bords`, 160, 250, [[0, on ? 0x31E7FD : 0x3A4450, 0.35], [1, 0x31E7FD, 0]])}`;
  const halo = on ? `<path d="${T.maison}" fill="none" stroke="#31E7FD" stroke-width="22" stroke-linejoin="round" stroke-opacity="0.2" filter="url(#tFlou8)">${pulse('stroke-opacity', 0.2, 0.38, 3)}</path>`
    : `<path d="${T.maison}" fill="none" stroke="#31E7FD" stroke-width="22" stroke-linejoin="round" stroke-opacity="0.28" filter="url(#tFlou8)"/>`;
  const lueurPorte = on ? `<path d="${T.porte}" fill="#5FF0FF" fill-opacity="0.5" filter="url(#tFlou8)">${pulse('fill-opacity', 0.5, 0.9, 3)}</path>`
    : `<path d="${T.porte}" fill="#5FF0FF" fill-opacity="0.7" filter="url(#tFlou8)"/>`;
  const L = on ? couche : (_n, c) => c;
  const ciel = `<ellipse cx="144" cy="120" rx="160" ry="120" fill="url(#${p}Ciel)"/>
<circle cx="144" cy="152" r="128" fill="none" stroke="url(#${p}Anneau)" stroke-width="1.3" clip-path="url(#tDessus)"/>`;
  const maison = `${halo}<path d="${T.maison}" fill="none" stroke="url(#tGMaison)" stroke-width="16" stroke-linejoin="round"/>`;
  const arche1 = `<path d="${T.arche1}" fill="none" stroke="url(#tGA1)" stroke-width="11" stroke-linejoin="round"/>`;
  const arche2 = `<path d="${T.arche2}" fill="none" stroke="url(#tGA2)" stroke-width="10" stroke-linejoin="round"/>`;
  const porte = `${lueurPorte}<path d="${T.porte}" fill="url(#tGPorte)"/>`;
  const sol = `<path d="${T.sol}" fill="url(#${p}Sol)"/>${on ? `<path d="${T.sol}" fill="url(#tLueurSol)"/>` : ''}<path d="${T.bords}" fill="none" stroke="url(#${p}Bords)" stroke-width="1.2"/>`;
  // Les câbles : pathLength 100 ; un tiret de 100 suivi d'un blanc de 200.
  // Décalage 100 : caché. 0 : plein. -100 : vidé depuis le départ, comme
  // l'appli à l'extinction.
  const decalage = on ? (() => {
    const [da, ua, ca] = ALLUMAGE.cable;
    const [de, ue, ce] = EXTINCTION.cable;
    const kt = [0, (A + da) / C, (A + da + ua) / C, (E + de) / C, (E + de + ue) / C, 1].map(r4);
    return `<animate attributeName="stroke-dashoffset" dur="${C}s" repeatCount="indefinite" calcMode="spline" keyTimes="${kt.join(';')}" values="100;100;0;0;-100;-100" keySplines="0 0 1 1;${bez(ca)};0 0 1 1;${bez(ce)};0 0 1 1"/>`;
  })() : '';
  const tiret = on ? ' pathLength="100" stroke-dasharray="100 200" stroke-dashoffset="100"' : '';
  const cables = T.cables.map((d) => `<path d="${d}" fill="none" stroke="#31E7FD" stroke-opacity="0.35" stroke-width="7" stroke-linecap="round" filter="url(#tFlou4)"${tiret}>${decalage}</path>
<path d="${d}" fill="none" stroke="url(#tGCable)" stroke-width="3.6" stroke-linecap="round"${tiret}>${decalage}</path>`).join('\n');
  // Les câbles n'existent, allumés, que de l'allumage à la fin de
  // l'extinction : un tiret de longueur nulle garderait son bout arrondi.
  const visibleCables = on ? `<animate attributeName="opacity" dur="${C}s" repeatCount="indefinite" calcMode="discrete" keyTimes="0;${r4((A + ALLUMAGE.cable[0]) / C)};${r4((E + EXTINCTION.cable[0] + EXTINCTION.cable[1]) / C)}" values="0;1;0"/>` : '';
  return `<defs>${defs}</defs>
${L('bg', ciel)}
<g${nuit}>${L('h', maison)}</g>
<g${nuit}>${L('a1', arche1)}</g>
<g${nuit}>${L('a2', arche2)}</g>
<g${nuit}>${L('bg', porte)}</g>
${L('bg', sol)}
<g${nuit} opacity="${on ? 0 : 1}">${visibleCables}${cables}</g>`;
}

/// Les paquets : pour le câble i, x = ((t + i) mod 3) / 3, la position et
/// l'échelle suivent Cubic(0.25, 0.1, 0.6, 1), l'opacité monte sur les
/// 14 premiers pour cent et descend sur les 14 derniers.
function paquets() {
  const corps = T.cables.map((d, i) => `<g>
  <animateMotion dur="3s" begin="-${i}s" repeatCount="indefinite" path="${d}" calcMode="spline" keyTimes="0;1" keyPoints="0;1" keySplines="0.25 0.1 0.6 1"/>
  <g opacity="0">
    <animate attributeName="opacity" dur="3s" begin="-${i}s" repeatCount="indefinite" keyTimes="0;0.14;0.86;1" values="0;1;1;0"/>
    <g>
      <animateTransform attributeName="transform" type="scale" dur="3s" begin="-${i}s" repeatCount="indefinite" calcMode="spline" keyTimes="0;1" values="1.1;0.3" keySplines="0.25 0.1 0.6 1"/>
      <ellipse rx="13" ry="10" fill="#31E7FD" fill-opacity="0.35" filter="url(#tFlou4p)"/>
      <ellipse rx="10" ry="7.5" fill="url(#tNoyau)"/>
      <ellipse rx="10" ry="7.5" fill="none" stroke="#A8F8FF" stroke-width="1.6"/>
    </g>
  </g>
</g>`).join('\n');
  return couche('points', corps);
}

/// Le tunnel, comme le CustomPaint de l'accueil : un panneau de l × h sur
/// le fond de l'appli, où le repère 320 × 338 est posé « meet », centré.
function tunnel(px, py, pl, ph) {
  const e = Math.min(pl / 320, ph / 338);
  const x = px + (pl - 320 * e) / 2;
  const y = py + (ph - 338 * e) / 2;
  return `<defs>
  <filter id="tFlou8" filterUnits="userSpaceOnUse" x="-120" y="-120" width="560" height="560"><feGaussianBlur stdDeviation="8"/></filter>
  <filter id="tFlou4" filterUnits="userSpaceOnUse" x="-120" y="-120" width="560" height="560"><feGaussianBlur stdDeviation="4"/></filter>
  <filter id="tFlou4p" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="4"/></filter>
  <filter id="tNuit" filterUnits="userSpaceOnUse" x="-120" y="-120" width="560" height="560" color-interpolation-filters="sRGB">
    <feColorMatrix type="matrix" values=".016 .032 .006 0 .012  .038 .075 .014 0 .03  .052 .102 .019 0 .045  0 0 0 1 0"/>
  </filter>
  <clipPath id="tDessus"><path d="${T.dessus}"/></clipPath>
  <!-- Pas de boîte : le dessin se pose sur le fond de la carte, et ses
       bords (le sol, le ciel) s'effacent en douceur au lieu d'être coupés. -->
  <radialGradient id="tFondu" cx="${px + pl / 2}" cy="${py + ph * 0.45}" r="${Math.max(pl, ph) * 0.62}" gradientUnits="userSpaceOnUse">
    <stop offset="0.62" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
  </radialGradient>
  <mask id="tCadre" maskUnits="userSpaceOnUse" x="${px - 200}" y="${py - 200}" width="${pl + 400}" height="${ph + 400}">
    <rect x="${px - 200}" y="${py - 200}" width="${pl + 400}" height="${ph + 400}" fill="url(#tFondu)"/>
  </mask>
  ${lin('tGMaison', 44, 200, [[0, 0x2DEBFF], [0.25, 0x18DDFF], [0.6, 0x0AA8FF], [1, 0x1FD2FF]])}
  ${lin('tGA1', 88, 200, [[0, 0x1CB9DB], [0.5, 0x0E8DB8], [1, 0x0A6C92]])}
  ${lin('tGA2', 118, 190, [[0, 0x127C9E], [1, 0x0A506E]])}
  ${lin('tGPorte', 126, 160, [[0, 0xC4FCFF], [1, 0x7DF0FF]])}
  ${lin('tGCable', 160, 285, [[0, 0x8FF4FF], [0.5, 0x22DDFB], [1, 0x01B9FD, 0]])}
  ${rad('tLueurSol', 144, 162, 90, [[0, 0x31E7FD, 0.32], [1, 0x31E7FD, 0]])}
  ${rad('tNoyau', -1, -1.5, 12, [[0, 0x6FF1FF], [1, 0x14C8EE]])}
</defs>
<g mask="url(#tCadre)"><g transform="translate(${x},${y}) scale(${e})">
  <g transform="translate(1.6,-8) scale(1.1)">
    <g opacity="0.4">${dessin(false)}</g>
    ${dessin(true)}
    ${paquets()}
  </g>
</g></g>`;
}

module.exports = { tunnel, C, A, E, ALLUMAGE, EXTINCTION };
