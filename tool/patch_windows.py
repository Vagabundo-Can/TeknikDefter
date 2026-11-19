"""Adds the handwriting recognition channel to the Windows runner after flutter create."""
import re, shutil, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
runner = root / 'windows' / 'runner'
for f in ('ink_recognizer.h', 'ink_recognizer.cpp'):
    shutil.copy(root / 'tool' / 'windows' / f, runner / f)

fw = runner / 'flutter_window.cpp'
s = fw.read_text(encoding='utf-8')
if 'ink_recognizer.h' not in s:
    s = s.replace('#include "flutter/generated_plugin_registrant.h"', '#include "flutter/generated_plugin_registrant.h"\n#include "ink_recognizer.h"')
    s = s.replace('RegisterPlugins(flutter_controller_->engine());', 'RegisterPlugins(flutter_controller_->engine());\n  RegisterInkChannel(flutter_controller_->engine(), GetHandle());', 1)
    s = re.sub(r'(FlutterWindow::MessageHandler\(HWND hwnd, UINT const message,\s*WPARAM const wparam,\s*LPARAM const lparam\) noexcept \{)',
               r'\1\n  if (message == WM_TD_INK) {\n    InkOnPosted(lparam);\n    return 0;\n  }', s, count=1)
    assert 'InkOnPosted' in s and 'RegisterInkChannel' in s, 'flutter_window.cpp patch failed'
    fw.write_text(s, encoding='utf-8')

cm = runner / 'CMakeLists.txt'
c = cm.read_text(encoding='utf-8')
if 'ink_recognizer.cpp' not in c:
    c = c.replace('"flutter_window.cpp"', '"flutter_window.cpp"\n  "ink_recognizer.cpp"', 1)
    c += '\n# Handwriting recognition (C++/WinRT)\ntarget_link_libraries(${BINARY_NAME} PRIVATE windowsapp)\nset_source_files_properties(ink_recognizer.cpp PROPERTIES COMPILE_OPTIONS "/WX-;/W3;/EHsc;/utf-8")\n'
    assert 'ink_recognizer.cpp' in c
    cm.write_text(c, encoding='utf-8')
print('Windows runner patched')
