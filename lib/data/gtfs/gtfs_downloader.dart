import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

/// Downloads and caches the Metrobus GTFS ZIP file.
///
/// Cache policy:
/// - Reuse if cached ZIP exists and is < 7 days old.
/// - Manual [force] parameter re-downloads regardless.
class GtfsDownloader {
  static const gtfsUrl = 'https://www.metrobus.com/gtfs.asp';
  static const _zipFilename = 'metrobus_gtfs.zip';
  static const _extractDir = 'gtfs_data';
  static const _maxCacheAge = Duration(days: 7);

  /// Get the app documents directory.
  Future<Directory> get _appDir async => getApplicationDocumentsDirectory();

  /// Get the cached ZIP file.
  Future<File> get _zipFile async {
    final dir = await _appDir;
    return File('${dir.path}/$_zipFilename');
  }

  /// Get the extraction directory.
  Future<Directory> get extractionDir async {
    final dir = await _appDir;
    return Directory('${dir.path}/$_extractDir');
  }

  /// Whether the cached GTFS data is still valid (< 7 days old).
  Future<bool> isCacheValid() async {
    final zip = await _zipFile;
    if (!await zip.exists()) return false;
    final modified = await zip.lastModified();
    return DateTime.now().difference(modified) < _maxCacheAge;
  }

  /// Last download timestamp, or null if never downloaded.
  Future<DateTime?> lastDownloadTime() async {
    final zip = await _zipFile;
    if (!await zip.exists()) return null;
    return zip.lastModified();
  }

  /// Download and extract the GTFS ZIP.
  ///
  /// Returns the extraction directory path.
  /// If [force] is true, re-downloads even if cache is valid.
  Future<String> downloadAndExtract({bool force = false}) async {
    final zip = await _zipFile;
    final extDir = await extractionDir;

    // Check cache
    if (!force && await isCacheValid() && await extDir.exists()) {
      return extDir.path;
    }

    // Download
    final response = await http.get(Uri.parse(gtfsUrl));
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download GTFS data: HTTP ${response.statusCode}',
      );
    }

    // Save ZIP
    await zip.writeAsBytes(response.bodyBytes);

    // Clean extraction directory
    if (await extDir.exists()) {
      await extDir.delete(recursive: true);
    }
    await extDir.create(recursive: true);

    // Extract ZIP
    final archive = ZipDecoder().decodeBytes(response.bodyBytes);
    for (final file in archive) {
      final filePath = '${extDir.path}/${file.name}';
      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }
    }

    return extDir.path;
  }
}
