// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/* Interface logic that needs no window: meson test -C build */

void test_states () {
    string[] states = { "off", "unpaired", "bond-lost", "absent", "seen", "classic", "complete" };
    int[] filled = { 0, 0, 3, 0, 1, 2, 3 };
    for (int i = 0; i < states.length; i++) {
        var s = Boomerang.LinkText.describe (states[i], "", "iPhone de Test");
        assert (s.filled == filled[i]);
        assert (s.title != "");
    }
}

void test_every_problem_offers_a_way_out () {
    foreach (var state in new string[] { "off", "unpaired", "bond-lost", "absent" }) {
        var s = Boomerang.LinkText.describe (state, "", "");
        assert (s.action != "" && s.action_label != "");
    }
    var linked = Boomerang.LinkText.describe ("complete", "", "X");
    assert (linked.action == "" && !linked.problem);
}

void test_le_missing_turns_amber () {
    var s = Boomerang.LinkText.describe ("classic", "le-missing", "X");
    assert (s.problem);
    assert (s.action == "pair");
    assert (!s.pending);
    var waiting = Boomerang.LinkText.describe ("classic", "", "X");
    assert (!waiting.problem && waiting.pending);
}

void test_names_and_battery () {
    assert ("Mon iPhone" in Boomerang.LinkText.describe ("complete", "", "Mon iPhone").title);
    assert ("iPhone" in Boomerang.LinkText.describe ("absent", "", "").title);
    assert (Boomerang.LinkText.battery (-1) == "");
    assert (Boomerang.LinkText.battery (82).has_prefix ("82"));
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/link/states", test_states);
    Test.add_func ("/link/way-out", test_every_problem_offers_a_way_out);
    Test.add_func ("/link/le-missing", test_le_missing_turns_amber);
    Test.add_func ("/link/names", test_names_and_battery);
    return Test.run ();
}
