// La boîte à outils des schémas animés : couleurs, textes, cartes, fils,
// billes et pictogrammes. anime.js (le README) et docs.js (les documents
// de docs/) dessinent avec elle.
//
// Deux règles tiennent les schémas propres :
//  - une carte connaît ses bords. Un fil part d'un point d'ancrage et
//    arrive sur un autre (carte.ancre('d')), il ne s'arrête jamais « à peu
//    près » à côté ;
//  - un texte sait sa largeur probable. Chaque texte posé dans une boîte
//    est mesuré avec la police la plus large qu'un visiteur puisse avoir
//    (Menlo pour la chasse fixe), et tout débordement est signalé au rendu.
//
// Les animations sont en SMIL, que GitHub joue dans une balise <img>. Pas
// de police externe : un SVG en <img> n'a pas le droit d'aller la chercher.
const fs = require('fs');
const path = require('path');

const MONO = 'ui-monospace,SFMono-Regular,Menlo,Consolas,monospace';
const SANS = 'system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif';
const K = {
  FOND: '#0D1117', CARTE: '#0C1117', CARTE2: '#0A1017', BORD: '#2A333D', TITRE: '#F1F5F9', TEXTE: '#94A3B0',
  DISCRET: '#5C6A7A', FIL: '#2F3A47', CYAN: '#31E7FD', BLEU: '#01B9FD', VERT: '#3DDC97', ROUGE: '#FF5C63',
};

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const r3 = (n) => +(+n).toFixed(3);

// ------------------------------------------------------------ mesures
// Largeur probable d'un texte, par excès. Chasse fixe : 0,61 em (Menlo, la
// plus large des polices de repli). Sans empattement : 0,56 em en moyenne,
// 0,62 pour les capitales.
function largeur(s, taille, police = SANS, espacement = 0) {
  const n = [...String(s)].length;
  if (police === MONO) return n * (taille * 0.61 + espacement);
  const maj = [...String(s)].filter((c) => /[A-ZÀ-Ý0-9]/.test(c)).length;
  return (n - maj) * taille * 0.53 + maj * taille * 0.64 + n * espacement;
}
const alertes = [];
function controle(s, taille, police, place, ou, espacement = 0) {
  const l = largeur(s, taille, police, espacement);
  if (l > place) alertes.push(`« ${s} » : ${Math.round(l)} px pour ${Math.round(place)} (${ou})`);
}

