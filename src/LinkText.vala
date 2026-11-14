// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 MelvinCwz
/*
 * Words for the daemon's LinkState (LinkStatus.vala and the iPhone's card show them). Plain GLib, so that
 * tests/test_ui.vala checks it without a window.
 */

namespace Boomerang.LinkText {
    /* What to say about one LinkState (see boomerangd/link.py link_state). */
    public class Summary : Object {
        public string title { get; set; default = ""; }
        /* A few words beside the name in the header when there is no battery to show. */
        public string short { get; set; default = ""; }
        public string detail { get; set; default = ""; }
        /* "", "pair", "reconnect" or "bluetooth": the button the popover offers. */
        public string action { get; set; default = ""; }
        public string action_label { get; set; default = ""; }
        /* Segments of the arc to fill (0 to 3), and whether they turn amber. */
        public int filled { get; set; default = 0; }
        public bool problem { get; set; default = false; }
        /* The middle segment breathes: something is happening. */
        public bool pending { get; set; default = false; }
    }

    public Summary describe (string state, string problem, string device) {
        var name = device != "" ? device : "iPhone";
        var s = new Summary ();
        switch (state) {
        case "off":
            s.title = _("Bluetooth éteint");
            s.short = _("Bluetooth éteint");
            s.detail = _("Allumez le Bluetooth de ce PC pour retrouver l'iPhone.");
            s.action = "bluetooth";
            s.action_label = _("Paramètres Bluetooth…");
            break;
        case "unpaired":
            s.title = _("Aucun iPhone relié");
            s.short = _("non appairé");
            s.detail = _("L'appairage se fait depuis l'iPhone, dans Réglages › Bluetooth. Boomerang vous guide.");
            s.action = "pair";
            s.action_label = _("Appairer un iPhone…");
            break;
        case "bond-lost":
            s.title = _("L'iPhone ne reconnaît plus ce PC");
            s.short = _("à appairer de nouveau");
            s.detail = _("L'appairage a été supprimé sur l'iPhone. Appairez de nouveau les deux appareils.");
            s.action = "pair";
            s.action_label = _("Appairer de nouveau…");
            s.filled = 3;
            s.problem = true;
            break;
        case "seen":
            s.title = _("%s à proximité").printf (name);
            s.short = _("connexion…");
            s.detail = _("Connexion en cours…");
            s.filled = 1;
            s.pending = true;
            break;
        case "classic":
            if (problem == "le-missing") {
                s.title = _("Notifications interrompues");
                s.short = _("notifications interrompues");
                s.detail = _("L'iPhone est relié mais n'envoie pas ses notifications. Vérifiez « Partager "
                           + "les notifications système » dans Réglages › Bluetooth sur l'iPhone, sinon "
                           + "appairez-le de nouveau.");
                s.action = "pair";
                s.action_label = _("Appairer de nouveau…");
                s.filled = 2;
                s.problem = true;
            } else {
                s.title = _("%s relié").printf (name);
                s.detail = _("Les notifications arrivent dans un instant.");
                s.filled = 2;
                s.pending = true;
            }
            break;
        case "complete":
            s.title = _("%s relié").printf (name);
            s.filled = 3;
            break;
        default:  // "absent"
            s.title = _("%s hors de portée").printf (name);
            s.short = _("hors de portée");
            s.detail = _("Boomerang le reconnecte dès qu'il revient près du PC.");
            s.action = "reconnect";
            s.action_label = _("Reconnecter maintenant");
            break;
        }
        return s;
    }

    /* Battery for the header: "82 %", or "" when unknown. */
    public string battery (int level) {
        return level >= 0 ? _("%d %%").printf (level) : "";
    }
}
