# Automation Strategies for DevPod & Devcontainer Workflows

This document contains automation ideas to streamline project creation and DevPod configuration. Test your workflow first, then implement the automations that make sense for your use case.

## Problem Statements

1. **DevPod Configuration**: Need to set `DOTFILES_URL` and `DOTFILES_SCRIPT` options on every new machine
2. **Devcontainer Scaffolding**: Need to create `.devcontainer/devcontainer.json` for every new project
3. **Template Management**: Want consistent devcontainer configs across projects

---

## Strategy 1: Automate DevPod Configuration in Setup Script

**When to use:** You want new machines to be fully configured in one command

### Implementation

Add to `setup` script after the mise install section:

```bash
# Configure DevPod dotfiles integration if DevPod is installed
if command -v devpod >/dev/null 2>&1; then
    echo "⚙️  Configuring DevPod dotfiles integration..."
    devpod context set-options \
      --option DOTFILES_URL=git@github.com:DaltonBuilds/dotfiles.git \
      --option DOTFILES_SCRIPT=install.sh
    echo "✅ DevPod configured!"
else
    echo "ℹ️  DevPod not found - skipping DevPod configuration"
    echo "   Install DevPod later and run: devpod context set-options --option DOTFILES_URL=git@github.com:DaltonBuilds/dotfiles.git --option DOTFILES_SCRIPT=install.sh"
fi
```

### Pros & Cons

✅ One-command bootstrap includes DevPod setup
✅ Don't forget this step on new machines
⚠️ Requires DevPod to be installed first (gracefully skips if not)
⚠️ Only runs once during initial setup (re-run setup if you change options)

---

## Strategy 2: Manage DevPod Config Files with Chezmoi

**When to use:** You want DevPod config versioned and synced across machines (advanced)

### How It Works

DevPod stores configuration in files (typically `~/.devpod/` or similar). You can manage these with chezmoi.

### Implementation Steps

1. **Find DevPod config location:**
   ```bash
   devpod context options --output json
   # Look for the config file path
   ```

2. **Add config to dotfiles:**
   ```bash
   # Example (adjust path based on your DevPod version)
   chezmoi add ~/.devpod/contexts/default/config.yaml
   ```

3. **Chezmoi will now sync this file across machines**

### Pros & Cons

✅ Config travels with your dotfiles
✅ Can version control DevPod settings
⚠️ More brittle - DevPod config format might change between versions
⚠️ Might conflict with DevPod's own config management
⚠️ Research current DevPod config structure before implementing

---

## Strategy 3: Shell Function for Project Scaffolding

**When to use:** You frequently create new projects and want quick scaffolding

### Basic Implementation

Add to `dot_bashrc`:

```bash
# Quick project scaffolding for devcontainers
newproject() {
    local project_name="${1:-new-project}"
    local base_image="${2:-mcr.microsoft.com/devcontainers/base:ubuntu}"

    echo "📦 Creating new project: $project_name"
    mkdir -p "$project_name/.devcontainer"
    cd "$project_name" || return 1

    # Create devcontainer.json from template
    cat > .devcontainer/devcontainer.json <<EOF
{
  "name": "$project_name",
  "image": "$base_image",

  "features": {},

  "customizations": {
    "vscode.extensions": [],
    "cursor.extensions": []
  },

  "remoteUser": "vscode",

  "postCreateCommand": "echo '✅ Devcontainer ready! Your dotfiles have been applied.'"
}
EOF

    # Initialize git repo
    git init

    echo "✅ Project '$project_name' created!"
    echo "   Next: devpod up ."
}
```

### Usage Examples

```bash
# Create project with default Ubuntu base
cd ~/build
newproject my-cool-app

# Create project with specific base image
newproject my-python-app mcr.microsoft.com/devcontainers/python:3.12

# Create project with Node base
newproject my-node-app mcr.microsoft.com/devcontainers/javascript-node:20
```

### Advanced Version with Options

```bash
newproject() {
    local project_name="${1}"
    local template="${2:-base}"

    if [ -z "$project_name" ]; then
        echo "Usage: newproject <project-name> [template]"
        echo "Templates: base, python, node, go, rust"
        return 1
    fi

    # Set image based on template
    case "$template" in
        python)
            base_image="mcr.microsoft.com/devcontainers/python:3.12"
            ;;
        node)
            base_image="mcr.microsoft.com/devcontainers/javascript-node:20"
            ;;
        go)
            base_image="mcr.microsoft.com/devcontainers/go:1.22"
            ;;
        rust)
            base_image="mcr.microsoft.com/devcontainers/rust:latest"
            ;;
        *)
            base_image="mcr.microsoft.com/devcontainers/base:ubuntu"
            ;;
    esac

    echo "📦 Creating $template project: $project_name"
    mkdir -p "$project_name/.devcontainer"
    cd "$project_name" || return 1

    cat > .devcontainer/devcontainer.json <<EOF
{
  "name": "$project_name",
  "image": "$base_image",
  "features": {},
  "customizations": {
    "vscode.extensions": [],
    "cursor.extensions": []
  },
  "remoteUser": "vscode"
}
EOF

    git init
    echo "✅ Project created! Run: devpod up ."
}
```

### Pros & Cons

✅ Fast project creation
✅ Consistent devcontainer structure
✅ Easy to customize and extend
⚠️ Requires remembering to use the function
⚠️ Limited to predefined templates (unless you add template files)

---

## Strategy 4: Template Library in Dotfiles

**When to use:** You have multiple project types with different configurations

### Directory Structure

