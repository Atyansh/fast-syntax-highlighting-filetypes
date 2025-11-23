# fast-syntax-highlighting-filetypes

Adds LS_COLORS-based file type highlighting to [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting).

When you type a command like `cat myfile.txt`, this plugin colors the filename based on its type (directory, executable, symlink, etc.) and extension, using your `LS_COLORS` configuration.

## Features

- Colors paths based on file type (directory, executable, symlink, etc.)
- Colors paths based on file extension (`.txt`, `.py`, `.tar.gz`, etc.)
- Uses your existing `LS_COLORS` configuration
- Works alongside fast-syntax-highlighting
- Handles special file types: setuid, setgid, sticky, orphaned symlinks
- Supports quoted paths (`"..."`, `'...'`, `$'...'`) and backslash escapes (`foo\ bar`)
- Supports `--option=/path/to/file` patterns
- Supports 24-bit true color and all ANSI attributes (bold, dim, italic, etc.)
- Cross-platform: works on Linux and macOS

## Installation

### Antigen

```zsh
antigen bundle zdharma-continuum/fast-syntax-highlighting
antigen bundle Atyansh/fast-syntax-highlighting-filetypes  # Must be after fast-syntax-highlighting
```

### Oh My Zsh

```bash
git clone https://github.com/Atyansh/fast-syntax-highlighting-filetypes.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting-filetypes
```

Then add to your `.zshrc` (must come after fast-syntax-highlighting):
```zsh
plugins=(... fast-syntax-highlighting fast-syntax-highlighting-filetypes)
```

### Manual

```bash
git clone https://github.com/Atyansh/fast-syntax-highlighting-filetypes.git
# Source after fast-syntax-highlighting in your .zshrc
source fast-syntax-highlighting-filetypes/fast-syntax-highlighting-filetypes.plugin.zsh
```

## Requirements

- Zsh 5.1+
- `LS_COLORS` environment variable set
- [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting) (required)

## How It Works

The plugin wraps fast-syntax-highlighting's internal `_zsh_highlight` function, which runs after every keystroke and widget. After FSH applies its highlighting, this plugin:

1. Parses the command line to find path arguments
2. Checks each path's type (directory, executable, symlink, etc.)
3. Looks up the appropriate color from `LS_COLORS`
4. Replaces FSH's path highlighting with the LS_COLORS-based style

By wrapping FSH directly, file type colors are applied consistently regardless of how the command line was modified (typing, tab completion, history navigation, etc.).

## Supported File Types

| Type | LS_COLORS Key | Description |
|------|---------------|-------------|
| `di` | Directory | |
| `ln` | Symbolic link | |
| `or` | Orphaned symlink | Points to non-existent file |
| `ex` | Executable | |
| `su` | Setuid | Executable with setuid bit |
| `sg` | Setgid | Executable with setgid bit |
| `st` | Sticky | Directory with sticky bit |
| `ow` | Other-writable | Directory writable by others |
| `tw` | Sticky + other-writable | |
| `bd` | Block device | |
| `cd` | Character device | |
| `pi` | Named pipe (FIFO) | |
| `so` | Socket | |
| `*.ext` | By extension | e.g., `*.tar`, `*.zip`, `*.mp3` |

## Configuration

The plugin uses your existing `LS_COLORS` environment variable. To customize colors:

```zsh
# Example: Set directory color to blue
export LS_COLORS="di=38;5;33:$LS_COLORS"
```

Or use `dircolors` to generate `LS_COLORS` from a config file:

```bash
eval "$(dircolors ~/.dircolors)"
```

## Troubleshooting

### Colors not showing

1. Make sure `LS_COLORS` is set:
   ```bash
   echo $LS_COLORS
   ```

2. Make sure the plugin is loaded after setting `LS_COLORS`

3. Check that the file actually exists on disk

### Performance

The plugin checks if each path exists on disk, which can be slow for:
- Network-mounted filesystems
- Very long command lines with many paths

### Plugin not working

Make sure fast-syntax-highlighting is loaded before this plugin. The plugin wraps FSH's internal function, so FSH must be available first.

## License

MIT License - see [LICENSE](LICENSE) file.

## Contributing

Contributions welcome! Please open an issue or PR on GitHub.

## Credits

Inspired by [zsh-syntax-highlighting-filetypes](https://github.com/trapd00r/zsh-syntax-highlighting-filetypes) by trapd00r.
