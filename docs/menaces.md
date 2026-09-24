# Modèle de menace

Ce que CyberSas protège, contre qui, et ce qu'il ne promet pas.

## Ce qu'on protège

- **Les services de la maison**, qui ne doivent être joignables que par les
  personnes autorisées.
- **L'adresse IP de la maison**, qui ne doit apparaître nulle part.
- **L'accès de l'équipe.** Un mot de passe volé ne doit pas suffire.
- **Le trafic entre appareils**, qui ne doit être lisible par personne d'autre,
  y compris l'hébergeur du VPS.

## Ce qui est exposé

Sur Internet, trois noms en HTTPS sur le port 443, et le port 80 qui ne fait
que rediriger :

- `hs.` : Headscale, pour que les appareils rejoignent le VPN.
- `auth.` : le portail de connexion, qui renvoie chez Google.
- `maison.` : un service de la maison, réservé aux comptes autorisés.

Tout autre nom est coupé avant même l'échange de certificat. Headscale et
oauth2-proxy n'écoutent pas sur Internet : seul Nginx peut les atteindre, par
un réseau Docker interne sans passerelle. Ils ont une sortie vers Internet,
et une seule raison de s'en servir : parler à Google.

## Pourquoi Google

L'identité est confiée à Google plutôt que gérée ici. Ce que ça apporte :

- **Aucun mot de passe stocké.** Il n'y a rien à voler sur le VPS.
- **Le second facteur est celui du compte Google**, déjà réglé sur le
  téléphone de chacun, avec l'alerte de connexion suspecte qui va avec.
- **Pas de réinitialisation à gérer.** Un mot de passe oublié se règle chez
  Google.

Ce que ça coûte :

- **Google devient un tiers de confiance.** S'il est en panne, personne ne peut
  se connecter. Les appareils déjà dans le VPN restent connectés, jusqu'à
  l'expiration de leur inscription, trente jours après.
- **Un compte Google volé ouvre le VPN.** Le second facteur limite ce risque,
  mais CyberSas ne peut pas l'imposer : il dépend du réglage de chaque compte.
- **Google sait qui se connecte, et quand.** Il ne voit rien de ce qui passe
  ensuite dans le VPN.

Le contrôle d'accès reste ici. Avoir un compte Google ne suffit pas : il faut
que l'adresse figure dans `etat/equipe.txt`. Headscale et oauth2-proxy
vérifient tous les deux la même liste, et exigent une adresse vérifiée par
Google.

## Contre qui

**Quelqu'un qui scanne Internet.** Il trouve un Nginx qui ne répond qu'à trois
noms, et un port 80 qui redirige. Aucune version n'est affichée
(`server_tokens off`).

**Quelqu'un qui veut détourner la connexion.** Le retour depuis Google n'est
accepté que vers les sous-domaines du domaine, et l'échange de code est protégé
par PKCE : un code intercepté ne sert à rien sans le secret que seul le
navigateur d'origine possède.

**Un membre de l'équipe qui va trop loin**, volontairement ou parce que son
appareil est compromis. La politique du VPN ferme tout par défaut : il n'atteint
que ce que son groupe autorise, ici les services web de la maison, pas leur SSH.
Il ne voit pas les appareils des autres membres. Le retirer de la liste
déconnecte aussi ses appareils.

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
- Il récupère le secret du client Google. Ce secret ne donne accès à aucun
  compte : il permet seulement de se faire passer pour CyberSas auprès de
  Google. Il faut alors le régénérer dans la console Google Cloud.
- Il ne peut **pas** lire le trafic entre deux appareils de l'équipe, qui ne
  passe pas par le VPS en clair.

Ce qui limite les dégâts : le relais du VPS n'a le droit d'atteindre que les
ports web de la maison. Pour aller plus loin, un attaquant doit inscrire un
nouvel appareil, ce qui laisse une trace dans les journaux de Headscale. C'est
pour ça que la surveillance de ces journaux fait partie de la suite du projet.

## Ce que CyberSas ne fait pas encore

- **Pas de blocage automatique des adresses** qui insistent. CrowdSec viendra.
- **Pas d'alertes.** Les journaux sont en JSON, prêts à partir vers un SIEM,
  mais rien ne les lit encore.
- **Pas de sauvegarde** de la base de Headscale.
