# Modèle de menace

Ce que CyberSas protège, contre qui, et ce qu'il ne promet pas.

## Ce qu'on protège

- **Les services de la maison**, qui ne doivent être joignables que par les
  personnes autorisées.
- **L'adresse IP de la maison**, qui ne doit apparaître nulle part.
- **Les comptes de l'équipe.** Un mot de passe volé ne doit pas suffire.
- **Le trafic entre appareils**, qui ne doit être lisible par personne d'autre,
  y compris l'hébergeur du VPS.

## Ce qui est exposé

Sur Internet, trois noms en HTTPS sur le port 443, et le port 80 qui ne fait
que rediriger :

- `hs.` : Headscale, pour que les appareils rejoignent le VPN.
- `auth.` : le portail Authelia.
- `maison.` : un service de la maison, derrière Authelia.

Tout autre nom est coupé avant même l'échange de certificat. Headscale et
Authelia n'écoutent pas sur Internet : ils sont sur un réseau Docker interne,
sans passerelle, que seul Nginx peut atteindre.

## Contre qui

**Quelqu'un qui scanne Internet.** Il trouve un Nginx qui ne répond qu'à trois
noms, et un port 80 qui redirige. Aucune version n'est affichée
(`server_tokens off`).

**Quelqu'un qui devine des mots de passe.** Nginx limite les tentatives à dix
par minute et par adresse sur le portail. Authelia gèle le compte dix minutes
après trois échecs en deux minutes. Et même avec le bon mot de passe, il manque
le second facteur.

**Un membre de l'équipe qui va trop loin**, volontairement ou parce que son
appareil est compromis. La politique du VPN ferme tout par défaut : il n'atteint
que ce que son groupe autorise, ici les services web de la maison, pas leur SSH.
Il ne voit pas les appareils des autres membres.

**Un service de la maison compromis.** Il ne peut se retourner vers aucun
appareil du VPN : aucune règle ne part de `tag:maison`.

**L'hébergeur du VPS.** Il voit passer le trafic chiffré du VPN, mais pas son
contenu : WireGuard chiffre de bout en bout, et les clés privées ne quittent pas
les appareils. En revanche, il voit en clair ce que Nginx publie sur `maison.`,
puisque le TLS se termine sur le VPS. Voir plus bas.

## Si le VPS tombe aux mains d'un attaquant

C'est le scénario le plus grave, et il vaut mieux le dire franchement.

- Il contrôle Headscale : il peut **ajouter un appareil à lui** dans le VPN, ou
  modifier la politique. Les règles d'accès ne protègent donc pas contre le VPS
  lui-même.
- Il voit en clair le trafic des services publiés par Nginx.
- Il ne peut **pas** lire le trafic entre deux appareils de l'équipe, qui ne
  passe pas par le VPS en clair.
- Il ne récupère pas les mots de passe : Authelia n'en garde que l'empreinte
  argon2id.

Ce qui limite les dégâts : le relais du VPS n'a le droit d'atteindre que les
ports web de la maison. Pour aller plus loin, un attaquant doit inscrire un
nouvel appareil, ce qui laisse une trace dans les journaux de Headscale. C'est
pour ça que la surveillance de ces journaux fait partie de la suite du projet.

## Ce que CyberSas ne fait pas encore

- **Pas de blocage automatique des adresses** qui insistent. CrowdSec viendra.
- **Pas d'alertes.** Les journaux sont en JSON, prêts à partir vers un SIEM,
  mais rien ne les lit encore.
- **Pas de sauvegarde** de la base de Headscale ni de celle d'Authelia.
- **Les groupes sont écrits deux fois**, dans Authelia et dans la politique du
  VPN. Oublier l'un des deux, c'est donner un accès web sans accès VPN, ou
  l'inverse.
