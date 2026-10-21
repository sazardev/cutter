import 'package:cutter/features/editor/data/built_in_template_catalog.dart';
import 'package:cutter/features/editor/domain/template.dart';
import 'package:cutter/l10n/app_localizations.dart';

/// The localized title and description of a template.
///
/// Built-in templates are translated by id; a template this switch does not
/// know falls back to the name it carries.
({String title, String body}) templateLabels(
  AppLocalizations l10n,
  Template template,
) {
  return switch (template.id) {
    BuiltInTemplateIds.verticalStory => (
        title: l10n.templateVerticalStoryTitle,
        body: l10n.templateVerticalStoryBody,
      ),
    BuiltInTemplateIds.voiceOver => (
        title: l10n.templateVoiceOverTitle,
        body: l10n.templateVoiceOverBody,
      ),
    BuiltInTemplateIds.photoMontage => (
        title: l10n.templatePhotoMontageTitle,
        body: l10n.templatePhotoMontageBody,
      ),
    _ => (title: template.name, body: ''),
  };
}
