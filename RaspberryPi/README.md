copy paste full nextcloud update:

```bash
dietpi-update; topgrade -y -c; sudo -E -u www-data php /var/www/nextcloud/updater/updater.phar --no-interaction
```
