import os

OUTPUT_FILE = "claude_codebase.md"

IGNORE_FOLDERS = {
    '.git', '.terraform', 'venv', '.venv', 'env', '__pycache__', 
    '.pytest_cache', '.aws', 'node_modules', 'dist', 'build'
}

IGNORE_EXTENSIONS = (
    '.tfstate', '.tfstate.backup', '.pyc', '.pyo', '.pyd', 
    '.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip', '.tar.gz', 
    '.lock', '.hcl'
)

def merge_here():
    # Uses the folder where the script is physically placed
    source_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(source_dir, OUTPUT_FILE)
    total_files = 0
    
    print(f"Scanning files inside: {source_dir}...\n")
    
    with open(output_path, 'w', encoding='utf-8') as outfile:
        outfile.write("# Codebase Directory Structure\n```text\n")
        for root, dirs, files in os.walk(source_dir):
            dirs[:] = [d for d in dirs if d not in IGNORE_FOLDERS]
            level = root.replace(source_dir, '').count(os.sep)
            indent = ' ' * 4 * level
            outfile.write(f"{indent}{os.path.basename(root)}/\n")
            sub_indent = ' ' * 4 * (level + 1)
            for f in files:
                if f != OUTPUT_FILE and f != os.path.basename(__file__) and not f.endswith(IGNORE_EXTENSIONS):
                    outfile.write(f"{sub_indent}{f}\n")
        outfile.write("```\n\n# Source Code Details\n")
        
        for root, dirs, files in os.walk(source_dir):
            dirs[:] = [d for d in dirs if d not in IGNORE_FOLDERS]
            for file in files:
                if file == OUTPUT_FILE or file == os.path.basename(__file__) or file.endswith(IGNORE_EXTENSIONS):
                    continue
                    
                file_path = os.path.join(root, file)
                relative_path = os.path.relpath(file_path, source_dir)
                
                _, ext = os.path.splitext(file)
                ext = ext.lower().replace('.', '')
                lang = "terraform" if ext in ['tf', 'tfvars'] else ("python" if ext == "py" else ext)
                
                outfile.write(f"\n## File: {relative_path}\n")
                outfile.write(f"```{lang}\n")
                
                try:
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as infile:
                        outfile.write(infile.read())
                except Exception as e:
                    outfile.write(f"[Error reading file: {str(e)}]\n")
                
                outfile.write("\n```\n")
                outfile.write("-" * 50 + "\n")
                total_files += 1

    print(f"Success! Found and merged {total_files} files.")
    print(f"Your file is ready here: {output_path}")

if __name__ == "__main__":
    merge_here()
