# Galera-Cluster-Percona-Backup
Galera Cluster Percona Backup

* This is used to do a full backup & then incremental backups.

* /etc/crontab
* 15 1 * * 1-6 root /usr/sbin/galera_br.sh incremental
* 15 1 * * 7 root /usr/sbin/galera_br.sh full
