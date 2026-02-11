"""
Shared YAML frontmatter parsing utilities for Test262 scripts.

Provides a lightweight fallback YAML parser for Test262 metadata,
used when PyYAML is not installed.
"""

import re
from typing import Any

try:
    import yaml
except ModuleNotFoundError:
    yaml = None

YAML_PATTERN = re.compile(r'/\*---(.*?)---\*/', re.DOTALL)


def _parse_yaml_scalar(value: str) -> Any:
    value = value.strip()
    if not value:
        return ""
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        inner = value[1:-1]
        return inner.replace('\\"', '"').replace("\\'", "'")
    lower = value.lower()
    if lower == "true":
        return True
    if lower == "false":
        return False
    if lower in ("null", "none", "~"):
        return None
    return value


def _split_top_level_csv(text: str) -> list[str]:
    parts = []
    current = []
    quote = None
    depth = 0
    escaped = False
    for ch in text:
        if escaped:
            current.append(ch)
            escaped = False
            continue
        if ch == "\\" and quote:
            escaped = True
            current.append(ch)
            continue
        if quote:
            current.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            current.append(ch)
            continue
        if ch in "[{(":
            depth += 1
            current.append(ch)
            continue
        if ch in "]})":
            depth = max(0, depth - 1)
            current.append(ch)
            continue
        if ch == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
            continue
        current.append(ch)
    if current:
        parts.append("".join(current).strip())
    return [p for p in parts if p]


def _parse_inline_list(value: str) -> list[Any] | None:
    value = value.strip()
    if not (value.startswith("[") and value.endswith("]")):
        return None
    inner = value[1:-1].strip()
    if not inner:
        return []
    return [_parse_yaml_scalar(item) for item in _split_top_level_csv(inner)]


def _parse_inline_dict(value: str) -> dict[str, Any] | None:
    value = value.strip()
    if not (value.startswith("{") and value.endswith("}")):
        return None
    inner = value[1:-1].strip()
    if not inner:
        return {}
    out = {}
    for item in _split_top_level_csv(inner):
        if ":" not in item:
            continue
        key, raw_val = item.split(":", 1)
        out[key.strip()] = _parse_yaml_scalar(raw_val)
    return out


def _parse_frontmatter_fallback(frontmatter: str) -> dict[str, Any]:
    data: dict[str, Any] = {}
    lines = frontmatter.splitlines()
    i = 0

    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()
        if ":" not in stripped:
            i += 1
            continue
        key, remainder = stripped.split(":", 1)
        key = key.strip()
        remainder = remainder.strip()

        if remainder:
            maybe_list = _parse_inline_list(remainder)
            if maybe_list is not None:
                data[key] = maybe_list
            else:
                maybe_dict = _parse_inline_dict(remainder)
                if maybe_dict is not None:
                    data[key] = maybe_dict
                elif remainder in ("|", ">"):
                    block_lines = []
                    j = i + 1
                    while j < len(lines):
                        next_line = lines[j]
                        if not next_line.strip():
                            block_lines.append("")
                            j += 1
                            continue
                        next_indent = len(next_line) - len(next_line.lstrip(" "))
                        if next_indent <= indent:
                            break
                        block_lines.append(next_line.lstrip())
                        j += 1
                    data[key] = "\n".join(block_lines).strip()
                    i = j
                    continue
                else:
                    data[key] = _parse_yaml_scalar(remainder)
            i += 1
            continue

        block_lines = []
        j = i + 1
        while j < len(lines):
            next_line = lines[j]
            if not next_line.strip():
                block_lines.append("")
                j += 1
                continue
            next_indent = len(next_line) - len(next_line.lstrip(" "))
            if next_indent <= indent:
                break
            block_lines.append(next_line)
            j += 1

        meaningful = [bl for bl in block_lines if bl.strip()]
        if not meaningful:
            data[key] = None
            i = j
            continue

        first = meaningful[0].strip()
        if first.startswith("- "):
            out_list = []
            for raw in block_lines:
                if not raw.strip():
                    continue
                raw_strip = raw.strip()
                if raw_strip.startswith("- "):
                    out_list.append(_parse_yaml_scalar(raw_strip[2:]))
            data[key] = out_list
        else:
            out_dict: dict[str, Any] = {}
            for raw in block_lines:
                if not raw.strip():
                    continue
                raw_strip = raw.strip()
                if ":" not in raw_strip:
                    continue
                child_key, child_val = raw_strip.split(":", 1)
                out_dict[child_key.strip()] = _parse_yaml_scalar(child_val)
            data[key] = out_dict
        i = j

    return data


def parse_yaml_frontmatter(source: str) -> dict[str, Any] | None:
    """Extract and parse YAML frontmatter from a test262 source file.

    Returns the parsed dict, or None if no frontmatter was found.
    """
    match = YAML_PATTERN.search(source)
    if not match:
        return None
    frontmatter = match.group(1)
    if yaml is not None:
        try:
            data = yaml.safe_load(frontmatter)
        except Exception:
            data = _parse_frontmatter_fallback(frontmatter)
    else:
        data = _parse_frontmatter_fallback(frontmatter)
    if not isinstance(data, dict):
        return None
    return data


def as_list(value: Any) -> list:
    """Coerce a value to a list (handles None and scalar)."""
    if isinstance(value, list):
        return value
    if value is None:
        return []
    return [value]
