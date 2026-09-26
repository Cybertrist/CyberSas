// Les fiches de l'audit : chaque constat de docs/audit.md devient une carte
// dessinée (numéro, gravité, sort, ce qui a été fait, son test), rangée en
// planche sous le bandeau de sa section. Le texte détaillé reste dans la
// page, repliable sous la planche. Le texte s'écrit dans
// docs/tools/audit.source.md ; ce script en tire docs/audit.md.
//
//   node docs/tools/audit.js && bash docs/tools/audit.sh
const fs = require('fs');
const path = require('path');

const DOCS = path.join(__dirname, '..');
const FICHIER = path.join(DOCS, 'audit.md');
const HTML = path.join(__dirname, 'html');
fs.mkdirSync(HTML, { recursive: true });

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
/// Le Markdown d'une ligne en HTML : gras, code, liens réduits à leur texte.
const enLigne = (s) => esc(s).replace(/(d) (d{3})/g, '$1&nbsp;$2')
  .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
  .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
  .replace(/`([^`]+)`/g, '<code>$1</code>')
  .replace(/\*([^*]+)\*/g, '$1');
// Une sous-liste « - a ; - b » devient la phrase « a ; b ».
const nu = (s) => s.replace(/\n\s*- /g, ' ').replace(/^\s*- /, '').replace(/\*\*|`|\*/g, '').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').trim();
/// La première phrase (ou deux si la première est courte).
// Jamais coupée au milieu : une phrase entière, qui commence par une
// capitale et finit par un point.
function phrase(s) {
  const t = s.replace(/\s+/g, ' ').trim();
  if (!t) return '';
  // Une fin de phrase : un point suivi d'un espace et d'une capitale, pas
  // le point d'un nom de fichier comme revocations.json.
  const m = t.match(/^(.+?[.!?])(?=\s+[A-ZÀ-Ý«]|$)/);
  let r = m ? m[1] : t;
  if (r.length < 70 && m) {
    const suite = t.slice(r.length).trim().match(/^(.+?[.!?])(?=\s+[A-ZÀ-Ý«]|$)/);
    if (suite) r += ' ' + suite[1];
  }
  // Le sort, déjà dit par la pastille, ne se répète pas dans le texte.
  r = r.replace(/\s*(Accepté|Corrigé)\.?$/, '').replace(/\s*[;:,]$/, '.').replace(/\s+\.$/, '.');
  if (!/[.!?»)]$/.test(r)) r += '.';
  // Une majuscule au début, et après chaque point.
  r = r.replace(/([.!?]) ([a-zà-ý])/g, (_, p, c) => `${p} ${c.toUpperCase()}`);
  return r.charAt(0).toUpperCase() + r.slice(1);
}

// ------------------------------------------------------------ la lecture
let md = fs.readFileSync(path.join(__dirname, 'audit.source.md'), 'utf8').replace(/\r\n/g, '\n');
// Ce que ce script a ajouté la dernière fois : on le retire avant de relire.
md = md
  .replace(/\n<img src="schemas\/audit\/fiches-[^\n]*\n/g, '\n')
  .replace(/\n<details>\n<summary>[^\n]*<\/summary>\n/g, '\n')
  .replace(/\n<\/details>\n/g, '\n')
  .replace(/\n{3,}/g, '\n\n');

// Les sections : chacune commence par son ancre et son bandeau.
const morceaux = md.split(/(?=<a name="[^"]+"><\/a>\n<img src="sections\/audit\/)/);
const tete = morceaux.shift();

/// Les puces de premier niveau d'un texte, continuation comprise.
function puces(texte) {
  const r = [];
  for (const l of texte.split('\n')) {
    if (/^- /.test(l)) r.push(l.slice(2));
    else if (/^\s+\S/.test(l) && r.length) r[r.length - 1] += '\n' + l;
  }
  return r;
}

