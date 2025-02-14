@TestOn('vm')
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dart_dev/src/dart_dev_tool.dart';
import 'package:dart_dev/src/tools/format_tool.dart';
import 'package:dart_dev/src/utils/executables.dart' as exe;
import 'package:glob/glob.dart';
import 'package:io/io.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../log_matchers.dart';
import 'shared_tool_tests.dart';

void main() {
  group('FormatTool', () {
    sharedDevToolTests(() => FormatTool());

    test('toCommand overrides the argParser', () {
      final argParser = FormatTool().argParser;
      expect(argParser.options.keys,
          containsAll(['overwrite', 'dry-run', 'check', 'formatter-args']));

      expect(argParser.options['overwrite']!.type, OptionType.flag);
      expect(argParser.options['overwrite']!.abbr, 'w');
      expect(argParser.options['overwrite']!.negatable, isFalse);

      expect(argParser.options['dry-run']!.type, OptionType.flag);
      expect(argParser.options['dry-run']!.abbr, 'n');
      expect(argParser.options['dry-run']!.negatable, isFalse);

      expect(argParser.options['check']!.type, OptionType.flag);
      expect(argParser.options['check']!.abbr, 'c');
      expect(argParser.options['check']!.negatable, isFalse);

      expect(argParser.options['formatter-args']!.type, OptionType.single);
    });

    group('getInputs', () {
      final root = 'test/tools/fixtures/format/globs';

      test('no excludes', () {
        final formatterInputs = FormatTool.getInputs(root: root);
        expect(formatterInputs.includedFiles, unorderedEquals({'.'}));
        expect(formatterInputs.excludedFiles, null);
        expect(formatterInputs.hiddenDirectories, null);
        expect(formatterInputs.skippedLinks, null);
      });

      test('custom excludes', () {
        FormatterInputs formatterInputs =
            FormatTool.getInputs(exclude: [Glob('*_exclude.dart')], root: root);

        expect(
            formatterInputs.includedFiles,
            unorderedEquals({
              'file.dart',
              p.join('links', 'not_link.dart'),
              p.join('lib', 'sub', 'file.dart'),
              'linked.dart',
              p.join('other', 'file.dart'),
            }));

        expect(formatterInputs.excludedFiles,
            unorderedEquals({'should_exclude.dart'}));
        expect(formatterInputs.hiddenDirectories,
            unorderedEquals({'.dart_tool_test'}));
        expect(
            formatterInputs.skippedLinks,
            unorderedEquals(
                {p.join('links', 'lib-link'), p.join('links', 'link.dart')}));
      });

      test('custom excludes with collapseDirectories', () {
        FormatterInputs formatterInputs = FormatTool.getInputs(
          exclude: [Glob('*_exclude.dart')],
          root: root,
          collapseDirectories: true,
        );

        expect(
          formatterInputs.includedFiles,
          unorderedEquals({
            'file.dart',
            'lib',
            'linked.dart',
            'other',
            'links',
          }),
        );

        expect(
          formatterInputs.excludedFiles,
          unorderedEquals({'should_exclude.dart'}),
        );
        expect(
          formatterInputs.hiddenDirectories,
          unorderedEquals({'.dart_tool_test'}),
        );
        expect(formatterInputs.skippedLinks, isEmpty);
      });

      test('empty inputs due to excludes config', () async {
        expect(
            FormatTool.getInputs(exclude: [Glob('**')], root: root)
                .includedFiles,
            isEmpty);
      });

      test('expandCwd forces . to be expanded to all files', () async {
        final formatterInputs =
            FormatTool.getInputs(expandCwd: true, root: root);
        expect(
            formatterInputs.includedFiles,
            unorderedEquals({
              'file.dart',
              p.join('links', 'not_link.dart'),
              p.join('lib', 'sub', 'file.dart'),
              'linked.dart',
              p.join('other', 'file.dart'),
              'should_exclude.dart',
            }));
        expect(formatterInputs.excludedFiles, isEmpty);
      });

      test('followLinks follows linked files and directories', () async {
        final formatterInputs = FormatTool.getInputs(
            expandCwd: true, followLinks: true, root: p.join(root, 'links'));
        expect(
            formatterInputs.includedFiles,
            unorderedEquals({
              p.join('lib-link', 'sub', 'file.dart'),
              'not_link.dart',
              'link.dart',
            }));
        expect(formatterInputs.skippedLinks, isEmpty);
      });
    });
  });

  group('buildArgs', () {
    test('no mode', () {
      expect(buildArgs(['a', 'b'], null), orderedEquals(['a', 'b']));
    });

    test('mode=overwrite', () {
      expect(buildArgs(['a', 'b'], FormatMode.overwrite),
          orderedEquals(['a', 'b', '-w']));
    });

    test('mode=dry-run', () {
      expect(buildArgs(['a', 'b'], FormatMode.dryRun),
          orderedEquals(['a', 'b', '-n']));
    });

    test('mode=check', () {
      expect(buildArgs(['a', 'b'], FormatMode.check),
          orderedEquals(['a', 'b', '-n', '--set-exit-if-changed']));
    });

    test('combines configured args with cli args (in that order)', () {
      final argParser = FormatTool().toCommand('t').argParser;
      final argResults = argParser.parse(['--formatter-args', '--indent 2']);
      expect(
          buildArgs(['a', 'b'], FormatMode.overwrite,
              argResults: argResults,
              configuredFormatterArgs: ['--fix', '--follow-links']),
          orderedEquals([
            'a',
            'b',
            '-w',
            '--fix',
            '--follow-links',
            '--indent',
            '2',
          ]));
    });
  });

  group('buildArgsForDartFormat', () {
    test('no mode', () {
      expect(
          buildArgsForDartFormat(['a', 'b'], null), orderedEquals(['a', 'b']));
    });

    test('mode=dry-run', () {
      expect(buildArgsForDartFormat(['a', 'b'], FormatMode.dryRun),
          orderedEquals(['a', 'b', '-o', 'none']));
    });

    test('mode=check', () {
      expect(buildArgsForDartFormat(['a', 'b'], FormatMode.check),
          orderedEquals(['a', 'b', '-o', 'none', '--set-exit-if-changed']));
    });

    test('combines configured args with cli args (in that order)', () {
      final argParser = FormatTool().toCommand('t').argParser;
      final argResults = argParser.parse(['--formatter-args', '--indent 2']);
      expect(
          buildArgsForDartFormat(['a', 'b'], FormatMode.overwrite,
              argResults: argResults,
              configuredFormatterArgs: ['--fix', '--follow-links']),
          orderedEquals([
            'a',
            'b',
            '--fix',
            '--follow-links',
            '--indent',
            '2',
          ]));
    });
  });

  group('buildExecution', () {
    test('throws UsageException if positional args are given', () {
      final argResults = ArgParser().parse(['a']);
      final context = DevToolExecutionContext(
          argResults: argResults, commandName: 'test_format');
      expect(
          () => buildExecution(context),
          throwsA(isA<UsageException>()
              .having((e) => e.message, 'command name', contains('test_format'))
              .having(
                  (e) => e.message, 'usage', contains('--formatter-args'))));
    });

    test('allows positional arguments when the command is hackFastFormat', () {
      final argParser = FormatTool().toCommand('t').argParser;
      final argResults = argParser.parse(['a/random/path']);
      final context = DevToolExecutionContext(
          argResults: argResults, commandName: 'hackFastFormat');
      final execution = buildExecution(context);
      expect(execution.exitCode, isNull);
      expect(execution.formatProcess!.executable, exe.dartfmt);
      expect(execution.formatProcess!.args, orderedEquals(['a/random/path']));
      expect(execution.formatProcess!.mode, ProcessStartMode.inheritStdio);
      expect(execution.directiveOrganization, isNull);
    });

    test('requires positional arguments when the command is hackFastFormat',
        () {
      final argParser = FormatTool().toCommand('t').argParser;
      final argResults = argParser.parse([]);
      final context = DevToolExecutionContext(
          argResults: argResults, commandName: 'hackFastFormat');
      expect(
          () => buildExecution(context),
          throwsA(isA<UsageException>()
              .having(
                  (e) => e.message, 'command name', contains('hackFastFormat'))
              .having((e) => e.message, 'usage',
                  contains('must specify targets'))));
    });

    test('throws UsageException if args are given after a separator', () {
      final argResults = ArgParser().parse(['--', 'a']);
      final context = DevToolExecutionContext(
          argResults: argResults, commandName: 'test_format');
      expect(
          () => buildExecution(context),
          throwsA(isA<UsageException>()
              .having((e) => e.message, 'command name', contains('test_format'))
              .having(
                  (e) => e.message, 'usage', contains('--formatter-args'))));
    });

    test(
        'returns config exit code and logs if configured formatter is '
        'dart_style but the package is not a direct dependency', () {
      expect(
          Logger.root.onRecord,
          emitsThrough(severeLogOf(allOf(
              contains('Cannot run "dart_style:format"'),
              contains('add "dart_style" to your pubspec.yaml'),
              contains('use "dartfmt" instead')))));

      final context = DevToolExecutionContext();
      final execution = buildExecution(context,
          formatter: Formatter.dartStyle,
          path: 'test/tools/fixtures/format/missing_dart_style');
      expect(execution.exitCode, ExitCode.config.code);
    });

    test('returns a config exit code if inputs list is empty', () {
      expect(
          Logger.root.onRecord,
          emitsThrough(severeLogOf(allOf(
              contains('formatter cannot run because no inputs could be found'),
              contains('tool/dart_dev/config.dart')))));

      final context = DevToolExecutionContext();
      final execution = buildExecution(context,
          exclude: [Glob('**')], path: 'test/tools/fixtures/format/globs');
      expect(execution.exitCode, ExitCode.config.code);
    });

    test('logs the excluded paths and hidden directories', () async {
      var currentLevel = Logger.root.level;
      Logger.root.level = Level.FINE;
      expect(
          Logger.root.onRecord,
          emitsInOrder([
            fineLogOf(allOf(contains('Excluding these paths'),
                contains('should_exclude.dart'))),
            fineLogOf(allOf(contains('Excluding these hidden directories'),
                contains('.dart_tool_test'))),
          ]));

      buildExecution(DevToolExecutionContext(),
          exclude: [Glob('*_exclude.dart')],
          path: 'test/tools/fixtures/format/globs');

      Logger.root.level = currentLevel;
    });

    test('logs the skipped links', () async {
      var currentLevel = Logger.root.level;
      Logger.root.level = Level.FINE;
      expect(
          Logger.root.onRecord,
          emitsInOrder([
            fineLogOf(allOf(contains('Excluding these links'),
                contains('lib-link'), contains('link.dart'))),
          ]));

      buildExecution(DevToolExecutionContext(),
          exclude: [Glob('*_exclude.dart')],
          path: 'test/tools/fixtures/format/globs/links');

      Logger.root.level = currentLevel;
    });

    group('returns a FormatExecution', () {
      test('', () {
        final context = DevToolExecutionContext();
        final execution = buildExecution(context);
        expect(execution.exitCode, isNull);
        expect(execution.formatProcess!.executable, exe.dartfmt);
        expect(execution.formatProcess!.args, orderedEquals(['.']));
        expect(execution.formatProcess!.mode, ProcessStartMode.inheritStdio);
        expect(execution.directiveOrganization, isNull);
      });

      test('that uses defaultMode if no mode flag is given', () {
        final context = DevToolExecutionContext();
        final execution =
            buildExecution(context, defaultMode: FormatMode.dryRun);
        expect(execution.exitCode, isNull);
        expect(execution.formatProcess!.executable, exe.dartfmt);
        expect(execution.formatProcess!.args, orderedEquals(['-n', '.']));
        expect(execution.formatProcess!.mode, ProcessStartMode.inheritStdio);
        expect(execution.directiveOrganization, isNull);
      });

      test('with dartfmt', () {
        final context = DevToolExecutionContext();
        final execution = buildExecution(context, formatter: Formatter.dartfmt);
        expect(execution.exitCode, isNull);
        expect(execution.formatProcess!.executable, exe.dartfmt);
        expect(execution.formatProcess!.args, orderedEquals(['.']));
        expect(execution.formatProcess!.mode, ProcessStartMode.inheritStdio);
        expect(execution.directiveOrganization, isNull);
      });

      test('with dartFormat', () {
        final context = DevToolExecutionContext();
        final execution =
            buildExecution(context, formatter: Formatter.dartFormat);
        expect(execution.exitCode, isNull);
        expect(execution.formatProcess!.executable, exe.dart);
        expect(execution.formatProcess!.args, orderedEquals(['format', '.']));
        expect(execution.formatProcess!.mode, ProcessStartMode.inheritStdio);
      });

      test('with dart_style:format', () {
        final context = DevToolExecutionContext();
        final execution = buildExecution(context,
            formatter: Formatter.dartStyle,
            path: 'test/tools/fixtures/format/has_dart_style');
        expect(execution.exitCode, isNull);
        expect(execution.formatProcess!.executable, exe.dart);
        expect(execution.formatProcess!.args,
            orderedEquals(['run', 'dart_style:format', '.']));
        expect(execution.formatProcess!.mode, ProcessStartMode.inheritStdio);
        expect(execution.directiveOrganization, isNull);
      });

      test('dartfmt with args', () {
        final argParser = FormatTool().toCommand('t').argParser;
        final argResults =
            argParser.parse(['-w', '--formatter-args', '--indent 2']);
        final context = DevToolExecutionContext(argResults: argResults);
        final execution = buildExecution(context,
            configuredFormatterArgs: ['--fix', '--follow-links'],
            formatter: Formatter.dartfmt);
        expect(execution.exitCode, isNull);
        expect(execution.formatProcess!.executable, exe.dartfmt);
        expect(
            execution.formatProcess!.args,
            orderedEquals(
                ['-w', '--fix', '--follow-links', '--indent', '2', '.']));
        expect(execution.formatProcess!.mode, ProcessStartMode.inheritStdio);
        expect(execution.directiveOrganization, isNull);
      });

      test('dartFormat with args', () {
        final argParser = FormatTool().toCommand('t').argParser;
        final argResults = argParser.parse(['--formatter-args', '--indent 2']);
        final context = DevToolExecutionContext(argResults: argResults);
        final execution = buildExecution(context,
            configuredFormatterArgs: ['--fix', '--follow-links'],
            formatter: Formatter.dartFormat);
        expect(execution.exitCode, isNull);
        expect(execution.formatProcess!.executable, exe.dart);
        expect(
            execution.formatProcess!.args,
            orderedEquals(
                ['format', '--fix', '--follow-links', '--indent', '2', '.']));
        expect(execution.formatProcess!.mode, ProcessStartMode.inheritStdio);
      });

      test('and logs the test subprocess by default', () {
        expect(Logger.root.onRecord,
            emitsThrough(infoLogOf(contains('${exe.dartfmt} .'))));

        buildExecution(DevToolExecutionContext());
      });

      test('and logs the test subprocess for dart format', () {
        expect(Logger.root.onRecord,
            emitsThrough(infoLogOf(contains('${exe.dart} format .'))));

        buildExecution(DevToolExecutionContext(),
            formatter: Formatter.dartFormat);
      });

      test('sorts imports when organizeImports is true', () {
        final context = DevToolExecutionContext();
        final execution = buildExecution(context, organizeDirectives: true);
        expect(execution.exitCode, isNull);
        expect(execution.formatProcess, isNotNull);
        expect(execution.directiveOrganization, isNotNull);
        expect(execution.directiveOrganization!.inputs, equals(['.']));
        expect(execution.directiveOrganization!.check, isFalse);
      });

      test('sorts imports in check mode when organizeImports is true', () {
        final context = DevToolExecutionContext();
        final execution = buildExecution(
          context,
          organizeDirectives: true,
          defaultMode: FormatMode.check,
        );
        expect(execution.exitCode, isNull);
        expect(execution.formatProcess, isNotNull);
        expect(execution.directiveOrganization, isNotNull);
        expect(execution.directiveOrganization!.inputs, equals(['.']));
        expect(execution.directiveOrganization!.check, isTrue);
      });
    });
  });

  group('buildFormatProcess', () {
    test('dartfmt', () {
      final process = buildFormatProcess(Formatter.dartfmt);
      expect(process.executable, exe.dartfmt);
      expect(process.args, isEmpty);
    });

    test('dart format', () {
      final process = buildFormatProcess(Formatter.dartFormat);
      expect(process.executable, exe.dart);
      expect(process.args, orderedEquals(['format']));
    });

    test('dart_style', () {
      final process = buildFormatProcess(Formatter.dartStyle);
      expect(process.executable, exe.dart);
      expect(process.args, orderedEquals(['run', 'dart_style:format']));
    });

    test('default', () {
      final process = buildFormatProcess(Formatter.dartfmt);
      expect(process.executable, exe.dartfmt);
      expect(process.args, isEmpty);
    });
  });

  group('logFormatCommand', () {
    test('<=5 inputs and verbose=false', () async {
      expect(Logger.root.onRecord,
          emitsThrough(infoLogOf(contains('dartfmt -x -y a b'))));
      logCommand('dartfmt', ['a', 'b'], ['-x', '-y']);
    });

    test('>5 inputs and verbose=true', () async {
      expect(Logger.root.onRecord,
          emitsThrough(infoLogOf(contains('dartfmt -x -y <6 paths>'))));
      logCommand('dartfmt', ['a', 'b', 'c', 'd', 'e', 'f'], ['-x', '-y']);
    });

    test('>5 inputs and verbose=false', () async {
      expect(Logger.root.onRecord,
          emitsThrough(infoLogOf(contains('dartfmt -x -y a b c d e f'))));
      logCommand('dartfmt', ['a', 'b', 'c', 'd', 'e', 'f'], ['-x', '-y'],
          verbose: true);
    });
  });

  group('validateAndParseMode', () {
    late ArgParser argParser;
    late void Function(String) usageException;

    setUp(() {
      argParser = FormatTool().toCommand('test_format').argParser;
      usageException =
          DevToolExecutionContext(commandName: 'test_format').usageException;
    });

    test('--check and --dry-run and --overwrite throws UsageException', () {
      final argResults =
          argParser.parse(['--check', '--dry-run', '--overwrite']);
      expect(
          () => validateAndParseMode(argResults, usageException),
          throwsA(isA<UsageException>().having((e) => e.message, 'usage footer',
              contains('--check and --dry-run and --overwrite'))));
    });

    test('--check and --dry-run throws UsageException', () {
      final argResults = argParser.parse(['--check', '--dry-run']);
      expect(
          () => validateAndParseMode(argResults, usageException),
          throwsA(isA<UsageException>().having((e) => e.message, 'usage footer',
              contains('--check and --dry-run'))));
    });

    test('--check and --overwrite throws UsageException', () {
      final argResults = argParser.parse(['--check', '--overwrite']);
      expect(
          () => validateAndParseMode(argResults, usageException),
          throwsA(isA<UsageException>().having((e) => e.message, 'usage footer',
              contains('--check and --overwrite'))));
    });

    test('--dry-run and --overwrite throws UsageException', () {
      final argResults = argParser.parse(['--dry-run', '--overwrite']);
      expect(
          () => validateAndParseMode(argResults, usageException),
          throwsA(isA<UsageException>().having((e) => e.message, 'usage footer',
              contains('--dry-run and --overwrite'))));
    });

    test('--check', () {
      final argResults = argParser.parse(['--check']);
      expect(
          validateAndParseMode(argResults, usageException), FormatMode.check);
    });

    test('--dry-run', () {
      final argResults = argParser.parse(['--dry-run']);
      expect(
          validateAndParseMode(argResults, usageException), FormatMode.dryRun);
    });

    test('--overwrite', () {
      final argResults = argParser.parse(['--overwrite']);
      expect(validateAndParseMode(argResults, usageException),
          FormatMode.overwrite);
    });

    test('no mode flag', () {
      final argResults = argParser.parse([]);
      expect(validateAndParseMode(argResults, usageException), isNull);
    });
  });
}
