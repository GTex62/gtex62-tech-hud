# Contributing to gtex62-tech-hud

Thanks for your interest!

## How to contribute

1. **Open an Issue** describing the bug/feature. Include OS/Conky version and screenshots if relevant.
1. **Fork** the repo, create a branch:

   ```bash
   git checkout -b feat/your-short-title
   ```

1. **Make changes**:

   * Keep code readable and minimal.
   * Lua/Conky: prefer clear names, avoid hard-coded user paths when possible.
   * Add/update screenshots if a widget’s look changes.
   * Keep secrets out of commits: use `config/*.example` and keep local files in `config/` (see `.gitignore`).

1. **Test locally** on your desktop (Conky X11).
1. **Commit** with a clear message:

   * Example: `fix(net-sys): show (VPN) label while reconnecting`

1. **Open a Pull Request** and link the Issue.

## Project layout

* `widgets/` – widget configs
* `scripts/` – various scripts
* `lua/` – shared Lua helpers
* `config/` – local config files + `.example` templates
* `icons/` – icon assets
* `fonts/` – bundled fonts
* `theme.lua` – fonts/colors/sizes
* `theme-sitrep.lua` – sitrep palette and layout
* `README-pfsense-widget.md` – pfSense widget specifics
* `screenshots/` – small PNGs shown in README

## Reporting bugs

* Include steps to reproduce, logs (if any), and screenshots.

## License

By contributing, you agree your contributions are licensed under the repository’s MIT License.
