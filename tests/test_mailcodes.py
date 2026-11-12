# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
from boomerangd.mailcodes import is_mail


def test_mail_apps_only():
    assert is_mail("Thunderbird", "", "Votre code : 482913")
    assert is_mail("Lucarne", "fr.melvincouwez.lucarne", "")
    assert is_mail("Google Chrome", "google-chrome", "Gmail\nCode de vérification 482913")
    assert not is_mail("Discord", "discord", "code 482913")
    assert not is_mail("Google Chrome", "google-chrome", "YouTube : nouvelle vidéo")
