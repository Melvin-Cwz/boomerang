# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
config_vala = configure_file(input: 'Config.vala.in', output: 'Config.vala', configuration: conf)

# Granite 9 (elementary OS 9) when present, else Granite 7 (elementary OS 8).
granite_dep = dependency('granite-9', required: false)
if granite_dep.found()
  add_project_arguments('--define=GRANITE9', language: 'vala')
else
  granite_dep = dependency('granite-7', version: '>= 7.7')
endif

executable(app_id,
  config_vala,
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
  dependencies: [
    dependency('gio-2.0'),
    dependency('gtk4'),
    dependency('pangocairo'),
    dependency('cairo'),
    granite_dep,
    meson.get_compiler('c').find_library('m', required: false),
  ],
  install: true,
)

# The bubble redraw decision (MessagesView), checked on its own: meson test -C <build>
test('bubble-diff', executable('test-bubble-diff', 'BubbleDiff.vala',
                               meson.project_source_root() / 'tests' / 'test_bubble_diff.vala',
                               dependencies: dependency('glib-2.0'), install: false))
