# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
config_vala = configure_file(input: 'Config.vala.in', output: 'Config.vala', configuration: conf)

# Built once per Granite found: Granite 9 (elementary OS 9) and Granite 7 (elementary OS 8).
# One package then serves both systems; src/launcher.in picks the build at start.
granite9_dep = dependency('granite-9', required: false)
granite7_dep = dependency('granite-7', version: '>= 7.7', required: not granite9_dep.found())

app_sources = files(
  'About.vala',
  'AppChoice.vala',
  'Application.vala',
  'AppWindow.vala',
  'Avatar.vala',
  'BubbleDiff.vala',
  'CallWindow.vala',
  'CallsView.vala',
  'Components.vala',
  'ComposeField.vala',
  'ContactEditor.vala',
  'ContactsView.vala',
  'ContributorsView.vala',
  'Daemon.vala',
  'FeedView.vala',
  'MainWindow.vala',
  'PageColumn.vala',
  'MessagesView.vala',
  'ConversationDetails.vala',
  'MessagesOptions.vala',
  'ConversationExport.vala',
  'NotificationsView.vala',
  'NowPlayingView.vala',
  'OneTimeCodes.vala',
  'SoundsCard.vala',
  'FreeSounds.vala',
  'Updates.vala',
  'HotspotProximity.vala',
  'WebShortcuts.vala',
  'WhatsNew.vala',
  'IndicatorSetting.vala',
  'InstallBox.vala',
  'FilesView.vala',
  'MirrorView.vala',
  'PhotosView.vala',
  'DriveOptions.vala',
  'HeadphonesView.vala',
  'ModuleRow.vala',
  'OptionalAppRow.vala',
  'PairingDialog.vala',
  'QuickReply.vala',
  'SetupParts.vala',
  'Onboarding.vala',
  'ServicesView.vala',
  'Sidebar.vala',
  'LinkText.vala',
  'LinkStatus.vala',
  'ModulesView.vala',
  'ThreadStyle.vala',
  'PhoneGuide.vala',
  'Guide.vala',
  'Language.vala',
  'Style.vala',
)
app_deps = [
  dependency('gio-2.0'),
  dependency('gtk4'),
  dependency('pangocairo'),
  dependency('cairo'),
  meson.get_compiler('c').find_library('m', required: false),
]
if granite9_dep.found()
  executable('boomerang-granite9', config_vala, app_sources, vala_args: ['--define=GRANITE9'],
             dependencies: app_deps + [granite9_dep], install: true, install_dir: pkglibexecdir)
endif
if granite7_dep.found()
  executable('boomerang-granite7', config_vala, app_sources,
             dependencies: app_deps + [granite7_dep], install: true, install_dir: pkglibexecdir)
endif
configure_file(input: 'launcher.in', output: app_id, configuration: conf,
               install: true, install_dir: bindir, install_mode: 'rwxr-xr-x')

# The bubble redraw decision (MessagesView), checked on its own: meson test -C <build>
test('bubble-diff', executable('test-bubble-diff', 'BubbleDiff.vala',
                               meson.project_source_root() / 'tests' / 'test_bubble_diff.vala',
                               dependencies: dependency('glib-2.0'), install: false))
