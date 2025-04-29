#!/usr/bin/env bash
# 
# UNBAN v0.1
#
# Script assumes the following:
#   - bash 4+
#   - fail2ban
#   - crowdsec

set -e

# --- HARDCODE ---

MAX_JOBS=10
LOG_FILE="unban.log"


# --- COLORS ---

DGRY="\e[30m" # Dark Grey
DRED="\e[31m" # Dark Red
DGRN="\e[32m" # Dark Green
DYLW="\e[33m" # Dark Yellow
DBLU="\e[34m" # Dark Blue
DPRP="\e[35m" # Dark Purple
DCYN="\e[36m" # Dark Cyan
LGRY="\e[37m" # Light Grey
GRY="\e[90m"  # Grey
RED="\e[91m"  # Red
GRN="\e[92m"  # Green
YLW="\e[93m"  # Yellow
BLU="\e[94m"  # Blue
PRP="\e[95m"  # Purple
CYN="\e[96m"  # Cyan
WHT="\e[97m"  # White
NON="\e[0m"   # Reset


# --- SCRIPT FLAGS ---

VER=$(grep -E '^# *UNBAN' "$0" | sed -E 's/^# *UNBAN *//');
SCRIPTDIR=$(pwd);
DRY_RUN=false
FORCE=false


# --- COUNTERS ---

UNBANNED_COUNT=0
SKIPPED_COUNT=0


# --- INIT LOG FILE ---

: > "$LOG_FILE"


# --- COMMAND CHECK ---

for cmd in fail2ban-client cscli; do
    if ! command -v $cmd &> /dev/null; then
        printf "${RED}[ERROR]${NON} ${cmd} is not installed or not in PATH.\n"
        exit 1
    fi
done


# --- USAGE ---

usage() {
    printf "\n${DBLU}[USAGE]${NON}: $0 [--dry-run] [--force] [IP1 IP2 IP3] or $0 [--dry-run] [--force] [filename.txt]\n\n"
    exit 1
}

OPTIONS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true;                            shift   ;;
    -f|--force)   FORCE=true;                              shift   ;;
    -v|--version) printf "\n${BLU}UNBAN ${VER}${NON}\n\n";  exit 0 ;;
    -h|--help)    usage                                            ;;
    *)            OPTIONS+=("$1");                         shift   ;;
  esac
done


# --- TRAP ---

trap 'rm -f "$TMP_RESULTS" "$LOG_FILE"' EXIT


# --- SETUP IP LIST VAR ---

IP_LIST=()

if [ -f "${OPTIONS[0]}" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        IP_LIST+=("$line")
    done < "${OPTIONS[0]}"
else
    for arg in "${OPTIONS[@]}"; do
        IFS=',' read -ra ADDR <<< "$arg"
        for ip in "${ADDR[@]}"; do
            IP_LIST+=("$ip")
        done
    done
fi


# --- ABORT IF NO IP ARGUMENT GIVEN ---

if [ ${#IP_LIST[@]} -eq 0 ]; then
    printf "${RED}[ERROR]${NON}: No IPs provided. Nothing to do.\n"
    usage
fi


# --- EXPAND IPS ENDING IN A DOT (192.168.1.) ---

expand_trailing_dot() {
    local base="$1"
    local expanded=()
    for i in {0..255}; do
        expanded+=("${base}${i}")
    done
    echo "${expanded[@]}"
}


# --- EXPAND IPS WITH A GIVEN RANGE (192.168.1.10-20) ---

expand_manual_range() {
    local base="$1"
    local expanded=()
    local prefix=${base%-*}
    local start=${prefix##*.}
    local end=${base##*-}
    prefix=${prefix%.*}.

    for ((i=start; i<=end; i++)); do
        expanded+=("${prefix}${i}")
    done
    echo "${expanded[@]}"
}


# --- LIMIT CONCURRENT JOBS ---

wait_for_jobs() {
    while (( $(jobs -r | wc -l) >= MAX_JOBS )); do
        sleep 0.5
    done
}


# --- CONFIRMATION IF NOT A DRY-RUN OR FORCED ---

if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
    printf "${YLW}[WARNING]${NON}: You are about to unban and remove decisions for ${#IP_LIST[@]} addresses.\n"
    read -rp "Are you sure you want to continue? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        printf "${GRY}operation canceled${NON}\n"
        exit 0
    fi
    printf "\n"
fi


# --- PROCESS UNBAN ---

TMP_RESULTS=$(mktemp)
for ip in "${IP_LIST[@]}"; do
    if [ -z "$ip" ]; then
        continue
    fi

    EXPANDED_IPS=()
    if [[ "$ip" == *.*.*. ]]; then
        printf "${GRY}detected trailing dot, expanding...${NON}\n"
        EXPANDED_IPS=( $(expand_trailing_dot "$ip") )
    elif [[ "$ip" =~ -[0-9]+$ ]]; then
        printf "${GRY}detected ip range, expanding...${NON}\n"
        EXPANDED_IPS=( $(expand_manual_range "$ip") )
    else
        EXPANDED_IPS=("$ip")
    fi

    for expanded_ip in "${EXPANDED_IPS[@]}"; do
        wait_for_jobs
        {
            is_banned_f2b=false
            is_banned_crowdsec=false

            if [[ "$(fail2ban-client banned "$expanded_ip" 2>/dev/null)" != "[[]]" ]]; then
                is_banned_f2b=true
            fi
            if cscli decisions list -i "$expanded_ip" | grep -q "$expanded_ip"; then
                is_banned_crowdsec=true
            fi

            if [ "$is_banned_f2b" = true ] || [ "$is_banned_crowdsec" = true ]; then
                if [ "$DRY_RUN" = true ]; then
                    printf "${PRP}[DRY RUN UNBANNED]${NON}: $expanded_ip\n"
                    echo "DRY-RUN UNBANNED: $expanded_ip" >> "$LOG_FILE"
                    echo "unbanned" >> "$TMP_RESULTS"
                else
                    fail2ban-client unban "$expanded_ip" &> /dev/null
                    cscli decisions delete -i "$expanded_ip" &> /dev/null
                    printf "${GRN}[UNBANNED]${NON}: $expanded_ip is no long banned\n"
                    echo "UNBANNED: $expanded_ip" >> "$LOG_FILE"
                    echo "unbanned" >> "$TMP_RESULTS"
                fi
            else
                if [ "$DRY_RUN" = true ]; then
                    printf "${PRP}[DRY RUN SKIPPED]${NON}: $expanded_ip\n"
                    echo "DRY-RUN SKIPPED: $expanded_ip" >> "$LOG_FILE"
                    echo "skipped" >> "$TMP_RESULTS"
                else
                    printf "${DCYN}[SKIPPED]${NON}: $expanded_ip is not banned\n"
                    echo "SKIPPED: $expanded_ip" >> "$LOG_FILE"
                    echo "skipped" >> "$TMP_RESULTS"
                fi
            fi
        } &
    done
done

wait


# --- TALLY RESULTS ---

UNBANNED_COUNT=$(grep -c "^unbanned" "$TMP_RESULTS" || true)
SKIPPED_COUNT=$(grep -c "^skipped" "$TMP_RESULTS" || true)
rm -f "$TMP_RESULTS"


# --- FINISH ---

printf "\n${BLU}[SUMMARY]${NON}: Unbanned: ${YLW}${UNBANNED_COUNT}${NON}, Skipped: ${YLW}${SKIPPED_COUNT}${NON}\n"
printf "${GRY}[LOG FILE]${NON}: See $LOG_FILE for details.\n"
printf "${LGRY}[DONE]${NON}: All operations completed.\n\n"

exit 0