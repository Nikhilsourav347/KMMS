import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';

const databaseFilename = 'ukm-operations.sembast';

Future<Database> openMillDatabase() async {
  if (kIsWeb) return databaseFactoryWeb.openDatabase(databaseFilename);
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return databaseFactoryIo.openDatabase('${directory.path}/$databaseFilename');
}
