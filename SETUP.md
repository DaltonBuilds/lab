# Development Environment Setup

This repository contains dotfiles and configuration for a reproducible development environment across bare metal machines and devcontainers.

## Architecture

- **chezmoi**: Manages dotfiles and downloads baseline tools via externals
- **mise**: Version manager and tool installer for CLI utilities
- **DevPod**: Creates and manages devcontainers with dotfiles pre-configured

## Quick Start

### On a New Machine (Bare Metal)

Run this one command to bootstrap your environment:

```bash
sh -c "$(curl -fsLS https://raw.githubusercontent.com/DaltonBuilds/dotfiles/main/setup)"
```

This will:
1. Install chezmoi
2. Clone this dotfiles repo
3. Apply all dotfiles to your home directory
4. Download mise and other baseline tools
5. Install mise-managed tools (starship, ripgrep, fd, bat)

### In DevPod Devcontainers

Configure DevPod to automatically inject these dotfiles into every devcontainer:

1. **Set dotfiles repository**:
   ```bash
   devpod context set-options \
     --option DOTFILES_URL=git@github.com:DaltonBuilds/dotfiles.git \
     --option DOTFILES_SCRIPT=install.sh
   ```

2. **Alternative: Use DevPod UI**
   - Open DevPod settings
   - Navigate to "Dotfiles" section
   - Set repository: `git@github.com:DaltonBuilds/dotfiles.git`
   - Set install script: `install.sh`

Now every devcontainer DevPod creates will automatically:
- Clone your dotfiles
- Run `install.sh` to bootstrap the environment
- Have all your baseline tools available (chezmoi, mise, ripgrep, fd, bat, starship)

## Baseline Tools

These tools are available in every environment:

- **chezmoi**: Dotfile manager
- **mise**: Version/tool manager
- **starship**: Shell prompt
- **ripgrep**: Fast grep alternative
- **fd**: Fast find alternative
- **bat**: Cat with syntax highlighting

## Adding Project-Specific Tools

In any project, create a `.mise.toml` file:

```toml
[tools]
node = "20"
python = "3.12"
terraform = "latest"
```

Mise will automatically install these when you enter the project directory.

## Customization

### Adding New Baseline Tools

**Option 1: Via mise (recommended for tools supported by mise)**

Edit `dot_config/mise/config.toml`:
```toml
[tools]
your-tool = "latest"
```

**Option 2: Via chezmoi externals (for any downloadable binary)**

Create `.chezmoiexternals/your-tool.toml`:
```toml
[".local/bin/your-tool"]
type = "file"
executable = true
url = "https://example.com/your-tool-{{.chezmoi.os}}-{{.chezmoi.arch}}"
```

### Adding New Dotfiles

Add files to this repo with the `dot_` prefix:
- `dot_bashrc` → `~/.bashrc`
- `dot_config/` → `~/.config/`

Commit and push, then run `chezmoi update` to apply.

## Testing Your Setup

### Test bare metal bootstrap

```bash
# In a fresh environment (or Docker container)
sh -c "$(curl -fsLS https://raw.githubusercontent.com/DaltonBuilds/dotfiles/main/setup)"

# Verify tools are available
chezmoi --version
mise --version
rg --version
```

### Test devcontainer bootstrap

```bash
# Create a test devcontainer with DevPod
devpod up ./test-project

# Verify dotfiles were applied
devpod ssh test-project
chezmoi --version
mise list
```

## How It Works

### Bootstrap Flow (Bare Metal)

```
curl setup script → install chezmoi → clone repo → apply dotfiles
                                                         ↓
                    mise binary downloaded ← chezmoi externals processed
                                    ↓
                         mise installs tools (starship, ripgrep, etc.)
```

### Bootstrap Flow (Devcontainer)

```
DevPod creates container → clones dotfiles repo → runs install.sh
                                                         ↓
                    install chezmoi → apply dotfiles (from local clone)
                                              ↓
                    mise binary installed → mise installs tools
```

## Troubleshooting

### Mise not activating

Check that your shell RC file (`.bashrc`, `.zshrc`) contains:
```bash
eval "$(mise activate bash)"  # or 'zsh'
```

### Tools not found after bootstrap

Ensure `~/.local/bin` is in your PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Devcontainer not getting dotfiles

Verify DevPod dotfiles configuration:
```bash
devpod context options | grep DOTFILES
```

## Repository Structure

```
.
├── .chezmoi.toml.tmpl       # Chezmoi config (OS detection)
├── .chezmoiexternals/       # Binary downloads (mise, chezmoi)
│   ├── mise.toml
│   └── chezmoi.toml
├── dot_bashrc               # Bash configuration
├── dot_config/              # XDG config files
│   ├── mise/
│   │   └── config.toml      # Global mise tools
│   ├── starship.toml
│   └── ghostty/
├── dot_vimrc                # Vim configuration
├── setup                    # Bare metal bootstrap script
├── install.sh               # Devcontainer bootstrap script
└── SETUP.md                 # This file
```
