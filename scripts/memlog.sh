#!/bin/bash
# logs peak used memory (MiB) inside the VM every 5s
P=0; while true; do U=$(free -m | awk '/Mem:/{print $3}'); [ $U -gt $P ] && P=$U; echo "$(date +%T) used=$U peak=$P" > /mnt/mac/Volumes/Data/lineage-build/mem_peak.txt; sleep 5; done
