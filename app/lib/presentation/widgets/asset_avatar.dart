import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The round initial standing for an asset in lists. Decorative: the name
/// next to it says the same.
class AssetAvatar extends StatelessWidget {
  const AssetAvatar(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CircleAvatar(
      radius: AppSpace.x5,
      backgroundColor: AppColors.line,
      foregroundColor: AppColors.ink,
      child: Text(name.characters.first.toUpperCase()),
    ),
  );
}
