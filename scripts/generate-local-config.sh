#!/bin/sh
set -eu

env_file="${1:-.env}"
output_file="${2:-Config/Local.xcconfig}"

if [ ! -f "$env_file" ]; then
    echo "Missing $env_file. Copy .env.example to .env first." >&2
    exit 1
fi

mkdir -p "$(dirname "$output_file")"
: > "$output_file"

while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        ""|\#*) continue ;;
    esac

    line=${line#export }
    key=${line%%=*}
    value=${line#*=}

    case "$key" in
        VITALSCORE_DEVELOPMENT_TEAM|\
        VITALSCORE_BUNDLE_IDENTIFIER|\
        VITALSCORE_TEST_BUNDLE_IDENTIFIER|\
        VITALSCORE_CODE_SIGN_STYLE|\
        VITALSCORE_CODE_SIGN_IDENTITY|\
        VITALSCORE_PROVISIONING_PROFILE_SPECIFIER|\
        VITALSCORE_API_BASE_URL|\
        VITALSCORE_PRIVACY_POLICY_URL|\
        VITALSCORE_TERMS_URL)
            value=$(printf "%s" "$value" | sed 's#://#:/\$()/#g')
            printf "%s = %s\n" "$key" "$value" >> "$output_file"
            ;;
    esac
done < "$env_file"

echo "Wrote $output_file"
