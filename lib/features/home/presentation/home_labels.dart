import 'package:cutter/features/home/domain/home_preferences.dart';
import 'package:cutter/features/home/domain/project_list_query.dart';
import 'package:cutter/l10n/app_localizations.dart';

/// The words for the home list options, shared by the filter screen and the
/// chips that summarise what is applied.
extension HomeLabels on AppLocalizations {
  /// Name of a sort order.
  String sortLabel(ProjectSort sort) => switch (sort) {
        ProjectSort.recent => homeSortRecent,
        ProjectSort.oldest => homeSortOldest,
        ProjectSort.name => homeSortName,
        ProjectSort.longest => homeSortLongest,
        ProjectSort.shortest => homeSortShortest,
      };

  /// Name of a project kind filter.
  String filterLabel(ProjectFilter filter) => switch (filter) {
        ProjectFilter.all => homeFilterAll,
        ProjectFilter.saved => homeFilterSaved,
        ProjectFilter.empty => homeFilterEmpty,
      };

  /// Name of a last edit filter.
  String editedLabelOf(EditedWithin edited) => switch (edited) {
        EditedWithin.any => homeEditedAny,
        EditedWithin.today => homeEditedToday,
        EditedWithin.week => homeEditedWeek,
        EditedWithin.month => homeEditedMonth,
      };

  /// Name of a length filter.
  String lengthLabel(LengthRange length) => switch (length) {
        LengthRange.any => homeLengthAny,
        LengthRange.short => homeLengthShort,
        LengthRange.medium => homeLengthMedium,
        LengthRange.long => homeLengthLong,
      };

  /// Name of a library part.
  String scopeLabel(ProjectScope scope) => switch (scope) {
        ProjectScope.active => homeProjectsSection,
        ProjectScope.archived => homeScopeArchived,
        ProjectScope.trash => homeScopeTrash,
      };
}
