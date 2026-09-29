import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/riverpod/providers/library.dart';
import 'package:kover/riverpod/providers/series.dart';

/// True when this series lives in a manga or comic library.
bool isComicEpub(WidgetRef ref, {required int seriesId}) {
  final series = ref.watch(seriesProvider(seriesId: seriesId)).asData?.value;
  if (series == null) return false;
  final library = ref
      .watch(libraryProvider(libraryId: series.libraryId))
      .asData
      ?.value;
  return library?.type.isComic ?? false;
}
