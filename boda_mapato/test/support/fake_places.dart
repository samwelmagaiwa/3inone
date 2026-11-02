import 'package:boda_mapato/widgets/place_picker.dart';

/// No lists at all: every level is a box to type in (what a place with no imported data looks like).
class NoPlaces implements PlaceSource {
  const NoPlaces();

  @override
  Future<List<PlaceOption>> regions() async => const <PlaceOption>[];

  @override
  Future<List<PlaceOption>> districts(String regionId) async => const <PlaceOption>[];

  @override
  Future<List<PlaceOption>> wards(String districtId) async => const <PlaceOption>[];

  @override
  Future<List<PlaceOption>> streets(String wardId) async => const <PlaceOption>[];
}

/// A little of Tanzania, with the gaps real data has: a district with no wards (Ilala), a region whose districts cannot be loaded (Arusha).
class FakePlaces implements PlaceSource {
  final List<String> asked = <String>[];

  static const PlaceOption dar = PlaceOption(id: '1', name: 'Dar es Salaam');
  static const PlaceOption arusha = PlaceOption(id: '2', name: 'Arusha');
  static const PlaceOption kinondoni = PlaceOption(id: '11', name: 'Kinondoni');
  static const PlaceOption ilala = PlaceOption(id: '12', name: 'Ilala');
  static const PlaceOption mikocheni = PlaceOption(id: '111', name: 'Mikocheni');
  static const PlaceOption msasani = PlaceOption(id: '112', name: 'Msasani');
  static const PlaceOption mikocheniA = PlaceOption(id: '1111', name: 'Mikocheni A');
  static const PlaceOption mikocheniB = PlaceOption(id: '1112', name: 'Mikocheni B');
  static const PlaceOption kimweri = PlaceOption(id: '1113', name: 'Kimweri');

  @override
  Future<List<PlaceOption>> regions() async {
    asked.add('regions');
    return const <PlaceOption>[dar, arusha];
  }

  @override
  Future<List<PlaceOption>> districts(String regionId) async {
    asked.add('districts:$regionId');
    if (regionId == '1') return const <PlaceOption>[kinondoni, ilala];
    throw Exception('the server could not be reached');
  }

  @override
  Future<List<PlaceOption>> wards(String districtId) async {
    asked.add('wards:$districtId');
    return districtId == '11' ? const <PlaceOption>[mikocheni, msasani] : const <PlaceOption>[];
  }

  @override
  Future<List<PlaceOption>> streets(String wardId) async {
    asked.add('streets:$wardId');
    return wardId == '111' ? const <PlaceOption>[mikocheniA, mikocheniB, kimweri] : const <PlaceOption>[];
  }
}
