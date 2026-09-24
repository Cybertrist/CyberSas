// La charte de CyberSas, reprise du logo : un cyan qui glisse vers le bleu
// sur un bleu nuit presque noir. Toutes les couleurs et tous les styles de
// texte de l'appli viennent d'ici.
import 'package:flutter/material.dart';

abstract final class Couleurs {
  static const fond = Color(0xFF04060A);
  static const fondHaut = Color(0xFF060F16);
  static const surface = Color(0xFF0C1117);
  static const surfaceHaute = Color(0xFF111923);
  static const bordure = Color(0xFF2A333D);
  static const cyan = Color(0xFF31E7FD);
  static const bleu = Color(0xFF01B9FD);
  static const texte = Color(0xFFF1F5F9);
  static const secondaire = Color(0xFF94A3B0);
  // Les petits textes en police mono : plus clairs que le gris secondaire,
  // pour rester lisibles à 11 px en plein jour.
  static const discret = Color(0xFFA4B2BF);
  static const eteint = Color(0xFF5E6B77);
  static const rouge = Color(0xFFFF5C7A);

  static const degrade = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, bleu],
  );
}

// Polices variables : la graisse se règle par l'axe « wght ».
TextStyle _police(String famille, double taille, double graisse, Color couleur,
        {double espacement = 0, double? hauteur}) =>
    TextStyle(
      fontFamily: famille,
      fontSize: taille,
      fontVariations: [FontVariation('wght', graisse)],
      color: couleur,
      letterSpacing: espacement,
      height: hauteur,
    );

/// Syne 800 : le nom de l'appli et les grands titres de marque.
TextStyle syne(double taille, {Color couleur = Couleurs.texte}) =>
    _police('Syne', taille, 800, couleur, espacement: -0.02 * taille);

/// Space Grotesk : tout le texte courant.
TextStyle texte(double taille,
        {double graisse = 400, Color couleur = Couleurs.texte, double? hauteur}) =>
    _police('SpaceGrotesk', taille, graisse, couleur, hauteur: hauteur);

/// JetBrains Mono : adresses, empreintes, étiquettes techniques.
TextStyle mono(double taille,
        {double graisse = 500,
        Color couleur = Couleurs.discret,
        double espacement = 0}) =>
    _police('JetBrainsMono', taille, graisse, couleur, espacement: espacement);

/// Une étiquette technique en capitales espacées : « RÉSEAU SAS · 10.77.0.0/24 ».
TextStyle etiquette({Color couleur = Couleurs.discret, double taille = 11}) =>
    mono(taille, couleur: couleur, espacement: 1.6);

ThemeData themeCyberSas() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'SpaceGrotesk',
    scaffoldBackgroundColor: Couleurs.fond,
    colorScheme: const ColorScheme.dark(
      primary: Couleurs.cyan,
      secondary: Couleurs.bleu,
      surface: Couleurs.surface,
      error: Couleurs.rouge,
    ),
  );
  return base.copyWith(
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((e) =>
          e.contains(WidgetState.selected) ? Colors.white : Couleurs.secondaire),
      trackColor: WidgetStateProperty.resolveWith((e) =>
          e.contains(WidgetState.selected) ? Couleurs.cyan : Couleurs.surfaceHaute),
      trackOutlineColor: WidgetStateProperty.resolveWith((e) =>
          e.contains(WidgetState.selected) ? Couleurs.cyan : Couleurs.bordure),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Couleurs.surfaceHaute,
      contentTextStyle: texte(14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Couleurs.bordure),
      ),
    ),
  );
}
