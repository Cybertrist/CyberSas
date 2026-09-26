// Les schémas animés du README.
//
// Des SVG plutôt que des GIF : quelques kilo-octets, nets à toute taille,
// et le texte reste du texte. La boîte à outils est dans svg.js ; les
// schémas des documents de docs/ sont dans docs.js.
//
//   node docs/tools/anime.js
//   node docs/tools/planche.js docs/schemas/relais.svg   # pour les vérifier
const path = require('path');
const S = require('./svg');
const { K, MONO, t, entete, fondu, visible, quand, carte, trace, fil, trace_anime, bille, pastille, zone, P, picto } = S;

const SORTIE = path.join(__dirname, '..', 'schemas');
const svg = (nom, l, h, corps, titre) => S.svg(SORTIE, nom, l, h, corps, titre);

/// Le point d'une courbe en S horizontale (celle de trace(…, 'courbe')) à la
/// fraction u.
function surCourbe([x1, y1], [x2, y2], u) {
  const m = (x1 + x2) / 2;
  const b = (a, c1, c2, d) => (1 - u) ** 3 * a + 3 * (1 - u) ** 2 * u * c1 + 3 * (1 - u) * u * u * c2 + u ** 3 * d;
  return [b(x1, m, m, x2), b(y1, y1, y2, y2)];
}

/// Le paquet du relais : une enveloppe (la session avec le serveur) autour
/// d'une autre (la session de bout en bout), fermée par un cadenas.
function enveloppe(exterieur, { ouverte = false } = {}) {
  const c = K[exterieur];
  return `<rect x="-34" y="-21" width="68" height="42" rx="9" fill="${K.FOND}" stroke="${c}" stroke-width="2"${ouverte ? ' stroke-dasharray="4 5"' : ''}/>
<rect x="-19" y="-12" width="38" height="24" rx="6" fill="#0A2A33" stroke="${K.CYAN}" stroke-width="1.8"/>
<g transform="translate(-7,-8) scale(0.5)">${P.cadenas(K.CYAN)}</g>`;
}