// --------------------------------------------------------------- cadre
function svg(dossier, nom, l, h, corps, titre) {
  const contenu = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${l} ${h}" width="${l}" height="${h}" role="img" aria-label="${esc(titre)}">
<title>${esc(titre)}</title>
<defs>
  <filter id="halo" x="-50%" y="-50%" width="200%" height="200%">
    <feGaussianBlur stdDeviation="6" result="b"/>
    <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="doux" x="-50%" y="-50%" width="200%" height="200%">
    <feGaussianBlur stdDeviation="3" result="b"/>
    <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="flou" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="8"/></filter>
  <pattern id="grille" width="40" height="40" patternUnits="userSpaceOnUse">
    <path d="M40 0H0V40" fill="none" stroke="${K.CYAN}" stroke-opacity="0.05"/>
  </pattern>
  <radialGradient id="lueur" cx="50%" cy="0%" r="80%">
    <stop offset="0" stop-color="${K.CYAN}" stop-opacity="0.10"/><stop offset="1" stop-color="${K.CYAN}" stop-opacity="0"/>
  </radialGradient>
  ${['CYAN', 'BLEU', 'VERT', 'ROUGE', 'FIL', 'DISCRET']
    .map((c) => `<marker id="p${c}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0.8 L9.2 5 L0 9.2 Z" fill="${K[c]}"/></marker>`)
    .join('\n  ')}
</defs>
<rect width="${l}" height="${h}" rx="16" fill="${K.FOND}"/>
<rect width="${l}" height="${h}" rx="16" fill="url(#grille)"/>
<rect width="${l}" height="${h}" rx="16" fill="url(#lueur)"/>
${corps}
</svg>`;
  fs.mkdirSync(dossier, { recursive: true });
  fs.writeFileSync(path.join(dossier, nom), contenu);
  console.log(`  ${nom}  ${(contenu.length / 1024).toFixed(1)} Ko`);
  while (alertes.length) console.log(`    DÉBORDEMENT ${alertes.shift()}`);
}

// --------------------------------------------------------------- textes
const t = (x, y, s, { taille = 14, couleur = K.TEXTE, police = SANS, poids = 400, ancre = 'start', espace = 0, extra = '' } = {}) =>
  `<text x="${r3(x)}" y="${r3(y)}" font-family="${police}" font-size="${taille}" font-weight="${poids}" fill="${couleur}" text-anchor="${ancre}"${espace ? ` letter-spacing="${espace}"` : ''} ${extra}>${esc(s)}</text>`;

/// Le titre d'un schéma : une étiquette en capitales, une phrase dessous.
function entete(l, etiquette, phrase, y = 56) {
  controle(etiquette, 13, MONO, l - 80, 'étiquette', 3);
  controle(phrase, 15, SANS, l - 80, 'phrase');
  return t(l / 2, y, etiquette, { taille: 13, couleur: K.CYAN, police: MONO, ancre: 'middle', espace: 3 }) +
    t(l / 2, y + 28, phrase, { taille: 15, ancre: 'middle' });
}

// ------------------------------------------------------------ le temps
/// Une valeur qui glisse d'un palier au suivant, sur un cycle.
function fondu(attribut, cycle, etapes) {
  // Arrondis : Chrome rejette un instant comme 0.009999999999999998, et une
  // seule animation rejetée fige tout le SVG.
  const e = etapes.map(([k, v]) => [r3(Math.min(Math.max(k, 0), 1)), v]);
  for (let i = 1; i < e.length; i++) if (e[i][0] < e[i - 1][0]) e[i][0] = e[i - 1][0];
  return `<animate attributeName="${attribut}" dur="${cycle}s" repeatCount="indefinite" keyTimes="${e.map((x) => x[0]).join(';')}" values="${e.map((x) => x[1]).join(';')}"/>`;
}

/// Visible de [de] à [a] (fractions du cycle), avec un court fondu.
function visible(cycle, de, a, douceur = 0.02) {
  const e = [[0, 0]];
  if (de > douceur) e.push([de - douceur, 0]);
  e.push([de, 1], [Math.min(a, 1), 1]);
  if (a + douceur < 1) e.push([a + douceur, 0], [1, 0]);
  else if (a < 1) e.push([1, 1]);
  return fondu('opacity', cycle, e);
}
/// Un groupe qui n'apparaît que de [de] à [a].
const quand = (cycle, de, a, contenu, douceur = 0.02) => `<g opacity="0">${visible(cycle, de, a, douceur)}${contenu}</g>`;

// --------------------------------------------------------------- cartes
/// Une carte : liseré coloré, pictogramme, titre en chasse fixe, sous-titre.
/// Rend un objet qui connaît ses bords : c.ancre('g'|'d'|'h'|'b', f) donne
/// le point du bord à la fraction f (0,5 = le milieu).
function carte(x, y, l, h, titre, sous, accent, { icone = null, allume = null, cycle = 10, estompe = null, taille = 14.5 } = {}) {
  const tx = x + (icone ? 58 : 20);
  controle(titre, taille, MONO, x + l - 12 - tx, `carte ${titre}`);
  if (sous) controle(sous, 12.5, SANS, x + l - 12 - tx, `carte ${titre}`);
  const bord = allume
    ? `<rect x="${x}" y="${y}" width="${l}" height="${h}" rx="14" fill="none" stroke="${accent}" stroke-width="1.6" opacity="0" filter="url(#halo)">${visible(cycle, allume[0], allume[1])}</rect>`
    : '';
  const ty = sous ? y + h / 2 - 3 : y + h / 2 + 5;
  const svg = `<g${estompe ? '' : ''}>
  <rect x="${x}" y="${y}" width="${l}" height="${h}" rx="14" fill="${K.CARTE}" stroke="${K.BORD}"/>
  ${bord}
  <rect x="${x}" y="${y + 14}" width="3" height="${h - 28}" rx="1.5" fill="${accent}"/>
  ${icone ? `<g transform="translate(${x + 18},${y + h / 2 - 14})">${icone(accent)}</g>` : ''}
  ${t(tx, ty, titre, { taille, couleur: K.TITRE, police: MONO, poids: 700 })}
  ${sous ? t(tx, y + h / 2 + 17, sous, { taille: 12.5 }) : ''}
</g>`;
  return boite(x, y, l, h, svg);
}

/// Toute boîte rectangulaire qui a des bords où brancher des fils.
function boite(x, y, l, h, svg = '') {
  return {
    x, y, l, h, svg,
    cx: x + l / 2, cy: y + h / 2,
    ancre(cote, f = 0.5) {
      if (cote === 'g') return [x, y + h * f];
      if (cote === 'd') return [x + l, y + h * f];
      if (cote === 'h') return [x + l * f, y];
      return [x + l * f, y + h];
    },
    toString() { return svg; },
  };
}

// ------------------------------------------------------------------ fils
/// Le tracé d'un fil entre deux points.
///  droit : une ligne ;
///  coude : horizontal, vertical, horizontal (ou l'inverse avec vertical:true),
///          aux angles arrondis ;
///  courbe : une courbe en S qui part et arrive à l'horizontale (ou à la
///          verticale), pour se poser d'équerre sur les bords.
function trace([x1, y1], [x2, y2], forme = 'droit', { vertical = false, rayon = 14, milieu = 0.5 } = {}) {
  if (forme === 'droit' || (x1 === x2 && !vertical) || (y1 === y2 && vertical)) return `M ${r3(x1)} ${r3(y1)} L ${r3(x2)} ${r3(y2)}`;
  if (forme === 'courbe') {
    if (vertical) {
      const m = y1 + (y2 - y1) * milieu;
      return `M ${r3(x1)} ${r3(y1)} C ${r3(x1)} ${r3(m)} ${r3(x2)} ${r3(m)} ${r3(x2)} ${r3(y2)}`;
    }
    const m = x1 + (x2 - x1) * milieu;
    return `M ${r3(x1)} ${r3(y1)} C ${r3(m)} ${r3(y1)} ${r3(m)} ${r3(y2)} ${r3(x2)} ${r3(y2)}`;
  }
  // coude
  if (!vertical) {
    const m = x1 + (x2 - x1) * milieu;
    const sx = Math.sign(x2 - x1) || 1;
    const sy = Math.sign(y2 - y1) || 1;
    const r = Math.min(rayon, Math.abs(y2 - y1) / 2, Math.abs(m - x1));
    return `M ${r3(x1)} ${r3(y1)} H ${r3(m - sx * r)} Q ${r3(m)} ${r3(y1)} ${r3(m)} ${r3(y1 + sy * r)} V ${r3(y2 - sy * r)} Q ${r3(m)} ${r3(y2)} ${r3(m + sx * r)} ${r3(y2)} H ${r3(x2)}`;
  }
  const m = y1 + (y2 - y1) * milieu;
  const sx = Math.sign(x2 - x1) || 1;
  const sy = Math.sign(y2 - y1) || 1;
  const r = Math.min(rayon, Math.abs(x2 - x1) / 2, Math.abs(m - y1));
  return `M ${r3(x1)} ${r3(y1)} V ${r3(m - sy * r)} Q ${r3(x1)} ${r3(m)} ${r3(x1 + sx * r)} ${r3(m)} H ${r3(x2 - sx * r)} Q ${r3(x2)} ${r3(m)} ${r3(x2)} ${r3(m + sy * r)} V ${r3(y2)}`;
}

/// Un fil dessiné : pointillé qui court, ou trait plein. La pointe se pose
/// sur le bord d'arrivée ; une pastille marque le départ.
function fil(d, { couleur = 'FIL', pointe = false, court = true, plein = false, epaisseur = 2, opacite = 1, depart = true } = {}) {
  const c = K[couleur] || couleur;
  const [, x0, y0] = d.match(/M\s*([-\d.]+)\s+([-\d.]+)/);
  const trait = plein ? '' : ` stroke-dasharray="6 7"`;
  const anim = !plein && court ? `<animate attributeName="stroke-dashoffset" from="26" to="0" dur="1.2s" repeatCount="indefinite"/>` : '';
  return `<g opacity="${opacite}"><path d="${d}" fill="none" stroke="${c}" stroke-width="${epaisseur}" stroke-linecap="round"${trait}${pointe ? ` marker-end="url(#p${couleur})"` : ''}>${anim}</path>${depart ? `<circle cx="${x0}" cy="${y0}" r="3.5" fill="${K.FOND}" stroke="${c}" stroke-width="2"/>` : ''}</g>`;
}

/// Un fil qui se trace de [de] à [a], reste, puis s'efface en [fin].
function trace_anime(d, cycle, de, a, fin, { couleur = 'CYAN', epaisseur = 2.4, pointe = true, halo = true } = {}) {
  const c = K[couleur] || couleur;
  const off = fondu('stroke-dashoffset', cycle, [[0, 100], [de, 100], [a, 0], [1, 0]]);
  // Pas de filtre sur un trait : une ligne droite a une boîte de hauteur
  // nulle, et le filtre l'efface. Le halo est un second trait, large et pâle.
  const lueur = halo ? `<path d="${d}" fill="none" stroke="${c}" stroke-opacity="0.18" stroke-width="${epaisseur + 6}" stroke-linecap="round" pathLength="100" stroke-dasharray="100" stroke-dashoffset="100">${off}</path>` : '';
  // La pointe n'arrive qu'avec le trait : posée sur le tracé entier dès le
  // début, elle attendrait seule au bout.
  const bout = pointe ? quand(cycle, a - 0.005, fin, `<path d="${d}" fill="none" stroke="${c}" stroke-opacity="0" stroke-width="${epaisseur}" marker-end="url(#p${couleur})"/>`, 0.005) : '';
  return quand(cycle, de, fin, `${lueur}<path d="${d}" fill="none" stroke="${c}" stroke-width="${epaisseur}" stroke-linecap="round" pathLength="100" stroke-dasharray="100" stroke-dashoffset="100">${off}</path>`, 0.01) + bout;
}

/// Une bille lumineuse qui suit un tracé quelconque. [etapes] : couples
/// [instant, position] (fractions du cycle et du tracé). Elle n'est
/// visible que pendant son voyage, de la première à la dernière étape.
function bille(d, cycle, etapes, { couleur = 'CYAN', rayon = 6, contenu = null, toujours = false } = {}) {
  const c = K[couleur] || couleur;
  const e = etapes.map(([k, p]) => [r3(k), r3(p)]);
  const debut = e[0][0];
  const fin = e[e.length - 1][0];
  const kt = [0, ...e.map((x) => x[0]), 1];
  const kp = [e[0][1], ...e.map((x) => x[1]), e[e.length - 1][1]];
  // keyTimes doit croître strictement avec calcMode="linear" dans Chrome :
  // on écarte les instants égaux d'un millième.
  for (let i = 1; i < kt.length; i++) if (kt[i] <= kt[i - 1]) kt[i] = r3(kt[i - 1] + 0.001);
  if (kt[kt.length - 1] > 1) return bille(d, cycle, etapes.map(([k, p]) => [k * 0.99, p]), { couleur, rayon, contenu, toujours });
  kt[kt.length - 1] = 1;
  const mouvement = `<animateMotion dur="${cycle}s" repeatCount="indefinite" path="${d}" calcMode="linear" keyTimes="${kt.join(';')}" keyPoints="${kp.join(';')}"/>`;
  const forme = contenu
    ? contenu
    : `<circle r="${rayon + 5}" fill="${c}" opacity="0.22"/><circle r="${rayon}" fill="${c}"/>`;
  const vis = toujours ? '' : visible(cycle, debut, fin, 0.015);
  return `<g opacity="${toujours ? 1 : 0}">${vis}<g filter="url(#halo)">${forme}${mouvement}</g></g>`;
}

/// Une pastille de texte (étiquette sur un fil), centrée en x, y.
function pastille(x, y, s, couleur = 'CYAN', { taille = 13, fond = null, police = MONO } = {}) {
  const c = K[couleur] || couleur;
  const l = largeur(s, taille, police) + 26;
  const f = fond || { CYAN: '#0A1B22', BLEU: '#08172A', VERT: '#0B1A14', ROUGE: '#1A0D10' }[couleur] || K.CARTE2;
  return `<rect x="${r3(x - l / 2)}" y="${r3(y - 16)}" width="${r3(l)}" height="32" rx="9" fill="${f}" stroke="${c}" stroke-opacity="0.6"/>` +
    t(x, y + taille * 0.36, s, { taille, couleur: c, police, ancre: 'middle' });
}

/// Un cadre en pointillés qui regroupe des cartes (le VPS, la maison…).
function zone(x, y, l, h, titre, couleur = 'DISCRET') {
  const c = K[couleur] || couleur;
  return boite(x, y, l, h, `<rect x="${x}" y="${y}" width="${l}" height="${h}" rx="18" fill="${c}" fill-opacity="0.03" stroke="${c}" stroke-opacity="0.55" stroke-dasharray="3 6"/>
${t(x + 18, y - 10, titre, { taille: 11.5, couleur: c, police: MONO, espace: 2.5 })}`);
}

// ---------------------------------------------------------- pictogrammes
// En traits, 28 × 28.
const P = {
  telephone: (c) => `<rect x="7" y="1" width="14" height="26" rx="3.5" fill="none" stroke="${c}" stroke-width="2"/><path d="M12 23 H16" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  serveur: (c) => `<rect x="3" y="3" width="22" height="9" rx="2.5" fill="none" stroke="${c}" stroke-width="2"/><rect x="3" y="16" width="22" height="9" rx="2.5" fill="none" stroke="${c}" stroke-width="2"/><path d="M8 7.5h.01M8 20.5h.01" stroke="${c}" stroke-width="3" stroke-linecap="round"/>`,
  maison: (c) => `<path d="M4 25 V12 L14 4 L24 12 V25 M11 25 V18 H17 V25" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/>`,
  portable: (c) => `<rect x="5" y="5" width="18" height="13" rx="2" fill="none" stroke="${c}" stroke-width="2"/><path d="M2 23 H26" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  cle: (c) => `<circle cx="9" cy="18" r="5.5" fill="none" stroke="${c}" stroke-width="2"/><path d="M13 14 L24 3 M20 7 L23 10 M17 10 L19 12" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  oeil: (c) => `<path d="M2 14 C6 7 22 7 26 14 C22 21 6 21 2 14 Z" fill="none" stroke="${c}" stroke-width="2"/><circle cx="14" cy="14" r="3.5" fill="none" stroke="${c}" stroke-width="2"/>`,
  empreinte: (c) => `<path d="M5 13 A9 9 0 0 1 23 13 M9 25 C10 21 10 17 10 14 A4 4 0 0 1 18 14 C18 18 18 22 16 26 M14 14 C14 18 14 21 12 25 M22 18 C22 20 21.5 22 21 24" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  reseau: (c) => `<circle cx="14" cy="5" r="3" fill="none" stroke="${c}" stroke-width="2"/><circle cx="5" cy="22" r="3" fill="none" stroke="${c}" stroke-width="2"/><circle cx="23" cy="22" r="3" fill="none" stroke="${c}" stroke-width="2"/><path d="M12.5 7.5 L6.5 19.5 M15.5 7.5 L21.5 19.5 M8 22 H20" stroke="${c}" stroke-width="2"/>`,
  crane: (c) => `<path d="M6 16 A8 8 0 1 1 22 16 V20 H18 V24 H10 V20 H6 Z" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/><circle cx="10.5" cy="14" r="2" fill="${c}"/><circle cx="17.5" cy="14" r="2" fill="${c}"/>`,
  bouclier: (c) => `<path d="M14 2 L24 6 V13 C24 19 19.5 23.5 14 26 C8.5 23.5 4 19 4 13 V6 Z" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/><path d="M9.5 14 L12.5 17 L18.5 11" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`,
  lien: (c) => `<path d="M12 16 L16 12 M10.5 13.5 L7 17 A4 4 0 0 0 12.7 22.7 L16 19.4 M17.5 14.5 L21 11 A4 4 0 0 0 15.3 5.3 L12 8.6" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  cadenas: (c) => `<rect x="5" y="12" width="18" height="14" rx="3" fill="none" stroke="${c}" stroke-width="2"/><path d="M9 12 V8 A5 5 0 0 1 19 8 V12" fill="none" stroke="${c}" stroke-width="2"/><path d="M14 17 V21" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  google: (c) => `<path d="M24 14.3 C24 19.9 20 24 14 24 A10 10 0 1 1 20.8 6.7 L17.9 9.5 A6 6 0 1 0 19.7 16 H14 V12.3 H23.8 C23.9 12.9 24 13.6 24 14.3 Z" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/>`,
  mur: (c) => `<rect x="3" y="5" width="22" height="18" rx="2" fill="none" stroke="${c}" stroke-width="2"/><path d="M3 11 H25 M3 17 H25 M10 5 V11 M18 11 V17 M10 17 V23" stroke="${c}" stroke-width="2"/>`,
  document: (c) => `<path d="M7 2 H17 L23 8 V26 H7 Z M17 2 V8 H23" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/><path d="M11 14 H19 M11 18 H19 M11 22 H16" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  sceau: (c) => `<circle cx="14" cy="12" r="8" fill="none" stroke="${c}" stroke-width="2"/><path d="M10 12 L13 15 L18.5 9.5 M9 18.5 L7 26 L11 24 L14 27 M19 18.5 L21 26 L17 24 L14 27" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`,
  puce: (c) => `<rect x="7" y="7" width="14" height="14" rx="2.5" fill="none" stroke="${c}" stroke-width="2"/><rect x="11" y="11" width="6" height="6" rx="1" fill="${c}"/><path d="M11 3 V7 M17 3 V7 M11 21 V25 M17 21 V25 M3 11 H7 M3 17 H7 M21 11 H25 M21 17 H25" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  horloge: (c) => `<circle cx="14" cy="14" r="11" fill="none" stroke="${c}" stroke-width="2"/><path d="M14 8 V14 L18 17" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  croix: (c) => `<circle cx="14" cy="14" r="11" fill="none" stroke="${c}" stroke-width="2"/><path d="M10 10 L18 18 M18 10 L10 18" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
  onde: (c) => `<path d="M3 14 H7 L10 6 L14 22 L18 10 L21 14 H25" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`,
  utilisateur: (c) => `<circle cx="14" cy="9" r="5" fill="none" stroke="${c}" stroke-width="2"/><path d="M4 26 C4 19 9 16 14 16 C19 16 24 19 24 26" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round"/>`,
};

/// Un pictogramme posé centré en (x, y), à l'échelle [e].
const picto = (nom, x, y, couleur, e = 1) => `<g transform="translate(${r3(x - 14 * e)},${r3(y - 14 * e)}) scale(${e})">${P[nom](K[couleur] || couleur)}</g>`;

module.exports = { K, MONO, SANS, esc, r3, largeur, controle, svg, t, entete, fondu, visible, quand, carte, boite, trace, fil, trace_anime, bille, pastille, zone, P, picto };
