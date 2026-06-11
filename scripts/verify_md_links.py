import os
import re
import subprocess
import sys
import urllib.parse
from typing import List, Dict, Union, Any, cast

# Force utf-8 encoding for stdout to handle emojis in Windows environments
if sys.platform == 'win32' and 'pytest' not in sys.modules:
    import io
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.detach(), encoding='utf-8', errors='replace')
        sys.stderr = io.TextIOWrapper(sys.stderr.detach(), encoding='utf-8', errors='replace')
    except Exception:
        pass

def run_git_command(args: List[str]) -> List[str]:
    try:
        result = subprocess.run(['git'] + args, capture_output=True, text=True, check=True)
        return result.stdout.splitlines()
    except subprocess.CalledProcessError:
        return []

def find_md_files(root_dir: str) -> List[str]:
    # Use git ls-files to find tracked and untracked markdown files, respecting .gitignore
    md_files = run_git_command(['ls-files', '--cached', '--others', '--exclude-standard', '*.md', '**/*.md'])
    return [os.path.abspath(os.path.join(root_dir, f)) for f in md_files]

def extract_links(file_path: str) -> List[Any]:
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return []
    
    # Smart filtering: Remove code blocks and inline code as they often contain examples/anti-patterns
    # Remove triple backtick blocks
    content = re.sub(r'```[\s\S]*?```', '', content)
    # Remove inline backticks
    content = re.sub(r'`[^`]*?`', '', content)
    
    # Matches [label](path) or ![label](path)
    # This also naturally captures image links
    links = re.findall(r'!?\[([^\]]+)\]\(([^)]+)\)', content)
    return links

def solve_link(base_file: str, target_path: str) -> Union[tuple[str, bool], tuple[None, bool]]:
    if target_path.startswith(('http://', 'https://', 'mailto:', 'tel:')):
        return None, True
    
    # Explicitly ignore common example placeholders
    if 'file:///C:/Users/...' in target_path or 'file:///c:/Users/...' in target_path:
        return None, True
    
    # Handle fragments
    path_only = target_path.split('#')[0]
    if not path_only:
        return None, True
    
    # URL decode if needed (e.g. %20)
    path_only = urllib.parse.unquote(path_only)
    
    # Handle absolute file:/// paths (typically used in artifacts in the brain directory)
    if path_only.startswith('file:///'):
        # Convert file:/// absolute path to os path
        # handle windows style C:/ or /C:/
        os_path: str = path_only.replace('file:///', '')
        # If it looks like /C:/Users/...
        if os_path.startswith('/') and len(os_path) > 2 and os_path[2] == ':':
            os_path = os_path[1:]
        
        os_path = os_path.replace('/', os.sep)
        
        # Check if absolute path is permitted based on the base_file location
        # It is generally forbidden outside `.gemini/antigravity/brain`, EXCEPT for media files from the brain directory in IDE artifacts
        normalized_base = base_file.replace('\\', '/')
        normalized_target = os_path.replace('\\', '/')
        
        is_in_brain = '.gemini/antigravity/brain' in normalized_base
        target_is_brain_media = '.gemini/antigravity/brain' in normalized_target and any(normalized_target.endswith(ext) for ext in ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.mp4', '.webm'])
        
        if not is_in_brain and not target_is_brain_media:
            return os_path, False
        
        # In CI, we can't verify absolute paths to the local brain directory
        if os.environ.get('CI') == 'true':
            return os_path, True
            
        if os.path.exists(os_path):
            return os_path, True
        else:
            return os_path, False
    
    # Default: Relative path resolution
    base_dir = os.path.dirname(base_file)
    target_abs = os.path.normpath(os.path.join(base_dir, path_only))
    
    if os.path.exists(target_abs):
        return target_abs, True
    else:
        return target_abs, False

def find_file_in_project(filename: str, root_dir: str) -> List[str]:
    # Use git to get all files in project (tracked and untracked, excluding standard)
    all_files = run_git_command(['ls-files', '--cached', '--others', '--exclude-standard'])
    matches = []
    for f in all_files:
        if os.path.basename(f) == filename:
            matches.append(os.path.abspath(os.path.join(root_dir, f)))
    return matches

def main():
    root_dir: str = os.getcwd()
    md_files: List[str] = find_md_files(root_dir)
    
    if not md_files:
        print("No markdown files found to verify.")
        sys.exit(0)
        
    broken_links: List[Dict[str, Any]] = []
    
    for md_file in md_files:
        links = extract_links(md_file)
        for label, path in links:
            abs_path, exists = solve_link(md_file, path)
            if abs_path and not exists:
                filename = os.path.basename(abs_path)
                suggestions = find_file_in_project(filename, root_dir)
                broken_links.append({
                    'file': str(md_file),
                    'label': str(label),
                    'path': str(path),
                    'target_abs': str(abs_path),
                    'suggestions': [str(s) for s in suggestions]
                })
    
    if not broken_links:
        print("✅ Links verification complete: All internal links are valid.")
        sys.exit(0)
        
    print(f"❌ Links verification failed: Found {len(broken_links)} broken internal links.")
    print("-" * 60)
    for bl in broken_links:
        file_path = cast(str, bl['file'])
        file_rel = os.path.relpath(file_path, root_dir)
        print(f"File: {file_rel}")
        print(f"  Link: [{bl['label']}]({bl['path']})")
        print(f"  Target Not Found: {bl['target_abs']}")
        if bl['suggestions']:
            for s in bl['suggestions']:
                s_str = str(s)
                rel = os.path.relpath(s_str, os.path.dirname(file_path))
                # Use forward slashes for markdown links
                rel = rel.replace('\\', '/')
                print(f"  💡 Suggested Fix: {rel}")
        else:
            print("  No suggestions found.")
        print("-" * 40)
    
    # Exit with code 1 so the workflow can fail
    sys.exit(1)

if __name__ == "__main__":
    main()