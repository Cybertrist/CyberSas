// Les schémas animés du README.
//
// Des SVG plutôt que des GIF : quelques kilo-octets, nets à toute taille,
// et le texte reste du texte. Les animations sont en SMIL, que les
// navigateurs jouent même quand le SVG est chargé par une balise <img>,
// ce qui est le cas sur GitHub. Aucune police externe : un SVG affiché en
// <img> n'a pas le droit d'aller la chercher, on s'en tient aux familles
// du système. Même principe que SmartBudget.
//
//   node docs/tools/anime.js
const fs = require('fs');
const path = require('path');

const SORTIE = path.join(__dirname, '..', 'schemas');
fs.mkdirSync(SORTIE, { recursive: true });

const MONO = 'ui-monospace,SFMono-Regular,Menlo,Consolas,monospace';
const SANS = 'system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif';
const FOND = '#0D1117';
const CARTE = '#0C1117';
const BORD = '#2A333D';
const TITRE = '#F1F5F9';
const TEXTE = '#94A3B0';
const DISCRET = '#5C6A7A';
const FIL = '#2F3A47';
const CYAN = '#31E7FD';
const BLEU = '#01B9FD';
const VERT = '#3DDC97';
const ROUGE = '#FF5C63';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/// Le cadre commun : fond, grille estompée, filtres de halo.
function svg(nom, largeur, hauteur, corps, titre) {
  const contenu = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${largeur} ${hauteur}" width="${largeur}" height="${hauteur}" role="img" aria-label="${esc(titre)}">
<title>${esc(titre)}</title>
<defs>
  <filter id="halo" x="-50%" y="-50%" width="200%" height="200%">
    <feGaussianBlur stdDeviation="6" result="b"/>
    <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="flou" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="8"/></filter>
  <pattern id="grille" width="40" height="40" patternUnits="userSpaceOnUse">
    <path d="M40 0H0V40" fill="none" stroke="${CYAN}" stroke-opacity="0.05"/>
  </pattern>
  <radialGradient id="lueur" cx="50%" cy="0%" r="80%">
    <stop offset="0" stop-color="${CYAN}" stop-opacity="0.10"/><stop offset="1" stop-color="${CYAN}" stop-opacity="0"/>
  </radialGradient>
</defs>
<rect width="${largeur}" height="${hauteur}" rx="16" fill="${FOND}"/>
<rect width="${largeur}" height="${hauteur}" rx="16" fill="url(#grille)"/>
<rect width="${largeur}" height="${hauteur}" rx="16" fill="url(#lueur)"/>
${corps}
</svg>`;
  fs.writeFileSync(path.join(SORTIE, nom), contenu);
  console.log(`  ${nom}  ${(contenu.length / 1024).toFixed(1)} Ko`);
}

/// Un texte.
const t = (x, y, s, { taille = 14, couleur = TEXTE, police = SANS, poids = 400, ancre = 'start', extra = '' } = {}) =>
  `<text x="${x}" y="${y}" font-family="${police}" font-size="${taille}" font-weight="${poids}" fill="${couleur}" text-anchor="${ancre}" ${extra}>${esc(s)}</text>`;

/// Une valeur qui glisse d'un palier au suivant, sur un cycle.
function fondu(attribut, cycle, etapes) {
  // Arrondis : Chrome rejette un instant comme 0.009999999999999998, et une
  // seule animation rejetée fige tout le SVG.
  const temps = etapes.map((e) => +e[0].toFixed(4)).join(';');
  const valeurs = etapes.map((e) => e[1]).join(';');
  return `<animate attributeName="${attribut}" dur="${cycle}s" repeatCount="indefinite" keyTimes="${temps}" values="${valeurs}"/>`;
}

/// Visible de [de] à [a] sur un cycle (0..1), avec un court fondu.
function visible(cycle, de, a, douceur = 0.02) {
  const e = [[0, 0]];
  if (de > douceur) e.push([de - douceur, 0]);
  e.push([de, 1], [Math.min(a, 1), 1]);
  if (a + douceur < 1) e.push([a + douceur, 0], [1, 0]);
  else if (a < 1) e.push([1, 1]);
  return fondu('opacity', cycle, e);
}

/// Une carte : liseré coloré, pictogramme, titre en chasse fixe, sous-titre.
function carte(x, y, l, h, titre, sous, accent, { icone = null, allume = null, cycle = 10 } = {}) {
  const bord = allume
    ? `<rect x="${x}" y="${y}" width="${l}" height="${h}" rx="14" fill="none" stroke="${accent}" stroke-width="1.6" opacity="0" filter="url(#halo)">${visible(cycle, allume[0], allume[1])}</rect>`
    : '';
  return `<g>
  <rect x="${x}" y="${y}" width="${l}" height="${h}" rx="14" fill="${CARTE}" stroke="${BORD}"/>
  ${bord}
  <rect x="${x}" y="${y + 14}" width="3" height="${h - 28}" rx="1.5" fill="${accent}"/>
  ${icone ? `<g transform="translate(${x + 18},${y + h / 2 - 14})">${icone(accent)}</g>` : ''}
  ${t(x + (icone ? 58 : 20), y + h / 2 - 3, titre, { taille: 14.5, couleur: TITRE, police: MONO, poids: 700 })}
  ${t(x + (icone ? 58 : 20), y + h / 2 + 17, sous, { taille: 12.5 })}
</g>`;
}

/// Une bille lumineuse qui glisse sur un trajet horizontal « M x y H x2 ».
/// [points] : où elle en est (0..1) aux instants [temps]. On anime cx
/// plutôt qu'un animateMotion à points d'arrêt : Chrome en rejette
/// certains, et une seule animation rejetée fige tout le SVG.
function bille(chemin, cycle, points, temps, couleur = CYAN, rayon = 6) {
  const [, x0, y, x1] = chemin.match(/M\s*([\d.]+)\s+([\d.]+)\s*H\s*([\d.]+)/).map(Number);
  const xs = points.split(';').map((p) => (x0 + parseFloat(p) * (x1 - x0)).toFixed(1)).join(';');
  const cx = `<animate attributeName="cx" dur="${cycle}s" repeatCount="indefinite" keyTimes="${temps}" values="${xs}"/>`;
  return `<g filter="url(#halo)">
  <circle cx="${x0}" cy="${y}" r="${rayon + 5}" fill="${couleur}" opacity="0.22">${cx}</circle>
  <circle cx="${x0}" cy="${y}" r="${rayon}" fill="${couleur}">${cx}</circle>
</g>`;
}

/// Un fil pointillé qui court.
const fil = (d, couleur = FIL) =>
  `<path d="${d}" fill="none" stroke="${couleur}" stroke-width="2" stroke-dasharray="6 7">
  <animate attributeName="stroke-dashoffset" from="26" to="0" dur="1.2s" repeatCount="indefinite"/></path>`;

// Des pictogrammes simples, en traits, 28 × 28.
const P = {
  telephone: (c) => `<rect x="7" y="1" width="14" height="26" rx="3.5" fill="none" stroke="${c}" stroke-width="2"/><path d="M12 23 H16" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  serveur: (c) => `<rect x="3" y="3" width="22" height="9" rx="2.5" fill="none" stroke="${c}" stroke-width="2"/><rect x="3" y="16" width="22" height="9" rx="2.5" fill="none" stroke="${c}" stroke-width="2"/><path d="M8 7.5h.01M8 20.5h.01" stroke="${c}" stroke-width="3" stroke-linecap="round"/>`,
  maison: (c) => `<path d="M4 25 V12 L14 4 L24 12 V25 M11 25 V18 H17 V25" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/>`,
  portable: (c) => `<rect x="5" y="5" width="18" height="13" rx="2" fill="none" stroke="${c}" stroke-width="2"/><path d="M2 23 H26" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  qr: (c) => `<rect x="3" y="3" width="9" height="9" rx="1.5" fill="none" stroke="${c}" stroke-width="2"/><rect x="16" y="3" width="9" height="9" rx="1.5" fill="none" stroke="${c}" stroke-width="2"/><rect x="3" y="16" width="9" height="9" rx="1.5" fill="none" stroke="${c}" stroke-width="2"/><path d="M17 17h3v3h-3zM22 22h3v3h-3z" fill="${c}"/>`,
  cle: (c) => `<circle cx="9" cy="18" r="5.5" fill="none" stroke="${c}" stroke-width="2"/><path d="M13 14 L24 3 M20 7 L23 10 M17 10 L19 12" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  oeil: (c) => `<path d="M2 14 C6 7 22 7 26 14 C22 21 6 21 2 14 Z" fill="none" stroke="${c}" stroke-width="2"/><circle cx="14" cy="14" r="3.5" fill="none" stroke="${c}" stroke-width="2"/>`,
  empreinte: (c) => `<path d="M5 13 A9 9 0 0 1 23 13 M9 25 C10 21 10 17 10 14 A4 4 0 0 1 18 14 C18 18 18 22 16 26 M14 14 C14 18 14 21 12 25 M22 18 C22 20 21.5 22 21 24" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  reseau: (c) => `<circle cx="14" cy="5" r="3" fill="none" stroke="${c}" stroke-width="2"/><circle cx="5" cy="22" r="3" fill="none" stroke="${c}" stroke-width="2"/><circle cx="23" cy="22" r="3" fill="none" stroke="${c}" stroke-width="2"/><path d="M12.5 7.5 L6.5 19.5 M15.5 7.5 L21.5 19.5 M8 22 H20" stroke="${c}" stroke-width="2"/>`,
  crane: (c) => `<path d="M6 16 A8 8 0 1 1 22 16 V20 H18 V24 H10 V20 H6 Z" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/><circle cx="10.5" cy="14" r="2" fill="${c}"/><circle cx="17.5" cy="14" r="2" fill="${c}"/>`,
  bouclier: (c) => `<path d="M14 2 L24 6 V13 C24 19 19.5 23.5 14 26 C8.5 23.5 4 19 4 13 V6 Z" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/><path d="M9.5 14 L12.5 17 L18.5 11" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`,
};

// ------------------------------------------------------------ 1. le tunnel
// Les tracés du logo, ceux que l'appli anime sur son accueil
// (mobile/lib/dessins.dart). Il s'allume couche par couche, les paquets
// entrent, puis il s'éteint dans l'ordre inverse.
{
  const C = 12; // secondes par cycle
  const T = {
    maison: 'M69 205 V98 Q69 86 80 80 L137 50 Q144 46 151 50 L208 80 Q219 86 219 98 V205',
    arche1: 'M97 200 V137 A47 47 0 0 1 191 137 V200',
    arche2: 'M124 190 V140 A20 20 0 0 1 164 140 V190',
    porte: 'M129 160 V141 A15 15 0 0 1 159 141 V160 Z',
    sol: 'M121 159.5 L167 159.5 L330 250 L330 330 L-42 330 L-42 250 Z',
    bords: 'M121 159.5 L-42 250 M167 159.5 L330 250',
    cables: ['M34 252 C62 236 84 222 98 200 L134 160', 'M144 290 L144 160', 'M254 252 C226 236 204 222 190 200 L154 160'],
  };
  // Allumé de [a] à [b] (fraction du cycle), avec 0,05 de montée et de descente.
  const couche = (a, b, contenu, extra = '') =>
    `<g opacity="0" ${extra}>${fondu('opacity', C, [[0, 0], [a, 0], [a + 0.05, 1], [b, 1], [b + 0.05, 0], [1, 0]])}${contenu}</g>`;
  const trait = (d, larg, grad) => `<path d="${d}" fill="none" stroke="url(#${grad})" stroke-width="${larg}" stroke-linejoin="round"/>`;
  const fantome = `<g opacity="0.22">
    <path d="${T.sol}" fill="#161D24"/>
    <path d="${T.maison}" fill="none" stroke="#1A3440" stroke-width="16" stroke-linejoin="round"/>
    <path d="${T.arche1}" fill="none" stroke="#15303B" stroke-width="11"/>
    <path d="${T.arche2}" fill="none" stroke="#122833" stroke-width="10"/>
    <path d="${T.porte}" fill="#1D3F4B"/>
  </g>`;
  const cables = T.cables
    .map(
      (d) => `<path d="${d}" fill="none" stroke="${CYAN}" stroke-opacity="0.35" stroke-width="7" stroke-linecap="round" filter="url(#flou)" pathLength="100" stroke-dasharray="100" stroke-dashoffset="100">${fondu('stroke-dashoffset', C, [[0, 100], [0.3, 100], [0.4, 0], [0.8, 0], [0.88, -100], [1, -100]])}</path>
<path d="${d}" fill="none" stroke="url(#gCable)" stroke-width="3.6" stroke-linecap="round" pathLength="100" stroke-dasharray="100" stroke-dashoffset="100">${fondu('stroke-dashoffset', C, [[0, 100], [0.3, 100], [0.4, 0], [0.8, 0], [0.88, -100], [1, -100]])}</path>`,
    )
    .join('\n');
  const paquets = T.cables
    .map(
      (d, i) => `<g>
  <ellipse rx="10" ry="7.5" fill="#6FF1FF" stroke="#A8F8FF" stroke-width="1.6" filter="url(#halo)">
    <animateMotion dur="3s" begin="${i}s" repeatCount="indefinite" path="${d}" keyPoints="0;1" keyTimes="0;1" calcMode="spline" keySplines="0.25 0.1 0.6 1"/>
    <animateTransform attributeName="transform" type="scale" dur="3s" begin="${i}s" repeatCount="indefinite" values="1.1;0.3" additive="sum"/>
  </ellipse></g>`,
    )
    .join('\n');
  const corps = `
<defs>
  <linearGradient id="gMaison" x1="0" y1="44" x2="0" y2="200" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#2DEBFF"/><stop offset=".25" stop-color="#18DDFF"/><stop offset=".6" stop-color="#0AA8FF"/><stop offset="1" stop-color="#1FD2FF"/></linearGradient>
  <linearGradient id="gA1" x1="0" y1="88" x2="0" y2="200" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#1CB9DB"/><stop offset=".5" stop-color="#0E8DB8"/><stop offset="1" stop-color="#0A6C92"/></linearGradient>
  <linearGradient id="gA2" x1="0" y1="118" x2="0" y2="190" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#127C9E"/><stop offset="1" stop-color="#0A506E"/></linearGradient>
  <linearGradient id="gPorte" x1="0" y1="126" x2="0" y2="160" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#C4FCFF"/><stop offset="1" stop-color="#7DF0FF"/></linearGradient>
  <linearGradient id="gSol" x1="0" y1="160" x2="0" y2="300" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#0E3446"/><stop offset=".45" stop-color="#08202D"/><stop offset="1" stop-color="#04060A" stop-opacity="0"/></linearGradient>
  <linearGradient id="gCable" x1="0" y1="160" x2="0" y2="285" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#8FF4FF"/><stop offset=".5" stop-color="#22DDFB"/><stop offset="1" stop-color="#01B9FD" stop-opacity="0.2"/></linearGradient>
  <radialGradient id="gCiel" cx="144" cy="110" r="150" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#0A3246" stop-opacity=".9"/><stop offset=".6" stop-color="#061A26" stop-opacity=".5"/><stop offset="1" stop-color="#04060A" stop-opacity="0"/></radialGradient>
  <clipPath id="cadre"><rect x="-42" y="-20" width="372" height="330"/></clipPath>
</defs>
<g transform="translate(470,34) scale(1.12)" clip-path="url(#cadre)">
  ${fantome}
  ${couche(0.02, 0.93, `<ellipse cx="144" cy="120" rx="160" ry="120" fill="url(#gCiel)"/><path d="${T.sol}" fill="url(#gSol)"/><path d="${T.bords}" fill="none" stroke="${CYAN}" stroke-opacity="0.3" stroke-width="1.2"/>`)}
  ${couche(0.07, 0.9, trait(T.arche2, 10, 'gA2'))}
  ${couche(0.12, 0.87, trait(T.arche1, 11, 'gA1'))}
  ${couche(0.17, 0.84, `<path d="${T.maison}" fill="none" stroke="${CYAN}" stroke-opacity="0.3" stroke-width="22" stroke-linejoin="round" filter="url(#flou)"/>${trait(T.maison, 16, 'gMaison')}`)}
  ${couche(0.02, 0.93, `<path d="${T.porte}" fill="#5FF0FF" filter="url(#flou)"/><path d="${T.porte}" fill="url(#gPorte)"/>`)}
  ${cables}
  ${couche(0.42, 0.78, paquets)}
</g>
${t(80, 150, 'LE TUNNEL', { taille: 12, couleur: CYAN, police: MONO, extra: 'letter-spacing="3"' })}
${t(80, 184, 'Noise IK, puis', { taille: 22, couleur: TITRE, poids: 600 })}
${t(80, 214, 'ChaCha20-Poly1305', { taille: 22, couleur: TITRE, poids: 600 })}
${t(80, 248, 'Clés renouvelées toutes les deux minutes,', { taille: 14 })}
${t(80, 270, 'rejeu et inondation refusés.', { taille: 14 })}
<g>${t(1200, 150, 'ÉTAT', { taille: 12, couleur: DISCRET, police: MONO, ancre: 'end', extra: 'letter-spacing="3"' })}
  <g opacity="0">${fondu('opacity', C, [[0, 0], [0.4, 0], [0.43, 1], [0.84, 1], [0.87, 0], [1, 0]])}${t(1200, 188, 'Connecté', { taille: 26, couleur: CYAN, poids: 600, ancre: 'end' })}</g>
  <g opacity="0">${fondu('opacity', C, [[0, 0], [0.02, 0], [0.05, 1], [0.38, 1], [0.41, 0], [1, 0]])}${t(1200, 188, 'Connexion…', { taille: 26, couleur: TEXTE, poids: 600, ancre: 'end' })}</g>
  <g opacity="1">${fondu('opacity', C, [[0, 1], [0.02, 1], [0.05, 0], [0.86, 0], [0.89, 1], [1, 1]])}${t(1200, 188, 'Coupé', { taille: 26, couleur: DISCRET, poids: 600, ancre: 'end' })}</g>
  ${t(1200, 218, '10.77.0.18 → 10.77.0.2', { taille: 14, police: MONO, ancre: 'end' })}
</g>`;
  svg('tunnel.svg', 1280, 400, corps, "Le tunnel du logo de CyberSas, animé comme dans l'appli : il s'allume couche par couche, les paquets entrent, puis il s'éteint. À gauche : Noise IK, puis ChaCha20-Poly1305, clés renouvelées toutes les deux minutes. À droite, l'état : coupé, connexion, connecté.");
}

// ------------------------------------------------------------ 2. le relais
// Un paquet part du téléphone, traverse le serveur, arrive à la maison.
// En clair aux deux bouts, illisible au milieu.
{
  const C = 7;
  const y = 120;
  const chemin = `M 300 ${y + 38} H 980`;
  const bulle = (x, titre, lignes, couleur, de, a) => `<g opacity="0">${visible(C, de, a, 0.03)}
  <rect x="${x}" y="${y + 104}" width="300" height="112" rx="12" fill="#0A1017" stroke="${couleur}" stroke-opacity="0.45"/>
  ${t(x + 18, y + 130, titre, { taille: 11.5, couleur, police: MONO, extra: 'letter-spacing="2"' })}
  ${lignes.map((l, i) => t(x + 18, y + 158 + i * 22, l, { taille: 14, couleur: TITRE, police: MONO })).join('')}
</g>`;
  const corps = `
${fil(`M 300 ${y + 38} H 490`)}${fil(`M 790 ${y + 38} H 980`)}
${carte(40, y, 260, 76, 'fold8-tristan', '10.77.0.18 · le téléphone', CYAN, { icone: P.telephone, allume: [0.02, 0.3], cycle: C })}
${carte(490, y, 300, 76, 'sasd', 'le serveur, qui relaie', BLEU, { icone: P.serveur, allume: [0.32, 0.6], cycle: C })}
${carte(980, y, 260, 76, 'maison', '10.77.0.2 · à la maison', VERT, { icone: P.maison, allume: [0.62, 0.95], cycle: C })}
${bille(chemin, C, '0;0;0.28;0.28;0.72;0.72;1;1', '0;0.12;0.3;0.52;0.62;0.64;0.8;1')}
${bulle(20, 'EN CLAIR, SUR LE TÉLÉPHONE', ['GET / HTTP/1.1', 'Host: maison.sas.internal'], CYAN, 0.02, 0.3)}
${bulle(490, 'CE QUE VOIT LE SERVEUR', ['7f 3a 9c e1 0b 52 d4 88', '19 a7 f0 3e 6c 21 …'], ROUGE, 0.32, 0.6)}
${bulle(960, 'DÉCHIFFRÉ, À LA MAISON', ['GET / HTTP/1.1', 'Host: maison.sas.internal'], VERT, 0.62, 0.95)}
${t(640, 60, 'LE SERVEUR RELAIE CE QU’IL NE PEUT PAS LIRE', { taille: 13, couleur: CYAN, police: MONO, ancre: 'middle', extra: 'letter-spacing="3"' })}
${t(640, 88, 'Les deux appareils ont leur propre session Noise : le serveur n’en a pas les clés.', { taille: 15, ancre: 'middle' })}`;
  svg('relais.svg', 1280, 370, corps, "Un paquet part du téléphone fold8-tristan, en clair : GET / HTTP/1.1. Il traverse le serveur sasd, qui ne voit que des octets chiffrés, puis arrive déchiffré à la maison. Le serveur relaie ce qu'il ne peut pas lire.");
}

// -------------------------------------------------------- 3. l'inscription
// Du QR de l'invitation à l'appareil dans le réseau, en cinq étapes.
{
  const C = 11;
  const l = 222;
  const g = 22;
  const y = 130;
  const etapes = [
    ['Invitation', 'QR à usage unique', P.qr, CYAN],
    ['Sa propre clé', 'créée sur l’appareil', P.cle, CYAN],
    ['Empreinte', 'Qm7X-tR2k-9vLp', P.oeil, BLEU],
    ['Signé', 'au doigt, par l’admin', P.empreinte, VERT],
    ['Dans le réseau', '10.77.0.3 · 120 jours', P.reseau, VERT],
  ];
  const x0 = (1280 - (5 * l + 4 * g)) / 2;
  const tranche = 0.9 / etapes.length;
  const cartes = etapes
    .map(([ti, so, ic, co], i) => carte(x0 + i * (l + g), y, l, 80, ti, so, co, { icone: ic, allume: [0.03 + i * tranche, 0.03 + (i + 1) * tranche], cycle: C }))
    .join('\n');
  const chemin = `M ${x0 + l / 2} ${y + 118} H ${x0 + 4 * (l + g) + l / 2}`;
  const pts = etapes.map((_, i) => [(i / 4).toFixed(3), (0.03 + i * tranche + 0.02).toFixed(3)]);
  const keyPoints = ['0', ...pts.flatMap((p, i) => (i === 0 ? [p[0]] : [pts[i - 1][0], p[0]])), '1', '1'];
  const keyTimes = ['0', ...pts.flatMap((p, i) => (i === 0 ? [p[1]] : [(parseFloat(p[1]) - 0.06).toFixed(3), p[1]])), '0.95', '1'];
  const numeros = etapes.map((_, i) => t(x0 + i * (l + g) + l / 2, y - 18, `0${i + 1}`, { taille: 12, couleur: DISCRET, police: MONO, ancre: 'middle' })).join('');
  const corps = `
${t(640, 60, 'UN NOUVEL APPAREIL, DE L’INVITATION AU RÉSEAU', { taille: 13, couleur: CYAN, police: MONO, ancre: 'middle', extra: 'letter-spacing="3"' })}
${t(640, 88, 'La clé privée ne quitte jamais l’appareil. L’admin compare l’empreinte, puis signe avec son doigt.', { taille: 15, ancre: 'middle' })}
${numeros}
<path d="${chemin}" stroke="${FIL}" stroke-width="2" stroke-dasharray="6 7"/>
${cartes}
${bille(chemin, C, keyPoints.join(';'), keyTimes.join(';'), VERT, 5)}`;
  svg('inscription.svg', 1280, 290, corps, "Un nouvel appareil rejoint le réseau en cinq étapes : 01 l'invitation, un QR à usage unique ; 02 l'appareil crée sa propre clé ; 03 l'admin compare l'empreinte, Qm7X-tR2k-9vLp ; 04 l'admin signe avec son doigt ; 05 l'appareil est dans le réseau, en 10.77.0.3, pour 120 jours.");
}

// -------------------------------------------------------- 4. le verrou
// Un serveur piraté présente un intrus : sans signature du verrou, le
// téléphone le refuse. Un appareil signé, lui, passe.
{
  const C = 9;
  const y = 120;
  const corps = `
${t(640, 60, 'UN SERVEUR PIRATÉ NE FAIT ENTRER PERSONNE', { taille: 13, couleur: CYAN, police: MONO, ancre: 'middle', extra: 'letter-spacing="3"' })}
${t(640, 88, 'Chaque appareil vérifie lui-même le certificat de l’autre, signé par la clé du verrou.', { taille: 15, ancre: 'middle' })}
${fil(`M 330 ${y + 38} H 930`)}${fil(`M 330 ${y + 148} H 930`)}
${carte(60, y, 270, 76, 'intrus', 'glissé par le serveur', ROUGE, { icone: P.crane, allume: [0.05, 0.45], cycle: C })}
${carte(60, y + 110, 270, 76, 'laptop-lea', 'signée par le verrou', VERT, { icone: P.portable, allume: [0.5, 0.92], cycle: C })}
${carte(930, y + 55, 290, 76, 'fold8-tristan', 'vérifie la signature', CYAN, { icone: P.bouclier, allume: [0.05, 0.92], cycle: C })}
${bille(`M 330 ${y + 38} H 900`, C, '0;0;1;1;1', '0;0.06;0.3;0.46;1', ROUGE, 5)}
${bille(`M 330 ${y + 148} H 900`, C, '0;0;0;1;1', '0;0.5;0.52;0.75;1', VERT, 5)}
<g opacity="0">${visible(C, 0.3, 0.46)}
  <rect x="520" y="${y + 18}" width="240" height="40" rx="10" fill="#1A0D10" stroke="${ROUGE}" stroke-opacity="0.6"/>
  ${t(640, y + 43, 'refusé · pas de signature', { taille: 14, couleur: ROUGE, police: MONO, ancre: 'middle' })}</g>
<g opacity="0">${visible(C, 0.75, 0.92)}
  <rect x="520" y="${y + 128}" width="240" height="40" rx="10" fill="#0B1A14" stroke="${VERT}" stroke-opacity="0.6"/>
  ${t(640, y + 153, 'accepté · signé par le verrou', { taille: 14, couleur: VERT, police: MONO, ancre: 'middle' })}</g>`;
  svg('verrou.svg', 1280, 330, corps, "Un serveur piraté glisse un intrus dans le réseau : le téléphone fold8-tristan vérifie le certificat, ne trouve pas de signature du verrou, et le refuse. L'ordinateur laptop-lea, signé par le verrou, est accepté.");
}
