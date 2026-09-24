import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../bin/skills.dart';

void main() {
  late Directory tempDir;
  late Uri skillsRoot;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('shader_fun_skills_test_');
    skillsRoot = Directory.current.uri.resolve('skills/');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Agent Skills installer', () {
    test('discovers all bundled skills and defaults to .agents home', () async {
      final plan = await planSkillInstall(
        projectRoot: tempDir,
        skillsRoot: skillsRoot,
      );

      expect(plan.action, SkillInstallAction.install);
      expect(plan.homes, ['.agents/skills']);
      expect(plan.skillNames.length, 10);
      expect(plan.installCount, 10);
      expect(plan.updateCount, 0);
      expect(plan.skillNames, contains('shader-fun-idioms'));
      expect(plan.skillNames, contains('shader-fun-setup'));
      expect(plan.skillNames, contains('shader-fun-controller'));
      expect(plan.skillNames, contains('shader-fun-uniforms'));
      expect(plan.skillNames, contains('shader-fun-viewport'));
      expect(plan.skillNames, contains('shader-fun-multipass'));
      expect(plan.skillNames, contains('shader-fun-channels'));
      expect(plan.skillNames, contains('shader-fun-audio'));
      expect(plan.skillNames, contains('shader-fun-gpu-sound'));
      expect(plan.skillNames, contains('shader-fun-projects'));
    });

    test(
      'installs all skills into default .agents/skills and is idempotent',
      () async {
        final result = await installSkills(
          projectRoot: tempDir,
          skillsRoot: skillsRoot,
        );

        expect(
          result,
          contains(
            'Installed 10 shader_fun agent skills into .agents/skills.',
          ),
        );

        for (final skillName in [
          'shader-fun-idioms',
          'shader-fun-setup',
          'shader-fun-controller',
          'shader-fun-uniforms',
          'shader-fun-viewport',
          'shader-fun-multipass',
          'shader-fun-channels',
          'shader-fun-audio',
          'shader-fun-gpu-sound',
          'shader-fun-projects',
        ]) {
          final skillFile = File.fromUri(
            tempDir.uri.resolve('.agents/skills/$skillName/SKILL.md'),
          );
          expect(
            skillFile.existsSync(),
            isTrue,
            reason: '$skillName/SKILL.md should exist',
          );
        }

        // Subsequent plan should be upToDate
        final planAfter = await planSkillInstall(
          projectRoot: tempDir,
          skillsRoot: skillsRoot,
        );
        expect(planAfter.action, SkillInstallAction.upToDate);
        expect(planAfter.installCount, 0);
        expect(planAfter.updateCount, 0);
      },
    );

    test('installs into all present agent homes', () async {
      // Create .claude and .cursor directories in the project root
      Directory.fromUri(tempDir.uri.resolve('.claude/')).createSync();
      Directory.fromUri(tempDir.uri.resolve('.cursor/')).createSync();

      final plan = await planSkillInstall(
        projectRoot: tempDir,
        skillsRoot: skillsRoot,
      );

      expect(plan.homes, ['.claude/skills', '.cursor/skills']);

      await installSkills(projectRoot: tempDir, skillsRoot: skillsRoot);

      final claudeSkill = File.fromUri(
        tempDir.uri.resolve('.claude/skills/shader-fun-idioms/SKILL.md'),
      );
      final cursorSkill = File.fromUri(
        tempDir.uri.resolve('.cursor/skills/shader-fun-idioms/SKILL.md'),
      );
      expect(claudeSkill.existsSync(), isTrue);
      expect(cursorSkill.existsSync(), isTrue);

      // .agents should not be created when other agent homes exist
      final agentsDir = Directory.fromUri(tempDir.uri.resolve('.agents/'));
      expect(agentsDir.existsSync(), isFalse);
    });

    test('detects stale versions and updates them', () async {
      await installSkills(projectRoot: tempDir, skillsRoot: skillsRoot);

      // Modify one installed skill to have version: 0
      final file = File.fromUri(
        tempDir.uri.resolve('.agents/skills/shader-fun-idioms/SKILL.md'),
      );
      final content = file.readAsStringSync().replaceFirst(
        RegExp(r'version:\s*\d+'),
        'version: 0',
      );
      file.writeAsStringSync(content);

      final plan = await planSkillInstall(
        projectRoot: tempDir,
        skillsRoot: skillsRoot,
      );

      expect(plan.action, SkillInstallAction.update);
      expect(plan.updateCount, 1);
      expect(
        describeSkillPlan(plan),
        contains(
          '1 shader_fun agent skill(s) have a newer version available',
        ),
      );

      // Re-installing updates it
      await installSkills(projectRoot: tempDir, skillsRoot: skillsRoot);

      final planAfter = await planSkillInstall(
        projectRoot: tempDir,
        skillsRoot: skillsRoot,
      );
      expect(planAfter.action, SkillInstallAction.upToDate);
    });
  });
}
