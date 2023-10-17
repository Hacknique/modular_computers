import git
import subprocess
from collections import defaultdict
import os
from datetime import datetime as dt


def render_contrib_percentage(contrib_data):
    html_output = "<h1>Contribution Percentage</h1>\n"
    html_output += "<table><tr><th>Author</th><th>Contribution</th></tr>\n"
    for author, percent in contrib_data.items():
        html_output += f"<tr><td>{author}</td><td>{percent}%</td></tr>\n"
    html_output += "</table>\n"
    return html_output

def render_file_history(file_history_data):
    html_output = ""
    for directory, files in file_history_data.items():
        html_output += f"<h2>Directory: {directory}</h2>\n"
        for filename, commit_data in files.items():
            html_output += f"<h3>File: {filename}</h3>\n"
            html_output += "<table><tr><th>Commit</th><th>Author</th><th>Message</th><th>Date</th><th>Changes</th></tr>\n"  # Added Date header
            for commit in commit_data:
                date_str = dt.utcfromtimestamp(commit['date']).strftime('%Y-%m-%d %H:%M:%S') 
                html_output += f"<tr><td>{commit['hash']}</td><td>{commit['author']}</td><td>{commit['message']}</td><td>{date_str}</td><td>{commit['changes']}</td></tr>\n"  # Added date_str
            html_output += "</table>\n"
    return html_output

if __name__ == "__main__":
    repo_path = "./"
    repo = git.Repo(repo_path)

    # Fetching Contribution Data
    contrib_data = defaultdict(int)
    total_commits = 0
    for commit in repo.iter_commits():
        author = commit.author.name
        contrib_data[author] += 1
        total_commits += 1

    for author, num_commits in contrib_data.items():
        contrib_data[author] = round((num_commits / total_commits) * 100, 2)

    # Fetching File History Data
    file_history_data = defaultdict(lambda: defaultdict(list))

    for commit in repo.iter_commits(paths="./"):
        for obj in commit.tree.traverse():
            if obj.type == "blob":  # It's a file
                filename = obj.name
                directory = obj.path.rsplit('/', 1)[0]
                
                changes = ""
                if commit.parents:  # if there is a parent commit
                    parent_commit = commit.parents[0]
                    cmd = f"git diff {parent_commit} {commit} -- {obj.path}"
                else:
                    cmd = f"git show {commit}:{obj.path}"

                try:
                    changes_raw = subprocess.check_output(cmd, shell=True, cwd=repo_path).decode('utf-8')
                    if changes_raw.strip():  # check if the diff is not empty
                        changes = f'<pre>{changes_raw}</pre>'
                    else:
                        continue  # skip this commit for this file if diff is empty
                except subprocess.CalledProcessError:
                    changes = "No changes or file not present in this commit."

                commit_data = {
                    "hash": commit.hexsha,
                    "author": commit.author.name,
                    "message": commit.message.strip(),
                    "changes": changes,
                    "date": commit.committed_date
                }
                file_history_data[directory][filename].append(commit_data)

    # Render HTML
    html_output = render_contrib_percentage(contrib_data)
    html_output += render_file_history(file_history_data)
    html_head = '''<!DOCTYPE html>
<html>
<head>
    <title>Git Contribution Report</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
</head>
<body>
'''

    # Define the HTML closing tags
    html_tail = '''
</body>
</html>
'''

    # Wrap the HTML content with head and tail
    full_html_output = html_head + html_output + html_tail
    
    # Create a directory called reports
    os.makedirs("reports", exist_ok=True)

    # Save HTML to file
    with open("reports/REFERENCES.html", "w") as f:
        f.write(full_html_output)
