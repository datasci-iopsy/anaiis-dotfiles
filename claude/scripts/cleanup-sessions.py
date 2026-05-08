#!/usr/bin/env python3
"""
cleanup-sessions.py, Interactive Claude Code session cleanup.

Usage:
    claude-cleanup                     # interactive, sorted by size (largest first)
    claude-cleanup --sort age          # sorted by age (oldest first)
    claude-cleanup --sort tokens       # sorted by last context size (largest first)
    claude-cleanup --older-than 30     # only sessions last used > 30 days ago
    claude-cleanup --dry-run           # preview deletions without removing files

Columns:
    Size    , on-disk file size (full conversation history log)
    Ctx     , effective input tokens at last assistant turn (cache_read + cache_creation
               + uncached); approximates how large the context window was most recently.
               Low Ctx on a large file means the session was compacted, healthy signal.
    Msgs    , number of user turns
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path


CLAUDE_DIR = Path.home() / ".claude" / "projects"


def decode_project(encoded_name: str) -> str:
    """Convert encoded project dir name (slashes-as-hyphens) to a short readable label."""
    decoded = encoded_name.lstrip("-").replace("-", "/")
    parts = [p for p in decoded.split("/") if p]
    return "/".join(parts[-2:]) if len(parts) >= 2 else (parts[-1] if parts else encoded_name)


def format_size(bytes_: int) -> str:
    if bytes_ >= 1_048_576:
        return f"{bytes_ / 1_048_576:.1f}M"
    if bytes_ >= 1_024:
        return f"{bytes_ / 1_024:.1f}K"
    return f"{bytes_}B"


def format_tokens(n: int | None) -> str:
    if n is None:
        return "?"
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}K"
    return str(n)


def parse_session(path: Path) -> dict:
    """Single-pass parse of a session JSONL.

    Returns title, user message count, and effective input token count at the
    last assistant turn (sum of input_tokens + cache_read_input_tokens +
    cache_creation_input_tokens).
    """
    custom_title = None
    first_user = None
    user_count = 0
    last_ctx_tokens = None

    try:
        with open(path, errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue

                rec_type = obj.get("type")

                if rec_type == "custom-title":
                    ct = obj.get("customTitle")
                    if ct and custom_title is None:
                        custom_title = ct

                elif rec_type == "user":
                    user_count += 1
                    if first_user is None:
                        content = obj.get("message", {}).get("content", "")
                        if isinstance(content, list):
                            for c in content:
                                if isinstance(c, dict) and c.get("type") == "text":
                                    first_user = c["text"].replace("\n", " ")
                                    break
                        elif isinstance(content, str):
                            first_user = content.replace("\n", " ")

                elif rec_type == "assistant":
                    usage = obj.get("message", {}).get("usage")
                    if usage:
                        ctx = (
                            usage.get("input_tokens", 0)
                            + usage.get("cache_read_input_tokens", 0)
                            + usage.get("cache_creation_input_tokens", 0)
                        )
                        if ctx > 0:
                            last_ctx_tokens = ctx

    except Exception:
        pass

    return {
        "title": custom_title or first_user or "(no title)",
        "msgs": user_count,
        "last_ctx_tokens": last_ctx_tokens,
    }


def scan_sessions(older_than_days: int | None = None) -> list[dict]:
    sessions = []
    cutoff = (time.time() - older_than_days * 86400) if older_than_days else None

    if not CLAUDE_DIR.exists() or not CLAUDE_DIR.is_dir():
        return sessions

    for project_dir in sorted(CLAUDE_DIR.iterdir()):
        if not project_dir.is_dir():
            continue
        for jsonl_file in sorted(project_dir.glob("*.jsonl")):
            if "memory" in jsonl_file.parts:
                continue
            try:
                stat = jsonl_file.stat()
            except OSError:
                continue
            mtime = stat.st_mtime
            if cutoff and mtime > cutoff:
                continue
            sessions.append({
                "file": jsonl_file,
                "project": decode_project(project_dir.name),
                "session_id": jsonl_file.stem,
                "size": stat.st_size,
                "mtime": mtime,
                "title": None,
                "msgs": None,
                "last_ctx_tokens": None,
            })

    return sessions


def parse_selection(selection: str, max_idx: int) -> set[int]:
    result = set()
    for part in selection.split(","):
        part = part.strip()
        if "-" in part:
            try:
                lo, hi = part.split("-", 1)
                for n in range(int(lo), int(hi) + 1):
                    if 1 <= n <= max_idx:
                        result.add(n)
            except ValueError:
                pass
        else:
            try:
                n = int(part)
                if 1 <= n <= max_idx:
                    result.add(n)
            except ValueError:
                pass
    return result


def main():
    parser = argparse.ArgumentParser(
        description="Interactive Claude Code session cleanup",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--sort", choices=["size", "age", "tokens"], default="size",
        help="Sort by size (largest first), age (oldest first), or tokens (largest ctx first). Default: size",
    )
    parser.add_argument(
        "--older-than", type=int, metavar="DAYS",
        help="Only show sessions last used more than N days ago",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be deleted without actually deleting",
    )
    args = parser.parse_args()

    print("Scanning sessions...", end="", flush=True)
    sessions = scan_sessions(older_than_days=args.older_than)

    if not sessions:
        print("\nNo sessions found.")
        return

    print(f"\rParsing {len(sessions)} session(s)...   ", end="", flush=True)
    for s in sessions:
        parsed = parse_session(s["file"])
        s["title"] = parsed["title"]
        s["msgs"] = parsed["msgs"]
        s["last_ctx_tokens"] = parsed["last_ctx_tokens"]
    print("\r" + " " * 40 + "\r", end="", flush=True)

    # Sort
    if args.sort == "age":
        sessions.sort(key=lambda s: s["mtime"])
    elif args.sort == "tokens":
        sessions.sort(key=lambda s: s["last_ctx_tokens"] or 0, reverse=True)
    else:
        sessions.sort(key=lambda s: s["size"], reverse=True)

    # ── Table ────────────────────────────────────────────────────────────────
    COL_NUM = 4
    COL_PROJ = 28
    COL_SIZE = 7
    COL_CTX = 7
    COL_DATE = 12
    COL_MSGS = 5
    COL_TITLE = 60

    header = (
        f"{'#':<{COL_NUM}}  {'Project':<{COL_PROJ}}  {'Size':>{COL_SIZE}}"
        f"  {'Ctx':>{COL_CTX}}  {'Last Used':<{COL_DATE}}  {'Msgs':>{COL_MSGS}}  Title"
    )
    print(header)
    print("-" * len(header))

    for i, s in enumerate(sessions, 1):
        date_str = datetime.fromtimestamp(s["mtime"]).strftime("%Y-%m-%d")
        print(
            f"{i:<{COL_NUM}}  {s['project']:<{COL_PROJ}.{COL_PROJ}}"
            f"  {format_size(s['size']):>{COL_SIZE}}"
            f"  {format_tokens(s['last_ctx_tokens']):>{COL_CTX}}"
            f"  {date_str:<{COL_DATE}}  {s['msgs']:>{COL_MSGS}}"
            f"  {s['title']:<{COL_TITLE}.{COL_TITLE}}"
        )

    total_size = sum(s["size"] for s in sessions)
    print()
    print(f"Total: {len(sessions)} session(s)  |  {format_size(total_size)} on disk")
    print()

    # ── Selection ────────────────────────────────────────────────────────────
    print("Select sessions to delete:")
    print("  Numbers:  1,3,5   or   2-8   or   1,3-7,9")
    print("  all       Delete everything listed above")
    print("  q         Quit without deleting")
    print()

    try:
        selection = input("Selection: ").strip()
    except (KeyboardInterrupt, EOFError):
        print("\nAborted.")
        return

    if not selection or selection.lower() == "q":
        print("Aborted.")
        return

    if selection.lower() == "all":
        chosen = set(range(1, len(sessions) + 1))
    else:
        chosen = parse_selection(selection, len(sessions))

    if not chosen:
        print("No valid sessions selected. Aborted.")
        return

    # ── Confirmation ─────────────────────────────────────────────────────────
    print()
    print("Sessions to delete:")
    total_bytes = 0
    for idx in sorted(chosen):
        s = sessions[idx - 1]
        print(f"  [{idx}]  {s['project']} ,  {s['title'][:55]}  ({format_size(s['size'])})")
        total_bytes += s["size"]
    print()
    print(f"Space freed: {format_size(total_bytes)}")
    print()

    if args.dry_run:
        print("[dry-run] No files deleted.")
        return

    try:
        confirm = input("Confirm deletion? [y/N]: ").strip().lower()
    except (KeyboardInterrupt, EOFError):
        print("\nAborted.")
        return

    if confirm != "y":
        print("Aborted.")
        return

    # ── Delete ────────────────────────────────────────────────────────────────
    deleted = 0
    for idx in sorted(chosen):
        s = sessions[idx - 1]
        try:
            s["file"].unlink()
            print(f"  deleted  {s['file'].name}")
            deleted += 1
        except OSError as e:
            print(f"  ERROR    {s['file'].name}: {e}", file=sys.stderr)

    print()
    print(f"Done. Deleted {deleted} session(s), freed {format_size(total_bytes)}.")


if __name__ == "__main__":
    main()
