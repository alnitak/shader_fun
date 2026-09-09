export 'compile_process_stub.dart'
    if (dart.library.io) 'compile_process_io.dart'
    if (dart.library.js_interop) 'compile_process_web.dart';
