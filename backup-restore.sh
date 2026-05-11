#!/usr/bin/env bash
set -euo pipefail

backup_restore() {
    local app type input_date date backup_date_fmt dst newname newpath

    read -rp "Enter app name: " app
    read -rp "Choose type (full/db/files/file/dir): " type
    read -rp "Enter restore date (YYYY-MM-DD or human date e.g., 4 Aug 2025 08:51:12): " input_date

    date=$(date -d "$input_date" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || true)

    if [[ -z "$date" ]]; then
        echo "Invalid date format."
        exit 1
    fi

    backup_date_fmt=$(date -d "$input_date" +"%Y%m%d%H%M%S")
    dst="/home/master/applications/$app/tmp"
    newname="${type}_restore_${app}_${backup_date_fmt}"
    newpath="$dst/$newname"

    mkdir -p "$newpath"

    case "$type" in
        full)
            /var/cw/scripts/bash/duplicity_restore.sh \
                --src "$app" -r \
                --dst "$newpath" \
                --time "$date"
            ;;
        db)
            /var/cw/scripts/bash/duplicity_restore.sh \
                --src "$app" -d \
                --dst "$newpath" \
                --time "$date"
            ;;
        files)
            /var/cw/scripts/bash/duplicity_restore.sh \
                --src "$app" -w \
                --dst "$newpath" \
                --time "$date"
            ;;
        file)
            local file filename s3_url

            read -rp "Enter file path inside public_html (e.g., license.txt or wp-content/plugins/breeze/breeze.php): " file

            filename=$(basename "$file")

            source /root/.duplicity

            s3_url=$(awk -F'[="]' '/S3_url/ {print $3}' /root/.duplicity)

            duplicity restore \
                --no-encryption \
                --no-print-statistics \
                --s3-use-new-style \
                -v 4 \
                -t "$date" \
                --file-to-restore "public_html/$file" \
                "$s3_url/apps/$app" \
                "$newpath/$filename"
            ;;
        dir)
            local dir dirname_only s3_url

            read -rp "Enter directory path inside public_html (e.g., wp-includes or wp-content/plugins/breeze): " dir

            dirname_only=$(basename "$dir")

            mkdir -p "$newpath/$dirname_only"

            source /root/.duplicity

            s3_url=$(awk -F'[="]' '/S3_url/ {print $3}' /root/.duplicity)

            duplicity restore \
                --no-encryption \
                --no-print-statistics \
                --s3-use-new-style \
                -v 4 \
                -t "$date" \
                --file-to-restore "public_html/$dir" \
                "$s3_url/apps/$app" \
                "$newpath/$dirname_only"
            ;;
        *)
            echo "Invalid type selected."
            exit 1
            ;;
    esac

    echo "Restore complete: $newpath"
}

backup_restore "$@"
