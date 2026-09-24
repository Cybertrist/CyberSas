# Le verrou du réseau, pas à pas

Le verrou protège le réseau contre son propre serveur. Avec lui, un serveur
piraté ne peut ni s'intercaler entre deux appareils, ni leur ouvrir des ports,
ni faire revenir un appareil banni. Le principe est décrit dans
[`protocole.md`](protocole.md) ; ce document dit comment s'en servir.

## La règle d'or

**La clé privée du verrou ne touche jamais le serveur.** Elle vit sur
l'ordinateur de l'admin, idéalement chiffrée, et sauvegardée hors ligne. Tout
ce qui est signé l'est sur cet ordinateur. Le serveur ne reçoit que des
documents déjà signés, qu'il transmet sans pouvoir les modifier.

Dans le labo, tout tient sur une machine, clé comprise : c'est commode pour
essayer, et c'est la seule exception.

## Créer le verrou

Sur l'ordinateur de l'admin :

```bash
sas verrou creer --fichier ~/.cybersas/verrou
```

La commande affiche la clé publique et son empreinte. La clé publique se pose
sur le serveur, dans `etat/verrou/publique`. La clé privée reste où elle est :
`sas verrou creer` ne remplace jamais une clé existante.

## Inscrire et signer un appareil

1. L'admin crée une clé d'inscription sur le serveur :
   `docker compose exec sasd sasd cle --etiquette maison --nom maison`.
2. L'appareil s'inscrit, en recevant la clé publique du verrou d'avance :
   `SAS_CLE=sas-... sas rejoindre --serveur https://vpn.exemple.fr --verrou <clé publique du verrou>`.
   Il affiche sa propre clé publique et son empreinte.
3. L'admin lit cette clé **sur l'appareil lui-même** (à l'écran, ou par
   `sas etat`), jamais sur le serveur. Puis il signe cette clé-là, et elle
   seule :

```bash
ssh vps 'docker compose exec -T sasd sasd appareils --json' \
  | sas verrou signer --fichier ~/.cybersas/verrou --cle <clé publique de l'appareil> \
  | ssh vps 'docker compose exec -T sasd sasd signatures'
```

`sas verrou signer` affiche ce qu'il signe : nom, adresse, étiquette ou
propriétaire, groupe et empreinte. Si l'empreinte ne correspond pas à celle
affichée par l'appareil, il ne faut rien envoyer.

Les certificats valent 90 jours (`--duree` pour changer). Il faut les
renouveler avant, de la même façon.

## Signer la politique

À chaque modification de `politique/politique.json`, augmenter son champ
`version`, puis :

```bash
sas verrou politique --fichier ~/.cybersas/verrou < politique/politique.json > politique/politique.sig
```

Poser les deux fichiers sur le serveur. Les appareils refusent une politique
mal signée, ou plus ancienne que la dernière qu'ils ont vue.

## Bannir un appareil volé ou perdu

1. Retirer l'appareil : `docker compose exec sasd sasd retirer <nom>`. Il est
   coupé tout de suite, mais son certificat reste valide jusqu'à expiration.
2. Le révoquer, pour qu'un serveur piraté ne puisse pas le faire revenir :

```bash
ssh vps 'cat etat/sasd/revocations.json' \
  | sas verrou revoquer --fichier ~/.cybersas/verrou --cle <clé publique de l'appareil> \
  | ssh vps 'cat > etat/sasd/revocations.json'
```

La liste est numérotée : les appareils gardent la plus récente vue, et
n'acceptent jamais d'en revenir à une plus ancienne.

## Si la clé du verrou est perdue ou volée

- **Perdue** : il faut en créer une nouvelle, et réinscrire tous les
  appareils avec `--oublier`, puisqu'ils refusent tout changement de verrou.
- **Volée** : même chose, et vite. Le voleur peut signer ce qu'il veut tant que
  les appareils font confiance à l'ancienne.
