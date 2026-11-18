/// A banner the admin placed on the dashboard (BR-SAWX2U).
///
/// The server sends every banner whose course / class / school / role
/// conditions the user meets and leaves the XP band to the device: the local
/// XP is the current one between syncs, so [appliesTo] is what makes a banner
/// appear and disappear the moment the number moves — the contract the
/// hard-coded `DashboardTiers` had.
class DashboardBanner {
  final int id;

  /// `system.*` for the banners seeded from the app's old hard-coded ones.
  final String? key;
  final String? badge;
  final String title;
  final String body;

  /// Palette key; unknown values fall back to the default border colour.
  final String accent;

  /// Illustration key shipped with the build, or null for none.
  final String? illustration;

  /// Deep link to open on tap, or null for a banner that does not react.
  final String? link;

  /// Inclusive XP bounds. Null means that end is open.
  final int? minXp;
  final int? maxXp;

  const DashboardBanner({
    required this.id,
    required this.title,
    required this.body,
    this.key,
    this.badge,
    this.accent = 'primary',
    this.illustration,
    this.link,
    this.minXp,
    this.maxXp,
  });

  factory DashboardBanner.fromJson(Map<String, dynamic> json) {
    return DashboardBanner(
      id: (json['id'] as num).toInt(),
      key: json['key'] as String?,
      badge: json['badge'] as String?,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      accent: json['accent'] as String? ?? 'primary',
      illustration: json['illustration'] as String?,
      link: json['link'] as String?,
      minXp: (json['min_xp'] as num?)?.toInt(),
      maxXp: (json['max_xp'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'badge': badge,
        'title': title,
        'body': body,
        'accent': accent,
        'illustration': illustration,
        'link': link,
        'min_xp': minXp,
        'max_xp': maxXp,
      };

  /// Does this banner belong on the dashboard at [xp]?
  ///
  /// Both bounds are inclusive, so bands the admin writes as 0–30 and 31–150
  /// neither overlap nor leave a gap at the seam.
  bool appliesTo(int xp) {
    if (minXp != null && xp < minXp!) return false;
    if (maxXp != null && xp > maxXp!) return false;
    return true;
  }
}
