import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dcli/dcli.dart' as dcli;
import 'package:enigma/src/constants/app_constants.dart';
import 'package:enigma/src/extension/string_extension.dart';
import 'package:enigma/src/json_to_dart/model_generator.dart';
import 'package:enigma/src/model/new_entity.dart';
import 'package:enigma/src/services/directory_service.dart';
import 'package:enigma/src/services/file_service.dart';
import 'package:enigma/src/services/input_service.dart';
import 'package:enigma/src/services/script_service.dart';
import 'package:mason_logger/mason_logger.dart';

Future<void> addEntityAction() async {
  // Check if the Dart version is in the correct range
  if (!await ScriptService.isDartVersionInRange('3.0.0', '4.0.0')) {
    stdout.writeln(dcli.red(AppConstants.kUpdateDartVersion));
    return;
  }

  // Create a new logger
  final Logger logger = Logger();
  final String currentPath = Directory.current.path;
  final String dataDirPath = '$currentPath/data/lib/';
  final String domainDirPath = '$currentPath/domain/lib/';

  String jsonData = '';
  while (jsonData.isEmpty) {
    try {
      final String data = InputService.getMultilineInput(
        'Enter json for class generation (ex: {"name" : "Ivan", ...}) : ',
      );
      jsonData = jsonEncode(jsonDecode(data));
    } catch (e) {
      stdout.writeln(dcli.red('Invalid JSON data'));
    }
  }

  final List<String> generatedClass = ModelGenerator.generateDartClasses(
    className: 'Main',
    rawJson: '$jsonData',
  );

  final List<NewEntity> models = <NewEntity>[];
  for (int i = 0; i < generatedClass.length; i++) {
    final String name = InputService.getValidatedInput(
          stdoutMessage:
              'Enter entity name for class (without entity postfix ex: "test data" or "TestData" or "test_data") \n '
              '${generatedClass[i]}'
              ': ',
          errorMessage: AppConstants.kData,
          functionValidator: (String? value) => value?.isNotEmpty,
        ) ??
        '';
    models.add(NewEntity(
      className: name.toCamelCase(),
      fileName: name.snakeCase(),
      rawClass: generatedClass[i],
    ));
  }

  for (int i = 0; i < models.length; i++) {
    NewEntity newModel = models[i].copyWith(
      isNeedToCreateModel: logger.chooseOne(
        'Create Model and Mapper?',
        choices: <String?>[
          AppConstants.kYes,
          AppConstants.kNo,
        ],
      ).toBool(),
      isNeedToAddHive: logger.chooseOne(
        'Add Hive to entity?',
        choices: <String?>[
          AppConstants.kYes,
          AppConstants.kNo,
        ],
      ).toBool(),
    );

    newModel = newModel.copyWith(
      hiveTypeId: newModel.isNeedToAddHive
          ? InputService.getValidatedInput(
              stdoutMessage: 'Enter Hive Type Id: ',
              errorMessage: AppConstants.kData,
              functionValidator: (String? value) => value?.isNotEmpty,
            ).toInt()
          : 0,
    );
    models.replaceRange(i, i + 1, <NewEntity>[newModel]);
  }

  for (int i = 0; i < models.length; i++) {
    NewEntity model = models[i];

    final String entityContent = '''
      import 'package:freezed_annotation/freezed_annotation.dart';
      ${model.isNeedToAddHive ? "import 'package:hive/hive.dart';" : ""}

      part '${model.fileName}_entity.freezed.dart';
      part '${model.fileName}_entity.g.dart';

      @freezed
      ${model.isNeedToAddHive ? "@HiveType(typeId: ${model.hiveTypeId})" : ""}
      class ${model.className}Entity with _\$${model.className}Entity {
        const factory ${model.className}Entity({
          ${model.classFields.map((ClassField e) => e.getFieldString(
              i: model.classFields.indexOf(e) + 1,
              isEntity: true,
              isNeedHive: model.isNeedToAddHive,
              otherModels: models,
            )).toList().join()}
        }) = _${model.className}Entity;

        factory ${model.className}Entity.fromJson(Map<String, dynamic> json) => _\$${model.className}EntityFromJson(json);
      }
      ''';

    final String mapperContent = '''
      import 'package:domain/domain.dart';
      import '../entities/entities.dart';
      
      abstract class ${model.className}Mapper {
        static ${model.className}Model toModel(${model.className}Entity entity) {
          return ${model.className}Model(
             ${model.classFields.map((ClassField e) => e.getMapperString(
              isEntity: true,
              otherModels: models,
            )).toList().join()}
          );
        }
      
        static ${model.className}Entity toEntity(${model.className}Model model) {
          return ${model.className}Entity(
             ${model.classFields.map((ClassField e) => e.getMapperString(
              otherModels: models,
            )).toList().join()}
          );
        }
      }
    ''';

    final String modelContent = '''
    import 'package:freezed_annotation/freezed_annotation.dart';

    part '${model.fileName}_model.freezed.dart';
    
    @freezed
    class ${model.className}Model with _\$${model.className}Model {
      factory ${model.className}Model({
         ${model.classFields.map((ClassField e) => e.getFieldString(
              i: model.classFields.indexOf(e) + 1,
              otherModels: models,
            )).toList().join()}
      }) = _${model.className}Model;
    }
    ''';
    final File entityFile = File('${dataDirPath}entities/${model.fileName}_entity.dart');
    final File mapperFile = File('${dataDirPath}mapper/${model.fileName}_mapper.dart');
    final File modelFile = File('${domainDirPath}models/${model.fileName}_model.dart');

    if (!entityFile.existsSync()) {
      entityFile.createSync(recursive: true);
      entityFile.writeAsStringSync(entityContent);
      await FileService.addToFile(
          "export '${model.fileName}_entity.dart';", '${dataDirPath}entities/entities.dart');
    }
    if (model.isNeedToCreateModel) {
      if (!mapperFile.existsSync()) {
        mapperFile.createSync(recursive: true);
        mapperFile.writeAsStringSync(mapperContent);
        await FileService.addToFile(
            "export '${model.fileName}_mapper.dart';", '${dataDirPath}mapper/mappers.dart');
      }
      if (!modelFile.existsSync()) {
        modelFile.createSync(recursive: true);
        modelFile.writeAsStringSync(modelContent);
        await FileService.addToFile(
            "export '${model.fileName}_model.dart';", '${domainDirPath}models/models.dart');
      }
    }
  }

  stdout.writeln(dcli.green('✅ Create Successfully!'));
  stdout.writeln(dcli.green('✅ Start build!'));
  await ScriptService.flutterBuild('$dataDirPath');
  await ScriptService.flutterBuild('$domainDirPath');
  stdout.writeln(dcli.green('✅ Build Successfully!'));

  stdout.writeln(dcli.green('✅ Finish Successfully!'));
}
