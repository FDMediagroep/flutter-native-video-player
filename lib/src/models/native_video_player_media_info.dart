class NativeVideoPlayerMediaInfo {
  const NativeVideoPlayerMediaInfo({
    this.title,
    this.subtitle,
    this.album,
    this.artworkUrl,
  });

  final String? title;
  final String? subtitle;
  final String? album;
  final String? artworkUrl;

  /// Returns a copy with the given fields replaced. Passing `null` keeps the
  /// current value — construct a new instance to clear a field.
  NativeVideoPlayerMediaInfo copyWith({
    String? title,
    String? subtitle,
    String? album,
    String? artworkUrl,
  }) => NativeVideoPlayerMediaInfo(
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    album: album ?? this.album,
    artworkUrl: artworkUrl ?? this.artworkUrl,
  );

  Map<String, dynamic> toMap() => <String, dynamic>{
    if (title != null) 'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (album != null) 'album': album,
    if (artworkUrl != null) 'artworkUrl': artworkUrl,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeVideoPlayerMediaInfo &&
          other.title == title &&
          other.subtitle == subtitle &&
          other.album == album &&
          other.artworkUrl == artworkUrl;

  @override
  int get hashCode => Object.hash(title, subtitle, album, artworkUrl);

  @override
  String toString() =>
      'NativeVideoPlayerMediaInfo(title: $title, subtitle: $subtitle, '
      'album: $album, artworkUrl: $artworkUrl)';
}
