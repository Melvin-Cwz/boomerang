# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
# meson test -C <build dir>: interface logic (Vala) and the daemon's offline checks (Python).
test_ui = executable('test-ui',
  'test_ui.vala', meson.project_source_root() / 'src' / 'LinkText.vala',
  dependencies: [dependency('glib-2.0'), dependency('gobject-2.0')],
)
test('interface', test_ui)
# Every tests/test_*.py file: a file left out of this list silently stops being run.
python_tests = []
foreach f : run_command('sh', '-c', 'cd "$MESON_SOURCE_ROOT/tests" && ls test_*.py',
                        check: true, env: {'MESON_SOURCE_ROOT': meson.project_source_root()}).stdout().strip().split('\n')
  python_tests += 'tests.' + f.replace('.py', '')
endforeach
test('daemon', python, args: ['-m', 'unittest'] + python_tests,
     workdir: meson.project_source_root(), timeout: 300)
