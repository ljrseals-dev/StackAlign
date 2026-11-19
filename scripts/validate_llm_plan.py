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


def strict_loads(raw: str):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def reject_constant(value):
        raise ValueError(f"non-standard JSON constant: {value}")

    return json.loads(raw, object_pairs_hook=unique_object, parse_constant=reject_constant)


def main() -> None:
    if len(sys.argv) != 2:
        reject("validator requires one response file")
    try:
        envelope = strict_loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError, RecursionError):
        reject("provider response is not valid JSON")

    content = envelope
    if isinstance(envelope, dict) and "choices" in envelope:
        choices = envelope.get("choices")
        if not isinstance(choices, list) or len(choices) != 1:
            reject("expected exactly one completion choice")
        choice = choices[0]
        if not isinstance(choice, dict):
            reject("completion choice is not an object")
        if choice.get("finish_reason") not in (None, "stop"):
            reject("completion did not finish normally")
        message = choice.get("message")
        if not isinstance(message, dict):
            reject("completion message is missing or malformed")
        if message.get("refusal") or message.get("tool_calls") or message.get("function_call"):
            reject("refusal and tool-call responses are not accepted")
        if message.get("role") not in (None, "assistant"):
            reject("completion message role is not assistant")
        content = message.get("content")

    if isinstance(content, str):
        try:
            plan = strict_loads(content)
        except (ValueError, RecursionError):
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
