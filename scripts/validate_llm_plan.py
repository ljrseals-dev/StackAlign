#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
"""Validate and normalize an OpenAI-compatible LLM planner response."""

import json
import sys
from pathlib import Path


def reject(message: str) -> None:
    print(f"agent: rejected model plan: {message}", file=sys.stderr)
    raise SystemExit(65)


def main() -> None:
    if len(sys.argv) != 2:
        reject("validator requires one response file")
    try:
        envelope = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        reject("provider response is not valid JSON")

    content = envelope
    if isinstance(envelope, dict) and "choices" in envelope:
        choices = envelope.get("choices")
        if not isinstance(choices, list) or len(choices) != 1:
            reject("expected exactly one completion choice")
        message = choices[0].get("message") if isinstance(choices[0], dict) else None
        content = message.get("content") if isinstance(message, dict) else None

    if isinstance(content, str):
        try:
            plan = json.loads(content)
        except json.JSONDecodeError:
            reject("model content is not strict JSON")
    else:
        plan = content

    required = {"summary", "tasks", "questions", "warnings", "unsupported_requests"}
    if not isinstance(plan, dict) or set(plan) != required:
        reject("plan keys do not match the required schema")
    if not isinstance(plan["summary"], str) or not 1 <= len(plan["summary"]) <= 1000:
        reject("summary must contain 1-1000 characters")
    if not isinstance(plan["tasks"], list) or len(plan["tasks"]) > 5:
        reject("tasks must be an array of at most five entries")
    for task in plan["tasks"]:
        if not isinstance(task, dict) or set(task) != {"type", "description"}:
            reject("task entry has an invalid shape")
        if task["type"] != "health_check":
            reject(f"task type is not implemented: {task['type']!r}")
        if not isinstance(task["description"], str) or not 1 <= len(task["description"]) <= 500:
            reject("task description must contain 1-500 characters")
    for field in ("questions", "warnings", "unsupported_requests"):
        values = plan[field]
        if not isinstance(values, list) or len(values) > 5:
            reject(f"{field} must be an array of at most five entries")
        if any(not isinstance(value, str) or not 1 <= len(value) <= 500 for value in values):
            reject(f"{field} entries must contain 1-500 characters")

    print(json.dumps(plan, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
