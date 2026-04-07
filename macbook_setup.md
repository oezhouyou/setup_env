<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# for setup a new macbook, there are lots of repeated work, such as install iterm, ohmyzsh, zoom etc. Anyway to combine them to a config file and auto exec during new laptop setup?

Yes — the simplest way is to treat new-Mac setup as **declarative**: put apps and CLI tools in a `Brewfile`, keep shell config in dotfiles, and run one bootstrap script on a fresh machine. Homebrew Bundle is built for exactly this, and it can install formulae, casks, Mac App Store apps, VS Code extensions, and more from a single file.

## Recommended setup

For your case, I’d use `brew bundle` for installs and `chezmoi` for dotfiles and setup scripts. Homebrew Bundle gives you a single `Brewfile` to describe desired packages, while chezmoi can run scripts when files change and is documented to work well with `brew bundle` on macOS.

That maps cleanly to what you mentioned: `iterm2` and `zoom` go in the `Brewfile` as casks, while `.zshrc`, terminal settings, aliases, and other repeated shell config live in dotfiles. You already use Homebrew and zsh-related tooling on macOS, so this approach matches your current setup style well.

## What the files look like

A minimal `Brewfile` can look like this:

```ruby
tap "homebrew/cask"

brew "git"
brew "gh"
brew "fzf"
brew "ripgrep"

cask "iterm2"
cask "zoom"
cask "google-chrome"
cask "visual-studio-code"
```

Then add a bootstrap script like this so a new Mac needs only one command after Homebrew is installed:[^1]

```bash
#!/bin/bash
set -e

brew bundle --file="$HOME/.Brewfile"
chezmoi init https://github.com/yourname/dotfiles.git
chezmoi apply
```


## Good workflow

On your current Mac, you can generate a starting point with `brew bundle dump --global --force`, which writes your installed Homebrew packages into a global `Brewfile`. After that, reinstalling on a new machine is as simple as `brew bundle --global`, and `brew bundle check || brew bundle install` is the documented pattern for scripts.

If you use App Store apps, Homebrew Bundle also supports `mas` entries in the same file, so one config can cover both regular apps and App Store installs. It also supports services, `uv` tools, Cargo packages, Go packages, and VS Code extensions, which makes it useful beyond just GUI apps.

## Best structure

Use this split so the setup stays maintainable:

- `Brewfile`: install apps and CLI tools.
- Dotfiles repo: `.zshrc`, git config, terminal config, aliases, editor settings.
- `chezmoi` scripts: machine bootstrap steps that should rerun when config changes.
- One `bootstrap.sh`: install Homebrew, then run `brew bundle` and `chezmoi apply`.

Chezmoi’s macOS guide specifically shows embedding a Brewfile inside a `run_onchange_` script, which means package installs can stay tied to config updates instead of being a separate manual step. A practical pattern is: install Homebrew once, then let chezmoi own ongoing setup.

## When to use Ansible

If you want full workstation provisioning across multiple Macs, Ansible is also a valid option on macOS and can manage Homebrew formulae and casks like `iterm2`, `zoom`, `docker`, and `slack`. For one developer laptop, though, `Brewfile + chezmoi` is usually the lighter and faster starting point.[^2]

A good next step is to create these three files first: `~/.Brewfile`, `~/.local/bin/bootstrap.sh`, and a dotfiles repo managed by chezmoi. Would you like a ready-to-use starter repo layout for your MacBook setup?
<span style="display:none">[^10][^11][^12][^13][^14][^15][^3][^4][^5][^6][^7][^8][^9]</span>

<div align="center">⁂</div>

[^1]: https://carloscuesta.me/blog/automated-macos-dev-setup

[^2]: https://oneuptime.com/blog/post/2026-02-21-ansible-manage-homebrew-packages-macos/view

[^3]: https://docs.brew.sh/Brew-Bundle-and-Brewfile

[^4]: https://www.caseyliss.com/2019/10/8/brew-bundle

[^5]: https://gist.github.com/ChristopherA/a579274536aab36ea9966f301ff14f3f

[^6]: https://docs.brew.sh/Manpage

[^7]: https://github.com/Lissy93/Brewfile

[^8]: https://chezmoi.io/user-guide/machines/macos/

[^9]: https://oneuptime.com/blog/post/2026-02-21-install-ansible-macos-homebrew/view

[^10]: https://amanhimself.dev/blog/using-mas-with-homebrew/

[^11]: https://www.thushanfernando.com/2022/08/managing-macos-with-brew-bundle-brewfile/

[^12]: https://natelandau.com/managing-dotfiles-with-chezmoi/

[^13]: https://formulae.brew.sh/formula/ansible

[^14]: https://www.youtube.com/watch?v=-VP2NVv3LHg

[^15]: https://github.com/twpayne/chezmoi/discussions/3774

