# Setting up a new MacBook with `brew bundle` + `chezmoi`

A common question when provisioning a new Mac: how do you avoid re-installing iTerm, oh-my-zsh, Zoom, and friends by hand every time? The notes below capture the approach this repo implements.

The simplest answer is to treat new-Mac setup as **declarative**: put apps and CLI tools in a `Brewfile`, keep shell config in dotfiles, and run one bootstrap script on a fresh machine. Homebrew Bundle is built for exactly this, and it can install formulae, casks, Mac App Store apps, VS Code extensions, and more from a single file.

## Recommended setup

Use `brew bundle` for installs and `chezmoi` for dotfiles and setup scripts. Homebrew Bundle gives you a single `Brewfile` to describe desired packages, while chezmoi can run scripts when files change and is documented to work well with `brew bundle` on macOS.

`iterm2` and `zoom` go in the `Brewfile` as casks; `.zshrc`, terminal settings, aliases, and other repeated shell config live in dotfiles.

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

Then add a bootstrap script like this so a new Mac needs only one command after Homebrew is installed:

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

If you want full workstation provisioning across multiple Macs, Ansible is also a valid option on macOS and can manage Homebrew formulae and casks like `iterm2`, `zoom`, `docker`, and `slack`. For one developer laptop, though, `Brewfile + chezmoi` is usually the lighter and faster starting point.

A reasonable starting point: create `Brewfile`, `bootstrap.sh`, and a chezmoi-managed dotfiles tree — the rest of this repo is one implementation of that pattern.
