// ignore_for_file: depend_on_referenced_packages
import 'package:hooks/hooks.dart';
import 'package:shader_fun/build_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderFunBundles(buildInput: input, buildOutput: output);
  });
}