/// Une fiche à partir d'un bloc « ### » qui porte une gravité.
function ficheConstat(titre, corps) {
  const m = titre.match(/^([A-Z]\d+)\.\s*(.*)$/);
  const champ = (nom) => {
    const p = puces(corps).find((x) => x.startsWith(`**${nom}**`));
    return p ? p.replace(`**${nom}**`, '').replace(/^\s*:\s*/, '') : '';
  };
  const gravite = nu(champ('Gravité')).split('.')[0].toLowerCase();
  const correction = champ('Correction') || champ('Corrections');
  const tests = [...(champ('Test') + ' ' + champ('Tests')).matchAll(/`((?:Test|Fuzz)\w+)`/g)].map((x) => x[1]);
  const accepte = !correction && /accept/i.test(corps);
  return {
    id: m ? m[1] : '', titre: m ? m[2] : titre, gravite,
    sort: accepte ? 'accepté' : 'corrigé',
    // Sans correction écrite (T7), le test en tient lieu.
    // Une correction trop courte pour se comprendre seule (« les dossiers
    // sont montés ») est précédée du problème qu'elle règle.
    texte: !correction && !champ('Le problème') ? 'Corrigé, et couvert par son test.'
      : correction && nu(correction).length < 70 && champ('Le problème')
        ? `${phrase(nu(champ('Le problème')))} **Correction** : ${phrase(nu(correction)).replace(/^./, (c) => c.toLowerCase())}`
        : phrase(nu(correction || champ('Le problème'))),
    tests,
  };
}

