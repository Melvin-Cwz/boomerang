/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 MelvinCwz
 */

/**
 * The app's style sheets name elementary's colours the Granite 7 way (@accent_color,
 * @fg_color, @LIME_500…). Granite 9 no longer defines those names: its own sheet works
 * with CSS variables (--accent-color, --LIME-500…). colors () rewrites a sheet for the
 * Granite the app is built with, so one sheet serves elementary OS 8 and 9.
 */
namespace Boomerang.Style {
#if GRANITE9
    private static Regex? palette = null;
    private static Regex? named = null;
#endif

    public static string colors (string css) {
#if GRANITE9
        try {
            if (palette == null) {
                // @LIME_500 → var(--LIME-500)
                palette = new Regex ("@([A-Z]+)_([0-9]{3})\\b");
                // @accent_color, @fg_color, @base_color, @selected_bg_color… → var(--accent-color)…
                named = new Regex ("@([a-z]+(?:_[a-z]+)*_color)\\b");
            }
            var step = palette.replace (css, -1, 0, "var(--\\1-\\2)");
            return named.replace_eval (step, -1, 0, 0, (info, result) => {
                result.append ("var(--%s)".printf (info.fetch (1).replace ("_", "-")));
                return false;
            });
        } catch (RegexError e) {
            warning ("style: %s", e.message);
            return css;
        }
#else
        return css;
#endif
    }
}
