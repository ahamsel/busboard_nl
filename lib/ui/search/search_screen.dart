import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../data/trip_planner/saved_place_store.dart';
import '../../domain/location/locate_me.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/map_pick_provider.dart';
import '../../state/providers.dart';
import '../../state/saved_place_providers.dart';
import '../../state/trip_planner_providers.dart';
import '../home/home_sheet.dart';
import '../kit/kit.dart';
import '../trip_planner/saved_trips_section.dart';

/// The most stops a search lists.
const maxPlaceMatches = 20;

/// Stops whose id starts with [query] or whose name contains it (any case), at most [maxPlaceMatches], by stop id.
List<StopInfo> matchStops(GtfsRepository repo, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out =
      repo.stopsById.values
          .where((s) => s.stopId.toLowerCase().startsWith(q) || s.stopName.toLowerCase().contains(q))
          .toList()
        ..sort((a, b) => _compareIds(a.stopId, b.stopId));
  return out.take(maxPlaceMatches).toList();
}

int _compareIds(String a, String b) {
  final ai = int.tryParse(a);
  final bi = int.tryParse(b);
  if (ai != null && bi != null) return ai.compareTo(bi);
  if (ai != null) return -1;
  if (bi != null) return 1;
  return a.compareTo(b);
}

/// How many recent places an empty search lists.
const _recentShown = 10;

