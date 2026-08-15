import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/config/app_env.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_page.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../domain/entities/app_preferences.dart';
import '../cubit/preferences_cubit.dart';
import '../cubit/preferences_state.dart';
import '../widgets/backup_card.dart';

/// The Profile tab (ADR §13.5) — the settings feature's screen.
///
/// Appearance and language are wired for real from v1 even though there is
/// exactly one language: the plumbing being proven is the point (ADR §12.1).
/// Adding Bengali later is a translation job, not a refactor.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppPage(
      child: BlocConsumer<PreferencesCubit, PreferencesState>(
        // Only surface a failure when one newly appears; a rebuild for an
        // unrelated field must not re-raise the snack bar.
        listenWhen: (previous, current) =>
            previous.saveFailure != current.saveFailure &&
            current.saveFailure != null,
        listener: (context, state) =>
            context.showSnackBar(l10n.stateErrorBody, isError: true),
        builder: (context, state) {
          final preferences = state.preferences;

          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              PageHeader(l10n.profileTitle, subtitle: l10n.appTagline),
              SectionLabel(l10n.profileSectionAppearance),
              _ThemeModeCard(
                selected: preferences.themeMode,
                onChanged: (mode) =>
                    context.read<PreferencesCubit>().setThemeMode(mode),
              ),
              const SizedBox(height: AppSpacing.sm),
              _HapticsCard(
                enabled: preferences.hapticsEnabled,
                onChanged: (enabled) => context
                    .read<PreferencesCubit>()
                    .setHapticsEnabled(enabled: enabled),
              ),
              SectionLabel(l10n.profileSectionLanguage),
              _LanguageCard(
                localeCode: preferences.localeCode,
                onChanged: (code) =>
                    context.read<PreferencesCubit>().setLocale(code),
              ),
              SectionLabel(l10n.profileSectionData),
              const BackupCard(),
              SectionLabel(l10n.profileSectionAbout),
              const _AboutCard(),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard({required this.selected, required this.onChanged});

  final AppThemeMode selected;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.profileThemeLabel, style: context.textStyles.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          // Stretches to the card so the three options share the width evenly
          // and don't reflow at 1.4× text scale.
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AppThemeMode>(
              segments: [
                ButtonSegment(
                  value: AppThemeMode.system,
                  label: Text(l10n.profileThemeSystem),
                ),
                ButtonSegment(
                  value: AppThemeMode.light,
                  label: Text(l10n.profileThemeLight),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text(l10n.profileThemeDark),
                ),
              ],
              selected: {selected},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _HapticsCard extends StatelessWidget {
  const _HapticsCard({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppCard(
      padding: EdgeInsets.zero,
      // SwitchListTile handles the ripple, the 48dp target and the semantics
      // of a toggle for us; the card just supplies the surface.
      child: SwitchListTile.adaptive(
        value: enabled,
        onChanged: onChanged,
        title: Text(l10n.profileHapticsLabel),
        subtitle: Text(l10n.profileHapticsDescription),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({required this.localeCode, required this.onChanged});

  /// Null means "follow the system" (ADR §12.1).
  final String? localeCode;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        title: Text(l10n.profileLanguageLabel),
        trailing: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: localeCode,
            borderRadius: AppRadius.mdAll,
            onChanged: onChanged,
            items: [
              DropdownMenuItem<String?>(
                child: Text(l10n.profileLanguageSystem),
              ),
              // Built from the generated supported locales, so shipping a new
              // ARB file adds a row here with no code change.
              for (final locale in L10n.supportedLocales)
                DropdownMenuItem<String?>(
                  value: locale.languageCode,
                  child: Text(_nameOf(locale)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A language is always listed in its own language — a reader looking for
  /// "বাংলা" will not recognise "Bengali".
  static String _nameOf(Locale locale) => switch (locale.languageCode) {
    'en' => 'English',
    'bn' => 'বাংলা',
    'hi' => 'हिन्दी',
    'ar' => 'العربية',
    'es' => 'Español',
    final code => code.toUpperCase(),
  };
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = getIt<AppConfig>();

    return AppCard(
      child: Column(
        children: [
          _AboutRow(label: l10n.profileAboutVersion, value: AppConfig.version),
          const Divider(height: AppSpacing.lg),
          _AboutRow(
            label: l10n.profileAboutEnvironment,
            value: switch (config.env) {
              AppEnvironment.dev => l10n.envDev,
              AppEnvironment.stg => l10n.envStg,
              AppEnvironment.prod => l10n.envProd,
            },
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: context.textStyles.bodyLarge)),
        Text(
          value,
          style: context.textStyles.labelLarge?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
