#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
# Parse a deliberately small TOML subset; this is not a full TOML implementation.
#
# Grammar: comments/blank lines, [table], [[array_table]], bare keys made of
# letters/digits/underscores, quoted strings with \\" and \\\\ escapes,
# decimal integers, and true/false. Arrays, dotted keys, dates, multiline
# strings, single quotes, and all other TOML constructs are rejected.

declare -A TOML_DATA

sa_toml_parse() {
    local file="${1-}"
    local line lineno=0 table="" table_kind="" array_index=-1
    local key raw_value value full_key tail char next_char
    local i length closed

    TOML_DATA=()

    if [[ -z "$file" || ! -r "$file" || ! -f "$file" ]]; then
        printf 'toml: %s: file is not a readable regular file\n' "${file:-<missing>}" >&2
        return 1
    fi

    local -A array_counts=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((lineno += 1))

        # Trim surrounding whitespace using Bash parameter expansion.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        [[ -z "$line" || "$line" == \#* ]] && continue

        # Array-of-table headers have independent counters per table name.
        if [[ "$line" =~ ^\[\[[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*\]\]$ ]]; then
            table="${BASH_REMATCH[1]}"
            table_kind="array"
            if [[ -n "${array_counts[$table]+present}" ]]; then
                array_index=${array_counts[$table]}
            else
                array_index=0
            fi
            array_counts["$table"]=$((array_index + 1))
            continue
        fi

        if [[ "$line" =~ ^\[[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*\]$ ]]; then
            table="${BASH_REMATCH[1]}"
            table_kind="simple"
            array_index=-1
            continue
        fi

        if [[ "$line" =~ ^([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            raw_value="${BASH_REMATCH[2]}"
            raw_value="${raw_value#"${raw_value%%[![:space:]]*}"}"
            raw_value="${raw_value%"${raw_value##*[![:space:]]}"}"

            if [[ -z "$raw_value" ]]; then
                printf 'toml: %s:%d: missing value for key %s\n' "$file" "$lineno" "$key" >&2
                TOML_DATA=()
                return 1
            fi

            if [[ "${raw_value:0:1}" == '"' ]]; then
                # Decode only the two explicitly supported escapes.
                value=""
                i=1
                length=${#raw_value}
                closed=0
                while (( i < length )); do
                    char="\${raw_value:i:1}"
                    if [[ "$char" == $'\\' ]]; then
                        ((i += 1))
                        if (( i >= length )); then
                            break
                        fi
                        next_char="\${raw_value:i:1}"
                        if [[ "$next_char" != '"' && "$next_char" != $'\\' ]]; then
                            printf 'toml: %s:%d: unsupported string escape\\%s\n' "$file" "$lineno" "$next_char" >&2
                            TOML_DATA=()
                            return 1
                        fi
                        value+="$next_char"
                    elif [[ "$char" == '"' ]]; then
                        closed=1
                        tail="\${raw_value:i+1}"
                        tail="\${tail#"\${tail%%[![:space:]]*}"}"
                        if [[ -n "$tail" && "\${tail:0:1}" != '#' ]]; then
                            printf 'toml: %s:%d: unexpected text after quoted string\n' "$file" "$lineno" >&2
                            TOML_DATA=()
                            return 1
                        fi
                        break
                    else
                        value+="$char"
                    fi
                    ((i += 1))
                done
                if (( closed == 0 )); then
                    printf 'toml: %s:%d: unterminated quoted string\n' "$file" "$lineno" >&2
                    TOML_DATA=()
                    return 1
                fi
            elif [[ "$raw_value" =~ ^[+-]?(0|[1-9][0-9]*)$ || "$raw_value" == true || "$raw_value" == false ]]; then
                value="$raw_value"
            else
                printf 'toml: %s:%d: unsupported or invalid value for key %s\n' "$file" "$lineno" "$key" >&2
                TOML_DATA=()
                return 1
            fi

            if [[ -n "$table" ]]; then
                if [[ "$table_kind" == array ]]; then
                    full_key="${table}.${array_index}.${key}"
                else
                    full_key="${table}.${key}"
                fi
            else
                full_key="$key"
            fi

            if [[ -n "${TOML_DATA[$full_key]+present}" ]]; then
                printf 'toml: %s:%d: duplicate key %s\n' "$file" "$lineno" "$full_key" >&2
                TOML_DATA=()
                return 1
            fi
            TOML_DATA["$full_key"]="$value"
            continue
        fi

        printf 'toml: %s:%d: unsupported syntax: %s\n' "$file" "$lineno" "$line" >&2
        TOML_DATA=()
        return 1
    done < "$file"

    return 0
}
