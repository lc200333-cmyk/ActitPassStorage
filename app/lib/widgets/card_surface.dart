import 'package:flutter/material.dart';

BoxDecoration cardSurfaceDecoration({
  required Color color,
  ImageProvider? backgroundImage,
}) =>
    BoxDecoration(
      color: color,
      image: backgroundImage == null
          ? null
          : DecorationImage(
              image: backgroundImage,
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.white.withValues(alpha: 0.28),
                BlendMode.srcOver,
              ),
            ),
    );
