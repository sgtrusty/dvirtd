# dvirtd

Docker-based development environment manager. Launches containerized dev
environments with X11/Wayland integration, persistent volumes, and image
version management.

## Requirements

- Docker + docker-compose
- bash-completion (optional)

## Install

    sudo make install

Installs to `/opt/dvirtd` with wrappers in `/usr/local/bin`.

## Usage

    dvirtd <command> [args]
      run <image> [cmdopt]   Launch a container
      list                   List available images
      help                   Show full usage

    dvirtmg <command> [args]
      build <image> [lvl]    Build an image (patch|minor|major)
      list                   List built images
      current [image]        Show current version
      outdated [--fix]       Show pending/outdated images
      refresh                Regenerate version.ini from recipes
      purge [image]          Remove images

## Recipe directory

Recipes are Docker Compose YML files. The directory is resolved in this order:

1. `DVIRTD_RECIPE_DIR` env var
2. `$IMPORT_DIR/recipe` (development path)
3. `/opt/dvirtd/recipe` (installed default)

Each `.yml` in the recipe directory becomes an available image.

## Security

- **`network_mode: host`** exposes Xorg to containers, which can read
  display buffer data to extract credentials, confidential information, and
  more. Avoid unless absolutely necessary.

- **Privileged containers** (`privileged: true`) should be avoided.
  GPU acceleration via DRI device sharing is the correct approach.
  For sandboxing with escalated privileges, use bubblewrap or firejail instead.

- **Root runtime user** in the final image layer exposes the container
  to unnecessary risk. Always drop to a non-root user.

- This project is provided for educational purposes and is not a finished
  security product. It does not guarantee absolute defense against attacks,
  but can aid in system hardening and reducing attack surface. The author
  is not liable for any damages arising from its use.
