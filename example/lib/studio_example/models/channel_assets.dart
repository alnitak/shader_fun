/// Texture asset metadata.
class TextureInfo {
  const TextureInfo({
    required this.name,
    required this.fileName,
    required this.category,
  });

  final String name;
  final String fileName;
  final String category;

  String get assetPath => 'assets/2d_texture/$fileName';
}

/// Audio track metadata.
class AudioTrackInfo {
  const AudioTrackInfo({
    required this.title,
    required this.fileName,
    required this.genre,
  });

  final String title;
  final String fileName;
  final String genre;

  String get assetPath => 'assets/audio/$fileName';
}

/// Predefined catalogues of built-in textures and audio tracks.
class ChannelAssets {
  static const List<AudioTrackInfo> allAudioTracks = [
    AudioTrackInfo(
      title: '8-Bit Mentality',
      fileName: '8_bit_mentality.mp3',
      genre: 'Chiptune / Retro Arcade',
    ),
    AudioTrackInfo(
      title: 'Electro Nebulae',
      fileName: 'electro_nebulae.mp3',
      genre: 'Electronic / Synthwave',
    ),
    AudioTrackInfo(
      title: 'Experiment',
      fileName: 'experiment.mp3',
      genre: 'Ambient / Glitch IDM',
    ),
    AudioTrackInfo(
      title: 'Most Geometric Person',
      fileName: 'most_geometric_person.mp3',
      genre: 'Electro Groove / Beats',
    ),
    AudioTrackInfo(
      title: 'Tropical Beeper',
      fileName: 'tropical_beeper.mp3',
      genre: 'Tropical / Chiptune Melodic',
    ),
    AudioTrackInfo(
      title: 'X Track Ture',
      fileName: 'x_track_ture.mp3',
      genre: 'Drum & Bass / Cyber Electronic',
    ),
  ];

  static const List<TextureInfo> allTextures = [
    // Noise
    TextureInfo(
      name: 'Blue Noise',
      fileName: 'blue_noise.png',
      category: 'Noise',
    ),
    TextureInfo(name: 'Bayer Matrix', fileName: 'bayer.png', category: 'Noise'),
    TextureInfo(
      name: 'Grey Noise Medium',
      fileName: 'grey_noise_medium.png',
      category: 'Noise',
    ),
    TextureInfo(
      name: 'Grey Noise Small',
      fileName: 'grey_noise_small.png',
      category: 'Noise',
    ),
    TextureInfo(
      name: 'RGBA Noise Medium',
      fileName: 'rgba_noise_medium.png',
      category: 'Noise',
    ),
    TextureInfo(
      name: 'RGBA Noise Small',
      fileName: 'rgba_noise_small.png',
      category: 'Noise',
    ),

    // Organic
    TextureInfo(
      name: 'Organic 1',
      fileName: 'organic_1.jpg',
      category: 'Organic',
    ),
    TextureInfo(
      name: 'Organic 2',
      fileName: 'organic_2.jpg',
      category: 'Organic',
    ),
    TextureInfo(
      name: 'Organic 3',
      fileName: 'organic_3.jpg',
      category: 'Organic',
    ),
    TextureInfo(
      name: 'Organic 4',
      fileName: 'organic_4.jpg',
      category: 'Organic',
    ),
    TextureInfo(name: 'Lichen', fileName: 'lichen.jpg', category: 'Organic'),

    // Surface
    TextureInfo(name: 'Wood Grain', fileName: 'wood.jpg', category: 'Surface'),
    TextureInfo(
      name: 'Rock Tiles',
      fileName: 'rock_tiles.jpg',
      category: 'Surface',
    ),
    TextureInfo(
      name: 'Rusty Metal',
      fileName: 'rusty_metal.jpg',
      category: 'Surface',
    ),
    TextureInfo(name: 'Pebbles', fileName: 'pobbles.png', category: 'Surface'),

    // Abstract
    TextureInfo(
      name: 'Abstract 1',
      fileName: 'abstract_1.jpg',
      category: 'Abstract',
    ),
    TextureInfo(
      name: 'Abstract 2',
      fileName: 'abstract_2.jpg',
      category: 'Abstract',
    ),
    TextureInfo(
      name: 'Abstract 3',
      fileName: 'abstract_3.jpg',
      category: 'Abstract',
    ),

    // Misc
    TextureInfo(name: 'Stars & Space', fileName: 'stars.jpg', category: 'Misc'),
    TextureInfo(
      name: 'London Street',
      fileName: 'london.jpg',
      category: 'Misc',
    ),
    TextureInfo(name: 'Nyancat', fileName: 'nyancat.png', category: 'Misc'),
    TextureInfo(name: 'Font Atlas', fileName: 'font_1.png', category: 'Misc'),
  ];
}