// ------------------------------------------------------------ 1. le tunnel
// Les tracés du logo, ceux que l'appli anime sur son accueil
// (mobile/lib/dessins.dart). Il s'allume couche par couche, les paquets
// entrent, puis il s'éteint dans l'ordre inverse. L'état, à droite, suit
// le dessin : un seul mot à la fois, jamais deux qui se chevauchent.
{
  const C = 12;
  const T = {
    maison: 'M69 205 V98 Q69 86 80 80 L137 50 Q144 46 151 50 L208 80 Q219 86 219 98 V205',
    arche1: 'M97 200 V137 A47 47 0 0 1 191 137 V200',
    arche2: 'M124 190 V140 A20 20 0 0 1 164 140 V190',
    porte: 'M129 160 V141 A15 15 0 0 1 159 141 V160 Z',
    sol: 'M121 159.5 L167 159.5 L330 250 L330 330 L-42 330 L-42 250 Z',
    bords: 'M121 159.5 L-42 250 M167 159.5 L330 250',
    cables: ['M34 252 C62 236 84 222 98 200 L134 160', 'M144 290 L144 160', 'M254 252 C226 236 204 222 190 200 L154 160'],
  };
  const couche = (a, b, contenu) =>
    `<g opacity="0">${fondu('opacity', C, [[0, 0], [a, 0], [a + 0.05, 1], [b, 1], [b + 0.05, 0], [1, 0]])}${contenu}</g>`;
  const trait = (d, larg, grad) => `<path d="${d}" fill="none" stroke="url(#${grad})" stroke-width="${larg}" stroke-linejoin="round"/>`;
  const fantome = `<g opacity="0.22">
    <path d="${T.sol}" fill="#161D24"/>
    <path d="${T.maison}" fill="none" stroke="#1A3440" stroke-width="16" stroke-linejoin="round"/>
    <path d="${T.arche1}" fill="none" stroke="#15303B" stroke-width="11"/>
    <path d="${T.arche2}" fill="none" stroke="#122833" stroke-width="10"/>
    <path d="${T.porte}" fill="#1D3F4B"/>
  </g>`;
  // Le tiret dépasse le tracé de 5 à chaque bout : sinon son bout arrondi
  // laisse un point lumineux devant la porte, tunnel coupé.
  const cable = [[0, 105], [0.3, 105], [0.4, 0], [0.8, 0], [0.88, -105], [1, -105]];
  const cables = T.cables
    .map((d) => `<path d="${d}" fill="none" stroke="${K.CYAN}" stroke-opacity="0.35" stroke-width="7" stroke-linecap="round" filter="url(#flou)" pathLength="100" stroke-dasharray="100 110" stroke-dashoffset="105">${fondu('stroke-dashoffset', C, cable)}</path>
<path d="${d}" fill="none" stroke="url(#gCable)" stroke-width="3.6" stroke-linecap="round" pathLength="100" stroke-dasharray="100 110" stroke-dashoffset="105">${fondu('stroke-dashoffset', C, cable)}</path>`)
    .join('\n');
  // Les paquets n'existent que tunnel ouvert : on les masque d'un bloc.
  const paquets = T.cables
    .map((d, i) => `<ellipse rx="10" ry="7.5" fill="#6FF1FF" stroke="#A8F8FF" stroke-width="1.6" filter="url(#halo)">
    <animateMotion dur="3s" begin="${i}s" repeatCount="indefinite" path="${d}" keyPoints="0;1" keyTimes="0;1" calcMode="spline" keySplines="0.25 0.1 0.6 1"/>
    <animateTransform attributeName="transform" type="scale" dur="3s" begin="${i}s" repeatCount="indefinite" values="1.1;0.3" additive="sum"/>
  </ellipse>`)
    .join('\n');
  // Un mot d'état visible de [de] à [a] ; les fondus ne se recouvrent pas.
  const etat = (mot, couleur, e) => `<g opacity="${e[0][1]}">${fondu('opacity', C, e)}${t(1200, 188, mot, { taille: 26, couleur, poids: 600, ancre: 'end' })}</g>`;
  const plage = (de, a) => [[0, 0], [de - 0.012, 0], [de, 1], [a, 1], [a + 0.012, 0], [1, 0]];
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
  ${couche(0.02, 0.93, `<ellipse cx="144" cy="120" rx="160" ry="120" fill="url(#gCiel)"/><path d="${T.sol}" fill="url(#gSol)"/><path d="${T.bords}" fill="none" stroke="${K.CYAN}" stroke-opacity="0.3" stroke-width="1.2"/>`)}
  ${couche(0.07, 0.9, trait(T.arche2, 10, 'gA2'))}
  ${couche(0.12, 0.87, trait(T.arche1, 11, 'gA1'))}
  ${couche(0.17, 0.84, `<path d="${T.maison}" fill="none" stroke="${K.CYAN}" stroke-opacity="0.3" stroke-width="22" stroke-linejoin="round" filter="url(#flou)"/>${trait(T.maison, 16, 'gMaison')}`)}
  ${couche(0.02, 0.93, `<path d="${T.porte}" fill="#5FF0FF" filter="url(#flou)"/><path d="${T.porte}" fill="url(#gPorte)"/>`)}
  ${cables}
  ${couche(0.42, 0.76, paquets)}
</g>
${t(80, 150, 'LE TUNNEL', { taille: 12, couleur: K.CYAN, police: MONO, espace: 3 })}
${t(80, 184, 'Noise IK, puis', { taille: 22, couleur: K.TITRE, poids: 600 })}
${t(80, 214, 'ChaCha20-Poly1305', { taille: 22, couleur: K.TITRE, poids: 600 })}
${t(80, 248, 'Clés renouvelées toutes les deux minutes,', { taille: 14 })}
${t(80, 270, 'rejeu et inondation refusés.', { taille: 14 })}
${t(1200, 150, 'ÉTAT', { taille: 12, couleur: K.DISCRET, police: MONO, ancre: 'end', espace: 3 })}
${etat('Coupé', K.DISCRET, [[0, 1], [0.02, 1], [0.032, 0], [0.974, 0], [0.986, 1], [1, 1]])}
${etat('Connexion…', K.TEXTE, plage(0.044, 0.39))}
${etat('Connecté', K.CYAN, plage(0.402, 0.8))}
${etat('Coupure…', K.TEXTE, plage(0.812, 0.962))}
${t(1200, 218, '10.77.0.18 → 10.77.0.2', { taille: 14, police: MONO, ancre: 'end' })}`;
  svg('tunnel.svg', 1280, 400, corps, "Le tunnel du logo de CyberSas, animé comme dans l'appli : il s'allume couche par couche, les paquets entrent, puis il s'éteint. À gauche : Noise IK, puis ChaCha20-Poly1305, clés renouvelées toutes les deux minutes. À droite, l'état : coupé, connexion, connecté, coupure.");
}

// ------------------------------------------------------------ 2. le relais
// Deux enveloppes l'une dans l'autre. L'extérieure est la session avec le
// serveur : il l'ouvre, lit le numéro du destinataire, et en referme une
// autre pour la maison. L'intérieure, la session de bout en bout, arrive
// fermée : il n'en a pas la clé.
{
  const C = 9;
  const y = 136;
  const tel = carte(40, y, 270, 76, 'fold8-tristan', '10.77.0.18 · le téléphone', K.CYAN, { icone: P.telephone, allume: [0.02, 0.34], cycle: C });
  const srv = carte(505, y, 270, 76, 'sasd', 'le serveur, qui relaie', K.BLEU, { icone: P.serveur, allume: [0.3, 0.64], cycle: C });
  const mai = carte(970, y, 270, 76, 'maison', '10.77.0.2 · à la maison', K.VERT, { icone: P.maison, allume: [0.6, 0.95], cycle: C });
  const aller = trace(tel.ancre('d'), srv.ancre('g'));
  const suite = trace(srv.ancre('d'), mai.ancre('g'));
  // Les enveloppes roulent sur le fil sans jamais mordre sur une carte.
  const x1 = tel.x + tel.l + 40, x2 = srv.x - 40, x3 = srv.x + srv.l + 40, x4 = mai.x - 40;
  const cy = tel.cy;
  const bulle = (c, titre, lignes, couleur, de, a) => {
    const x = c.cx - 150, yb = y + 128;
    return quand(C, de, a, `<path d="M ${c.cx} ${c.y + c.h} V ${yb}" stroke="${couleur}" stroke-opacity="0.5" stroke-width="1.5" stroke-dasharray="3 4"/>
  <rect x="${x}" y="${yb}" width="300" height="${40 + lignes.length * 22}" rx="12" fill="${K.CARTE2}" stroke="${couleur}" stroke-opacity="0.45"/>
  ${t(x + 18, yb + 26, titre, { taille: 11.5, couleur, police: MONO, espace: 2 })}
  ${lignes.map(([l, c2], i) => t(x + 18, yb + 54 + i * 22, l, { taille: 14, couleur: c2 || K.TITRE, police: MONO })).join('')}`, 0.03);
  };
  const corps = `
${entete(1280, 'LE SERVEUR RELAIE CE QU’IL NE PEUT PAS LIRE', 'Deux enveloppes : il ouvre celle qui lui est adressée, jamais celle de bout en bout.')}
${fil(aller)}${fil(suite)}
${tel}${srv}${mai}
${bille(`M ${x1} ${cy} H ${x2}`, C, [[0.06, 0], [0.28, 1]], { contenu: enveloppe('BLEU') })}
${bille(`M ${x2} ${cy} H ${x2}`, C, [[0.28, 0], [0.33, 0]], { contenu: enveloppe('BLEU', { ouverte: true }) })}
${bille(`M ${x3} ${cy} H ${x4}`, C, [[0.4, 0], [0.62, 1]], { contenu: enveloppe('VERT') })}
${bulle(tel, 'EN CLAIR, SUR LE TÉLÉPHONE', [['GET / HTTP/1.1'], ['Host: maison.sas.internal']], K.CYAN, 0.02, 0.34)}
${bulle(srv, 'CE QUE LIT LE SERVEUR', [['relayer vers l’appareil n°2', K.BLEU], ['7f 3a 9c e1 0b 52 d4 88 …', K.ROUGE]], K.BLEU, 0.3, 0.64)}
${bulle(mai, 'DÉCHIFFRÉ, À LA MAISON', [['GET / HTTP/1.1'], ['Host: maison.sas.internal']], K.VERT, 0.6, 0.95)}
<g transform="translate(0,400)">
  <rect x="330" y="-12" width="30" height="20" rx="5" fill="none" stroke="${K.BLEU}" stroke-width="2"/>
  ${t(372, 3, 'la session avec le serveur, une par appareil', { taille: 13 })}
  <rect x="712" y="-12" width="30" height="20" rx="5" fill="#0A2A33" stroke="${K.CYAN}" stroke-width="1.8"/>
  ${t(754, 3, 'la session de bout en bout, téléphone ↔ maison', { taille: 13 })}
</g>`;
  svg('relais.svg', 1280, 440, corps, "Un paquet part du téléphone fold8-tristan, en clair : GET / HTTP/1.1. Il voyage dans deux enveloppes. Le serveur sasd ouvre l'extérieure, la sienne, et n'y lit que le numéro du destinataire ; l'intérieure, la session de bout en bout, reste fermée : il n'en voit que des octets chiffrés. Il la remet dans une nouvelle enveloppe pour la maison, qui la déchiffre.");
}

// -------------------------------------------------------- 3. l'inscription
// Le vrai parcours, tel que l'appli le fait : un diagramme de séquence à
// trois colonnes, qui se déroule message après message.
{
  const C = 20;
  const cols = { app: 210, srv: 640, adm: 1070 };
  const haut = 128;
  const tetes = [
    carte(cols.app - 140, haut, 280, 70, 'nouvel appareil', 'le portable d’Alice', K.CYAN, { icone: P.portable }),
    carte(cols.srv - 140, haut, 280, 70, 'sasd', 'le serveur', K.BLEU, { icone: P.serveur }),
    carte(cols.adm - 140, haut, 280, 70, 'fold8-tristan', 'le téléphone de l’admin', K.VERT, { icone: P.telephone }),
  ];
  const y0 = haut + 118;
  const pas = 50;
  // [de, vers, texte, couleur] ; de === vers : une action sur place.
  const etapes = [
    ['adm', 'srv', 'Créer l’invitation · alice@gmail.com, 1 h', 'VERT'],
    ['srv', 'adm', 'une clé d’inscription, à usage unique', 'BLEU'],
    ['adm', 'app', 'le lien cybersas:// · serveur, clé, clé du verrou', 'VERT'],
    ['app', 'app', 'crée sa paire de clés : la privée ne sort pas', 'CYAN', P.cle],
    ['app', 'srv', 'inscription + preuve de possession', 'CYAN'],
    ['srv', 'adm', 'une demande · empreinte Qm7X-tR2k-9vLp', 'BLEU'],
    ['adm', 'adm', 'compare l’empreinte, signe au doigt', 'VERT', P.empreinte],
    ['adm', 'srv', 'le certificat, signé par le verrou', 'VERT'],
    ['srv', 'app', 'le réseau et les certificats', 'BLEU'],
    ['app', 'app', 'dans le réseau · 10.77.0.3 · 90 jours', 'VERT', P.reseau],
  ];
  const fin = 0.93;
  const tranche = 0.86 / etapes.length;
  const lignes = Object.values(cols)
    .map((x) => `<path d="M ${x} ${haut + 70} V ${y0 + etapes.length * pas - 10}" stroke="${K.FIL}" stroke-width="2" stroke-dasharray="4 6"/>`)
    .join('');
  const messages = etapes
    .map(([de, vers, texte, couleur, ic], i) => {
      const y = y0 + i * pas;
      const a = 0.03 + i * tranche;
      // Chaque étape existe en fantôme dès la première image, et s'allume
      // à son tour : le schéma se lit à tout instant.
      const num = t(26, y + 5, String(i + 1).padStart(2, '0'), { taille: 12, couleur: K.DISCRET, police: MONO }) +
        quand(C, a, fin, t(26, y + 5, String(i + 1).padStart(2, '0'), { taille: 12, couleur: K[couleur], police: MONO }), 0.012);
      if (de === vers) {
        // Une action sur place : une boîte posée sur la ligne de vie.
        const x = cols[de];
        const l = S.largeur(texte, 13.5) + 64;
        const bx = Math.min(Math.max(x - l / 2, 48), 1240 - l);
        S.controle(texte, 13.5, S.SANS, l - 58, `étape ${i + 1}`);
        const boiteAction = (bord, encre, opac) => `<rect x="${bx}" y="${y - 17}" width="${l}" height="34" rx="10" fill="${K.CARTE}" stroke="${bord}" stroke-opacity="${opac}"/>
  ${picto(ic.name, bx + 22, y, bord, 0.66)}
  ${t(bx + 42, y + 5, texte, { taille: 13.5, couleur: encre })}`;
        return num + boiteAction(K.FIL, K.DISCRET, 1) + quand(C, a, fin, boiteAction(K[couleur], K.TITRE, 0.7), 0.012);
      }
      const x1 = cols[de], x2 = cols[vers];
      const sg = Math.sign(x2 - x1);
      const d = `M ${x1 + sg * 8} ${y} H ${x2 - sg * 8}`;
      const lx = (x1 + x2) / 2;
      const lp = S.largeur(texte, 12.5, MONO) + 26;
      S.controle(texte, 12.5, MONO, Math.abs(x2 - x1) - 40, `étape ${i + 1}`);
      const etiquette = (encre) => `<rect x="${lx - lp / 2}" y="${y - 29}" width="${lp}" height="22" rx="7" fill="${K.FOND}"/>${t(lx, y - 13, texte, { taille: 12.5, couleur: encre, police: MONO, ancre: 'middle' })}`;
      return num +
        `<circle cx="${x1}" cy="${y}" r="4" fill="${K.FIL}"/>` +
        quand(C, a, fin, `<circle cx="${x1}" cy="${y}" r="5" fill="${K[couleur]}"/>`, 0.012) +
        trace_anime(d, C, a, a + tranche * 0.55, fin, { couleur }) +
        etiquette(K.DISCRET) +
        quand(C, a + tranche * 0.3, fin, etiquette(K.TITRE), 0.012);
    })
    .join('\n');
  const h = y0 + etapes.length * pas + 10;
  const corps = `
${entete(1280, 'UN NOUVEL APPAREIL, DE L’INVITATION AU RÉSEAU', 'La clé privée ne quitte jamais l’appareil. L’admin compare l’empreinte, puis signe avec son doigt.')}
${lignes}
${tetes.join('')}
${messages}`;
  svg('inscription.svg', 1280, h, corps, "Un nouvel appareil rejoint le réseau, en dix messages entre trois acteurs : le nouvel appareil, le serveur sasd et le téléphone de l'admin. 01 l'admin crée une invitation pour alice@gmail.com, valable une heure ; 02 le serveur rend une clé d'inscription à usage unique ; 03 l'admin envoie le lien cybersas:// avec le serveur, la clé et la clé du verrou ; 04 l'appareil crée sa paire de clés, la privée ne sort pas ; 05 il s'inscrit avec une preuve de possession ; 06 le serveur présente la demande à l'admin avec l'empreinte Qm7X-tR2k-9vLp ; 07 l'admin compare l'empreinte et signe au doigt ; 08 le certificat signé part au serveur ; 09 le serveur donne le réseau et les certificats à l'appareil ; 10 l'appareil est dans le réseau, en 10.77.0.3, pour 90 jours.");
}

// -------------------------------------------------------- 4. le verrou
// Un serveur piraté présente un intrus : sans signature du verrou, le
// téléphone le refuse. Un appareil signé, lui, passe. Les deux fils
// arrivent sur le bord du téléphone.
{
  const C = 9;
  const y = 128;
  const intrus = carte(60, y, 280, 76, 'intrus', 'glissé par le serveur', K.ROUGE, { icone: P.crane, allume: [0.05, 0.46], cycle: C });
  const lea = carte(60, y + 120, 280, 76, 'laptop-lea', 'signé par le verrou', K.VERT, { icone: P.portable, allume: [0.5, 0.93], cycle: C });
  const tel = carte(930, y + 60, 290, 76, 'fold8-tristan', 'vérifie la signature', K.CYAN, { icone: P.bouclier, allume: [0.05, 0.93], cycle: C });
  const a1 = intrus.ancre('d'), b1 = tel.ancre('g', 0.3);
  const a2 = lea.ancre('d'), b2 = tel.ancre('g', 0.7);
  const d1 = trace(a1, b1, 'courbe');
  const d2 = trace(a2, b2, 'courbe');
  const [px1, py1] = surCourbe(a1, b1, 0.5);
  const [px2, py2] = surCourbe(a2, b2, 0.5);
  const corps = `
${entete(1280, 'UN SERVEUR PIRATÉ NE FAIT ENTRER PERSONNE', 'Chaque appareil vérifie lui-même le certificat de l’autre, signé par la clé du verrou.')}
${fil(d1, { pointe: true })}${fil(d2, { pointe: true })}
${intrus}${lea}${tel}
${bille(d1, C, [[0.06, 0], [0.3, 0.97]], { couleur: 'ROUGE', rayon: 5 })}
${quand(C, 0.3, 0.46, `${picto('croix', b1[0] - 26, b1[1], 'ROUGE', 0.8)}${pastille(tel.cx, tel.y + tel.h + 34, 'refusé · pas de signature du verrou', 'ROUGE')}`)}
${bille(d2, C, [[0.5, 0], [0.74, 1]], { couleur: 'VERT', rayon: 5 })}
${quand(C, 0.74, 0.93, `<rect x="${tel.x}" y="${tel.y}" width="${tel.l}" height="${tel.h}" rx="14" fill="none" stroke="${K.VERT}" stroke-width="1.6" filter="url(#halo)"/>${pastille(tel.cx, tel.y + tel.h + 34, 'accepté · signé par le verrou', 'VERT')}`)}`;
  svg('verrou.svg', 1280, 360, corps, "Un serveur piraté glisse un intrus dans le réseau : le téléphone fold8-tristan vérifie le certificat, ne trouve pas de signature du verrou, et le refuse. L'ordinateur laptop-lea, signé par le verrou, est accepté.");
}

// -------------------------------------------------- 5. l'architecture
// Qui parle à qui : le VPS au milieu, les appareils autour, Google à part.
// Tous les tunnels sortent vers le VPS, la maison comprise : elle n'ouvre
// aucun port.
{
  const C = 10;
  const vps = zone(430, 140, 420, 356, 'LE VPS, SEUL POINT PUBLIC', 'BLEU');
  const sd = carte(470, 190, 340, 84, 'sasd', 'tunnel, relais, API, pare-feu, DNS', K.BLEU, { icone: P.serveur, allume: [0.1, 0.9], cycle: C });
  const ng = carte(470, 300, 340, 70, 'Nginx', '443 · vpn. auth. maison.', K.BLEU, { icone: P.mur });
  const op = carte(470, 396, 340, 70, 'oauth2-proxy', 'la connexion Google des pages', K.BLEU, { icone: P.cadenas });
  const tel = carte(40, 190, 290, 76, 'fold8-tristan', 'l’appli Android', K.CYAN, { icone: P.telephone, allume: [0.04, 0.3], cycle: C });
  const lap = carte(40, 330, 290, 76, 'laptop-lea', 'le client sas, Linux', K.CYAN, { icone: P.portable });
  const maisonZ = zone(950, 140, 290, 200, 'LA MAISON', 'VERT');
  const mai = carte(970, 194, 250, 76, 'maison', 'aucun port ouvert', K.VERT, { icone: P.maison, allume: [0.5, 0.76], cycle: C });
  const ggl = carte(970, 396, 250, 70, 'Google', 'le compte, le jeton', K.DISCRET, { icone: P.google });
  const d1 = trace(tel.ancre('d'), sd.ancre('g', 0.35), 'courbe');
  const d2 = trace(lap.ancre('d'), sd.ancre('g', 0.7), 'courbe');
  const d3 = trace(mai.ancre('g'), sd.ancre('d', 0.5), 'courbe');
  const d4 = `M ${ng.cx} ${ng.y} V ${sd.y + sd.h}`;
  const d5 = `M ${op.cx} ${op.y} V ${ng.y + ng.h}`;
  const d6 = trace(op.ancre('d'), ggl.ancre('g'));
  // Le chemin de bout en bout, par le relais : téléphone, sasd, maison.
  const x1 = tel.x + tel.l, x3 = mai.x;
  const cheminPaquet = `M ${x1} ${tel.cy - 12} C ${(x1 + sd.x) / 2} ${tel.cy - 12} ${(x1 + sd.x) / 2} ${sd.y + sd.h * 0.35} ${sd.x} ${sd.y + sd.h * 0.35} H ${sd.x + sd.l} C ${(sd.x + sd.l + x3) / 2} ${sd.cy} ${(sd.x + sd.l + x3) / 2} ${mai.cy} ${x3} ${mai.cy}`;
  const corps = `
${entete(1280, 'CE QU’IL Y A DEDANS, ET QUI PARLE À QUI', 'Tous les tunnels sortent vers le VPS, la maison comprise : elle n’a aucun port ouvert.')}
${vps}${maisonZ}
${fil(d1, { couleur: 'CYAN', pointe: true })}${fil(d2, { couleur: 'CYAN', pointe: true })}${fil(d3, { couleur: 'VERT', pointe: true })}
${fil(d4, { plein: true, couleur: 'BLEU', opacite: 0.6 })}${fil(d5, { plein: true, couleur: 'BLEU', opacite: 0.6 })}${fil(d6, { couleur: 'DISCRET', pointe: true })}
${sd}${ng}${op}${tel}${lap}${mai}${ggl}
${pastille(tel.cx, tel.y - 26, 'UDP 51820, vers le VPS', 'CYAN', { taille: 12 })}
${pastille(mai.cx, mai.y + mai.h + 30, 'sort vers le VPS', 'VERT', { taille: 12 })}
${t(ng.cx + 10, (sd.y + sd.h + ng.y) / 2 + 4, '127.0.0.1', { taille: 11.5, couleur: K.DISCRET, police: MONO })}
${bille(cheminPaquet, C, [[0.06, 0], [0.62, 1]], { contenu: `<circle r="11" fill="${K.CYAN}" opacity="0.2"/><g transform="translate(-7,-7) scale(0.5)">${P.cadenas(K.CYAN)}</g>` })}
${quand(C, 0.3, 0.62, pastille(sd.cx, sd.y - 20, 'relayé, chiffré de bout en bout', 'CYAN', { taille: 12 }))}
${t(640, 540, 'Nginx publie un service de la maison sur une page web, derrière la même connexion Google. Le serveur ne signe jamais rien.', { taille: 13.5, ancre: 'middle' })}`;
  svg('architecture.svg', 1280, 570, corps, "L'architecture. Au milieu, le VPS, seul point public : sasd (tunnel, relais, API, pare-feu, DNS), Nginx sur le port 443 pour vpn., auth. et maison., et oauth2-proxy pour la connexion Google des pages. À gauche, le téléphone fold8-tristan avec l'appli Android et laptop-lea avec le client sas ouvrent leur tunnel vers sasd en UDP 51820. À droite, la maison sort elle aussi vers le VPS : aucun port ouvert chez elle. Un paquet du téléphone vers la maison est relayé par sasd, chiffré de bout en bout. oauth2-proxy parle à Google.");
}

// --------------------------------------------------- 6. la révocation
// L'admin révoque un appareil depuis son téléphone : la liste signée
// passe par le serveur, qui la vérifie sans pouvoir la changer, et chaque
// appareil coupe l'appareil révoqué.
{
  const C = 12;
  const adm = carte(40, 236, 290, 84, 'fold8-tristan', 'Révoquer portable-test', K.VERT, { icone: P.empreinte, allume: [0.03, 0.34], cycle: C });
  const srv = carte(490, 236, 300, 84, 'sasd', 'vérifie, garde, transmet', K.BLEU, { icone: P.serveur, allume: [0.32, 0.56], cycle: C });
  const cibles = [
    carte(950, 120, 290, 72, 'maison', '10.77.0.2', K.VERT, { icone: P.maison }),
    carte(950, 242, 290, 72, 'laptop-lea', '10.77.0.5', K.VERT, { icone: P.portable }),
  ];
  const rev = carte(950, 364, 290, 72, 'portable-test', '10.77.0.9', K.ROUGE, { icone: P.portable, allume: [0.66, 0.93], cycle: C });
  const dA = trace(adm.ancre('d'), srv.ancre('g'));
  const dCibles = cibles.map((c) => trace(srv.ancre('d'), c.ancre('g'), 'courbe'));
  const dRev = trace(srv.ancre('d'), rev.ancre('g'), 'courbe');
  const doc = `<rect x="-26" y="-18" width="52" height="36" rx="7" fill="${K.FOND}" stroke="${K.VERT}" stroke-width="2"/>${t(0, 5, 'v4', { taille: 13, couleur: K.VERT, police: MONO, poids: 700, ancre: 'middle' })}`;
  const corps = `
${entete(1280, 'RÉVOQUER UN APPAREIL DEPUIS L’APPLI', 'La liste est signée sur le téléphone de l’admin. Le serveur la transmet, sans pouvoir la changer ni la faire reculer.')}
${fil(dA, { couleur: 'VERT', pointe: true })}
${dCibles.map((d) => fil(d, { couleur: 'BLEU', pointe: true })).join('')}
${fil(dRev, { couleur: 'BLEU', pointe: true })}
${adm}${srv}${cibles.join('')}${rev}
${quand(C, 0.03, 0.2, pastille(adm.cx, adm.y - 26, 'empreinte reconnue', 'VERT', { taille: 12 }))}
${quand(C, 0.12, 0.93, pastille(adm.cx, adm.y + adm.h + 28, 'liste v4, signée par le verrou', 'VERT', { taille: 12 }))}
${bille(`M ${adm.x + adm.l + 34} ${adm.cy} H ${srv.x - 34}`, C, [[0.14, 0], [0.32, 1]], { contenu: doc })}
${quand(C, 0.34, 0.93, pastille(srv.cx, srv.y - 26, 'signature juste · v4 > v3', 'BLEU', { taille: 12 }))}
${quand(C, 0.4, 0.93, pastille(srv.cx, srv.y + srv.h + 28, 'revocations.json', 'BLEU', { taille: 12 }))}
${dCibles.map((d) => bille(d, C, [[0.46, 0], [0.62, 1]], { couleur: 'BLEU', rayon: 5 })).join('')}
${bille(dRev, C, [[0.46, 0], [0.62, 1]], { couleur: 'BLEU', rayon: 5 })}
${cibles.map((c) => quand(C, 0.62, 0.93, pastille(c.x + c.l - 64, c.y, 'v4 retenue', 'VERT', { taille: 11.5 }))).join('')}
${quand(C, 0.66, 0.93, `<path d="${dRev}" fill="none" stroke="${K.ROUGE}" stroke-width="2.4" marker-end="url(#pROUGE)"/>${pastille(rev.x + rev.l - 58, rev.y, 'coupé', 'ROUGE', { taille: 11.5 })}`)}
${t(640, 486, 'Les appareils gardent la plus récente vue, et n’acceptent jamais d’en revenir à une plus ancienne.', { taille: 13.5, ancre: 'middle' })}`;
  svg('revocation.svg', 1280, 516, corps, "Révoquer un appareil depuis l'appli. Sur son téléphone fold8-tristan, l'admin touche Révoquer portable-test ; après son empreinte, le téléphone signe la liste de révocation v4 avec la clé du verrou. Le serveur sasd vérifie la signature et que v4 est plus récente que v3, la garde dans revocations.json et la transmet. La maison et laptop-lea retiennent la v4 ; portable-test est coupé. Les appareils n'acceptent jamais une liste plus ancienne.");
}