/// "Where to?" (spec 2026-10-12 §3.3): find a stop or a place to go to, to start from, or to save.
/// [end] is the end being chosen; [save] saves the pick as a named place instead of planning to it.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.end = MapPick.to, this.save = false});

  static const fieldKey = ValueKey('search-field');

  final MapPick end;
  final bool save;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title => widget.save
      ? 'Save a place'
      : widget.end == MapPick.from
      ? 'Choose a start'
      : 'Where to?';

  /// A pick or a location fix is being worked out: further taps are ignored until it ends.
  var _busy = false;

  /// Waiting for a location fix (the rows show "Finding you…").
  var _locating = false;

  /// Leaves the screen: back to the page below, or home when this is the first page.
  void _leave(GoRouter router) {
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  /// One fix, with the "Finding you…" row showing while it is awaited.
  Future<PinPlace?> _locate() async {
    if (mounted) setState(() => _locating = true);
    try {
      return await locateMe();
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Everything this needs from [ref] and [context] is taken before the first await: the fix can take a while,
  /// and the rider may leave meanwhile. The destination is still set then, since the rider asked to go there.
  Future<void> _pick(Place place, {bool askAboutStop = false}) async {
    if (_busy) return;
    final router = GoRouter.of(context);
    final query = ref.read(planQueryProvider.notifier);
    final hasStart = ref.read(planQueryProvider).from != null;
    final recent = ref.read(recentPlacesProvider.notifier);
    final sheet = ref.read(homeSheetProvider.notifier);
    _busy = true;
    try {
      if (widget.save) return await _saveFlow(place);
      if (widget.end == MapPick.from) {
        query.setFrom(place);
        _leave(router);
        return;
      }
      if (askAboutStop && place is StopPlace) {
        final goHere = await BBDialog.show<bool>(
          context,
          title: place.label,
          actions: const [
            BBDialogAction(label: 'See its buses', value: false),
            BBDialogAction(label: 'Go here', value: true, primary: true),
          ],
        );
        if (goHere == null) return;
        if (!goHere) {
          sheet.open(StopSheet(place.stopId));
          if (mounted) _leave(router);
          return;
        }
      }
      await recent.push(place);
      query.setDestination(place);
      if (!hasStart) {
        final here = await _locate();
        if (here != null) query.setFrom(here);
      }
      sheet.open(const OptionsSheet());
      if (mounted) _leave(router);
    } finally {
      _busy = false;
    }
  }

  /// Asks for a name and an icon, then saves [place].
  Future<void> _saveFlow(Place place) async {
    final router = GoRouter.of(context);
    final places = ref.read(savedPlacesProvider.notifier);
    var name = place.label;
    var icon = SavedPlaceIcon.star;
    final save = await BBDialog.show<bool>(
      context,
      title: 'Save this place',
      content: _SaveFields(initialName: place.label, onName: (v) => name = v, onIcon: (v) => icon = v),
      actions: const [
        BBDialogAction(label: 'Cancel', value: false),
        BBDialogAction(label: 'Save', value: true, primary: true),
      ],
    );
    if (save != true) return;
    final saved = await places.put(
      SavedPlace(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.trim().isEmpty ? place.label : name.trim(),
        icon: icon,
        place: place,
      ),
    );
    if (!mounted) return;
    if (!saved) {
      BBToast.show(context, 'You can save up to $maxSavedPlaces places. Remove one first.');
      return;
    }
    _leave(router);
  }

  /// "My location" as the start.
  Future<void> _useMyLocation() async {
    if (_busy) return;
    final router = GoRouter.of(context);
    final query = ref.read(planQueryProvider.notifier);
    _busy = true;
    try {
      final here = await _locate();
      if (here != null) {
        query.setFrom(here);
        if (mounted) _leave(router);
      } else if (mounted) {
        BBToast.show(context, "Couldn't find your location");
      }
    } finally {
      _busy = false;
    }
  }

  void _chooseOnMap() {
    if (_busy) return;
    ref.read(mapPickProvider.notifier).start(widget.end);
    _leave(GoRouter.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final query = _controller.text.trim();
    final repo = ref.watch(gtfsRepositoryProvider).value;
    final saved = ref.watch(savedPlacesProvider).value ?? const <SavedPlace>[];
    final recent = ref.watch(recentPlacesProvider).value ?? const <Place>[];
    return BBScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BBTopBar(title: _title, onBack: () => _leave(GoRouter.of(context))),
          Padding(
            padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.s),
            child: BBTextField(
              key: SearchScreen.fieldKey,
              controller: _controller,
              autofocus: true,
              leadingIcon: BBIcons.search,
              hint: 'Search for a stop or a place',
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.xxl),
              children: [
                if (_locating)
                  Semantics(
                    liveRegion: true,
                    child: const BBPickRow(icon: BBIcons.nearMe, label: 'Finding you…', onTap: null),
                  ),
                ...(query.isEmpty ? _emptyRows(saved, recent) : _resultRows(bb, repo, query, saved)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _emptyRows(List<SavedPlace> saved, List<Place> recent) {
    return [
      // A saved place is a stop or a pin the rider names, not a spot on the map to be picked later.
      if (!widget.save) BBPickRow(icon: BBIcons.map, label: 'Choose on map', onTap: _chooseOnMap),
      if (widget.end == MapPick.from && !widget.save)
        BBPickRow(icon: BBIcons.nearMe, label: myLocationLabel, onTap: _useMyLocation),
      if (saved.isNotEmpty && !widget.save) ...[
        const SizedBox(height: BBSpace.m),
        const BBSectionHeader(title: 'Saved places'),
        const SizedBox(height: BBSpace.xs),
        for (final p in saved) _savedRow(p),
      ],
      if (recent.isNotEmpty) ...[
        const SizedBox(height: BBSpace.m),
        const BBSectionHeader(title: 'Recent'),
        const SizedBox(height: BBSpace.xs),
        for (final p in recent.take(_recentShown))
          BBPickRow(
            icon: BBIcons.history,
            label: p.label,
            semanticLabel: p is StopPlace ? '${p.label}, stop ${p.stopId}' : p.label,
            onTap: () => _pick(p),
          ),
      ],
    ];
  }

  Widget _savedRow(SavedPlace p) =>
      BBPickRow(icon: savedPlaceIconData(p.icon), label: p.name, semanticLabel: p.name, onTap: () => _pick(p.place));

  List<Widget> _resultRows(BBTokens bb, GtfsRepository? repo, String query, List<SavedPlace> saved) {
    final stops = repo == null ? <StopInfo>[] : matchStops(repo, query);
    // A stop number typed in full is that stop, ahead of stops whose names mention it.
    final exact = repo?.stopsById[query];
    if (exact != null) {
      stops
        ..removeWhere((s) => s.stopId == exact.stopId)
        ..insert(0, exact);
    }
    final lower = query.toLowerCase();
    // Saving a place is for a stop, not for one already saved.
    final places = [
      for (final p in saved)
        if (!widget.save && p.name.toLowerCase().contains(lower)) p,
    ];
    if (stops.isEmpty && places.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: BBSpace.l),
          child: Text('No stops match "$query"', style: bb.text.body.copyWith(color: bb.colors.muted)),
        ),
      ];
    }
    return [
      for (final s in stops)
        BBPickRow(
          icon: BBIcons.stop,
          label: '${s.stopName} (${s.stopId})',
          semanticLabel: '${s.stopName}, stop ${s.stopId}',
          onTap: () => _pick(StopPlace(stopId: s.stopId, name: s.stopName), askAboutStop: true),
        ),
      if (stops.isNotEmpty && places.isNotEmpty) const BBDivider(),
      for (final p in places) _savedRow(p),
    ];
  }
}

/// The name and icon fields of the save dialog, with their own controller (the dialog is still on screen as it closes).
class _SaveFields extends StatefulWidget {
  const _SaveFields({required this.initialName, required this.onName, required this.onIcon});

  final String initialName;
  final ValueChanged<String> onName;
  final ValueChanged<SavedPlaceIcon> onIcon;

  @override
  State<_SaveFields> createState() => _SaveFieldsState();
}

class _SaveFieldsState extends State<_SaveFields> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialName);
  var _icon = SavedPlaceIcon.star;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _labels = {
    SavedPlaceIcon.home: 'Home',
    SavedPlaceIcon.work: 'Work',
    SavedPlaceIcon.school: 'School',
    SavedPlaceIcon.star: 'Star',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BBTextField(
          controller: _controller,
          hint: 'Name',
          autofocus: true,
          onChanged: widget.onName,
          inputFormatters: [LengthLimitingTextInputFormatter(savedTripNameMax)],
        ),
        const SizedBox(height: BBSpace.m),
        BBSegmented<SavedPlaceIcon>(
          segments: [for (final e in _labels.entries) BBSegment(value: e.key, label: e.value)],
          selected: _icon,
          onChanged: (v) {
            setState(() => _icon = v);
            widget.onIcon(v);
          },
        ),
      ],
    );
  }
}
