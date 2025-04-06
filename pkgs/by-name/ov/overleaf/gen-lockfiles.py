#!/usr/bin/env python3
import argparse
import json
import os
import os.path
import re
import stat
import subprocess
import shutil
import tempfile

GITHUB_REGEX = re.compile(
    "(?:(?:(?:https|git\\+https|git)://)|(?:(?:git\\+ssh|ssh)://git@))github.com/([\\w\\.-]+)/([\\w\\.-]+)\\.git"
)


def clone(url, rev):
    match = GITHUB_REGEX.fullmatch(url)
    if match is not None:
        owner, repo = match.groups()
        out = subprocess.check_output(
            [
                "nix-prefetch-url",
                "--print-path",
                "--unpack",
                "--",
                f"https://github.com/{owner}/{repo}/archive/{rev}.tar.gz",
            ],
            text=True,
        )
        return out.splitlines()[1]
    out = subprocess.check_output(
        [
            "nix-prefetch-git",
            "--url",
            url,
            "--rev",
            rev,
            "--quiet",
        ]
    )
    args = json.loads(out)
    return args["path"]


INSTALL_SCRIPTS = [
    "postinstall",
    "build",
    "preinstall",
    "install",
    "prepack",
    "prepare",
]


def chmod_plus_recursive(path, mode):
    old_mode = os.lstat(path).st_mode
    os.chmod(path, old_mode | mode)
    if stat.S_ISDIR(old_mode):
        for child in os.listdir(path):
            chmod_plus_recursive(os.path.join(path, child), mode)


def process_git_dependency(output_dir, output_map, url, rev):
    resolved = f"{url}#{rev}"
    if resolved in output_map:
        return

    path = clone(url, rev)

    with open(os.path.join(path, "package.json")) as f:
        package_json = json.load(f)

    name = package_json["name"]

    # Skip Git dependencies with install scripts.
    if "scripts" not in package_json or all(
        script not in package_json["scripts"] for script in INSTALL_SCRIPTS
    ):
        print(f"Skipping {name}.")
        return

    try:
        with open(os.path.join(path, "package-lock.json")) as f:
            package_lock = json.load(f)
    except FileNotFoundError as _:
        with tempfile.TemporaryDirectory() as tmp:
            dir = os.path.join(tmp, "package")

            shutil.copytree(path, dir)
            chmod_plus_recursive(dir, stat.S_IWUSR)

            print(f"Generating lockfile for {name}...")

            subprocess.run(
                [
                    "npm",
                    "install",
                    "--package-lock-only",
                    "--ignore-scripts",
                    "--silent",
                ],
                check=True,
                cwd=dir,
            )

            filename = f"{name}.json"
            output_map[resolved] = filename

            old = os.path.join(dir, "package-lock.json")
            new = os.path.join(output_dir, filename)
            os.makedirs(os.path.dirname(new), exist_ok=True)
            shutil.copy2(old, new)

        with open(new) as f:
            package_lock = json.load(f)

    process_lock_file(output_dir, output_map, package_lock)


GIT_SCHEMES = ["git", "git+ssh", "git+https", "ssh"]


def process_lock_file(output_dir, output_map, package_lock):
    # We can add support for the legacy package-lock.json format later if
    # needed.
    if "packages" not in package_lock:
        return
    for package in package_lock["packages"].values():
        if "resolved" not in package:
            continue
        resolved = package["resolved"]
        if all(not resolved.startswith(f"{scheme}:") for scheme in GIT_SCHEMES):
            continue
        url, rev = resolved.split("#", 2)
        process_git_dependency(output_dir, output_map, url, rev)


ESCAPE_TRANS = str.maketrans({"$": "\\$", '"': '"', "\\": "\\\\"})


def write_output_map(output_dir, output_map):
    with open(os.path.join(output_dir, "default.nix"), "w") as f:
        f.write("{\n")
        for resolved, filename in output_map.items():
            resolved = resolved.translate(ESCAPE_TRANS)
            filename = filename.translate(ESCAPE_TRANS)
            f.write(f'  "{resolved}" = ./. + "/{filename}";\n')
        f.write("}\n")


def main(output_dir, package_lock_path):
    with open(package_lock_path) as f:
        package_lock = json.load(f)
    output_map = {}
    os.makedirs(output_dir, exist_ok=True)
    process_lock_file(output_dir, output_map, package_lock)
    write_output_map(output_dir, output_map)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate missing package-lock.json files for Git dependencies."
    )
    parser.add_argument(
        "package_lock",
        type=str,
        default="package-lock.json",
        help="Path to the root package-lock.json file.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default="lockfiles",
        help="Path to a directory in which to store the generated package-lock.json files.",
    )
    args = parser.parse_args()

    main(args.output, args.package_lock)