```
dotfiles/
├── templates/
│   ├── devcontainer-base.json
│   ├── devcontainer-python.json
│   ├── devcontainer-node.json
│   ├── devcontainer-go.json
│   └── README.md
```

### Example Template: `templates/devcontainer-python.json`

```json
{
  "name": "PROJECT_NAME",
  "image": "mcr.microsoft.com/devcontainers/python:3.12",

  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {}
  },

  "customizations": {
    "vscode.extensions": [
      "ms-python.python",
      "ms-python.vscode-pylance"
    ]
  },

  "postCreateCommand": "pip install --upgrade pip && pip install -r requirements.txt || true",

  "remoteUser": "vscode"
}
```

### Shell Function to Use Templates

Add to `dot_bashrc`:

```bash
newproject() {
    local project_name="${1}"
    local template="${2:-base}"

    if [ -z "$project_name" ]; then
        echo "Usage: newproject <name> [template]"
        echo "Available templates:"
        ls ~/.templates/devcontainer-*.json 2>/dev/null | xargs -n1 basename | sed 's/devcontainer-//;s/.json//' | sed 's/^/  - /'
        return 1
    fi

    local template_file="$HOME/.templates/devcontainer-${template}.json"

    if [ ! -f "$template_file" ]; then
        echo "❌ Template not found: $template"
        echo "Available templates:"
        ls ~/.templates/devcontainer-*.json | xargs -n1 basename | sed 's/devcontainer-//;s/.json//' | sed 's/^/  - /'
        return 1
    fi

    echo "📦 Creating $template project: $project_name"
    mkdir -p "$project_name/.devcontainer"
    cd "$project_name" || return 1

    # Copy template and replace PROJECT_NAME placeholder
    sed "s/PROJECT_NAME/$project_name/g" "$template_file" > .devcontainer/devcontainer.json

    git init
    echo "✅ Project created from $template template!"
    echo "   Next: devpod up ."
}
```

### Add Templates to Dotfiles

In your dotfiles repo, templates would be managed as:

```
dot_templates/
├── devcontainer-base.json
├── devcontainer-python.json
└── devcontainer-node.json
```

Chezmoi will place these in `~/.templates/`

### Pros & Cons

✅ Highly customizable per project type
✅ Can include specific VS Code extensions, features, etc.
✅ Templates are versioned in dotfiles
✅ Easy to add new templates
⚠️ More files to maintain
⚠️ Need to keep templates updated with devcontainer spec changes

---

## Strategy 5: Hybrid Approach (Recommended)

Combine the best of multiple strategies:

### Phase 1: Essential Automation (Implement First)

1. **Add DevPod config to `setup` script** (Strategy 1)
   - Automates one-time machine configuration
   - Low maintenance, high value

### Phase 2: Project Scaffolding (Implement After Testing)

2. **Add basic `newproject` function** (Strategy 3 - Basic Version)
   - Quick wins for new projects
   - Easy to customize as you learn what you need

### Phase 3: Advanced Templates (Implement If Needed)

3. **Create template library** (Strategy 4)
   - Only if you find yourself creating many different project types
   - Only if the basic shell function isn't flexible enough

---

## Common Devcontainer Base Images

For reference when choosing templates:

```bash
# General purpose
mcr.microsoft.com/devcontainers/base:ubuntu
mcr.microsoft.com/devcontainers/base:debian

# Language-specific
mcr.microsoft.com/devcontainers/python:3.12
mcr.microsoft.com/devcontainers/javascript-node:20
mcr.microsoft.com/devcontainers/typescript-node:20
mcr.microsoft.com/devcontainers/go:1.22
mcr.microsoft.com/devcontainers/rust:latest
mcr.microsoft.com/devcontainers/java:17
mcr.microsoft.com/devcontainers/php:8.2

# Full stacks
mcr.microsoft.com/devcontainers/universal:2
```

---

## Testing Your Automation

Before implementing any automation:

1. **Manual workflow first**: Create 3-5 projects manually to understand your patterns
2. **Identify pain points**: What do you copy/paste repeatedly?
3. **Start simple**: Implement the simplest automation that solves 80% of your needs
4. **Iterate**: Add complexity only when you need it

### Quick Test Checklist

- [ ] Create a devcontainer manually in a test project
- [ ] Use DevPod to spin it up (`devpod up .`)
- [ ] Verify dotfiles are applied
- [ ] Verify baseline tools are available (chezmoi, mise, ripgrep, etc.)
- [ ] Test on 2-3 different project types (if applicable)
- [ ] Document what you do repeatedly
- [ ] Then implement automation for those repetitive tasks

---

## Implementation Checklist

When you're ready to implement:

- [ ] Choose which strategy fits your workflow
- [ ] Test the code snippets in a temporary branch
- [ ] Update this document with any refinements you make
- [ ] Commit to your dotfiles repo
- [ ] Test on a fresh project
- [ ] Update SETUP.md if the workflow changes

---

## Future Ideas

- Integrate with project initializers (npm init, poetry new, cargo new, etc.)
- Auto-detect project type and suggest appropriate template
- Add VS Code/Cursor extension recommendations per template
- Create different templates for frontend vs backend vs fullstack
- Add Docker Compose support for multi-container projects
- Template for projects with database dependencies

---

## Questions to Answer Through Testing

Before implementing automation, answer these:

1. How often do I create new projects? (daily vs weekly vs monthly)
2. Do my projects use similar or wildly different base images?
3. Do I need VS Code extensions pre-configured or do I add them ad-hoc?
4. Do I care about Docker-in-Docker, GPU support, or other advanced features?
5. Do I want to track devcontainer.json files in git per-project?

Your answers will determine which automation strategy makes the most sense.
