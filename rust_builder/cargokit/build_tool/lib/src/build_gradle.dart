/// This is copied from Cargokit (which is the official way to use it currently)
/// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'artifacts_provider.dart';
import 'builder.dart';
import 'environment.dart';
import 'options.dart';
import 'target.dart';

final log = Logger('build_gradle');

class BuildGradle {
  BuildGradle({required this.userOptions});

  final CargokitUserOptions userOptions;

  Future<void> build() async {
    final targets = Environment.targetPlatforms
        .map((arch) {
          final target = Target.forFlutterName(arch);
          if (target == null) {
            throw Exception(
              "Unknown darwin target or platform: $arch, ${Environment.darwinPlatformName}",
            );
          }
          return target;
        })
        .toSet()
        .toList();

    final environment = BuildEnvironment.fromEnvironment(isAndroid: true);
    final provider = ArtifactProvider(
      environment: environment,
      userOptions: userOptions,
    );
    final artifacts = await provider.getArtifacts(targets);

    // The output directory is shared by every ABI: a build for one ABI would
    // otherwise leave the previous build's library in the APK, which then
    // claims an ABI it cannot run (an arm64 APK installing on x86_64 and
    // closing at launch).
    final output = Directory(Environment.outputDir);
    if (output.existsSync()) {
      output.deleteSync(recursive: true);
    }

    for (final target in targets) {
      final libs = artifacts[target]!;
      final outputDir = path.join(Environment.outputDir, target.android!);
      Directory(outputDir).createSync(recursive: true);

      for (final lib in libs) {
        if (lib.type == AritifactType.dylib) {
          File(lib.path).copySync(path.join(outputDir, lib.finalFileName));
        }
      }
    }
  }
}
