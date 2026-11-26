class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  // Keep in lockstep with pubspec.yaml when bumping the version.
  static const current = AppVersion(1, 6, 5, 31);

  final int major;
  final int minor;
  final int patch;
  final int build;

  static AppVersion? tryParse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final parts = s.split('+');
    if (parts.isEmpty || parts.length > 2) return null;
    final build = parts.length == 2 ? int.tryParse(parts[1]) : 0;
    if (build == null || build < 0) return null;
    final core = parts[0].split('.');
    if (core.length != 3) return null;
    final n = [for (final p in core) int.tryParse(p)];
    if (n.any((e) => e == null || e < 0)) return null;
    return AppVersion(n[0]!, n[1]!, n[2]!, build);
  }

  bool get isNewerThanCurrent => compareTo(current) > 0;

  @override
  int compareTo(AppVersion other) {
    final a = [major, minor, patch, build];
    final b = [other.major, other.minor, other.patch, other.build];
    for (var i = 0; i < 4; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);

  String get label =>
      build == 0 ? '$major.$minor.$patch' : '$major.$minor.$patch+$build';

  @override
  String toString() => label;
}
