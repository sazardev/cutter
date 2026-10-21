import 'package:flutter/material.dart';

/// The icon of a genre; a note for one it does not know, so a catalog can
/// add genres without a new build.
IconData genreIcon(String genre) => switch (genre) {
      'epic' || 'cinematic' || 'scoring' => Icons.movie_filter_outlined,
      'electronic' || 'dance' => Icons.graphic_eq,
      'ambient' || 'calm' || 'world' => Icons.spa_outlined,
      'upbeat' || 'fun' => Icons.celebration_outlined,
      'comedy' => Icons.sentiment_very_satisfied_outlined,
      'horror' || 'dark' => Icons.nightlight_outlined,
      'romantic' || 'piano' => Icons.piano_outlined,
      'rock' || 'hiphop' => Icons.nightlife_outlined,
      'lofi' => Icons.headphones_outlined,
      'sport' || 'sports' => Icons.sports_score_outlined,
      'corporate' => Icons.business_center_outlined,
      _ => Icons.music_note_outlined,
    };
