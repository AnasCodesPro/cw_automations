#!/usr/bin/env bash
set +e

services=("nginx" "varnish" "apache2" "php-fpm" "mysql" "memcached" "redis-server" "imunify360")

for s in "${services[@]}"; do
    [[ $s == "php-fpm" ]] && s=$(php -v | awk '{print "php"substr($2,1,3)"-fpm";exit}')
    [[ $s == "imunify360" ]] && s=$(systemctl list-unit-files | grep -q imunify360-agent && echo imunify360-agent || echo imunify360)

    if systemctl restart "$s" &>/dev/null; then
        echo "$(tput setaf 2)   |✓ $s restarted$(tput sgr0)"
    else
        echo "$(tput setaf 1)   |✗ $s failed$(tput sgr0)"
    fi
done

swapoff -a && swapon -a && \
    echo "$(tput setaf 2)   |✓ Swap cleared$(tput sgr0)" || \
    echo "$(tput setaf 1)   |✗ Swap clear failed$(tput sgr0)"

imunify360-agent config update '{"ENHANCED_DOS": {"default_limit": 50}, "MALWARE_SCAN_INTENSITY": {"cpu": 1}}' >/dev/null && \
imunify360-agent config show | jq '{
    ENHANCED_DOS: {
        default_limit: .ENHANCED_DOS.default_limit
    },
    MALWARE_SCAN_INTENSITY: {
        cpu: .MALWARE_SCAN_INTENSITY.cpu
    }
}'
