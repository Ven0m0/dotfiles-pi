copy paste full nextcloud update:

```bash
sudo dietpi-update 1; topgrade -y -c; sudo -E -u www-data php /var/www/nextcloud/updater/updater.phar --no-interaction
```
