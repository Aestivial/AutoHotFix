# AutoHotFix - Interactive HotFix (HF) Deployment Helper

`AutoHotFix.sh` is a bash script designed to streamline the deployment of HotFixes (HF) for JAR files (or any specified extension) in internal CXL/TriplePoint environments. It intelligently matches HF files to target files, handles backups, and provides an interactive prompt for each replacement.

## Features

*   **Interactive Prompts:** Guides you through selecting HF and target folders.
*   **Intelligent Matching:** Maps target files by an "artifact key" (filename without version/qualifier) to identify corresponding HF files.
*   **Safe Replacement:** Moves old target files to a timestamped backup directory before copying the new HF file.
*   **Customizable Extension:** Defaults to `.jar`, but can be set for any file extension.
*   **Recursive HF Scan:** Option to process HF files from subdirectories within the HF folder.
*   **Dry Run Mode:** Preview actions without making any changes.
*   **Flexible Naming:** Option to keep the target's original filename or use the HF file's name when copying.

## How it Works

1.  **Input:** Prompts for the HotFix (source) folder and the Target (destination) folder, or accepts them via command-line flags.
2.  **Target Indexing:** Builds an internal map of all target files based on their "artifact key." The artifact key is derived by stripping the file extension and any trailing version/qualifier (e.g., `tpt-cxl-trade-capture-8.25.01.0.16.jar` becomes `tpt-cxl-trade-capture`).
3.  **HF Matching & Prompting:** For each HF file, the script finds all target files that match its artifact key. It then interactively prompts you for each match:
    *   **[y]es**: Replace the target file with the HF file.
    *   **[n]o**: Skip this specific replacement.
    *   **[a]ll**: Replace this target and all subsequent matches for the *current HF file* without further prompting.
    *   **[s]kip all**: Skip this target and all subsequent matches for the *current HF file*.
    *   **[q]uit**: Exit the script immediately.
4.  **Replacement Action:**
    *   The existing target file is moved to a timestamped backup folder within the HF directory: `<HF_DIR>/backup/<YYYYmmdd_HHMMSS>/<relative-target-dir>/`.
    *   The HF file is copied into the target directory. By default, it keeps its own filename, but you can choose to use the target's original filename.

## Usage
(include these in the same flow to integrate with existing Jenkins automation pipeline)
1.  **Perms to make the script executable:**
    ```bash
    chmod +x AutoHotFix.sh
    ```

2.  **Run interactively:**
    ```bash
    ./AutoHotFix.sh
    ```
    The script will then prompt you for the HotFix and Target folder paths.

3.  **Run with flags (non-interactive for paths):**
    You can provide folder paths and other options directly as arguments.

    ```bash
    ./AutoHotFix.sh --source /path/to/your/hotfix/files --target /path/to/your/application/deployments
    ```

## Options

| Flag                 | Description                                                                                             | Default                   |
| :------------------- | :------------------------------------------------------------------------------------------------------ | :------------------------ |
| `--source <path>`    | Specifies the HotFix folder containing the new files.                                                   | Interactive prompt        |
| `--target <path>`    | Specifies the Target folder where files need to be updated.                                             | Interactive prompt        |
| `--ext <extension>`  | Sets the file extension to process (e.g., `jar`, `war`, `zip`).                                         | `jar`                     |
| `--hf-recursive`     | Enables scanning for HF files in subdirectories within the HotFix folder.                               | `off` (only top-level)    |
| `--dry-run`          | Shows what actions would be performed without actually modifying any files or creating backups.          | `off`                     |
| `--keep-target-name` | When copying, uses the original target file's name instead of the HotFix file's name.                   | `off` (uses HF filename)  |
| `-h`, `--help`       | Displays the help message.                                                                              |                           |

## Examples

### 1. Basic Interactive Deployment

Run the script and let it guide you:

```bash
./AutoHotFix.sh