/// Des fiches à partir d'une liste « - **Titre** texte ».
function fichesListe(corps, { gravite, sort = null, ids = true }) {
  return puces(corps).map((p) => {
    const plat = p.replace(/\s*\n\s*-\s+/g, ' ').replace(/\s*\n\s*/g, ' ');
    const b = plat.match(/^\*\*(.+?)\*\*\s*(.*)$/);
    let titre = b ? b[1] : phrase(nu(plat), 80);
    let reste = b ? b[2] : '';
    let id = '';
    const m = titre.match(/^([A-Z]\d+)\.\s*(.*)$/);
    if (ids && m) { id = m[1]; titre = m[2]; }
    titre = nu(titre).replace(/[.:]$/, '');
    reste = reste.replace(/^[,:.]\s*/, '');
    let s = sort;
    if (!s) s = /Accepté/.test(plat) ? 'accepté' : /Corrigé|corrigé|maintenant|désormais|[Mm]ise à jour/.test(plat) ? 'corrigé' : '';
    const tests = [...plat.matchAll(/`((?:Test|Fuzz)\w+)`/g)].map((x) => x[1]);
    // L'outil qui l'a trouvé, « (gosec G115) », devient une étiquette.
    const outil = reste.match(/^\(([^)]+)\)\s*[.:]?\s*/);
    if (outil) reste = reste.slice(outil[0].length);
    let texte = phrase(nu(reste.replace(/Test\s*:\s*`[^`]+`\.?/g, '')) || '');
    // Une énumération trop longue (O4) : son premier élément seulement.
    if (texte.length > 240 && texte.includes(' ; ')) texte = texte.split(' ; ')[0] + ', entre autres.';
    return { id, titre, gravite, sort: s, texte, tests, outils: outil ? outil[1].split(/,\s*/).filter((o) => o.split(' ').length <= 2) : [] };
  });
}

// --------------------------------------------------------------- le dessin
const COUL = {
  haute: '#FF5C63', 'moyenne à haute': '#FF5C63', 'moyenne, haute dans le modèle du verrou': '#FF5C63',
  moyenne: '#01B9FD', 'moyenne à basse': '#01B9FD', basse: '#94A3B0', info: '#94A3B0',
  durcissement: '#3DDC97', outil: '#31E7FD', 'en corrigeant': '#31E7FD', reste: '#FF5C63', 'à faire': '#FF5C63',
};
const couleur = (g) => COUL[etiquette(g)] || COUL[g] || (g.startsWith('haute') ? '#FF5C63' : g.startsWith('moyenne') ? '#01B9FD' : '#94A3B0');
const etiquette = (g) => ({ 'moyenne, haute dans le modèle du verrou': 'moyenne', 'moyenne à haute': 'moyenne à haute', 'moyenne à basse': 'moyenne à basse' }[g] || g);
const SORT = { corrigé: ['#3DDC97', 'check_circle', 'corrigé'], accepté: ['#94A3B0', 'info', 'accepté'], écarté: ['#94A3B0', 'block', 'écarté'], reste: ['#FF5C63', 'hourglass_empty', 'reste'] };

function carte(f) {
  const c = couleur(f.gravite);
  const [cs, ics, ls] = SORT[f.sort] || [];
  return `<div class="f" style="--g:${c}">
  <div class="h">${f.id ? `<span class="id">${esc(f.id)}</span>` : ''}<span class="gr">${esc(etiquette(f.gravite))}</span>${ls ? `<span class="so" style="--s:${cs}"><i>${ics}</i>${ls}</span>` : ''}</div>
  <h3>${enLigne(f.titre)}</h3>
  ${f.texte ? `<p>${enLigne(f.texte)}</p>` : ''}
  ${f.tests.length || (f.outils || []).length ? `<div class="t">${(f.outils || []).map((o) => `<code class="o">${esc(o)}</code>`).join('')}${f.tests.map((t) => `<code>${t}</code>`).join('')}</div>` : ''}
</div>`;
}

const tetePage = (l) => `<!doctype html><html lang="fr"><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@24,500,1,0" rel="stylesheet">
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:${l}px;background:#0D1117;color:#F1F5F9}
.w{padding:22px 56px;display:grid;gap:12px}
.f{background:#0C1117;border:1px solid #2A333D;border-left:3px solid var(--g);border-radius:12px;padding:14px 16px;display:flex;flex-direction:column;gap:7px}
.h{display:flex;align-items:center;gap:8px}
.id{font-family:'JetBrains Mono',monospace;font-size:13px;font-weight:700;color:#F1F5F9;background:#1A222C;border-radius:6px;padding:3px 8px}
.gr{font-family:'JetBrains Mono',monospace;font-size:11px;letter-spacing:1.5px;text-transform:uppercase;color:var(--g);border:1px solid color-mix(in srgb,var(--g) 45%,transparent);background:color-mix(in srgb,var(--g) 9%,transparent);border-radius:6px;padding:3px 8px}
.so{margin-left:auto;display:flex;align-items:center;gap:5px;font-family:'Space Grotesk',sans-serif;font-size:12.5px;font-weight:600;color:var(--s)}
.so i{font-style:normal;font-family:'Material Symbols Rounded';font-size:17px}
h3{font-family:'Space Grotesk',sans-serif;font-size:15px;font-weight:700;line-height:1.35}
p{font-family:'Space Grotesk',sans-serif;font-size:13px;line-height:1.5;color:#94A3B0}
p b{color:#DDE4EC;font-weight:600}
code{font-family:'JetBrains Mono',monospace;font-size:11.5px;color:#C3CCD7}
.t{display:flex;flex-wrap:wrap;gap:6px;margin-top:2px}
.t code{color:#31E7FD;background:#31E7FD10;border:1px solid #31E7FD30;border-radius:5px;padding:2px 7px}
.t code.o{color:#94A3B0;background:#11171E;border-color:#2A333D}
.bar{display:grid;grid-template-columns:330px 1fr 110px;align-items:center;gap:14px;font-family:'Space Grotesk',sans-serif;font-size:13.5px;color:#C3CCD7}
.bar i{display:block;height:18px;border-radius:5px;background:linear-gradient(90deg,#01B9FD,#31E7FD);box-shadow:0 0 14px #31E7FD30}
.bar b{font-family:'JetBrains Mono',monospace;font-size:13px;color:#F1F5F9;text-align:right}
.tot{font-family:'Space Grotesk',sans-serif;font-size:14px;color:#94A3B0;margin-top:6px}.tot b{color:#3DDC97}
</style></head><body>`;
const piedPage = `<script>document.fonts.ready.then(()=>{setTimeout(()=>{document.title='H'+Math.ceil(document.documentElement.getBoundingClientRect().height);},300);});</script></body></html>`;

const rendus = [];
function planche(nom, fiches, colonnes = 2) {
  const html = `${tetePage(1280)}<div class="w" style="grid-template-columns:repeat(${colonnes},1fr)">${fiches.map(carte).join('\n')}</div>${piedPage}`;
  fs.writeFileSync(path.join(HTML, `fiches-${nom}.html`), html);
  rendus.push(`fiches-${nom}`);
  return `<img src="schemas/audit/fiches-${nom}.png" alt="${fiches.map((f) => `${f.id ? f.id + ' ' : ''}${nu(f.titre)} (${etiquette(f.gravite)}${f.sort ? ', ' + f.sort : ''})`).join(' ; ').replace(/"/g, '&quot;')}." width="100%">`;
}

function graphique(nom, lignes, total) {
  const max = Math.max(...lignes.map((l) => l[1]));
  const html = `${tetePage(1280)}<div class="w">${lignes.map(([n, v]) => `<div class="bar"><span>${enLigne(n)}</span><i style="width:${(v / max * 100).toFixed(1)}%"></i><b>${v.toLocaleString('fr-FR')} M</b></div>`).join('')}<div class="tot">${total}</div></div>${piedPage}`;
  fs.writeFileSync(path.join(HTML, `fiches-${nom}.html`), html);
  rendus.push(`fiches-${nom}`);
  return `<img src="schemas/audit/fiches-${nom}.png" alt="Le fuzzing, en millions d'entrées par cible : ${lignes.map(([n, v]) => `${nu(n)} ${v}`).join(', ')}. ${nu(total)}" width="100%">`;
}

// ------------------------------------------------------- la mise en forme
const replie = (resume, texte) => `<details>\n<summary>${resume}</summary>\n\n${texte.trim()}\n\n</details>`;

const sortie = [tete.trimEnd()];
for (const m of morceaux) {
  const ancre = m.match(/^<a name="([^"]+)">/)[1];
  const blocs = m.split(/\n(?=### )/);
  const debut = blocs.shift().trimEnd();
  const parTitre = blocs.map((b) => {
    const [l1, ...r] = b.split('\n');
    return { titre: l1.replace(/^###\s*/, ''), corps: r.join('\n'), brut: b.trimEnd() };
  });
  let texte = debut;
  const avecGravite = parTitre.filter((b) => /\*\*Gravité\*\*/.test(b.corps));
  if (['protocole-et-cryptographie', 'serveur', 'clients-et-deploiement', 'revue-des-corrections'].includes(ancre)) {
    const fiches = [];
    for (const b of parTitre) {
      if (/\*\*Gravité\*\*/.test(b.corps)) fiches.push(ficheConstat(b.titre, b.corps));
      else if (/Informations/.test(b.titre)) fiches.push(...fichesListe(b.corps, { gravite: 'info' }));
      // Un constat numéroté sans gravité écrite (R2) : une seule fiche.
      else if (/^[A-Z]\d+\./.test(b.titre)) fiches.push({ ...ficheConstat(b.titre, b.corps), gravite: 'basse', texte: phrase(nu(puces(b.corps).join(" "))) });
      else fiches.push(...fichesListe(b.corps, { gravite: 'durcissement', sort: 'corrigé' }));
    }
    texte += '\n\n' + planche(ancre, fiches) + '\n\n' + replie("Le détail, constat par constat", parTitre.map((b) => b.brut).join('\n\n'));
  } else if (ancre === 'trouve-en-corrigeant') {
    const intro = debut.split('\n- ')[0];
    const liste = debut.slice(intro.length);
    texte = intro.trimEnd() + '\n\n' + planche(ancre, fichesListe(liste, { gravite: 'en corrigeant', sort: 'corrigé' })) + '\n\n' + replie('Le détail', liste);
  } else if (ancre === 'deuxieme-audit') {
    const outils = parTitre.find((b) => b.titre.startsWith('Les outils'));
    const trouves = parTitre.find((b) => b.titre.startsWith('Ce qu'));
    const ecartes = parTitre.find((b) => b.titre.startsWith('Écartés'));
    const fuzz = parTitre.find((b) => b.titre.startsWith('Le fuzzing'));
    const f1 = fichesListe(trouves.corps, { gravite: 'outil', sort: 'corrigé' });
    const f2 = fichesListe(ecartes.corps, { gravite: 'info', sort: 'écarté', ids: false });
    const mesures = [...fuzz.corps.matchAll(/^- ([^\n:]+?) :\s*([\d,]+) million/gm)].map((x) => [x[1].trim(), parseFloat(x[2].replace(',', '.'))]);
    texte += '\n\n### Les outils\n\n<img src="schemas/audit/outils.png" alt="Les outils du deuxième audit : govulncheck, staticcheck, gosec, Semgrep, Trivy, Hadolint, ShellCheck, Gixy, et du fuzzing long." width="100%">' +
      '\n\n### Ce qu\'ils ont trouvé, et ce qui a été corrigé\n\n' + planche('deuxieme', f1) + '\n\n' +
      replie('Le détail des dix constats', trouves.corps) + '\n\n### Écartés, avec leur raison\n\n' + planche('ecartes', f2) + '\n\n' +
      replie('Le détail, et pourquoi', ecartes.corps) + '\n\n### Le fuzzing, poussé plus loin\n\n' +
      graphique('fuzzing', mesures, 'Trois minutes par cible, <b>148 millions d’entrées au total, sans une panique ni un désaccord</b>.') + '\n\n' +
      replie('Les quatre nouvelles cibles', fuzz.corps.split('Résultat, trois minutes')[0]);
  } else if (ancre === 'troisieme-audit') {
    const fiches = [];
    const garder = [];
    for (const b of parTitre) {
      if (/\*\*Gravité\*\*/.test(b.corps)) fiches.push(ficheConstat(b.titre, b.corps));
      else if (/constats bas/.test(b.titre)) fiches.push(...fichesListe(b.corps, { gravite: 'basse', sort: 'corrigé' }));
      else if (/Informations/.test(b.titre)) fiches.push(...fichesListe(b.corps, { gravite: 'info', sort: 'corrigé' }));
      else if (/Accepté/.test(b.titre)) fiches.push(...fichesListe(b.corps, { gravite: 'basse', sort: 'accepté' }));
      else garder.push(b);
    }
    texte += '\n\n' + planche('troisieme', fiches) + '\n\n' +
      replie('Le détail des 23 constats', parTitre.filter((b) => !garder.includes(b)).map((b) => b.brut).join('\n\n')) +
      '\n\n' + garder.map((b) => b.brut).join('\n\n');
  } else if (ancre === 'ce-qui-reste') {
    const pied = debut.indexOf('\n<br>');
    const corpsListe = pied > 0 ? debut.slice(0, pied) : debut;
    const [avant, ...lst] = corpsListe.split('\n- ');
    const liste = '- ' + lst.join('\n- ');
    texte = avant.trimEnd() + '\n\n' + planche(ancre, fichesListe(liste, { gravite: 'à faire', sort: 'aucun' })) + '\n\n' + replie('Le détail', liste) + (pied > 0 ? '\n' + debut.slice(pied) : '');
  } else {
    texte = m.trimEnd();
  }
  sortie.push(texte);
}
fs.writeFileSync(FICHIER, sortie.join('\n\n').replace(/\n{3,}/g, '\n\n') + '\n');
fs.writeFileSync(path.join(__dirname, 'html', 'fiches.liste'), rendus.join('\n') + '\n');
console.log(`  ${rendus.length} planches à rendre`);
