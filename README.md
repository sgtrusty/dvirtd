# arch-safecode

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
