import 'package:flutter/material.dart';

import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../shared/widgets/app_page.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/roadmap_placeholder.dart';

/// The Insights tab — adherence, body weight, strength progression and the
/// Day/Week/Month/Cycle filter (ADR §11).
///
/// Placeholder until there is history worth aggregating (roadmap Phase 3,
/// step 15).
class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(l10n.insightsTitle),
          Expanded(
            child: RoadmapPlaceholder(
              icon: Icons.insights_rounded,
              title: l10n.insightsPlaceholderTitle,
              message: l10n.insightsPlaceholderBody,
              milestone: 'Phase 3',
            ),
          ),
        ],
      ),
    );
  }
}
